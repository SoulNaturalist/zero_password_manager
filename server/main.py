import asyncio
import base64
import hmac
import secrets
import string
from typing import List, Optional
from datetime import datetime, timedelta, timezone

import pyotp
import webauthn
from webauthn.helpers.structs import (
    AuthenticatorSelectionCriteria,
    ResidentKeyRequirement,
    UserVerificationRequirement,
    RegistrationCredential,
    AuthenticationCredential,
)
from webauthn.helpers import (
    generate_registration_options,
    verify_registration_response,
    generate_authentication_options,
    verify_authentication_response,
    options_to_json,
)
import random
from fastapi import BackgroundTasks, Depends, FastAPI, Header, HTTPException, Request, status
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
import logging

# Centralized Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("zero_vault")

# Favicon Engine
_DNS_TIMEOUT_SECONDS = 2  # hard cap on DNS resolution time


def get_favicon_url(site_url: str) -> Optional[str]:
    if not site_url:
        return None
    try:
        # Clean URL and extract domain
        if not site_url.startswith(('http://', 'https://')):
            site_url = 'https://' + site_url
        parsed = urllib.parse.urlparse(site_url)
        domain = parsed.netloc.lower()
        if not domain:
            domain = parsed.path.split('/')[0].lower()

        # Remove 'www.'
        if domain.startswith('www.'):
            domain = domain[4:]

        if not domain or '.' not in domain:
            return None

        # SSRF Protection: Check that domain does not resolve to private/internal IP.
        # A 2-second timeout prevents DNS-based timing DoS where a slow resolver
        # would block the worker indefinitely.
        import socket
        import ipaddress
        try:
            old_timeout = socket.getdefaulttimeout()
            socket.setdefaulttimeout(_DNS_TIMEOUT_SECONDS)
            try:
                ip = socket.gethostbyname(domain)
            finally:
                socket.setdefaulttimeout(old_timeout)

            ip_obj = ipaddress.ip_address(ip)

            # Block RFC1918, loopback, link-local, and multicast ranges
            if (ip_obj.is_private or ip_obj.is_loopback
                    or ip_obj.is_link_local or ip_obj.is_multicast):
                logger.warning(f"SSRF blocked: {domain} resolved to private/reserved IP {ip}")
                return None
        except Exception as e:
            logger.error(f"DNS lookup failed for {domain}: {e}")
            return None

        return f"https://logo.clearbit.com/{domain}?size=128"
    except Exception:
        return None

def validate_base64(data: str) -> bool:
    if not data:
        return True
    try:
        base64.b64decode(data, validate=True)
        return True
    except Exception:
        return False


def _extract_webauthn_challenge(response: dict) -> Optional[str]:
    """Extract the challenge string from a WebAuthn credential response.

    The passkeys Flutter package does not add a top-level 'challenge' field;
    the challenge lives inside the base64url-encoded clientDataJSON.
    We decode it here so we can look it up in the challenges table.
    """
    try:
        import json as _json
        client_data_b64 = (
            response.get("response", {}).get("clientDataJSON") or
            response.get("clientDataJSON")
        )
        if not client_data_b64:
            return None
        # base64url → bytes (add padding if needed)
        padded = client_data_b64 + "=" * (-len(client_data_b64) % 4)
        client_data = _json.loads(base64.urlsafe_b64decode(padded))
        return client_data.get("challenge")
    except Exception as exc:
        logger.warning(f"Could not extract challenge from clientDataJSON: {exc}")
        return None


# Initialize database
models.Base.metadata.create_all(bind=engine)
# Apply column migrations for tables that already exist
models.run_migrations(engine)

# ── Startup security assertions ───────────────────────────────────────────────
# JWT_SECRET_KEY is validated inside Settings.__init__ — server will not start
# if the variable is absent.

if not settings.TELEGRAM_BOT_TOKEN:
    logger.warning("TELEGRAM_BOT_TOKEN not set. Security alerts via Telegram will be disabled.")

# WebAuthn: in production the relying-party origin MUST be HTTPS and MUST NOT
# be localhost. A misconfigured origin allows a phishing site to accept
# authenticator responses that were meant for the real server.
if settings.ENVIRONMENT == "production":
    if not settings.EXPECTED_ORIGIN.startswith("https://"):
        raise RuntimeError(
            f"EXPECTED_ORIGIN must use HTTPS in production (got: {settings.EXPECTED_ORIGIN!r})"
        )
    if "localhost" in settings.EXPECTED_ORIGIN or "127.0.0.1" in settings.EXPECTED_ORIGIN:
        raise RuntimeError(
            "EXPECTED_ORIGIN must not point to localhost in production. "
            f"Got: {settings.EXPECTED_ORIGIN!r}"
        )

# Setup Rate Limiter
limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Zero Vault API (Fortress + 2FA)")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS and Security Headers
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Strict-Transport-Security"] = (
        "max-age=63072000; includeSubDomains; preload"
    )
    # Prevent information leakage via Referer header
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # Restrict access to sensitive browser APIs
    response.headers["Permissions-Policy"] = (
        "camera=(), microphone=(), geolocation=(), payment=()"
    )
    # Content-Security-Policy — block XSS and unwanted resource loading
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' https://logo.clearbit.com data:; "
        "connect-src 'self'; "
        "frame-ancestors 'none'; "
        "base-uri 'self'; "
        "form-action 'self';"
    )
    # Remove potentially leaky headers added by underlying framework/server
    response.headers.pop("Server", None)
    response.headers.pop("X-Powered-By", None)
    return response


