/// Canonical roles defining staff permissions in the restaurant system.
///
/// Strictly two interactive POS roles exist: [cashier] and [manager].
/// Supervisor and Owner act as identical aliases of Manager.
enum StaffRole {
  cashier('CASHIER', 'Front Counter Cashier'),
  manager('MANAGER', 'Manager');

  const StaffRole(this.code, this.displayName);

  final String code;
  final String displayName;

  /// Display aliases: Supervisor and Owner are treated as identical aliases of Manager.
  static const StaffRole supervisor = StaffRole.manager;
  static const StaffRole owner = StaffRole.manager;

  static StaffRole fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'MANAGER':
      case 'SUPERVISOR':
      case 'OWNER':
        return StaffRole.manager;
      case 'CASHIER':
        return StaffRole.cashier;
      default:
        throw ArgumentError('Unknown staff role code: $code');
    }
  }

  bool get isManager => this == StaffRole.manager;
  bool get isCashier => this == StaffRole.cashier;
}
