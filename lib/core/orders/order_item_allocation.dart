/// Data model representing an immutable line-level sales, discount, tax,
/// BOM recipe cost, and contribution margin allocation in signed 64-bit Integer Paisa.
///
/// Governed by ADR-0021: Line-Level Sales and Cost Allocation Policy.
class OrderItemAllocation {
  const OrderItemAllocation({
    this.id,
    required this.orderId,
    this.orderItemId,
    this.revision = 0,
    required this.lineKind,
    required this.entryType,
    this.menuItemId,
    this.dealId,
    this.componentMenuItemId,
    required this.itemNameSnapshot,
    required this.quantity,
    required this.grossSalesPaisa,
    required this.allocatedDiscountPaisa,
    required this.netSalesPaisa,
    required this.taxCarveOutPaisa,
    this.bomRecipeCostPaisa,
    this.contributionMarginPaisa,
    required this.recordedAt,
  });

  final int? id;
  final int orderId;
  final int? orderItemId;
  final int revision;
  final String lineKind; // 'ITEM', 'DEAL_PARENT', 'DEAL_COMPONENT'
  final String entryType; // 'SALE', 'CONTRA'
  final int? menuItemId;
  final int? dealId;
  final int? componentMenuItemId;
  final String itemNameSnapshot;
  final int quantity;
  final int grossSalesPaisa;
  final int allocatedDiscountPaisa;
  final int netSalesPaisa;
  final int taxCarveOutPaisa;
  final int? bomRecipeCostPaisa;
  final int? contributionMarginPaisa;
  final DateTime recordedAt;

  bool get isContra => entryType == 'CONTRA';
  bool get isDealComponent => lineKind == 'DEAL_COMPONENT';
  bool get isDealParent => lineKind == 'DEAL_PARENT';
  bool get isItem => lineKind == 'ITEM';

  factory OrderItemAllocation.fromMap(Map<String, Object?> map) {
    return OrderItemAllocation(
      id: map['id'] as int?,
      orderId: map['order_id'] as int,
      orderItemId: map['order_item_id'] as int?,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
      lineKind: map['line_kind'] as String? ?? 'ITEM',
      entryType: map['entry_type'] as String? ?? 'SALE',
      menuItemId: map['menu_item_id'] as int?,
      dealId: map['deal_id'] as int?,
      componentMenuItemId: map['component_menu_item_id'] as int?,
      itemNameSnapshot: map['item_name_snapshot'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      grossSalesPaisa: (map['gross_sales_paisa'] as num?)?.toInt() ?? 0,
      allocatedDiscountPaisa: (map['allocated_discount_paisa'] as num?)?.toInt() ?? 0,
      netSalesPaisa: (map['net_sales_paisa'] as num?)?.toInt() ?? 0,
      taxCarveOutPaisa: (map['tax_carve_out_paisa'] as num?)?.toInt() ?? 0,
      bomRecipeCostPaisa: (map['bom_recipe_cost_paisa'] as num?)?.toInt(),
      contributionMarginPaisa: (map['contribution_margin_paisa'] as num?)?.toInt(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'order_id': orderId,
      'order_item_id': orderItemId,
      'revision': revision,
      'line_kind': lineKind,
      'entry_type': entryType,
      'menu_item_id': menuItemId,
      'deal_id': dealId,
      'component_menu_item_id': componentMenuItemId,
      'item_name_snapshot': itemNameSnapshot,
      'quantity': quantity,
      'gross_sales_paisa': grossSalesPaisa,
      'allocated_discount_paisa': allocatedDiscountPaisa,
      'net_sales_paisa': netSalesPaisa,
      'tax_carve_out_paisa': taxCarveOutPaisa,
      'bom_recipe_cost_paisa': bomRecipeCostPaisa,
      'contribution_margin_paisa': contributionMarginPaisa,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}
