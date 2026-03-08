# 🔐 Zero Password Manager
### Private • Self-Hosted • No Cloud Password Manager Built With Flutter

**Zero Password Manager** is a **privacy-first password manager built with Flutter** that gives you **full control over your sensitive data**.

---

## 🎬 Demo — Flutter UI Preview

![Zero Password Manager Demo](assets/demo.gif)

> **UI walkthrough (Flutter app):**
> Splash → Login → Sign Up → 2FA Setup → PIN entry → Password Vault → Add Entry → Edit Entry → Settings
> + Theme showcase: **Midnight Dark** · **Cyberpunk** (neon cyan/magenta) · **Glassmorphism** (blur glass cards)

Unlike traditional password managers, **Zero Password Manager does NOT use cloud storage**.  
Your passwords and seed phrases are stored **only on your own server**, ensuring **maximum privacy, security, and ownership of your data**.

No third-party access.  
No cloud providers.  
No tracking.

Just **you and your data**.

---

# 🚀 Key Features

## ☁️ No Cloud. Ever.
Most password managers store your data in **third-party cloud infrastructure**.

**Zero Password Manager does not.**

✔ Your data stays **only on your server**  
✔ No Google Cloud  
✔ No AWS  
✔ No external storage  
✔ No data mining  

This ensures **true data ownership and privacy**.

---

## 🔑 Secure Password Vault
Safely store and manage:
- website logins
- API keys
- private credentials
- personal secrets

All data is stored in a **secure encrypted vault** using **AES-256-GCM**. Master password never leaves your device (**Zero-Knowledge**).

---

## 🛡️ Hardened 2FA
Built-in support for TOTP (Google Authenticator, Microsoft Authenticator, Aegis, etc.).
- Mandatory 2FA setup during registration.
- OTP-gated critical actions.
- Replay attack protection.

---

## 🎨 Beautiful Custom Themes
Zero Password Manager includes **3 unique UI themes**:
- **Cyberpunk**: A futuristic neon interface.
- **Glassmorphism**: A modern glass-style interface with blur effects.
- **Midnight Dark**: Optimized for OLED screens and night usage.

---

# 📱 Built With Flutter
The application is built using **Flutter**, making it fast and cross-platform.
Supported platforms: Android, iOS, Web, Desktop.

---

# 🛡 Security Philosophy
Zero Password Manager follows a **Zero Cloud Security Model**.
Your secrets should never live in someone else's infrastructure.
- No external cloud services.
- No analytics tracking.
- No third-party data access.
- Everything stays **under your control**.

---

# ⚙️ Tech Stack
- **Flutter & Dart**
- **FastAPI & Python**
- **SQLAlchemy** (Local SQLite)
- **Argon2id & AES-256-GCM**

---

# 📦 Local Deployment (No Cloud Needed)

Zero Password Manager is designed to be self-hosted in your own local environment.

## 🐍 1. Backend Setup (FastAPI)
The server handles authentication, audit logs, and stores encrypted blobs.

1.  **Navigate to the server directory**:
    ```bash
    cd server
    ```
2.  **Install dependencies**:
    ```bash
    pip install -r requirements.txt
    ```
3.  **Configure Environment**:
    Copy `env.example` to `.env` and set your `JWT_SECRET_KEY`.
4.  **Launch the Server**:
    ```bash
    python -m uvicorn main:app --host 0.0.0.0 --port 3000
    ```
    *The API will be available at `http://localhost:3000`.*

---

### 📱 2. Flutter App Setup
Ensure you have the Flutter SDK installed.

1.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```
2.  **Configuration**:
    Create a `.env` file in the root directory (based on `env.example`). Set `API_BASE_URL` to point to your server's IP.
3.  **Run the App**:
    ```bash
    flutter run
    ```

### 📦 3. Mobile Build (Android & iOS)

To build the application for mobile devices:

#### Android
```bash
flutter build apk --release
# Or for Play Store
flutter build appbundle --release
```

#### iOS / Apple
*Note: Requires macOS and Xcode.*
```bash
flutter build ios --release
```

---

# 🤝 Contributing
I would be very happy to receive help with the development of **Zero Password Manager**! 

If you want to:
- 🛠 Fix bugs
- ✨ Add new features
- 🎨 Improve UI/UX
- 📝 Improve documentation

Feel free to **fork the repository**, create a branch, and submit a **Pull Request**. Any contribution is valuable!

---

# 📜 License
This project is licensed under the **PolyForm Noncommercial License 1.0.0**.

✅ **You can**: Use, study, modify, and distribute for personal, research, or hobby projects.
❌ **You cannot**: Use for commercial purposes or revenue-generating activities.

---

> 🔐 **Zero Password Manager** — Your data, your server, your rules.

---
[Русская версия README](README_RU.md)