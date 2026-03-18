import asyncio
import base64
import hashlib
import hmac
import logging
import re
import secrets
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import BackgroundTasks, HTTPException, Request, Response
import pyotp
from argon2.low_level import Type as Argon2Type, hash_secret_raw
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..models import User, RefreshToken, SecurityEvent, UsedOTP, UsedMFAToken
from ..security import SecurityManager, SECURITY_PARAMS
from ..audit.service import record as audit
from .constants import (
    AES_NONCE_LEN,
    ARGON2_HASH_LEN,
    ARGON2_MEMORY_COST,
    ARGON2_PARALLELISM,
    ARGON2_TIME_COST,
    MAX_EXECUTION_TIME,
    MAX_FAILED_OTP_ATTEMPTS,
    LOCKOUT_TIME_MINUTES,
)
from .exceptions import (
    InvalidCredentials,
    InvalidOTPCode,
    InvalidRefreshToken,
    OTPInvalid,
    OTPReplay,
    OTPRequired,
    WeakPassword,
)
from .. import schemas as _root_schemas  # avoid circular: use local schemas below
from .schemas import UserCreate, LoginPhase1Response, TOTPConfirmRequest, Token

_pwd_context = CryptContext(
    schemes=["argon2"],
    deprecated="auto",
    argon2__memory_cost=65536,
    argon2__time_cost=3,
    argon2__parallelism=4
)

_PASSWORD_RE = re.compile(r'^(?=.*[A-Z])(?=.*[a-z])(?=.*\d)(?=.*[!@#$%^&*(),.?":{}|<>]).{14,}$')


# ── Password hashing ──────────────────────────────────────────────────────────

def hash_password(plain: str) -> str:
    return SecurityManager.hash_password(plain)


def verify_password(plain: str, hashed: str) -> bool:
    return SecurityManager.verify_password(plain, hashed)


def verify_password_fake(plain: str, hashed: str) -> bool:
    """Fake password verification for constant-time comparison."""
    # Argon2 verify is timing-resistant by default, but we use it with a fake hash
    return SecurityManager.verify_password(plain, hashed)


def is_password_strong(password: str) -> bool:
    return bool(_PASSWORD_RE.match(password))


# ── JWT ───────────────────────────────────────────────────────────────────────

def create_access_token(user: User, device_id: str) -> str:
    now = int(time.time())
    payload = {
        "sub": str(user.id),
        "device": device_id,
        "type": "access",
        "jti": secrets.token_hex(16),
        "token_version": user.token_version,
        "iat": now,
        "exp": now + int(timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES).total_seconds()),
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm="HS256")

def create_short_token(user_id: int) -> str:
    """Create a short-lived token for sensitive operations like seed phrase access."""
    now = int(time.time())
    payload = {
        "sub": str(user_id),
        "scope": "seed_access",
        "iat": now,
        "exp": now + 60,
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm="HS256")


def create_refresh_token(db: Session, user_id: int, device_id: str) -> str:
    token_id = uuid.uuid4()
    raw_token = secrets.token_urlsafe(64)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    
    db_token = RefreshToken(
        id=token_id,
        user_id=user_id,
        token_hash=token_hash,
        device_id=device_id,
        expires_at=datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    )
    
    db.add(db_token)
    
    return f"{token_id}.{raw_token}"


def decode_token(token: str, expected_type: str | None = "access") -> dict:
    """Decode and verify a JWT using SecurityManager."""
    return SecurityManager.decode_token(token, expected_type)


# ── Crypto helpers ────────────────────────────────────────────────────────────

def generate_salt() -> str:
    """Return a base64-encoded 32-byte random salt for client-side KDF."""
    return base64.b64encode(secrets.token_bytes(32)).decode()


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
    """AES-256-GCM encrypt with AAD. Returns base64(nonce ‖ ciphertext ‖ tag)."""
    nonce = secrets.token_bytes(AES_NONCE_LEN)
    aad = b"vault-data"
    ciphertext_with_tag = AESGCM(key).encrypt(nonce, plaintext.encode(), aad)
    return base64.b64encode(nonce + ciphertext_with_tag).decode()


