import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:resturant_sys/core/auth/pin_hasher.dart';

void main() {
  for (final rounds in [PinHasher.iterations, PinHasher.iterations * 2]) {
    test('verifies existing PointyCastle credentials with $rounds rounds', () {
      const pin = '73918426';
      final salt = Uint8List.fromList(List.generate(16, (index) => index));
      final reference = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
        ..init(pc.Pbkdf2Parameters(salt, rounds, 32));
      final expected = reference.process(Uint8List.fromList(utf8.encode(pin)));
      final verifier = 'pbkdf2-sha256\$$rounds\$${base64Url.encode(salt)}\$${base64Url.encode(expected)}';
      expect(PinHasher.verifyPin(pin, verifier), isTrue);
      expect(PinHasher.verifyPin('73918427', verifier), isFalse);
      if (rounds == PinHasher.iterations) {
        expect(PinHasher.hashPin(pin, salt: utf8.decode(salt)), verifier);
      }
    });
  }
}
