import base64
import secrets
import string
import time
import hmac
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
from webauthn import (
    generate_registration_options,
    verify_registration_response,
    generate_authentication_options,
    verify_authentication_response,
    options_to_json,
)
import random
import asyncio
from fastapi import Depends, FastAPI, Header, HTTPException, Request, status, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordRequestForm
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from . import models, schemas, crud
from .auth import service as auth_service, dependencies as auth_deps
from .exceptions import AppException, app_exception_handler
from .auth.router import router as auth_router
from .auth.service import verify_hardened_otp
from .config import settings
from .database import engine, get_db
import logging
from .utils import get_favicon_url, EncryptionService
from .auth.dependencies import get_current_user, get_seed_access_user
from .middleware import SecurityMiddleware, ProxyHeadersMiddleware

# Centralized Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("zero_vault")

def validate_base64(data: str) -> bool:
    if not data:
        return True
    try:
        base64.b64decode(data, validate=True)
        return True
    except Exception:
        return False


# Initialize database
models.Base.metadata.create_all(bind=engine)

# Apply schema migrations (add columns introduced after initial deployment)
from .database import run_migrations
run_migrations(engine)


# Setup Rate Limiter
limiter = Limiter(key_func=get_remote_address)
app = FastAPI(title="Zero Vault API (Fortress + 2FA)")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_exception_handler(AppException, app_exception_handler)

# CORS and Security Hardening
# In production, restrict to actual domain
cors_origins = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]
if settings.ENVIRONMENT == "production":
    # Replace with your actual production domain
    cors_origins = [settings.EXPECTED_ORIGIN]

app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-OTP", "X-Requested-With"],
    expose_headers=["X-Total-Count"],
)

# Security Middleware (Should be early)
app.add_middleware(ProxyHeadersMiddleware)
app.add_middleware(SecurityMiddleware)

app.include_router(auth_router)  # Compatibility with legacy/root routes
app.include_router(auth_router, prefix="/api/v1")


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    """Injects high-security HTTP headers for protection against XSS, Clickjacking, and Sniffing."""
    response = await call_next(request)
    
    # HSTS: Strict Transport Security (Force HTTPS) - 1 year
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload"
    
    # CSP: Content Security Policy
    # default-src 'self' prevents loading resources from other domains
    # img-src 'self' data: allows local images and base64 (favicons)
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self' 'unsafe-inline'; "
        "img-src 'self' data: https://www.google.com; "
        "connect-src 'self'; "
        "frame-ancestors 'none'; "
        "object-src 'none'"
    )
    
    # Prevent Content-Type Sniffing
    response.headers["X-Content-Type-Options"] = "nosniff"
    
    # Clickjacking Protection
    response.headers["X-Frame-Options"] = "DENY"
    
    # XSS Protection (Traditional but still useful as defense-in-depth)
    response.headers["X-XSS-Protection"] = "1; mode=block"
    
    # Referrer Policy
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    
    return response


# Constants
MAX_PAYLOAD_SIZE = 2 * 1024 * 1024  # 2MB

from fastapi import WebSocket, WebSocketDisconnect

class ConnectionManager:
    def __init__(self):
        # user_id -> list of websockets to support multiple devices/tabs
        self.active_connections: dict[int, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, user_id: int):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)
        logger.info(f"WS: User {user_id} connected. Total active sessions for user: {len(self.active_connections[user_id])}")

    def disconnect(self, websocket: WebSocket, user_id: int):
        if user_id in self.active_connections:
            if websocket in self.active_connections[user_id]:
                self.active_connections[user_id].remove(websocket)
                logger.info(f"WS: User {user_id} session closed. Remaining sessions: {len(self.active_connections[user_id])}")
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]

    async def send_personal_message(self, message: dict, user_id: int):
        connections = self.active_connections.get(user_id, [])
        for websocket in connections:
            try:
                await websocket.send_json(message)
            except Exception as e:
                logger.error(f"WS: Failed to send message to user {user_id}: {str(e)}")

manager = ConnectionManager()

