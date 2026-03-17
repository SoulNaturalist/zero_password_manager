from typing import Optional

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    login: str = Field(..., min_length=1, max_length=256)
    password: str = Field(..., min_length=1)
    device_info: Optional[dict] = None


class UserCreate(BaseModel):
    login: str
    password: str
    salt: Optional[str] = None


class UserResponse(BaseModel):
    id: int
    login: str
    salt: str
    totp_secret: Optional[str] = None
    totp_uri: Optional[str] = None

    model_config = {"from_attributes": True}


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
    code: str = Field(..., min_length=6, max_length=6, pattern=r'^\d{6}$')
    mfa_token: Optional[str] = None


class LoginPhase1Response(BaseModel):
    requires_mfa: bool
    mfa_token: Optional[str] = None
    salt: str
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None
