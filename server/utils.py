import urllib.parse
import ipaddress
from typing import Optional

from fastapi import Request

from .config import settings


# NOTE: the legacy `EncryptionService` (server-side seed-phrase encryption)
# was REMOVED as part of the zero-knowledge audit. The server must not hold
# a key capable of decrypting user secrets — that's the recovery-bypass
# anti-pattern flagged by the 2026 ETH Zurich password-manager research.
# All seed phrases are now stored exclusively as client-encrypted blobs
# (see /profile/seed-phrase in main.py and the `client:` storage prefix).
# The SEED_PHRASE_KEY env var is retained only because legacy DB rows from
# before this migration still exist; they are no longer decrypted server-side.


def get_client_ip(request: Request) -> str:
    """Return the real client IP, trusting X-Forwarded-For only from trusted proxies."""
    requester_ip = request.client.host if request.client else None
    if requester_ip:
        try:
            requester_addr = ipaddress.ip_address(requester_ip)
            for entry in settings.TRUSTED_PROXY_RANGES:
                try:
                    if "/" in entry:
                        if requester_addr in ipaddress.ip_network(entry, strict=False):
                            break
                    elif requester_ip == entry:
                        break
                except ValueError:
                    continue
            else:
                return requester_ip
        except ValueError:
            return requester_ip

    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        for hop in forwarded.split(","):
            candidate = hop.strip()
            try:
                ipaddress.ip_address(candidate)
                return candidate
            except ValueError:
                continue

    return requester_ip or "unknown"


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
