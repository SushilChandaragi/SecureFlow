/// SecureFlow Mobile — SecureStorageService
///
/// Wraps flutter_secure_storage for saving sensitive config (AWS creds, NFC key,
/// settings toggles, and credential/TOTP caches).
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _kAwsKeyId        = 'sf_aws_access_key_id';
  static const _kAwsSecret       = 'sf_aws_secret_access_key';
  static const _kAwsRegion       = 'sf_aws_region';
  static const _kS3Bucket        = 'sf_s3_bucket_name';
  static const _kMockHardware    = 'sf_mock_hardware_secret';
  static const _kDesktopSecret   = 'sf_master_vault_key'; // UTF-8 of mock_hardware_secret.txt
  static const _kNfcExpected     = 'sf_nfc_expected_secret';      // bytes (legacy)
  static const _kNfcExpectedStr  = 'sf_nfc_expected_string';      // plain UTF-8
  static const _kPasswordStore   = 'sf_password_store_cache';
  static const _kTotpStore       = 'sf_totp_store_cache';
  static const _kSettings        = 'sf_settings_json';

  // ── AWS Credentials ──────────────────────────────────────────────────────

  Future<void> saveAwsCredentials({
    required String accessKeyId,
    required String secretAccessKey,
    required String region,
    required String bucketName,
  }) async {
    await _storage.write(key: _kAwsKeyId,  value: accessKeyId);
    await _storage.write(key: _kAwsSecret, value: secretAccessKey);
    await _storage.write(key: _kAwsRegion, value: region);
    await _storage.write(key: _kS3Bucket,  value: bucketName);
  }

  Future<Map<String, String>?> loadAwsCredentials() async {
    final id  = await _storage.read(key: _kAwsKeyId);
    final sec = await _storage.read(key: _kAwsSecret);
    final reg = await _storage.read(key: _kAwsRegion);
    final bkt = await _storage.read(key: _kS3Bucket);
    if (id == null || sec == null || reg == null || bkt == null) return null;
    return {
      'accessKeyId': id,
      'secretAccessKey': sec,
      'region': reg,
      'bucketName': bkt,
    };
  }

  // ── Mock Hardware Secret ─────────────────────────────────────────────────

  Future<void> saveMockHardwareSecret(Uint8List secret) async {
    await _storage.write(key: _kMockHardware, value: base64Encode(secret));
  }

  Future<Uint8List?> loadMockHardwareSecret() async {
    final b64 = await _storage.read(key: _kMockHardware);
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  // ── Desktop Shared Secret (links mobile to desktop mock_hardware_secret.txt) ─

  /// Save the exact string contents of the desktop's mock_hardware_secret.txt.
  /// The secret string is trimmed to eliminate whitespace/newline mismatches.
  Future<void> saveDesktopSecret(String secret) async {
    await _storage.write(key: _kDesktopSecret, value: secret.trim());
  }

  /// Returns the raw UTF-8 bytes of the stored desktop secret, or null if not set.
  Future<Uint8List?> loadDesktopSecretBytes() async {
    final s = await _storage.read(key: _kDesktopSecret);
    if (s == null || s.isEmpty) return null;
    return Uint8List.fromList(utf8.encode(s));
  }

  Future<String?> loadDesktopSecretString() async {
    return _storage.read(key: _kDesktopSecret);
  }

  Future<void> clearDesktopSecret() async {
    await _storage.delete(key: _kDesktopSecret);
  }

  // ── NFC Expected Secret ─────────────────────────────────────────────────
  // We store the plain UTF-8 string from the tag (e.g. SECUREFLOW-NFC-KEY-V1-A3F9K2M7)
  // and compare strings, which is far more reliable than byte-level comparison.

  /// Save the NFC key as a trimmed plain string.
  Future<void> saveNfcSecretString(String secret) async {
    await _storage.write(key: _kNfcExpectedStr, value: secret.trim());
  }

  /// Load the stored NFC key string. Returns null if not yet bound.
  Future<String?> loadNfcSecretString() async {
    return _storage.read(key: _kNfcExpectedStr);
  }

  // Legacy bytes API (kept for compat, no longer used by auth flow)
  Future<void> saveNfcSecret(Uint8List secret) async {
    await _storage.write(key: _kNfcExpected, value: base64Encode(secret));
  }

  Future<Uint8List?> loadNfcSecret() async {
    final b64 = await _storage.read(key: _kNfcExpected);
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<void> saveSettings(Map<String, dynamic> settings) async {
    await _storage.write(key: _kSettings, value: jsonEncode(settings));
  }

  Future<Map<String, dynamic>> loadSettings() async {
    final raw = await _storage.read(key: _kSettings);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ── Credential Cache ──────────────────────────────────────────────────────

  Future<void> savePasswordStoreJson(String json) async {
    await _storage.write(key: _kPasswordStore, value: json);
  }

  Future<String?> loadPasswordStoreJson() async {
    return _storage.read(key: _kPasswordStore);
  }

  // ── TOTP Store ────────────────────────────────────────────────────────────

  Future<void> saveTotpStoreJson(String json) async {
    await _storage.write(key: _kTotpStore, value: json);
  }

  Future<String?> loadTotpStoreJson() async {
    return _storage.read(key: _kTotpStore);
  }

  // ── Clear All ─────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
