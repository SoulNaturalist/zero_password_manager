import re
from datetime import datetime
from typing import Annotated, Optional

from pydantic import BaseModel, Field
from pydantic.functional_validators import AfterValidator

# ── Reusable annotated types ──────────────────────────────────────────────────

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


HexColor  = Annotated[str, AfterValidator(_check_hex_color)]
FolderIcon = Annotated[str, AfterValidator(_check_icon)]


# ── Schemas ───────────────────────────────────────────────────────────────────

class FolderCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    color: HexColor = "#5D52D2"
    icon: FolderIcon = "folder"
    is_hidden: bool = False


class FolderUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=1, max_length=64)
    color: Optional[HexColor] = None
    icon: Optional[FolderIcon] = None
    is_hidden: Optional[bool] = None


class FolderResponse(BaseModel):
    id: int
    name: str
    color: str
    icon: str
    is_hidden: bool = False
    created_at: datetime
    updated_at: datetime
    password_count: int = 0

    model_config = {"from_attributes": True}
