/// SecureFlow Mobile — Riverpod State Providers
///
/// Single source of truth for session state, vault contents, credentials, TOTP.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/vault_file.dart';
import '../models/credential.dart';
import '../models/totp_key.dart';
import '../models/user_profile.dart';
import '../services/crypto_service.dart';
import '../services/cloud_service.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';

// ─── Service Singletons ──────────────────────────────────────────────────────

final cryptoServiceProvider = Provider<CryptoService>((_) => CryptoService());
final authServiceProvider   = Provider<AuthService>((_)   => AuthService());
final storageServiceProvider= Provider<SecureStorageService>(
  (_) => SecureStorageService());

final cloudServiceProvider = FutureProvider<CloudService?>((ref) async {
  final storage = ref.watch(storageServiceProvider);
  final creds = await storage.loadAwsCredentials();
  if (creds == null) return null;
  return CloudService(
    bucketName: creds['bucketName']!,
    region:     creds['region']!,
    accessKeyId:     creds['accessKeyId']!,
    secretAccessKey: creds['secretAccessKey']!,
  );
});

// ─── Session State ───────────────────────────────────────────────────────────

class SessionState {
  final bool isUnlocked;
  final UserProfile? profile;
  final String statusMessage;
  final bool isError;
  final bool isLoading;

  const SessionState({
    this.isUnlocked = false,
    this.profile,
    this.statusMessage = '',
    this.isError = false,
    this.isLoading = false,
  });

  SessionState copyWith({
    bool? isUnlocked,
    UserProfile? profile,
    String? statusMessage,
    bool? isError,
    bool? isLoading,
  }) => SessionState(
        isUnlocked: isUnlocked ?? this.isUnlocked,
        profile:    profile ?? this.profile,
        statusMessage: statusMessage ?? this.statusMessage,
        isError:    isError ?? this.isError,
        isLoading:  isLoading ?? this.isLoading,
      );
}

class SessionNotifier extends StateNotifier<SessionState> {
  final CryptoService _crypto;
  final SecureStorageService _storage;

  SessionNotifier(this._crypto, this._storage)
      : super(const SessionState());

  Future<bool> unlockWithBiometric(AuthService auth) async {
    state = state.copyWith(isLoading: true, statusMessage: 'VERIFYING BIOMETRIC...');
    try {
      final ok = await auth.authenticateWithBiometric();
      if (!ok) {
        state = state.copyWith(
          isLoading: false,
          statusMessage: 'IDENTITY REJECTED',
          isError: true,
        );
        return false;
      }
      return _performMockHandshake();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        statusMessage: e.toString(),
        isError: true,
      );
      return false;
    }
  }

  Future<bool> unlockWithNfc(Uint8List nfcPayload) async {
    state = state.copyWith(isLoading: true, statusMessage: 'VERIFYING NFC KEY...');
    try {
      _crypto.nfcHandshake(nfcPayload);
      _setUnlocked(authMethod: 'nfc');
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        statusMessage: e.toString(),
        isError: true,
      );
      return false;
    }
  }

  Future<bool> _performMockHandshake() async {
    final secret = await _storage.loadMockHardwareSecret();
    if (secret == null) {
      state = state.copyWith(
        isLoading: false,
        statusMessage: 'HARDWARE SECRET NOT CONFIGURED',
        isError: true,
      );
      return false;
    }
    try {
      _crypto.mockHandshake(secret);
      _setUnlocked(authMethod: 'biometric');
      return true;
    } on CryptoServiceException catch (e) {
      state = state.copyWith(
        isLoading: false,
        statusMessage: e.message,
        isError: true,
      );
      return false;
    }
  }

  void _setUnlocked({required String authMethod}) {
    final profile = UserProfile(
      deviceName: 'ANDROID DEVICE',
      sessionId: DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase(),
      sessionStart: DateTime.now(),
      isBiometricAuth: authMethod == 'biometric',
      isNfcAuth: authMethod == 'nfc',
    );
    state = state.copyWith(
      isUnlocked: true,
      profile: profile,
      isLoading: false,
      statusMessage: 'ENCLAVE ACTIVE',
      isError: false,
    );
  }

  void lock() {
    _crypto.lockVault();
    state = const SessionState(statusMessage: 'VAULT SEALED');
  }

  void setStatus(String msg, {bool isError = false}) {
    state = state.copyWith(statusMessage: msg, isError: isError);
  }
}

