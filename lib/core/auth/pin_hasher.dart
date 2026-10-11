import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Cryptographic PIN hashing and verification utility using SHA-256.
abstract final class PinHasher {
  static const String _defaultSalt = 'resturant_pos_pin_salt_v1';

  /// Hashes a 4-digit PIN using SHA-256 with salt.
  static String hashPin(String pin, {String salt = _defaultSalt}) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }

  /// Verifies a candidate 4-digit PIN against an existing SHA-256 hash.
  static bool verifyPin(String pin, String hash, {String salt = _defaultSalt}) {
    final computed = hashPin(pin, salt: salt);
    return computed == hash;
  }
}
