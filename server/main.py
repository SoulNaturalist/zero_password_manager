import base64
import secrets
import string
import time
from typing import List, Optional

import pyotp
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from . import auth, crud, models, schemas
from .config import settings
from .database import engine, get_db


# Initialize database
models.Base.metadata.create_all(bind=engine)

# Setup Rate Limiter
limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Zero Vault API (Fortress + 2FA)")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS and Security Headers
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Strict-Transport-Security"] = (
        "max-age=63072000; includeSubDomains"
    )
    return response


# Constants
MAX_PAYLOAD_SIZE = 2 * 1024 * 1024  # 2MB


# 2FA Helper with Replay Protection
def verify_hardened_otp(db: Session, user: models.User, otp: Optional[str]):
    if not user.totp_enabled:
        return
    if not otp:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="OTP_REQUIRED",
            headers={"X-2FA-Required": "true"}
        )

    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(otp, valid_window=1):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="INVALID_OTP"
        )

    # Replay Protection: Check if this timecode was already used
    current_timecode = totp.timecode(auth.datetime.utcnow())
    if current_timecode <= user.last_otp_ts:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="OTP_REPLAY_DETECTED"
        )

    # Update last used timecode
    user.last_otp_ts = current_timecode
    db.commit()


@app.post("/register",
          response_model=schemas.UserResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("3/minute")
def register(request: Request,
             user: schemas.UserCreate,
             db: Session = Depends(get_db)):
    db_user = crud.get_user_by_login(db, login=user.login)
    if db_user:
        raise HTTPException(status_code=400, detail="Login already registered")
    
    # Create user
    new_user = crud.create_user(db=db, user=user)
    
    # Generate 2FA Secret for binding during registration
    secret = pyotp.random_base32()
    crud.update_user_totp(db, new_user.id, secret=secret)
    
    # Return user data + 2FA setup info
    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=new_user.login, issuer_name="ZeroVault")
    
    # We return the UserResponse which we need to extend with setup info
    return {
        "id": new_user.id,
        "login": new_user.login,
        "salt": new_user.salt,
        "totp_secret": secret,
        "totp_uri": uri
    }


@app.post("/login", response_model=schemas.Token)
@limiter.limit("5/minute")
def login(request: Request,
          form_data: OAuth2PasswordRequestForm = Depends(),
          db: Session = Depends(get_db)):
    user = crud.get_user_by_login(db, login=form_data.username)
    if not user or not auth.verify_password(form_data.password,
                                           user.hashed_password):
        time.sleep(1)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect login or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Check if login requires OTP in config
    if "login" in settings.PERMISSIONS_OTP_LIST:
        # If 2FA is enabled, check if OTP is provided in a custom header
        otp = request.headers.get("X-OTP")
        if user.totp_enabled and not otp:
            return schemas.Token(two_fa_required=True, salt=user.salt)

        if user.totp_enabled:
            verify_hardened_otp(db, user, otp)

    access_token = auth.create_access_token(data={"sub": str(user.id)})
    refresh_token = auth.create_refresh_token(user_id=user.id)

    crud.audit_event(db, user.id, "login", ip=request.client.host)

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user_id": user.id,
        "login": user.login,
        "salt": user.salt,
        "two_fa_required": False
    }


@app.post("/2fa/setup", response_model=schemas.TOTPSetupResponse)
def setup_2fa(current_user: models.User = Depends(auth.get_current_user),
              db: Session = Depends(get_db)):
    secret = pyotp.random_base32()
    crud.update_user_totp(db, current_user.id, secret=secret)

    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=current_user.login,
                               issuer_name="ZeroVault")

    return {"secret": secret, "otp_uri": uri}


@app.post("/2fa/confirm")
def confirm_2fa(request: schemas.TOTPConfirmRequest,
                db: Session = Depends(get_db)):
    # If we have user_id in request, use it (for registration flow)
    # Otherwise try to get from current_user (for logged in users)
    # For security, we should verify the user actually exists and hasn't enabled 2FA yet
    
    if not request.user_id:
         raise HTTPException(status_code=400, detail="USER_ID_REQUIRED")

    user = db.query(models.User).get(request.user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
        
    if user.totp_enabled:
        raise HTTPException(status_code=400, detail="2FA already enabled")

    if not user.totp_secret:
        raise HTTPException(status_code=400, detail="2FA not set up")

    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(request.code):
        raise HTTPException(status_code=400, detail="Invalid OTP")

    # Set initial timecode to prevent immediate reuse of setup code
    user.last_otp_ts = totp.timecode(auth.datetime.utcnow())
    user.totp_enabled = True
    db.commit()

    crud.audit_event(db, user.id, "2fa_enabled")

    return {"status": "2fa enabled"}


@app.post("/refresh")
def refresh_token(payload: dict, db: Session = Depends(get_db)):
    token = payload.get("refresh_token")
    if not token:
        raise HTTPException(status_code=400, detail="Refresh token missing")

    try:
        data = auth.jwt.decode(token, auth.SECRET_KEY,
                              algorithms=[auth.ALGORITHM])
        if data.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = data.get("sub")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    new_access_token = auth.create_access_token(data={"sub": user_id})
    return {"access_token": new_access_token, "token_type": "bearer"}


@app.get("/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_passwords(request: Request,
                   current_user: models.User = Depends(auth.get_current_user),
                   db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))
    return crud.get_passwords(db, user_id=current_user.id)


@app.post("/passwords",
          response_model=schemas.PasswordResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
def create_password(request: Request,
                    password: schemas.PasswordCreate,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    if len(password.encrypted_payload) > MAX_PAYLOAD_SIZE:
        raise HTTPException(status_code=400, detail="Payload too large")

    return crud.create_password(db, password=password, user_id=current_user.id)


@app.get("/audit", response_model=List[schemas.AuditResponse])
def read_audit_logs(request: Request,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "audit_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))
    return crud.get_logs(db, user_id=current_user.id)


@app.get("/api/generate-password")
def generate_password(length: int = 24):
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()_+-="
    password = ''.join(secrets.choice(alphabet) for i in range(length))
    return {"password": password}


@app.get("/health")
def health():
    return {
        "status": "ok",
        "security": "fortress",
        "2fa": "enabled",
        "architecture": "zero-knowledge"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
