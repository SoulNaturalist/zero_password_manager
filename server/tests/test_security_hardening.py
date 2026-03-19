from starlette.requests import Request

from server.main import _get_webauthn_origin, app
from server.utils import get_client_ip


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