final sessionProvider = StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(
    ref.watch(cryptoServiceProvider),
    ref.watch(storageServiceProvider),
  );
});

// ─── Vault Files ─────────────────────────────────────────────────────────────

final vaultFilesProvider = FutureProvider<List<VaultFile>>((ref) async {
  final cloud = await ref.watch(cloudServiceProvider.future);
  if (cloud == null) return [];
  try {
    final keys = await cloud.getVaultInventory();
    return keys.map((k) => VaultFile(name: k, source: 'cloud')).toList();
  } catch (_) {
    return [];
  }
});

// ─── Credentials ─────────────────────────────────────────────────────────────

class CredentialNotifier extends StateNotifier<List<Credential>> {
  final CryptoService _crypto;
  final CloudService? _cloud;

  CredentialNotifier(this._crypto, this._cloud) : super([]);

  static const _filename = 'passwords.enc';

  Future<void> load() async {
    if (!_crypto.isUnlocked || _cloud == null) return;
    try {
      final blob = await _cloud!.downloadToBuffer(_filename);
      final json = utf8.decode(_crypto.decryptBlob(blob));
      final data = jsonDecode(json);
      if (data is List) {
        state = data.map((e) => Credential.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      state = [];
    }
  }

  Future<void> add(Credential cred) async {
    state = [...state, cred];
    await _persist();
  }

  Future<void> remove(Credential cred) async {
    state = state.where((c) => c.storeKey != cred.storeKey).toList();
    await _persist();
  }

  Future<void> _persist() async {
    if (!_crypto.isUnlocked || _cloud == null) return;
    final json = jsonEncode(state.map((c) => c.toJson()).toList());
    final blob = _crypto.encryptToBlob(Uint8List.fromList(utf8.encode(json)));
    await _cloud!.uploadVaultFile(blob, _filename);
  }
}

final credentialProvider = StateNotifierProvider<CredentialNotifier, List<Credential>>((ref) {
  final crypto = ref.watch(cryptoServiceProvider);
  final cloudAsync = ref.watch(cloudServiceProvider);
  final cloud = cloudAsync.valueOrNull;
  return CredentialNotifier(crypto, cloud);
});

// ─── TOTP Keys ───────────────────────────────────────────────────────────────

class TotpNotifier extends StateNotifier<List<TotpKey>> {
  final CryptoService _crypto;
  final CloudService? _cloud;

  TotpNotifier(this._crypto, this._cloud) : super([]);

  static const _filename = 'auth_keys.enc';

  Future<void> load() async {
    if (!_crypto.isUnlocked || _cloud == null) return;
    try {
      final blob = await _cloud!.downloadToBuffer(_filename);
      final json = utf8.decode(_crypto.decryptBlob(blob));
      final data = jsonDecode(json);
      if (data is List) {
        state = data.map((e) => TotpKey.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      state = [];
    }
  }

  Future<void> add(TotpKey key) async {
    state = [...state, key];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((k) => k.id != id).toList();
    await _persist();
  }

  Future<void> _persist() async {
    if (!_crypto.isUnlocked || _cloud == null) return;
    final json = jsonEncode(state.map((k) => k.toJson()).toList());
    final blob = _crypto.encryptToBlob(Uint8List.fromList(utf8.encode(json)));
    await _cloud!.uploadVaultFile(blob, _filename);
  }
}

final totpProvider = StateNotifierProvider<TotpNotifier, List<TotpKey>>((ref) {
  final crypto = ref.watch(cryptoServiceProvider);
  final cloudAsync = ref.watch(cloudServiceProvider);
  final cloud = cloudAsync.valueOrNull;
  return TotpNotifier(crypto, cloud);
});
