import base64
import secrets
from datetime import datetime, timedelta
from typing import Optional

import pyotp
from argon2.low_level import Type as Argon2Type, hash_secret_raw
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from . import models
from .config import settings
from .database import get_db

# ── Crypto constants ──────────────────────────────────────────────────────────
# Argon2id parameters (OWASP recommended minimums, 2024)
ARGON2_TIME_COST   = 3
ARGON2_MEMORY_COST = 65_536  # 64 MB
ARGON2_PARALLELISM = 1
ARGON2_HASH_LEN    = 32

AES_NONCE_LEN = 12  # 96-bit nonce for AES-256-GCM

# ── Internal helpers ──────────────────────────────────────────────────────────

_pwd_context   = CryptContext(schemes=["argon2"], deprecated="auto")
_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


# ── Password hashing ──────────────────────────────────────────────────────────

def verify_password(plain: str, hashed: str) -> bool:
    return _pwd_context.verify(plain, hashed)


def hash_password(plain: str) -> str:
    return _pwd_context.hash(plain)


# ── JWT tokens ────────────────────────────────────────────────────────────────

def create_access_token(data: dict) -> str:
    payload = {
        **data,
        "exp": datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        "type": "access",
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.ALGORITHM)


def create_refresh_token(user_id: int) -> str:
    payload = {
        "sub": str(user_id),
        "exp": datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        "type": "refresh",
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.ALGORITHM)


def decode_token(token: str) -> dict:
    """Decode and verify a JWT. Raises HTTPException on any failure."""
    try:
        return jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )


# ── Encryption helpers (used only if server-side crypto is needed) ─────────────
# Note: this app is zero-knowledge — the server receives already-encrypted blobs.
# These helpers exist for key derivation / future use.

def generate_salt() -> str:
    """Return a base64-encoded 16-byte random salt."""
    return base64.b64encode(secrets.token_bytes(16)).decode()


def derive_key(password: str, salt_b64: str) -> bytes:
    """Derive a 256-bit key from a password using Argon2id."""
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
    """AES-256-GCM decrypt. Raises HTTP 400 on any failure (never leaks internals)."""
    try:
        payload = base64.b64decode(payload_b64)
        if len(payload) < AES_NONCE_LEN + 16:
            raise ValueError("Payload too short")
        nonce, ciphertext_with_tag = payload[:AES_NONCE_LEN], payload[AES_NONCE_LEN:]
        return AESGCM(key).decrypt(nonce, ciphertext_with_tag, None).decode()
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Decryption failed")


# ── 2FA / OTP ─────────────────────────────────────────────────────────────────

def verify_hardened_otp(db: Session, user: models.User, otp: Optional[str]) -> None:
    """
    Verify a TOTP code for hardened (OTP-gated) operations.

    Raises HTTPException if:
      - 2FA is enabled but no OTP was supplied
      - the OTP code is invalid
      - the OTP time-window was already used (replay attack)
    """
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
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="INVALID_OTP")

    # Replay protection: each time-window can only be used once
    current_timecode = totp.timecode(datetime.utcnow())
    if current_timecode <= user.last_otp_ts:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="OTP_REPLAY_DETECTED")

    user.last_otp_ts = current_timecode
    db.commit()


# ── FastAPI dependency ────────────────────────────────────────────────────────

async def get_current_user(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> models.User:
    """Resolve a Bearer JWT to a User row. Raises 401 on any failure."""
    payload = decode_token(token)

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = db.query(models.User).filter(models.User.id == int(user_id)).first()
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user
