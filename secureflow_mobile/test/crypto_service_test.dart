import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:secureflow_mobile/services/crypto_service.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('CryptoService Tests', () {
    late CryptoService cryptoService;
    final mockSecret = Uint8List.fromList(
      'SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy'.codeUnits,
    );

    setUp(() {
      cryptoService = CryptoService();
    });

    test('Initial state is locked', () {
      expect(cryptoService.isUnlocked, isFalse);
      expect(cryptoService.handshakeMode, equals('none'));
    });

    test('Mock handshake unlocks the vault', () {
      cryptoService.mockHandshake(mockSecret);
      expect(cryptoService.isUnlocked, isTrue);
      expect(cryptoService.handshakeMode, equals('mock'));
    });

    test('Encryption and Decryption parity in Mock mode', () {
      cryptoService.mockHandshake(mockSecret);
      final plaintext = Uint8List.fromList('Test secure payload'.codeUnits);
      
      final blob = cryptoService.encryptToBlob(plaintext);
      expect(blob, isNotNull);
      expect(blob.length, greaterThan(4));
      
      // The header should be SFV3 (0x53, 0x46, 0x56, 0x33)
      expect(blob.sublist(0, 4), equals(Uint8List.fromList([0x53, 0x46, 0x56, 0x33])));
      
      // Mode byte should be _kModeMock (0x4D = 'M')
      expect(blob[4], equals(0x4D));

      final decrypted = cryptoService.decryptBlob(blob);
      expect(String.fromCharCodes(decrypted), equals('Test secure payload'));
    });

    test('Cross-session decryption using re-derivation', () {
      // 1. Session A: Encrypts data
      cryptoService.mockHandshake(mockSecret);
      final plaintext = Uint8List.fromList('Cross-session payload'.codeUnits);
      final blob = cryptoService.encryptToBlob(plaintext);

      // 2. Session B: Starts fresh, sets the desktop vault secret, and decrypts directly
      final serviceB = CryptoService();
      serviceB.mockHandshake(mockSecret); // mockHandshake initializes _hardwareSecret

      final decrypted = serviceB.decryptBlob(blob);
      expect(String.fromCharCodes(decrypted), equals('Cross-session payload'));
    });

    test('Locking wipes key material', () {
      cryptoService.mockHandshake(mockSecret);
      expect(cryptoService.isUnlocked, isTrue);

      cryptoService.lockVault();
      expect(cryptoService.isUnlocked, isFalse);
      expect(cryptoService.handshakeMode, equals('none'));

      final plaintext = Uint8List.fromList('Data'.codeUnits);
      expect(() => cryptoService.encryptToBlob(plaintext), throwsException);
    });

    test('Simulated hardware HMAC and HKDF parity with Python', () {
      final hsNonce = Uint8List(32)..fillRange(0, 32, 0xAB);

      // 1. PointyCastle HMAC-SHA256 Parity
      final hmac = HMac(SHA256Digest(), 64)..init(KeyParameter(mockSecret));
      final hmacResp = hmac.process(hsNonce);
      const expectedHmacHex = '4ae372b062516486a51a5f9d5bacbc50e6b88b6a72a5c02c96ac881da1040caf';
      expect(hmacResp, equals(_parseHex(expectedHmacHex)));

      // 2. PointyCastle HKDF-SHA256 parity from derived IKM
      final ikm = Uint8List(64)
        ..setRange(0, 32, hmacResp)
        ..setRange(32, 64, hsNonce);
      
      final hkdf = HKDFKeyDerivator(SHA256Digest());
      hkdf.init(HkdfParameters(ikm, 32, null, Uint8List.fromList('session_key'.codeUnits)));
      final derivedKey = Uint8List(32);
      hkdf.deriveKey(null, 0, derivedKey, 0);

      const expectedKeyHex = 'd50939b067e2f4ec79067ad2e5e1c69762c7f3ef63936cab14e09684b1415d55';
      expect(derivedKey, equals(_parseHex(expectedKeyHex)));
    });
    test('NFC handshake unlocks and provides Mode H parity', () {
      cryptoService.nfcHandshake(mockSecret);
      expect(cryptoService.isUnlocked, isTrue);
      expect(cryptoService.handshakeMode, equals('nfc'));

      final plaintext = Uint8List.fromList('NFC hardware secret'.codeUnits);
      final blob = cryptoService.encryptToBlob(plaintext);
      expect(blob, isNotNull);
      expect(blob[4], equals(0x48)); // _kModeHardware = 0x48 = 'H'

      // NFC unlocked session can decrypt its own blob
      final decrypted = cryptoService.decryptBlob(blob);
      expect(String.fromCharCodes(decrypted), equals('NFC hardware secret'));

      // A fresh Mock/QR-paired session (with mockSecret) can decrypt this NFC Mode H blob
      final mockSession = CryptoService();
      mockSession.mockHandshake(mockSecret);
      final decryptedByMock = mockSession.decryptBlob(blob);
      expect(String.fromCharCodes(decryptedByMock), equals('NFC hardware secret'));
    });

    test('Absolute cross-platform byte-level parity with Python engine', () {
      final freshSession = CryptoService();
      freshSession.updateHardwareSecret(mockSecret);

      final pythonEncryptedBlob = _parseHex(
        '534656334d936e57975c749a7fb6f5fa0b11b96e130c315263cb839257226e6eafdc35ad7b5da9de21acb59524f51774b4e48835d0f02ac673fe591aa3e8f3f2a98bb4a4b502fed61a7e6afa32d3fbf72672e092dd608f5cf0a6f6ec1907c4f2e9f85f6bf0ba3033ade31ee16dd67d3d3e7531'
      );

      final decrypted = freshSession.decryptBlob(pythonEncryptedBlob);
      expect(
        String.fromCharCodes(decrypted),
        equals('Hello SecureFlow Cross-Platform Decryption Parity!'),
      );
    });
  });
}

Uint8List _parseHex(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
