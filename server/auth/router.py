import asyncio
from datetime import datetime, timezone

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
)
from ..config import settings

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


@router.post("/2fa/setup", response_model=TOTPSetupResponse)
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


@router.post("/2fa/confirm")
@limiter.limit("5/minute")
async def confirm_2fa(
    request: Request,
    body: TOTPConfirmRequest,
    # IDOR fix: the caller must be the authenticated owner of the account.
    # Previously any unauthenticated request could pass an arbitrary user_id
    # and attempt to enable 2FA on someone else's account.
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.totp_enabled:
        raise TwoFAAlreadyEnabled()
    if not current_user.totp_secret:
        raise TwoFANotSetUp()

    totp = pyotp.TOTP(current_user.totp_secret)

    # Replay-protection: reject a code from a window already used.
    current_timecode = totp.timecode(datetime.now(timezone.utc))
    if current_timecode <= current_user.last_otp_ts:
        await asyncio.sleep(1)
        raise InvalidOTPCode()

    if not totp.verify(body.code, valid_window=1):
        await asyncio.sleep(1)
        raise InvalidOTPCode()

    # Lock in the timecode immediately so the same code cannot be reused.
    current_user.last_otp_ts = current_timecode
    current_user.totp_enabled = True
    db.commit()

    audit(db, current_user.id, "2fa_enabled")
    return {"status": "2fa enabled"}


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
