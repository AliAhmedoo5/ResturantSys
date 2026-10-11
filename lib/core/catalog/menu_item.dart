/// Represents a sellable menu item with tax-inclusive pricing.
class MenuItem {
  const MenuItem({
    required this.id,
    required this.categoryId,
    this.categoryName,
    required this.name,
    required this.basePrice,
    this.taxRate = 0.0,
    this.isTaxInclusive = true,
    this.isActive = true,
    this.createdAt,
  });

  final int id;
  final int categoryId;
  final String? categoryName;
  final String name;
  final double basePrice;
  final double taxRate;
  final bool isTaxInclusive;
  final bool isActive;
  final DateTime? createdAt;

  /// The pre-tax net price of the item.
  /// When [isTaxInclusive] is true, back-calculates net: basePrice / (1 + taxRate / 100).
  double get netPrice {
    if (taxRate <= 0) return basePrice;
    if (isTaxInclusive) {
      return basePrice / (1.0 + (taxRate / 100.0));
    }
    return basePrice;
  }

  /// The tax portion in rupees.
  double get taxAmount {
    if (taxRate <= 0) return 0.0;
    if (isTaxInclusive) {
      return basePrice - netPrice;
    }
    return basePrice * (taxRate / 100.0);
  }

  /// Total customer-facing price.
  double get grossPrice {
    if (isTaxInclusive || taxRate <= 0) {
      return basePrice;
    }
    return basePrice + taxAmount;
  }

  factory MenuItem.fromMap(Map<String, Object?> map, {String? categoryName}) {
    return MenuItem(
      id: map['id'] as int,
      categoryId: map['category_id'] as int,
      categoryName: categoryName ?? (map['category_name'] as String?),
      name: map['name'] as String,
      basePrice: (map['base_price'] as num).toDouble(),
      taxRate: (map['tax_rate'] as num?)?.toDouble() ?? 0.0,
      isTaxInclusive: (map['is_tax_inclusive'] as int?) != 0,
      isActive: (map['is_active'] as int?) != 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'category_id': categoryId,
      'name': name,
      'base_price': basePrice,
      'tax_rate': taxRate,
      'is_tax_inclusive': isTaxInclusive ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  MenuItem copyWith({
    int? id,
    int? categoryId,
    String? categoryName,
    String? name,
    double? basePrice,
    double? taxRate,
    bool? isTaxInclusive,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return MenuItem(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      name: name ?? this.name,
      basePrice: basePrice ?? this.basePrice,
      taxRate: taxRate ?? this.taxRate,
      isTaxInclusive: isTaxInclusive ?? this.isTaxInclusive,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
