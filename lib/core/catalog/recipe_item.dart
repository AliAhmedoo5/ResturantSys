import 'storage_unit.dart';

/// Represents a single raw ingredient component within a Menu Item's Bill of Materials (BOM).
class RecipeItem {
  const RecipeItem({
    required this.id,
    required this.menuItemId,
    required this.rawIngredientId,
    this.rawIngredientName,
    this.storageUnit,
    required this.quantityPerRecipeUnit,
    this.costPerRecipeUnit = 0.0,
    this.createdAt,
  });

  final int id;
  final int menuItemId;
  final int rawIngredientId;
  final String? rawIngredientName;
  final StorageUnit? storageUnit;
  final double quantityPerRecipeUnit;
  final double costPerRecipeUnit;
  final DateTime? createdAt;

  /// Ingredient food cost for this recipe component.
  double get totalIngredientCost => quantityPerRecipeUnit * costPerRecipeUnit;

  factory RecipeItem.fromMap(Map<String, Object?> map) {
    final unitString = map['storage_unit'] as String?;
    return RecipeItem(
      id: map['id'] as int,
      menuItemId: map['menu_item_id'] as int,
      rawIngredientId: map['raw_ingredient_id'] as int,
      rawIngredientName: map['raw_ingredient_name'] as String?,
      storageUnit: unitString != null ? StorageUnit.fromCode(unitString) : null,
      quantityPerRecipeUnit: (map['quantity_per_recipe_unit'] as num).toDouble(),
      costPerRecipeUnit: (map['cost_per_recipe_unit'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'menu_item_id': menuItemId,
      'raw_ingredient_id': rawIngredientId,
      'quantity_per_recipe_unit': quantityPerRecipeUnit,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  RecipeItem copyWith({
    int? id,
    int? menuItemId,
    int? rawIngredientId,
    String? rawIngredientName,
    StorageUnit? storageUnit,
    double? quantityPerRecipeUnit,
    double? costPerRecipeUnit,
    DateTime? createdAt,
  }) {
    return RecipeItem(
      id: id ?? this.id,
      menuItemId: menuItemId ?? this.menuItemId,
      rawIngredientId: rawIngredientId ?? this.rawIngredientId,
      rawIngredientName: rawIngredientName ?? this.rawIngredientName,
      storageUnit: storageUnit ?? this.storageUnit,
      quantityPerRecipeUnit: quantityPerRecipeUnit ?? this.quantityPerRecipeUnit,
      costPerRecipeUnit: costPerRecipeUnit ?? this.costPerRecipeUnit,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
