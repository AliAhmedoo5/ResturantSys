import 'dart:convert';
import '../orders/cart_item.dart';
import 'discount_rules.dart';
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
    this.rules = const DiscountRules(),
  });

  final int id;
  final String name;
  final DiscountType type;
  final double value;
  final bool isActive;
  final DateTime? createdAt;
  final DiscountRules rules;

  /// Calculates the rupee discount amount against a given subtotal.
  /// Never exceeds the subtotal itself.
  double calculateDiscount(double subtotal, {List<CartItem>? items, String? diningMode, int? cashierId, DateTime? now}) {
    if (!isActive || !subtotal.isFinite || !value.isFinite || subtotal <= 0 || value <= 0) return 0;
    final subtotalPaisa = (subtotal * 100).round();
    if (!rules.eligible(subtotalPaisa: subtotalPaisa, now: now ?? DateTime.now(), diningMode: diningMode, cashierId: cashierId)) return 0;
    final eligiblePaisa = items == null
      ? (rules.categoryIds.isEmpty && rules.dealIds.isEmpty ? subtotalPaisa : 0)
      : items.where(rules.includes).fold<int>(0, (sum, item) => sum + (item.totalPrice * 100).round());
    final basisPoints = (value * 100).round();
    var amount = type == DiscountType.percentage ? (eligiblePaisa * basisPoints + 5000) ~/ 10000 : (value * 100).round();
    if (amount > eligiblePaisa) amount = eligiblePaisa;
    if (rules.maximumDiscountPaisa != null && amount > rules.maximumDiscountPaisa!) amount = rules.maximumDiscountPaisa!;
    return amount / 100.0;
  }

  factory DiscountPreset.fromMap(Map<String, Object?> map) {
    return DiscountPreset(
      id: map['id'] as int,
      rules: DiscountRules.fromMap(jsonDecode(map['rules_json'] as String? ?? '{}') as Map<String, dynamic>),
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
      'rules_json': jsonEncode(rules.toMap()),
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
    DiscountRules? rules,
  }) {
    return DiscountPreset(
      id: id ?? this.id,
      rules: rules ?? this.rules,
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
