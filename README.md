# 🔐 Zero Password Manager

<p align="center">
  <strong>Open-source · Self-hosted · Zero-knowledge · End-to-end encrypted</strong>
</p>

<p align="center">
  <a href="https://github.com/SoulNaturalist/zero_password_manager/releases/latest">
    <img alt="Latest Release" src="https://img.shields.io/github/v/release/SoulNaturalist/zero_password_manager?label=release&color=4CAF50">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/license-PolyForm%20Noncommercial-blue">
  </a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter">
  <img alt="FastAPI" src="https://img.shields.io/badge/FastAPI-Python-009688?logo=fastapi">
  <img alt="Encryption" src="https://img.shields.io/badge/encryption-AES--256--GCM-critical">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Desktop-lightgrey">
</p>

<p align="center">
  <em>Your passwords. Your server. Your rules. No cloud. No subscriptions. No tracking.</em>
</p>

---

<!--
SEO Keywords: password manager, open source password manager, self-hosted password manager,
encrypted password vault, zero knowledge password manager, privacy focused password storage,
secure credential manager, AES-256 password manager, Flutter password manager, biometric password vault,
no cloud password manager, local password manager, offline password manager, TOTP 2FA password manager
-->

## What Is Zero Password Manager?

**Zero Password Manager** is a free, open-source, self-hosted **encrypted password vault** built with Flutter and FastAPI. It gives you a beautiful mobile and desktop app backed by a server you run yourself — on your home lab, VPS, or Raspberry Pi.

Unlike commercial password managers, Zero stores **zero data on third-party servers**. Not "zero-knowledge" in the marketing sense — zero-cloud in the literal sense. Your encrypted vault lives exclusively on hardware you own.

> **Self-hosting + end-to-end encryption + full auditability = true privacy.**

---

## ✨ Features

| Feature | Details |
|---|---|
| 🔑 **Encrypted vault** | AES-256-GCM encryption, all passwords encrypted client-side before upload |
| 🧠 **Zero-knowledge architecture** | Master password never leaves your device; server stores only encrypted blobs |
| 🔒 **Argon2id key derivation** | Gold-standard KDF resistant to GPU/ASIC attacks (3 iterations, 64 MB memory) |
| 📱 **Cross-platform** | Android, iOS, Web, Windows, macOS, Linux — one Flutter codebase |
| 🛡️ **Mandatory 2FA** | TOTP from day one; works with Aegis, Google Authenticator, Bitwarden Auth |
| 🤳 **Biometric unlock** | Fingerprint + Face ID; PIN fallback; auto-lock on inactivity |
| 📁 **Password folders** | Organize credentials with custom names, 12 colors, 16 icons |
| 📜 **Audit log** | Every vault read/write logged with timestamp and IP address |
| 🕐 **Password history** | Full change history per entry; restore previous credentials |
| 📥 **CSV import** | Migrate from Chrome, Firefox, Bitwarden, LastPass, 1Password |
| 🔄 **Password rotation** | Built-in rotation reminders and history tracking |
| 🚨 **Emergency access** | Configurable emergency access for trusted contacts |
| 🤝 **Secure sharing** | Share individual credentials without exposing master password |
| 🎨 **3 UI themes** | Midnight Dark, Cyberpunk (neon), Glassmorphism (frosted glass) |
| ♻️ **WebAuthn / Passkeys** | FIDO2 passkey support for passwordless login |
| 🌐 **Fully offline** | Works on local network with no internet dependency |

---

## 🔐 Security Highlights

### End-to-End Encrypted Password Vault

```
Your Device
  └─ Master password
       └─ Argon2id (time=3, mem=64MB, parallel=1)
            └─ 256-bit encryption key
                 └─ AES-256-GCM (random 12-byte nonce per entry)
                      └─ Encrypted blob ──────────────► Your Server
                                                         (stores blob only)
                                                         (no key, no plaintext)
```

Your server is **cryptographically blind**. Even with full database access, an attacker sees only opaque ciphertext — useless without your master password.

### Zero-Knowledge by Design

