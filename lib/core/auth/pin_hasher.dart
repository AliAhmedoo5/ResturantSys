import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

/// Versioned, independently salted PBKDF2 verifiers. Legacy hashes are read only.
abstract final class PinHasher {
  static const iterations = 600000;
  static const _legacySalt = 'resturant_pos_pin_salt_v1';

  static Uint8List randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  static Uint8List _derive(String pin, Uint8List salt, int rounds) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, rounds, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  static String hashPin(String pin, {String? salt}) {
    final nonce = salt == null ? randomBytes(16) : Uint8List.fromList(utf8.encode(salt));
    return 'pbkdf2-sha256\$$iterations\$${base64Url.encode(nonce)}\$${base64Url.encode(_derive(pin, nonce, iterations))}';
  }

  static bool isLegacy(String hash) => RegExp(r'^[a-f0-9]{64}$').hasMatch(hash);

  static bool verifyPin(String pin, String hash, {String salt = _legacySalt}) {
    if (isLegacy(hash)) {
      return constantTimeEquals(sha256.convert(utf8.encode('$salt:$pin')).toString(), hash);
    }
    try {
      final parts = hash.split(r'$');
      if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
      final rounds = int.parse(parts[1]);
      if (rounds < iterations || rounds > iterations * 2) return false;
      final nonce = base64Url.decode(parts[2]);
      if (nonce.isEmpty || nonce.length > 128 || base64Url.decode(parts[3]).length != 32) return false;
      return constantTimeEquals(base64Url.encode(_derive(pin, nonce, rounds)), parts[3]);
    } on FormatException {
      return false;
    }
  }

  static bool constantTimeEquals(String first, String second) {
    if (first.length != second.length) return false;
    var difference = 0;
    for (var index = 0; index < first.length; index++) {
      difference |= first.codeUnitAt(index) ^ second.codeUnitAt(index);
    }
    return difference == 0;
  }
}
