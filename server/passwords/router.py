import secrets
import string
from typing import List

from fastapi import APIRouter, Depends, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from sqlalchemy.orm import Session

from ..auth.dependencies import get_current_user, require_otp_for
from ..database import get_db
from ..models import Password, User
from ..utils import attach_favicons, get_favicon_url
from .constants import MAX_PAYLOAD_BYTES
from .dependencies import valid_password
from .exceptions import PayloadTooLarge
from .schemas import PasswordCreate, PasswordResponse, PasswordUpdate
from .service import (
    create_password,
    delete_password,
    get_passwords,
    get_passwords_by_folder,
    update_password,
)

router = APIRouter(prefix="/passwords", tags=["passwords"])
limiter = Limiter(key_func=get_remote_address)


@router.get("", response_model=List[PasswordResponse])
@limiter.limit("60/minute")
def read_passwords(
    request: Request,
    current_user: User = Depends(require_otp_for("vault_read")),
    db: Session = Depends(get_db),
):
    passwords = get_passwords(db, user_id=current_user.id)
    attach_favicons(passwords)
    return passwords


@router.post("", response_model=PasswordResponse, status_code=201)
@limiter.limit("30/minute")
def create_password_entry(
    request: Request,
    body: PasswordCreate,
    current_user: User = Depends(require_otp_for("vault_write")),
    db: Session = Depends(get_db),
):
    if len(body.encrypted_payload) > MAX_PAYLOAD_BYTES:
        raise PayloadTooLarge()

    pw = create_password(db, data=body, user_id=current_user.id)
    pw.favicon_url = get_favicon_url(pw.site_url)
    return pw


@router.put("/{password_id}", response_model=PasswordResponse)
@limiter.limit("30/minute")
def update_password_entry(
    request: Request,
    body: PasswordUpdate,
    password: Password = Depends(valid_password),
    db: Session = Depends(get_db),
):
    updated = update_password(db, password=password, data=body)
    updated.favicon_url = get_favicon_url(updated.site_url)
    return updated


@router.delete("/{password_id}", status_code=204)
@limiter.limit("30/minute")
def delete_password_entry(
    request: Request,
    password: Password = Depends(valid_password),
    db: Session = Depends(get_db),
):
    delete_password(db, password=password)


# ── Utility: password generator ───────────────────────────────────────────────

@router.get("/generate")
def generate_password(
    length: int = 24,
):
    """Generate a cryptographically random password (length 8–128)."""
    from ..exceptions import AppException

    class InvalidLength(AppException):
        status_code = 400
        detail = "length must be between 8 and 128"

    if not (8 <= length <= 128):
        raise InvalidLength()

    alphabet = string.ascii_letters + string.digits + "!@#$%^&*()_+-="
    return {"password": "".join(secrets.choice(alphabet) for _ in range(length))}


# ── Password history ──────────────────────────────────────────────────────────
# Registered here (under /passwords prefix) and also in audit router for compat.

from ..audit.schemas import HistoryResponse
from ..audit.service import get_history


@router.get("/history", response_model=List[HistoryResponse])
@limiter.limit("30/minute")
def read_password_history(
    request: Request,
    current_user: User = Depends(require_otp_for("history_read")),
    db: Session = Depends(get_db),
):
    history = get_history(db, user_id=current_user.id)
    attach_favicons(history)
    return history
