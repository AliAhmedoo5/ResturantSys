import 'storage_unit.dart';
import 'modifier_group.dart';

/// Represents a modifier option applied to menu items with price and ingredient deltas.
class Modifier {
  const Modifier({
    required this.id,
    this.menuItemId,
    this.groupId,
    this.group,
    this.menuItemName,
    required this.name,
    this.priceDelta = 0.0,
    this.rawIngredientId,
    this.rawIngredientName,
    this.ingredientQtyDelta = 0.0,
    this.storageUnit,
    this.isActive = true,
    this.createdAt,
  });

  final int id;
  final int? menuItemId;
  final int? groupId;
  final ModifierGroup? group;
  final String? menuItemName;
  final String name;
  final double priceDelta;
  final int? rawIngredientId;
  final String? rawIngredientName;
  final double ingredientQtyDelta;
  final StorageUnit? storageUnit;
  final bool isActive;
  final DateTime? createdAt;

  factory Modifier.fromMap(Map<String, Object?> map, {ModifierGroup? group}) {
    final unitString = map['storage_unit'] as String?;
    return Modifier(
      id: map['id'] as int,
      menuItemId: map['menu_item_id'] as int?,
      groupId: map['group_id'] as int?,
      group: group,
      menuItemName: map['menu_item_name'] as String?,
      name: map['name'] as String,
      priceDelta: (map['price_delta'] as num?)?.toDouble() ?? 0.0,
      rawIngredientId: map['raw_ingredient_id'] as int?,
      rawIngredientName: map['raw_ingredient_name'] as String?,
      ingredientQtyDelta: (map['ingredient_qty_delta'] as num?)?.toDouble() ?? 0.0,
      storageUnit: unitString != null ? StorageUnit.fromCode(unitString) : null,
      isActive: (map['is_active'] as int?) != 0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'menu_item_id': menuItemId,
      'group_id': groupId,
      'name': name,
      'price_delta': priceDelta,
      'raw_ingredient_id': rawIngredientId,
      'ingredient_qty_delta': ingredientQtyDelta,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  Modifier copyWith({
    int? id,
    int? menuItemId,
    int? groupId,
    ModifierGroup? group,
    bool clearGroup = false,
    bool clearMenuItem = false,
    String? menuItemName,
    String? name,
    double? priceDelta,
    int? rawIngredientId,
    String? rawIngredientName,
    double? ingredientQtyDelta,
    StorageUnit? storageUnit,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Modifier(
      id: id ?? this.id,
      menuItemId: clearMenuItem ? null : menuItemId ?? this.menuItemId,
      groupId: clearGroup ? null : groupId ?? this.groupId,
      group: clearGroup ? null : group ?? this.group,
      menuItemName: menuItemName ?? this.menuItemName,
      name: name ?? this.name,
      priceDelta: priceDelta ?? this.priceDelta,
      rawIngredientId: rawIngredientId ?? this.rawIngredientId,
      rawIngredientName: rawIngredientName ?? this.rawIngredientName,
      ingredientQtyDelta: ingredientQtyDelta ?? this.ingredientQtyDelta,
      storageUnit: storageUnit ?? this.storageUnit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
