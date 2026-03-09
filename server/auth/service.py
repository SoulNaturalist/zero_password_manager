import base64
import re
import secrets
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt as pyjwt
import pyotp
from argon2.low_level import Type as Argon2Type, hash_secret_raw
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from jwt import PyJWTError
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from ..config import settings
from ..models import User
from .constants import (
    AES_NONCE_LEN,
    ARGON2_HASH_LEN,
    ARGON2_MEMORY_COST,
    ARGON2_PARALLELISM,
    ARGON2_TIME_COST,
)
from .exceptions import (
    InvalidOTPCode,
    InvalidRefreshToken,
    OTPInvalid,
    OTPReplay,
    OTPRequired,
    WeakPassword,
)
from .. import schemas as _root_schemas  # avoid circular: use local schemas below
from .schemas import UserCreate

_pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

# Enforce the same policy everywhere: 14+ chars, upper, lower, digit, special.
# Must stay in sync with crud.validate_password_strength.
_PASSWORD_RE = re.compile(
    r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[!@#$%^&*()\-_=+,.?":{}|<>]).{14,}$'
)


# ── Password hashing ──────────────────────────────────────────────────────────

def hash_password(plain: str) -> str:
    return _pwd_context.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return _pwd_context.verify(plain, hashed)


def is_password_strong(password: str) -> bool:
    return bool(_PASSWORD_RE.match(password))


# ── JWT ───────────────────────────────────────────────────────────────────────

def create_access_token(data: dict) -> str:
    payload = {
        **data,
        "jti": str(uuid.uuid4()),  # unique ID — enables per-token revocation
        "exp": datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        "type": "access",
    }
    return pyjwt.encode(payload, settings.JWT_SECRET_KEY, algorithm="HS256")


def create_refresh_token(user_id: int) -> str:
    payload = {
        "sub": str(user_id),
        "jti": str(uuid.uuid4()),  # unique ID — enables per-token revocation
        "exp": datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        "type": "refresh",
    }
    return pyjwt.encode(payload, settings.JWT_SECRET_KEY, algorithm="HS256")


def decode_token(token: str) -> dict:
    """Decode and verify a JWT. Raises InvalidRefreshToken on any failure.
    Algorithm is hardcoded to HS256 to prevent algorithm confusion attacks.
    """
    try:
        return pyjwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=["HS256"],
            options={"require": ["exp", "sub"]},
        )
    except PyJWTError:
        raise InvalidRefreshToken()


# ── Crypto helpers ────────────────────────────────────────────────────────────

def generate_salt() -> str:
    """Return a base64-encoded 16-byte random salt for client-side KDF."""
    return base64.b64encode(secrets.token_bytes(16)).decode()


def derive_key(password: str, salt_b64: str) -> bytes:
    """Derive a 256-bit key from a master password using Argon2id."""
    return hash_secret_raw(
        secret=password.encode(),
        salt=base64.b64decode(salt_b64),
        time_cost=ARGON2_TIME_COST,
        memory_cost=ARGON2_MEMORY_COST,
        parallelism=ARGON2_PARALLELISM,
        hash_len=ARGON2_HASH_LEN,
        type=Argon2Type.ID,
    )


def encrypt(plaintext: str, key: bytes) -> str:
    """AES-256-GCM encrypt. Returns base64(nonce ‖ ciphertext ‖ tag)."""
    nonce = secrets.token_bytes(AES_NONCE_LEN)
    ciphertext_with_tag = AESGCM(key).encrypt(nonce, plaintext.encode(), None)
    return base64.b64encode(nonce + ciphertext_with_tag).decode()


def decrypt(payload_b64: str, key: bytes) -> str:
    """AES-256-GCM decrypt. Always raises a generic error to avoid leaking internals."""
    from ..exceptions import AppException

    try:
        payload = base64.b64decode(payload_b64)
        if len(payload) < AES_NONCE_LEN + 16:
            raise ValueError("Payload too short")
        nonce, body = payload[:AES_NONCE_LEN], payload[AES_NONCE_LEN:]
        return AESGCM(key).decrypt(nonce, body, None).decode()
    except Exception:
        class DecryptionFailed(AppException):
            status_code = 400
            detail = "Decryption failed"
        raise DecryptionFailed()


# ── TOTP / 2FA ────────────────────────────────────────────────────────────────

def verify_hardened_otp(db: Session, user: User, otp: Optional[str]) -> None:
    """
    Verify a TOTP code for operations protected by hardened OTP.
    Raises a domain exception (never HTTPException) on any failure.
    """
    if not user.totp_enabled:
        return

    if not otp:
        raise OTPRequired()

    totp = pyotp.TOTP(user.totp_secret)

    if not totp.verify(otp, valid_window=1):
        raise OTPInvalid()

    # Replay protection: each 30-second window can only be used once
    current_timecode = totp.timecode(datetime.now(timezone.utc))
    if current_timecode <= user.last_otp_ts:
        raise OTPReplay()

    user.last_otp_ts = current_timecode
    db.commit()


# ── User CRUD ─────────────────────────────────────────────────────────────────

def get_user_by_login(db: Session, login: str) -> Optional[User]:
    return db.query(User).filter(User.login == login).first()


def create_user(db: Session, data: UserCreate) -> User:
    if not is_password_strong(data.password):
        raise WeakPassword()

    user = User(
        login=data.login,
        hashed_password=hash_password(data.password),
        salt=generate_salt(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def update_user_totp(
    db: Session,
    user_id: int,
    secret: Optional[str] = None,
    enabled: Optional[bool] = None,
) -> User:
    user = db.get(User, user_id)
    if secret is not None:
        user.totp_secret = secret
    if enabled is not None:
        user.totp_enabled = enabled
    db.commit()
    db.refresh(user)
    return user
