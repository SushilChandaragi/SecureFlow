/// SecureFlow Mobile — AuthService
///
/// Replaces the ESP32 serial handshake with:
///   1. Fingerprint / Face biometric (local_auth)
///   2. NFC tag reading (nfc_manager) — 32-byte payload on tag = the hardware secret
library;

import 'dart:typed_data';
import 'package:local_auth/local_auth.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../utils/logger.dart';

class AuthServiceException implements Exception {
  final String message;
  const AuthServiceException(this.message);
  @override
  String toString() => 'AuthServiceException: $message';
}

class AuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  // ── Biometric ─────────────────────────────────────────────────────────────

  /// Returns true if the device can perform biometric authentication.
  Future<bool> isBiometricAvailable() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final isDeviceSupported = await _localAuth.isDeviceSupported();
    return canCheck && isDeviceSupported;
  }

  /// Returns the list of enrolled biometrics.
  Future<List<BiometricType>> getEnrolledBiometrics() async {
    return _localAuth.getAvailableBiometrics();
  }

  /// Prompt the user for biometric authentication.
  ///
  /// Returns true on success, false on cancellation.
  /// Throws [AuthServiceException] on device error.
  Future<bool> authenticateWithBiometric({
    String reason = 'PRESENT BIOMETRIC TO UNLOCK VAULT',
  }) async {
    try {
      sfLog('AuthService: biometric prompt start');
      final authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device credential fallback
          stickyAuth: true,
        ),
      );
      sfLog('AuthService: biometric result=$authenticated');
      return authenticated;
    } catch (e) {
      sfLog('AuthService: biometric error=$e');
      throw AuthServiceException('Biometric error: $e');
    }
  }

  // ── NFC Tag ───────────────────────────────────────────────────────────────

  /// Returns true if NFC hardware is available on this device.
  Future<bool> isNfcAvailable() async {
    return NfcManager.instance.isAvailable();
  }

  /// Initiate NFC tag read session.
  ///
  /// Reads up to 32 bytes from the NDEF text record or raw NDEFRecord payload.
  /// The 32 bytes act as the "hardware secret" replacement.
  ///
  /// [onPayload] is called with the raw bytes from the tag.
  /// [onError]   is called if the session fails.
  Future<void> startNfcSession({
    required void Function(Uint8List payload) onPayload,
    required void Function(String error) onError,
    String alertMessage = 'TAP NFC TAG TO AUTHENTICATE',
  }) async {
    final available = await isNfcAvailable();
    if (!available) {
      sfLog('AuthService: NFC unavailable');
      onError('NFC_UNAVAILABLE');
      return;
    }

    sfLog('AuthService: NFC session start');

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          final payload = _extractPayload(tag);
          if (payload == null || payload.isEmpty) {
            onError('NFC_EMPTY_TAG');
            NfcManager.instance.stopSession(errorMessage: 'EMPTY TAG');
            return;
          }
          sfLog('AuthService: NFC payload len=${payload.length}');
          // Pad or trim to exactly 32 bytes.
          final secret = _normalise32(payload);
          onPayload(secret);
          NfcManager.instance.stopSession();
        } catch (e) {
          sfLog('AuthService: NFC read error=$e');
          onError('NFC_READ_ERROR: $e');
          NfcManager.instance.stopSession(errorMessage: 'READ FAILED');
        }
      },
      onError: (error) async {
        sfLog('AuthService: NFC session error=${error.message}');
        onError('NFC_SESSION_ERROR: ${error.message}');
      },
    );
  }

  /// Stop any active NFC session.
  Future<void> stopNfcSession() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Extract raw bytes from an NFC tag.
  /// Tries NDEF text record → NDEF raw payload → NfcA raw data.
  Uint8List? _extractPayload(NfcTag tag) {
    final ndef = Ndef.from(tag);
    if (ndef != null) {
      final cached = ndef.cachedMessage;
      if (cached != null && cached.records.isNotEmpty) {
        for (final rec in cached.records) {
          final payload = rec.payload;
          if (payload.isNotEmpty) {
            // NDEF Text Record starts with 1 status byte + language code.
            // Skip the language prefix if present.
            if (payload[0] == 0x02 || payload[0] == 0x03) {
              final langLen = payload[0] & 0x3F;
              if (payload.length > 1 + langLen) {
                return Uint8List.fromList(
                  payload.sublist(1 + langLen),
                );
              }
            }
            return Uint8List.fromList(payload);
          }
        }
      }
    }
    return _extractUid(tag);
  }

  Uint8List? _extractUid(NfcTag tag) {
    final data = tag.data;
    Uint8List? fromIdentifier(dynamic identifier) {
      if (identifier is Uint8List) return identifier;
      if (identifier is List) {
        return Uint8List.fromList(identifier.cast<int>());
      }
      return null;
    }

    final nfca = data['nfca'];
    if (nfca is Map && nfca['identifier'] != null) {
      return fromIdentifier(nfca['identifier']);
    }
    final mfc = data['mifareclassic'];
    if (mfc is Map && mfc['identifier'] != null) {
      return fromIdentifier(mfc['identifier']);
    }
    final mfu = data['mifareultralight'];
    if (mfu is Map && mfu['identifier'] != null) {
      return fromIdentifier(mfu['identifier']);
    }
    if (data['identifier'] != null) {
      return fromIdentifier(data['identifier']);
    }
    return null;
  }

  /// Normalise raw bytes to exactly 32 bytes (pad with zeros or truncate).
  Uint8List _normalise32(Uint8List bytes) {
    if (bytes.length == 32) return bytes;
    final out = Uint8List(32);
    final copyLen = bytes.length < 32 ? bytes.length : 32;
    out.setRange(0, copyLen, bytes);
    return out;
  }
}