def decrypt(payload_b64: str, key: bytes) -> str:
    """AES-256-GCM decrypt with AAD. Always raises a generic error to avoid leaking internals."""
    from ..exceptions import AppException

    try:
        payload = base64.b64decode(payload_b64)
        if len(payload) < AES_NONCE_LEN + 16:
            raise ValueError("Payload too short")
        nonce, body = payload[:AES_NONCE_LEN], payload[AES_NONCE_LEN:]
        aad = b"vault-data"
        return AESGCM(key).decrypt(nonce, body, aad).decode()
    except Exception:
        class DecryptionFailed(AppException):
            status_code = 400
            detail = "Decryption failed"
        raise DecryptionFailed()


# ── TOTP / 2FA ────────────────────────────────────────────────────────────────

def authenticate_user(db: Session, login: str, password: str):
    """Authenticate user with protection against login enumeration."""
    user = get_user_by_login(db, login)
    
    # Always perform a hash verification to maintain constant time
    fake_hash = "$argon2id$v=19$m=65536,t=3,p=4$fake$fakehash"
    
    if not user:
        verify_password(password, fake_hash)
        raise InvalidCredentials()
    
    if not verify_password(password, user.hashed_password):
        raise InvalidCredentials()
    
    return user

def verify_hardened_otp(db: Session, user: User, otp: Optional[str], ip_address: Optional[str] = None) -> None:
    """
    Verify a TOTP code with drift compensation, atomic replay protection, and account lockout.

    CWE-287 (Replay Attack) fix:
      Old approach — SELECT then INSERT — had a race condition: two concurrent
      requests could both pass the SELECT check before either committed the INSERT.
      New approach:
        1. Verify OTP mathematically (no DB round-trip for invalid codes).
        2. If valid, attempt atomic INSERT protected by the UniqueConstraint
           on (user_id, otp).  The second concurrent request gets IntegrityError
           and is rejected as OTPReplay — no window for parallel reuse.
    """
    if not user.totp_enabled:
        return

    if not otp:
        raise OTPRequired()

    # ── Lockout check BEFORE any cryptographic work (NIST 800-63B) ──
    if user.lockout_until and user.lockout_until > datetime.now(timezone.utc):
        raise HTTPException(
            status_code=423,
            detail="Account temporarily locked. Try again later.",
        )

    # ── Step 1: mathematical check (fast path — rejects wrong codes without DB) ──
    totp_secret = decrypt_totp(user.totp_secret, user.id)
    totp_obj = pyotp.TOTP(totp_secret)
    valid = False

    for offset in [-30, 0, 30]:
        check_time = datetime.now(timezone.utc) + timedelta(seconds=offset)
        if totp_obj.verify(otp, for_time=check_time, valid_window=1):
            valid = True
            break

    if not valid:
        handle_failed_otp_attempt(db, user, ip_address)
        raise OTPInvalid()

    # ── Step 2: atomic INSERT — IntegrityError means OTP already used ──
    try:
        used_otp = UsedOTP(user_id=user.id, otp=otp)
        db.add(used_otp)
        db.flush()  # Raise IntegrityError now, before committing other state
    except IntegrityError:
        db.rollback()
        handle_failed_otp_attempt(db, user, ip_address)
        raise OTPReplay()

    reset_otp_failure_counters(user, db)
    db.commit()

def handle_failed_otp_attempt(db: Session, user: User, ip_address: Optional[str] = None) -> None:
    """Handle failed OTP attempt with proper logging and lockout."""
    if not user:
        return
    
    user.failed_otp_attempts = (user.failed_otp_attempts or 0) + 1
    if user.failed_otp_attempts >= MAX_FAILED_OTP_ATTEMPTS:
        user.lockout_until = datetime.now(timezone.utc) + timedelta(minutes=LOCKOUT_TIME_MINUTES)
        audit(db, user.id, "account_locked", {"reason": "too_many_otp_failures"})
    
    db.commit()

def reset_otp_failure_counters(user: User, db: Session) -> None:
    """Reset OTP failure counters on successful verification."""
    user.failed_otp_attempts = 0
    user.lockout_until = None
    db.commit()

def safe_compare(a: Optional[str], b: Optional[str]) -> bool:
    """Safe comparison of strings in constant time."""
    if a is None or b is None:
        return False
    return hmac.compare_digest(a.encode(), b.encode())