# Constants
MAX_PAYLOAD_SIZE = 2 * 1024 * 1024  # 2MB

# 2FA Helper with Timing-Safe Verification and Account Lockout
def verify_hardened_otp(db: Session, user: models.User, otp: Optional[str], background_tasks: BackgroundTasks = None):
    if not user.totp_enabled:
        return

    # Uniform error for missing vs invalid credentials/OTP to prevent enumeration
    common_error = HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Invalid credentials or OTP"
    )

    if not otp:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="OTP_REQUIRED",
            headers={"X-2FA-Required": "true"}
        )

    # Re-fetch user with row-level lock
    db_user = db.query(models.User).filter(models.User.id == user.id).with_for_update().first()
    if not db_user:
        raise common_error

    # Check for account lockout
    if db_user.lockout_until and db_user.lockout_until > datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account temporarily locked due to repeated failures"
        )

    totp = pyotp.TOTP(db_user.totp_secret)
    valid = False
    new_timecode = 0

    # Drift compensation: Check ±1 step (30 seconds)
    for offset in [-1, 0, 1]:
        check_time = datetime.now(timezone.utc) + timedelta(seconds=offset * 30)
        timecode = int(totp.timecode(check_time))
        
        # Timing-safe comparison using hmac.compare_digest
        # We verify if the provided OTP matches the TOTP for this time window
        if totp.verify(otp, for_time=check_time, valid_window=0):
            # Replay Protection: timecode must be strictly greater than last used
            if timecode > db_user.last_otp_ts:
                new_timecode = timecode
                valid = True
                break
    
    if not valid:
        # Increment failure counter
        db_user.failed_otp_attempts = (db_user.failed_otp_attempts or 0) + 1
        if db_user.failed_otp_attempts >= settings.MAX_FAILED_OTP_ATTEMPTS:
            db_user.lockout_until = datetime.now(timezone.utc) + timedelta(minutes=settings.LOCKOUT_TIME_MINUTES)
            crud.audit_event(db, db_user.id, "account_locked", {"reason": "too_many_otp_failures"}, background_tasks=background_tasks)
        
        db.commit()
        raise common_error
    
    # Success: Reset failure counters and update last used timecode
    db_user.last_otp_ts = new_timecode
    db_user.failed_otp_attempts = 0
    db_user.lockout_until = None
    db.commit()


@app.post("/register",
          response_model=schemas.UserResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("3/minute")
async def register(request: Request,
                   user: schemas.UserCreate,
                   background_tasks: BackgroundTasks,
                   db: Session = Depends(get_db)):
    # Timing Attack Mitigation (non-blocking)
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # User Enumeration & Policy Protection: Generic responses
    db_user = crud.get_user_by_login(db, login=user.login)
    if db_user:
        raise HTTPException(status_code=400, detail="Ошибка регистрации")
    
    # Create user (crud.create_user already validates password but we standardize error here)
    try:
        new_user = crud.create_user(db=db, user=user, background_tasks=background_tasks)
    except HTTPException as e:
        if e.status_code == 400:
             raise HTTPException(status_code=400, detail="Ошибка регистрации")
        raise e
    
    # Generate 2FA Secret for binding during registration
    secret = pyotp.random_base32()
    crud.update_user_totp(db, new_user.id, secret=secret)
    
    crud.audit_event(db, new_user.id, "user_registered", ip=request.client.host, background_tasks=background_tasks)

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
async def login(request: Request,
          background_tasks: BackgroundTasks,
          form_data: OAuth2PasswordRequestForm = Depends(),
          db: Session = Depends(get_db)):
    # Timing Attack Mitigation
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # Uniform error for all login/2FA failures
    common_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid credentials or OTP",
        headers={"WWW-Authenticate": "Bearer"},
    )

    user = db.query(models.User).filter(models.User.login == form_data.username).with_for_update().first()

    if not user:
        # Non-blocking delay to prevent user-enumeration timing attacks
        await asyncio.sleep(random.uniform(0.1, 0.3))
        crud.audit_event(db, None, "login_failed", {"login": form_data.username, "reason": "user_not_found"}, ip=request.client.host, background_tasks=background_tasks)
        raise common_error

    # Check for account lockout
    if user.lockout_until and user.lockout_until > datetime.now(timezone.utc):
        crud.audit_event(db, user.id, "login_failed", {"reason": "account_locked"}, ip=request.client.host, background_tasks=background_tasks)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account temporarily locked due to repeated failures"
        )

    # Track attempt
    user.last_login_attempt = datetime.now(timezone.utc)

    # Password check
    if not auth.verify_password(form_data.password, user.hashed_password):
        # Increment failure counter
        user.failed_otp_attempts = (user.failed_otp_attempts or 0) + 1
        if user.failed_otp_attempts >= settings.MAX_FAILED_OTP_ATTEMPTS:
            user.lockout_until = datetime.now(timezone.utc) + timedelta(minutes=settings.LOCKOUT_TIME_MINUTES)
            crud.audit_event(db, user.id, "account_locked", {"reason": "too_many_login_failures"}, background_tasks=background_tasks)
        
        db.commit()
        await asyncio.sleep(random.uniform(0.1, 0.3))
        crud.audit_event(db, user.id, "login_failed", {"reason": "invalid_password"}, ip=request.client.host, background_tasks=background_tasks)
        raise common_error

    # Check if login requires OTP in config
    if "login" in settings.PERMISSIONS_OTP_LIST:
        otp = request.headers.get("X-OTP")
        if user.totp_enabled and not otp:
            crud.audit_event(db, user.id, "login_2fa_required", ip=request.client.host, background_tasks=background_tasks)
            return schemas.Token(two_fa_required=True, salt=user.salt)

        if user.totp_enabled:
            # Re-verify logic inside already handles lockout/failures for OTP
            verify_hardened_otp(db, user, otp, background_tasks=background_tasks)

    access_token = auth.create_access_token(data={"sub": str(user.id)})
    refresh_token = auth.create_refresh_token(user_id=user.id)

    # Success: Reset failure counters
    user.failed_otp_attempts = 0
    user.lockout_until = None
    db.commit()

    crud.audit_event(db, user.id, "login", ip=request.client.host, background_tasks=background_tasks)

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
    uri = totp.provisioning_uri(name=current_user.login, issuer_name="ZeroVault")
    return {"secret": secret, "otp_uri": uri}

