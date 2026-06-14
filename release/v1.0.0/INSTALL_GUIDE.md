# SecureFlow v1.0.0 — Installation & User Guide

> **SecureFlow** is a hardware-anchored, end-to-end encrypted security suite comprising:
> - 🖥️ **SecureFlow Vault** — A Windows desktop application for encrypted file storage, password management, TOTP authenticator, and keystroke-dynamics intrusion detection.
> - 📱 **SecureFlow Mobile** — An Android companion app for on-the-go credential access, document vault, and cloud sync.

---

## 📦 Release Contents

| File | Platform | Size |
|------|----------|------|
| `SecureFlow_Vault_v1.0.0.exe` | Windows 10/11 (64-bit) | ~124 MB |
| `SecureFlow_Mobile_v1.0.0.apk` | Android 7.0+ (API 24+) | ~79.5 MB |

---

## 🖥️ Installing the Windows Desktop App (SecureFlow_Vault_v1.0.0.exe)

### System Requirements
- **OS:** Windows 10 or Windows 11 (64-bit)
- **RAM:** 4 GB minimum (8 GB recommended)
- **Storage:** 500 MB free disk space
- **Internet:** Required for cloud sync features (optional)
- **Permissions:** Standard user account (no admin required for basic use)

### Step-by-Step Installation

