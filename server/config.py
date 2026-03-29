import os
from typing import Optional, Any
from dotenv import load_dotenv
import logging

# Centralized Logging for config
logger = logging.getLogger("zero_vault.config")

# Try loading from various locations to ensure .env is found
dotenv_paths = [
    ".env",
    "deployer/.env",
    "server/.env",
    "env.local",
    "env.dev",
    "env.prod"
]
for path in dotenv_paths:
    if os.path.exists(path):
        load_dotenv(path)
        logger.info(f"Loaded environment variables from: {path}")

def get_env(key: str, default: Any = None, mandatory: bool = True) -> Any:
    """
    Helper to get environment variables.
    If mandatory is True and key is missing, raises RuntimeError.
    """
    value = os.getenv(key)
    if value is None:
        if mandatory:
            raise RuntimeError(f"CRITICAL ERROR: Mandatory environment variable '{key}' is NOT set!")
        return default
    return value

class Settings:
    PROJECT_NAME: str = "Zero Vault API"
    ENVIRONMENT: str = get_env("ENVIRONMENT", "development", mandatory=False)
    
    # Database (MANDATORY)
    DATABASE_URL: str = get_env("DATABASE_URL")
    
    # OTP Configuration
    _otp_list: str = get_env("PERMISSIONS_OTP_LIST", "login", mandatory=False)
    PERMISSIONS_OTP_LIST: list[str] = [x.strip() for x in _otp_list.split(",") if x.strip()]
    
    # JWT Settings (MANDATORY: No fallbacks)
    JWT_SECRET_KEY: str = get_env("JWT_SECRET_KEY")
    ALGORITHM: str = "HS256"  # Locked for security
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(get_env("ACCESS_TOKEN_EXPIRE_MINUTES", "15", mandatory=False))
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(get_env("REFRESH_TOKEN_EXPIRE_DAYS", "7", mandatory=False))
    
    # Critical Keys (MANDATORY: No fallbacks)
    SEED_PHRASE_KEY: str = get_env("SEED_PHRASE_KEY")
    TOTP_MASTER_KEY: str = get_env("TOTP_MASTER_KEY")
    DEVICE_SECRET: str = get_env("DEVICE_SECRET")
    BLOCK_CLEANUP_INTERVAL_HOURS: int = int(get_env("BLOCK_CLEANUP_INTERVAL_HOURS", "1", mandatory=False))

    def __init__(self):
        # Validate critical security infrastructure
        if len(self.JWT_SECRET_KEY) < 64:
            raise RuntimeError(
                f"CRITICAL SECURITY ERROR: JWT_SECRET_KEY is too weak! "
                f"Current length: {len(self.JWT_SECRET_KEY)} characters. "
                f"Required: at least 64 characters (512 bits) for HS256 maximum entropy."
            )
            
        if not self.SEED_PHRASE_KEY or not self.TOTP_MASTER_KEY or not self.DEVICE_SECRET:
            missing = [k for k, v in {
                "SEED_PHRASE_KEY": self.SEED_PHRASE_KEY,
                "TOTP_MASTER_KEY": self.TOTP_MASTER_KEY,
                "DEVICE_SECRET": self.DEVICE_SECRET
            }.items() if not v]
            raise RuntimeError(f"CRITICAL ERROR: Missing essential security keys: {', '.join(missing)}")

    # Environment and Storage Configuration
    MAX_PASSWORDS_PER_USER: int = int(get_env("MAX_PASSWORDS_PER_USER", "1000", mandatory=False))
    
    # Brute-force/Lockout Protection
    MAX_FAILED_OTP_ATTEMPTS: int = int(get_env("MAX_FAILED_OTP_ATTEMPTS", "5", mandatory=False))
    LOCKOUT_TIME_MINUTES: int = int(get_env("LOCKOUT_TIME_MINUTES", "15", mandatory=False))

    # Telegram Notifications (Security Alerts)
    TELEGRAM_BOT_TOKEN: Optional[str] = get_env("TELEGRAM_BOT_TOKEN", mandatory=False)
    TELEGRAM_CHAT_ID: Optional[str] = get_env("TELEGRAM_CHAT_ID", mandatory=False)
    CRITICAL_EVENTS: list[str] = [
        "account_locked", "passkey_login_failed", "2fa_enabled", "2fa_disabled",
        "device_revoked", "vault_delete", "passkey_registered",
        "password_create_limit_reached", "vault_import", "vault_update",
        "profile_updated", "passkey_login_success", "vault_create", "register",
        "backend_changed_confirmed"
    ]

    # WebAuthn Configuration
    RP_ID: str = get_env("RP_ID", "localhost", mandatory=False)
    RP_NAME: str = get_env("RP_NAME", "Zero Password Manager", mandatory=False)
    EXPECTED_ORIGIN: str = get_env("EXPECTED_ORIGIN", "http://localhost", mandatory=False)
    
    _webauthn_origins: str = get_env("WEBAUTHN_ALLOWED_ORIGINS", EXPECTED_ORIGIN, mandatory=False)
    WEBAUTHN_ALLOWED_ORIGINS: list[str] = [x.strip() for x in _webauthn_origins.split(",") if x.strip()]
    
    ALLOWED_ORIGINS: list[str] = get_env("ALLOWED_ORIGINS", "*", mandatory=False).split(",")
    
    _whitelist: str = get_env("WHITELIST_IPS", "127.0.0.1,::1", mandatory=False)
    WHITELIST_IPS: list[str] = [x.strip() for x in _whitelist.split(",") if x.strip()]
    
    _trusted_proxies: str = get_env("TRUSTED_PROXY_RANGES", "127.0.0.1,::1", mandatory=False)
    TRUSTED_PROXY_RANGES: list[str] = [x.strip() for x in _trusted_proxies.split(",") if x.strip()]

settings = Settings()
