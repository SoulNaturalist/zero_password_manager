import os

# ── Helpers ───────────────────────────────────────────────────────────────────

_INSECURE_SECRETS = frozenset({
    "",
    "secret",
    "changeme",
    "fallback_secret_key_for_development_only",
})


def _parse_list(raw: str) -> list[str]:
    """Split a comma-separated env-var string into a clean list."""
    return [item.strip() for item in raw.split(",") if item.strip()]


def _load_jwt_secret() -> str:
    """Read JWT_SECRET_KEY from env; raise immediately if missing or insecure."""
    secret = os.getenv("JWT_SECRET_KEY", "")
    if secret in _INSECURE_SECRETS:
        raise RuntimeError(
            "[SECURITY] JWT_SECRET_KEY is not set or uses an insecure default.\n"
            "Generate one:  python -c \"import secrets; print(secrets.token_hex(32))\"\n"
            "Then add       JWT_SECRET_KEY=<value>  to your .env file."
        )
    return secret


# ── Settings ──────────────────────────────────────────────────────────────────

class Settings:
    """
    Application settings loaded from environment variables at startup.

    All attributes are class-level so the object behaves as a simple namespace.
    Startup fails immediately (fail-fast) if critical values are missing.
    """

    # JWT — ALGORITHM is intentionally NOT configurable to prevent the alg:none attack.
    ALGORITHM: str = "HS256"
    JWT_SECRET_KEY: str = _load_jwt_secret()
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "7"))

    # CORS — comma-separated list of allowed origins, e.g.:
    #   ALLOWED_ORIGINS=http://192.168.1.100:8080,http://localhost:8080
    ALLOWED_ORIGINS: list[str] = _parse_list(os.getenv("ALLOWED_ORIGINS", ""))

    # Operations that require a fresh OTP code in addition to a valid JWT.
    # Possible values: login, vault_read, vault_write, audit_read, history_read
    PERMISSIONS_OTP_LIST: list[str] = _parse_list(
        os.getenv("PERMISSIONS_OTP_LIST", "login")
    )


settings = Settings()
