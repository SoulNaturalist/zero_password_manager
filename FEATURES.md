# ✨ Zero Password Manager Features

A curated overview of what makes **Zero Password Manager** different from mainstream password managers.

> **Private by default. Self-hosted by design. Zero-knowledge at the core.**

---

## Quick Navigation

- [Privacy & Security Foundation](#privacy--security-foundation)
- [Vault Organization](#vault-organization)
- [Authentication & Access Control](#authentication--access-control)
- [Sharing, Recovery & Continuity](#sharing-recovery--continuity)
- [Productivity & Day-to-Day UX](#productivity--day-to-day-ux)
- [Platform & Deployment](#platform--deployment)
- [Why It Stands Out](#why-it-stands-out)

---

## Privacy & Security Foundation

### 🧠 True zero-knowledge architecture
Your vault is encrypted on the client before it reaches the server. The backend stores encrypted blobs, not readable secrets.

### 🏠 Self-hosted deployment
Run it on your own infrastructure — home server, VPS, NAS, or local network. No vendor lock-in. No mandatory cloud.

### 🔐 Strong vault encryption
Built around modern authenticated encryption for passwords, notes, and sensitive metadata.

### 🛡️ Mandatory 2FA with TOTP
Two-factor authentication is treated as a core security layer, not an optional afterthought.

### 🚨 Per-operation OTP gating
You can protect sensitive actions like vault reads, writes, and audit-log access with fresh OTP verification.

### 🌐 IP whitelist support
Trusted IPs and networks can be whitelisted to fit secure home-lab, office, or reverse-proxy deployments.

### 📜 Full audit trail
Track important security-relevant activity with timestamps and access events.

### 🔎 Password history
Review past changes to entries and keep an operational record of updates and deletions.

### 👁️ Hidden folders with TOTP reveal
Keep especially sensitive categories hidden until explicitly unlocked for the current session.

---

## Vault Organization

### 📁 Password folders
Group credentials by work, home, finance, cloud, gaming, or any structure that fits your life.

### 🎨 Custom folder identity
Use multiple folder colors and icons so the vault stays easy to scan even as it grows.

### 🧩 Rich metadata support
Store more than just a password — usernames, URLs, notes, and sensitive recovery-related data can be handled cleanly.

### 🌱 Seed / recovery phrase awareness
Entries containing recovery phrases can be treated as high-sensitivity items and optionally hidden from the main list.

---

## Authentication & Access Control

### 👆 Biometric unlock
Unlock with fingerprint or Face ID where supported, while keeping biometric secrets on-device.

### 🔢 PIN fallback
Use a local PIN as a fast unlock option and backup path when biometrics are unavailable.

### 🔑 Passkeys / WebAuthn
Register passkeys for passwordless sign-in and modern phishing-resistant authentication.

### 📱 Device-aware access
Manage registered devices and revoke access when needed.

### 🌍 App localization
The app supports multiple interface languages, making it easier to use across teams and households.

---

## Sharing, Recovery & Continuity

### 🤝 Secure password sharing
Share credentials without exposing your master key. Shared data is re-encrypted before it is sent.

### 🔁 Password rotation support
Track entries that are due for rotation and build healthier credential hygiene over time.

### 🆘 Emergency access
Designate trusted contacts who can request access to an emergency vault snapshot after a waiting period.

### 📣 Telegram security notifications
Connect Telegram to receive security alerts and important account activity notifications.

---

## Productivity & Day-to-Day UX

### 📥 CSV import
Move into Zero Password Manager from browser exports or other password managers without manual re-entry.

### 💾 Local encrypted cache
Improve resilience and usability with secure local caching for vault data and folder state.

### 🎨 Three visual themes
Choose between **Midnight Dark**, **Cyberpunk**, and **Glassmorphism** for very different visual moods.

### 🧭 Built for real daily use
The project includes dedicated flows for setup, login, 2FA enrollment, password creation, editing, sharing, folder management, history, and settings.

---

## Platform & Deployment

### 📱 Cross-platform client
Built with Flutter for Android, iOS, Web, Windows, macOS, and Linux.

### ⚡ FastAPI backend
A modern Python API with modular services, security middleware, and self-hosted deployment flexibility.

### 🧪 Security-focused evolution
Recent development has heavily emphasized hardening, auth fixes, biometric reliability, token handling, and safer in-memory behavior.

---

## Why It Stands Out

Most password managers stop at **"encrypted vault in someone else's cloud."**

**Zero Password Manager goes further:**

- your server,
- your infrastructure,
- your policies,
- your security boundaries,
- your data ownership.

If you want a password manager that combines **self-hosting, zero-knowledge design, modern authentication, secure sharing, emergency recovery, and a polished UI**, this project is built exactly for that niche.

---

## Start Here

- Return to the main project page: [README.md](README.md)
- Setup and overview: [README.md#-quick-start](README.md#-quick-start)
- Security model: [README.md#-security-model](README.md#-security-model)
