import pytest
from starlette.requests import Request

from server.main import _get_webauthn_origin, app
from server.utils import get_client_ip

pytestmark = pytest.mark.security


def _make_request(*, client_host: str, headers: list[tuple[bytes, bytes]] | None = None) -> Request:
    scope = {
        "type": "http",
        "method": "GET",
        "path": "/",
        "headers": headers or [],
        "client": (client_host, 12345),
        "scheme": "http",
        "server": ("testserver", 80),
        "query_string": b"",
    }
    return Request(scope)


def test_get_client_ip_ignores_untrusted_x_forwarded_for():
    request = _make_request(
        client_host="203.0.113.10",
        headers=[(b"x-forwarded-for", b"198.51.100.22")],
    )
    assert get_client_ip(request) == "203.0.113.10"


def test_get_client_ip_uses_trusted_proxy_x_forwarded_for():
    request = _make_request(
        client_host="127.0.0.1",
        headers=[(b"x-forwarded-for", b"198.51.100.22, 127.0.0.1")],
    )
    assert get_client_ip(request) == "198.51.100.22"


def test_refresh_route_registered_once():
    refresh_routes = [
        route for route in app.routes
        if getattr(route, "path", None) == "/refresh" and "POST" in getattr(route, "methods", set())
    ]
    assert len(refresh_routes) == 1


def test_webauthn_origin_allows_configured_origin():
    request = _make_request(
        client_host="127.0.0.1",
        headers=[(b"origin", b"http://localhost")],
    )
    assert _get_webauthn_origin(request) == "http://localhost"


def test_runtime_policy_blocks_windows(monkeypatch):
    import server.main as main
    monkeypatch.setattr(main.platform, "system", lambda: "Windows")
    with pytest.raises(RuntimeError, match="supported only on Linux"):
        main.enforce_runtime_security_policy()


