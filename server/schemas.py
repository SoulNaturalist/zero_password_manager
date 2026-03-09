import re
from datetime import datetime
from typing import Annotated, Any, Dict, List, Optional

from pydantic import BaseModel, Field
from pydantic import ConfigDict
from pydantic.functional_validators import AfterValidator


# ── Reusable field types ───────────────────────────────────────────────────────
# Defined once here so FolderCreate and FolderUpdate share the same validation
# logic without duplicating @field_validator methods.

_HEX_COLOR_RE = re.compile(r'^#[0-9A-Fa-f]{6}$')

_ALLOWED_ICONS = {
    'bank', 'cloud', 'code', 'crypto', 'email', 'favorite',
    'folder', 'gaming', 'home', 'lock', 'school', 'shopping_cart',
    'social', 'star', 'vpn_key', 'work',
}


def _check_hex_color(v: str) -> str:
    if not _HEX_COLOR_RE.match(v):
        raise ValueError("Must be a valid hex color, e.g. #5D52D2")
    return v


def _check_icon(v: str) -> str:
    if v not in _ALLOWED_ICONS:
        raise ValueError(f"Must be one of: {', '.join(sorted(_ALLOWED_ICONS))}")
    return v


HexColor = Annotated[str, AfterValidator(_check_hex_color)]
FolderIcon = Annotated[str, AfterValidator(_check_icon)]


# ── Auth schemas ──────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    login: str = Field(..., min_length=1, max_length=256)
    password: str = Field(..., min_length=1)


class UserCreate(BaseModel):
    login: str
    password: str


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    login: str
    salt: str
    totp_secret: Optional[str] = None
    totp_uri: Optional[str] = None


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


class TOTPSetupResponse(BaseModel):
    secret: str
    otp_uri: str


class TOTPConfirmRequest(BaseModel):
    user_id: Optional[int] = None
    code: str = Field(..., min_length=6, max_length=6, pattern=r'^\d{6}$')


# ── Folder schemas ────────────────────────────────────────────────────────────

class FolderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    color: HexColor = "#5D52D2"
    icon: FolderIcon = "folder"


class FolderUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=64)
    color: Optional[HexColor] = None
    icon: Optional[FolderIcon] = None


class FolderResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    color: str
    icon: str
    created_at: datetime
    updated_at: datetime
    password_count: int = 0


# ── Password schemas ──────────────────────────────────────────────────────────

class PasswordCreate(BaseModel):
    site_url: str = Field(..., max_length=2048)
    site_login: str = Field(..., max_length=512)
    encrypted_payload: str = Field(..., max_length=2 * 1024 * 1024)   # 2 MB
    notes_encrypted: Optional[str] = Field(None, max_length=256 * 1024)  # 256 KB
    has_2fa: bool = False
    has_seed_phrase: bool = False
    folder_id: Optional[int] = None


class PasswordUpdate(PasswordCreate):
    pass


class PasswordResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    site_url: str
    site_login: str
    encrypted_payload: str
    notes_encrypted: Optional[str] = None
    has_2fa: bool
    has_seed_phrase: bool
    folder_id: Optional[int] = None
    favicon_url: Optional[str] = None
    created_at: datetime
    updated_at: datetime


# ── Audit / history schemas ───────────────────────────────────────────────────

class HistoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    action_type: str
    action_details: Dict[str, Any]
    site_url: str
    favicon_url: Optional[str] = None
    created_at: datetime


class AuditResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    event: str
    meta: Dict[str, Any]
    created_at: datetime
