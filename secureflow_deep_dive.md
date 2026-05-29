# SecureFlow — Complete System Deep Dive
### A beginner-friendly explanation of every file, every concept, every data flow

---

## What Is SecureFlow?

SecureFlow is a **personal security vault** — think of it like a very secure safe that holds:
- Passwords (called Credentials)
- Authenticator codes (TOTP — 6-digit codes that change every 30 seconds, like Google Authenticator)
- Important documents (PDFs, files)
- All of the above encrypted, both on your computer and in the cloud (AWS S3)

It has **two parts** that work together:
1. **Desktop App** — a Python program that runs on Windows
2. **Android App** — a Flutter app on your phone

Both are designed to share the same encrypted files through AWS S3 cloud storage.

---

## The Master Idea: Encryption

Before explaining files, you need to understand the core idea.

**Encryption** means scrambling data so only someone with the right key can read it.
SecureFlow uses **AES-256-GCM** — the same encryption used by banks and governments.

The key is 32 random bytes (256 bits). It is never written to disk. It lives only in RAM.

To produce this key, SecureFlow uses **HKDF-SHA256** (a standard key derivation function):

```
INPUT  : A "secret" (hardware secret or NFC tag text)
         + A random "nonce" (one-time number, 32 bytes)
OUTPUT : A 32-byte AES encryption key
```

Every time you log in, a new nonce is generated, producing a fresh session key.
But old files can still be decrypted because the blob (encrypted file) stores the nonce inside it,
so the key can always be re-derived:

```
Re-derive key = HKDF(same_secret + stored_nonce_from_blob)
```

---

## The Blob Format — How Encrypted Data Is Stored

Every encrypted piece of data (password, document, TOTP key) is stored as a "blob":

```
[4 bytes:  magic header "SFV3"]
[1 byte:   mode — M=mock/software, H=hardware/ESP32]
[32 bytes: handshake nonce — the random number used to derive the key]
[12 bytes: file nonce — AES-GCM's own random number]
[N bytes:  ciphertext + 16-byte authentication tag]
```

The authentication tag (last 16 bytes of ciphertext) is AES-GCM's built-in tamper detection.
If even one byte is changed, decryption fails immediately with InvalidCipherTextException.

---

# PART 1: THE DESKTOP PYTHON APP

```
SecureFlowV1/
├── main.py                     Entry point — starts the app
├── crypto_engine.py            ALL encryption/decryption logic
├── cloud_manager.py            AWS S3 upload/download
├── vault_gui.py                The entire visual interface (tkinter)
├── secureflow_logger.py        Logging and telemetry system
├── mock_hardware_secret.txt    The temporary "key" (replaces ESP32)
├── .env                        AWS credentials (never committed to git)
├── requirements.txt            Python packages needed
└── SecureFlow_Vault/           Where encrypted files are stored locally
```

---

### `main.py` — The Starting Point

This is the very first file Python runs. It does 3 things:
1. Initialises the logger
2. Creates a CryptoEngine object (the encryption brain)
3. Creates the VaultGUI window and passes the crypto engine to it

Think of it as the ignition key — it wires everything together and starts the engine.

---

### `crypto_engine.py` — The Encryption Brain

**This is the most important file in the entire project.**

It is a Python class called CryptoEngine with these capabilities:

#### Two Ways to Unlock (Handshake)

**Mode 1: Mock Handshake (current / development)**

```python
def mock_handshake(self):
    secret = open("mock_hardware_secret.txt").read_bytes()
    # "SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy\r\n"
    nonce  = random_32_bytes()
    key    = HKDF(secret, nonce)   # derives 32-byte AES key
    # Key stored only in RAM
```

This reads the text file as raw bytes and uses it as the secret.
It is a placeholder for the ESP32.

**Mode 2: Hardware Handshake (future / real security)**

```python
def hardware_handshake(self, com_port):
    nonce    = random_32_bytes()
    response = esp32.hmac(nonce)   # send nonce to ESP32, get HMAC back
    key      = HKDF(response + nonce)
```

Here, the ESP32 microcontroller computes an HMAC using a secret key burned into its hardware.
The secret never leaves the chip. This is true hardware-rooted security.

#### Encrypting a File

```
plaintext → AES-256-GCM encrypt → blob written to SecureFlow_Vault/
```

