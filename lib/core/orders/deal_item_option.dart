/// An optional choice within a deal item slot (e.g. Cola, Sprite, or Large Fries with upgrade price).
class DealItemOption {
  const DealItemOption({
    required this.id,
    required this.dealItemId,
    required this.menuItemId,
    this.isDefault = false,
    this.upgradePrice = 0.0,
    this.menuItemName,
  });

  final int id;
  final int dealItemId;
  final int menuItemId;
  final bool isDefault;
  final double upgradePrice;
  final String? menuItemName;

  factory DealItemOption.fromMap(Map<String, Object?> map, {String? menuItemName}) {
    return DealItemOption(
      id: map['id'] as int,
      dealItemId: map['deal_item_id'] as int,
      menuItemId: map['menu_item_id'] as int,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      upgradePrice: (map['upgrade_price'] as num?)?.toDouble() ?? 0.0,
      menuItemName: menuItemName ?? map['menu_item_name'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'deal_item_id': dealItemId,
      'menu_item_id': menuItemId,
      'is_default': isDefault ? 1 : 0,
      'upgrade_price': upgradePrice,
    };
  }

  DealItemOption copyWith({
    int? id,
    int? dealItemId,
    int? menuItemId,
    bool? isDefault,
    double? upgradePrice,
    String? menuItemName,
  }) {
    return DealItemOption(
      id: id ?? this.id,
      dealItemId: dealItemId ?? this.dealItemId,
      menuItemId: menuItemId ?? this.menuItemId,
      isDefault: isDefault ?? this.isDefault,
      upgradePrice: upgradePrice ?? this.upgradePrice,
      menuItemName: menuItemName ?? this.menuItemName,
    );
  }
}
