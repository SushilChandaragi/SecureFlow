/// SecureFlow Mobile — SecureStorageService
///
/// Wraps flutter_secure_storage for saving sensitive config (AWS creds, mock secret).
/// Uses Android Keystore-backed AES encryption.
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
  static const _kNfcExpected     = 'sf_nfc_expected_secret';
  static const _kPasswordStore   = 'sf_password_store_cache';
  static const _kTotpStore       = 'sf_totp_store_cache';

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

  // ── NFC Expected Secret (bind to one tag) ───────────────────────────────

  Future<void> saveNfcSecret(Uint8List secret) async {
    await _storage.write(key: _kNfcExpected, value: base64Encode(secret));
  }

  Future<Uint8List?> loadNfcSecret() async {
    final b64 = await _storage.read(key: _kNfcExpected);
    if (b64 == null) return null;
    return base64Decode(b64);
  }

  // ── Credential Cache (encrypted at app level too via crypto_service) ──────

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
