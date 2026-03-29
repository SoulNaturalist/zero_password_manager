# Zero Vault - Core Architecture & Security Design (v0.2.1)

Zero Vault is a high-security, open-source credential manager built on a **true Zero-Knowledge Architecture**.  
The server never sees the master key, plaintext passwords, or any metadata that could reveal which services the user is using.

---

## 🛡️ Security Architecture

### 1. Zero-Knowledge & Key Derivation (client-side only)
All cryptographic operations happen **exclusively on the device**:

- **KDF**: Argon2id (default) with PBKDF2-SHA256 fallback (100,000+ iterations).
- **Salt**: 16-byte cryptographically secure random salt generated once during registration.
- **Derived keys**:
  - `master_key` — used for AES-256-GCM encryption of the entire vault.
  - `auth_hash` — sent to the server and stored as an Argon2 hash.

**Important**: The master key **never leaves the device** and is never stored in plaintext.

### 2. Data Encryption (AES-256-GCM)
- **Algorithm**: AES-256-GCM (AEAD — confidentiality + integrity).
- **IV**: 12-byte random nonce generated for every encryption operation.
- **Tag**: 16-byte authentication tag.
- All encryption/decryption is performed in `lib/services/vault_service.dart` **before** any data is sent to the server.

### 3. Metadata Blinding
- URLs, usernames, and site names are stored as HMAC-SHA256 (key = master_key).
- The server sees only 64-character hex strings — impossible to infer which services the user has.

---

## 🏗️ Backend System Design (FastAPI v0.2.1)

### 1. Hardened Configuration
`config.py` + `.env`:
- Critical secrets are validated at startup (`JWT_SECRET_KEY` must be ≥ 32 characters).
- Automatic DB selection via `DATABASE_URL`:
  - `sqlite+aiosqlite:///./zero_vault.db` (development)
  - `postgresql+asyncpg://...` (production)

### 2. Authentication & Session Management
- **JWT**: short-lived access tokens (15 min) + long-lived refresh tokens.
- **Revocation**: Redis blacklist by `jti` (instant global logout).
- **MFA**: TOTP + Passkeys (WebAuthn).
- **Rate limiting**: SlowAPI + Redis (5/min for login, 60/min default).

### 3. Security Middleware
`SecurityMiddleware` (`middleware.py`):
- Protection against IP spoofing (`X-Forwarded-For` with hop limit).
- Scanner detection + automatic Redis block.
- Enforces security headers (HSTS, CSP, etc.).

### 4. Data Layer
- **SQLAlchemy 2.0 Async** with universal engine (`database.py`).
- **Models**: `User`, `Password`, `Folder`, `TokenBlacklist`.
- **Services**: clean feature-first `service.py` per domain (no heavy CRUD repository layer).

---

## 📂 What We Fixed in v0.2.1

| Issue                          | Fix Applied                               | File                     |
|--------------------------------|-------------------------------------------|--------------------------|
| In-memory rate limiter         | Redis + SlowAPI                           | `auth/router.py`         |
| No JWT revocation              | Redis blacklist by `jti`                  | `security.py`            |
| Synchronous DB                 | AsyncSession + connection pooling         | `database.py`            |
| SQLite / PostgreSQL choice     | Single `DATABASE_URL` in `.env`           | `config.py` + `database.py` |
| Mixed architecture             | Feature-first (router + service + schema) | `auth/`, `passwords/`, `folders/` |
| Lifespan / cleanup             | Proper startup/shutdown                   | `main.py`                |

---

## 🚀 Deployment

```bash
cp .env.example .env
# Choose SQLite (dev) or PostgreSQL (prod) in DATABASE_URL
docker compose up --build