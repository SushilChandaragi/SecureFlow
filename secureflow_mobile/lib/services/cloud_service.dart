/// SecureFlow Mobile — CloudService
///
/// Dart port of cloud_manager.py — AWS S3 operations using SigV4 signing.
/// All downloads are kept in RAM (Uint8List) and never touch disk.
library;

import 'dart:typed_data';
import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:http/http.dart' as http;

class CloudServiceException implements Exception {
  final String message;
  const CloudServiceException(this.message);
  @override
  String toString() => 'CloudServiceException: $message';
}

class CloudService {
  final String bucketName;
  final String region;
  late final AWSSigV4Signer _signer;

  CloudService({
    required this.bucketName,
    required this.region,
    required String accessKeyId,
    required String secretAccessKey,
  }) {
    _signer = AWSSigV4Signer(
      credentialsProvider: AWSCredentialsProvider(
        AWSCredentials(accessKeyId, secretAccessKey),
      ),
    );
  }

  AWSCredentialScope get _s3Scope =>
      AWSCredentialScope(region: region, service: AWSService.s3);

  String get _baseUrl => 'https://$bucketName.s3.$region.amazonaws.com';

  // ── Inventory ──────────────────────────────────────────────────────────────

  /// List all .enc object keys in the S3 bucket.
  Future<List<String>> getVaultInventory() async {
    final List<String> keys = [];
    String? continuationToken;

    do {
      final qp = <String, String>{'list-type': '2'};
      if (continuationToken != null) qp['continuation-token'] = continuationToken;

      final request = AWSHttpRequest.get(
        Uri.parse('$_baseUrl/?${_encodeQueryParams(qp)}'),
        headers: const {'Content-Type': 'application/xml'},
      );

      final signed = await _signer.sign(request, credentialScope: _s3Scope);
      final response = await http.get(
        signed.uri,
        headers: Map<String, String>.fromEntries(
          signed.headers.entries.map((e) => MapEntry(e.key, e.value)),
        ),
      );

      if (response.statusCode != 200) {
        throw CloudServiceException('S3 list failed: ${response.statusCode}');
      }

      final body = response.body;
      final keyMatches = RegExp(r'<Key>([^<]+)</Key>').allMatches(body);
      for (final m in keyMatches) {
        final key = m.group(1) ?? '';
        if (key.toLowerCase().endsWith('.enc')) keys.add(key);
      }

      final isTruncated = body.contains('<IsTruncated>true</IsTruncated>');
      if (isTruncated) {
        final t = RegExp(r'<NextContinuationToken>([^<]+)</NextContinuationToken>')
            .firstMatch(body);
        continuationToken = t?.group(1);
      } else {
        continuationToken = null;
      }
    } while (continuationToken != null);

    keys.sort();
    return keys;
  }

  // ── Download ───────────────────────────────────────────────────────────────

  /// Download an object to a RAM buffer — never writes to disk.
  Future<Uint8List> downloadToBuffer(String objectKey) async {
    final request = AWSHttpRequest.get(
      Uri.parse('$_baseUrl/${Uri.encodeComponent(objectKey)}'),
    );

    final signed = await _signer.sign(request, credentialScope: _s3Scope);
    final response = await http.get(
      signed.uri,
      headers: Map<String, String>.fromEntries(
        signed.headers.entries.map((e) => MapEntry(e.key, e.value)),
      ),
    );

    if (response.statusCode != 200) {
      throw CloudServiceException('S3 download failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  // ── Upload ─────────────────────────────────────────────────────────────────

  /// Upload encrypted bytes to S3.
  Future<void> uploadVaultFile(Uint8List data, String objectKey) async {
    final request = AWSHttpRequest.put(
      Uri.parse('$_baseUrl/${Uri.encodeComponent(objectKey)}'),
      headers: const {'Content-Type': 'application/octet-stream'},
      body: data,
    );

    final signed = await _signer.sign(request, credentialScope: _s3Scope);
    final response = await http.put(
      signed.uri,
      headers: Map<String, String>.fromEntries(
        signed.headers.entries.map((e) => MapEntry(e.key, e.value)),
      ),
      body: data,
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw CloudServiceException('S3 upload failed: ${response.statusCode}');
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Cryptographic shred — delete an object from S3.
  Future<void> deleteVaultFile(String objectKey) async {
    final request = AWSHttpRequest.delete(
      Uri.parse('$_baseUrl/${Uri.encodeComponent(objectKey)}'),
    );

    final signed = await _signer.sign(request, credentialScope: _s3Scope);
    final response = await http.delete(
      signed.uri,
      headers: Map<String, String>.fromEntries(
        signed.headers.entries.map((e) => MapEntry(e.key, e.value)),
      ),
    );

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw CloudServiceException('S3 delete failed: ${response.statusCode}');
    }
  }

  String _encodeQueryParams(Map<String, String> params) {
    return params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }
}
