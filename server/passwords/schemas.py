from datetime import datetime
from typing import Optional

from typing import Any

from pydantic import BaseModel, Field, field_validator

from .constants import MAX_PAYLOAD_BYTES


class PasswordCreate(BaseModel):
    site_url: str = Field(..., max_length=2048)
    site_login: str = Field(..., max_length=512)
    encrypted_payload: str = Field(..., max_length=MAX_PAYLOAD_BYTES)
    notes_encrypted: Optional[str] = Field(None, max_length=256 * 1024)
    has_2fa: bool = False
    has_seed_phrase: bool = False
    folder_id: Optional[int] = None


class PasswordUpdate(PasswordCreate):
    pass


class PasswordResponse(BaseModel):
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

    @field_validator("has_seed_phrase", mode="before")
    @classmethod
    def _suppress_seed_presence(cls, _: Any) -> bool:
        return False

    model_config = {"from_attributes": True}
