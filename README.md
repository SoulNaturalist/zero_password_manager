# 🔐 Zero Password Manager
### Private • Self-Hosted • Zero-Knowledge • Built With Flutter

<!--
Keywords: Password Manager, Self-hosted, Zero-Knowledge, Privacy-first, No Cloud, Flutter, FastAPI, AES-256-GCM, Argon2id, Cyberpunk UI, Glassmorphism, Open Source, Security, Hardened 2FA, TOTP, Vault, Encrypted Storage, Password Folders.
Description: A premium, privacy-focused, self-hosted password manager with a stunning Cyberpunk/Glassmorphism UI. Built with Flutter and FastAPI. No cloud, no tracking, just you and your data.
-->

<p align="center">
  <strong>Your data. Your server. Your rules.</strong><br/>
  The password manager that never phones home.
</p>

---

**Zero Password Manager** is an **open-source, self-hosted password manager** built with Flutter and FastAPI. Unlike every major commercial password manager, it stores your data **exclusively on hardware you own** — no cloud accounts, no subscription fees, no surveillance.

If you've ever asked *"who actually has access to my passwords?"* — this is the answer.

---

## 🎬 Demo — Flutter UI Preview

![Zero Password Manager Demo](assets/demo.gif)

> **UI walkthrough:**
> Splash → Login → Sign Up → 2FA Setup → PIN entry → Password Vault → Folders → Add Entry → Edit Entry → Settings
> + Theme showcase: **Midnight Dark** · **Cyberpunk** (neon cyan/magenta) · **Glassmorphism** (blur glass cards)

---

# 🚀 Why Zero Password Manager?

## ☁️ Truly No Cloud — Not Just "Zero-Knowledge"

Most password managers that claim "zero-knowledge" still host your encrypted blobs on **their servers**. That means:
- They can be subpoenaed
- They can be breached
- They can be shut down (taking your data with them)
- They can change their privacy policy tomorrow

**Zero Password Manager takes a different approach:**

> Your encrypted vault lives on **your machine**. Period.

✔ No Google Cloud, AWS, Azure, or any third-party storage
✔ No account to create on some company's website
✔ No monthly fee that goes up every year
✔ No "oops, we got breached" emails
✔ No service discontinuation risk — it's your server
✔ Works fully offline on your local network

This is what **true data ownership** looks like.

---

## 🔐 Military-Grade Encryption, On Your Terms

Every password you save is encrypted **before it ever leaves your device**:

- **AES-256-GCM** — the same cipher used by militaries and financial institutions worldwide
- **Argon2id** key derivation — the gold standard for password hashing, resistant to GPU and ASIC attacks (3 iterations, 64 MB memory)
- **12-byte random nonce** per encryption — guarantees uniqueness even if you save the same password twice
- The server stores **only encrypted blobs** — it literally cannot read your passwords even if it wanted to
- Your master password **never travels over the network** — ever

```
Your device → derives key from master password → encrypts → sends blob → server stores blob
Server has: encrypted blob only. No key. No plaintext. Zero knowledge.
```

---

## 📱 Beautiful UI That Doesn't Feel Like a Chore

Security tools are usually ugly. Zero Password Manager isn't.

### 3 Hand-Crafted Themes

| Theme | Vibe | Best For |
|-------|------|----------|
| **Midnight Dark** | Deep purple, clean and focused | OLED screens, daily use |
| **Cyberpunk** | Neon cyan + magenta glow, gradients | Standing out, late-night vibes |
| **Glassmorphism** | Frosted glass cards, soft blur | Modern aesthetic, readability |

Switch themes instantly from Settings. Your choice is saved across sessions.

---

## 🛡️ Hardened 2FA — Not an Afterthought

2FA is **mandatory from day one**, not an optional extra:

- **TOTP** support (Google Authenticator, Aegis, Microsoft Authenticator, Bitwarden Authenticator — any standard app)
- **QR code setup** during registration — scan and go
- **Per-operation OTP gating** — you can require a fresh OTP code for every vault read, every write, or every audit log access (configurable)
- **Replay attack protection** — each time-code can only be used once, even within its valid window
- **Brute-force rate limiting** — 5 attempts per minute with mandatory delays on wrong codes

---

## 📁 Password Folders — Keep Your Vault Organized

As your vault grows, finding the right password shouldn't feel like scrolling through a wall of entries.

**Folders let you group passwords the way you think:**

- 🏠 `Home` — WiFi, router, smart home devices
- 💼 `Work` — company tools, VPN, internal systems
- 🏦 `Finance` — banking, investment, crypto wallets
- 🎮 `Gaming` — Steam, Epic, console accounts
- ☁️ `Cloud` — AWS, GCP, hosting panels
- ...or any custom structure that makes sense to you

**How it works:**
- Create folders with a **custom name**, pick from **12 colors** and **16 icons**
- The **folder bar** on the main screen lets you filter your vault in one tap
- Assign a folder when adding or editing any entry — always optional
- Deleting a folder **never deletes passwords** — they just become unassigned
- All folder data is user-scoped on the server — no cross-account leakage

