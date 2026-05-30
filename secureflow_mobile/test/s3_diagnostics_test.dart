import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:secureflow_mobile/services/cloud_service.dart';

void main() {
  test('S3 safe-key round-trip: list, download, upload, delete', () async {
    final envFile = File('../.env');
    final lines = envFile.readAsLinesSync();
    final env = <String, String>{};
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx == -1) continue;
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }

    final cloud = CloudService(
      bucketName: env['S3_BUCKET_NAME']!,
      region: env['AWS_DEFAULT_REGION']!,
      accessKeyId: env['AWS_ACCESS_KEY_ID']!,
      secretAccessKey: env['AWS_SECRET_ACCESS_KEY']!,
    );

    print('\n[1] Listing inventory...');
    final inventory = await cloud.getVaultInventory();
    print('  Found: $inventory');

    final unsafe = inventory.where((info) => info.key.contains(' ')).toList();
    expect(unsafe, isEmpty, reason: 'No file keys should contain spaces after migration');
    print('  All keys are space-free. PASS.');

    if (inventory.isNotEmpty) {
      final key = inventory.first.key;
      print('\n[2] Downloading "$key"...');
      final data = await cloud.downloadToBuffer(key);
      expect(data.length, greaterThan(0));
      print('  Downloaded ${data.length}B. Header: ${String.fromCharCodes(data.sublist(0, data.length.clamp(0, 4)))}');
      print('  PASS.');
    }

    print('\n[3] Upload + download + delete round-trip with safe filename...');
    final testKey = 'secureflow_test_roundtrip.enc';
    final testData = Uint8List.fromList([0x53, 0x46, 0x56, 0x33, 0xAA, 0xBB]);
    await cloud.uploadVaultFile(testData, testKey);
    final got = await cloud.downloadToBuffer(testKey);
    expect(got, equals(testData));
    await cloud.deleteVaultFile(testKey);
    print('  Round-trip: PASS.');
  });
}
