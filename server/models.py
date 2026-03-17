from sqlalchemy import Column, Index, Integer, String, Boolean, ForeignKey, JSON, DateTime, LargeBinary, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from .database import Base
import uuid

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    login = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)
    salt = Column(String, nullable=False)  # Base64 salt for client-side KDF
    telegram_chat_id = Column(String, nullable=True) # Added for per-user security alerts

    # 2FA and Security Fields
    totp_secret = Column(String, nullable=True)
    totp_enabled = Column(Boolean, default=False)
    last_otp_ts = Column(Integer, default=0) # Protect against replay attacks
    failed_otp_attempts = Column(Integer, default=0)
    failed_reset_attempts = Column(Integer, default=0)
    lockout_until = Column(DateTime(timezone=True), nullable=True)
    reset_lockout_until = Column(DateTime(timezone=True), nullable=True)
    last_login_attempt = Column(DateTime(timezone=True), nullable=True)
    seed_phrase_encrypted = Column(String, nullable=True)
    seed_phrase_last_viewed_at = Column(DateTime(timezone=True), nullable=True)
    token_version = Column(Integer, default=0, nullable=False)

    history = relationship("PasswordHistory", back_populates="user")
    passwords = relationship("Password", back_populates="owner")
    folders = relationship("Folder", back_populates="owner")


class Folder(Base):
    __tablename__ = "folders"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    name = Column(String, nullable=False)
    color = Column(String, nullable=False, default="#5D52D2")  # Hex color
    icon = Column(String, nullable=False, default="folder")   # Icon name
    is_hidden = Column(Boolean, nullable=False, default=False)  # Hidden folders require TOTP to reveal
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    owner = relationship("User", back_populates="folders")
    passwords = relationship("Password", back_populates="folder")


class WebAuthnCredential(Base):
    __tablename__ = "webauthn_credentials"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    credential_id = Column(String, unique=True, index=True, nullable=False)
    public_key = Column(LargeBinary, nullable=False)
    sign_count = Column(Integer, default=0)
    transports = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    owner = relationship("User", backref="webauthn_credentials")


class UserDevice(Base):
    __tablename__ = "user_devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    device_id = Column(String, index=True, nullable=False) # Persistent client-side ID
    device_name = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    last_used_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    owner = relationship("User", backref="devices")


class WebAuthnChallenge(Base):
    __tablename__ = "webauthn_challenges"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True) # Optional for login
    challenge = Column(String, unique=True, index=True, nullable=False)
    type = Column(String, nullable=False) # 'registration' or 'authentication'
    expires_at = Column(DateTime(timezone=True), nullable=False)
    # CWE-1073: used flag prevents race-condition re-use of the same challenge
    used = Column(Boolean, default=False, nullable=False)
    used_at = Column(DateTime(timezone=True), nullable=True)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Password(Base):
    __tablename__ = "passwords"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    folder_id = Column(Integer, ForeignKey("folders.id"), nullable=True)
    site_hash = Column(String, index=True, nullable=True) # HMAC(masterKey, siteName)
    encrypted_payload = Column(String, nullable=False)  # base64: nonce + ciphertext + tag
    notes_encrypted = Column(String, nullable=True)     # base64
    encrypted_metadata = Column(JSON, nullable=True)    # JSON of other encrypted fields (site_url, site_login, etc.)

    has_2fa = Column(Boolean, default=False)
    has_seed_phrase = Column(Boolean, default=False)

    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

    owner = relationship("User", back_populates="passwords")
    folder = relationship("Folder", back_populates="passwords")


class PasswordHistory(Base):
    __tablename__ = "password_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    password_id = Column(Integer, ForeignKey("passwords.id"), nullable=True)
    action_type = Column(String)  # CREATE, UPDATE, DELETE
    action_details = Column(JSON) # Masked data (log site_url, but not payloads)
    site_url = Column(String)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="history")


class Audit(Base):
    __tablename__ = "audit"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True)
    event = Column(String) # login, register, vault_read, etc.
    meta = Column(JSON)
    ip_address = Column(String)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

class RefreshToken(Base):
    __tablename__ = "refresh_tokens"

    # CWE-613: indexes allow O(1) token lookup and efficient revocation checks
    __table_args__ = (
        Index('idx_refresh_token_hash', 'token_hash'),
        Index('idx_refresh_user_revoked', 'user_id', 'revoked'),
    )

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    token_hash = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))
    expires_at = Column(DateTime(timezone=True), nullable=False)
    revoked = Column(Boolean, default=False)
    device_id = Column(String)
    user = relationship("User")

class IPBlock(Base):
    __tablename__ = "ip_blocks"

    id = Column(Integer, primary_key=True, index=True)
    ip = Column(String, index=True, nullable=False)
    until = Column(DateTime(timezone=True), nullable=False)
    reason = Column(String, nullable=True) # e.g. "Brute force", "Scanner detected"
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class FailedAttempt(Base):
    __tablename__ = "failed_attempts"

    id = Column(Integer, primary_key=True, index=True)
    ip = Column(String, index=True, nullable=False)
    count = Column(Integer, default=0)
    last_attempt = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class UsedOTP(Base):
    __tablename__ = "used_otps"

    # CWE-287: unique constraint makes INSERT atomic — concurrent requests using
    # the same OTP code will get an IntegrityError on the second insert, which
    # is handled in verify_hardened_otp() to raise OTPReplay.
    __table_args__ = (
        UniqueConstraint('user_id', 'otp', name='uq_user_otp'),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    otp = Column(String, nullable=False)
    used_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    user = relationship("User")


class SecurityEvent(Base):
    __tablename__ = "security_events"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    type = Column(String, index=True)
    details = Column(JSON)
    ip = Column(String)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))

    user = relationship("User")
