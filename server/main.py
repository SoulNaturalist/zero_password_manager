import asyncio
import logging
import secrets
import string
import urllib.parse
from datetime import datetime
from typing import Callable, List, Optional

import pyotp
from fastapi import Depends, FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from . import auth, crud, models, schemas
from .config import settings
from .database import engine, get_db

logger = logging.getLogger(__name__)

# ── Database init ─────────────────────────────────────────────────────────────

models.Base.metadata.create_all(bind=engine)

# ── App + rate limiter ────────────────────────────────────────────────────────

limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Zero Vault API")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── CORS ──────────────────────────────────────────────────────────────────────
# Wildcard origins are forbidden. Set ALLOWED_ORIGINS in .env.

if not settings.ALLOWED_ORIGINS:
    logger.warning(
        "[SECURITY] ALLOWED_ORIGINS is not set — cross-origin requests will be blocked. "
        "Set ALLOWED_ORIGINS=http://your-host in .env."
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-OTP"],
)

# ── Security headers ──────────────────────────────────────────────────────────

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Frame-Options"]           = "DENY"
    response.headers["X-Content-Type-Options"]    = "nosniff"
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    response.headers["Referrer-Policy"]           = "no-referrer"
    response.headers["Permissions-Policy"]        = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"]   = (
        "default-src 'none'; script-src 'none'; object-src 'none';"
    )
    return response


# ── Constants ─────────────────────────────────────────────────────────────────

MAX_PAYLOAD_BYTES = 2 * 1024 * 1024  # 2 MB


# ── Utility functions ─────────────────────────────────────────────────────────

def get_client_ip(request: Request) -> str:
    """Return the real client IP, respecting X-Forwarded-For from trusted proxies."""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def get_favicon_url(site_url: Optional[str]) -> Optional[str]:
    """Return a Clearbit logo URL for a site, or None if the URL is unusable."""
    if not site_url:
        return None
    try:
        if not site_url.startswith(("http://", "https://")):
            site_url = "https://" + site_url
        parsed = urllib.parse.urlparse(site_url)
        domain = parsed.netloc.lower() or parsed.path.split("/")[0].lower()
        domain = domain.removeprefix("www.")
        if not domain or "." not in domain:
            return None
        return f"https://logo.clearbit.com/{domain}?size=128"
    except Exception:
        return None


def _attach_favicons(entries) -> None:
    """Set the transient favicon_url attribute on a list of password-like objects."""
    for entry in entries:
        entry.favicon_url = get_favicon_url(entry.site_url)


# ── Dependency factory ────────────────────────────────────────────────────────

def require_otp_for(permission: str) -> Callable:
    """
    FastAPI dependency factory.

    Returns a dependency that authenticates the user and, when *permission*
    is listed in PERMISSIONS_OTP_LIST, also validates the X-OTP header.

    Usage:
        current_user: models.User = Depends(require_otp_for("vault_read"))
    """
    def guard(
        request: Request,
        current_user: models.User = Depends(auth.get_current_user),
        db: Session = Depends(get_db),
    ) -> models.User:
        if permission in settings.PERMISSIONS_OTP_LIST:
            auth.verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))
        return current_user

    return guard


# ── Auth endpoints ────────────────────────────────────────────────────────────

@app.post("/register", response_model=schemas.UserResponse, status_code=201)
@limiter.limit("3/minute")
def register(
    request: Request,
    body: schemas.UserCreate,
    db: Session = Depends(get_db),
):
    if crud.get_user_by_login(db, login=body.login):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Login already registered")

    new_user = crud.create_user(db, user=body)

    secret = pyotp.random_base32()
    crud.update_user_totp(db, new_user.id, secret=secret)

    totp_uri = pyotp.TOTP(secret).provisioning_uri(name=new_user.login, issuer_name="ZeroVault")

    return schemas.UserResponse(
        id=new_user.id,
        login=new_user.login,
        salt=new_user.salt,
        totp_secret=secret,
        totp_uri=totp_uri,
    )


@app.post("/login", response_model=schemas.Token)
@limiter.limit("5/minute")
async def login(
    request: Request,
    body: schemas.LoginRequest,
    db: Session = Depends(get_db),
):
    user = crud.get_user_by_login(db, login=body.login)

    if not user or not auth.verify_password(body.password, user.hashed_password):
        await asyncio.sleep(1)  # slow down brute-force; use async to avoid blocking the loop
        raise HTTPException(
            status.HTTP_401_UNAUTHORIZED,
            "Incorrect login or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if "login" in settings.PERMISSIONS_OTP_LIST and user.totp_enabled:
        otp = request.headers.get("X-OTP")
        if not otp:
            return schemas.Token(two_fa_required=True, salt=user.salt)
        auth.verify_hardened_otp(db, user, otp)

    crud.audit_event(db, user.id, "login", ip=get_client_ip(request))

    return schemas.Token(
        access_token=auth.create_access_token({"sub": str(user.id)}),
        refresh_token=auth.create_refresh_token(user.id),
        token_type="bearer",
        user_id=user.id,
        login=user.login,
        salt=user.salt,
        two_fa_required=False,
    )


@app.post("/2fa/setup", response_model=schemas.TOTPSetupResponse)
def setup_2fa(
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    secret = pyotp.random_base32()
    crud.update_user_totp(db, current_user.id, secret=secret)
    otp_uri = pyotp.TOTP(secret).provisioning_uri(name=current_user.login, issuer_name="ZeroVault")
    return schemas.TOTPSetupResponse(secret=secret, otp_uri=otp_uri)


@app.post("/2fa/confirm")
@limiter.limit("5/minute")
async def confirm_2fa(
    request: Request,
    body: schemas.TOTPConfirmRequest,
    db: Session = Depends(get_db),
):
    if not body.user_id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "USER_ID_REQUIRED")

    user = db.get(models.User, body.user_id)
    if not user:
        await asyncio.sleep(1)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid request")

    if user.totp_enabled:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "2FA already enabled")
    if not user.totp_secret:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "2FA not set up")

    totp = pyotp.TOTP(user.totp_secret)
    if not totp.verify(body.code):
        await asyncio.sleep(1)
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Invalid OTP")

    user.last_otp_ts = totp.timecode(datetime.utcnow())
    user.totp_enabled = True
    db.commit()

    crud.audit_event(db, user.id, "2fa_enabled")
    return {"status": "2fa enabled"}


