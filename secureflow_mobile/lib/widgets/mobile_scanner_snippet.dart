// SecureFlow Mobile Companion — MVK Sync & Pairing Module
// 
// This snippet demonstrates how to parse a scanned 32-byte hexadecimal 
// Master Vault Key (MVK) from the Desktop's setup QR code and store it 
// strictly in the Android Keystore-backed flutter_secure_storage vault.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class SecureFlowPairingScanner extends StatefulWidget {
  final VoidCallback onPairingComplete;

  const SecureFlowPairingScanner({super.key, required this.onPairingComplete});

  @override
  State<SecureFlowPairingScanner> createState() => _SecureFlowPairingScannerState();
}

class _SecureFlowPairingScannerState extends State<SecureFlowPairingScanner> {
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _kMasterVaultKey = 'sf_master_vault_key';
  bool _processing = false;

  /// Helper to convert a Hexadecimal string to Uint8List bytes
  Uint8List _parseHex(String hex) {
    hex = hex.replaceAll(RegExp(r'\s+'), '');
    if (hex.length % 2 != 0) {
      throw const FormatException('Hex string must have an even length.');
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      final byteString = hex.substring(i * 2, i * 2 + 2);
      final byteValue = int.parse(byteString, radix: 16);
      bytes[i] = byteValue;
    }
    return bytes;
  }

  /// Processes the raw scanned text from QR code
  Future<void> _handleQrDetected(String rawValue) async {
    if (_processing) return;
    setState(() => _processing = true);

    try {
      final trimmed = rawValue.trim();
      
      // 1. Validate MVK length (hex representation of 32 bytes is exactly 64 characters)
      if (trimmed.length != 64 || !RegExp(r'^[a-fA-F0-9]+$').hasMatch(trimmed)) {
        throw const FormatException('Invalid QR format. Must be a 32-byte hexadecimal string.');
      }

      // 2. Perform byte-level parsing validation
      final mvkBytes = _parseHex(trimmed);
      assert(mvkBytes.length == 32);

      // 3. Write strictly to Android Keystore-backed encrypted storage
      // The key is stored as the raw hex string for cross-platform matching
      await _secureStorage.write(
        key: _kMasterVaultKey,
        value: trimmed,
      );

      // 4. Notify UI & Trigger visual success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981), // Emerald green
            duration: Duration(seconds: 2),
            content: Text(
              '🟢 PAIRING SUCCESS: MASTER VAULT KEY SECURED IN KEYSTORE',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        widget.onPairingComplete();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444), // Danger red
            content: Text(
              '❌ PAIRING ERROR: ${e.toString()}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF333333)), // Soft carbon border
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode != null && barcode.rawValue != null) {
                _handleQrDetected(barcode.rawValue!);
              }
            },
          ),
          if (_processing)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
