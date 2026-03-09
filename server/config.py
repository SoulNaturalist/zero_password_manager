import os
from typing import Optional


class Settings:
    PROJECT_NAME: str = "Zero Vault API"

    # OTP Configuration
    # Actions that require OTP verification (comma-separated string in .env)
    # Possible values: "login", "vault_read", "vault_write", "audit_read"
    _otp_list: str = os.getenv("PERMISSIONS_OTP_LIST", "login")
    PERMISSIONS_OTP_LIST: list[str] = [x.strip() for x in _otp_list.split(",") if x.strip()]

    # JWT Settings
    # JWT_SECRET_KEY must be set explicitly in every environment.
    # No fallback is provided — if the variable is absent the server refuses
    # to start, which prevents accidental use of a known/weak key.
    # Generate a secure value with:
    #   python -c "import secrets; print(secrets.token_hex(32))"
    _jwt_raw: Optional[str] = os.getenv("JWT_SECRET_KEY")
    if not _jwt_raw:
        raise RuntimeError(
            "JWT_SECRET_KEY environment variable is required and must not be empty. "
            "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
        )
    JWT_SECRET_KEY: str = _jwt_raw
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "7"))

    # Environment and Storage Configuration
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    MAX_PASSWORDS_PER_USER: int = int(os.getenv("MAX_PASSWORDS_PER_USER", "1000"))

    # Brute-force/Lockout Protection
    MAX_FAILED_OTP_ATTEMPTS: int = int(os.getenv("MAX_FAILED_OTP_ATTEMPTS", "5"))
    LOCKOUT_TIME_MINUTES: int = int(os.getenv("LOCKOUT_TIME_MINUTES", "15"))

    # Telegram Notifications (Security Alerts)
    TELEGRAM_BOT_TOKEN: Optional[str] = os.getenv("TELEGRAM_BOT_TOKEN")
    TELEGRAM_CHAT_ID: Optional[str] = os.getenv("TELEGRAM_CHAT_ID")
    CRITICAL_EVENTS: list[str] = [
        "account_locked",
        "passkey_login_failed",
        "2fa_enabled",
        "2fa_disabled",
        "device_revoked",
        "vault_delete",
        "passkey_registered",
        "password_create_limit_reached",
    ]

    # WebAuthn Configuration
    RP_ID: str = os.getenv("RP_ID", "localhost")
    RP_NAME: str = os.getenv("RP_NAME", "Zero Password Manager")
    EXPECTED_ORIGIN: str = os.getenv("EXPECTED_ORIGIN", "http://localhost")

    # CORS — no wildcard default; must be configured explicitly in production.
    # An empty ALLOWED_ORIGINS list causes FastAPI to reject cross-origin requests,
    # which is safe. Set ALLOWED_ORIGINS env var to a comma-separated list of
    # allowed origins (e.g. "https://app.example.com").
    _raw_origins: str = os.getenv("ALLOWED_ORIGINS", "")
    ALLOWED_ORIGINS: list[str] = [o.strip() for o in _raw_origins.split(",") if o.strip()]


settings = Settings()
