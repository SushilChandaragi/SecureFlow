/// SecureFlow Mobile — Riverpod State Providers
///
/// Single source of truth for session state, vault contents, credentials,
/// TOTP keys, and document vault. Backed by SQLite (DatabaseService) with
/// per-row AES-256-GCM encryption via CryptoService.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import '../models/vault_file.dart';
import '../models/credential.dart';
import '../models/totp_key.dart';
import '../models/vault_document.dart';
import '../models/user_profile.dart';
import '../services/crypto_service.dart';
import '../services/cloud_service.dart';
import '../services/auth_service.dart';
import '../services/secure_storage_service.dart';
import '../services/database_service.dart';
import '../utils/logger.dart';

// ─── Service Singletons ──────────────────────────────────────────────────────

final cryptoServiceProvider = Provider<CryptoService>((_) => CryptoService());
final authServiceProvider   = Provider<AuthService>((_)   => AuthService());
final storageServiceProvider= Provider<SecureStorageService>(
  (_) => SecureStorageService());

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final db = DatabaseService();
  // Open DB eagerly — it is just schema creation, no decryption needed here.
  db.open();
  return db;
});

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
  final DatabaseService _db;
  static final RegExp _nfcKeyPattern = RegExp(r'^SECUREFLOW-NFC-KEY-V1-[A-Z0-9]{8}$');

  SessionNotifier(this._crypto, this._storage, this._db)
      : super(const SessionState());

  Future<bool> unlockWithBiometric(AuthService auth) async {
    sfLog('Session: unlockWithBiometric start');
    state = state.copyWith(isLoading: true, statusMessage: 'VERIFYING BIOMETRIC...');
    try {
      final ok = await auth.authenticateWithBiometric();
      if (!ok) {
        sfLog('Session: biometric rejected');
        state = state.copyWith(
          isLoading: false,
          statusMessage: 'IDENTITY REJECTED',
          isError: true,
        );
        return false;
      }
      sfLog('Session: biometric accepted');
      return _performMockHandshake();
    } catch (e) {
      sfLog('Session: biometric exception=$e');
      state = state.copyWith(
        isLoading: false,
        statusMessage: e.toString(),
        isError: true,
      );
      return false;
    }
  }

  /// Unlock using a plain-text string extracted from an NFC tag.
  /// On first use, binds to that string. Subsequently must match exactly.
  Future<bool> unlockWithNfcString(String tagText) async {
    final trimmed = tagText.trim();
    sfLog('Session: unlockWithNfcString text="${trimmed.substring(0, trimmed.length.clamp(0, 16))}..."');
    state = state.copyWith(isLoading: true, statusMessage: 'VERIFYING NFC KEY...');
    try {
      final expected = await _storage.loadNfcSecretString();
      final expectedValid = expected != null && _nfcKeyPattern.hasMatch(expected);
      if (!expectedValid) {
        if (expected != null && expected.isNotEmpty) {
          sfLog('Session: NFC key invalid/legacy. Rebinding to new tag.');
        }
        await _storage.saveNfcSecretString(trimmed);
      } else if (expected != trimmed) {
        sfLog('Session: NFC string mismatch. Expected="$expected" got="$trimmed"');
        state = state.copyWith(
          isLoading: false,
          statusMessage: 'NFC KEY MISMATCH',
          isError: true,
        );
        return false;
      }
      // Use UTF-8 bytes of the string as the crypto handshake payload
      final payloadBytes = Uint8List.fromList(utf8.encode(trimmed));
      final padded = Uint8List(32);
      padded.setRange(0, payloadBytes.length.clamp(0, 32), payloadBytes);
      _crypto.nfcHandshake(padded);
      sfLog('Session: NFC handshake ok');
      await _setUnlocked(authMethod: 'nfc');
      return true;
    } catch (e) {
      sfLog('Session: NFC exception=$e');
      state = state.copyWith(
        isLoading: false,
        statusMessage: e.toString(),
        isError: true,
      );
      return false;
    }
  }

  Future<bool> _performMockHandshake() async {
    // Priority 1: use the desktop shared secret (content of mock_hardware_secret.txt)
    // This is what makes mobile decrypt files that were encrypted on the desktop.
    final desktopSecret = await _storage.loadDesktopSecretBytes();
    if (desktopSecret != null) {
      sfLog('Session: using desktop shared secret (${desktopSecret.length}B) for handshake');
      try {
        _crypto.mockHandshake(desktopSecret);
        sfLog('Session: desktop-secret handshake ok');
        await _setUnlocked(authMethod: 'biometric');
        return true;
      } on CryptoServiceException catch (e) {
        sfLog('Session: desktop-secret handshake error=${e.message}');
        state = state.copyWith(isLoading: false, statusMessage: e.message, isError: true);
        return false;
      }
    }

    // Priority 2: use the stored random mobile secret (mobile-only vault, no desktop link).
    var secret = await _storage.loadMockHardwareSecret();
    if (secret == null) {
      sfLog('Session: no secret found — generating random mobile secret');
      secret = _generateSecret(32);
      await _storage.saveMockHardwareSecret(secret);
    }
    sfLog('Session: using random mobile secret (${secret.length}B) for handshake');
    try {
      _crypto.mockHandshake(secret);
      sfLog('Session: mobile-secret handshake ok');
      await _setUnlocked(authMethod: 'biometric');
      return true;
    } on CryptoServiceException catch (e) {
      sfLog('Session: mock handshake error=${e.message}');
      state = state.copyWith(isLoading: false, statusMessage: e.message, isError: true);
      return false;
    }
  }


  Uint8List _generateSecret(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => rng.nextInt(256)),
    );
  }

  Future<void> _setUnlocked({required String authMethod}) async {
    sfLog('Session: unlocked via $authMethod');
    
    // Read the master vault key from secure storage and immediately inject it into CryptoService
    final desktopKeyBytes = await _storage.loadDesktopSecretBytes();
    if (desktopKeyBytes != null) {
      sfLog('Session: Injecting MVK (${desktopKeyBytes.length}B) into CryptoService');
      _crypto.updateHardwareSecret(desktopKeyBytes);
    } else {
      sfLog('Session: MVK not found in secure storage');
    }

    // Load or generate a device-unique secret for local SQLite encryption.
    // This remains completely decoupled from whether we are paired to a desktop.
    var secret = await _storage.loadMockHardwareSecret();
    if (secret == null) {
      sfLog('Session: generating and saving new device-unique mockHardwareSecret');
      secret = _generateSecret(32);
      await _storage.saveMockHardwareSecret(secret);
    }
    
    _db.attachSecret(secret);
    
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
    sfLog('Session: lock');
    _crypto.lockVault();
    _db.detachSecret();
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
    ref.watch(databaseServiceProvider),
  );
});

