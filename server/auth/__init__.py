# Re-export public auth API so that `from . import auth` in main.py can reach
# all symbols via `auth.<symbol>` without knowing the internal module layout.

from .dependencies import get_current_user
from .service import (
    create_access_token,
    create_refresh_token,
    decode_token,
    generate_salt,
    hash_password,
    verify_password,
)

# Legacy alias: some call sites use auth.get_password_hash
get_password_hash = hash_password

__all__ = [
    "create_access_token",
    "create_refresh_token",
    "decode_token",
    "generate_salt",
    "get_current_user",
    "get_password_hash",
    "hash_password",
    "verify_password",
]
