# SecureFlow Mobile Companion App (Flutter)

The SecureFlow Mobile App is a Flutter-based companion that works in zero-knowledge parity with the SecureFlow Desktop client. It allows users to decrypt cloud-synced documents, manage local credentials, and generate TOTP authentication codes.

---

## 1. Features

- **Biometric Authentication**: Local biometric login via Fingerprint/Face authentication (Android BiometricPrompt).
- **NFC Tag Pairing & Authentication**: Unlocking the vault using a physical NDEF-formatted NFC tag.
- **Local Credentials Store**: Encrypted username/password pairings stored securely in a local SQLite database.
- **Authenticator Tab**: TOTP (Time-based One-Time Password) generation (compliant with RFC 6238).
- **In-Memory Document Viewer**: Inline PDF reader that decrypts documents into RAM and renders them without writing them to disk.
- **Bulk Sync Manager**: A dedicated "SYNC ALL" button inside the document vault screen to synchronize local unsynced files with AWS S3.

---

## 2. Configuration & Pairing

Before using cloud operations, configure the mobile app to pair with the desktop client:

1. **AWS S3 Configuration**:
   - Go to **Settings** -> **AWS S3 Credentials**.
   - Input your S3 Access Key ID, Secret Access Key, Region, and Bucket Name matching the desktop `.env` file.
2. **Desktop Secret Pairing**:
   - Paste the exact contents of the desktop `mock_hardware_secret.txt` file (e.g., `SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy`) into the **Desktop Vault Secret** field.
   - This aligns the HKDF derivation parameters so that files encrypted on the desktop can be successfully decrypted on mobile.
3. **NFC Hardware Key Setup**:
   - Format a MIFARE Classic 1K or NDEF-compatible NFC tag.
   - Write a Text (TNF_WELL_KNOWN, RTD_TEXT) record using a writer application (like "NFC Tools").
   - Set the text payload to: `SECUREFLOW-NFC-KEY-V1-[8CHARS]` (replace the last 8 characters with a unique uppercase alphanumeric sequence).
   - On the first scan in the app, the tag binds to secure storage. Subsequent scans will authenticate and unlock the vault.

---

## 3. Storage Architecture

- **Secure Storage**: Flutter Secure Storage (Android Keystore secure enclave) is used to store high-value settings (AWS credentials, the paired desktop secret, and the expected NFC token value).
- **Local SQLite DB**: Local data is stored encrypted under `databases/secureflow.db`.
  - Credentials and TOTP JSON models are encrypted as V3 envelopes, base64-encoded, and stored in SQLite TEXT columns.
  - Documents are encrypted and stored directly as SQLite BLOB data.

---

## 4. How to Build & Run

### Prerequisites
- Flutter SDK (v3.19+ recommended)
- Android SDK (target API 34+)
- An active Android emulator or physical device with NFC capabilities

### Running the App
1. Navigate to the mobile folder:
   ```bash
   cd secureflow_mobile
   ```
2. Get dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run
   ```

### Running Tests
Verify cryptographic and S3 operations:
```bash
flutter test
```
The test suite includes `hkdf_parity_test.dart` to validate key derivation compatibility against Python-generated test parameters.
