import 'deal_item.dart';

/// A bundled promotion containing multiple menu items and customer-selected options sold at a package price.
class Deal {
  const Deal({
    required this.id,
    required this.name,
    required this.basePrice,
    this.isActive = true,
    required this.createdAt,
    this.items = const [],
  });

  final int id;
  final String name;
  final double basePrice;
  final bool isActive;
  final DateTime createdAt;
  final List<DealItem> items;

  factory Deal.fromMap(Map<String, Object?> map, {List<DealItem> items = const []}) {
    return Deal(
      id: map['id'] as int,
      name: map['name'] as String,
      basePrice: (map['base_price'] as num).toDouble(),
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      items: items,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'base_price': basePrice,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Deal copyWith({
    int? id,
    String? name,
    double? basePrice,
    bool? isActive,
    DateTime? createdAt,
    List<DealItem>? items,
  }) {
    return Deal(
      id: id ?? this.id,
      name: name ?? this.name,
      basePrice: basePrice ?? this.basePrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }
}
