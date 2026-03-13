import asyncio
from datetime import datetime

import pyotp
from fastapi import APIRouter, Depends, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from ..audit.service import record as audit
from ..database import get_db
from ..models import User
from ..utils import get_client_ip
from .dependencies import get_current_user
from .exceptions import (
    InvalidOTPCode,
    InvalidRefreshToken,
    TwoFAAlreadyEnabled,
    TwoFANotSetUp,
    UserAlreadyExists,
)
from .schemas import (
    LoginRequest,
    RefreshRequest,
    TOTPConfirmRequest,
    TOTPSetupResponse,
    Token,
    UserCreate,
    UserResponse,
)
from .service import (
    create_access_token,
    create_refresh_token,
    create_user,
    decode_token,
    get_user_by_login,
    update_user_totp,
    verify_hardened_otp,
    verify_password,
    hash_password,
)
from ..config import settings
from ..security import SecurityManager
from ..schemas import PasswordResetRequest

router = APIRouter(tags=["auth"])
limiter = Limiter(key_func=get_remote_address)


@router.post("/register", response_model=UserResponse, status_code=201)
@limiter.limit("3/minute")
def register(
    request: Request,
    body: UserCreate,
    db: Session = Depends(get_db),
):
    if get_user_by_login(db, login=body.login):
        raise UserAlreadyExists()

    new_user = create_user(db, data=body)

    secret = pyotp.random_base32()
    update_user_totp(db, new_user.id, secret=secret)
    totp_uri = pyotp.TOTP(secret).provisioning_uri(
        name=new_user.login, issuer_name="ZeroVault"
    )

    audit(db, new_user.id, "register")

    return UserResponse(
        id=new_user.id,
        login=new_user.login,
        salt=new_user.salt,
        totp_secret=secret,
        totp_uri=totp_uri,
    )


@router.post("/login", response_model=Token)
@limiter.limit("5/minute")
async def login(
    request: Request,
    body: LoginRequest,
    db: Session = Depends(get_db),
):
    user = get_user_by_login(db, login=body.login)

    if not user or not verify_password(body.password, user.hashed_password):
        await asyncio.sleep(1)  # async sleep — does not block the event loop
        from .exceptions import InvalidCredentials
        raise InvalidCredentials()

    if "login" in settings.PERMISSIONS_OTP_LIST and user.totp_enabled:
        otp = request.headers.get("X-OTP")
        if not otp:
            return Token(two_fa_required=True, salt=user.salt)
        verify_hardened_otp(db, user, otp)

    audit(db, user.id, "login", ip=get_client_ip(request))

    return Token(
        access_token=create_access_token({"sub": str(user.id)}),
        refresh_token=create_refresh_token(user.id),
        user_id=user.id,
        login=user.login,
        salt=user.salt,
    )


@router.post("/setup_2fa", response_model=TOTPSetupResponse)
def setup_2fa(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    secret = pyotp.random_base32()
    update_user_totp(db, current_user.id, secret=secret)
    otp_uri = pyotp.TOTP(secret).provisioning_uri(
        name=current_user.login, issuer_name="ZeroVault"
    )
    return TOTPSetupResponse(secret=secret, otp_uri=otp_uri)


@router.post("/confirm_2fa", response_model=Token)
@limiter.limit("5/minute")
async def confirm_2fa(
    request: Request,
    body: TOTPConfirmRequest,
    db: Session = Depends(get_db),
):
    user = db.get(User, body.user_id)
    if not user:
        await asyncio.sleep(1)
        from .exceptions import InvalidCredentials
        raise InvalidCredentials()

    if user.totp_enabled:
        raise TwoFAAlreadyEnabled()
    if not user.totp_secret:
        raise TwoFANotSetUp()

    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(body.code):
        await asyncio.sleep(1)
        raise InvalidOTPCode()

    user.last_otp_ts = totp.timecode(datetime.utcnow())
    user.totp_enabled = True
    db.commit()

    audit(db, user.id, "2fa_enabled")
    
    return Token(
        access_token=create_access_token({"sub": str(user.id)}),
        refresh_token=create_refresh_token(user.id),
        user_id=user.id,
        login=user.login,
        salt=user.salt,
    )


@router.post("/refresh")
def refresh_token(
    body: RefreshRequest,
):
    data = decode_token(body.refresh_token)
    if data.get("type") != "refresh":
        raise InvalidRefreshToken()

    user_id = data.get("sub")
    if not user_id:
        raise InvalidRefreshToken()

    return {
        "access_token": create_access_token({"sub": user_id}),
        "token_type": "bearer",
    }


@router.post("/reset-password")
@limiter.limit("5/10minutes")
async def reset_password(
    request: Request,
    body: PasswordResetRequest,
    db: Session = Depends(get_db),
):
    # Constant-time delay baseline
    SecurityManager.constant_time_delay()

    user = get_user_by_login(db, login=body.login)
    
    # Generic error message to prevent enumeration
    generic_error = HTTPException(
        status_code=400,
        detail="Invalid login or TOTP code"
    )

    if not user:
        raise generic_error

    # Check progressive lockout
    if SecurityManager.is_locked_out(user):
        raise HTTPException(
            status_code=403,
            detail="Too many failed attempts. Please try again later."
        )

    try:
        # Verify TOTP
        verify_hardened_otp(db, user, body.totp_code)
        
        # Success: Update password and reset failures
        user.hashed_password = hash_password(body.new_password)
        SecurityManager.handle_success(db, user)
        
        # Security: Invalidate existing sessions (we'd need a blacklist or versioning for better enforcement)
        # For now, we clear the salt or rotate a transient version if we had one.
        
        audit(db, user.id, "password_reset_success", ip=get_client_ip(request))
        return {"success": True}
        
    except (InvalidOTPCode, OTPInvalid, OTPReplay, OTPRequired) as e:
        SecurityManager.handle_failure(db, user)
        audit(db, user.id, "password_reset_failed", ip=get_client_ip(request))
        raise generic_error


@router.post("/verify-totp", response_model=dict)
@limiter.limit("5/minute")
async def verify_totp_for_seed(
    request: Request,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Verify TOTP to get a short-lived token for sensitive resource access (e.g., Seed Phrase)."""
    otp = request.headers.get("X-OTP")
    if not otp:
        raise OTPRequired()

    verify_hardened_otp(db, current_user, otp)

    # Issue a very short-lived token with specific scope
    seed_access_token = create_access_token({
        "sub": str(current_user.id),
        "scope": "seed_access",
        "iat": datetime.utcnow()
    })
    
    # Note: create_access_token in service currently uses settings.ACCESS_TOKEN_EXPIRE_MINUTES
    # Ideally, we'd want this to be 1 min.
    
    return {"seed_access_token": seed_access_token}
