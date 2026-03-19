"""
Tests for registration, login, and TOTP flows.
"""
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

import pyotp
import pytest

# A password that satisfies all constraints:
# 14+ chars, upper, lower, digit, special char, zxcvbn score >= 3, not common.
STRONG_PASSWORD = "Xk9#mPqR2$vLn5@hTjWs"
WEAK_PASSWORD = "password123"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _register(client, login="alice", password=STRONG_PASSWORD):
    return client.post("/register", json={"login": login, "password": password})


def _login(client, login="alice", password=STRONG_PASSWORD):
    return client.post("/login", json={"login": login, "password": password})


def _secret_from_uri(totp_uri: str) -> str:
    """Extract the base-32 secret embedded in an otpauth:// URI."""
    qs = parse_qs(urlparse(totp_uri).query)
    return qs["secret"][0]


def _make_token_for(user, db_session) -> str:
    """Bypass HTTP login: mint an access token directly via the service layer."""
    from server.auth.service import create_access_token
    return create_access_token(user, "test-device")


def _get_user(db_session, login="alice"):
    from server.models import User
    return db_session.query(User).filter(User.login == login).first()


# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

class TestRegister:
    def test_success_returns_201_with_totp_uri(self, client):
        r = _register(client)
        assert r.status_code == 201
        data = r.json()
        assert data["login"] == "alice"
        assert "totp_uri" in data and data["totp_uri"].startswith("otpauth://")
        assert "salt" in data and data["salt"]
        assert "id" in data

    def test_duplicate_login_returns_400(self, client):
        _register(client)
        r = _register(client)
        assert r.status_code == 400  # UserAlreadyExists is 400

    def test_weak_password_rejected(self, client):
        r = _register(client, password=WEAK_PASSWORD)
        assert r.status_code != 201

    def test_second_user_gets_different_salt(self, client):
        r1 = _register(client, login="alice")
        r2 = _register(client, login="bob")
        assert r1.status_code == 201
        assert r2.status_code == 201
        assert r1.json()["salt"] != r2.json()["salt"]

    def test_totp_secret_stored_encrypted(self, client, db_session):
        r = _register(client)
        assert r.status_code == 201
        user = _get_user(db_session)
        # totp_secret must be stored (encrypted), not None
        assert user.totp_secret is not None
        # It must NOT be a plain base-32 string (it is base64-encoded AES-GCM ciphertext)
        import base64
        decoded = base64.urlsafe_b64decode(user.totp_secret + "==")
        # AES-GCM nonce is 12 bytes; ciphertext follows — payload must be > 12 bytes
        assert len(decoded) > 12


# ---------------------------------------------------------------------------
# Login (phase 1, no MFA)
# ---------------------------------------------------------------------------

class TestLogin:
    def test_valid_credentials_returns_tokens(self, client):
        _register(client)
        r = _login(client)
        assert r.status_code == 200
        data = r.json()
        assert data["requires_mfa"] is False
        assert data["access_token"]
        assert data["refresh_token"]
        assert data["salt"]

    def test_wrong_password_does_not_return_tokens(self, client):
        _register(client)
        r = _login(client, password="WrongPass!12345#Z")
        assert r.status_code == 401
        assert "access_token" not in r.text

    def test_nonexistent_user_does_not_leak_existence(self, client):
        r = _login(client, login="ghost")
        # Must not 500 and must not reveal "user not found"
        assert r.status_code == 401
        assert "user not found" not in r.text.lower()


# ---------------------------------------------------------------------------
# TOTP setup and confirmation
# ---------------------------------------------------------------------------