- Master password is **never transmitted** over the network
- Server stores: encrypted blob + Argon2id login hash + salt
- Server **cannot** decrypt passwords, notes, or seed phrases
- No telemetry, no analytics, no callbacks to external services

### Hardened Authentication

- **TOTP 2FA mandatory** — not optional, not a premium add-on
- **Per-operation OTP gating** — require a fresh OTP code for vault reads/writes (configurable)
- **Replay attack protection** — each time-code usable only once within its window
- **JWT access tokens** (15-min TTL) + refresh tokens (7-day TTL) + revocation
- **Rate limiting** via `slowapi` on all sensitive endpoints (5 attempts/min for OTP)
- **HTTP security headers** — HSTS, CSP, X-Frame-Options, X-Content-Type-Options

### CVE-Hardened Codebase

Recent security commits include: JWT revocation, WebAuthn validation tightening, Pydantic schema security review, SSRF protection in favicon proxy, and full OWASP-aligned audit.

---

## 📱 Download

[![Download APK](https://img.shields.io/github/v/release/SoulNaturalist/zero_password_manager?label=Download%20APK&logo=android&color=4CAF50)](https://github.com/SoulNaturalist/zero_password_manager/releases/latest)

1. Download the latest `zero-password-manager-vX.X.X.apk` from [Releases](https://github.com/SoulNaturalist/zero_password_manager/releases)
2. Enable **Install from unknown sources** on your Android device
3. Install the APK
4. Set up your [backend server](#️-self-hosting-guide) first

> iOS and Desktop builds require building from source — see instructions below.

---

## ⚙️ Self-Hosting Guide

### Prerequisites

- Python 3.10+ on your server
- Flutter 3.x SDK (for building from source)
- 5 minutes

### Step 1 — Start the Backend Server

```bash
git clone https://github.com/SoulNaturalist/zero_password_manager.git
cd zero_password_manager/server

pip install -r requirements.txt
cp env.example .env
```

Edit `.env` and set your values:

```env
JWT_SECRET_KEY=<run: python -c "import secrets; print(secrets.token_hex(32))">
ALLOWED_ORIGINS=http://YOUR_SERVER_IP:3000
```

Start the server:

```bash
python -m uvicorn main:app --host 0.0.0.0 --port 3000
```

The API is now running at `http://YOUR_SERVER_IP:3000`. The interactive API docs are at `/docs`.

### Step 2 — Configure the Flutter App

```bash
cd ..                        # back to project root
cp env.example env.prod
```

Edit `env.prod`:

```env
API_BASE_URL=http://YOUR_SERVER_IP:3000
ENVIRONMENT=prod
```

### Step 3 — Run or Build the App

**Run on a connected device / emulator:**

```bash
flutter pub get
flutter run --dart-define=ENVIRONMENT=prod
```

**Build Android APK:**

```bash
flutter build apk --release --dart-define=ENVIRONMENT=prod
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Build for iOS** (requires macOS + Xcode):

```bash
flutter build ios --release
```

**Build for Web:**

```bash
flutter build web --release
```

---

## 🗂️ Project Structure

```
zero_password_manager/
├── lib/                        # Flutter/Dart application
│   ├── main.dart               # Entry point
│   ├── config/
│   │   └── app_config.dart     # API endpoint configuration
│   ├── screens/                # All UI screens (15 screens)
│   │   ├── login_screen.dart
│   │   ├── passwords_screen.dart
│   │   ├── add_password_screen.dart
│   │   ├── folders_screen.dart
│   │   ├── settings_screen.dart
│   │   └── ...
│   ├── services/               # Business logic
│   │   ├── crypto_service.dart    # AES-256-GCM encryption
│   │   ├── vault_service.dart     # Password vault operations
│   │   ├── sharing_service.dart   # Secure sharing
│   │   ├── rotation_service.dart  # Password rotation
│   │   └── emergency_service.dart # Emergency access
│   ├── widgets/                # Reusable UI components
│   └── theme/
│       └── colors.dart         # 3 theme definitions
│
├── server/                     # FastAPI Python backend
│   ├── main.py                 # API server + all routes
│   ├── auth/                   # JWT + WebAuthn authentication
│   ├── passwords/              # CRUD for encrypted vault entries
│   ├── folders/                # Folder management
│   ├── audit/                  # Audit log module
│   ├── models.py               # SQLAlchemy ORM models
│   ├── schemas.py              # Pydantic validation schemas
│   └── requirements.txt        # Python dependencies
│
├── assets/                     # Images and backgrounds
├── env.example                 # Environment config template
├── pubspec.yaml                # Flutter package manifest
└── .github/workflows/          # CI/CD — automated APK release
```

---

## ⚡ Tech Stack

| Layer | Technology |
|---|---|
| Mobile / Desktop / Web | Flutter 3.x + Dart |
| Backend API | FastAPI (Python) |
| Database | SQLite via SQLAlchemy 2.0 |
| Vault encryption | AES-256-GCM |
| Key derivation | Argon2id |
| Authentication | JWT HS256 (access + refresh tokens) |
| Two-factor auth | TOTP via `pyotp` |
| Passkeys | WebAuthn via `py_webauthn` |
| Rate limiting | `slowapi` |
| Local secure storage | `flutter_secure_storage` |
| Local cache | Hive (encrypted) |
| Biometrics | `flutter_locker` |

---

## 🆚 Comparison

| Feature | **Zero PM** | LastPass | Bitwarden Cloud | 1Password |
|---|:---:|:---:|:---:|:---:|
| Data on your server only | ✅ | ❌ | ❌ | ❌ |
| Zero cloud dependency | ✅ | ❌ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ | ❌ |
| Free (no subscription) | ✅ | ❌ | partial | ❌ |
| Works fully offline | ✅ | ❌ | ❌ | ❌ |
| Audit log (free) | ✅ | premium | premium | premium |
| Biometric unlock | ✅ | ✅ | ✅ | ✅ |
| Password history | ✅ | ✅ | ✅ | ✅ |
| Emergency access | ✅ | ❌ | ✅ | ✅ |
| Password rotation | ✅ | ❌ | ❌ | ❌ |
| Cyberpunk / custom themes | ✅ | ❌ | ❌ | ❌ |

---

## 🗺️ Roadmap

- [ ] **v0.3** — Docker Compose for one-command server deployment
- [ ] **v0.3** — Browser extension (Chrome/Firefox)
- [ ] **v0.4** — TOTP/2FA code storage (built-in authenticator)
- [ ] **v0.4** — Secure notes with markdown support
- [ ] **v0.5** — Argon2id parameter tuning UI
- [ ] **v0.5** — Multi-vault support (personal + work)
- [ ] **Future** — iOS App Store build pipeline
- [ ] **Future** — Self-hosted update server
- [ ] **Future** — Hardware key (YubiKey) support

---

## 🤝 Contributing

Contributions are welcome! Here's how to get started:

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/your-feature`
3. **Commit** your changes with a clear message
4. **Open a Pull Request** targeting `main`

**Good first contributions:**
- 🐛 Bug fixes
- 📝 Documentation improvements
- 🌍 Translations (i18n)
- 🎨 UI/UX polish
- 🧪 Test coverage

Please check open [Issues](https://github.com/SoulNaturalist/zero_password_manager/issues) before starting large features.

---

## 📜 License

Licensed under the **[PolyForm Noncommercial License 1.0.0](LICENSE)**.

| | |
|---|---|
| ✅ **Allowed** | Personal use, research, hobby projects, self-hosting for non-commercial purposes |
| ✅ **Allowed** | Study, modify, and distribute under the same terms |
| ❌ **Prohibited** | Commercial use, revenue-generating deployments |

---

## 🌐 Translations

- [Русская версия / Russian README](README_RU.md)
- [Environment setup guide / Настройка окружения](README_ENV.md)

---

<p align="center">
  <strong>🔐 Zero Password Manager</strong><br>
  <em>Private · Encrypted · Self-hosted · Open Source</em><br><br>
  If this project helps you, consider giving it a ⭐ on GitHub
</p>