// ─── Vault Files (cloud inventory) ───────────────────────────────────────────

final vaultFilesProvider = FutureProvider<List<VaultFile>>((ref) async {
  final cloud = await ref.watch(cloudServiceProvider.future);
  if (cloud == null) return [];
  try {
    final objects = await cloud.getVaultInventory();
    return objects.map((obj) => VaultFile(
      name: obj.key,
      source: 'cloud',
      sizeBytes: obj.sizeBytes,
      lastModified: obj.lastModified,
    )).toList();
  } catch (_) {
    return [];
  }
});

// ─── Credentials ─────────────────────────────────────────────────────────────

class CredentialNotifier extends StateNotifier<List<Credential>> {
  final Ref _ref;
  static const _filename = 'passwords.enc';

  CredentialNotifier(this._ref) : super([]);

  DatabaseService get _db => _ref.read(databaseServiceProvider);
  CryptoService get _crypto => _ref.read(cryptoServiceProvider);
  CloudService? get _cloud => _ref.read(cloudServiceProvider).valueOrNull;

  Future<void> load() async {
    try {
      final creds = await _db.loadCredentials();
      state = creds;
    } catch (e) {
      sfLog('CredentialNotifier: load error=$e');
      state = [];
    }
  }

  Future<void> add(Credential cred) async {
    await _db.saveCredential(cred);
    state = [...state, cred];
    _syncToCloud();
  }

  Future<void> update(Credential old, Credential updated) async {
    await _db.updateCredential(old, updated);
    state = state.map((c) => c.storeKey == old.storeKey ? updated : c).toList();
    _syncToCloud();
  }

  Future<void> remove(Credential cred) async {
    await _db.deleteCredential(cred.storeKey);
    state = state.where((c) => c.storeKey != cred.storeKey).toList();
    _syncToCloud();
  }

  void _syncToCloud() {
    if (!_crypto.isUnlocked || _cloud == null) return;
    final json = jsonEncode(state.map((c) => c.toJson()).toList());
    final blob = _crypto.encryptToBlob(Uint8List.fromList(utf8.encode(json)));
    _cloud!.uploadVaultFile(blob, _filename).catchError((e) {
      sfLog('CredentialNotifier: cloud sync error=$e');
    });
  }
}

final credentialProvider = StateNotifierProvider<CredentialNotifier, List<Credential>>((ref) {
  return CredentialNotifier(ref);
});

// ─── TOTP Keys ───────────────────────────────────────────────────────────────

class TotpNotifier extends StateNotifier<List<TotpKey>> {
  final Ref _ref;
  static const _filename = 'auth_keys.enc';