@app.post("/2fa/confirm")
@limiter.limit("5/minute")
async def confirm_2fa(
    request: Request,
    request_data: schemas.TOTPConfirmRequest,
    background_tasks: BackgroundTasks,
    # IDOR fix: require JWT auth — endpoint always acts on the authenticated
    # user, making it impossible to enable 2FA for an arbitrary user_id.
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    if current_user.totp_enabled:
        raise HTTPException(status_code=400, detail="2FA already enabled")
    if not current_user.totp_secret:
        raise HTTPException(status_code=400, detail="2FA not set up")

    totp = pyotp.TOTP(current_user.totp_secret)

    # Replay-protection: reject a code from a window that was already used
    current_timecode = int(totp.timecode(datetime.now(timezone.utc)))
    if current_timecode <= current_user.last_otp_ts:
        await asyncio.sleep(1)
        raise HTTPException(status_code=400, detail="OTP already used")

    if not totp.verify(request_data.code, valid_window=1):
        await asyncio.sleep(1)
        crud.audit_event(db, current_user.id, "2fa_confirm_failed",
                         {"reason": "invalid_otp"}, ip=request.client.host,
                         background_tasks=background_tasks)
        raise HTTPException(status_code=400, detail="Invalid OTP")

    current_user.last_otp_ts = current_timecode
    current_user.totp_enabled = True
    db.commit()

    crud.audit_event(db, current_user.id, "2fa_enabled",
                     ip=request.client.host, background_tasks=background_tasks)
    return {"status": "2fa enabled"}


@app.get("/profile", response_model=schemas.ProfileResponse)
def get_profile(current_user: models.User = Depends(auth.get_current_user)):
    """Get current user profile info."""
    return current_user


@app.post("/profile/update", response_model=schemas.ProfileResponse)
def update_profile(request: Request,
                   background_tasks: BackgroundTasks,
                   user_update: schemas.ProfileUpdate,
                   current_user: models.User = Depends(auth.get_current_user),
                   db: Session = Depends(get_db)):
    """Update profile settings like Telegram Chat ID. Requires TOTP if enabled."""
    
    # Security: Require TOTP if enabled
    if current_user.totp_enabled:
        otp_code = user_update.totp_code or request.headers.get("X-OTP")
        verify_hardened_otp(db, current_user, otp_code, background_tasks=background_tasks)

    if user_update.telegram_chat_id is not None:
        current_user.telegram_chat_id = user_update.telegram_chat_id
    
    # Also support password change if provided
    if user_update.password:
        if not crud.validate_password_strength(user_update.password):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Password too weak. Minimum 14 characters, including uppercase, lowercase, digits, and special symbols."
            )
        current_user.hashed_password = auth.get_password_hash(user_update.password)
        
    db.commit()
    db.refresh(current_user)
    crud.audit_event(db, current_user.id, "profile_updated", background_tasks=background_tasks)
    return current_user