The original file is deleted from disk after encryption (zero-footprint design).

#### Decrypting a File

```
blob from disk/S3 → read nonce from blob header → re-derive key → AES-256-GCM decrypt → bytes in RAM only
```

Decrypted bytes are NEVER written to disk. They are only shown in the viewer and then discarded.

#### Locking the Vault

```python
def lock_vault(self):
    ctypes.memset(key_address, 0, 32)  # overwrite RAM with zeros
```

The key is literally zeroed out in memory using a system call.
ctypes.memset is a direct memory operation that Python's garbage collector cannot interfere with.

---

### `cloud_manager.py` — AWS S3 Bridge

A simple, focused module that talks to Amazon S3:

| Method | What it does |
|--------|-------------|
| upload_vault_file(path) | Uploads a .enc file from disk to S3 |
| get_vault_inventory() | Lists all files in the S3 bucket |
| download_to_buffer(key) | Downloads a file from S3 directly into RAM — no disk write |

It reads AWS credentials from the .env file using python-dotenv.

The .env file contains:
```
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=ap-south-1
S3_BUCKET_NAME=your-bucket-name
```
This file is in .gitignore — it must never be pushed to GitHub.

---

### `vault_gui.py` — The Desktop Interface (1843 lines)

This is the visual layer. It is built with customtkinter (a modern-looking tkinter wrapper).
It is one large class VaultGUI with many sections:

#### Panels / Tabs Inside the App

| Tab | Purpose |
|-----|---------|
| VAULT | Encrypt local files and view the list |
| PASSWORD VAULT | Store and view encrypted username/password pairs |
| AUTHENTICATOR | TOTP code generator (like Google Authenticator) |
| CLOUD SYNC | Upload/download encrypted files to/from S3 |
| ML MONITOR | Anomaly detection on telemetry data |

#### Key Concepts in the GUI

**Thread Queue Pattern:**
The GUI runs on the main thread. Any background work (S3 upload, decryption of large files)
runs on a separate thread. The background thread posts results to a queue.Queue.
The main thread reads from this queue every 50ms and updates the UI.
This prevents the interface from freezing.

**In-Memory PDF Viewer:**
Documents are decrypted to RAM, passed to PyMuPDF (fitz) which renders each page as an image.
The image is shown in a scrollable frame. The decrypted bytes are kept in self._pdf_bytes
and explicitly deleted when the viewer closes.

**Password Store:**
Passwords are stored as a Python dictionary in memory, serialised to JSON,
encrypted as a V3 blob, and saved to passwords.enc in the vault folder.

**TOTP Store:**
TOTP secrets are stored similarly in auth_keys.enc.
The code generation uses pyotp.TOTP(secret).now() — standard RFC 6238.

---

### `secureflow_logger.py` — Telemetry and Audit Trail

This module does two things:

1. **Logging** — Writes all app events to a rotating log file (secureflow.log).
   Every encrypt, decrypt, upload, login attempt is recorded with a timestamp.

2. **Telemetry** — Records system metrics (CPU usage, RAM usage, keystroke timing)
   to telemetry.csv. This feeds the ML Monitor tab which detects anomalous behavior
   using scikit-learn's IsolationForest algorithm.

---

### `requirements.txt` — Dependencies

```
customtkinter   Modern GUI framework
cryptography    AES-GCM encryption, HKDF
boto3           AWS S3 client
PyMuPDF (fitz)  PDF rendering
pyotp           TOTP code generation
pandas          Telemetry data analysis
matplotlib      Charts for ML monitor
scikit-learn    Anomaly detection (IsolationForest)
python-dotenv   Load .env files
pyserial        ESP32 serial communication (future use)
pillow          Image processing
```

---

# PART 2: THE ANDROID FLUTTER APP

