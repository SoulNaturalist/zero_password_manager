"""
Test fixtures.

env vars must be set BEFORE any server module is imported because
config.py evaluates os.getenv() at class-definition time (module level).
"""
import base64
import os

os.environ.setdefault("JWT_SECRET_KEY", "a" * 64)
os.environ.setdefault("SEED_PHRASE_KEY", base64.b64encode(b"s" * 32).decode())
os.environ.setdefault("TOTP_MASTER_KEY", base64.b64encode(b"t" * 32).decode())
os.environ.setdefault("DEVICE_SECRET", "d" * 64)
os.environ.setdefault("PERMISSIONS_OTP_LIST", "")  # no MFA gate on login by default

from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from sqlalchemy.pool import StaticPool

from server.database import Base, get_db
from server.main import app

# StaticPool ensures all SQLAlchemy operations share the SAME underlying
# connection, which is required for in-memory SQLite (each new connection
# would otherwise get an independent, empty database).
_ENGINE = create_engine(
    "sqlite:///:memory:",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
_Session = sessionmaker(autocommit=False, autoflush=False, bind=_ENGINE)


@pytest.fixture()
def db_session():
    Base.metadata.create_all(bind=_ENGINE)
    session = _Session()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=_ENGINE)


@pytest.fixture()
def client(db_session):
    def _override():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = _override

    # Disable rate limiting: replace _check_request_limit with a no-op that
    # still satisfies slowapi's expectation of request.state.view_rate_limit.
    from slowapi import Limiter as _Limiter

    def _noop_check(self, request, endpoint_func, in_middleware=True):
        request.state.view_rate_limit = (None, "unlimited")

    # Disable constant-time delays so tests run fast
    with patch("server.auth.router.constant_time_response"), \
         patch("server.security.SecurityManager.constant_time_delay"), \
         patch.object(_Limiter, "_check_request_limit", _noop_check):
        with TestClient(app, raise_server_exceptions=True) as c:
            yield c
    app.dependency_overrides.clear()
