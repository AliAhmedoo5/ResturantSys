import 'package:sqflite_common/sqlite_api.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'department.dart';
import 'job_role.dart';
import 'pin_hasher.dart';
import 'session_state.dart';
import 'staff.dart';
import 'staff_role.dart';

/// Service responsible for PIN verification, staff lookup, and active session coordination.
class AuthService {
  AuthService({
    required this.database,
    SessionState? session,
  }) : session = session ?? SessionState();

  final Database database;
  final SessionState session;

  static final RegExp _pinFormatRegex = RegExp(r'^\d{4,8}$');
  static final RegExp _cashierPinRegex = RegExp(r'^\d{4}$');
  static final RegExp _managerPinRegex = RegExp(r'^\d{4,8}$');

  /// Authenticates a staff member by checking a 4–8 digit numeric PIN against stored SHA-256 hashes.
  ///
  /// Returns the authenticated [Staff] with associated department metadata, or `null` if invalid.
  Future<Staff?> authenticateWithPin(String pin) async {
    if (!_pinFormatRegex.hasMatch(pin)) {
      return null;
    }

    final hashedPin = PinHasher.hashPin(pin);

    final results = await database.rawQuery('''
      SELECT 
        s.job_role_id,
        s.login_enabled,
        j.name AS job_role_name,
        s.id, 
        s.name, 
        s.department_id, 
        s.pin_hash, 
        s.role, 
        s.is_active, 
        s.created_at,
        d.name AS department_name
      FROM ${PosDatabaseConstants.tableStaff} s
      LEFT JOIN job_roles j ON s.job_role_id = j.id
      LEFT JOIN ${PosDatabaseConstants.tableDepartments} d 
        ON s.department_id = d.id
      WHERE s.pin_hash = ? AND s.is_active = 1 AND s.login_enabled = 1
      LIMIT 1;
    ''', [hashedPin]);

    if (results.isEmpty) {
      return null;
    }

    final row = results.first;
    if (!StaffRole.isInteractiveCode(row['role'] as String)) {
      return null;
    }
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

  // ===========================================================================
  // UNIVERSAL STAFF & DEPARTMENT DIRECTORY
  // ===========================================================================

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  Future<List<JobRole>> getJobRoles() async =>
      (await database.query('job_roles', orderBy: 'name COLLATE NOCASE')).map(JobRole.fromMap).toList();

  String _jobName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Job role name cannot be empty.');
    return trimmed;
  }

  Future<JobRole> createJobRole(String name) async {
    final trimmed = _jobName(name);
    final id = await database.insert('job_roles', {'name': trimmed});
    return JobRole(id: id, name: trimmed);
  }

  Future<void> updateJobRole(int id, String name) async {
    final count = await database.update('job_roles', {'name': _jobName(name)}, where: 'id = ?', whereArgs: [id]);
    if (count == 0) throw StateError('Job role no longer exists.');
  }

