/// SecureFlow Mobile — CryptoService
///
/// Fresh Dart implementation of the same cryptographic operations as the
/// Python desktop's CryptoEngine. All algorithms are identical so that
/// encrypted blobs are cross-platform compatible (mobile ↔ desktop).
///
/// Algorithm chain:
///   Key derivation : HKDF-SHA256 (same as Python: HKDF(SHA256, 32, salt, info))
///   Encryption     : AES-256-GCM  (same as Python: AESGCM(key).encrypt(nonce, data, None))
///   Blob format V3 : [SFV3][M|H][32-byte handshake nonce][12-byte file nonce][ciphertext+tag]
///
/// NOTE: This code is intentionally separate from the Python desktop code.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

// ─── Vault blob constants (must match Python desktop exactly) ────────────────

/// Magic header bytes for V3 blobs — b"SFV3" in ASCII.
final _kHeaderV3 = Uint8List.fromList([0x53, 0x46, 0x56, 0x33]);

/// Magic header bytes for V2 blobs — b"SFV2".
final _kHeaderV2 = Uint8List.fromList([0x53, 0x46, 0x56, 0x32]);

/// Magic header bytes for V1 blobs — b"SFV1".
final _kHeaderV1 = Uint8List.fromList([0x53, 0x46, 0x56, 0x31]);

/// Mode byte for mock (software) handshake — b"M" = 0x4D.
const _kModeMock = 0x4D;

/// Mode byte for hardware handshake — b"H" = 0x48.
// ignore: unused_element
const _kModeHardware = 0x48;

const _kKeySize         = 32;  // AES-256 = 32 bytes
const _kHandshakeNonce  = 32;  // HKDF salt / simulated hardware nonce
const _kFileNonce       = 12;  // AES-GCM standard 96-bit nonce
const _kGcmTagLen       = 16;  // AES-GCM authentication tag

/// HKDF info string — must match Python: b"SecureFlow session key"
final _kHkdfInfo = Uint8List.fromList('SecureFlow session key'.codeUnits);

// ─── Exceptions ──────────────────────────────────────────────────────────────

class CryptoServiceException implements Exception {
  final String message;
  const CryptoServiceException(this.message);
  @override
  String toString() => 'CryptoServiceException: $message';
}

// ─── CryptoService ───────────────────────────────────────────────────────────

class CryptoService {
  // Session key is kept as a Uint8List so it can be explicitly zeroed on lock.
  Uint8List? _sessionKey;
  Uint8List? _handshakeNonce;
  Uint8List? _hardwareSecret; // kept to re-derive key for cross-session decrypt
  Uint8List? _nfcPayload;     // kept to re-derive NFC key for cross-session decrypt
  String _handshakeMode = 'none';
  bool _isLocked = true;

  bool get isUnlocked => !_isLocked && _sessionKey != null;
  String get handshakeMode => _handshakeMode;

  // ── Key Derivation ─────────────────────────────────────────────────────────

  /// Perform mock handshake — derives session key from [hardwareSecret] bytes.
  void mockHandshake(Uint8List hardwareSecret) {
    _wipeKey();
    _hardwareSecret = Uint8List.fromList(hardwareSecret); // keep for re-derive
    _handshakeNonce = _randomBytes(_kHandshakeNonce);
    _sessionKey = _hkdfDerive(hardwareSecret, _handshakeNonce!);
    _handshakeMode = 'mock';
    _isLocked = false;
  }

  /// Perform NFC-backed handshake.
  void nfcHandshake(Uint8List nfcPayload) {
    _wipeKey();
    _nfcPayload = Uint8List.fromList(nfcPayload);
    _hardwareSecret = Uint8List.fromList(nfcPayload);
    _handshakeNonce = _randomBytes(_kHandshakeNonce);

    // Compute HMAC signature of _handshakeNonce using the NFC payload as key (Mode H parity)
    final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(_hardwareSecret!));
    final hmacResp = hmac.process(_handshakeNonce!);