  TotpNotifier(this._ref) : super([]);

  DatabaseService get _db => _ref.read(databaseServiceProvider);
  CryptoService get _crypto => _ref.read(cryptoServiceProvider);
  CloudService? get _cloud => _ref.read(cloudServiceProvider).valueOrNull;

  Future<void> load() async {
    try {
      final keys = await _db.loadTotpKeys();
      state = keys;
    } catch (e) {
      sfLog('TotpNotifier: load error=$e');
      state = [];
    }
  }

  Future<void> add(TotpKey key) async {
    await _db.saveTotpKey(key);
    state = [...state, key];
    _syncToCloud();
  }

  Future<void> update(TotpKey updated) async {
    await _db.updateTotpKey(updated);
    state = state.map((k) => k.id == updated.id ? updated : k).toList();
    _syncToCloud();
  }

  Future<void> remove(String id) async {
    await _db.deleteTotpKey(id);
    state = state.where((k) => k.id != id).toList();
    _syncToCloud();
  }

  void _syncToCloud() {
    if (!_crypto.isUnlocked || _cloud == null) return;
    final json = jsonEncode(state.map((k) => k.toJson()).toList());
    final blob = _crypto.encryptToBlob(Uint8List.fromList(utf8.encode(json)));
    _cloud!.uploadVaultFile(blob, _filename).catchError((e) {
      sfLog('TotpNotifier: cloud sync error=$e');
    });
  }
}

final totpProvider = StateNotifierProvider<TotpNotifier, List<TotpKey>>((ref) {
  return TotpNotifier(ref);
});

// ─── Document Vault ───────────────────────────────────────────────────────────

class DocumentNotifier extends StateNotifier<List<VaultDocument>> {
  final Ref _ref;
  static const _prefix = 'docs/';

  DocumentNotifier(this._ref) : super([]);

  DatabaseService get _db => _ref.read(databaseServiceProvider);
  CryptoService get _crypto => _ref.read(cryptoServiceProvider);
  CloudService? get _cloud => _ref.read(cloudServiceProvider).valueOrNull;

  Future<void> load() async {
    try {
      final docs = await _db.loadDocumentMeta();
      state = docs;
    } catch (e) {
      sfLog('DocumentNotifier: load error=$e');
      state = [];
    }
  }

  /// Encrypt [plainBytes], store in SQLite, and auto-sync to S3.
  Future<VaultDocument> addDocument({
    required String name,
    required Uint8List plainBytes,
  }) async {
    final id       = const Uuid().v4();
    final mimeType = lookupMimeType(name) ?? 'application/octet-stream';
    final doc = await _db.saveDocument(
      id: id, name: name, mimeType: mimeType, plainBytes: plainBytes,
    );
    state = [doc, ...state];
    // Auto-sync to S3 immediately
    _syncDocumentToCloud(doc, plainBytes);
    return doc;
  }

  /// Returns decrypted bytes for a document (RAM-only).
  Future<Uint8List> openDocument(String id) => _db.loadDocumentBytes(id);

  Future<void> deleteDocument(String id) async {
    await _db.deleteDocument(id);
    // Also delete from cloud
    final doc = state.where((d) => d.id == id).firstOrNull;
    if (doc != null && _cloud != null) {
      _cloud!.deleteVaultFile('$_prefix${doc.id}.enc').catchError((_) {});
    }
    state = state.where((d) => d.id != id).toList();
  }

  /// Manually trigger sync for a specific document (e.g. retry).
  Future<void> syncDocument(String id) async {
    try {
      final bytes = await _db.loadDocumentBytes(id);
      final doc   = state.firstWhere((d) => d.id == id);
      _syncDocumentToCloud(doc, bytes);
    } catch (e) {
      sfLog('DocumentNotifier: syncDocument error=$e');
    }
  }

  void _syncDocumentToCloud(VaultDocument doc, Uint8List plainBytes) {
    if (!_crypto.isUnlocked || _cloud == null) return;
    final encBlob = _crypto.encryptToBlob(plainBytes);
    _cloud!.uploadVaultFile(encBlob, '$_prefix${doc.id}.enc').then((_) async {
      await _db.markSynced(doc.id);
      state = state.map((d) => d.id == doc.id ? d.copyWith(isSynced: true) : d).toList();
      sfLog('DocumentNotifier: synced ${doc.name} to cloud');
    }).catchError((e) {
      sfLog('DocumentNotifier: cloud sync failed for ${doc.name}: $e');
    });
  }
}

final documentProvider = StateNotifierProvider<DocumentNotifier, List<VaultDocument>>((ref) {
  return DocumentNotifier(ref);
});