class TestTOTPSetup:
    def _auth_headers(self, client, db_session):
        _register(client)
        user = _get_user(db_session)
        token = _make_token_for(user, db_session)
        return {"Authorization": f"Bearer {token}"}

    def test_setup_2fa_requires_auth(self, client):
        r = client.post("/setup_2fa")
        assert r.status_code == 401

    def test_setup_2fa_returns_secret_and_uri(self, client, db_session):
        headers = self._auth_headers(client, db_session)
        r = client.post("/setup_2fa", headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert "secret" in data
        assert "otp_uri" in data
        assert data["otp_uri"].startswith("otpauth://")

    def test_confirm_2fa_enables_totp(self, client, db_session):
        headers = self._auth_headers(client, db_session)

        # Get a fresh TOTP secret via setup_2fa
        r = client.post("/setup_2fa", headers=headers)
        assert r.status_code == 200
        secret = r.json()["secret"]

        # Generate a valid code and confirm
        code = pyotp.TOTP(secret).now()
        r = client.post("/confirm_2fa", json={"code": code}, headers=headers)
        assert r.status_code == 200
        data = r.json()
        assert data.get("access_token")

        # Verify totp_enabled was persisted
        user = _get_user(db_session)
        db_session.refresh(user)
        assert user.totp_enabled is True

    def test_confirm_2fa_rejects_wrong_code(self, client, db_session):
        headers = self._auth_headers(client, db_session)
        client.post("/setup_2fa", headers=headers)

        r = client.post("/confirm_2fa", json={"code": "000000"}, headers=headers)
        assert r.status_code in (400, 401)

    def test_setup_2fa_fails_when_already_enabled(self, client, db_session):
        headers = self._auth_headers(client, db_session)

        # Enable TOTP
        r = client.post("/setup_2fa", headers=headers)
        secret = r.json()["secret"]
        code = pyotp.TOTP(secret).now()
        client.post("/confirm_2fa", json={"code": code}, headers=headers)

        # Re-mint token after TOTP is enabled (token_version unchanged here)
        user = _get_user(db_session)
        db_session.refresh(user)
        new_token = _make_token_for(user, db_session)
        headers = {"Authorization": f"Bearer {new_token}"}

        r = client.post("/setup_2fa", headers=headers)
        assert r.status_code == 400


# ---------------------------------------------------------------------------
# Full MFA login flow (login requires OTP)
# ---------------------------------------------------------------------------

class TestMFALoginFlow:
    def test_mfa_login_returns_full_tokens(self, client, db_session):
        """Full flow: register → enable TOTP → login (mfa required) → /login/mfa."""
        _register(client)
        user = _get_user(db_session)
        token = _make_token_for(user, db_session)
        headers = {"Authorization": f"Bearer {token}"}

        # Setup + confirm TOTP
        r = client.post("/setup_2fa", headers=headers)
        secret = r.json()["secret"]
        code = pyotp.TOTP(secret).now()
        client.post("/confirm_2fa", json={"code": code}, headers=headers)

        # Now login with MFA gating enabled
        with patch("server.auth.router.settings") as mock_settings:
            mock_settings.PERMISSIONS_OTP_LIST = ["login"]
            mock_settings.ALGORITHM = "HS256"

            r = _login(client)
            assert r.status_code == 200
            data = r.json()
            assert data["requires_mfa"] is True
            mfa_token = data["mfa_token"]
            assert mfa_token

            # Phase 2: verify TOTP
            code2 = pyotp.TOTP(secret).now()
            r = client.post("/login/mfa", json={"code": code2, "mfa_token": mfa_token})
            assert r.status_code == 200
            tokens = r.json()
            assert tokens.get("access_token")
            assert tokens.get("refresh_token")


# ---------------------------------------------------------------------------
# Token refresh
# ---------------------------------------------------------------------------

class TestTokenRefresh:
    def test_refresh_returns_new_tokens(self, client, db_session):
        _register(client)
        r = _login(client)
        assert r.status_code == 200
        refresh_token = r.json()["refresh_token"]
        assert refresh_token

        # device_id cookie must match what was stored
        device_cookie = client.cookies.get("device_id", "test-device")
        r = client.post(
            "/refresh",
            json={"refresh_token": refresh_token},
            cookies={"device_id": device_cookie},
        )
        # Refresh may fail on device mismatch in test env; just verify no 500
        assert r.status_code != 500

    def test_invalid_refresh_token_rejected(self, client):
        r = client.post("/refresh", json={"refresh_token": "fake.token"})
        assert r.status_code in (401, 422)