**Step 1 — Download**
Save `SecureFlow_Vault_v1.0.0.exe` to any folder on your PC (e.g., `C:\Users\YourName\Downloads\`).

**Step 2 — Windows SmartScreen Warning (Important!)**
When you double-click the EXE, Windows may show a blue "Windows protected your PC" dialog.
- Click **"More info"**
- Click **"Run anyway"**

> This warning appears because the app is not code-signed with a commercial certificate. It is safe to proceed.

**Step 3 — First Launch**
- The app launches directly — there is no installer. Nothing is written to `Program Files`.
- A `SecureFlow_Vault/` folder will be created in the same directory as the EXE to store your encrypted vault.

**Step 4 — Set Your Master Password**
- On first run, you will be prompted to create a **Master Password**.
- This password encrypts your vault using AES-256-GCM. **There is no recovery option if lost.**
- Choose a strong, memorable passphrase (e.g., `correct-horse-battery-staple`).

**Step 5 — (Optional) AWS Cloud Sync Setup**
- Go to **Settings → Cloud** and enter your AWS S3 bucket credentials.
- If skipping, the vault works fully offline.

### Features Overview

| Tab | What It Does |
|-----|-------------|
| **Vault** | Store & view encrypted files (PDF, DOCX, images, etc.) |
| **Passwords** | Save & auto-fill website credentials; hold entry to reveal password |
| **Authenticator** | TOTP 2FA codes (like Google Authenticator) |
| **ML Insights** | Real-time keystroke dynamics — flags anomalous typing patterns |
| **Cloud** | Sync vault to AWS S3 |

### Common Actions

**Add a file to the Vault:**
1. Click the **Upload** button in the Vault tab.
2. Select any file — it is encrypted and stored instantly.
3. Click the file name to preview. Click **Close File** to clear the viewer.

**Add a password:**
1. Go to the **Passwords** tab → Click **+Add Password**.
2. Fill in site, username, and password → Save.
3. Right-click or use the **Delete** button to remove an entry.

**Add a TOTP key (Authenticator):**
1. Go to **Authenticator** tab → Click **+Add Key**.
2. Paste the secret key from your website's 2FA setup page.
3. Live 30-second codes will appear. Click **Delete** to remove any entry.

**Lock the vault:**
- Press **Lock Vault** or close the window. Re-opening requires your master password.

---

## 📱 Installing the Android App (SecureFlow_Mobile_v1.0.0.apk)

### System Requirements
- **OS:** Android 7.0 (Nougat) or later
- **RAM:** 2 GB minimum
- **Storage:** 200 MB free space
- **Internet:** Required for cloud sync; core features work offline

### Step-by-Step Installation

**Step 1 — Transfer the APK**
Transfer `SecureFlow_Mobile_v1.0.0.apk` to your Android device using one of:
- USB cable (drag & drop to Downloads folder)
- Google Drive / WhatsApp / Email attachment
- ADB: `adb install SecureFlow_Mobile_v1.0.0.apk`

**Step 2 — Allow Unknown Sources**
Android blocks APKs from outside the Play Store by default. To allow:
- Open **Settings → Apps** (or Security & Privacy)
- Tap **Install unknown apps**
- Select **Files** (or your file manager app)
- Toggle **Allow from this source** → ON

> On newer Android: When you tap the APK, Android will prompt you directly. Tap **Settings** in that prompt, enable the toggle, then press **Back** and **Install**.

**Step 3 — Install**
1. Open your file manager and navigate to Downloads.
2. Tap `SecureFlow_Mobile_v1.0.0.apk`.
3. Tap **Install** when prompted.
4. Tap **Open** when installation is complete.

**Step 4 — First Launch & Login**
- The app will request camera permission (for QR code scanning) and storage permission.
- **Grant both permissions** for full functionality.
- Log in using the same master credentials configured in the desktop app.

### Features Overview

| Screen | What It Does |
|--------|-------------|
| **Dashboard** | Quick access to vault health and recent activity |
| **Vault** | Browse and decrypt stored documents |
| **Passwords** | View credentials; hold password field to reveal |
| **Authenticator** | Scan QR codes or enter keys for TOTP 2FA |
| **Settings** | Configure cloud sync, biometric unlock, and app theme |

### Common Actions

**Scan a new TOTP QR code:**
1. Open **Authenticator** tab.
2. Tap the **+** button → choose **Scan QR Code**.
3. Point camera at the 2FA QR code on your website.

**View a document:**
1. Open **Vault** tab.
2. Tap any file — it decrypts and opens in the built-in viewer.

**Biometric unlock (optional):**
1. Open **Settings → Security**.
2. Enable **Biometric Login** — subsequent logins will use fingerprint/face.

---

## 🔗 Linking Desktop & Mobile (Cloud Sync)

For passwords and TOTP codes to sync between desktop and mobile:

1. **On Desktop:** Go to Settings → Cloud → Enter your AWS S3 credentials → Click **Save & Sync**.
2. **On Mobile:** Go to Settings → Cloud Sync → Enter the same credentials → Tap **Connect**.
3. The **Sync** button in each app will push/pull encrypted data from the shared S3 bucket.

> All data is encrypted on your device **before** being uploaded. The cloud never sees your plaintext data.

---

## 🛡️ Security Notes

- Your **Master Password** is never stored anywhere — not on device, not in the cloud.
- All encryption uses **AES-256-GCM** with HMAC-SHA256 integrity verification.
- The HMAC oracle runs on a paired **ESP32 hardware token** (optional hardware tether).
- The **keystroke ML engine** (desktop only) builds a behavioral baseline over your first 50 login sessions and will alert on anomalous typing patterns.

---

## ❓ Troubleshooting

### Windows
| Issue | Fix |
|-------|-----|
| App won't open after SmartScreen | Right-click → Properties → Unblock → OK |
| Vault folder not found error | Ensure the EXE and `SecureFlow_Vault/` folder are in the same directory |
| Cloud sync fails | Check AWS credentials in Settings and ensure S3 bucket policy allows PutObject/GetObject |
| Antivirus quarantines the EXE | Add an exclusion for the EXE in your antivirus settings |

### Android
| Issue | Fix |
|-------|-----|
| "App not installed" error | Ensure "Unknown sources" is enabled for your file manager |
| Camera permission denied | Settings → Apps → SecureFlow → Permissions → Camera → Allow |
| APK file corrupt | Re-download the APK; verify MD5 if provided |
| Login fails on mobile | Ensure you're using the same master password as the desktop app |

---

## 📋 Uninstalling

**Windows:** Delete `SecureFlow_Vault_v1.0.0.exe` and the `SecureFlow_Vault/` data folder. No registry entries are created.

**Android:** Settings → Apps → SecureFlow Mobile → Uninstall.

---

## 📄 Version History

| Version | Date | Notes |
|---------|------|-------|
| v1.0.0 | June 2026 | Initial public release — Vault, Passwords, Authenticator, ML Insights, Cloud Sync |

---

*For source code, architecture documentation, and firmware (ESP32 HMAC Oracle), visit the [GitHub Repository](https://github.com/SushilChandaragi/SecureFlow).*
