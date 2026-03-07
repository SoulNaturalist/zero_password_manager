import os

class Settings:
    PROJECT_NAME: str = "Zero Vault API"
    
    # OTP Configuration
    # Actions that require OTP verification
    # Possible values: "login", "vault_read", "vault_write", "audit_read"
    PERMISSIONS_OTP_LIST: list[str] = ["login"]
    
    # JWT Settings
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "fallback_secret_key_for_development_only")
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 15
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

settings = Settings()
