import 'deal_item_option.dart';

/// A component item slot or choice category within a Deal bundle.
class DealItem {
  const DealItem({
    required this.id,
    required this.dealId,
    required this.groupName,
    this.categoryId,
    this.defaultMenuItemId,
    this.isUpgradeable = false,
    this.upgradePrice = 0.0,
    this.options = const [],
    this.defaultMenuItemName,
  });

  final int id;
  final int dealId;
  final String groupName;
  final int? categoryId;
  final int? defaultMenuItemId;
  final bool isUpgradeable;
  final double upgradePrice;
  final List<DealItemOption> options;
  final String? defaultMenuItemName;

  factory DealItem.fromMap(
    Map<String, Object?> map, {
    List<DealItemOption> options = const [],
    String? defaultMenuItemName,
  }) {
    return DealItem(
      id: map['id'] as int,
      dealId: map['deal_id'] as int,
      groupName: map['group_name'] as String,
      categoryId: map['category_id'] as int?,
      defaultMenuItemId: map['default_menu_item_id'] as int?,
      isUpgradeable: (map['is_upgradeable'] as int? ?? 0) == 1,
      upgradePrice: (map['upgrade_price'] as num?)?.toDouble() ?? 0.0,
      options: options,
      defaultMenuItemName: defaultMenuItemName ?? map['default_menu_item_name'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'deal_id': dealId,
      'group_name': groupName,
      'category_id': categoryId,
      'default_menu_item_id': defaultMenuItemId,
      'is_upgradeable': isUpgradeable ? 1 : 0,
      'upgrade_price': upgradePrice,
    };
  }

  DealItem copyWith({
    int? id,
    int? dealId,
    String? groupName,
    int? categoryId,
    int? defaultMenuItemId,
    bool? isUpgradeable,
    double? upgradePrice,
    List<DealItemOption>? options,
    String? defaultMenuItemName,
  }) {
    return DealItem(
      id: id ?? this.id,
      dealId: dealId ?? this.dealId,
      groupName: groupName ?? this.groupName,
      categoryId: categoryId ?? this.categoryId,
      defaultMenuItemId: defaultMenuItemId ?? this.defaultMenuItemId,
      isUpgradeable: isUpgradeable ?? this.isUpgradeable,
      upgradePrice: upgradePrice ?? this.upgradePrice,
      options: options ?? this.options,
      defaultMenuItemName: defaultMenuItemName ?? this.defaultMenuItemName,
    );
  }
}
