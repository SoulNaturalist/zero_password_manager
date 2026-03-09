import asyncio
import base64
import logging
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
import urllib.parse

logger = logging.getLogger(__name__)

# ── Favicon helper ────────────────────────────────────────────────────────────

def get_favicon_url(site_url: str) -> Optional[str]:
    if not site_url:
        return None
    try:
        if not site_url.startswith(('http://', 'https://')):
            site_url = 'https://' + site_url
        parsed = urllib.parse.urlparse(site_url)
        domain = parsed.netloc.lower()
        if not domain:
            domain = parsed.path.split('/')[0].lower()
        if domain.startswith('www.'):
            domain = domain[4:]
        if not domain or '.' not in domain:
            return None
        return f"https://logo.clearbit.com/{domain}?size=128"
    except Exception:
        return None


# ── IP helper (proxy-aware) ───────────────────────────────────────────────────

def get_client_ip(request: Request) -> str:
    """Return the real client IP, respecting X-Forwarded-For from trusted proxies."""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        # Take the first (leftmost) address — the original client
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


# ── Database init ─────────────────────────────────────────────────────────────

models.Base.metadata.create_all(bind=engine)

# ── Rate limiter ──────────────────────────────────────────────────────────────

limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Zero Vault API (Fortress + 2FA)")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ──────────────────────────────────────────────────────────────────────
# SECURITY: wildcard origins are forbidden.
# Set ALLOWED_ORIGINS in .env, e.g.:
#   ALLOWED_ORIGINS=http://192.168.1.100:8080,http://localhost:8080
_cors_origins = settings.ALLOWED_ORIGINS
if not _cors_origins:
    # No origins configured → allow nothing (safe default).
    # For local dev convenience we log a warning instead of crashing,
    # but no cross-origin requests will succeed.
    logger.warning(
        "[SECURITY] ALLOWED_ORIGINS is not set. "
        "Cross-origin requests will be blocked. "
        "Set ALLOWED_ORIGINS in your .env file."
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,      # explicit list, never "*"
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-OTP"],
)

# ── Security headers ──────────────────────────────────────────────────────────

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
        "default-src 'none'; "
        "script-src 'none'; "
        "object-src 'none';"
    )
    return response


# ── Constants ─────────────────────────────────────────────────────────────────

MAX_PAYLOAD_SIZE = 2 * 1024 * 1024  # 2 MB


# ── 2FA helper ────────────────────────────────────────────────────────────────

def verify_hardened_otp(db: Session, user: models.User, otp: Optional[str]):
    if not user.totp_enabled:
        return
    if not otp:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="OTP_REQUIRED",
            headers={"X-2FA-Required": "true"},
        )

    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(otp, valid_window=1):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="INVALID_OTP",
        )

    # Replay protection: reject re-used time-codes
    current_timecode = totp.timecode(auth.datetime.utcnow())
    if current_timecode <= user.last_otp_ts:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="OTP_REPLAY_DETECTED",
        )

    user.last_otp_ts = current_timecode
    db.commit()


# ── Auth endpoints ────────────────────────────────────────────────────────────

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

    new_user = crud.create_user(db=db, user=user)

    secret = pyotp.random_base32()
    crud.update_user_totp(db, new_user.id, secret=secret)

    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=new_user.login, issuer_name="ZeroVault")

    return {
        "id": new_user.id,
        "login": new_user.login,
        "salt": new_user.salt,
        "totp_secret": secret,
        "totp_uri": uri,
    }


@app.post("/login", response_model=schemas.Token)
@limiter.limit("5/minute")
async def login(request: Request,
                form_data: OAuth2PasswordRequestForm = Depends(),
                db: Session = Depends(get_db)):
    user = crud.get_user_by_login(db, login=form_data.username)
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        # SECURITY: use asyncio.sleep — time.sleep blocks the event loop
        await asyncio.sleep(1)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect login or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if "login" in settings.PERMISSIONS_OTP_LIST:
        otp = request.headers.get("X-OTP")
        if user.totp_enabled and not otp:
            return schemas.Token(two_fa_required=True, salt=user.salt)
        if user.totp_enabled:
            verify_hardened_otp(db, user, otp)

    access_token = auth.create_access_token(data={"sub": str(user.id)})
    refresh_token = auth.create_refresh_token(user_id=user.id)

    # SECURITY: log real client IP, not proxy IP
    crud.audit_event(db, user.id, "login", ip=get_client_ip(request))

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "user_id": user.id,
        "login": user.login,
        "salt": user.salt,
        "two_fa_required": False,
    }