@app.post("/refresh")
def refresh_token(
    payload: schemas.RefreshRequest,
    db: Session = Depends(get_db),
):
    data = auth.decode_token(payload.refresh_token)
    if data.get("type") != "refresh":
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token type")

    user_id = data.get("sub")
    if not user_id:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token")

    return {"access_token": auth.create_access_token({"sub": user_id}), "token_type": "bearer"}


# ── Password endpoints ────────────────────────────────────────────────────────

@app.get("/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_passwords(
    request: Request,
    current_user: models.User = Depends(require_otp_for("vault_read")),
    db: Session = Depends(get_db),
):
    passwords = crud.get_passwords(db, user_id=current_user.id)
    _attach_favicons(passwords)
    return passwords


@app.post("/passwords", response_model=schemas.PasswordResponse, status_code=201)
@limiter.limit("30/minute")
def create_password(
    request: Request,
    body: schemas.PasswordCreate,
    current_user: models.User = Depends(require_otp_for("vault_write")),
    db: Session = Depends(get_db),
):
    if len(body.encrypted_payload) > MAX_PAYLOAD_BYTES:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Payload too large")

    new_pwd = crud.create_password(db, password=body, user_id=current_user.id)
    new_pwd.favicon_url = get_favicon_url(new_pwd.site_url)
    return new_pwd


@app.put("/passwords/{password_id}", response_model=schemas.PasswordResponse)
@limiter.limit("30/minute")
def update_password(
    request: Request,
    password_id: int,
    body: schemas.PasswordUpdate,
    current_user: models.User = Depends(require_otp_for("vault_write")),
    db: Session = Depends(get_db),
):
    updated = crud.update_password(db, password_id=password_id, password=body, user_id=current_user.id)
    updated.favicon_url = get_favicon_url(updated.site_url)
    return updated


@app.delete("/passwords/{password_id}", status_code=204)
@limiter.limit("30/minute")
def delete_password(
    request: Request,
    password_id: int,
    current_user: models.User = Depends(require_otp_for("vault_write")),
    db: Session = Depends(get_db),
):
    crud.delete_password(db, password_id=password_id, user_id=current_user.id)


# ── Folder endpoints ──────────────────────────────────────────────────────────

@app.get("/folders", response_model=List[schemas.FolderResponse])
@limiter.limit("60/minute")
def read_folders(
    request: Request,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    return crud.get_folders(db, user_id=current_user.id)


@app.post("/folders", response_model=schemas.FolderResponse, status_code=201)
@limiter.limit("30/minute")
def create_folder(
    request: Request,
    body: schemas.FolderCreate,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    return crud.create_folder(db, folder=body, user_id=current_user.id)


@app.put("/folders/{folder_id}", response_model=schemas.FolderResponse)
@limiter.limit("30/minute")
def update_folder(
    request: Request,
    folder_id: int,
    body: schemas.FolderUpdate,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    return crud.update_folder(db, folder_id=folder_id, folder=body, user_id=current_user.id)


@app.delete("/folders/{folder_id}", status_code=204)
@limiter.limit("30/minute")
def delete_folder(
    request: Request,
    folder_id: int,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    crud.delete_folder(db, folder_id=folder_id, user_id=current_user.id)


@app.get("/folders/{folder_id}/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_folder_passwords(
    request: Request,
    folder_id: int,
    current_user: models.User = Depends(require_otp_for("vault_read")),
    db: Session = Depends(get_db),
):
    passwords = crud.get_passwords_by_folder(db, folder_id=folder_id, user_id=current_user.id)
    _attach_favicons(passwords)
    return passwords


# ── Audit / history endpoints ─────────────────────────────────────────────────

@app.get("/audit", response_model=List[schemas.AuditResponse])
@limiter.limit("30/minute")
def read_audit_logs(
    request: Request,
    current_user: models.User = Depends(require_otp_for("audit_read")),
    db: Session = Depends(get_db),
):
    return crud.get_audit_logs(db, user_id=current_user.id)


# Both routes serve the same handler — /password-history kept for Flutter client compat.
@app.get("/passwords/history", response_model=List[schemas.HistoryResponse])
@app.get("/password-history",  response_model=List[schemas.HistoryResponse])
@limiter.limit("30/minute")
def read_password_history(
    request: Request,
    current_user: models.User = Depends(require_otp_for("history_read")),
    db: Session = Depends(get_db),
):
    history = crud.get_history(db, user_id=current_user.id)
    _attach_favicons(history)
    return history


# ── Utility endpoints ─────────────────────────────────────────────────────────

@app.get("/api/generate-password")
def generate_password(
    length: int = 24,
    current_user: models.User = Depends(auth.get_current_user),
):
    if not (8 <= length <= 128):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "length must be between 8 and 128")
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()_+-="
    return {"password": "".join(secrets.choice(alphabet) for _ in range(length))}


@app.get("/health")
def health():
    return {"status": "ok", "architecture": "zero-knowledge", "2fa": "enabled"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
