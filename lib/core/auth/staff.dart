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
  });

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
  bool get canAccessRegister =>
      role == StaffRole.cashier ||
      role == StaffRole.supervisor ||
      role == StaffRole.owner;

  /// Can view kitchen display/tokens and log ingredient prep/wastage chits.
  bool get canAccessKitchen =>
      role == StaffRole.kitchen ||
      role == StaffRole.supervisor ||
      role == StaffRole.owner;

  /// Can access back-office settings, Khata, staff management, and reports.
  bool get canAccessSupervisorPortal =>
      role == StaffRole.supervisor || role == StaffRole.owner;

  /// Can authorize discounts exceeding cashier threshold, void orders, and kick drawer.
  bool get canAuthorizeOverrides =>
      role == StaffRole.supervisor || role == StaffRole.owner;

  /// Can authorize post-print order voids and reprint void slips.
  bool get canVoidOrders =>
      role == StaffRole.supervisor || role == StaffRole.owner;

  /// Can execute End-of-Day Z-Report, locking shifts and resetting daily tokens.
  bool get canPerformZReport =>
      role == StaffRole.supervisor || role == StaffRole.owner;

  factory Staff.fromMap(Map<String, Object?> map, {String? departmentName}) {
    return Staff(
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
