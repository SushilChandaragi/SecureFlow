/// SecureFlow Mobile — DatabaseService
///
/// SQLite-backed persistence with per-row AES-256-GCM encryption.
/// ALL sensitive fields are encrypted before reaching the DB file.
///
/// Schema
/// ──────
///   credentials  (id TEXT PK, encrypted_json TEXT, updated_at INTEGER)
///   totp_keys    (id TEXT PK, encrypted_json TEXT, updated_at INTEGER)
///   documents    (id TEXT PK, name TEXT, size INTEGER, mime TEXT,
///                  encrypted_blob BLOB, updated_at INTEGER, is_synced INTEGER)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/credential.dart';
import '../models/totp_key.dart';
import '../models/vault_document.dart';
import '../services/crypto_service.dart';
import '../utils/logger.dart';

class DatabaseService {
  static const _dbName    = 'secureflow.db';
  static const _dbVersion = 1;

  Database? _db;
  final CryptoService _localCrypto = CryptoService();

  // Completer ensures open() is awaited exactly once across all callers.
  Completer<void>? _openCompleter;

  // ── Initialise ─────────────────────────────────────────────────────────────

  Future<void> open() async {
    if (_db != null) {
      sfLog('DB: already open');
      return;
    }
    if (_openCompleter != null) {
      sfLog('DB: waiting for in-progress open');
      return _openCompleter!.future;
    }

    _openCompleter = Completer<void>();
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, _dbName);
      sfLog('DB: opening at $path');
      _db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _createSchema,
        onOpen: (db) => sfLog('DB: onOpen fired'),
      );
      sfLog('DB: open complete');
      _openCompleter!.complete();
    } catch (e, st) {
      sfLog('DB: OPEN FAILED — $e\n$st');
      _openCompleter!.completeError(e, st);
      _openCompleter = null;
      rethrow;
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    sfLog('DB: creating schema v$version');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS credentials (
        id             TEXT PRIMARY KEY,
        encrypted_json TEXT NOT NULL,
        updated_at     INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS totp_keys (
        id             TEXT PRIMARY KEY,
        encrypted_json TEXT NOT NULL,
        updated_at     INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id             TEXT PRIMARY KEY,
        name           TEXT NOT NULL,
        size           INTEGER NOT NULL,
        mime           TEXT NOT NULL,
        encrypted_blob BLOB NOT NULL,
        updated_at     INTEGER NOT NULL,
        is_synced      INTEGER NOT NULL DEFAULT 0
      )
    ''');
    sfLog('DB: schema created');
  }

  Future<Database> get _ready async {
    if (_db == null) {
      sfLog('DB: _ready — calling open()');
      await open();
    }
    return _db!;
  }

  void attachSecret(Uint8List secret) {
    _localCrypto.mockHandshake(secret);
    sfLog('DB: local crypto attached & unlocked');
  }

  void detachSecret() {
    _localCrypto.lockVault();
    sfLog('DB: local crypto detached & locked');
  }

  CryptoService get _c {
    if (!_localCrypto.isUnlocked) {
      sfLog('DB: ERROR — local crypto reports locked');
      throw StateError('DatabaseService: local crypto is locked');
    }
    return _localCrypto;
  }

  // ── Credentials ────────────────────────────────────────────────────────────

  Future<List<Credential>> loadCredentials() async {
    final db   = await _ready;
    final rows = await db.query('credentials', orderBy: 'updated_at DESC');
    sfLog('DB: loadCredentials — ${rows.length} raw rows');
    final out  = <Credential>[];
    for (final row in rows) {
      try {
        final enc   = row['encrypted_json'] as String;
        final blob  = base64.decode(enc);
        final plain = _c.decryptBlob(Uint8List.fromList(blob));
        final json  = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        out.add(Credential.fromJson(json));
      } catch (e) {
        sfLog('DB: skipping corrupt credential row id=${row['id']}: $e');
      }
    }
    sfLog('DB: loadCredentials — returned ${out.length} decrypted');
    return out;
  }

  Future<void> saveCredential(Credential cred) async {
    final db    = await _ready;
    sfLog('DB: saveCredential key=${cred.storeKey}');
    final plain = utf8.encode(jsonEncode(cred.toJson()));
    final blob  = _c.encryptToBlob(Uint8List.fromList(plain));
    final enc   = base64.encode(blob);
    await db.insert(
      'credentials',
      {
        'id':             cred.storeKey,
        'encrypted_json': enc,
        'updated_at':     DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    sfLog('DB: saveCredential DONE key=${cred.storeKey}');
  }

  Future<void> deleteCredential(String storeKey) async {
    final db = await _ready;
    sfLog('DB: deleteCredential key=$storeKey');
    await db.delete('credentials', where: 'id = ?', whereArgs: [storeKey]);
  }

  Future<void> updateCredential(Credential oldCred, Credential newCred) async {
    await deleteCredential(oldCred.storeKey);
    await saveCredential(newCred);
  }

  // ── TOTP Keys ──────────────────────────────────────────────────────────────

  Future<List<TotpKey>> loadTotpKeys() async {
    final db   = await _ready;
    final rows = await db.query('totp_keys', orderBy: 'updated_at ASC');
    sfLog('DB: loadTotpKeys — ${rows.length} raw rows');
    final out  = <TotpKey>[];
    for (final row in rows) {
      try {
        final enc   = row['encrypted_json'] as String;
        final blob  = base64.decode(enc);
        final plain = _c.decryptBlob(Uint8List.fromList(blob));
        final json  = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
        out.add(TotpKey.fromJson(json));
      } catch (e) {
        sfLog('DB: skipping corrupt TOTP row id=${row['id']}: $e');
      }
    }
    sfLog('DB: loadTotpKeys — returned ${out.length} decrypted');
    return out;
  }

  Future<void> saveTotpKey(TotpKey key) async {
    final db    = await _ready;
    sfLog('DB: saveTotpKey id=${key.id}');
    final plain = utf8.encode(jsonEncode(key.toJson()));
    final blob  = _c.encryptToBlob(Uint8List.fromList(plain));
    final enc   = base64.encode(blob);
    await db.insert(
      'totp_keys',
      {
        'id':             key.id,
        'encrypted_json': enc,
        'updated_at':     DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    sfLog('DB: saveTotpKey DONE id=${key.id}');
  }

  Future<void> deleteTotpKey(String id) async {
    final db = await _ready;
    sfLog('DB: deleteTotpKey id=$id');
    await db.delete('totp_keys', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTotpKey(TotpKey updated) async => saveTotpKey(updated);

  // ── Documents ──────────────────────────────────────────────────────────────

  Future<List<VaultDocument>> loadDocumentMeta() async {
    final db   = await _ready;
    final rows = await db.query(
      'documents',
      columns: ['id', 'name', 'size', 'mime', 'updated_at', 'is_synced'],
      orderBy: 'updated_at DESC',
    );
    sfLog('DB: loadDocumentMeta — ${rows.length} rows');
    return rows.map((r) => VaultDocument(
      id:        r['id']   as String,
      name:      r['name'] as String,
      size:      r['size'] as int,
      mimeType:  r['mime'] as String,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      isSynced:  (r['is_synced'] as int) == 1,
    )).toList();
  }

  Future<Uint8List> loadDocumentBytes(String id) async {
    final db   = await _ready;
    sfLog('DB: loadDocumentBytes id=$id');
    final rows = await db.query(
      'documents',
      columns: ['encrypted_blob'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      sfLog('DB: loadDocumentBytes — NOT FOUND id=$id');
      throw StateError('Document $id not found');
    }
    // SQLite BLOB comes back as Uint8List, but guard against List<int>
    final raw = rows.first['encrypted_blob'];
    final enc = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    sfLog('DB: loadDocumentBytes — encrypted size=${enc.length}');
    final plain = _c.decryptBlob(enc);
    sfLog('DB: loadDocumentBytes — decrypted size=${plain.length}');
    return plain;
  }

  Future<VaultDocument> saveDocument({
    required String id,
    required String name,
    required String mimeType,
    required Uint8List plainBytes,
  }) async {
    final db        = await _ready;
    sfLog('DB: saveDocument id=$id name=$name plainSize=${plainBytes.length}');
    final encrypted = _c.encryptToBlob(plainBytes);
    sfLog('DB: saveDocument — encryptedSize=${encrypted.length}');
    final now = DateTime.now();
    await db.insert(
      'documents',
      {
        'id':             id,
        'name':           name,
        'size':           plainBytes.length,
        'mime':           mimeType,
        'encrypted_blob': encrypted,
        'updated_at':     now.millisecondsSinceEpoch,
        'is_synced':      0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    sfLog('DB: saveDocument DONE id=$id');
    return VaultDocument(
      id: id, name: name, size: plainBytes.length,
      mimeType: mimeType, updatedAt: now, isSynced: false,
    );
  }

  Future<void> markSynced(String id) async {
    final db = await _ready;
    sfLog('DB: markSynced id=$id');
    await db.update('documents', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteDocument(String id) async {
    final db = await _ready;
    sfLog('DB: deleteDocument id=$id');
    await db.delete('documents', where: 'id = ?', whereArgs: [id]);
  }

  /// Wipe all encrypted rows — use from Settings if data is corrupt after an update.
  Future<void> clearAllRows() async {
    final db = await _ready;
    sfLog('DB: clearAllRows — wiping all rows');
    await db.delete('credentials');
    await db.delete('totp_keys');
    await db.delete('documents');
    sfLog('DB: clearAllRows DONE');
  }

  Future<void> close() async {
    sfLog('DB: close');
    await _db?.close();
    _db = null;
    _openCompleter = null;
  }
}
