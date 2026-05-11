import logging
from typing import Callable, Optional

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import User
from .exceptions import InvalidCredentials
from .service import decode_token, verify_hardened_otp

_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")
_oauth2_scheme_optional = OAuth2PasswordBearer(tokenUrl="login", auto_error=False)
_log = logging.getLogger(__name__)


def _user_from_access_claims(payload: dict, db: Session) -> User: 
    from .. import crud  # local import — avoids circular module dependency

    jti = payload.get("jti")
    if jti and crud.is_token_blacklisted(db, jti):
        _log.warning("access_claims: token jti=%s is blacklisted", jti)
        raise InvalidCredentials()

    user_id = payload.get("sub")
    if not user_id:
        _log.warning("access_claims: missing 'sub' claim")
        raise InvalidCredentials()

    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        _log.warning("access_claims: user id=%s not found in DB", user_id)
        raise InvalidCredentials()

    token_ver = payload.get("token_version")
    if token_ver != user.token_version:
        _log.warning(
            "access_claims: token_version mismatch — token=%r db=%r user_id=%s",
            token_ver,
            user.token_version,
            user_id,
        )
        raise InvalidCredentials()

    return user


def _resolve_user_from_token(token: str, db: Session) -> User: 
    try:
        payload = decode_token(token)
    except Exception as exc:
        _log.warning("resolve_user: decode_token failed — %s", exc)
        raise InvalidCredentials() 

    return _user_from_access_claims(payload, db)


def get_current_user(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Resolve a Bearer JWT to a User row. Raises 401 on any failure."""
    return _resolve_user_from_token(token, db)


def get_current_user_optional(
    token: Optional[str] = Depends(_oauth2_scheme_optional),
    db: Session = Depends(get_db),
) -> Optional[User]:
    """Like get_current_user but returns None when no Authorization header is present."""
    if token is None:
        return None
    return _resolve_user_from_token(token, db)


def get_seed_access_user(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Specialized dependency that verifies a short-lived 'seed_access' token."""
    payload = decode_token(token)

    if payload.get("scope") != "seed_access":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Valid TOTP verification required"
        )

    return _user_from_access_claims(payload, db)


def require_otp_for(permission: str) -> Callable:
    """
    Dependency factory: authenticates the request and, when *permission* is
    listed in PERMISSIONS_OTP_LIST, additionally validates the X-OTP header.

    Usage:
        current_user: User = Depends(require_otp_for("vault_read"))

    FastAPI caches dependency results within a request scope, so the JWT
    lookup from get_current_user runs only once even when chained.
    """
    def guard(
        request: Request,
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
    ) -> User:
        if permission in settings.PERMISSIONS_OTP_LIST:
            verify_hardened_otp(db, current_user, request.headers.get("X-OTP"))
        return current_user

    return guard
