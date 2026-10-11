import '../catalog/menu_item.dart';
import '../catalog/modifier.dart';
import 'deal.dart';

/// Represents a customer choice within a deal item slot.
class SelectedDealChoice {
  const SelectedDealChoice({
    required this.dealItemId,
    required this.groupName,
    required this.menuItemId,
    required this.menuItemName,
    this.upgradePrice = 0.0,
  });

  final int dealItemId;
  final String groupName;
  final int menuItemId;
  final String menuItemName;
  final double upgradePrice;

  Map<String, dynamic> toJson() => {
    'deal_item_id': dealItemId,
    'group_name': groupName,
    'menu_item_id': menuItemId,
    'menu_item_name': menuItemName,
    'upgrade_price': upgradePrice,
  };

  factory SelectedDealChoice.fromJson(Map<String, dynamic> json) {
    return SelectedDealChoice(
      dealItemId: json['deal_item_id'] as int,
      groupName: json['group_name'] as String,
      menuItemId: json['menu_item_id'] as int,
      menuItemName: json['menu_item_name'] as String,
      upgradePrice: (json['upgrade_price'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// An in-progress line item in the cashier's active cart.
class CartItem {
  CartItem({
    this.menuItem,
    this.deal,
    this.quantity = 1,
    List<Modifier>? selectedModifiers,
    List<SelectedDealChoice>? selectedDealChoices,
  })  : assert(menuItem != null || deal != null, 'CartItem must contain either a MenuItem or a Deal'),
        selectedModifiers = selectedModifiers ?? [],
        selectedDealChoices = selectedDealChoices ?? [];

  final MenuItem? menuItem;
  final Deal? deal;
  int quantity;
  final List<Modifier> selectedModifiers;
  final List<SelectedDealChoice> selectedDealChoices;

  bool get isDeal => deal != null;
  String get name => menuItem?.name ?? deal!.name;

  double get basePrice => menuItem?.basePrice ?? deal!.basePrice;

  /// Effective unit price including deal upgrade additions and modifier deltas.
  double get unitPrice {
    double price = basePrice;

    // Add upgrades from deal choices
    for (final choice in selectedDealChoices) {
      price += choice.upgradePrice;
    }

    // Add modifier price deltas
    for (final mod in selectedModifiers) {
      price += mod.priceDelta;
    }

    return price;
  }

  double get totalPrice => unitPrice * quantity;

  CartItem copyWith({
    MenuItem? menuItem,
    Deal? deal,
    int? quantity,
    List<Modifier>? selectedModifiers,
    List<SelectedDealChoice>? selectedDealChoices,
  }) {
    return CartItem(
      menuItem: menuItem ?? this.menuItem,
      deal: deal ?? this.deal,
      quantity: quantity ?? this.quantity,
      selectedModifiers: selectedModifiers ?? List.of(this.selectedModifiers),
      selectedDealChoices: selectedDealChoices ?? List.of(this.selectedDealChoices),
    );
  }
}
