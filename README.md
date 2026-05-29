# SecureFlow Mobile — NFC Hardware Key

This project uses an NFC-based option to bind a physical tag as a way to unlock the mobile vault. Documentation moved from the in-app Settings to this README and secureflow_deep_dive.md to keep the app UI minimal.

## NFC Hardware Key

- Tag type: MIFARE Classic 1K (NDEF text record)
- Format: `SECUREFLOW-NFC-KEY-V1-[8CHARS]`

How it works

- First tap: the app reads the NDEF text payload and stores the exact string into secure storage (binding).
- Subsequent taps: the app compares the scanned text to the stored string; on match it derives a session key via HKDF and unlocks the vault.

How to write a tag

1. Install "NFC Tools" (or any NDEF writer app)
2. Add a Text record
3. Enter the full string: `SECUREFLOW-NFC-KEY-V1-ABCDEFG1` (replace last 8 chars)
4. Save to tag (MIFARE Classic / NDEF-compatible)

Resetting a tag

- Previously this was accessible from Settings → NFC KEY → VIEW / RESET. That UI has been removed; you can still reset the bound tag by using the Reset option in secureflow_deep_dive.md or by clearing the `sf_nfc_expected_string` entry from secure storage.

Security notes

- NFC tags used here are _not_ a hardware root — they store a plain-text key value. For a true hardware root, use a YubiKey or HMAC-capable token.
- Treat the tag like a second factor: keep it physically safe.
