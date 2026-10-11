import 'storage_unit.dart';

/// Represents a bulk raw ingredient stock entity tracked in kitchen inventory.
class RawIngredient {
  const RawIngredient({
    required this.id,
    required this.name,
    required this.storageUnit,
    required this.currentStock,
    required this.lowStockThreshold,
    this.costPerRecipeUnit = 0.0,
    this.createdAt,
  });

  final int id;
  final String name;
  final StorageUnit storageUnit;
  final double currentStock;
  final double lowStockThreshold;
  final double costPerRecipeUnit;
  final DateTime? createdAt;

  /// Indicates if the available stock has reached or fallen below the warning threshold.
  bool get isLowStock => currentStock <= lowStockThreshold;

  factory RawIngredient.fromMap(Map<String, Object?> map) {
    return RawIngredient(
      id: map['id'] as int,
      name: map['name'] as String,
      storageUnit: StorageUnit.fromCode(map['storage_unit'] as String),
      currentStock: (map['current_stock'] as num).toDouble(),
      lowStockThreshold: (map['low_stock_threshold'] as num).toDouble(),
      costPerRecipeUnit: (map['cost_per_recipe_unit'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'storage_unit': storageUnit.code,
      'current_stock': currentStock,
      'low_stock_threshold': lowStockThreshold,
      'cost_per_recipe_unit': costPerRecipeUnit,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  RawIngredient copyWith({
    int? id,
    String? name,
    StorageUnit? storageUnit,
    double? currentStock,
    double? lowStockThreshold,
    double? costPerRecipeUnit,
    DateTime? createdAt,
  }) {
    return RawIngredient(
      id: id ?? this.id,
      name: name ?? this.name,
      storageUnit: storageUnit ?? this.storageUnit,
      currentStock: currentStock ?? this.currentStock,
      lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
      costPerRecipeUnit: costPerRecipeUnit ?? this.costPerRecipeUnit,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
