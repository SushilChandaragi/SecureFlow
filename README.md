# SecureFlow — Zero-Knowledge Security Vault (Desktop & Mobile)

SecureFlow is a zero-knowledge personal security vault consisting of a Windows Desktop client, an Android companion app, and a shared AWS S3 cloud vault. It securely manages passwords (credentials), TOTP authenticator keys (2FA), and critical files (PDFs, images).

---

## 1. System Architecture

SecureFlow splits responsibilities between a desktop engine and a mobile companion:

```
                  ┌──────────────────────────────┐
                  │      Windows Desktop App     │
                  │   (Python & CustomTkinter)   │
                  └──────────────┬───────────────┘
                                 │
                   [Boto3 Encrypted Uploads]
                                 │
                                 ▼
                  ┌──────────────────────────────┐
                  │       AWS S3 Sync Vault      │
                  │  (Zero-Knowledge Cloud Sync)  │
                  └──────────────┬───────────────┘
                                 │
                   [Dart S3 Encrypted Downloads]
                                 │
                                 ▼
                  ┌──────────────────────────────┐
                  │      Android Mobile App      │
                  │       (Flutter & Dart)       │
                  └──────────────────────────────┘
```

### Key Technical Pillars
- **Zero-Footprint Encryption**: Files decrypted on both platforms never touch the physical disk in plaintext form. They are decrypted directly into RAM buffers, displayed in-memory, and immediately zeroed out when closed.
- **Cryptographic Parity**: Both clients implement identical key derivation and encryption formats:
  - **KDF**: HKDF-SHA256 (32-byte salt, info parameter: `b"SecureFlow session key"`).
  - **Cipher**: AES-256-GCM (12-byte random IV, 16-byte authentication tag).
- **In-Memory Security**: RAM variables holding master key material are scrubbed directly using raw memory operations (`ctypes.memset` in Python, `fillRange(0)` in Dart) to mitigate cold-boot or memory dump attacks.

---

## 2. Recent Achievements & Current Status

We have stabilized the system and resolved key cross-platform synchronization blockers:

### What We Achieved:
1. **Dynamic Cloud Re-Encryption**: Desktop files encrypted in Mode H (Hardware port mode) are transparently translated in RAM to Mode M (Software/Mock secret mode) before being uploaded to S3. This ensures they can be opened by the mobile device without a physical ESP32 hardware attachment.
2. **S3 Path Escaping Fix**: Resolved a path double-escaping bug in the Flutter AWS S3 client where component encoding corrupted subfolder slash paths (`/`), returning `403 Forbidden` errors.
3. **NFC Decapsulation Rigor**: Replaced the custom NDEF text reader in Flutter with a robust UTF-8/UTF-16 decoder that strips null paddings, stopping pairing mismatches and "InvalidCipherTextException" crashes when using NFC tags.
4. **Mobile Bulk Sync**: Implemented a "SYNC ALL" button in the mobile document vault screen to allow one-click bulk uploading of local unsynced files.
5. **Keystroke Dynamics EDR**: The desktop client features a passive background intrusion detection agent (`global_agent.py`) that monitors key-press intervals, feeds a trained Isolation Forest model, and locks the vault if typing patterns diverge from the owner's baseline.

---

## 3. The SecureFlow V3 Binary Envelope

All files stored locally in the vault or synced to the cloud follow the V3 binary envelope layout:

```
┌──────────────┬──────────────┬──────────────────────┬──────────────────────┬──────────────────────┐
│  Magic (4B)  │  Mode (1B)   │ Handshake Nonce(32B) │   File Nonce (12B)   │   Ciphertext + Tag   │
│   "SFV3"     │  'M' or 'H'  │    HKDF Salt / IV    │     AES-GCM IV       │    Variable + 16B    │
└──────────────┴──────────────┴──────────────────────┴──────────────────────┴──────────────────────┘
```

---

## 4. Desktop Client Setup & Execution

### Prerequisites
- Windows OS
- Python 3.13 (or 3.10+)

### Setup
1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Configure environment variables in a local `.env` file (copied from `.env.example`):
   ```env
   AWS_ACCESS_KEY_ID=your_access_key
   AWS_SECRET_ACCESS_KEY=your_secret_key
   AWS_REGION=ap-south-1
   S3_BUCKET_NAME=your_bucket_name
   ```
3. Initialize the local Mock hardware secret:
   - Create `mock_hardware_secret.txt` in the root folder.
   - Enter a high-entropy secret string (e.g., `SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy`).

### Running the App
- Run the main desktop app:
  ```bash
  python main.py
  ```
- Run the active intrusion detection background agent:
  ```bash
  python global_agent.py
  ```

### Local Verification Tool
Verify file decryption integrity directly from the command line:
```bash
python verify_parity.py SecureFlow_Vault/example.pdf.enc
```
