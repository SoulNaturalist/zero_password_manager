from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, JSON, DateTime
from sqlalchemy.orm import relationship
from datetime import datetime
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    login = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    salt = Column(String, nullable=False)  # Base64 salt for client-side KDF
    
    # 2FA Fields
    totp_secret = Column(String, nullable=True)
    totp_enabled = Column(Boolean, default=False)
    last_otp_ts = Column(Integer, default=0) # Protect against replay attacks
    
    history = relationship("PasswordHistory", back_populates="user")
    

class Password(Base):
    __tablename__ = "passwords"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    site_url = Column(String, index=True)
    site_login = Column(String)
    # Zero-Knowledge: Only encrypted blobs
    encrypted_payload = Column(String, nullable=False)  # base64: nonce + ciphertext + tag
    notes_encrypted = Column(String, nullable=True)     # base64
    
    has_2fa = Column(Boolean, default=False)
    has_seed_phrase = Column(Boolean, default=False)
    
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    owner = relationship("User", back_populates="passwords")


class PasswordHistory(Base):
    __tablename__ = "password_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    password_id = Column(Integer, ForeignKey("passwords.id"), nullable=True)
    action_type = Column(String)  # CREATE, UPDATE, DELETE
    action_details = Column(JSON) # Masked data (log site_url, but not payloads)
    site_url = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="history")


class Audit(Base):
    __tablename__ = "audit"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True)
    event = Column(String) # login, register, vault_read, etc.
    meta = Column(JSON)
    ip_address = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)
