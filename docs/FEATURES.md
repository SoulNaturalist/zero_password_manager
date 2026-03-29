# Zero Password Manager - Feature Guide

Zero Password Manager is a privacy-first, self-hosted solution. Here is a detailed overview of the available features in version 0.2.0.

## 🔐 Security & Privacy
- **End-to-End Encryption**: All vault data is encrypted on your device using AES-256-GCM. Your master password never leaves your phone.
- **Blind URL Hashing**: Site URLs are stored as HMAC-SHA256 hashes. The server doesn't know which accounts you have.
- **Mandatory TOTP**: Two-factor authentication is required for all accounts.
- **Biometric Unlock**: Use Fingerprint or Face ID to unlock your vault securely.
- **Passkeys (FIDO2)**: Log in without a password using hardware keys or platform authenticators.
- **PIN Protection**: Set a 6-digit PIN for quick access with auto-lock and rate-limiting.

## 📂 Vault Organization
- **Smart Folders**: Organize credentials into folders with custom icons and colors.
- **Hidden Folders**: Protect sensitive categories with an additional layer of authentication (PIN/Biometric/TOTP).
- **Search & Filters**: Quickly find credentials by name, URL, or tag.
- **Custom Icons**: Automatic favicon fetching (via a secure proxy) for a polished look.

## 🛠 Usability
- **Password History**: Every change is tracked. You can restore old passwords if needed.
- **Secure Sharing**: Share credentials with other users without exposing your master key.
- **CSV Import**: Migrate from Chrome, Firefox, Bitwarden, or LastPass in seconds.
- **Password Generator**: Create strong, unique passwords with customizable length and character sets.
- **Rotation Reminders**: Get notified when it's time to update old passwords.

## 🌐 Platform Support
- **Mobile**: Full-featured Android and iOS apps.
- **Web**: Access your vault from any modern browser.
- **Desktop**: Native apps for Windows, macOS, and Linux.

## 🎨 Personalization
- **Theme Engine**: Choose between Midnight Dark, Cyberpunk, and Glassmorphism themes.
- **Language**: Full support for English and Russian.
