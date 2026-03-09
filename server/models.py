from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, JSON, String
from sqlalchemy.orm import relationship

from .database import Base


class User(Base):
    __tablename__ = "users"

    id              = Column(Integer, primary_key=True, index=True)
    login           = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    salt            = Column(String, nullable=False)  # base64 salt for client-side KDF

    # 2FA
    totp_secret  = Column(String,  nullable=True)
    totp_enabled = Column(Boolean, default=False)
    last_otp_ts  = Column(Integer, default=0)  # replay-attack protection

    passwords = relationship("Password",       back_populates="owner")
    folders   = relationship("Folder",         back_populates="owner")
    history   = relationship("PasswordHistory", back_populates="user")


class Folder(Base):
    __tablename__ = "folders"

    id      = Column(Integer,  primary_key=True, index=True)
    user_id = Column(Integer,  ForeignKey("users.id"), nullable=False)
    name    = Column(String,   nullable=False)
    color   = Column(String,   nullable=False, default="#5D52D2")
    icon    = Column(String,   nullable=False, default="folder")
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    owner     = relationship("User",     back_populates="folders")
    passwords = relationship("Password", back_populates="folder")

    # Transient — populated by the query layer, never written to the database.
    password_count: int = 0


class Password(Base):
    __tablename__ = "passwords"

    id      = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    folder_id = Column(Integer, ForeignKey("folders.id"), nullable=True)

    site_url   = Column(String, index=True)
    site_login = Column(String)

    # Zero-knowledge: only encrypted blobs are stored; server cannot decrypt them.
    encrypted_payload = Column(String, nullable=False)  # base64(nonce ‖ ciphertext ‖ tag)
    notes_encrypted   = Column(String, nullable=True)   # base64

    has_2fa        = Column(Boolean, default=False)
    has_seed_phrase = Column(Boolean, default=False)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    owner  = relationship("User",   back_populates="passwords")
    folder = relationship("Folder", back_populates="passwords")

    # Transient — set per-request by the router layer.
    favicon_url: str = None


class PasswordHistory(Base):
    __tablename__ = "password_history"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, ForeignKey("users.id"))
    password_id = Column(Integer, ForeignKey("passwords.id"), nullable=True)
    action_type    = Column(String)  # CREATE | UPDATE | DELETE
    action_details = Column(JSON)    # Masked: logs site_url but never plaintext payloads
    site_url   = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="history")

    # Transient — set per-request by the router layer.
    favicon_url: str = None


class Audit(Base):
    __tablename__ = "audit"

    id         = Column(Integer, primary_key=True, index=True)
    user_id    = Column(Integer, index=True)
    event      = Column(String)  # login | register | vault_read | vault_create | …
    meta       = Column(JSON)
    ip_address = Column(String)
    created_at = Column(DateTime, default=datetime.utcnow)
