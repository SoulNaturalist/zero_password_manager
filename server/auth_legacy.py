import os
import secrets
import base64
from datetime import datetime, timedelta, timezone
from typing import Optional
from jose import JWTError, jwt
from passlib.context import CryptContext
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from argon2.low_level import hash_secret_raw, Type as Argon2Type
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from .database import get_db
from . import models
from .config import settings

# Security Configuration
SECRET_KEY = settings.JWT_SECRET_KEY
ALGORITHM = settings.ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = settings.REFRESH_TOKEN_EXPIRE_DAYS

# Argon2 / AES Configuration (Industry Standard 2024-2025)
ARGON2_TIME_COST = 3
ARGON2_MEMORY_COST = 65536
ARGON2_PARALLELISM = 1
ARGON2_HASH_LEN = 32
AES_NONCE_LEN = 12

pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(user_id: int):
    expire = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode = {"sub": str(user_id), "exp": expire, "type": "refresh"}
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


# Crypto Utils (Corrected AES-GCM tag handling)
def generate_salt() -> str:
    return base64.b64encode(secrets.token_bytes(16)).decode()

def derive_key(password: str, salt_b64: str) -> bytes:
    salt = base64.b64decode(salt_b64)
    return hash_secret_raw(
        secret=password.encode(),
        salt=salt,
        time_cost=ARGON2_TIME_COST,
        memory_cost=ARGON2_MEMORY_COST,
        parallelism=ARGON2_PARALLELISM,
        hash_len=ARGON2_HASH_LEN,
        type=Argon2Type.ID,
    )


def encrypt_data(plaintext: str, key: bytes) -> str:
    """Corrected: Returns base64(nonce + ciphertext + tag)"""
    nonce = secrets.token_bytes(AES_NONCE_LEN)
    aesgcm = AESGCM(key)
    # encrypt returns ciphertext + tag
    ciphertext_with_tag = aesgcm.encrypt(nonce, plaintext.encode(), None)
    return base64.b64encode(nonce + ciphertext_with_tag).decode()


def decrypt_data(encrypted_payload_b64: str, key: bytes) -> str:
    """Corrected: Decrypts base64(nonce + ciphertext + tag) with validation"""
    try:
        payload = base64.b64decode(encrypted_payload_b64)
        if len(payload) < AES_NONCE_LEN + 16:  # nonce (12) + min tag (16)
            raise ValueError("Payload too short")
        
        nonce = payload[:AES_NONCE_LEN]
        ciphertext_with_tag = payload[AES_NONCE_LEN:]
        aesgcm = AESGCM(key)
        return aesgcm.decrypt(nonce, ciphertext_with_tag, None).decode()
    except Exception as e:
        # In production, log this specifically for security auditing
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Decryption failed: {str(e)}"
        )

# Auth Dependency
async def get_current_user(token: str = Depends(oauth2_scheme),
                           db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = db.query(models.User).filter(models.User.id == int(user_id)).first()
    if user is None:
        raise credentials_exception

    return user