---

## 🔒 Biometric Unlock

Stop typing your master password every time:

- **Fingerprint** and **Face ID** unlock support
- **PIN code** fallback for devices without biometrics
- Local authentication only — biometric data never leaves your device
- Auto-lock after configurable inactivity timeout

---

## 📜 Audit Log — Know Exactly What Happened

Every sensitive action is logged:

- Login attempts (with IP address)
- Vault reads and writes
- Password creation, updates, and deletions
- 2FA enable/disable events
- Full history with timestamps

You can review everything that's ever happened in your vault. No black boxes.

---

## 🔑 Password History

Accidentally overwrote a password? Zero Password Manager keeps a **full change history** for every entry:
- See previous versions of every credential
- Timestamped CREATE / UPDATE / DELETE records
- Masked sensitive data in history (login shown, password hidden)

---

## 📥 CSV Import

Already using Chrome, Firefox, Bitwarden, LastPass, or 1Password? Import your existing vault in seconds:
- Standard CSV format support
- Bulk import in a single upload
- No manual re-entry needed

---

## 🌐 Cross-Platform

Built with Flutter — one codebase, runs everywhere:

| Platform | Status |
|----------|--------|
| Android | ✅ |
| iOS | ✅ |
| Web | ✅ |
| Windows | ✅ |
| macOS | ✅ |
| Linux | ✅ |

---

# 🛡 Security Architecture

```
┌─────────────────────────────────────────────┐
│              Your Device                     │
│  Master password → Argon2id → 256-bit key   │
│  Plaintext → AES-256-GCM → Encrypted blob   │
└────────────────────┬────────────────────────┘
                     │ HTTPS (encrypted blob only)
┌────────────────────▼────────────────────────┐
│              Your Server                     │
│  Stores: encrypted blob, login hash, salt   │
│  Cannot read: passwords, notes, seed phrases│
│  JWT auth + rate limiting + audit logging   │
└─────────────────────────────────────────────┘
```

**Security stack:**
- `Argon2id` — password hashing (time_cost=3, memory=64MB, parallelism=1)
- `AES-256-GCM` — authenticated encryption with random nonces
- `HS256 JWT` — short-lived access tokens (15 min) + refresh tokens (7 days)
- `slowapi` — rate limiting on all sensitive endpoints
- `HSTS + CSP + X-Frame-Options` — HTTP security headers

---

# ⚙️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile/Desktop/Web | Flutter & Dart |
| Backend API | FastAPI (Python) |
| Database | SQLite via SQLAlchemy |
| Password hashing | Argon2id |
| Vault encryption | AES-256-GCM |
| Authentication | JWT (HS256) |
| 2FA | TOTP via pyotp |
| Rate limiting | slowapi |

---

# 📦 Self-Hosting in 5 Minutes

## 🐍 1. Start the Backend

```bash
cd server
pip install -r requirements.txt
cp env.example .env
# Edit .env — set JWT_SECRET_KEY and ALLOWED_ORIGINS
python -m uvicorn main:app --host 0.0.0.0 --port 3000
```

Generate a secure JWT secret:
```bash
python -c "import secrets; print(secrets.token_hex(32))"
```

## 📱 2. Run the Flutter App

```bash
flutter pub get
# Edit env.dev — set API_BASE_URL to your server IP
flutter run
```

## 📦 3. Build for Mobile

```bash
# Android
flutter build apk --release

# iOS (requires macOS + Xcode)
flutter build ios --release
```

---

# 🆚 How It Compares

| Feature | Zero Password Manager | LastPass | Bitwarden Cloud | 1Password |
|---------|----------------------|----------|-----------------|-----------|
| Your server only | ✅ | ❌ | ❌ | ❌ |
| Zero cloud dependency | ✅ | ❌ | ❌ | ❌ |
| Open source | ✅ | ❌ | ✅ | ❌ |
| No subscription fee | ✅ | ❌ | partial | ❌ |
| Works offline | ✅ | ❌ | ❌ | ❌ |
| Audit log | ✅ | premium | premium | premium |
| Biometric unlock | ✅ | ✅ | ✅ | ✅ |
| Password folders | ✅ | ✅ | ✅ | ✅ |
| Cyberpunk theme | ✅ | ❌ | ❌ | ❌ |

---

# 🤝 Contributing

Contributions are welcome:
- 🛠 Bug fixes
- ✨ New features
- 🎨 UI/UX improvements
- 📝 Documentation

Fork → branch → Pull Request. Every contribution matters.

---

# 📜 License

Licensed under the **PolyForm Noncommercial License 1.0.0**.

✅ **You can**: Use, study, modify, and distribute for personal, research, or hobby projects.
❌ **You cannot**: Use for commercial purposes or revenue-generating activities.

---

<p align="center">
  <strong>🔐 Zero Password Manager — Your data. Your server. Your rules.</strong>
</p>

---

[Русская версия README](README_RU.md)