    final ikm = Uint8List(_kHandshakeNonce * 2)
      ..setRange(0, _kHandshakeNonce, hmacResp)
      ..setRange(_kHandshakeNonce, _kHandshakeNonce * 2, _handshakeNonce!);
    _sessionKey = _hkdfDeriveFromIkm(ikm);
    _handshakeMode = 'nfc';
    _isLocked = false;
  }

  // ── Encryption ─────────────────────────────────────────────────────────────

  /// Encrypt [plaintext] and return a V3 blob compatible with the desktop.
  ///
  /// Blob format:
  ///   [4B magic][1B mode][32B handshake nonce][12B file nonce][ciphertext+16B tag]
  Uint8List encryptToBlob(Uint8List plaintext) {
    _requireKey();
    final fileNonce = _randomBytes(_kFileNonce);
    final ciphertext = _aesGcmEncrypt(_sessionKey!, fileNonce, plaintext);

    final modeByte = _handshakeMode == 'nfc' ? _kModeHardware : _kModeMock;

    return _assembleV3Blob(
      mode: modeByte,
      handshakeNonce: _handshakeNonce!,
      fileNonce: fileNonce,
      ciphertext: ciphertext,
    );
  }

  // ── Decryption ─────────────────────────────────────────────────────────────

  /// Decrypt a V1 / V2 / V3 blob and return raw plaintext bytes.
  /// Never writes anything to disk — works entirely in RAM.
  Uint8List decryptBlob(Uint8List blob) {
    _requireKey();

    if (blob.length < 4) {
      throw const CryptoServiceException('Blob too small — corrupted or invalid.');
    }

    final header = blob.sublist(0, 4);

    if (_bytesEqual(header, _kHeaderV3)) {
      return _decryptV3(blob);
    } else if (_bytesEqual(header, _kHeaderV2)) {
      return _decryptV2(blob);
    } else if (_bytesEqual(header, _kHeaderV1)) {
      return _decryptV1(blob);
    } else {
      throw const CryptoServiceException('Unrecognized blob header — not a SecureFlow file.');
    }
  }

  // ── Lock / Wipe ────────────────────────────────────────────────────────────

  /// Zero-fill the session key and all nonce material.
  void lockVault() {
    _wipeKey();
    _isLocked = true;
    _handshakeMode = 'none';
  }

  /// Update active hardware secret (used when desktop secret is configured/paired in settings).
  void updateHardwareSecret(Uint8List secret) {
    _wipeKey();
    _hardwareSecret = Uint8List.fromList(secret);
    _handshakeNonce = _randomBytes(_kHandshakeNonce);
    _sessionKey = _hkdfDerive(secret, _handshakeNonce!);
    _handshakeMode = 'mock';
    _isLocked = false;
  }

  /// Clear active hardware secret.
  void clearHardwareSecret() {
    _wipeKey();
    _isLocked = true;
    _handshakeMode = 'none';
  }

  // ── Internal — Format Decryptors ───────────────────────────────────────────

  Uint8List _decryptV3(Uint8List blob) {
    const minLen = 4 + 1 + _kHandshakeNonce + _kFileNonce + _kGcmTagLen;
    if (blob.length < minLen) {
      throw const CryptoServiceException('V3 blob too small — corrupted.');
    }

    final hsNonce   = blob.sublist(5, 5 + _kHandshakeNonce);
    final fileNonce = blob.sublist(5 + _kHandshakeNonce, 5 + _kHandshakeNonce + _kFileNonce);
    final ct        = blob.sublist(5 + _kHandshakeNonce + _kFileNonce);
    final mode      = blob[4];

    print('[SecureFlow] CryptoService: Decrypting V3 Blob. Mode: ${String.fromCharCode(mode)} (0x${mode.toRadixString(16)})');
    print('[SecureFlow] CryptoService: Handshake Nonce Hex: ${hsNonce.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}');
    print('[SecureFlow] CryptoService: File Nonce Hex: ${fileNonce.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}');
    print('[SecureFlow] CryptoService: Hardware Secret is Null: ${_hardwareSecret == null}');
    
    if (_hardwareSecret != null) {
      final secretStr = String.fromCharCodes(_hardwareSecret!);
      print('[SecureFlow] CryptoService: Hardware Secret Length: ${_hardwareSecret!.length} bytes');
      print('[SecureFlow] CryptoService: Hardware Secret String: "$secretStr"');
      print('[SecureFlow] CryptoService: Hardware Secret Hex: ${_hardwareSecret!.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}');
    }

    Uint8List? derivedKey;

    if (mode == _kModeMock) {
      if (_hardwareSecret == null) {
        throw const CryptoServiceException(
            'Desktop vault secret not available.\n'
            'Go to Settings → Configure AWS Credentials and paste the Desktop Vault Secret:\n'
            'SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy');
      }
      derivedKey = _hkdfDerive(_hardwareSecret!, hsNonce);
      print('[SecureFlow] CryptoService: Mode M Derived Key Hex: ${derivedKey.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}');
    } else if (mode == _kModeHardware) {
      if (_hardwareSecret == null) {
        throw const CryptoServiceException(
            'Desktop vault secret not available.\n'
            'Go to Settings → Configure AWS Credentials and paste the Desktop Vault Secret:\n'
            'SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy');
      }
      try {
        final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(_hardwareSecret!));
        final hmacResp = hmac.process(hsNonce);
        final ikm = Uint8List(_kHandshakeNonce * 2)
          ..setRange(0, _kHandshakeNonce, hmacResp)
          ..setRange(_kHandshakeNonce, _kHandshakeNonce * 2, hsNonce);
        derivedKey = _hkdfDeriveFromIkm(ikm);
        print('[SecureFlow] CryptoService: Mode H Simulated Hardware Derived Key Hex: ${derivedKey.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}');
        
        final pt = _aesGcmDecrypt(derivedKey, fileNonce, ct);
        print('[SecureFlow] CryptoService: Mode H Decryption SUCCESSFUL!');
        return pt;
      } catch (e) {
        print('[SecureFlow] CryptoService: Mode H Simulated Hardware Decryption Failed: $e');
        // Fall back to Mock derivation if simulated hardware fails
        derivedKey?.fillRange(0, derivedKey.length, 0);
        derivedKey = _hkdfDerive(_hardwareSecret!, hsNonce);
        print('[SecureFlow] CryptoService: Mode H Fallback Mock Derived Key Hex: ${derivedKey.map((b) => b.toRadixString(16).padLeft(2, "0")).join("")}');
      }
    } else {
      throw const CryptoServiceException('Unrecognized V3 encryption mode.');
    }

    try {
      final pt = _aesGcmDecrypt(derivedKey, fileNonce, ct);
      print('[SecureFlow] CryptoService: Fallthrough Decryption SUCCESSFUL!');
      return pt;
    } on Exception catch (e) {
      print('[SecureFlow] CryptoService: Fallthrough Decryption Failed: $e');
      rethrow;
    } finally {
      derivedKey.fillRange(0, derivedKey.length, 0);
    }
  }


  /// Decrypt a V2 blob: [SFV2][32B hs-nonce][12B file-nonce][ct+tag]
  Uint8List _decryptV2(Uint8List blob) {
    const minLen = 4 + _kHandshakeNonce + _kFileNonce + _kGcmTagLen;
    if (blob.length < minLen) {
      throw const CryptoServiceException('V2 blob too small — corrupted.');
    }

    final hsNonce   = blob.sublist(4, 4 + _kHandshakeNonce);
    final fileNonce = blob.sublist(4 + _kHandshakeNonce, 4 + _kHandshakeNonce + _kFileNonce);
    final ct        = blob.sublist(4 + _kHandshakeNonce + _kFileNonce);

    if (!_bytesEqual(hsNonce, _handshakeNonce!)) {
      throw const CryptoServiceException(
        'V2: Handshake nonce mismatch. Re-authenticate.');
    }
    return _aesGcmDecrypt(_sessionKey!, fileNonce, ct);
  }

  /// Decrypt a V1 blob: [SFV1][12B file-nonce][ct+tag]
  Uint8List _decryptV1(Uint8List blob) {
    const minLen = 4 + _kFileNonce + _kGcmTagLen;
    if (blob.length < minLen) {
      throw const CryptoServiceException('V1 blob too small — corrupted.');
    }

    final fileNonce = blob.sublist(4, 4 + _kFileNonce);
    final ct        = blob.sublist(4 + _kFileNonce);
    return _aesGcmDecrypt(_sessionKey!, fileNonce, ct);
  }

  // ── Internal — Crypto Primitives ──────────────────────────────────────────

  /// HKDF-SHA256 key derivation — mirrors Python: HKDF(SHA256, 32, salt=nonce, info=info)
  Uint8List _hkdfDerive(Uint8List ikm, Uint8List salt) {
    final hkdf = HKDFKeyDerivator(SHA256Digest());
    hkdf.init(HkdfParameters(ikm, _kKeySize, salt, _kHkdfInfo));
    final out = Uint8List(_kKeySize);
    hkdf.deriveKey(null, 0, out, 0);
    return out;
  }

  /// HKDF-SHA256 from raw IKM (NFC/Hardware variant — no separate salt).
  Uint8List _hkdfDeriveFromIkm(Uint8List ikm) {
    final hkdf = HKDFKeyDerivator(SHA256Digest());
    hkdf.init(HkdfParameters(ikm, _kKeySize, null, _kHkdfInfo));
    final out = Uint8List(_kKeySize);
    hkdf.deriveKey(null, 0, out, 0);
    return out;
  }

  /// AES-256-GCM encrypt — mirrors Python: AESGCM(key).encrypt(nonce, data, None)
  Uint8List _aesGcmEncrypt(Uint8List key, Uint8List nonce, Uint8List plaintext) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), _kGcmTagLen * 8, nonce, Uint8List(0));
    cipher.init(true, params);

    final out = Uint8List(cipher.getOutputSize(plaintext.length));
    int offset = cipher.processBytes(plaintext, 0, plaintext.length, out, 0);
    int finalLen = cipher.doFinal(out, offset);
    return out.sublist(0, offset + finalLen);
  }

  /// AES-256-GCM decrypt — mirrors Python: AESGCM(key).decrypt(nonce, ct, None)
  Uint8List _aesGcmDecrypt(Uint8List key, Uint8List nonce, Uint8List ciphertext) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), _kGcmTagLen * 8, nonce, Uint8List(0));
    cipher.init(false, params);

    try {
      final out = Uint8List(cipher.getOutputSize(ciphertext.length));
      int offset = cipher.processBytes(ciphertext, 0, ciphertext.length, out, 0);
      int finalLen = cipher.doFinal(out, offset);
      return out.sublist(0, offset + finalLen);
    } on InvalidCipherTextException catch (e) {
      throw CryptoServiceException('Decryption failed — wrong key or corrupted data: $e');
    }
  }

  // ── Internal — Helpers ────────────────────────────────────────────────────

  Uint8List _assembleV3Blob({
    required int mode,
    required Uint8List handshakeNonce,
    required Uint8List fileNonce,
    required Uint8List ciphertext,
  }) {
    final totalLen = 4 + 1 + _kHandshakeNonce + _kFileNonce + ciphertext.length;
    final blob = Uint8List(totalLen)
      ..setRange(0, 4, _kHeaderV3)
      ..[4] = mode
      ..setRange(5, 5 + _kHandshakeNonce, handshakeNonce)
      ..setRange(5 + _kHandshakeNonce, 5 + _kHandshakeNonce + _kFileNonce, fileNonce)
      ..setRange(5 + _kHandshakeNonce + _kFileNonce, totalLen, ciphertext);
    return blob;
  }

  void _requireKey() {
    if (_sessionKey == null || _isLocked) {
      throw const CryptoServiceException(
        'Vault is locked. Authenticate with biometric or NFC to unlock.');
    }
  }

  void _wipeKey() {
    _sessionKey?.fillRange(0, _sessionKey!.length, 0);
    _handshakeNonce?.fillRange(0, _handshakeNonce!.length, 0);
    _hardwareSecret?.fillRange(0, _hardwareSecret!.length, 0);
    _nfcPayload?.fillRange(0, _nfcPayload!.length, 0);
    _sessionKey = null;
    _handshakeNonce = null;
    _hardwareSecret = null;
    _nfcPayload = null;
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0; // constant-time compare
  }
}
