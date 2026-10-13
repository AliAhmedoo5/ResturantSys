import 'package:sqflite_common/sqlite_api.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'pin_hasher.dart';
import 'staff.dart';
import 'session_state.dart';

/// Service responsible for PIN verification, staff lookup, and active session coordination.
class AuthService {
  AuthService({
    required this.database,
    SessionState? session,
  }) : session = session ?? SessionState();

  final Database database;
  final SessionState session;

  static final RegExp _pinFormatRegex = RegExp(r'^\d{4}$');

  /// Authenticates a staff member by checking a 4-digit numeric PIN against stored SHA-256 hashes.
  ///
  /// Returns the authenticated [Staff] with associated department metadata, or `null` if invalid.
  Future<Staff?> authenticateWithPin(String pin) async {
    if (!_pinFormatRegex.hasMatch(pin)) {
      return null;
    }

    final hashedPin = PinHasher.hashPin(pin);

    final results = await database.rawQuery('''
      SELECT 
        s.id, 
        s.name, 
        s.department_id, 
        s.pin_hash, 
        s.role, 
        s.is_active, 
        s.created_at,
        d.name AS department_name
      FROM ${PosDatabaseConstants.tableStaff} s
      LEFT JOIN ${PosDatabaseConstants.tableDepartments} d 
        ON s.department_id = d.id
      WHERE s.pin_hash = ? AND s.is_active = 1
      LIMIT 1;
    ''', [hashedPin]);

    if (results.isEmpty) {
      return null;
    }

    final row = results.first;
    final staff = Staff.fromMap(
      row,
      departmentName: row['department_name'] as String?,
    );

    return staff;
  }

  /// Authenticates a staff member specifically verifying Supervisor or Owner authorization
  /// without modifying the active session (preserving the active cashier's login).
  Future<Staff?> authenticateSupervisorPin(String pin) async {
    final staff = await authenticateWithPin(pin);
    if (staff != null && staff.canVoidOrders) {
      return staff;
    }
    return null;
  }

  /// Authenticates a staff member and establishes an active user session.
  Future<Staff?> authenticateAndLogin(String pin) async {
    final staff = await authenticateWithPin(pin);
    if (staff != null) {
      session.login(staff);
    }
    return staff;
  }

  /// Changes a staff member's 4-digit PIN after verifying their current PIN.
  Future<bool> changePin({
    required int staffId,
    required String oldPin,
    required String newPin,
  }) async {
    if (!_pinFormatRegex.hasMatch(newPin)) {
      return false;
    }

    final staffResults = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ? AND is_active = 1',
      whereArgs: [staffId],
      limit: 1,
    );

    if (staffResults.isEmpty) {
      return false;
    }

    final currentHash = staffResults.first['pin_hash'] as String;
    if (!PinHasher.verifyPin(oldPin, currentHash)) {
      return false;
    }

    final newHash = PinHasher.hashPin(newPin);
    final count = await database.update(
      PosDatabaseConstants.tableStaff,
      {'pin_hash': newHash},
      where: 'id = ?',
      whereArgs: [staffId],
    );

    return count > 0;
  }
}