@app.websocket("/ws/device-events")
async def websocket_device_events(websocket: WebSocket, token: Optional[str] = None):
    client_host = websocket.client.host if websocket.client else "unknown"
    try:
        # Authentication
        auth_header = websocket.headers.get("authorization")
        if (token is None or not token) and auth_header and auth_header.lower().startswith("bearer "):
            token = auth_header.split(" ", 1)[1].strip()
        
        if not token:
            logger.warning(f"WS: Rejecting connection from {client_host} - No token")
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
            return

        payload = auth_service.decode_token(token)
        user_id = int(payload.get("sub"))
        
    except Exception as e:
        logger.warning(f"WS: Auth failed for {client_host}: {str(e)}")
        try:
            await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        except:
            pass
        return

    await manager.connect(websocket, user_id)
    try:
        while True:
            # Keep-alive / wait for disconnect
            await websocket.receive_text()
    except WebSocketDisconnect:
        # Handled naturally
        pass
    except Exception as e:
        logger.error(f"WS: Exception in session for user {user_id}: {type(e).__name__}: {str(e)}")
    except BaseException as e:
        logger.error(f"WS: BaseException in session for user {user_id}: {type(e).__name__}: {str(e)}")
    finally:
        manager.disconnect(websocket, user_id)

@app.get("/profile", response_model=schemas.UserResponse)
def get_profile(request: Request, current_user: models.User = Depends(auth_deps.get_current_user)):
    """Get current user profile info."""
    # We need to explicitly set the password_count since it's not in the DB model directly
    # as a simple column but we want it in the response.
    # FastAPI/Pydantic will pick it up from current_user if we match names, 
    # but the model doesn't have it. We can return a dict or a new object.
    response_data = schemas.UserResponse.model_validate(current_user)
    response_data.password_count = len(current_user.passwords)
    return response_data


