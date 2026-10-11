import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';

void main() {
  group('PinHasher Tests', () {
    test('hashes 4-digit PIN deterministically', () {
      final hash1 = PinHasher.hashPin('1234');
      final hash2 = PinHasher.hashPin('1234');

      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // 256 bits = 64 hex characters
    });

    test('generates different hashes for different PINs', () {
      final hash1 = PinHasher.hashPin('1234');
      final hash2 = PinHasher.hashPin('4321');

      expect(hash1, isNot(equals(hash2)));
    });

    test('verifies correct PIN against hash', () {
      final hash = PinHasher.hashPin('9876');

      expect(PinHasher.verifyPin('9876', hash), isTrue);
      expect(PinHasher.verifyPin('1234', hash), isFalse);
    });

    test('supports custom salt', () {
      final hashDefault = PinHasher.hashPin('1234');
      final hashCustom = PinHasher.hashPin('1234', salt: 'custom_salt_99');

      expect(hashDefault, isNot(equals(hashCustom)));
      expect(PinHasher.verifyPin('1234', hashCustom, salt: 'custom_salt_99'), isTrue);
    });
  });
}
