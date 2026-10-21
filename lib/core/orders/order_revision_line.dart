/// A granular line item modification attached to an immutable [OrderRevision].
class OrderRevisionLine {
  const OrderRevisionLine({
    required this.id,
    required this.revisionId,
    this.originalOrderLineId,
    this.itemId,
    required this.action,
    required this.oldQtyDecimal,
    required this.newQtyDecimal,
    required this.linePriceDeltaPaisa,
    required this.bomDisposition,
    required this.ingredientDeltaSnapshotJson,
  });

  final int id;
  final int revisionId;
  final int? originalOrderLineId;
  final int? itemId;
  final String action;
  final String oldQtyDecimal;
  final String newQtyDecimal;
  final int linePriceDeltaPaisa;
  final String bomDisposition;
  final String ingredientDeltaSnapshotJson;

  factory OrderRevisionLine.fromMap(Map<String, Object?> map) {
    return OrderRevisionLine(
      id: map['id'] as int,
      revisionId: map['revision_id'] as int,
      originalOrderLineId: map['original_order_line_id'] as int?,
      itemId: map['item_id'] as int?,
      action: map['action'] as String,
      oldQtyDecimal: map['old_qty_decimal'] as String,
      newQtyDecimal: map['new_qty_decimal'] as String,
      linePriceDeltaPaisa: map['line_price_delta_paisa'] as int,
      bomDisposition: map['bom_disposition'] as String,
      ingredientDeltaSnapshotJson:
          (map['ingredient_delta_snapshot_json'] as String?) ?? '[]',
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'revision_id': revisionId,
      'original_order_line_id': originalOrderLineId,
      'item_id': itemId,
      'action': action,
      'old_qty_decimal': oldQtyDecimal,
      'new_qty_decimal': newQtyDecimal,
      'line_price_delta_paisa': linePriceDeltaPaisa,
      'bom_disposition': bomDisposition,
      'ingredient_delta_snapshot_json': ingredientDeltaSnapshotJson,
    };
  }
}
