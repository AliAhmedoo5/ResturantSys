import 'staff_role.dart';

/// Represents a registered staff member with role-based operational permissions.
class Staff {
  const Staff({
    required this.id,
    required this.name,
    required this.departmentId,
    this.departmentName,
    required this.pinHash,
    required this.role,
    required this.isActive,
    this.createdAt,
    this.jobRoleId,
    this.jobRoleName,
    this.loginEnabled = true,
  });

  final int? jobRoleId;
  final String? jobRoleName;
  final bool loginEnabled;

  final int id;
  final String name;
  final int departmentId;
  final String? departmentName;
  final String pinHash;
  final StaffRole role;
  final bool isActive;
  final DateTime? createdAt;

  // ---------------------------------------------------------------------------
  // Role-Based Capabilities
  // ---------------------------------------------------------------------------

  /// Can open shifts, tender orders, and operate the counter cash drawer.
  /// Strictly restricted to Cashiers; Manager credentials cannot operate the counter.
  bool get canAccessRegister => loginEnabled && role == StaffRole.cashier;

  /// Both operating roles can assign and monitor delivery trips.
  /// Cash collection remains restricted to the Cashier's own open shift.
  bool get canAccessRiderTrips => isActive && loginEnabled &&
      (role == StaffRole.cashier || role == StaffRole.manager);

  /// Can access back-office settings, Khata, staff management, and reports.
  bool get canAccessSupervisorPortal => loginEnabled && role == StaffRole.manager;

  /// Can authorize discounts exceeding cashier threshold, void orders, and kick drawer.
  bool get canAuthorizeOverrides => loginEnabled && role == StaffRole.manager;

  /// Can authorize audited order voids.
  bool get canVoidOrders => loginEnabled && role == StaffRole.manager;

  /// Can execute End-of-Day Z-Report, locking shifts and resetting daily tokens.
  bool get canPerformZReport => loginEnabled && role == StaffRole.manager;

  Staff copyWith({
    int? id,
    String? name,
    int? departmentId,
    String? departmentName,
    String? pinHash,
    StaffRole? role,
    bool? isActive,
    DateTime? createdAt,
    int? jobRoleId,
    String? jobRoleName,
    bool? loginEnabled,
  }) {
    return Staff(
      jobRoleId: jobRoleId ?? this.jobRoleId,
      jobRoleName: jobRoleName ?? this.jobRoleName,
      loginEnabled: loginEnabled ?? this.loginEnabled,
      id: id ?? this.id,
      name: name ?? this.name,
      departmentId: departmentId ?? this.departmentId,
      departmentName: departmentName ?? this.departmentName,
      pinHash: pinHash ?? this.pinHash,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Staff.fromMap(Map<String, Object?> map, {String? departmentName}) {
    return Staff(
      jobRoleId: map['job_role_id'] as int?,
      jobRoleName: map['job_role_name'] as String?,
      loginEnabled: (map['login_enabled'] as int? ?? 1) == 1,
      id: map['id'] as int,
      name: map['name'] as String,
      departmentId: map['department_id'] as int,
      departmentName: departmentName ?? (map['department_name'] as String?),
      pinHash: map['pin_hash'] as String,
      role: StaffRole.fromCode(map['role'] as String),
      isActive: (map['is_active'] as int?) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'job_role_id': jobRoleId,
      'login_enabled': loginEnabled ? 1 : 0,
      'id': id,
      'name': name,
      'department_id': departmentId,
      'pin_hash': pinHash,
      'role': role.code,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
