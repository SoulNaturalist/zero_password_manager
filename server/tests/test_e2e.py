import base64
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import pyotp
import pytest

pytestmark = pytest.mark.e2e


STRONG_PASSWORD = "Xk9#mPqR2$vLn5@hTjWs"


def _auth_headers(token: str, extra: dict[str, str] | None = None) -> dict[str, str]:
    headers = {"Authorization": f"Bearer {token}"}
    if extra:
        headers.update(extra)
    return headers


def _time_shifted_otp(secret: str, *, seconds_ahead: int) -> tuple[datetime, str]:
    future = datetime.now(timezone.utc) + timedelta(seconds=seconds_ahead)
    return future, pyotp.TOTP(secret).at(future)


def test_full_seed_and_vault_flow_e2e(client):
    register = client.post("/register", json={"login": "e2e-user", "password": STRONG_PASSWORD})
    assert register.status_code == 201
    register_data = register.json()

    enrollment_token = register_data["access_token"]
    setup = client.post("/setup_2fa", headers=_auth_headers(enrollment_token))
    assert setup.status_code == 200
    secret = setup.json()["secret"]

    first_code = pyotp.TOTP(secret).now()
    confirm = client.post(
        "/confirm_2fa",
        json={"code": first_code},
        headers=_auth_headers(enrollment_token),
    )
    assert confirm.status_code == 200
    confirm_data = confirm.json()
    access_token = confirm_data["access_token"]
    assert access_token
    assert confirm_data["refresh_token"]

    encrypted_payload = base64.b64encode(b"encrypted-password").decode()
    encrypted_notes = base64.b64encode(b"encrypted-notes").decode()
    encrypted_metadata = base64.b64encode(b"encrypted-metadata").decode()

    create_password = client.post(
        "/passwords",
        json={
            "site_hash": "hash:e2e",
            "encrypted_payload": encrypted_payload,
            "notes_encrypted": encrypted_notes,
            "encrypted_metadata": encrypted_metadata,
            "has_seed_phrase": False,
        },
        headers=_auth_headers(access_token),
    )
    assert create_password.status_code == 201
    password_id = create_password.json()["id"]

    read_passwords = client.get("/passwords", headers=_auth_headers(access_token))
    assert read_passwords.status_code == 200
    passwords = read_passwords.json()
    assert any(item["id"] == password_id for item in passwords)

    seed_ciphertext = base64.b64encode(b"client-side-seed-ciphertext").decode()
    seed_time, seed_code = _time_shifted_otp(secret, seconds_ahead=90)
    with patch("server.auth.service.datetime") as mocked_datetime:
        mocked_datetime.now.return_value = seed_time
        set_seed = client.post(
            "/profile/seed-phrase",
            json={"seed_phrase_encrypted": seed_ciphertext},
            headers=_auth_headers(access_token, {"X-OTP": seed_code}),
        )
    assert set_seed.status_code == 200
    assert set_seed.json()["success"] is True

    verify_time, verify_code = _time_shifted_otp(secret, seconds_ahead=150)
    with patch("server.auth.service.datetime") as mocked_datetime:
        mocked_datetime.now.return_value = verify_time
        seed_verify = client.post(
            "/api/v1/verify-totp",
            headers=_auth_headers(access_token, {"X-OTP": verify_code}),
            json={},
        )
    assert seed_verify.status_code == 200
    seed_access_token = seed_verify.json()["seed_access_token"]

    get_seed = client.get(
        "/profile/seed-phrase",
        headers={"Authorization": f"Bearer {seed_access_token}"},
    )
    assert get_seed.status_code == 200
    assert get_seed.json()["seed_phrase_encrypted"] == seed_ciphertext

    delete_password = client.delete(
        f"/passwords/{password_id}",
        headers=_auth_headers(access_token),
    )
    assert delete_password.status_code == 200
    assert delete_password.json()["status"] == "deleted"


def test_device_events_websocket_accepts_bearer_header_e2e(client):
    register = client.post("/register", json={"login": "ws-user", "password": STRONG_PASSWORD})
    assert register.status_code == 201
    access_token = register.json()["access_token"]

    with client.websocket_connect(
        "/ws/device-events",
        headers={"Authorization": f"Bearer {access_token}"},
    ) as websocket:
        websocket.send_text("ping")
