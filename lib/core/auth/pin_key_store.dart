import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The fingerprint key belongs to the Windows user and installation, never SQLite.
class PinKeyStore {
  const PinKeyStore();
  static const _storage = FlutterSecureStorage();

  String _reference(String databasePath) =>
      'restaurant.pin.${sha256.convert(utf8.encode(databasePath))}';

  Future<String?> read(String databasePath) =>
      _storage.read(key: _reference(databasePath));

  Future<void> write(String databasePath, String key) =>
      _storage.write(key: _reference(databasePath), value: key);
}
