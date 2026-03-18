import os
from typing import Optional
from dotenv import load_dotenv
import logging

# Centralized Logging for config
logger = logging.getLogger("zero_vault.config")

# Try loading from various locations to ensure BOT_TOKEN is found
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

class Settings:
    PROJECT_NAME: str = "Zero Vault API"
    
    # OTP Configuration
    # Actions that require OTP verification (comma-separated string in .env)
    # Possible values: "login", "vault_read", "vault_write", "audit_read"
    _otp_list: str = os.getenv("PERMISSIONS_OTP_LIST", "login")
    PERMISSIONS_OTP_LIST: list[str] = [x.strip() for x in _otp_list.split(",") if x.strip()]
    
    # JWT Settings (MANDATORY: No fallbacks)
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "")
    ALGORITHM: str = "HS256"  # Locked for security
    ACCESS_TOKEN_EXPIRE_MINUTES: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", str(60 * 24 * 30)))
    REFRESH_TOKEN_EXPIRE_DAYS: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "365"))
    
    # Critical Keys (MANDATORY: No fallbacks)
    SEED_PHRASE_KEY: str = os.getenv("SEED_PHRASE_KEY", "")
    TOTP_MASTER_KEY: str = os.getenv("TOTP_MASTER_KEY", "")
    DEVICE_SECRET: str = os.getenv("DEVICE_SECRET", "")
    BLOCK_CLEANUP_INTERVAL_HOURS: int = int(os.getenv("BLOCK_CLEANUP_INTERVAL_HOURS", "1"))

    def __init__(self):
        # Validate critical security infrastructure
        if not self.JWT_SECRET_KEY:
            raise RuntimeError("CRITICAL ERROR: JWT_SECRET_KEY is not set in environment!")
            
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
        "vault_import",
        "vault_update",
        "profile_updated",
        "passkey_login_success",
        "vault_create",
        "register",
        "backend_changed_confirmed"
    ]

    # WebAuthn Configuration
    RP_ID: str = os.getenv("RP_ID", "localhost")
    RP_NAME: str = os.getenv("RP_NAME", "Zero Password Manager")
    # For Flutter, the origin is usually the app's package name or a specific URL
    # For local development with a proxy/web, it might be http://localhost:PORT
    EXPECTED_ORIGIN: str = os.getenv("EXPECTED_ORIGIN", "http://localhost")
    ALLOWED_ORIGINS: list[str] = os.getenv("ALLOWED_ORIGINS", "*").split(",")
    _whitelist: str = os.getenv("WHITELIST_IPS", "127.0.0.1,::1")
    WHITELIST_IPS: list[str] = [x.strip() for x in _whitelist.split(",") if x.strip()]

settings = Settings()
