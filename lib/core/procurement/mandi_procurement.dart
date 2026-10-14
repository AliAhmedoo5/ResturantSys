import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'desi_unit.dart';

/// Represents a recorded traditional Pakistani wholesale market purchase.
class MandiProcurement {
  const MandiProcurement({
    required this.id,
    required this.rawIngredientId,
    this.rawIngredientName,
    required this.traditionalUnit,
    required this.quantity,
    required this.totalCost,
    required this.convertedQuantity,
    required this.costPerRecipeUnit,
    this.storageUnit = StorageUnit.g,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final int rawIngredientId;
  final String? rawIngredientName;
  final DesiUnit traditionalUnit;
  final double quantity;
  final double totalCost;
  final double convertedQuantity;
  final double costPerRecipeUnit;
  final StorageUnit storageUnit;
  final String? notes;
  final DateTime createdAt;

  factory MandiProcurement.fromMap(
    Map<String, Object?> map, {
    String? ingredientName,
    String? ingredientUnit,
  }) {
    return MandiProcurement(
      id: map['id'] as int,
      rawIngredientId: map['raw_ingredient_id'] as int,
      rawIngredientName: ingredientName ?? (map['raw_ingredient_name'] as String?),
      traditionalUnit: DesiUnit.fromCode(map['traditional_unit'] as String),
      quantity: (map['quantity'] as num).toDouble(),
      totalCost: (map['total_cost'] as num).toDouble(),
      convertedQuantity: (map['converted_quantity'] as num).toDouble(),
      costPerRecipeUnit: (map['cost_per_recipe_unit'] as num).toDouble(),
      storageUnit: ingredientUnit != null
          ? StorageUnit.fromCode(ingredientUnit)
          : StorageUnit.fromCode((map['storage_unit'] as String?) ?? 'g'),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'raw_ingredient_id': rawIngredientId,
      'traditional_unit': traditionalUnit.code,
      'quantity': quantity,
      'total_cost': totalCost,
      'converted_quantity': convertedQuantity,
      'cost_per_recipe_unit': costPerRecipeUnit,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
