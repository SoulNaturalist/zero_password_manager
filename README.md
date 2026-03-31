<div align="center">

# 🔐 Zero Password Manager

### Zero Cloud. Zero Tracking. Zero Compromise.

*A privacy-first, self-hosted password manager built on true zero-knowledge principles.*<br>
*Your vault lives on your server. Your key never leaves your device. Your secrets stay yours.*

<br>

[![Release](https://img.shields.io/github/v/release/SoulNaturalist/zero_password_manager?label=latest%20release&color=4CAF50&style=flat-square)](https://github.com/SoulNaturalist/zero_password_manager/releases/latest)
[![License](https://img.shields.io/badge/license-PolyForm%20Noncommercial-3b82f6?style=flat-square)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-Python-009688?style=flat-square&logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![AES-256-GCM](https://img.shields.io/badge/encryption-AES--256--GCM-ef4444?style=flat-square&logo=opensourceinitiative&logoColor=white)](#-security-model)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-64748b?style=flat-square)](#-quick-start)

<br>

[![Download APK](https://img.shields.io/github/v/release/SoulNaturalist/zero_password_manager?label=Download%20APK&logo=android&logoColor=white&color=4CAF50&style=for-the-badge)](https://github.com/SoulNaturalist/zero_password_manager/releases/latest)
[![Feature Guide](https://img.shields.io/badge/Feature%20Guide-Explore%20Capabilities-8b5cf6?style=for-the-badge)](docs/FEATURES.md)
[![How it Works](https://img.shields.io/badge/How%20it%20Works-Technical%20Core-5d52d2?style=for-the-badge)](docs/CORE.md)

<br>

---

![Zero Password Manager Demo](assets/demo.gif)

---

</div>

<!--
SEO: password manager, open source password manager, self-hosted password manager,
encrypted password vault, zero knowledge password manager, zero knowledge security,
privacy focused password storage, secure credential manager, AES-256 password manager,
Flutter password manager, biometric password vault, offline password manager,
no cloud password manager, TOTP 2FA password manager, PBKDF2 password manager
-->

<br>

## The Problem with Every Other Password Manager

Every major password manager — LastPass, 1Password, Bitwarden Cloud — ultimately stores your vault on **someone else's server**. "Zero-knowledge" in their marketing means they *claim* not to read your data. It doesn't mean they *can't*.

**Zero Password Manager takes a different position:** the server that holds your vault is one you run yourself. On your home server, your VPS, your Raspberry Pi. The encrypted vault sits on hardware you physically control.

Combined with client-side encryption that ensures the server is **cryptographically blind** to all vault contents, this is privacy that doesn't require trusting anyone.

> **No cloud subscription. No vendor lock-in. No breach notifications from a company you forgot you trusted.**

<br>

---

## 📚 Documentation & Guides

Detailed material for both users and security-conscious developers:

- **[Feature Guide](docs/FEATURES.md)** — Polished tour of security, organization, and platform capabilities.
- **[Technical Core (How it Works)](docs/CORE.md)** — Deep technical dive into the encryption architecture, data flow, and security model.

---

## ✨ Features at a Glance

<table>
<tr>
<td width="50%" valign="top">

**🔒 Security & Privacy**
- AES-256-GCM end-to-end encryption
- PBKDF2-SHA256 (100k iterations) key derivation
- Blind site hashing — URLs never stored in plaintext
- Mandatory TOTP 2FA — no opt-out
- Per-operation OTP gating on sensitive reads/writes
- Replay attack protection on all OTP codes
- Full OWASP-aligned security audit applied
- WebAuthn / FIDO2 passkey support
- Biometric unlock (fingerprint + Face ID)
- PIN fallback with auto-lock

</td>
<td width="50%" valign="top">

**⚙️ Vault & Usability**
- Unlimited credentials, folders, and tags
- 12 folder colors + 16 folder icons
- Full password history with per-entry restore
- Password rotation reminders
- Emergency access for trusted contacts
- Secure credential sharing (no master key exposure)
- CSV import from Chrome, Firefox, Bitwarden, LastPass
- Complete audit log (every access with timestamp + IP)
- 3 hand-crafted UI themes: Midnight Dark, Cyberpunk, Glassmorphism
- Cross-platform: Android · iOS · Web · Windows · macOS · Linux

</td>
</tr>
</table>

<br>

---

## 🔐 Security Model

> This section exists because password managers live or die by the honesty and clarity of their security claims. Here is exactly how Zero Password Manager protects your data — nothing hidden.

### Encryption Architecture

Passwords are encrypted **on your device** before a single byte reaches the network.

```
╔══════════════════════════════════════════════════════════════════╗
║  YOUR DEVICE                                                      ║
║                                                                   ║
║  Master Password + Salt                                           ║
║       │                                                           ║
║       ▼                                                           ║
║  PBKDF2-SHA256                                                    ║
║  (100,000 iterations · 256-bit output)                           ║
║       │                                                           ║
║       ├──► Vault Key ──► AES-256-GCM ──► Encrypted Blob          ║
║       │                  (12-byte nonce · 16-byte auth tag)       ║
║       │                                                           ║
║       └──► HMAC-SHA256(site_url) ──► Site Hash (lookup key)       ║
║                                                                   ║
╠══════════════════════════════════════════════════════════════════╣
║  NETWORK  →  Only encrypted blob + site hash ever transmitted    ║
╠══════════════════════════════════════════════════════════════════╣
║  YOUR SERVER                                                      ║
║                                                                   ║
║  Stores:  [ site_hash ][ encrypted_blob ][ argon2id_login_hash ] ║
║  Knows:   Nothing. Cryptographically blind.                       ║
║                                                                   ║
╚══════════════════════════════════════════════════════════════════╝
```

### What the Server Sees

| Data | Server Stores | Server Can Read |
|---|---|---|
| Your master password | ❌ Never | ❌ Never |
| Site URLs | HMAC-SHA256 hash only | ❌ Hash is one-way |
| Usernames | AES-256-GCM ciphertext | ❌ No key |
| Passwords | AES-256-GCM ciphertext | ❌ No key |
| Notes / metadata | AES-256-GCM ciphertext | ❌ No key |
| Your login credential | Argon2id hash + salt | ❌ One-way |

**Blind site hashing** is a standout feature: even site URLs are stored as HMAC-SHA256 hashes. An attacker who compromises your database cannot determine which websites you have credentials for.

### Authentication Hardening

- **TOTP 2FA is mandatory** — enforced on account creation, cannot be disabled
- **Per-operation OTP gating** — configurable requirement for a fresh OTP on every vault read or write
- **Single-use time codes** — each TOTP code is invalidated after first use within its window
- **JWT access tokens** (15-min TTL) + refresh tokens (7-day TTL) with server-side revocation
- **Rate limiting** on all auth endpoints — 5 OTP attempts/minute, 10 login attempts/minute
- **Security headers** — HSTS, Content-Security-Policy, X-Frame-Options, X-Content-Type-Options
- **SSRF protection** on internal HTTP proxy (favicon fetcher)

### Audit Trail

Every vault operation — read, write, delete, login, logout — is logged with timestamp, IP address, and user agent. The audit log is append-only and visible only to the account owner.

<br>

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────┐    ┌─────────────────────────────────────┐
│           Flutter Client            │    │           FastAPI Server             │
│  (Android / iOS / Web / Desktop)    │    │         (your server/VPS)            │
│                                     │    │                                      │
│  ┌─────────────────────────────┐   │    │  ┌──────────────────────────────┐   │
│  │       UI Screens (15)       │   │    │  │     Auth Module (JWT+2FA)    │   │
│  └──────────────┬──────────────┘   │    │  ├──────────────────────────────┤   │
│                 │                   │    │  │   Passwords Module (CRUD)    │   │
│  ┌──────────────▼──────────────┐   │    │  ├──────────────────────────────┤   │
│  │    Services Layer           │   │    │  │   Folders Module             │   │
│  │  • CryptoService (E2E enc)  │   │    │  ├──────────────────────────────┤   │
│  │  • VaultService             │◄──┼────┼─►│   Audit Module               │   │
│  │  • SharingService           │   │    │  ├──────────────────────────────┤   │
│  │  • EmergencyService         │   │    │  │   WebAuthn Module (FIDO2)    │   │
│  │  • RotationService          │   │    │  └──────────────┬───────────────┘   │
│  └──────────────┬──────────────┘   │    │                 │                    │
│                 │                   │    │  ┌──────────────▼───────────────┐   │
│  ┌──────────────▼──────────────┐   │    │  │    SQLite (SQLAlchemy 2.0)   │   │
│  │  Local Secure Storage       │   │    │  │  Encrypted blobs + hashes    │   │
│  │  (flutter_secure_storage +  │   │    │  └──────────────────────────────┘   │
│  │   Hive encrypted cache)     │   │    │                                      │
│  └─────────────────────────────┘   │    └─────────────────────────────────────┘
└─────────────────────────────────────┘

         Encrypted over HTTPS only. No plaintext ever on wire.
```

<br>

---

## 🚀 Quick Start

> **5-minute setup.** You need Python 3.10+ and Flutter 3.x.

### 1 — Clone and start the backend

```bash
git clone https://github.com/SoulNaturalist/zero_password_manager.git
cd zero_password_manager/server

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp ../example.env .env
```

Open `.env` and set the two required values:

```env
# Generate with: python -c "import secrets; print(secrets.token_hex(32))"
JWT_SECRET_KEY=your-64-character-hex-secret-here

# Your server's accessible address
ALLOWED_ORIGINS=http://YOUR_SERVER_IP:3000
```

Start the API server:

```bash
python -m uvicorn main:app --host 0.0.0.0 --port 3000
```

API is live at `http://YOUR_SERVER_IP:3000` · Interactive docs at `/docs`

---

### 2 — Configure the Flutter app

```bash
cd ..                   # back to the project root
cp example.env env.prod
```

Edit `env.prod`:

```env
API_BASE_URL=http://YOUR_SERVER_IP:3000
ENVIRONMENT=prod
```

---

### 3 — Build or run the app

**Android (release APK):**

```bash
flutter pub get
flutter build apk --release --dart-define=ENVIRONMENT=prod
# → build/app/outputs/flutter-apk/app-release.apk
```

**Run on connected device / emulator:**

```bash
flutter run --dart-define=ENVIRONMENT=prod
```

**Web:**

```bash
flutter build web --release --dart-define=ENVIRONMENT=prod
```

**iOS** *(requires macOS + Xcode):*

```bash
flutter build ios --release --dart-define=ENVIRONMENT=prod
```

<br>

---

## 📲 Download Pre-built APK

Pre-built Android APKs are available from [GitHub Releases](https://github.com/SoulNaturalist/zero_password_manager/releases).

```
1. Download zero-password-manager-vX.X.X.apk
2. Enable "Install from unknown sources" on your device
3. Install and open the app
4. Enter your server address on the settings screen
```

> iOS and Desktop: build from source using the instructions above.

<br>

---

## 🗂️ Project Structure

```
zero_password_manager/
│
├── lib/                              # Flutter application (Dart)
│   ├── main.dart                     # App entry point
│   ├── config/
│   │   └── app_config.dart           # Server URL + environment config
│   ├── screens/                      # 15 UI screens
│   │   ├── login_screen.dart
│   │   ├── signup_screen.dart
│   │   ├── pin_screen.dart
│   │   ├── passwords_screen.dart     # Main vault view
│   │   ├── add_password_screen.dart
│   │   ├── edit_password_screen.dart
│   │   ├── password_history_screen.dart
│   │   ├── folders_screen.dart
│   │   ├── settings_screen.dart
│   │   ├── sharing_screen.dart
│   │   ├── emergency_screen.dart
│   │   └── telegram_binding_screen.dart
│   ├── services/                     # Core business logic
│   │   ├── crypto_service.dart       # AES-256-GCM + PBKDF2 + HMAC-SHA256
│   │   ├── vault_service.dart        # Vault CRUD operations
│   │   ├── sharing_service.dart      # Secure credential sharing
│   │   ├── rotation_service.dart     # Password rotation tracking
│   │   ├── emergency_service.dart    # Emergency access grants
│   │   └── cache_service.dart        # Encrypted local cache (Hive)
│   ├── widgets/                      # Reusable UI components
│   └── theme/
│       └── colors.dart               # Midnight Dark · Cyberpunk · Glassmorphism
│
├── server/                           # FastAPI backend (Python)
│   ├── main.py                       # Application factory + middleware
│   ├── auth/                         # JWT auth + WebAuthn/FIDO2
│   ├── passwords/                    # Encrypted vault CRUD
│   ├── folders/                      # Folder management
│   ├── audit/                        # Immutable audit log
│   ├── models.py                     # SQLAlchemy ORM models
│   ├── schemas.py                    # Pydantic request/response schemas
│   ├── crud.py                       # Database operations
│   └── requirements.txt
│
├── assets/
│   ├── demo.gif                      # Demo animation
│   └── images/backgrounds/           # Theme background images
│
├── .github/workflows/
│   └── release-apk.yml               # Automated APK build + GitHub Release
│
├── env.example                       # Environment config template
├── pubspec.yaml                      # Flutter package manifest (v0.2.1)
└── README.md
```

<br>

---

## ⚡ Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Mobile / Desktop / Web | Flutter 3.x + Dart | Cross-platform UI |
| Backend API | FastAPI + Uvicorn | REST API server |
| Database | SQLite + SQLAlchemy 2.0 | Encrypted vault storage |
| Vault encryption | AES-256-GCM | Symmetric authenticated encryption |
| Login KDF | Argon2id (server-side) | Password hashing for login |
| Vault KDF | PBKDF2-SHA256 (100k iter) | Vault key derivation on device |
| Site obfuscation | HMAC-SHA256 | Blind site URL hashing |
| Authentication | JWT HS256 (access + refresh) | Stateless session management |
| Two-factor auth | TOTP (`pyotp`) | Time-based one-time passwords |
| Passkeys | WebAuthn (`py_webauthn`) | FIDO2 passwordless authentication |
| Rate limiting | `slowapi` | Brute-force protection |
| Local secure storage | `flutter_secure_storage` | Platform keychain integration |
| Local cache | Hive (encrypted) | Offline-capable vault cache |
| Biometrics | `flutter_locker` | Fingerprint + Face ID unlock |

<br>

---

## 🆚 Why Not Just Use Bitwarden?

| | Zero PM | Bitwarden Cloud | LastPass | 1Password |
|---|:---:|:---:|:---:|:---:|
| **Server you control** | ✅ | ❌ | ❌ | ❌ |
| **No third-party cloud** | ✅ | ❌ | ❌ | ❌ |
| **Fully open source** | ✅ | ✅ | ❌ | ❌ |
| **Free, no subscription** | ✅ | partial | ❌ | ❌ |
| **Works fully offline** | ✅ | ❌ | ❌ | ❌ |
| **Blind URL hashing** | ✅ | ❌ | ❌ | ❌ |
| **Audit log (free tier)** | ✅ | enterprise | enterprise | ❌ |
| **Password rotation** | ✅ | ❌ | ❌ | ❌ |
| **Emergency access** | ✅ | ✅ | ❌ | ✅ |
| **Custom themes** | ✅ (3) | ❌ | ❌ | ❌ |
| **Mandatory 2FA** | ✅ | optional | optional | optional |

> Bitwarden is excellent software and the recommended choice if you want hosted simplicity. Zero Password Manager is for users who need total control over their data infrastructure.

<br>

---

## 🗺️ Roadmap

**v0.3**
- [✔] Docker Compose for one-command server deployment
- [ ] Browser extension (Chrome / Firefox)
- [ ] Improved onboarding flow

**v0.4**
- [ ] Built-in TOTP authenticator (store 2FA seeds in vault)
- [ ] Secure notes with Markdown rendering
- [ ] Custom fields per credential

**v0.5**
- [ ] PBKDF2 iteration count configuration UI
- [ ] Multi-vault support (personal / work)
- [ ] Encrypted backup export (`.zpmbak`)

**Future**
- [ ] iOS App Store build pipeline
- [ ] Hardware security key support (YubiKey / FIDO2 token)
- [ ] Self-hosted auto-update server
- [ ] Passphrase generator with wordlist selection

<br>

---

## 🤝 Contributing

Zero Password Manager is open to contributions. Security-focused projects particularly benefit from fresh eyes.

```bash
# 1. Fork the repository on GitHub
# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/zero_password_manager.git

# 3. Create a feature branch
git checkout -b feature/your-feature-name

# 4. Make your changes, then commit
git commit -m "feat: describe your change clearly"

# 5. Push and open a Pull Request targeting main
git push origin feature/your-feature-name
```

**Good first issues:**

| Area | Examples |
|---|---|
| 🐛 Bug fixes | UI edge cases, error handling improvements |
| 📝 Documentation | Clearer setup guides, architecture docs |
| 🌍 Translations | i18n for new languages (app is currently EN/RU) |
| 🎨 UI / UX | Accessibility improvements, new theme ideas |
| 🧪 Tests | Unit tests for `crypto_service.dart`, integration tests |
| 🔐 Security | Audit, threat modelling, dependency review |

Please check [open Issues](https://github.com/SoulNaturalist/zero_password_manager/issues) before starting significant work, and open a discussion first for large feature additions.

<br>

---

## 📜 License

Licensed under the **[PolyForm Noncommercial License 1.0.0](LICENSE)**.

| ✅ Permitted | ❌ Prohibited |
|---|---|
| Personal use and self-hosting | Commercial use or SaaS deployments |
| Research and academic use | Revenue-generating services built on this code |
| Hobby projects and tinkering | Sublicensing under different terms |
| Forking and modifying | Removing license or attribution |

If you need a commercial license, open an issue to discuss.

<br>

---

## 🌐 Translations

- 🇷🇺 [Русская версия (Russian README)](README_RU.md)
- ⚙️ [Environment configuration guide](README_ENV.md)

---

<div align="center">

<br>

**🔐 Zero Password Manager**

*Private · Encrypted · Self-hosted · Open Source*

<br>

If this project is useful to you, consider giving it a ⭐ — it helps others find it.

<br>

---

**Suggested repository description:**
> Self-hosted, open-source password manager with AES-256-GCM client-side encryption, mandatory TOTP 2FA, blind URL hashing, biometric unlock, and a Flutter UI. No cloud. No subscriptions. No trust required.

**Suggested GitHub topics:**
`password-manager` `self-hosted` `flutter` `fastapi` `open-source` `privacy` `security` `aes-256` `zero-knowledge` `totp` `2fa` `encrypted-vault` `dart` `biometric` `end-to-end-encryption`

</div>