```
secureflow_mobile/
├── lib/
│   ├── main.dart                   App entry point
│   ├── app.dart                    Root widget, routing, lifecycle
│   ├── config/
│   │   ├── colors.dart             Design system colours
│   │   ├── typography.dart         Font styles
│   │   └── constants.dart          Spacing, radius, copy text
│   ├── models/
│   │   ├── credential.dart         Data shape: username/password
│   │   ├── totp_key.dart           Data shape: TOTP secret + issuer
│   │   ├── vault_document.dart     Data shape: local document metadata
│   │   ├── vault_file.dart         Data shape: S3 cloud file
│   │   └── user_profile.dart       Data shape: user display name
│   ├── services/
│   │   ├── crypto_service.dart         Encryption engine (mirrors Python)
│   │   ├── auth_service.dart           Biometric + NFC authentication
│   │   ├── database_service.dart       SQLite local storage
│   │   ├── cloud_service.dart          AWS S3 (Dart side)
│   │   ├── secure_storage_service.dart Secrets store (Android Keystore)
│   │   ├── totp_service.dart           TOTP code generation
│   │   └── vault_provider.dart         State management (Riverpod)
│   ├── screens/
│   │   ├── splash_screen.dart          Loading animation
│   │   ├── login_screen.dart           Fingerprint + NFC login
│   │   ├── dashboard_screen.dart       Home screen with stats
│   │   ├── password_vault_screen.dart  Credential manager
│   │   ├── authenticator_screen.dart   TOTP codes
│   │   ├── document_vault_screen.dart  Local encrypted docs
│   │   ├── cloud_vault_screen.dart     S3 cloud files
│   │   ├── document_viewer_screen.dart In-memory PDF viewer
│   │   ├── analytics_screen.dart       Usage charts
│   │   └── settings_screen.dart        Config + danger zone
│   ├── widgets/                    Reusable UI components
│   └── utils/
│       └── logger.dart             sfLog() debug logging
└── android/
    └── app/src/main/
        └── AndroidManifest.xml     Android permissions + config
```

---

## SERVICES LAYER — The Backend of the App

### `crypto_service.dart` — Mobile Encryption Engine

This is the Dart equivalent of crypto_engine.py. It implements the exact same algorithm
so that a file encrypted on the desktop can be decrypted on mobile and vice versa.

