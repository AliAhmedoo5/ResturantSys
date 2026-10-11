/// Fulfillment channel driving packaging deductions and kitchen routing.
enum DiningType {
  dineIn('DINE_IN', 'Dine-In'),
  takeaway('TAKEAWAY', 'Takeaway'),
  delivery('DELIVERY', 'Delivery');

  const DiningType(this.code, this.displayName);

  final String code;
  final String displayName;

  static DiningType fromCode(String code) {
    return DiningType.values.firstWhere(
      (type) => type.code == code,
      orElse: () => DiningType.dineIn,
    );
  }

  bool get requiresPackaging => this == DiningType.takeaway || this == DiningType.delivery;
}