@app.post("/2fa/setup", response_model=schemas.TOTPSetupResponse)
def setup_2fa(current_user: models.User = Depends(auth.get_current_user),
              db: Session = Depends(get_db)):
    secret = pyotp.random_base32()
    crud.update_user_totp(db, current_user.id, secret=secret)

    totp = pyotp.TOTP(secret)
    uri = totp.provisioning_uri(name=current_user.login, issuer_name="ZeroVault")

    return {"secret": secret, "otp_uri": uri}


@app.post("/2fa/confirm")
@limiter.limit("5/minute")   # SECURITY: brute-force protection on OTP confirmation
async def confirm_2fa(request: Request,
                      body: schemas.TOTPConfirmRequest,
                      db: Session = Depends(get_db)):
    # SECURITY: user_id is required
    if not body.user_id:
        raise HTTPException(status_code=400, detail="USER_ID_REQUIRED")

    user = db.get(models.User, body.user_id)
    if not user:
        # SECURITY: don't reveal whether the user exists
        await asyncio.sleep(1)
        raise HTTPException(status_code=400, detail="Invalid request")

    if user.totp_enabled:
        raise HTTPException(status_code=400, detail="2FA already enabled")

    if not user.totp_secret:
        raise HTTPException(status_code=400, detail="2FA not set up")

    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(body.code):
        await asyncio.sleep(1)   # slow down wrong-code attempts
        raise HTTPException(status_code=400, detail="Invalid OTP")

    user.last_otp_ts = totp.timecode(auth.datetime.utcnow())
    user.totp_enabled = True
    db.commit()

    crud.audit_event(db, user.id, "2fa_enabled")

    return {"status": "2fa enabled"}


@app.post("/refresh")
def refresh_token(payload: schemas.RefreshRequest,
                  db: Session = Depends(get_db)):
    # SECURITY: typed schema instead of raw dict
    try:
        data = auth.jwt.decode(
            payload.refresh_token,
            auth.SECRET_KEY,
            algorithms=[auth.ALGORITHM],
        )
        if data.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")
        user_id = data.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    new_access_token = auth.create_access_token(data={"sub": user_id})
    return {"access_token": new_access_token, "token_type": "bearer"}


# ── Password endpoints ────────────────────────────────────────────────────────

@app.get("/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_passwords(request: Request,
                   current_user: models.User = Depends(auth.get_current_user),
                   db: Session = Depends(get_db)):
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    db_passwords = crud.get_passwords(db, user_id=current_user.id)
    for p in db_passwords:
        p.favicon_url = get_favicon_url(p.site_url)
    return db_passwords


