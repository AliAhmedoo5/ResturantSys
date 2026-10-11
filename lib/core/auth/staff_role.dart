/// Canonical roles defining staff permissions in the restaurant system.
enum StaffRole {
  cashier('CASHIER', 'Front Counter Cashier'),
  kitchen('KITCHEN', 'Kitchen Cook'),
  supervisor('SUPERVISOR', 'Supervisor'),
  owner('OWNER', 'Owner / Management');

  const StaffRole(this.code, this.displayName);

  final String code;
  final String displayName;

  static StaffRole fromCode(String code) {
    return StaffRole.values.firstWhere(
      (r) => r.code.toUpperCase() == code.toUpperCase(),
      orElse: () => StaffRole.cashier,
    );
  }
}
