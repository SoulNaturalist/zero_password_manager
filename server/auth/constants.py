# Argon2id parameters — single source of truth, mirrored in security.py.
# Tuned above OWASP minimums (m=64 MB, t=3, p=1) to match a password-manager
# threat model where the master-password hash protects everything.
ARGON2_TIME_COST   = 4
ARGON2_MEMORY_COST = 131_072  # 128 MB
ARGON2_PARALLELISM = 2
ARGON2_HASH_LEN    = 32

# AES-256-GCM
AES_NONCE_LEN = 12  # 96-bit nonce

# ── Security Constants ────────────────────────────────────────────────────────

MAX_EXECUTION_TIME = 2.0  # seconds
MAX_FAILED_OTP_ATTEMPTS = 5
LOCKOUT_TIME_MINUTES = 15
