from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

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


class PasswordBase(BaseModel):
    site_url: str
    site_login: str
    has_2fa: bool = False
    has_seed_phrase: bool = False


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
    code: str


class AuditResponse(BaseModel):
    id: int
    event: str
    meta: Dict[str, Any]
    created_at: datetime

    class Config:
        from_attributes = True