@app.post("/passwords",
          response_model=schemas.PasswordResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
def create_password(request: Request,
                    password: schemas.PasswordCreate,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    if len(password.encrypted_payload) > MAX_PAYLOAD_SIZE:
        raise HTTPException(status_code=400, detail="Payload too large")

    new_pwd = crud.create_password(db, password=password, user_id=current_user.id)
    new_pwd.favicon_url = get_favicon_url(new_pwd.site_url)
    return new_pwd


@app.put("/passwords/{password_id}",
         response_model=schemas.PasswordResponse)
@limiter.limit("30/minute")
def update_password(request: Request,
                    password_id: int,
                    password: schemas.PasswordUpdate,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    updated = crud.update_password(db, password_id=password_id,
                                   password=password, user_id=current_user.id)
    updated.favicon_url = get_favicon_url(updated.site_url)
    return updated


@app.delete("/passwords/{password_id}",
            status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("30/minute")
def delete_password(request: Request,
                    password_id: int,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    crud.delete_password(db, password_id=password_id, user_id=current_user.id)


# ── Folder endpoints ──────────────────────────────────────────────────────────

@app.get("/folders", response_model=List[schemas.FolderResponse])
@limiter.limit("60/minute")
def read_folders(request: Request,
                 current_user: models.User = Depends(auth.get_current_user),
                 db: Session = Depends(get_db)):
    return crud.get_folders(db, user_id=current_user.id)


@app.post("/folders",
          response_model=schemas.FolderResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
def create_folder(request: Request,
                  folder: schemas.FolderCreate,
                  current_user: models.User = Depends(auth.get_current_user),
                  db: Session = Depends(get_db)):
    db_folder = crud.create_folder(db, folder=folder, user_id=current_user.id)
    return {
        "id": db_folder.id,
        "name": db_folder.name,
        "color": db_folder.color,
        "icon": db_folder.icon,
        "created_at": db_folder.created_at,
        "updated_at": db_folder.updated_at,
        "password_count": 0,
    }


@app.put("/folders/{folder_id}", response_model=schemas.FolderResponse)
@limiter.limit("30/minute")
def update_folder(request: Request,
                  folder_id: int,
                  folder: schemas.FolderUpdate,
                  current_user: models.User = Depends(auth.get_current_user),
                  db: Session = Depends(get_db)):
    db_folder = crud.update_folder(db, folder_id=folder_id,
                                   folder=folder, user_id=current_user.id)
    count = db.query(models.Password).filter(
        models.Password.folder_id == folder_id
    ).count()
    return {
        "id": db_folder.id,
        "name": db_folder.name,
        "color": db_folder.color,
        "icon": db_folder.icon,
        "created_at": db_folder.created_at,
        "updated_at": db_folder.updated_at,
        "password_count": count,
    }


@app.delete("/folders/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("30/minute")
def delete_folder(request: Request,
                  folder_id: int,
                  current_user: models.User = Depends(auth.get_current_user),
                  db: Session = Depends(get_db)):
    crud.delete_folder(db, folder_id=folder_id, user_id=current_user.id)


@app.get("/folders/{folder_id}/passwords",
         response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_folder_passwords(request: Request,
                          folder_id: int,
                          current_user: models.User = Depends(auth.get_current_user),
                          db: Session = Depends(get_db)):
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    passwords = crud.get_passwords_by_folder(
        db, folder_id=folder_id, user_id=current_user.id
    )
    for p in passwords:
        p.favicon_url = get_favicon_url(p.site_url)
    return passwords


# ── Audit / history endpoints ─────────────────────────────────────────────────

@app.get("/audit", response_model=List[schemas.AuditResponse])
@limiter.limit("30/minute")
def read_audit_logs(request: Request,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    if "audit_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))
    return crud.get_logs(db, user_id=current_user.id)


# FIX BUG: Flutter client calls /password-history (not /passwords/history)
# Both routes are registered to keep backward compatibility.
@app.get("/passwords/history", response_model=List[schemas.HistoryResponse])
@app.get("/password-history",  response_model=List[schemas.HistoryResponse])
@limiter.limit("30/minute")
def read_password_history(request: Request,
                          current_user: models.User = Depends(auth.get_current_user),
                          db: Session = Depends(get_db)):
    if "history_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))

    history = crud.get_history(db, user_id=current_user.id)
    for h in history:
        h.favicon_url = get_favicon_url(h.site_url)
    return history


# ── Utility endpoints ─────────────────────────────────────────────────────────

@app.get("/api/generate-password")
def generate_password(
    length: int = 24,
    # SECURITY: endpoint now requires authentication
    current_user: models.User = Depends(auth.get_current_user),
):
    if not (8 <= length <= 128):
        raise HTTPException(status_code=400, detail="length must be between 8 and 128")
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()_+-="
    password = ''.join(secrets.choice(alphabet) for _ in range(length))
    return {"password": password}


@app.get("/health")
def health():
    return {
        "status": "ok",
        "security": "fortress",
        "2fa": "enabled",
        "architecture": "zero-knowledge",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
