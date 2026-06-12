import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secureflow_mobile/services/crypto_service.dart';

void main() {
  test('HKDF parity with Python desktop', () {
    final secret = Uint8List.fromList(hex.decode(
      '536563757265466c6f772d4d6f636b2d5365637265742d4368616e67652d4d652d5573652d486967682d456e74726f7079',
    ));
    final handshakeNonce = Uint8List.fromList(hex.decode(
      'fa5fe6dd79adaa60ef2a205f22484c3946b7ae074af5d74cd3f75e5a39cc7c6a',
    ));
    final expectedKey = Uint8List.fromList(hex.decode(
      '5d1e5c5291e6b4601d72e943be1eb5a1a0efdab9bbd7aba7813c5d1fdafe184c',
    ));

    final crypto = CryptoService();
    final derivedKey = crypto.deriveKey(secret, handshakeNonce);

    expect(hex.encode(derivedKey), equals(hex.encode(expectedKey)));
  });
}
