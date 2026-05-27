// SecureFlow Microcopy, Empty States & Loading States (§11, §12, §13)
abstract final class SFCopy {
  // ── Premium Microcopy §11 ──────────────────────────────────────────
  static const loading      = 'ESTABLISHING SECURE ENCLAVE';
  static const logout       = 'PURGE SESSION';
  static const deleteFile   = 'CRYPTOGRAPHIC SHRED';
  static const authFail     = 'IDENTITY REJECTED';
  static const uploadDone   = 'ASSET SECURED TO GHOST WAREHOUSE';
  static const locked       = 'VAULT SEALED';
  static const unlocked     = 'ENCLAVE ACTIVE';
  static const sessionEnd   = 'SESSION TERMINATED. MEMORY PURGED.';
  static const copying      = 'CREDENTIAL EXTRACTED';
  static const clipboardClr = 'CLIPBOARD SANITIZED';
  static const decrypting   = 'DECRYPTING ASSET...';
  static const purging      = 'MEMORY PURGE COMPLETE';

  // ── Empty States §12 ──────────────────────────────────────────────
  static const vaultEmpty     = 'VAULT IS STERILE. NO ASSETS DETECTED.';
  static const passwordsEmpty = 'CREDENTIAL ARCHIVE EMPTY.';
  static const analyticsEmpty = 'NO THREAT VECTORS DETECTED.';
  static const totpEmpty      = 'NO AUTH KEYS ENROLLED.';

  // ── Loading State Terminal Output §13 ─────────────────────────────
  static const List<String> cryptoBootSequence = [
    '[OK] AES-256-GCM BOUND',
    '[OK] HKDF-SHA256 VERIFIED',
    '[OK] SESSION NONCE GENERATED',
    '[OK] SECURE ENCLAVE INITIALIZED',
    '[OK] MEMORY GUARD ACTIVE',
  ];

  // ── Screen Headers ────────────────────────────────────────────────
  static const identityRequired = 'IDENTITY VERIFICATION REQUIRED';
  static const awaitingNfc      = 'AWAITING NFC KEY TAP';
  static const awaitingBio      = 'PRESENT BIOMETRIC';
  static const threatIntel      = 'THREAT INTELLIGENCE';
  static const secureUpload     = 'SECURE UPLOAD';
  static const ramOnly          = 'RAM-ONLY SESSION';
  static const panicClose       = 'PANIC CLOSE';
  static const vaultDestruction = 'VAULT DESTRUCTION';
  static const emergencyLock    = 'EMERGENCY LOCK MODE';

  // ── Session Timer ─────────────────────────────────────────────────
  static const initializingEnclave = 'INITIALIZING SECURE ENCLAVE...';
}
