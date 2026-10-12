import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/catalog/menu_item.dart';
import '../../core/orders/cart_item.dart';
import '../../core/orders/deal.dart';
import '../../core/orders/deal_item.dart';
import '../../core/theme/theme.dart';

/// Fast 1-tap modal for configuring customer choices and upgrades within a Deal.
class DealSelectionDialog extends StatefulWidget {
  const DealSelectionDialog({
    super.key,
    required this.deal,
    this.availableMenuItems = const [],
  });

  final Deal deal;
  final List<MenuItem> availableMenuItems;

  @override
  State<DealSelectionDialog> createState() => _DealSelectionDialogState();
}

class _DealSelectionDialogState extends State<DealSelectionDialog> {
  // Map of dealItemId -> Selected option
  final Map<int, ({int menuItemId, String menuItemName, double upgradePrice})> _selectedChoices = {};
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _initializeDefaults();
  }

  void _initializeDefaults() {
    for (final item in widget.deal.items) {
      if (item.options.isNotEmpty) {
        // Find default option or pick first
        final defaultOpt = item.options.firstWhere(
          (o) => o.isDefault,
          orElse: () => item.options.first,
        );
        final name = defaultOpt.menuItemName ?? _resolveMenuItemName(defaultOpt.menuItemId);
        _selectedChoices[item.id] = (
          menuItemId: defaultOpt.menuItemId,
          menuItemName: name,
          upgradePrice: defaultOpt.upgradePrice,
        );
      } else if (item.defaultMenuItemId != null) {
        final name = item.defaultMenuItemName ?? _resolveMenuItemName(item.defaultMenuItemId!);
        _selectedChoices[item.id] = (
          menuItemId: item.defaultMenuItemId!,
          menuItemName: name,
          upgradePrice: 0.0,
        );
      }
    }
  }

  String _resolveMenuItemName(int id) {
    try {
      final found = widget.availableMenuItems.firstWhere((m) => m.id == id);
      return found.name;
    } catch (_) {
      return 'Item #$id';
    }
  }

  double get _currentTotalPrice {
    double total = widget.deal.basePrice;
    for (final choice in _selectedChoices.values) {
      total += choice.upgradePrice;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(WarmCounterSpacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.deal.name,
                          style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Base Price: Rs ${_currencyFormat.format(widget.deal.basePrice)}',
                          style: WarmCounterTypography.bodyMedium.copyWith(
                            color: WarmCounterColors.lightSecondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

              // Item Slot Groups
              Expanded(
                child: ListView.separated(
                  itemCount: widget.deal.items.length,
                  separatorBuilder: (context, _) => const SizedBox(height: WarmCounterSpacing.space16),
                  itemBuilder: (context, index) {
                    final item = widget.deal.items[index];
                    return _buildDealItemSlot(item);
                  },
                ),
              ),

              const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

              // Bottom Price & Confirm
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Package Price:',
                          style: WarmCounterTypography.secondaryLabel.copyWith(
                            color: WarmCounterColors.lightSecondaryText,
                          ),
                        ),
                        Text(
                          'Rs ${_currencyFormat.format(_currentTotalPrice)}',
                          style: WarmCounterTypography.tabularPrice.copyWith(
                            fontSize: 22,
                            color: WarmCounterColors.lightPrimaryAction,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  ElevatedButton.icon(
                    key: const ValueKey('add_deal_to_order_button'),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Add to Order'),
                    onPressed: _handleConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(160, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDealItemSlot(DealItem item) {
    final selected = _selectedChoices[item.id];

    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space12),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightPageBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.groupName,
            style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: WarmCounterSpacing.space8),
          if (item.options.isNotEmpty)
            Wrap(
              spacing: WarmCounterSpacing.space8,
              runSpacing: WarmCounterSpacing.space8,
              children: item.options.map((opt) {
                final isChosen = selected?.menuItemId == opt.menuItemId &&
                    (selected?.upgradePrice ?? 0.0) == opt.upgradePrice;
                final optName = opt.menuItemName ?? _resolveMenuItemName(opt.menuItemId);
                final upgradeLabel = opt.upgradePrice > 0
                    ? ' (+Rs ${_currencyFormat.format(opt.upgradePrice)})'
                    : '';

                return ChoiceChip(
                  key: ValueKey('deal_opt_${item.id}_${opt.id}'),
                  label: Text('$optName$upgradeLabel'),
                  selected: isChosen,
                  selectedColor: WarmCounterColors.lightActiveNavHighlight,
                  onSelected: (chosen) {
                    if (chosen) {
                      setState(() {
                        _selectedChoices[item.id] = (
                          menuItemId: opt.menuItemId,
                          menuItemName: optName,
                          upgradePrice: opt.upgradePrice,
                        );
                      });
                    }
                  },
                );
              }).toList(),
            )
          else if (item.defaultMenuItemId != null)
            Text(
              'Included: ${item.defaultMenuItemName ?? _resolveMenuItemName(item.defaultMenuItemId!)}',
              style: WarmCounterTypography.bodyMedium.copyWith(
                color: WarmCounterColors.lightSecondaryText,
              ),
            ),
        ],
      ),
    );
  }

  void _handleConfirm() {
    final choices = <SelectedDealChoice>[];
    for (final entry in _selectedChoices.entries) {
      final dealItemId = entry.key;
      final val = entry.value;
      final dealItem = widget.deal.items.firstWhere((i) => i.id == dealItemId);

      choices.add(SelectedDealChoice(
        dealItemId: dealItemId,
        groupName: dealItem.groupName,
        menuItemId: val.menuItemId,
        menuItemName: val.menuItemName,
        upgradePrice: val.upgradePrice,
      ));
    }

    Navigator.of(context).pop(choices);
  }
}
