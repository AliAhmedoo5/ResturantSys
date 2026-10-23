import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Credentials belong to this installation and Windows user, not its database
/// backups. Only opaque references are stored in delivery settings.
abstract interface class ReportCredentialStore {
  Future<String?> read(String reference);
  Future<void> write(String reference, String password);
  Future<void> delete(String reference);
}

class SecureReportCredentialStore implements ReportCredentialStore {
  SecureReportCredentialStore(String databasePath)
      : _prefix = 'restaurant.gmail.${sha256.convert(utf8.encode(databasePath))}';

  final String _prefix;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String reference) => _storage.read(key: '$_prefix.$reference');

  @override
  Future<void> write(String reference, String password) =>
      _storage.write(key: '$_prefix.$reference', value: password);

  @override
  Future<void> delete(String reference) => _storage.delete(key: '$_prefix.$reference');
}