@app.post("/profile/update", response_model=schemas.UserResponse)
def update_profile(request: Request,
                   background_tasks: BackgroundTasks,
                   user_update: schemas.ProfileUpdate,
                   current_user: models.User = Depends(auth_deps.get_current_user),
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
        current_user.hashed_password = auth_service.hash_password(user_update.password)
        
    db.commit()
    db.refresh(current_user)
    crud.audit_event(db, current_user.id, "profile_updated", background_tasks=background_tasks)
    return current_user


@app.get("/profile/seed-phrase")
@limiter.limit("5/hour")
def get_seed_phrase(
    request: Request,
    current_user: models.User = Depends(get_seed_access_user),
    db: Session = Depends(get_db)
):
    """Retrieve the client-encrypted seed phrase blob. Requires short-lived token."""
    if not current_user.seed_phrase_encrypted:
        raise HTTPException(status_code=404, detail="Seed phrase not set")

    # Access Log
    crud.audit_event(db, current_user.id, "seed_phrase_viewed")
    
    # Update last viewed
    current_user.seed_phrase_last_viewed_at = datetime.now(timezone.utc)
    db.commit()
    
    stored_value = current_user.seed_phrase_encrypted
    if stored_value.startswith("client:"):
        return {"seed_phrase_encrypted": stored_value.removeprefix("client:")}

    legacy_plaintext = EncryptionService.decrypt(stored_value)
    return {"seed_phrase": legacy_plaintext}


@app.post("/profile/seed-phrase")
@limiter.limit("5/hour")
def set_seed_phrase(
    request: Request,
    body: dict,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    """Set or rotate the seed phrase. Rotation requires multi-factor proof."""
    encrypted_phrase = body.get("seed_phrase_encrypted")
    new_phrase = body.get("seed_phrase")
    if not encrypted_phrase and not new_phrase:
        raise HTTPException(status_code=400, detail="Seed phrase required")

    # If it's a rotation, we should ideally verify old phrase or password
    # For now, let's enforce TOTP at least
    if current_user.totp_enabled:
        otp = request.headers.get("X-OTP")
        verify_hardened_otp(db, current_user, otp)

    # Encrypt with Server Key
    if encrypted_phrase:
        current_user.seed_phrase_encrypted = f"client:{encrypted_phrase}"
    else:
        current_user.seed_phrase_encrypted = EncryptionService.encrypt(new_phrase)
    db.commit()
    
    crud.audit_event(db, current_user.id, "seed_phrase_updated")
    return {"success": True}


@app.get("/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def read_passwords(request: Request,
                   current_user: models.User = Depends(auth_deps.get_current_user),
                   db: Session = Depends(get_db),
                   background_tasks: BackgroundTasks = BackgroundTasks()):
    # OTP-Gated if configured
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    
    db_passwords = crud.get_passwords(db, user_id=current_user.id)
    
    # Favicon URLs are now handled client-side in Zero-Knowledge mode 
    # or via site_url if it still exists (legacy support)
    for p in db_passwords:
        site_url = getattr(p, 'site_url', None)
        if site_url:
            p.favicon_url = get_favicon_url(site_url)
        
    crud.audit_event(db, current_user.id, "passwords_read", ip=request.client.host, background_tasks=background_tasks)
    return db_passwords


@app.post("/passwords",
          response_model=schemas.PasswordResponse,
          status_code=status.HTTP_201_CREATED)
@limiter.limit("30/minute")
def create_password(request: Request,
                    password: schemas.PasswordCreate,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth_deps.get_current_user),
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
    if password.site_url:
        new_pwd.site_url = password.site_url # For the response schema
        new_pwd.favicon_url = get_favicon_url(password.site_url)
    return new_pwd


@app.get("/passwords/search/{query}", response_model=List[schemas.PasswordResponse])
@limiter.limit("60/minute")
def search_passwords(request: Request,
                    query: str,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth_deps.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    
    results = crud.search_passwords(db, query=query, user_id=current_user.id, background_tasks=background_tasks)
    for p in results:
        site_url = getattr(p, 'site_url', None)
        if site_url:
            p.favicon_url = get_favicon_url(site_url)
            
    return results


@app.post("/import-passwords",
          response_model=List[schemas.PasswordResponse],
          status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
def import_passwords(request: Request,
                    data: schemas.PasswordImport,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth_deps.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    # Sanity check: limit batch size to 500 items to avoid timeouts/OOM
    if len(data.items) > 500:
        raise HTTPException(status_code=400, detail="Batch size too large (max 500)")

    return crud.import_passwords(db, data=data, user_id=current_user.id, background_tasks=background_tasks)


@app.put("/passwords/{password_id}",
         response_model=schemas.PasswordResponse)
@limiter.limit("30/minute")
def update_password(request: Request,
                    password_id: int,
                    password: schemas.PasswordUpdate,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth_deps.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    if not validate_base64(password.encrypted_payload):
        raise HTTPException(status_code=400, detail="Invalid encrypted payload (not base64)")
    
    if password.notes_encrypted and not validate_base64(password.notes_encrypted):
        raise HTTPException(status_code=400, detail="Invalid notes payload (not base64)")

    updated = crud.update_password(db, password_id=password_id, password=password, user_id=current_user.id, background_tasks=background_tasks)
    if password.site_url:
        updated.site_url = password.site_url # For the response schema
        updated.favicon_url = get_favicon_url(password.site_url)
    return updated


@app.delete("/passwords/{password_id}")
@limiter.limit("30/minute")
def delete_password(request: Request,
                    password_id: int,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth_deps.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    crud.delete_password(db, password_id=password_id, user_id=current_user.id, background_tasks=background_tasks)
    return {"status": "deleted"}


# ── Folder Endpoints ──────────────────────────────────────────────────────────

@app.get("/folders", response_model=List[schemas.FolderResponse])
@limiter.limit("30/minute")
def read_folders(request: Request,
                 current_user: models.User = Depends(auth_deps.get_current_user),
                 db: Session = Depends(get_db)):
    return crud.get_folders(db, user_id=current_user.id)


@app.post("/folders", response_model=schemas.FolderResponse)
@limiter.limit("10/minute")
def create_folder(request: Request,
                  folder: schemas.FolderCreate,
                  background_tasks: BackgroundTasks,
                  current_user: models.User = Depends(auth_deps.get_current_user),
                  db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    return crud.create_folder(db=db, folder=folder, user_id=current_user.id, background_tasks=background_tasks)


@app.put("/folders/{folder_id}", response_model=schemas.FolderResponse)
@limiter.limit("10/minute")
def update_folder(request: Request,
                  folder_id: int,
                  folder: schemas.FolderUpdate,
                  current_user: models.User = Depends(auth_deps.get_current_user),
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
@limiter.limit("10/minute")
def delete_folder(request: Request,
                  folder_id: int,
                  current_user: models.User = Depends(auth_deps.get_current_user),
                  db: Session = Depends(get_db)):
    crud.delete_folder(db, folder_id=folder_id, user_id=current_user.id)


@app.get("/folders/{folder_id}/passwords", response_model=List[schemas.PasswordResponse])
@limiter.limit("30/minute")
def read_passwords_by_folder(request: Request,
                             folder_id: int,
                             background_tasks: BackgroundTasks,
                             current_user: models.User = Depends(auth_deps.get_current_user),
                             db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "vault_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    passwords = crud.get_passwords_by_folder(db, folder_id=folder_id, user_id=current_user.id)
    for p in passwords:
        site_url = getattr(p, 'site_url', None)
        if site_url:
            p.favicon_url = get_favicon_url(site_url)
    return passwords


@app.get("/audit", response_model=List[schemas.AuditResponse])
@limiter.limit("10/minute")
def read_audit_logs(request: Request,
                    background_tasks: BackgroundTasks,
                    current_user: models.User = Depends(auth_deps.get_current_user),
                    db: Session = Depends(get_db)):
    # OTP-Gated if configured
    if "audit_read" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)
    return crud.get_logs(db, user_id=current_user.id)


@app.get("/password-history", response_model=List[schemas.HistoryResponse])
@limiter.limit("10/minute")
def read_password_history(request: Request,
                          background_tasks: BackgroundTasks,
                          current_user: models.User = Depends(auth_deps.get_current_user),
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


@app.post("/password-history", response_model=schemas.HistoryResponse)
@limiter.limit("20/minute")
def log_password_history(request: Request,
                        history: schemas.HistoryCreate,
                        background_tasks: BackgroundTasks,
                        current_user: models.User = Depends(auth_deps.get_current_user),
                        db: Session = Depends(get_db)):
    # History logging is always allowed — the vault_write OTP gate protects the
    # actual password operation; adding a separate OTP for logging would force
    # the user to enter their TOTP twice per delete/update, which is wrong.
    if "history_write" in settings.PERMISSIONS_OTP_LIST:
        verify_hardened_otp(db, current_user, request.headers.get("X-OTP"), background_tasks=background_tasks)

    return crud.create_history(db, history, user_id=current_user.id)




@app.post("/admin/request-backend-change")
@limiter.limit("5/minute")
def request_backend_change(
    request: Request,
    new_url: str,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    challenge_id = secrets.token_hex(16)
    crud.create_challenge(db, current_user.id, challenge_id, f"backend_change:{new_url}")

    asyncio.create_task(manager.send_personal_message({
        "type": "backend_change_request",
        "new_url": new_url,
        "challenge_id": challenge_id
    }, current_user.id))
    
    crud.audit_event(db, current_user.id, "backend_change_requested", {"new_url": new_url}, background_tasks=background_tasks)
    return {"status": "request_sent"}


@app.post("/device/confirm-backend-change")
@limiter.limit("5/minute")
def confirm_backend_change(
    request: Request,
    payload: dict,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    challenge_id = payload.get("challenge_id")
    totp_code = payload.get("totp")
    
    challenge_data = crud.get_challenge(db, challenge_id)
    if not challenge_data or not challenge_data.type.startswith("backend_change:"):
        raise HTTPException(status_code=400, detail="Invalid challenge")
        
    verify_hardened_otp(db, current_user, totp_code, background_tasks=background_tasks)
    
    crud.delete_challenge(db, challenge_id)
    crud.audit_event(db, current_user.id, "backend_changed_confirmed", background_tasks=background_tasks)
    return {"status": "backend_changed"}



# ── WebAuthn Endpoints ────────────────────────────────────────────────────────

def _get_webauthn_rp_id() -> str:
    return settings.RP_ID


def _get_webauthn_origin(request: Request) -> str:
    origin = request.headers.get("origin")
    if not origin:
        return settings.EXPECTED_ORIGIN
    if origin not in settings.WEBAUTHN_ALLOWED_ORIGINS:
        raise HTTPException(status_code=400, detail="Invalid origin")
    return origin


@app.post("/webauthn/register/options")
@limiter.limit("5/minute")
async def webauthn_register_options(
    request: Request,
    options_data: schemas.WebAuthnOptionsRequest,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    rp_id = _get_webauthn_rp_id()

    options = generate_registration_options(
        rp_id=rp_id,
        rp_name=settings.RP_NAME,
        user_id=bytes(str(current_user.id), "utf-8"),
        user_name=current_user.login,
        authenticator_selection=AuthenticatorSelectionCriteria(
            resident_key=ResidentKeyRequirement.REQUIRED,
            user_verification=UserVerificationRequirement.REQUIRED,
        ),
    )
    
    # Store challenge (encode to base64url for DB and client consistency)
    import base64
    challenge_str = base64.urlsafe_b64encode(options.challenge).decode("utf-8").rstrip("=")
    crud.create_challenge(db, current_user.id, challenge_str, "registration")
    
    from fastapi.responses import JSONResponse
    return JSONResponse(content=options_to_json(options))


@app.post("/webauthn/register/verify")
@limiter.limit("5/minute")
async def webauthn_register_verify(
    request: Request,
    verify_data: schemas.WebAuthnRegistrationVerify,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    rp_id = _get_webauthn_rp_id()
    expected_origin = _get_webauthn_origin(request)

    challenge_data = crud.get_challenge(db, verify_data.registration_response.get("challenge"))
    if not challenge_data or challenge_data.type != "registration":
        raise HTTPException(status_code=400, detail="Invalid challenge")
    
    if challenge_data.expires_at < datetime.now(timezone.utc):
        crud.delete_challenge(db, challenge_data.challenge)
        raise HTTPException(status_code=400, detail="Challenge expired")
    
    try:
        import base64
        verification = verify_registration_response(
            credential=verify_data.registration_response,
            expected_challenge=base64.urlsafe_b64decode(challenge_data.challenge + "=="),
            expected_origin=expected_origin,
            expected_rp_id=rp_id,
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
    rp_id = _get_webauthn_rp_id()

    options = generate_authentication_options(
        rp_id=rp_id,
        user_verification=UserVerificationRequirement.REQUIRED,
    )
    
    # Store challenge
    import base64
    challenge_str = base64.urlsafe_b64encode(options.challenge).decode("utf-8").rstrip("=")
    crud.create_challenge(db, None, challenge_str, "authentication")
    
    from fastapi.responses import JSONResponse
    return JSONResponse(content=options_to_json(options))


@app.post("/webauthn/login/verify")
@limiter.limit("10/minute")
async def webauthn_login_verify(
    request: Request,
    verify_data: schemas.WebAuthnLoginVerify,
    db: Session = Depends(get_db)
):
    rp_id = _get_webauthn_rp_id()
    expected_origin = _get_webauthn_origin(request)

    common_error = HTTPException(status_code=400, detail="Authentication failed")

    challenge_data = crud.get_challenge(db, verify_data.authentication_response.get("challenge"))
    if not challenge_data or challenge_data.type != "authentication":
        raise common_error
    
    if challenge_data.expires_at < datetime.now(timezone.utc):
        crud.delete_challenge(db, challenge_data.challenge)
        raise common_error
    
    credential_id = verify_data.authentication_response.get("id")
    db_credential = crud.get_webauthn_credential_by_id(db, credential_id)
    
    if not db_credential:
        # Prevent credential enumeration
        time.sleep(1)
        raise common_error

    user = db.query(models.User).filter(models.User.id == db_credential.user_id).first()
    if user and user.lockout_until and user.lockout_until > datetime.now(timezone.utc):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account temporarily locked due to repeated failures"
        )
    
    try:
        import base64
        verification = verify_authentication_response(
            credential=verify_data.authentication_response,
            expected_challenge=base64.urlsafe_b64decode(challenge_data.challenge + "=="),
            expected_origin=expected_origin,
            expected_rp_id=rp_id,
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
        access_token = auth_service.create_access_token(user, verify_data.device_id)
        refresh_token = auth_service.create_refresh_token(db, user.id, verify_data.device_id)
        
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
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    return crud.get_user_devices(db, current_user.id)


@app.delete("/webauthn/devices/{device_id}")
async def revoke_device_endpoint(
    device_id: int,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db)
):
    crud.revoke_device(db, device_id, current_user.id)
    crud.audit_event(db, current_user.id, "device_revoked", {"internal_device_id": device_id}, background_tasks=background_tasks)
    return {"status": "success"}


@app.get("/health")
def health():
    """Minimal health check to avoid information disclosure."""
    return {"status": "ok"}


# ── Password Sharing ──────────────────────────────────────────────────────────

@app.post("/sharing", response_model=schemas.ShareResponse, status_code=status.HTTP_201_CREATED)
async def create_share(
    share: schemas.ShareCreate,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db),
):
    """Create a zero-knowledge password share.

    The client re-encrypts the payload with an ephemeral key before sending;
    the server never sees the plaintext or the share key.
    """
    # Verify recipient exists
    recipient = db.query(models.User).filter(models.User.login == share.recipient_login).first()
    if recipient is None:
        raise HTTPException(status_code=404, detail="Recipient not found")
    if recipient.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot share with yourself")

    # Check expiry
    expires_at = None
    if share.expires_in_days is not None:
        if not (1 <= share.expires_in_days <= 90):
            raise HTTPException(status_code=400, detail="expires_in_days must be 1–90")
        expires_at = datetime.now(timezone.utc) + timedelta(days=share.expires_in_days)

    db_share = models.PasswordShare(
        owner_id=current_user.id,
        recipient_login=share.recipient_login,
        encrypted_payload=share.encrypted_payload,
        encrypted_metadata=share.encrypted_metadata,
        label=share.label,
        expires_at=expires_at,
    )
    db.add(db_share)
    db.commit()
    db.refresh(db_share)

    crud.audit_event(db, current_user.id, "share_created",
                     {"share_id": db_share.id, "recipient": share.recipient_login},
                     background_tasks=background_tasks)
    return db_share


@app.get("/sharing/outgoing", response_model=List[schemas.ShareResponse])
async def list_outgoing_shares(
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db),
):
    """List all shares created by the current user."""
    shares = (
        db.query(models.PasswordShare)
        .filter(models.PasswordShare.owner_id == current_user.id)
        .order_by(models.PasswordShare.created_at.desc())
        .all()
    )
    return shares


@app.get("/sharing/incoming", response_model=List[schemas.ShareResponse])
async def list_incoming_shares(
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db),
):
    """List all shares sent to the current user."""
    shares = (
        db.query(models.PasswordShare)
        .filter(models.PasswordShare.recipient_login == current_user.login)
        .order_by(models.PasswordShare.created_at.desc())
        .all()
    )
    return shares


@app.get("/sharing/{share_id}", response_model=schemas.ShareDetailResponse)
async def get_share(
    share_id: int,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db),
):
    """Fetch share details (owner or recipient only)."""
    share = db.query(models.PasswordShare).filter(models.PasswordShare.id == share_id).first()
    if share is None:
        raise HTTPException(status_code=404, detail="Share not found")
    if share.owner_id != current_user.id and share.recipient_login != current_user.login:
        raise HTTPException(status_code=403, detail="Access denied")

    # Enforce expiry
    if share.expires_at and share.expires_at < datetime.now(timezone.utc):
        share.status = "expired"
        db.commit()
        raise HTTPException(status_code=410, detail="Share has expired")

    return share


@app.post("/sharing/{share_id}/accept", response_model=schemas.ShareResponse)
async def accept_share(
    share_id: int,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db),
):
    """Mark an incoming share as accepted."""
    share = db.query(models.PasswordShare).filter(models.PasswordShare.id == share_id).first()
    if share is None:
        raise HTTPException(status_code=404, detail="Share not found")
    if share.recipient_login != current_user.login:
        raise HTTPException(status_code=403, detail="Access denied")
    if share.status != "pending":
        raise HTTPException(status_code=400, detail=f"Share is already {share.status}")
    if share.expires_at and share.expires_at < datetime.now(timezone.utc):
        raise HTTPException(status_code=410, detail="Share has expired")

    share.status = "accepted"
    db.commit()
    db.refresh(share)

    crud.audit_event(db, current_user.id, "share_accepted",
                     {"share_id": share_id, "owner_id": share.owner_id},
                     background_tasks=background_tasks)
    return share


@app.delete("/sharing/{share_id}", status_code=status.HTTP_204_NO_CONTENT)
async def revoke_share(
    share_id: int,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(auth_deps.get_current_user),
    db: Session = Depends(get_db),
):
    """Revoke (delete) a share. Only the owner can revoke."""
    share = db.query(models.PasswordShare).filter(models.PasswordShare.id == share_id).first()
    if share is None:
        raise HTTPException(status_code=404, detail="Share not found")
    if share.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the owner can revoke a share")

    db.delete(share)
    db.commit()

    crud.audit_event(db, current_user.id, "share_revoked",
                     {"share_id": share_id},
                     background_tasks=background_tasks)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=3000)
