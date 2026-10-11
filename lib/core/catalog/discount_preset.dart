/// Type of promotional or pre-approved discount applied at checkout.
enum DiscountType {
  percentage('PERCENTAGE', 'Percentage (%)'),
  flat('FLAT', 'Flat Amount (Rs)');

  const DiscountType(this.code, this.displayName);

  final String code;
  final String displayName;

  static DiscountType fromCode(String code) {
    return DiscountType.values.firstWhere(
      (t) => t.code.toUpperCase() == code.toUpperCase(),
      orElse: () => DiscountType.percentage,
    );
  }
}

/// Pre-approved discount preset configured by supervisor for fast cashier checkout.
///
/// Implements ADR-0004: pre-configured discounts selectable without supervisor PIN.
class DiscountPreset {
  const DiscountPreset({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
    required this.isActive,
    this.createdAt,
  });

  final int id;
  final String name;
  final DiscountType type;
  final double value;
  final bool isActive;
  final DateTime? createdAt;

  /// Calculates the rupee discount amount against a given subtotal.
  /// Never exceeds the subtotal itself.
  double calculateDiscount(double subtotal) {
    if (subtotal <= 0 || value <= 0) return 0.0;
    if (type == DiscountType.percentage) {
      final amount = subtotal * (value / 100.0);
      return amount > subtotal ? subtotal : amount;
    } else {
      return value > subtotal ? subtotal : value;
    }
  }

  factory DiscountPreset.fromMap(Map<String, Object?> map) {
    return DiscountPreset(
      id: map['id'] as int,
      name: map['name'] as String,
      type: DiscountType.fromCode(map['type'] as String),
      value: (map['value'] as num).toDouble(),
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
      'type': type.code,
      'value': value,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  DiscountPreset copyWith({
    int? id,
    String? name,
    DiscountType? type,
    double? value,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return DiscountPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