Uses the pointycastle Dart library (same algorithms as Python's cryptography library).

#### Two Handshake Modes

**Mock Handshake** (mirrors Python mock_handshake):
```dart
void mockHandshake(Uint8List hardwareSecret) {
  nonce      = random_32_bytes()
  sessionKey = HKDF(hardwareSecret, nonce)
  // stored in RAM only
}
```

**NFC Handshake** (mobile-specific alternative):
```dart
void nfcHandshake(Uint8List nfcPayload) {
  // nfcPayload = UTF-8 bytes of "SECUREFLOW-NFC-KEY-V1-A3F9K2M7"
  // padded/trimmed to 32 bytes
  sessionKey = HKDF(nfcPayload)
}
```

Locking: Dart's fillRange(0, length, 0) zeroes the key bytes in the Uint8List.

---

### `auth_service.dart` — Who Is This Person?

Two authentication methods:

**Biometric (Fingerprint / Face)**
Uses the local_auth Flutter plugin. It calls Android's BiometricPrompt API.
If the OS says "yes, this is the right person", the app then derives the crypto key.
Important: biometric ONLY proves identity to Android — it does not produce the crypto key.
After biometric success, the app reads the stored secret and runs mockHandshake().

**NFC Tag Reading**
Uses the nfc_manager plugin. When you tap the NFC button in the app:
1. The app registers as the foreground NFC dispatcher
2. When you bring your Mifare Classic tag close, Android reads the NDEF record
3. The app extracts the text payload ("SECUREFLOW-NFC-KEY-V1-A3F9K2M7")
4. First ever tap: saves this string to secure storage (binding)
5. Subsequent taps: compares against stored string (verification)
6. On match: runs nfcHandshake() with the string bytes

The NDEF text record format is:
```
byte[0]   = status byte (0x02 = UTF-8, lang len = 2)
byte[1-2] = "en" (language code)
byte[3+]  = actual text ("SECUREFLOW-NFC-KEY-V1-A3F9K2M7")
```
The parser skips the language prefix and extracts only the text.

---

### `secure_storage_service.dart` — The Device's Secret Safe

This service uses Flutter Secure Storage which on Android uses Android Keystore.
Android Keystore is a hardware-backed secure enclave — secrets stored here cannot be
extracted even by other apps on a rooted device.

**What it stores:**

| Key | Content |
|-----|---------|
| sf_aws_access_key_id | AWS Access Key |
| sf_aws_secret_access_key | AWS Secret |
| sf_aws_region | e.g. "ap-south-1" |
| sf_s3_bucket_name | S3 bucket name |
| sf_mock_hardware_secret | Random 32-byte secret (base64 encoded) |
| sf_desktop_shared_secret | Content of mock_hardware_secret.txt (links to desktop) |
| sf_nfc_expected_string | The NFC tag text that was bound on first tap |
| sf_settings_json | User preferences (JSON) |

**Why base64?**
Secure storage only handles strings. Raw binary bytes are encoded to base64
(A-Z, 0-9 safe characters) before storing and decoded when reading.

---

### `database_service.dart` — Local Encrypted Storage (SQLite)

SQLite is a file-based database that lives on the device at:
```
/data/data/com.secureflow.secureflow_mobile/databases/secureflow.db
```

The database has 3 tables:

#### Table: `credentials`
| Column | Type | Purpose |
|--------|------|---------|
| id | TEXT | UUID primary key |
| encrypted_json | TEXT | Base64(AES-256-GCM encrypted JSON) |
| updated_at | INTEGER | Unix timestamp in milliseconds |

A credential in plain form looks like:
```json
{"storeKey": "uuid", "service": "Gmail", "username": "user@gmail.com", "password": "hunter2"}
```
This JSON is UTF-8 encoded, encrypted to a V3 blob, base64 encoded, then stored as TEXT.

#### Table: `totp_keys`
Same structure. Plain form:
```json
{"id": "uuid", "issuer": "GitHub", "account": "user@email.com", "secret": "JBSWY3DPEHPK3PXP"}
```

#### Table: `documents`
| Column | Type | Purpose |
|--------|------|---------|
| id | TEXT | UUID |
| name | TEXT | Original filename |
| size | INTEGER | Size in bytes (plaintext) |
| mime | TEXT | "application/pdf", "image/jpeg", etc. |
| encrypted_blob | BLOB | Raw AES-256-GCM blob stored as binary |
| updated_at | INTEGER | Timestamp |
| is_synced | INTEGER | 0=local only, 1=uploaded to S3 |

**Completer Pattern:**
SQLite's openDatabase() is asynchronous (takes 100-500ms).
A Completer ensures that if 10 read operations happen simultaneously before
the database is open, they all wait for the single open() to complete — none crash.

---

### `cloud_service.dart` — AWS S3 from Dart

The mobile S3 client.

| Operation | What happens |
|-----------|-------------|
| Upload | Encrypts bytes, uploads raw blob bytes to S3 as filename.enc |
| List | Gets list of .enc files in the bucket |
| Download | Downloads raw blob bytes from S3, decrypts in RAM, shows viewer |

AWS credentials are read from SecureStorageService (Android Keystore).

---

### `totp_service.dart` — 6-Digit Code Generator

TOTP (Time-based One-Time Password) works like this:
```
code = HMAC-SHA1(secret, floor(current_unix_time / 30))
     = truncated to 6 decimal digits
```
The secret is a base32 string (e.g. JBSWY3DPEHPK3PXP) stored in the database.
Every 30 seconds, a completely new code is produced.

totp_service.dart wraps the otp Flutter package and provides:
- generateCode(secret) — current 6-digit code string
- getSecondsRemaining() — seconds until next code (for the countdown ring)
- validateCode(secret, code) — checks if a code is valid (used for MFA setup)

---

### `vault_provider.dart` — The App's Brain (State Management)

Uses Riverpod — a state management framework. Think of it as a central control room
where all screens subscribe to data and get updated automatically when data changes.

**Providers (singletons):**

| Provider | Type | Purpose |
|----------|------|---------|
| cryptoServiceProvider | CryptoService | One instance, shared everywhere |
| authServiceProvider | AuthService | Biometric + NFC |
| storageServiceProvider | SecureStorageService | Android Keystore bridge |
| databaseServiceProvider | DatabaseService | SQLite |
| cloudServiceProvider | CloudService? | S3 (null if not configured) |

**Session State Machine:**
```
LOCKED (start)
    tap fingerprint
LOADING (verifying with Android OS)
    OS says OK
    read secret from Android Keystore
    run HKDF → derive AES key (in RAM only)
    attach crypto to database
UNLOCKED (all data accessible)
    after 2 minutes in background / manual lock
LOCKED (key zeroed from RAM)
```

**Data Providers (reactive lists):**
- credentialProvider — list of decrypted Credential objects
- totpProvider — list of TotpKey objects
- documentProvider — list of VaultDocument metadata
- vaultFilesProvider — list of S3 VaultFile objects

When you add a password, credentialProvider.notifier.add(cred) is called.
This triggers database_service.saveCredential() which encrypts and writes to SQLite.
Then credentialProvider notifies all listening screens to rebuild with the new list.

---

## SCREENS LAYER — What You See

### `splash_screen.dart` — Loading Animation
Shows an animated hexadecimal sequence while the app initialises providers.
After 2 seconds, navigates to login_screen.dart.

### `login_screen.dart` — Authentication Gate
Two options:
1. Fingerprint button — calls auth_service.authenticateWithBiometric() then session.unlockWithBiometric()
2. NFC button — starts NFC session, on tag read calls session.unlockWithNfcString()

A wave animation (sine wave drawn with CustomPainter) runs continuously in the background.
NFC button pulses with opacity animation while scanning.

### `dashboard_screen.dart` — Home
Shows live statistics pulled from providers:
- Number of saved credentials
- Number of TOTP keys
- Number of local documents
- Cloud sync status (connected/disconnected)

### `password_vault_screen.dart` — Credential Manager
- List of all saved username/password entries
- Tap to copy password
- Swipe to delete
- FAB button to add new credential dialog
- Edit loads existing values into form fields

### `authenticator_screen.dart` — TOTP Codes
- List of all TOTP accounts with live 6-digit codes
- Circular countdown ring showing seconds until next refresh
- Add via QR code scan or manual secret entry
- Code updates every 30 seconds automatically

### `document_vault_screen.dart` — Local Documents
- Pick any file from device storage
- File is read into RAM (never touches disk path)
- Encrypted with session key, stored in SQLite documents table
- Tap to view — decrypted in RAM, rendered by Syncfusion PDF viewer
- Upload to S3 button — encrypts blob, uploads

### `cloud_vault_screen.dart` — S3 Cloud Files
- Lists all .enc files in the configured S3 bucket
- Upload button: picks file, encrypts, uploads
- Tap any file: downloads to RAM, decrypts, opens document viewer

### `document_viewer_screen.dart` — In-Memory PDF Renderer
- Accepts either decrypted bytes or a VaultFile (downloads from S3 first)
- Uses Syncfusion Flutter PDF Viewer (SfPdfViewer.memory(bytes))
- Decrypted bytes never written to any file
- On close: bytes set to null, Dart garbage collector reclaims RAM

### `settings_screen.dart` — Configuration + Danger Zone

Sections:
1. AWS S3 Credentials — accessKeyId, secret, region, bucket name + Desktop Vault Secret
2. NFC Key Manager — shows bound NFC tag string, reset option
3. Security Settings — toggles (auto-lock, blur on background)
4. Cloud Status — shows S3 connection status, sync stats
5. Danger Zone (red section):
   - EMERGENCY LOCK — immediately zeros the key and returns to login
   - CLEAR CORRUPT DB ROWS — wipes all SQLite rows (use after crypto migration)
   - VAULT DESTRUCTION — clears everything in Android Keystore + SQLite

### `analytics_screen.dart` — Charts
Shows usage patterns:
- Credentials added over time
- Document uploads over time
- Auth method breakdown (fingerprint vs NFC)

---

## DATA FLOW: Complete Example — Saving a Password

Here is the complete journey when you type a password and hit Save:

```
1. User types: Service="Gmail", User="me@gmail.com", Pass="hunter2"

2. PasswordVaultScreen calls:
   ref.read(credentialProvider.notifier).add(cred)

3. CredentialNotifier calls:
   database_service.saveCredential(cred)

4. DatabaseService:
   a. JSON encode: {"service":"Gmail","username":"me@...","password":"hunter2"}
   b. UTF-8 encode to raw bytes
   c. crypto_service.encryptToBlob(bytes)
      generates random 12-byte file nonce
      AES-256-GCM encrypt with session key
      assembles blob: [SFV3][M][32B hs-nonce][12B file-nonce][ciphertext+tag]
   d. base64.encode(blob) = safe string
   e. SQLite INSERT: id=UUID, encrypted_json=base64string, updated_at=timestamp

5. Database file on disk contains ONLY the encrypted base64 string.
   If someone copies secureflow.db they see pure gibberish.

6. CredentialNotifier updates its list
   PasswordVaultScreen rebuilds and shows new entry
```

---

## DATA FLOW: Complete Example — Reading a Password Back

```
1. App starts, user fingerprints, session unlocks
   HKDF re-derives the SAME key (same secret from Android Keystore + blob's own nonce)

2. PasswordVaultScreen loads, credentialProvider triggers loadCredentials()

3. DatabaseService.loadCredentials():
   a. SQLite SELECT all rows from credentials
   b. For each row:
      base64.decode(encrypted_json) = raw blob bytes
      crypto_service.decryptBlob(blob)
        reads blob header to find nonce
        re-derives key: HKDF(hardwareSecret, blobNonce)
        AES-256-GCM decrypt = plaintext bytes
      utf8.decode = JSON string = Credential object
   c. Returns list of Credential objects

4. PasswordVaultScreen displays: "Gmail — me@gmail.com — ••••••••"
```

---

## DATA FLOW: Desktop to Cloud to Mobile

```
DESKTOP:
1. User opens PDF on desktop app
2. crypto_engine.encrypt_file(path)
   reads mock_hardware_secret.txt as bytes
   HKDF(secret, random_nonce) = AES key
   encrypts file, saves as file.pdf.enc in SecureFlow_Vault/
3. User clicks "Sync to Cloud"
   cloud_manager.upload_vault_file("file.pdf.enc")
   boto3 uploads to S3

          <<  AWS S3 on Amazon servers  >>

MOBILE:
4. User opens Cloud Vault screen
5. cloud_service.listFiles() shows "file.pdf.enc"
6. User taps the file
7. cloud_service.downloadToMemory("file.pdf.enc") = raw blob bytes in RAM
8. crypto_service.decryptBlob(blob)
   reads blob: header=SFV3, mode=M, hs_nonce=32bytes
   looks up hardware_secret from Android Keystore
   (must be the SAME string as mock_hardware_secret.txt — set in Settings)
   HKDF(desktop_secret, hs_nonce_from_blob) = same key as desktop derived
   AES-256-GCM decrypt = plaintext PDF bytes
9. SfPdfViewer.memory(plaintextBytes) = PDF renders in app
10. User closes viewer, bytes = null, RAM freed
```

---

## Security Architecture Summary

| Layer | Technology | Where |
|-------|-----------|-------|
| Physical Auth | Fingerprint (Android BiometricPrompt) | Device hardware |
| NFC Auth | NDEF text comparison (Mifare Classic tag) | Phone NFC chip |
| Secret Storage | Android Keystore (hardware-backed) | Secure enclave |
| Key Derivation | HKDF-SHA256 | RAM only |
| Encryption | AES-256-GCM (authenticated encryption) | RAM only |
| Local DB | SQLite — all rows base64(AES blob) | App private storage |
| Cloud Storage | AWS S3 — raw AES blob bytes | Amazon servers |
| Plaintext | Never touches disk in any form | RAM only |
| Lock | Key bytes zeroed with fillRange(0) | Immediate |

---

## What Is Not Yet Implemented

| Feature | Status | What Is Needed |
|---------|--------|---------------|
| ESP32 hardware auth | Not connected | USB/BLE bridge in mobile app |
| MFA TOTP on login | Missing | Add TOTP verify step after biometric |
| Password sync to cloud | Missing | Encrypt JSON and upload to S3 |
| Biometric on desktop | Missing | Windows Hello integration |
| Cross-device TOTP sync | Missing | Shared encrypted JSON in S3 |
| NFC as real hardware root | Software only | HMAC-capable NFC token (YubiKey) |

---

## Current State in One Sentence

SecureFlow is a fully functional AES-256-GCM encrypted vault running in software-simulation mode,
where the ESP32 hardware chip is replaced by a text file secret, ready to be swapped for real hardware
the moment the ESP32 is connected — all the code paths for hardware mode already exist in both
the desktop (hardware_handshake) and the mobile (nfcHandshake is the placeholder).
