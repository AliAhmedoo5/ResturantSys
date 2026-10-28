/// Draft definition when creating or configuring a deal item slot.
class DealItemDraft {
  const DealItemDraft({
    this.id,
    required this.groupName,
    this.categoryId,
    this.defaultMenuItemId,
    this.isUpgradeable = false,
    this.upgradePrice = 0.0,
    this.options = const [],
  });

  final String groupName;
  final int? id;
  final int? categoryId;
  final int? defaultMenuItemId;
  final bool isUpgradeable;
  final double upgradePrice;
  final List<DealOptionDraft> options;
}

/// Draft definition of an option inside a deal item slot.
class DealOptionDraft {
  const DealOptionDraft({
    required this.menuItemId,
    this.isDefault = false,
    this.upgradePrice = 0.0,
  });

  final int menuItemId;
  final bool isDefault;
  final double upgradePrice;
}