@app.post("/refresh")
@limiter.limit("5/minute")
def refresh_token(
    request: Request,
    payload: schemas.RefreshRequest,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    try:
        # decode_token uses PyJWT with algorithms=["HS256"] — no algorithm confusion
        data = auth.decode_token(payload.refresh_token)
    except Exception:
        crud.audit_event(db, None, "refresh_token_failed", {"reason": "invalid_token"},
                         ip=request.client.host, background_tasks=background_tasks)
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    if data.get("type") != "refresh":
        crud.audit_event(db, data.get("sub"), "refresh_token_failed",
                         {"reason": "invalid_token_type"},
                         ip=request.client.host, background_tasks=background_tasks)
        raise HTTPException(status_code=401, detail="Invalid token type")

    # Reject refresh tokens that were explicitly revoked (e.g. after logout).
    jti = data.get("jti")
    if jti and crud.is_token_blacklisted(db, jti):
        crud.audit_event(db, data.get("sub"), "refresh_token_failed",
                         {"reason": "token_revoked"},
                         ip=request.client.host, background_tasks=background_tasks)
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    user_id = data.get("sub")
    new_access_token = auth.create_access_token(data={"sub": user_id})
    crud.audit_event(db, user_id, "token_refreshed", ip=request.client.host,
                     background_tasks=background_tasks)
    return {"access_token": new_access_token, "token_type": "bearer"}


@app.get("/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_passwords(request: Request,
                   current_user: models.User = Depends(auth.get_current_user),
                   db: Session = Depends(get_db),
                   background_tasks: BackgroundTasks = BackgroundTasks()):
    # OTP-Gated if configured
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    
    db_passwords = crud.get_passwords(db, user_id=current_user.id)
    
    # Favicon URLs are now handled client-side in Zero-Knowledge mode 
    # or via site_url if it still exists (legacy support)
    for p in db_passwords:
        if p.site_url:
            p.favicon_url = get_favicon_url(p.site_url)
        
    crud.audit_event(db, current_user.id, "passwords_read", ip=request.client.host, background_tasks=background_tasks)
    return db_passwords


@app.post("/passwords",
          response_model=schemas.PasswordResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
def create_password(request: Request,
                    password: schemas.PasswordCreate,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    if len(password.encrypted_payload) > MAX_PAYLOAD_SIZE:
        crud.audit_event(db, current_user.id, "password_create_failed", {"reason": "payload_too_large"}, ip=request.client.host, background_tasks=background_tasks)
        raise HTTPException(status_code=400, detail="Payload too large")

    # Enforce storage quota
    pwd_count = db.query(models.Password).filter(models.Password.user_id == current_user.id).count()
    if pwd_count >= settings.MAX_PASSWORDS_PER_USER:
        raise HTTPException(status_code=400, detail="Maximum number of passwords reached")

    if not validate_base64(password.encrypted_payload):
        raise HTTPException(status_code=400, detail="Invalid encrypted payload (not base64)")
    
    if password.notes_encrypted and not validate_base64(password.notes_encrypted):
        raise HTTPException(status_code=400, detail="Invalid notes payload (not base64)")

    new_pwd = crud.create_password(db, password=password, user_id=current_user.id)
    if new_pwd.site_url:
        new_pwd.favicon_url = get_favicon_url(new_pwd.site_url)
    return new_pwd


@app.put("/passwords/{password_id}",
         response_model=schemas.PasswordResponse)
@limiter.limit("30/minute")
def update_password(request: Request,
                    password_id: int,
                    password: schemas.PasswordUpdate,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    if not validate_base64(password.encrypted_payload):
        raise HTTPException(status_code=400, detail="Invalid encrypted payload (not base64)")
    
    if password.notes_encrypted and not validate_base64(password.notes_encrypted):
        raise HTTPException(status_code=400, detail="Invalid notes payload (not base64)")

    updated = crud.update_password(db, password_id=password_id, password=password, user_id=current_user.id)
    if updated.site_url:
        updated.favicon_url = get_favicon_url(updated.site_url)
    return updated


@app.delete("/passwords/{password_id}")
@limiter.limit("30/minute")
def delete_password(request: Request,
                    password_id: int,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    crud.delete_password(db, password_id=password_id, user_id=current_user.id, background_tasks=background_tasks)
    return {"status": "deleted"}


# ── Folder Endpoints ──────────────────────────────────────────────────────────

@app.get("/folders", response_model=List[schemas.FolderResponse])
def read_folders(current_user: models.User = Depends(auth.get_current_user),
                 db: Session = Depends(get_db)):
    return crud.get_folders(db, user_id=current_user.id)


@app.post("/folders", response_model=schemas.FolderResponse)
def create_folder(request: Request,
                  folder: schemas.FolderCreate,
                  background_tasks: BackgroundTasks,
                  current_user: models.User = Depends(auth.get_current_user),
                  db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    return crud.create_folder(db=db, folder=folder, user_id=current_user.id, background_tasks=background_tasks)


@app.put("/folders/{folder_id}", response_model=schemas.FolderResponse)
def update_folder(folder_id: int,
                  folder: schemas.FolderUpdate,
                  current_user: models.User = Depends(auth.get_current_user),
                  db: Session = Depends(get_db)):
    db_folder = crud.update_folder(db, folder_id=folder_id, folder=folder, user_id=current_user.id)
    count = db.query(models.Password).filter(models.Password.folder_id == folder_id).count()
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
def delete_folder(folder_id: int,
                  current_user: models.User = Depends(auth.get_current_user),
                  db: Session = Depends(get_db)):
    crud.delete_folder(db, folder_id=folder_id, user_id=current_user.id)


@app.get("/folders/{folder_id}/passwords", response_model=List[schemas.PasswordResponse])
def read_passwords_by_folder(request: Request,
                             folder_id: int,
                             background_tasks: BackgroundTasks,
                             current_user: models.User = Depends(auth.get_current_user),
                             db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    passwords = crud.get_passwords_by_folder(db, folder_id=folder_id, user_id=current_user.id)
    for p in passwords:
        if p.site_url:
            p.favicon_url = get_favicon_url(p.site_url)
    return passwords


@app.get("/audit", response_model=List[schemas.AuditResponse])
def read_audit_logs(request: Request,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "audit_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    return crud.get_logs(db, user_id=current_user.id)


@app.get("/passwords/history", response_model=List[schemas.HistoryResponse])
def read_password_history(request: Request,
                          background_tasks: BackgroundTasks,
                          current_user: models.User = Depends(auth.get_current_user),
                          db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "history_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
        
    history = crud.get_history(db, user_id=current_user.id)
    
    # Inject favicon URLs for legacy data
    for h in history:
        if h.site_url:
            h.favicon_url = get_favicon_url(h.site_url)
        
    return history


_MIN_GEN_LENGTH = 8
_MAX_GEN_LENGTH = 256


@app.get("/api/generate-password")
@limiter.limit("10/minute")
def generate_password(request: Request, length: int = 24):
    # Clamp to safe range to prevent CPU/memory exhaustion (DoS).
    length = max(_MIN_GEN_LENGTH, min(length, _MAX_GEN_LENGTH))
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()_+-="
    password = "".join(secrets.choice(alphabet) for _ in range(length))
    return {"password": password}



# ── WebAuthn Endpoints ────────────────────────────────────────────────────────

@app.post("/webauthn/register/options")
@limiter.limit("5/minute")
async def webauthn_register_options(
    request: Request,
    options_data: schemas.WebAuthnOptionsRequest,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db)
):
    options = generate_registration_options(
        rp_id=settings.RP_ID,
        rp_name=settings.RP_NAME,
        user_id=str(current_user.id),
        user_name=current_user.login,
        authenticator_selection=AuthenticatorSelectionCriteria(
            resident_key=ResidentKeyRequirement.REQUIRED,
            user_verification=UserVerificationRequirement.REQUIRED,
        ),
    )
    
    # Store challenge
    challenge_str = options.challenge.decode("utf-8") if isinstance(options.challenge, bytes) else options.challenge
    crud.create_challenge(db, current_user.id, challenge_str, "registration")
    
    from fastapi.responses import JSONResponse
    return JSONResponse(content=options_to_json(options))


@app.post("/webauthn/register/verify")
@limiter.limit("5/minute")
async def webauthn_register_verify(
    request: Request,
    verify_data: schemas.WebAuthnRegistrationVerify,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    challenge_key = (
        verify_data.registration_response.get("challenge")
        or _extract_webauthn_challenge(verify_data.registration_response)
    )
    challenge_data = crud.get_challenge(db, challenge_key)
    if not challenge_data or challenge_data.type != "registration":
        raise HTTPException(status_code=400, detail="Invalid challenge")
    
    if challenge_data.expires_at < datetime.now(timezone.utc):
        crud.delete_challenge(db, challenge_data.challenge)
        raise HTTPException(status_code=400, detail="Challenge expired")
    
    try:
        verification = verify_registration_response(
            credential=verify_data.registration_response,
            expected_challenge=challenge_data.challenge.encode("utf-8"),
            expected_origin=settings.EXPECTED_ORIGIN,
            expected_rp_id=settings.RP_ID,
            require_user_verification=True,
        )
        
        # Store credential
        crud.create_webauthn_credential(
            db,
            user_id=current_user.id,
            credential_id=verification.credential_id,
            public_key=verification.public_key,
            sign_count=verification.sign_count,
            transports=verify_data.registration_response.get("response", {}).get("transports")
        )
        
        # Tracking device
        crud.upsert_user_device(db, current_user.id, verify_data.device_id, verify_data.device_name)
        
        # Delete challenge
        crud.delete_challenge(db, challenge_data.challenge)
        
        crud.audit_event(db, current_user.id, "passkey_registered", {"device_id": verify_data.device_id}, background_tasks=background_tasks)
        
        return {"status": "success"}
    except Exception as e:
        # Sanitize error message and log internally
        logger.error(f"WebAuthn Register Error: {str(e)}")
        # Standardized error message
        raise HTTPException(status_code=400, detail="Registration verification failed")


@app.post("/webauthn/login/options")
@limiter.limit("10/minute")
async def webauthn_login_options(
    request: Request,
    db: Session = Depends(get_db)
):
    options = generate_authentication_options(
        rp_id=settings.RP_ID,
        user_verification=UserVerificationRequirement.REQUIRED,
    )
    
    # Store challenge
    challenge_str = options.challenge.decode("utf-8") if isinstance(options.challenge, bytes) else options.challenge
    crud.create_challenge(db, None, challenge_str, "authentication")
    
    from fastapi.responses import JSONResponse
    return JSONResponse(content=options_to_json(options))


@app.post("/webauthn/login/verify")
@limiter.limit("10/minute")
async def webauthn_login_verify(
    request: Request,
    verify_data: schemas.WebAuthnLoginVerify,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    common_error = HTTPException(status_code=400, detail="Authentication failed")

    challenge_key = (
        verify_data.authentication_response.get("challenge")
        or _extract_webauthn_challenge(verify_data.authentication_response)
    )
    challenge_data = crud.get_challenge(db, challenge_key)
    if not challenge_data or challenge_data.type != "authentication":
        raise common_error
    
    if challenge_data.expires_at < datetime.now(timezone.utc):
        crud.delete_challenge(db, challenge_data.challenge)
        raise common_error
    
    credential_id = verify_data.authentication_response.get("id")
    db_credential = crud.get_webauthn_credential_by_id(db, credential_id)
    
    if not db_credential:
        # Non-blocking delay to prevent credential-enumeration timing attacks
        await asyncio.sleep(random.uniform(0.1, 0.3))
        raise common_error

    user = db.query(models.User).filter(models.User.id == db_credential.user_id).first()
    if user and user.lockout_until and user.lockout_until > datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account temporarily locked due to repeated failures"
        )
    
    try:
        verification = verify_authentication_response(
            credential=verify_data.authentication_response,
            expected_challenge=challenge_data.challenge.encode("utf-8"),
            expected_origin=settings.EXPECTED_ORIGIN,
            expected_rp_id=settings.RP_ID,
            credential_public_key=db_credential.public_key,
            credential_current_sign_count=db_credential.sign_count,
            require_user_verification=True,
        )
        
        # Security check: sign_count must increase
        if verification.new_sign_count <= db_credential.sign_count:
             raise HTTPException(status_code=403, detail="Possible clone attack (sign count drift)")
        
        # Update sign count
        crud.update_webauthn_sign_count(db, credential_id, verification.new_sign_count)
        
        # Tracking device
        user = db.query(models.User).filter(models.User.id == db_credential.user_id).first()
        crud.upsert_user_device(db, user.id, verify_data.device_id, verify_data.device_name)
        
        # Success: Reset failure counters
        user.failed_otp_attempts = 0
        user.lockout_until = None
        db.commit()

        # Issue tokens (sub must be stringified user.id for auth.get_current_user)
        access_token = auth.create_access_token(data={"sub": str(user.id)})
        refresh_token = auth.create_refresh_token(user_id=user.id)
        
        # Delete challenge
        crud.delete_challenge(db, challenge_data.challenge)
        
        crud.audit_event(db, user.id, "passkey_login_success", {"device_id": verify_data.device_id}, background_tasks=background_tasks)
        
        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "user_id": user.id,
            "login": user.login,
            "salt": user.salt
        }
    except Exception as e:
        crud.audit_event(db, db_credential.user_id if db_credential else None, "passkey_login_failed", {"error": "Authentication failed"}, background_tasks=background_tasks)
        logger.error(f"WebAuthn Login Error: {str(e)}")
        raise common_error


@app.get("/webauthn/devices", response_model=List[schemas.DeviceResponse])
async def list_devices(
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db)
):
    return crud.get_user_devices(db, current_user.id)


@app.delete("/webauthn/devices/{device_id}")
async def revoke_device_endpoint(
    device_id: int,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db)
):
    crud.revoke_device(db, device_id, current_user.id)
    crud.audit_event(db, current_user.id, "device_revoked", {"internal_device_id": device_id}, background_tasks=background_tasks)
    return {"status": "success"}


@app.post("/logout")
@limiter.limit("10/minute")
async def logout(
    request: Request,
    background_tasks: BackgroundTasks,
    body: Optional[schemas.LogoutRequest] = None,
    current_user: models.User = Depends(auth.get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke the current access token and, if provided, the refresh token.

    Both token JTIs are added to the blacklist so they are rejected even before
    their exp timestamps.  Clients should pass their refresh_token in the body
    to ensure full session invalidation.
    """
    # Blacklist access token
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    try:
        payload = auth.decode_token(token)
        jti = payload.get("jti")
        if jti:
            exp_ts = payload.get("exp")
            expires_at = (
                datetime.fromtimestamp(exp_ts, tz=timezone.utc)
                if exp_ts
                else datetime.now(timezone.utc)
            )
            crud.blacklist_token(db, jti, expires_at)
    except Exception:
        # Token was already invalid; still return 200 so the client can clean up
        pass

    # Also blacklist the refresh token if the client sent it.
    # This closes the window where a stolen refresh token could be used
    # after the user explicitly logs out.
    if body and body.refresh_token:
        try:
            rt_payload = auth.decode_token(body.refresh_token)
            if rt_payload.get("type") == "refresh":
                rt_jti = rt_payload.get("jti")
                if rt_jti:
                    rt_exp_ts = rt_payload.get("exp")
                    rt_expires_at = (
                        datetime.fromtimestamp(rt_exp_ts, tz=timezone.utc)
                        if rt_exp_ts
                        else datetime.now(timezone.utc)
                    )
                    crud.blacklist_token(db, rt_jti, rt_expires_at)
        except Exception:
            pass  # Invalid refresh token — nothing to revoke

    crud.audit_event(
        db, current_user.id, "logout",
        ip=request.client.host,
        background_tasks=background_tasks,
    )
    return {"status": "logged out"}


@app.get("/health")
def health():
    """Minimal health check to avoid information disclosure."""
    return {"status": "ok"}


# ── Background scheduler ──────────────────────────────────────────────────────

async def _emergency_approval_loop():
    """Process auto-approvals every hour."""
    while True:
        await asyncio.sleep(3600)
        try:
            db_gen = get_db()
            db = next(db_gen)
            try:
                crud.process_emergency_approvals(db)
            finally:
                try:
                    next(db_gen)
                except StopIteration:
                    pass
        except Exception as exc:
            logger.error(f"Emergency approval loop error: {exc}")


@app.on_event("startup")
async def start_scheduler():
    asyncio.create_task(_emergency_approval_loop())


# ── Password Rotation Endpoints ───────────────────────────────────────────────

@app.put("/passwords/{password_id}/rotation", response_model=schemas.PasswordResponse)
@limiter.limit("30/minute")
def configure_rotation(request: Request,
                       password_id: int,
                       config: schemas.RotationConfig,
                       background_tasks: BackgroundTasks,
                       current_user: models.User = Depends(auth.get_current_user),
                       db: Session = Depends(get_db)):
    """Enable / disable automatic rotation for a stored password."""
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"),
                            background_tasks=background_tasks)
    updated = crud.set_rotation_config(
        db, password_id, current_user.id,
        config.rotation_enabled, config.rotation_interval_days,
    )
    return updated


@app.post("/passwords/{password_id}/rotate", response_model=schemas.PasswordResponse)
@limiter.limit("30/minute")
def rotate_password(request: Request,
                    password_id: int,
                    payload: schemas.RotationUpdate,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth.get_current_user),
                    db: Session = Depends(get_db)):
    """Client submits the freshly generated, re-encrypted password after rotation."""
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"),
                            background_tasks=background_tasks)
    if not validate_base64(payload.encrypted_payload):
        raise HTTPException(status_code=400, detail="Invalid encrypted payload (not base64)")
    updated = crud.record_rotation(
        db, password_id, current_user.id,
        payload.encrypted_payload,
        payload.notes_encrypted,
        payload.encrypted_metadata,
        background_tasks=background_tasks,
    )
    return updated


@app.get("/passwords/rotation-due", response_model=List[schemas.RotationDueItem])
@limiter.limit("30/minute")
def get_rotation_due(request: Request,
                     current_user: models.User = Depends(auth.get_current_user),
                     db: Session = Depends(get_db)):
    """Return passwords whose rotation interval has elapsed."""
    return crud.get_passwords_due_for_rotation(db, current_user.id)


# ── Secure Sharing Endpoints ──────────────────────────────────────────────────

@app.post("/share", response_model=schemas.ShareResponse, status_code=status.HTTP_201_CREATED)
@limiter.limit("20/minute")
def create_share(request: Request,
                 share: schemas.ShareCreate,
                 background_tasks: BackgroundTasks,
                 current_user: models.User = Depends(auth.get_current_user),
                 db: Session = Depends(get_db)):
    """Share an encrypted password with another user.

    The client must re-encrypt the password payload specifically for the
    recipient before sending it — the server never sees plaintext.
    """
    if not validate_base64(share.encrypted_payload):
        raise HTTPException(status_code=400, detail="Invalid encrypted payload (not base64)")
    return crud.create_share(db, current_user.id, share, background_tasks=background_tasks)


@app.get("/share/incoming", response_model=List[schemas.ShareResponse])
def get_incoming_shares(current_user: models.User = Depends(auth.get_current_user),
                        db: Session = Depends(get_db)):
    """List shares sent to the current user."""
    return crud.get_shares_incoming(db, current_user.id)


@app.get("/share/outgoing", response_model=List[schemas.ShareResponse])
def get_outgoing_shares(current_user: models.User = Depends(auth.get_current_user),
                        db: Session = Depends(get_db)):
    """List shares created by the current user."""
    return crud.get_shares_outgoing(db, current_user.id)


@app.get("/share/{share_id}", response_model=schemas.ShareDetailResponse)
def get_share(share_id: int,
              background_tasks: BackgroundTasks,
              current_user: models.User = Depends(auth.get_current_user),
              db: Session = Depends(get_db)):
    """Retrieve full share data (including encrypted payload) — recipient only."""
    share = crud.get_share_detail(db, share_id, current_user.id)
    crud.audit_event(db, current_user.id, "share_viewed", {"share_id": share_id},
                     background_tasks=background_tasks)
    return share


@app.post("/share/{share_id}/accept", response_model=schemas.ShareResponse)
def accept_share(share_id: int,
                 background_tasks: BackgroundTasks,
                 current_user: models.User = Depends(auth.get_current_user),
                 db: Session = Depends(get_db)):
    """Recipient accepts a pending share."""
    return crud.accept_share(db, share_id, current_user.id,
                             background_tasks=background_tasks)


@app.delete("/share/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_share(share_id: int,
                 background_tasks: BackgroundTasks,
                 current_user: models.User = Depends(auth.get_current_user),
                 db: Session = Depends(get_db)):
    """Owner revokes a share."""
    crud.revoke_share(db, share_id, current_user.id,
                      background_tasks=background_tasks)


# ── Emergency Access Endpoints ────────────────────────────────────────────────

@app.post("/emergency-access", response_model=schemas.EmergencyAccessResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
def invite_emergency_contact(request: Request,
                              invite: schemas.EmergencyInvite,
                              background_tasks: BackgroundTasks,
                              current_user: models.User = Depends(auth.get_current_user),
                              db: Session = Depends(get_db)):
    """Grantor invites a trusted person as emergency contact."""
    ea = crud.create_emergency_access(db, current_user.id, invite,
                                      background_tasks=background_tasks)
    return _ea_response(ea, db)


@app.get("/emergency-access", response_model=List[schemas.EmergencyAccessResponse])
def list_emergency_contacts(current_user: models.User = Depends(auth.get_current_user),
                             db: Session = Depends(get_db)):
    """List all emergency access entries for the current user (as grantor or grantee)."""
    entries = crud.list_emergency_access(db, current_user.id)
    return [_ea_response(ea, db) for ea in entries]


@app.post("/emergency-access/{ea_id}/accept", response_model=schemas.EmergencyAccessResponse)
def accept_emergency(ea_id: int,
                     background_tasks: BackgroundTasks,
                     current_user: models.User = Depends(auth.get_current_user),
                     db: Session = Depends(get_db)):
    """Grantee accepts an invitation."""
    ea = crud.accept_emergency_invite(db, ea_id, current_user.id,
                                      background_tasks=background_tasks)
    return _ea_response(ea, db)


@app.post("/emergency-access/{ea_id}/request-access", response_model=schemas.EmergencyAccessResponse)
def request_emergency(ea_id: int,
                      background_tasks: BackgroundTasks,
                      current_user: models.User = Depends(auth.get_current_user),
                      db: Session = Depends(get_db)):
    """Grantee triggers the emergency access timer."""
    ea = crud.request_emergency_access(db, ea_id, current_user.id,
                                       background_tasks=background_tasks)
    return _ea_response(ea, db)


@app.post("/emergency-access/{ea_id}/checkin", response_model=schemas.EmergencyAccessResponse)
def checkin_emergency(ea_id: int,
                      background_tasks: BackgroundTasks,
                      current_user: models.User = Depends(auth.get_current_user),
                      db: Session = Depends(get_db)):
    """Grantor confirms they are alive — resets the approval timer."""
    ea = crud.checkin_emergency_access(db, ea_id, current_user.id,
                                       background_tasks=background_tasks)
    return _ea_response(ea, db)


@app.post("/emergency-access/{ea_id}/deny", status_code=status.HTTP_204_NO_CONTENT)
def deny_emergency(ea_id: int,
                   background_tasks: BackgroundTasks,
                   current_user: models.User = Depends(auth.get_current_user),
                   db: Session = Depends(get_db)):
    """Grantor explicitly denies the pending emergency request."""
    crud.deny_emergency_access(db, ea_id, current_user.id,
                                background_tasks=background_tasks)


@app.delete("/emergency-access/{ea_id}", status_code=status.HTTP_204_NO_CONTENT)
def revoke_emergency(ea_id: int,
                     background_tasks: BackgroundTasks,
                     current_user: models.User = Depends(auth.get_current_user),
                     db: Session = Depends(get_db)):
    """Grantor revokes an emergency access grant."""
    crud.revoke_emergency_access(db, ea_id, current_user.id,
                                  background_tasks=background_tasks)


@app.post("/emergency-access/{ea_id}/vault", response_model=schemas.EmergencyAccessResponse)
def upload_emergency_vault(ea_id: int,
                            body: schemas.EmergencyVaultUpload,
                            background_tasks: BackgroundTasks,
                            current_user: models.User = Depends(auth.get_current_user),
                            db: Session = Depends(get_db)):
    """Grantor pre-uploads an encrypted vault snapshot for the grantee to use in emergency."""
    if not validate_base64(body.encrypted_vault):
        raise HTTPException(status_code=400, detail="Invalid encrypted vault (not base64)")
    ea = crud.upload_emergency_vault(db, ea_id, current_user.id, body.encrypted_vault,
                                      background_tasks=background_tasks)
    return _ea_response(ea, db)


@app.get("/emergency-access/{ea_id}/vault", response_model=schemas.EmergencyVaultResponse)
def get_emergency_vault(ea_id: int,
                         background_tasks: BackgroundTasks,
                         current_user: models.User = Depends(auth.get_current_user),
                         db: Session = Depends(get_db)):
    """Grantee retrieves the encrypted vault after access has been approved."""
    ea = crud.get_emergency_vault(db, ea_id, current_user.id)
    crud.audit_event(db, current_user.id, "emergency_vault_accessed",
                     {"ea_id": ea_id, "grantor_id": ea.grantor_id},
                     background_tasks=background_tasks)
    return {"encrypted_vault": ea.encrypted_vault}


def _ea_response(ea: models.EmergencyAccess, db: Session) -> dict:
    """Build EmergencyAccessResponse enriched with login names."""
    grantor = db.query(models.User).filter(models.User.id == ea.grantor_id).first()
    grantee = db.query(models.User).filter(models.User.id == ea.grantee_id).first()
    return {
        "id": ea.id,
        "grantor_id": ea.grantor_id,
        "grantee_id": ea.grantee_id,
        "grantor_login": grantor.login if grantor else None,
        "grantee_login": grantee.login if grantee else None,
        "status": ea.status,
        "wait_days": ea.wait_days,
        "last_checkin_at": ea.last_checkin_at,
        "requested_at": ea.requested_at,
        "approved_at": ea.approved_at,
        "created_at": ea.created_at,
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
