import base64
import os
import urllib.parse
from typing import Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import Request

from .config import settings


class EncryptionService:
    @staticmethod
    def _get_key() -> bytes:
        # Ensure key is 32 bytes for AesGcm
        key_str = settings.SEED_PHRASE_KEY
        key_bytes = key_str.encode()
        if len(key_bytes) < 32:
            return key_bytes.ljust(32, b'\0')
        return key_bytes[:32]

    @classmethod
    def encrypt(cls, plaintext: str) -> str:
        if not plaintext:
            return ""
        aesgcm = AESGCM(cls._get_key())
        nonce = os.urandom(12)
        ciphertext = aesgcm.encrypt(nonce, plaintext.encode(), None)
        return base64.b64encode(nonce + ciphertext).decode()

    @classmethod
    def decrypt(cls, encrypted_b64: str) -> str:
        if not encrypted_b64:
            return ""
        try:
            data = base64.b64decode(encrypted_b64)
            nonce = data[:12]
            ciphertext = data[12:]
            aesgcm = AESGCM(cls._get_key())
            decrypted = aesgcm.decrypt(nonce, ciphertext, None)
            return decrypted.decode()
        except Exception:
            return ""


def get_client_ip(request: Request) -> str:
    """Return the real client IP, respecting X-Forwarded-For from trusted proxies."""
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def get_favicon_url(site_url: Optional[str]) -> Optional[str]:
    """Return a Clearbit logo URL for a domain, or None if the URL is unusable."""
    if not site_url:
        return None
    try:
        if not site_url.startswith(("http://", "https://")):
            site_url = "https://" + site_url
        parsed = urllib.parse.urlparse(site_url)
        domain = parsed.netloc.lower() or parsed.path.split("/")[0].lower()
        domain = domain.removeprefix("www.")
        if not domain or "." not in domain:
            return None
        # Switch to Icon Horse for higher quality (256px)
        return f"https://icon.horse/icon/{domain}?size=large"
    except Exception:
        return None


def attach_favicons(entries: list) -> None:
    """Attach a transient favicon_url to each item in a list of password-like objects."""
    for entry in entries:
        entry.favicon_url = get_favicon_url(entry.site_url)