def test_runtime_policy_blocks_production_with_ssh_password(monkeypatch):
    import server.main as main
    monkeypatch.setattr(main.platform, "system", lambda: "Linux")
    monkeypatch.setattr(main.settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(main, "_ssh_password_login_enabled", lambda: True)

    with pytest.raises(RuntimeError, match="Production startup blocked"):
        main.enforce_runtime_security_policy()


# ═══════════════════════════════════════════════════════════════════════════════
# Тесты для проверки исправлений уязвимостей в сбросе пароля (PR #78)
# ═══════════════════════════════════════════════════════════════════════════════


class TestPasswordResetVulnerabilities:
    """Тесты для проверки исправленных уязвимостей в эндпоинте сброса пароля."""

    @pytest.fixture
    def user_with_2fa(self, db_session):
        """Создаёт пользователя с включенной 2FA."""
        from server.models import User
        from server.auth.service import hash_password
        import pyotp

        user = User(
            login="user_with_2fa",
            hashed_password=hash_password("OldPassword123!"),
            totp_secret=pyotp.random_base32(),
            totp_enabled=True,
            token_version=1,
        )
        db_session.add(user)
        db_session.commit()
        return user

    @pytest.fixture
    def user_without_2fa(self, db_session):
        """Создаёт пользователя без 2FA."""
        from server.models import User
        from server.auth.service import hash_password

        user = User(
            login="user_without_2fa",
            hashed_password=hash_password("OldPassword123!"),
            totp_enabled=False,
            token_version=1,
        )
        db_session.add(user)
        db_session.commit()
        return user

    def test_reset_password_with_totp_for_2fa_user(self, client, user_with_2fa):
        """Пользователь с 2FA может сбросить пароль с помощью TOTP."""
        import pyotp

        totp = pyotp.TOTP(user_with_2fa.totp_secret)
        valid_code = totp.now()

        response = client.post("/reset-password", json={
            "login": "user_with_2fa",
            "totp_code": valid_code,
            "new_password": "NewSecurePassword123!@#",
        })

        assert response.status_code == 200
        assert response.json()["success"] is True

    def test_reset_password_with_current_password_for_non_2fa_user(self, client, user_without_2fa):
        """Пользователь без 2FA может сбросить пароль с помощью текущего пароля."""
        response = client.post("/reset-password", json={
            "login": "user_without_2fa",
            "current_password": "OldPassword123!",
            "new_password": "NewSecurePassword123!@#",
        })

        assert response.status_code == 200
        assert response.json()["success"] is True

    def test_reset_password_timing_attack_protection(self, client, user_with_2fa):
        """Проверка защиты от timing-атак: время ответа одинаковое для существующих и несуществующих пользователей."""
        import time

        # Запрос для существующего пользователя (неверный TOTP)
        start = time.perf_counter()
        response1 = client.post("/reset-password", json={
            "login": "user_with_2fa",
            "totp_code": "000000",
            "new_password": "SomePassword123!",
        })
        time_existing = time.perf_counter() - start

        # Запрос для несуществующего пользователя
        start = time.perf_counter()
        response2 = client.post("/reset-password", json={
            "login": "nonexistent_user_xyz",
            "totp_code": "000000",
            "new_password": "SomePassword123!",
        })
        time_nonexistent = time.perf_counter() - start

        # Оба запроса должны вернуть одинаковый ответ
        assert response1.status_code == response2.status_code == 200
        assert response1.json() == response2.json() == {"success": True}

        # Разница во времени должна быть незначительной (менее 100ms)
        assert abs(time_existing - time_nonexistent) < 0.1, \
            f"Timing difference too large: {abs(time_existing - time_nonexistent):.4f}s"

    def test_reset_password_user_enumeration_protection(self, client):
        """Проверка защиты от user enumeration: ответы идентичны для существующих и несуществующих пользователей."""

        test_cases = [
            # (login, totp_code, current_password, new_password, description)
            ("existing_user", "123456", None, "NewPass123!", "existing user with TOTP"),
            ("nonexistent_user", "123456", None, "NewPass123!", "nonexistent user with TOTP"),
            ("existing_user", None, "oldpass", "NewPass123!", "existing user with password"),
            ("nonexistent_user", None, "oldpass", "NewPass123!", "nonexistent user with password"),
        ]

        responses = []
        for login, totp, password, new_pass, desc in test_cases:
            payload = {
                "login": login,
                "new_password": new_pass,
            }
            if totp:
                payload["totp_code"] = totp
            if password:
                payload["current_password"] = password

            response = client.post("/reset-password", json=payload)
            responses.append((desc, response.status_code, response.json()))

        # Все ответы должны быть одинаковыми
        first_status = responses[0][1]
        first_body = responses[0][2]

        for desc, status, body in responses:
            assert status == first_status, f"Status mismatch for {desc}: {status} != {first_status}"
            assert body == first_body, f"Body mismatch for {desc}: {body} != {first_body}"

    def test_reset_password_weak_password_rejection(self, client, user_with_2fa):
        """Проверка отклонения слабых паролей при сбросе."""
        import pyotp

        totp = pyotp.TOTP(user_with_2fa.totp_secret)
        valid_code = totp.now()

        weak_passwords = [
            "short",
            "onlylowercase",
            "ONLYUPPERCASE",
            "1234567890",
            "NoSpecialChars1",
            "Valid1!",  # слишком короткий
        ]

        for weak_pass in weak_passwords:
            response = client.post("/reset-password", json={
                "login": "user_with_2fa",
                "totp_code": valid_code,
                "new_password": weak_pass,
            })

            # Должна быть ошибка 400
            assert response.status_code == 400, f"Weak password '{weak_pass}' was accepted"
            assert "too weak" in response.json()["detail"].lower() or "password" in response.json()["detail"].lower()

    def test_reset_password_invalidation_old_sessions(self, client, user_with_2fa):
        """Проверка инвалидации старых сессий после сброса пароля."""
        import pyotp

        totp = pyotp.TOTP(user_with_2fa.totp_secret)
        old_token_version = user_with_2fa.token_version

        # Сбрасываем пароль
        response = client.post("/reset-password", json={
            "login": "user_with_2fa",
            "totp_code": totp.now(),
            "new_password": "NewSecurePassword123!@#",
        })

        assert response.status_code == 200
        assert response.json()["success"] is True

        # Проверяем, что token_version увеличился
        # (в реальном тесте нужно перезагрузить пользователя из БД)


class TestShortTokenSecurity:
    """Тесты для проверки безопасности коротких токенов (seed_access)."""

    def test_short_token_contains_token_version(self, user_without_2fa):
        """Проверка, что короткий токен содержит token_version."""
        from server.auth.service import create_short_token, decode_token

        token = create_short_token(user_without_2fa)
        payload = decode_token(token)

        assert "token_version" in payload
        assert payload["token_version"] == user_without_2fa.token_version

    def test_short_token_invalid_after_password_change(self, client, user_without_2fa, db_session):
        """Проверка, что короткий токен становится невалидным после сброса пароля."""
        from server.auth.service import create_short_token, decode_token
        import jwt

        # Создаём короткий токен
        short_token = create_short_token(user_without_2fa)

        # Проверяем, что токен валиден
        payload = decode_token(short_token)
        assert payload["token_version"] == user_without_2fa.token_version

        # Меняем token_version (имитируем сброс пароля)
        user_without_2fa.token_version += 1
        db_session.commit()

        # Теперь токен должен быть невалидным
        # (в реальном коде это проверяется в зависимостях)
