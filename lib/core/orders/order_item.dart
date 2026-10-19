import 'dart:convert';

/// A line item within a finalized Order.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    this.menuItemId,
    this.dealId,
    required this.name,
    this.quantity = 1,
    required this.unitPrice,
    required this.totalPrice,
    this.modifiersJson,
    this.dealChoicesJson,
    this.bomJson,
    required this.createdAt,
  });

  final int id;
  final int orderId;
  final int? menuItemId;
  final int? dealId;
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String? modifiersJson;
  final String? dealChoicesJson;
  final String? bomJson;
  final DateTime createdAt;

  bool get isDeal => dealId != null;

  /// Quantities consumed by this entire sold line, frozen at checkout.
  /// Null identifies a legacy order whose BOM was not captured.
  Map<int, double>? get decodedBom {
    if (bomJson == null) return null;
    final values = jsonDecode(bomJson!) as Map<String, dynamic>;
    return values.map((key, value) => MapEntry(int.parse(key), (value as num).toDouble()));
  }

  List<Map<String, dynamic>> get decodedModifiers {
    if (modifiersJson == null || modifiersJson!.isEmpty) return [];
    try {
      final decoded = jsonDecode(modifiersJson!);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  List<Map<String, dynamic>> get decodedDealChoices {
    if (dealChoicesJson == null || dealChoicesJson!.isEmpty) return [];
    try {
      final decoded = jsonDecode(dealChoicesJson!);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [];
  }

  factory OrderItem.fromMap(Map<String, Object?> map) {
    return OrderItem(
      id: map['id'] as int,
      orderId: map['order_id'] as int,
      menuItemId: map['menu_item_id'] as int?,
      dealId: map['deal_id'] as int?,
      name: map['name'] as String,
      quantity: (map['quantity'] as int? ?? 1),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      modifiersJson: map['modifiers_json'] as String?,
      dealChoicesJson: map['deal_choices_json'] as String?,
      bomJson: map['bom_json'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'order_id': orderId,
      'menu_item_id': menuItemId,
      'deal_id': dealId,
      'name': name,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'modifiers_json': modifiersJson,
      'deal_choices_json': dealChoicesJson,
      'bom_json': bomJson,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
