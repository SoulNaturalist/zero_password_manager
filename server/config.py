import os
import sys


class Settings:
    PROJECT_NAME: str = "Zero Vault API"

    # OTP Configuration
    # Actions that require OTP verification (comma-separated string in .env)
    # Possible values: "login", "vault_read", "vault_write", "audit_read"
    _otp_list: str = os.getenv("PERMISSIONS_OTP_LIST", "login")
    PERMISSIONS_OTP_LIST: list[str] = [x.strip() for x in _otp_list.split(",") if x.strip()]

    # JWT Settings
    # SECURITY: ALGORITHM is intentionally NOT env-configurable to prevent
    # the "alg:none" JWT bypass attack.
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "7"))

    # CORS — set ALLOWED_ORIGINS in .env as comma-separated list, e.g.:
    # ALLOWED_ORIGINS=http://192.168.1.100:3000,http://localhost:3000
    _raw_origins: str = os.getenv("ALLOWED_ORIGINS", "")
    ALLOWED_ORIGINS: list[str] = (
        [o.strip() for o in _raw_origins.split(",") if o.strip()]
        if _raw_origins
        else []
    )

    # SECURITY: JWT_SECRET_KEY must be explicitly set in the environment.
    # A missing or weak secret allows forging tokens for any user.
    _raw_secret: str = os.getenv("JWT_SECRET_KEY", "")

    @property
    def JWT_SECRET_KEY(self) -> str:
        secret = self._raw_secret
        insecure_defaults = {
            "",
            "fallback_secret_key_for_development_only",
            "secret",
            "changeme",
        }
        if secret in insecure_defaults:
            raise RuntimeError(
                "[SECURITY] JWT_SECRET_KEY is not set or uses an insecure default. "
                "Generate a strong secret: python -c \"import secrets; print(secrets.token_hex(32))\" "
                "and add JWT_SECRET_KEY=<value> to your .env file."
            )
        return secret


settings = Settings()