def constant_time_response(start_time: float) -> None:
    """Ensure constant time response for all authentication paths."""
    SecurityManager.constant_time_delay(start_time)

def create_mfa_token(user_id: int, device_id: str) -> str:
    """Create a temporary one-time-use MFA token.  jti is stored in UsedMFAToken
    on first use; a second attempt with the same token gets IntegrityError → 401.
    """
    now = int(time.time())
    payload = {
        "sub": str(user_id),
        "device": device_id,
        "type": "mfa",
        "jti": secrets.token_hex(16),  # unique ID for one-time-use enforcement
        "iat": now,
        "exp": now + 120,  # 2 minutes
    }
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.ALGORITHM)

def validate_mfa_token(token: str, db: Session) -> dict:
    """Validate MFA token and atomically mark it as used (replay protection).

    Uses the same atomic-INSERT pattern as verify_hardened_otp / UsedOTP:
    the UniqueConstraint on UsedMFAToken.jti ensures that if two concurrent
    requests present the same token only one succeeds; the second gets an
    IntegrityError and is rejected with 401.
    """
    from sqlalchemy.exc import IntegrityError
    from datetime import timezone as _tz

    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.ALGORITHM])
        if payload.get("type") != "mfa":
            raise ValueError("Invalid token type")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid MFA token")

    jti = payload.get("jti")
    if not jti:
        # Tokens without jti pre-date this change; reject them.
        raise HTTPException(status_code=401, detail="Invalid MFA token")

    exp = payload.get("exp", 0)
    expires_at = datetime.fromtimestamp(exp, tz=_tz.utc)

    try:
        db.add(UsedMFAToken(jti=jti, expires_at=expires_at))
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=401, detail="MFA token already used")

    return payload

def get_device_id_from_request(request: Request) -> str:
    """Get device ID from secure cookie or generate new one."""
    device_id = request.cookies.get("device_id")
    if not device_id:
        device_id = secrets.token_hex(32)
    return device_id

def log_security_event(db: Session, user_id: Optional[int], event_type: str, details: dict, ip_address: str) -> None:
    """Log security events using SecurityManager."""
    SecurityManager.log_security_event(db, event_type, details, ip_address, user_id)

def notify_user_of_suspicious_activity(db: Session, user: User, ip_address: str, device_id: str) -> None:
    """Notify user of suspicious activity (placeholder implementation)."""
    # TODO: Implement email notification or other alert mechanism
    logging.warning(f"Suspicious activity detected for user {user.id} from IP {ip_address}")

def verify_refresh_token(db: Session, token: str):
    """Verify and return refresh token. Raises InvalidRefreshToken on any failure."""
    try:
        token_id, raw = token.split(".")
    except ValueError:
        raise InvalidRefreshToken()

    db_token = db.get(RefreshToken, token_id)

    fake_hash = "$argon2id$v=19$m=65536,t=3,p=4$fake$fakehash"

    if not db_token:
        # Use a constant time check even for invalid IDs
        hashlib.sha256(raw.encode()).hexdigest()
        raise InvalidRefreshToken()

    if db_token.revoked:
        raise InvalidRefreshToken()

    if db_token.expires_at < datetime.utcnow():
        raise InvalidRefreshToken()

    current_hash = hashlib.sha256(raw.encode()).hexdigest()
    if not hmac.compare_digest(current_hash, db_token.token_hash):
        raise InvalidRefreshToken()

    return db_token

def rotate_refresh_token(db: Session, token: str):
    """Rotate refresh token for security."""
    db_token = verify_refresh_token(db, token)
    
    # Revoke old token
    db_token.revoked = True
    
    # Create new token
    new_refresh = create_refresh_token(db, db_token.user_id, db_token.device_id)
    access = create_access_token(db_token.user, db_token.device_id)
    
    return access, new_refresh


# ── User CRUD ─────────────────────────────────────────────────────────────────

def get_user_by_login(db: Session, login: str) -> Optional[User]:
    return db.query(User).filter(User.login == login).first()