  Future<void> deleteJobRole(int id) async {
    await database.transaction((txn) async {
      final assigned = await txn.query('staff', columns: ['id'], where: 'job_role_id = ?', whereArgs: [id], limit: 1);
      if (assigned.isNotEmpty) throw StateError('Reassign staff before deleting this job role.');
      await txn.delete('job_roles', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> _validateJobRole(int? id) async {
    if (id != null && await _jobRoleName(id) == null) throw ArgumentError('Job role does not exist.');
  }

  Future<String?> _jobRoleName(int? id) async {
    if (id == null) return null;
    final rows = await database.query('job_roles', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first['name'] as String;
  }

  /// Retrieves all configured departments in the system.
  Future<List<Department>> getDepartments() async {
    final rows = await database.query(
      PosDatabaseConstants.tableDepartments,
      orderBy: 'id ASC',
    );
    return rows.map((r) => Department.fromMap(r)).toList();
  }

  /// Creates a new custom department.
  Future<Department> createDepartment(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Department name cannot be empty.');
    }

    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableDepartments,
      {
        'name': trimmed,
        'created_at': now,
      },
    );

    return Department(
      id: id,
      name: trimmed,
      createdAt: DateTime.parse(now),
    );
  }

  /// Registers a new staff member with name, department, role, and a 4-digit numeric PIN.
  Future<Staff> registerStaff({
    required String name,
    required int departmentId,
    required StaffRole role,
    required String pin,
    int? jobRoleId,
    bool loginEnabled = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Staff name cannot be empty.');
    }

    if (!loginEnabled) {
      // Non-login staff have no usable PIN.
    } else if (role == StaffRole.manager) {
      if (!_managerPinRegex.hasMatch(pin)) {
        throw ArgumentError('Manager PIN must be between 4 and 8 numeric digits.');
      }
    } else {
      if (!_cashierPinRegex.hasMatch(pin)) {
        throw ArgumentError('Cashier PIN must be exactly 4 numeric digits.');
      }
    }

    // Verify department exists
    final deptRows = await database.query(
      PosDatabaseConstants.tableDepartments,
      where: 'id = ?',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (deptRows.isEmpty) {
      throw ArgumentError('Department ID $departmentId does not exist.');
    }
    final departmentName = deptRows.first['name'] as String;

    final hashedPin = loginEnabled ? PinHasher.hashPin(pin) : 'NO_LOGIN_${DateTime.now().microsecondsSinceEpoch}';

    await _validateJobRole(jobRoleId);
    // Verify unique PIN
    final existingPinRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'pin_hash = ?',
      whereArgs: [hashedPin],
      limit: 1,
    );
    if (existingPinRows.isNotEmpty) {
      throw StateError('This PIN is already assigned to another staff member.');
    }

    final now = _formatTimestamp(DateTime.now());
    final id = await database.insert(
      PosDatabaseConstants.tableStaff,
      {
        'job_role_id': jobRoleId,
        'login_enabled': loginEnabled ? 1 : 0,
        'name': trimmedName,
        'department_id': departmentId,
        'pin_hash': hashedPin,
        'role': role.code,
        'is_active': 1,
        'created_at': now,
      },
    );

    return Staff(
      id: id,
      jobRoleId: jobRoleId,
      jobRoleName: await _jobRoleName(jobRoleId),
      loginEnabled: loginEnabled,
      name: trimmedName,
      departmentId: departmentId,
      departmentName: departmentName,
      pinHash: hashedPin,
      role: role,
      isActive: true,
      createdAt: DateTime.parse(now),
    );
  }

  /// Supervisor/Manager administrative reset or update of a staff member's PIN.
  Future<bool> updateStaffPin({
    required int staffId,
    required String newPin,
  }) async {
    final staffRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [staffId],
      limit: 1,
    );
    if (staffRows.isEmpty) {
      throw StateError('Staff ID #$staffId does not exist.');
    }
    final role = StaffRole.fromCode(staffRows.first['role'] as String);

    if (role == StaffRole.manager) {
      if (!_managerPinRegex.hasMatch(newPin)) {
        throw ArgumentError('Manager PIN must be between 4 and 8 numeric digits.');
      }
    } else {
      if (!_cashierPinRegex.hasMatch(newPin)) {
        throw ArgumentError('Cashier PIN must be exactly 4 numeric digits.');
      }
    }

    final newHash = PinHasher.hashPin(newPin);

    // Ensure PIN is not already in use by someone else
    final conflictRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'pin_hash = ? AND id != ?',
      whereArgs: [newHash, staffId],
      limit: 1,
    );
    if (conflictRows.isNotEmpty) {
      throw StateError('This PIN is already in use by another staff member.');
    }

    final count = await database.update(
      PosDatabaseConstants.tableStaff,
      {'pin_hash': newHash},
      where: 'id = ?',
      whereArgs: [staffId],
    );

    return count > 0;
  }

  /// Lists all registered staff members with joined department names.
  Future<List<Staff>> getAllStaff() async {
    final rows = await database.rawQuery('''
      SELECT 
        s.job_role_id,
        s.login_enabled,
        j.name AS job_role_name,
        s.id, 
        s.name, 
        s.department_id, 
        s.pin_hash, 
        s.role, 
        s.is_active, 
        s.created_at,
        d.name AS department_name
      FROM ${PosDatabaseConstants.tableStaff} s
      LEFT JOIN job_roles j ON s.job_role_id = j.id
      LEFT JOIN ${PosDatabaseConstants.tableDepartments} d 
        ON s.department_id = d.id
      ORDER BY s.id ASC;
    ''');

    return rows
        .where((r) => StaffRole.isInteractiveCode(r['role'] as String))
        .map((r) => Staff.fromMap(
              r,
              departmentName: r['department_name'] as String?,
            ))
        .toList();
  }

  /// Activates or deactivates a staff member's account.
  Future<bool> updateStaffActiveStatus({
    required int staffId,
    required bool isActive,
  }) async {
    final count = await database.update(
      PosDatabaseConstants.tableStaff,
      {'is_active': isActive ? 1 : 0},
      where: 'id = ?',
      whereArgs: [staffId],
    );
    return count > 0;
  }

  /// Updates a staff member's general profile information.
  Future<Staff> updateStaff({
    required int staffId,
    required String name,
    required int departmentId,
    required StaffRole role,
    String? newPin,
    bool? isActive,
    int? jobRoleId,
    bool loginEnabled = true,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Staff name cannot be empty.');
    }

    final deptRows = await database.query(
      PosDatabaseConstants.tableDepartments,
      where: 'id = ?',
      whereArgs: [departmentId],
      limit: 1,
    );
    if (deptRows.isEmpty) {
      throw ArgumentError('Department ID $departmentId does not exist.');
    }
    final departmentName = deptRows.first['name'] as String;

    await _validateJobRole(jobRoleId);
    final existing = await database.query('staff', where: 'id = ?', whereArgs: [staffId]);
    if (existing.isEmpty) throw StateError('Staff member does not exist.');
    if (loginEnabled && existing.first['login_enabled'] == 0 && newPin == null) {
      throw ArgumentError('Set a PIN when enabling system access.');
    }
    final updateValues = <String, Object?>{
      'job_role_id': jobRoleId,
      'login_enabled': loginEnabled ? 1 : 0,
      'name': trimmedName,
      'department_id': departmentId,
      'role': role.code,
    };

    if (isActive != null) {
      updateValues['is_active'] = isActive ? 1 : 0;
    }

    if (newPin != null && loginEnabled) {
      if (role == StaffRole.manager) {
        if (!_managerPinRegex.hasMatch(newPin)) {
          throw ArgumentError('Manager PIN must be between 4 and 8 numeric digits.');
        }
      } else {
        if (!_cashierPinRegex.hasMatch(newPin)) {
          throw ArgumentError('Cashier PIN must be exactly 4 numeric digits.');
        }
      }
      final newHash = PinHasher.hashPin(newPin);
      final conflictRows = await database.query(
        PosDatabaseConstants.tableStaff,
        where: 'pin_hash = ? AND id != ?',
        whereArgs: [newHash, staffId],
        limit: 1,
      );
      if (conflictRows.isNotEmpty) {
        throw StateError('This PIN is already in use by another staff member.');
      }
      updateValues['pin_hash'] = newHash;
    }

    await database.update(
      PosDatabaseConstants.tableStaff,
      updateValues,
      where: 'id = ?',
      whereArgs: [staffId],
    );

    final staffRows = await database.rawQuery('''
      SELECT 
        s.job_role_id,
        s.login_enabled,
        j.name AS job_role_name,
        s.id, 
        s.name, 
        s.department_id, 
        s.pin_hash, 
        s.role, 
        s.is_active, 
        s.created_at,
        d.name AS department_name
      FROM ${PosDatabaseConstants.tableStaff} s
      LEFT JOIN job_roles j ON s.job_role_id = j.id
      LEFT JOIN ${PosDatabaseConstants.tableDepartments} d 
        ON s.department_id = d.id
      WHERE s.id = ?
      LIMIT 1;
    ''', [staffId]);

    return Staff.fromMap(
      staffRows.first,
      departmentName: departmentName,
    );
  }

  // ===========================================================================
  // ONBOARDING & ACTIVE CASHIER AUDIT
  // ===========================================================================

  /// Checks whether first-run onboarding is required.
  ///
  /// Incomplete setup remains mandatory across restarts. Completed installations
  /// with disabled cashiers use the Manager portal warning instead.
  Future<bool> isOnboardingRequired() async {
    final settingRows = await database.query(
      PosDatabaseConstants.tableSystemSettings,
      where: 'key = ?',
      whereArgs: [PosDatabaseConstants.settingOnboardingCompleted],
      limit: 1,
    );
    return settingRows.isEmpty || settingRows.first['value'] != 'true';
  }

  /// Checks whether there is at least one active Cashier profile.
  Future<bool> hasActiveCashier() async {
    final cashierCountResult = await database.rawQuery(
      "SELECT COUNT(*) as count FROM ${PosDatabaseConstants.tableStaff} WHERE role = 'CASHIER' AND is_active = 1 AND login_enabled = 1;",
    );
    final count = (cashierCountResult.isNotEmpty ? cashierCountResult.first['count'] as int? : 0) ?? 0;
    return count > 0;
  }

  /// Marks first-run onboarding as completed in system settings.
  Future<void> completeOnboarding() async {
    final staff = await getAllStaff();
    if (!staff.any((s) => s.isActive && s.loginEnabled && s.role.isManager) ||
        !staff.any((s) => s.isActive && s.loginEnabled && s.role.isCashier)) {
      throw StateError('Onboarding requires an active Manager and a distinct active Cashier.');
    }
    final now = _formatTimestamp(DateTime.now());
    await database.insert(
      PosDatabaseConstants.tableSystemSettings,
      {
        'key': PosDatabaseConstants.settingOnboardingCompleted,
        'value': 'true',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Resume an interrupted setup only after verifying the existing role's PIN.
  Future<Staff> provisionOnboardingStaff({
    required String name,
    required int departmentId,
    required StaffRole role,
    required String pin,
  }) async {
    if (!await isOnboardingRequired()) {
      throw StateError('Onboarding is already complete.');
    }
    final existing = (await getAllStaff()).where((s) => s.loginEnabled && s.role == role);
    if (existing.isNotEmpty) {
      final authenticated = await authenticateWithPin(pin);
      if (authenticated == null || authenticated.role != role) {
        throw StateError('Enter the existing ${role.displayName} PIN to resume setup.');
      }
      return authenticated;
    }
    return registerStaff(name: name, departmentId: departmentId, role: role, pin: pin);
  }
}
