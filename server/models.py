from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, JSON, DateTime, LargeBinary
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from .database import Base


# ── Migration helper ──────────────────────────────────────────────────────────

def run_migrations(engine):
    """Add new columns to existing tables (idempotent, SQLite-safe)."""
    with engine.connect() as conn:
        # passwords: rotation fields
        _add_column_if_missing(conn, "passwords", "rotation_enabled", "BOOLEAN DEFAULT 0")
        _add_column_if_missing(conn, "passwords", "rotation_interval_days", "INTEGER")
        _add_column_if_missing(conn, "passwords", "last_rotated_at", "DATETIME")


def _add_column_if_missing(conn, table: str, column: str, col_def: str):
    from sqlalchemy import text
    rows = conn.execute(text(f"PRAGMA table_info({table})")).fetchall()
    existing = {row[1] for row in rows}
    if column not in existing:
        conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {col_def}"))
        conn.commit()

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
    lockout_until = Column(DateTime, nullable=True)
    last_login_attempt = Column(DateTime, nullable=True)

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
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

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
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    owner = relationship("User", backref="webauthn_credentials")


class UserDevice(Base):
    __tablename__ = "user_devices"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    device_id = Column(String, index=True, nullable=False) # Persistent client-side ID
    device_name = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    last_used_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    owner = relationship("User", backref="devices")


class WebAuthnChallenge(Base):
    __tablename__ = "webauthn_challenges"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, nullable=True) # Optional for login
    challenge = Column(String, unique=True, index=True, nullable=False)
    type = Column(String, nullable=False) # 'registration' or 'authentication'
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


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

    # Automatic password rotation
    rotation_enabled = Column(Boolean, default=False)
    rotation_interval_days = Column(Integer, nullable=True)
    last_rotated_at = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc))

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
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

    user = relationship("User", back_populates="history")


class TokenBlacklist(Base):
    """JWT revocation store.

    When a user calls /logout the token's ``jti`` claim is written here.
    get_current_user checks this table so revoked tokens are rejected even
    before their ``exp`` timestamp.  Rows are pruned lazily on each insert.
    """
    __tablename__ = "token_blacklist"

    id = Column(Integer, primary_key=True, index=True)
    jti = Column(String(36), unique=True, index=True, nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False)
    created_at = Column(DateTime(timezone=True), default=lambda: datetime.now(timezone.utc))


class Audit(Base):
    __tablename__ = "audit"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, index=True)
    event = Column(String) # login, register, vault_read, etc.
    meta = Column(JSON)
    ip_address = Column(String)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


# ── Secure Password Sharing ───────────────────────────────────────────────────

class SharedPassword(Base):
    """Zero-knowledge password share.

    The owner re-encrypts the password client-side and sends the resulting
    ``encrypted_payload`` here.  The server never sees the plaintext.
    """
    __tablename__ = "shared_passwords"

    id = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    recipient_id = Column(Integer, ForeignKey("users.id"), nullable=True)  # set after lookup by login
    recipient_login = Column(String, nullable=False, index=True)
    # Client re-encrypts the password specifically for the recipient
    encrypted_payload = Column(String, nullable=False)
    encrypted_metadata = Column(JSON, nullable=True)
    label = Column(String, nullable=True)  # Human-readable label (site name, etc.)
    status = Column(String, default="pending")  # pending | accepted | revoked
    expires_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc),
                        onupdate=lambda: datetime.now(timezone.utc))

    owner = relationship("User", foreign_keys=[owner_id], backref="shares_sent")
    recipient = relationship("User", foreign_keys=[recipient_id], backref="shares_received")


# ── Emergency Access ──────────────────────────────────────────────────────────

class EmergencyAccess(Base):
    """Trusted-person emergency access.

    Flow:
    1. Grantor invites grantee  →  status = invited
    2. Grantee accepts          →  status = accepted
    3. Grantee requests access  →  status = waiting, requested_at = now
       Grantor can check-in     →  resets timer
       Grantor can deny         →  status = denied
    4. After wait_days with no checkin/deny  →  status = approved
    5. Grantor can revoke any time           →  status = revoked

    The grantor optionally pre-uploads an ``encrypted_vault`` so the grantee
    can decrypt it with a shared key arranged out-of-band.
    """
    __tablename__ = "emergency_access"

    id = Column(Integer, primary_key=True, index=True)
    grantor_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    grantee_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    status = Column(String, default="invited")  # invited|accepted|waiting|approved|denied|revoked
    wait_days = Column(Integer, default=7)
    last_checkin_at = Column(DateTime, nullable=True)  # grantor last active confirmation
    requested_at = Column(DateTime, nullable=True)      # when grantee triggered request
    approved_at = Column(DateTime, nullable=True)
    # Pre-uploaded vault: owner encrypts vault for grantee before emergency
    encrypted_vault = Column(String, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(DateTime, default=lambda: datetime.now(timezone.utc),
                        onupdate=lambda: datetime.now(timezone.utc))

    grantor = relationship("User", foreign_keys=[grantor_id], backref="emergency_granted")
    grantee = relationship("User", foreign_keys=[grantee_id], backref="emergency_received")
