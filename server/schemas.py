from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime


# ── Folder Schemas ────────────────────────────────────────────────────────────

class FolderCreate(BaseModel):
    name: str
    color: str = "#5D52D2"
    icon: str = "folder"


class FolderUpdate(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None


class FolderResponse(BaseModel):
    id: int
    name: str
    color: str
    icon: str
    created_at: datetime
    updated_at: datetime
    password_count: int = 0

    class Config:
        from_attributes = True


# ── User Schemas ──────────────────────────────────────────────────────────────

class UserBase(BaseModel):
    login: str


class UserCreate(UserBase):
    password: str
    telegram_chat_id: Optional[str] = None

class UserResponse(UserBase):
    """Used only for /register — includes one-time TOTP setup fields."""
    id: int
    salt: str  # Client needs salt for KDF
    telegram_chat_id: Optional[str] = None
    totp_secret: Optional[str] = None
    totp_uri: Optional[str] = None

    class Config:
        from_attributes = True


class ProfileResponse(UserBase):
    """Used for /profile GET and POST — never exposes totp_secret."""
    id: int
    salt: str
    telegram_chat_id: Optional[str] = None

    class Config:
        from_attributes = True


class ProfileUpdate(BaseModel):
    password: Optional[str] = None
    telegram_chat_id: Optional[str] = None
    totp_code: Optional[str] = None


# ── WebAuthn Schemas ──────────────────────────────────────────────────────────

class WebAuthnOptionsRequest(BaseModel):
    device_name: Optional[str] = "Unknown Device"

class WebAuthnRegistrationVerify(BaseModel):
    registration_response: Dict[str, Any]
    device_name: str
    device_id: str

class WebAuthnLoginVerify(BaseModel):
    authentication_response: Dict[str, Any]
    device_id: str
    device_name: Optional[str] = "Passkey Login"

class DeviceResponse(BaseModel):
    id: int
    device_name: str
    last_used_at: datetime
    is_active: bool

    class Config:
        from_attributes = True


class Token(BaseModel):
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None
    token_type: str = "bearer"
    user_id: Optional[int] = None
    login: Optional[str] = None
    salt: Optional[str] = None
    two_fa_required: bool = False


class PasswordBase(BaseModel):
    site_hash: Optional[str] = None # HMAC(masterKey, siteName)
    site_url: Optional[str] = None  # To be deprecated/moved to encrypted_metadata
    site_login: Optional[str] = None # To be deprecated/moved to encrypted_metadata
    encrypted_metadata: Optional[str] = None # Client-side encrypted JSON
    has_2fa: bool = False
    has_seed_phrase: bool = False
    folder_id: Optional[int] = None


class PasswordCreate(PasswordBase):
    encrypted_payload: str # Client-side encrypted
    notes_encrypted: Optional[str] = None

class PasswordUpdate(PasswordCreate):
    pass


class PasswordResponse(PasswordBase):
    id: int
    encrypted_payload: str
    notes_encrypted: Optional[str] = None
    favicon_url: Optional[str] = None
    folder_id: Optional[int] = None
    rotation_enabled: bool = False
    rotation_interval_days: Optional[int] = None
    last_rotated_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class HistoryResponse(BaseModel):
    id: int
    action_type: str
    action_details: Dict[str, Any]
    site_url: str
    favicon_url: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class TOTPSetupResponse(BaseModel):
    secret: str
    otp_uri: str


class RefreshRequest(BaseModel):
    refresh_token: str


class LogoutRequest(BaseModel):
    refresh_token: Optional[str] = None


class TOTPConfirmRequest(BaseModel):
    code: str


class AuditResponse(BaseModel):
    id: int
    event: str
    meta: Dict[str, Any]
    created_at: datetime

    class Config:
        from_attributes = True


# ── Password Rotation Schemas ─────────────────────────────────────────────────

class RotationConfig(BaseModel):
    rotation_enabled: bool
    rotation_interval_days: Optional[int] = None  # None = manual only


class RotationUpdate(BaseModel):
    """Client reports the new encrypted payload after rotating the password."""
    encrypted_payload: str
    notes_encrypted: Optional[str] = None
    encrypted_metadata: Optional[str] = None


class RotationDueItem(BaseModel):
    id: int
    encrypted_metadata: Optional[str] = None  # client decrypts to find site name
    rotation_interval_days: Optional[int] = None
    last_rotated_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# ── Secure Sharing Schemas ────────────────────────────────────────────────────

class ShareCreate(BaseModel):
    recipient_login: str
    encrypted_payload: str              # re-encrypted for recipient by client
    encrypted_metadata: Optional[Dict[str, Any]] = None
    label: Optional[str] = None
    expires_in_days: Optional[int] = None


class ShareResponse(BaseModel):
    id: int
    owner_id: int
    recipient_login: str
    label: Optional[str] = None
    status: str
    expires_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class ShareDetailResponse(ShareResponse):
    encrypted_payload: str
    encrypted_metadata: Optional[Dict[str, Any]] = None


# ── Emergency Access Schemas ──────────────────────────────────────────────────

class EmergencyInvite(BaseModel):
    grantee_login: str
    wait_days: int = 7                  # 1–30


class EmergencyVaultUpload(BaseModel):
    encrypted_vault: str                # vault re-encrypted by grantor for grantee


class EmergencyAccessResponse(BaseModel):
    id: int
    grantor_id: int
    grantee_id: int
    grantor_login: Optional[str] = None
    grantee_login: Optional[str] = None
    status: str
    wait_days: int
    last_checkin_at: Optional[datetime] = None
    requested_at: Optional[datetime] = None
    approved_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class EmergencyVaultResponse(BaseModel):
    encrypted_vault: str
