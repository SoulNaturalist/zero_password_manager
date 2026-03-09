from pydantic import BaseModel, Field, field_validator
from typing import Optional, List, Dict, Any
from datetime import datetime
import re


# ── Folder Schemas ────────────────────────────────────────────────────────────

_HEX_COLOR_RE = re.compile(r'^#[0-9A-Fa-f]{6}$')
_ALLOWED_ICONS = {
    'folder', 'work', 'home', 'lock', 'star', 'favorite',
    'shopping_cart', 'school', 'code', 'gaming', 'bank',
    'email', 'cloud', 'social', 'crypto', 'vpn_key',
}


class FolderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    color: str = Field("#5D52D2", max_length=7)
    icon: str = Field("folder", max_length=32)

    @field_validator('color')
    @classmethod
    def validate_color(cls, v: str) -> str:
        if not _HEX_COLOR_RE.match(v):
            raise ValueError('color must be a valid hex color, e.g. #5D52D2')
        return v

    @field_validator('icon')
    @classmethod
    def validate_icon(cls, v: str) -> str:
        if v not in _ALLOWED_ICONS:
            raise ValueError(f'icon must be one of: {", ".join(sorted(_ALLOWED_ICONS))}')
        return v


class FolderUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=64)
    color: Optional[str] = Field(None, max_length=7)
    icon: Optional[str] = Field(None, max_length=32)

    @field_validator('color')
    @classmethod
    def validate_color(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not _HEX_COLOR_RE.match(v):
            raise ValueError('color must be a valid hex color, e.g. #5D52D2')
        return v

    @field_validator('icon')
    @classmethod
    def validate_icon(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and v not in _ALLOWED_ICONS:
            raise ValueError(f'icon must be one of: {", ".join(sorted(_ALLOWED_ICONS))}')
        return v


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

class UserResponse(UserBase):
    id: int
    salt: str  # Client needs salt for KDF
    totp_secret: Optional[str] = None
    totp_uri: Optional[str] = None

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


class RefreshRequest(BaseModel):
    refresh_token: str


class PasswordBase(BaseModel):
    site_url: str = Field(..., max_length=2048)
    site_login: str = Field(..., max_length=512)
    has_2fa: bool = False
    has_seed_phrase: bool = False
    folder_id: Optional[int] = None


class PasswordCreate(PasswordBase):
    encrypted_payload: str = Field(..., max_length=2 * 1024 * 1024)  # 2 MB
    notes_encrypted: Optional[str] = Field(None, max_length=256 * 1024)  # 256 KB

class PasswordUpdate(PasswordCreate):
    pass


class PasswordResponse(PasswordBase):
    id: int
    encrypted_payload: str
    notes_encrypted: Optional[str] = None
    favicon_url: Optional[str] = None
    folder_id: Optional[int] = None
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


class TOTPConfirmRequest(BaseModel):
    user_id: Optional[int] = None
    code: str = Field(..., min_length=6, max_length=6, pattern=r'^\d{6}$')


class AuditResponse(BaseModel):
    id: int
    event: str
    meta: Dict[str, Any]
    created_at: datetime

    class Config:
        from_attributes = True