def create_user(db: Session, data: UserCreate) -> User:
    if not is_password_strong_enhanced(data.password):
        raise WeakPassword()

    user = User(
        login=data.login,
        hashed_password=hash_password(data.password),
        salt=data.salt if data.salt else generate_salt(),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# ── Device Fingerprinting ─────────────────────────────────────────────────────

def generate_device_id(request: Request, device_info: Optional[dict] = None) -> str:
    """Generate a secure device fingerprint. Uses mobile info if provided."""
    if device_info:
        return SecurityManager.generate_device_id_from_flutter(device_info)
    return SecurityManager.generate_device_id(request)


# ── Password Security Enhancements ────────────────────────────────────────────

def is_password_strong_enhanced(password: str) -> bool:
    """Enhanced password strength check with entropy and breach detection."""
    import zxcvbn
    
    # Basic regex check
    if not _PASSWORD_RE.match(password):
        return False
    
    # Entropy check using zxcvbn
    result = zxcvbn.zxcvbn(password)
    
    if result["score"] < 3:
        return False
    
    # Representative subset of top-10000 most common passwords (March 2026 update)
    # In full production, this would be a separate file or a bloom filter.
    common_passwords = {
        "password", "password123", "123456", "12345678", "123456789", "qwerty", 
        "admin", "welcome", "login", "secret", "qazwsx", "root", "monkey", 
        "dragon", "master", "p@ssword", "oracle", "starwars", "pokemon",
        "letmein", "changeme", "iloveyou", "football", "baseball", "soccer",
    }
    
    clean_pwd = password.strip().lower()
    if clean_pwd in common_passwords or any(cp in clean_pwd for cp in ["12345", "qwerty", "asdfgh"]):
        return False
    
    # Check for repetitive characters
    if len(set(password)) < 5:
        return False
        
    return True


# Cache master key for performance
MASTER_KEY = base64.b64decode(settings.TOTP_MASTER_KEY)

def encrypt_totp(secret: str, user_id: int) -> str:
    """Encrypt TOTP secret with per-user unique key and nonce using HKDF."""
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    
    master_key = base64.b64decode(settings.TOTP_MASTER_KEY)
    info = f"user-{user_id}".encode()
    
    # Derive unique key using HKDF
    hkdf = HKDF(
        algorithm=SECURITY_PARAMS["HKDF"]["algorithm"],
        length=SECURITY_PARAMS["HKDF"]["length"],
        salt=None,
        info=info,
    )
    derived_key = hkdf.derive(master_key)
    
    # Use AES-GCM with unique nonce
    cipher = AESGCM(derived_key[:32])
    nonce = secrets.token_bytes(12)
    aad = hashlib.sha256(info).digest()
    encrypted = cipher.encrypt(nonce, secret.encode(), aad)
    return base64.urlsafe_b64encode(nonce + encrypted).decode()

def decrypt_totp(data: str, user_id: int) -> str:
    """Decrypt TOTP secret with per-user unique key using HKDF."""
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    
    payload = base64.urlsafe_b64decode(data)
    nonce, body = payload[:12], payload[12:]
    
    master_key = base64.b64decode(settings.TOTP_MASTER_KEY)
    info = f"user-{user_id}".encode()
    
    # Derive same key using HKDF
    hkdf = HKDF(
        algorithm=SECURITY_PARAMS["HKDF"]["algorithm"],
        length=SECURITY_PARAMS["HKDF"]["length"],
        salt=None,
        info=info,
    )
    derived_key = hkdf.derive(master_key)
    
    cipher = AESGCM(derived_key[:32])
    aad = hashlib.sha256(info).digest()
    return cipher.decrypt(nonce, body, aad).decode()

def generate_derived_key(user_id: int) -> bytes:
    """Legacy derived key logic, replaced by HKDF in encrypt/decrypt_totp."""
    master_key = base64.b64decode(settings.TOTP_MASTER_KEY)
    import hashlib
    salt = hashlib.sha256(str(user_id).encode()).digest()
    return hashlib.pbkdf2_hmac('sha256', master_key, salt, 100000, dklen=32)

def update_user_totp(
    db: Session,
    user: User,
    secret: Optional[str] = None,
    enabled: Optional[bool] = None,
):
    if secret is not None:
        user.totp_secret = encrypt_totp(secret, user.id)
    if enabled is not None:
        user.totp_enabled = enabled
    db.commit()
    db.refresh(user)
    return user
