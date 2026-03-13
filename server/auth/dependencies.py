from typing import Callable

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..models import User
from .exceptions import InvalidCredentials
from .service import decode_token, verify_hardened_otp

_oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")


def get_current_user(
    token: str = Depends(_oauth2_scheme),
    db: Session = Depends(get_db),
) -> User:
    """Resolve a Bearer JWT to a User row. Raises 401 on any failure."""
    payload = decode_token(token)

    user_id = payload.get("sub")
    if not user_id:
        raise InvalidCredentials()

    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        raise InvalidCredentials()

    return user


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

    user_id = payload.get("sub")
    if not user_id:
        raise InvalidCredentials()

    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        raise InvalidCredentials()

    return user


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
