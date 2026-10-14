import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'wastage_reason.dart';

/// Represents an audited kitchen ingredient spoilage or damage incident.
class KitchenWastage {
  const KitchenWastage({
    required this.id,
    required this.staffId,
    this.staffName,
    required this.rawIngredientId,
    this.rawIngredientName,
    required this.quantity,
    this.storageUnit = StorageUnit.g,
    required this.costLoss,
    required this.reason,
    this.notes,
    required this.createdAt,
  });

  final int id;
  final int staffId;
  final String? staffName;
  final int rawIngredientId;
  final String? rawIngredientName;
  final double quantity;
  final StorageUnit storageUnit;
  final double costLoss;
  final WastageReason reason;
  final String? notes;
  final DateTime createdAt;

  factory KitchenWastage.fromMap(
    Map<String, Object?> map, {
    String? staffName,
    String? rawIngredientName,
    String? storageUnit,
  }) {
    return KitchenWastage(
      id: map['id'] as int,
      staffId: map['staff_id'] as int,
      staffName: staffName ?? (map['staff_name'] as String?),
      rawIngredientId: map['raw_ingredient_id'] as int,
      rawIngredientName: rawIngredientName ?? (map['raw_ingredient_name'] as String?),
      quantity: (map['quantity'] as num).toDouble(),
      storageUnit: storageUnit != null
          ? StorageUnit.fromCode(storageUnit)
          : StorageUnit.fromCode((map['storage_unit'] as String?) ?? 'g'),
      costLoss: (map['cost_loss'] as num).toDouble(),
      reason: WastageReason.fromCode(map['reason'] as String),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'staff_id': staffId,
      'raw_ingredient_id': rawIngredientId,
      'quantity': quantity,
      'cost_loss': costLoss,
      'reason': reason.code,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
