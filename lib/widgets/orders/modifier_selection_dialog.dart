import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/catalog/modifier.dart';
import '../../core/catalog/modifier_group.dart';
import '../../core/theme/theme.dart';

/// Modal sheet for selecting item customizations (+Add-ons with price/BOM addition, -Removals with 0g BOM).
class ModifierSelectionDialog extends StatefulWidget {
  const ModifierSelectionDialog({
    super.key,
    required this.itemName,
    required this.availableModifiers,
    this.initialSelected = const [],
    this.groups = const [],
  });

  final String itemName;
  final List<ModifierGroup> groups;
  final List<Modifier> availableModifiers;
  final List<Modifier> initialSelected;

  @override
  State<ModifierSelectionDialog> createState() => _ModifierSelectionDialogState();
}

class _ModifierSelectionDialogState extends State<ModifierSelectionDialog> {
  late final Set<int> _selectedIds;
  String? _error;

  List<ModifierGroup> get _groups => {
    for (final group in widget.groups) group.id: group,
    for (final modifier in widget.availableModifiers)
      if (modifier.group != null) modifier.group!.id: modifier.group!,
  }.values.toList();
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialSelected.map((m) => m.id).toSet();
  }

  @override
  Widget build(BuildContext context) {
    // Separate into Add-ons (+ price/ingredient) and Removals (- price 0 / 'No')
    final addOns = widget.availableModifiers.where((m) => m.groupId == null && (m.priceDelta > 0 || m.ingredientQtyDelta > 0)).toList();
    final removals = widget.availableModifiers.where((m) => m.groupId == null && m.priceDelta <= 0 && m.ingredientQtyDelta <= 0).toList();

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 620),
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
                          'Customize: ${widget.itemName}',
                          style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select Add-ons or ingredient removals for kitchen prep',
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

              // Modifiers list
              Expanded(
                child: ListView(
                  children: [
                    for (final group in _groups) _buildGroup(group),
                    if (addOns.isNotEmpty) ...[
                      Text(
                        '+ Add-ons (Price & BOM Addition)',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: WarmCounterColors.lightPrimaryAction,
                        ),
                      ),
                      const SizedBox(height: WarmCounterSpacing.space8),
                      ...addOns.map(_buildModifierTile),
                      const SizedBox(height: WarmCounterSpacing.space16),
                    ],
                    if (removals.isNotEmpty) ...[
                      Text(
                        '- Removals (0g BOM Recipe Deduction)',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: WarmCounterColors.lightDestructiveAction,
                        ),
                      ),
                      const SizedBox(height: WarmCounterSpacing.space8),
                      ...removals.map(_buildModifierTile),
                    ],
                    if (widget.availableModifiers.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            'No modifiers configured for this item.',
                            style: WarmCounterTypography.bodyMedium.copyWith(
                              color: WarmCounterColors.lightSecondaryText,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

              if (_error != null)
                Text(_error!, key: const ValueKey('modifier_selection_error'), style: const TextStyle(color: WarmCounterColors.lightDestructiveAction)),
              // Bottom Apply
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Flexible(
                    child: ElevatedButton.icon(
                      key: const ValueKey('apply_modifiers_button'),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Apply Customizations'),
                      onPressed: _handleApply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(140, WarmCounterSpacing.touchTargetMin),
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

  Widget _buildGroup(ModifierGroup group) {
    final options = widget.availableModifiers.where((m) => m.groupId == group.id).toList();
    final selected = options.where((m) => _selectedIds.contains(m.id)).firstOrNull;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(group.name, style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
      Text('${group.isRequired ? 'Required: ' : ''}Choose ${group.requiredCount} to ${group.maxSelected}', style: WarmCounterTypography.caption),
      ...options.map(_buildModifierTile),
      const SizedBox(height: WarmCounterSpacing.space16),
    ]);
    if (group.selectionMode != 'SINGLE') return content;
    return RadioGroup<int>(groupValue: selected?.id, onChanged: (value) {
      if (value == null) {
        if (selected != null) _toggleModifier(selected, false);
      } else {
        _toggleModifier(options.firstWhere((m) => m.id == value), true);
      }
    }, child: content);
  }

  Widget _buildModifierTile(Modifier mod) {
    final isSelected = _selectedIds.contains(mod.id);
    final priceLabel = mod.priceDelta > 0
        ? '+Rs ${_currencyFormat.format(mod.priceDelta)}'
        : 'Rs 0.00';

    final group = _groups.where((g) => g.id == mod.groupId).firstOrNull;
    if (group?.selectionMode == 'SINGLE') {
      return RadioListTile<int>(
        key: ValueKey('modifier_tile_${mod.id}'),
        value: mod.id,
        toggleable: !(group?.isRequired ?? false),
        title: Text(mod.name, style: WarmCounterTypography.bodyMedium),
        subtitle: Text(priceLabel),
        activeColor: WarmCounterColors.lightPrimaryAction,
      );
    }

    return CheckboxListTile(
      key: ValueKey('modifier_tile_${mod.id}'),
      title: Text(mod.name, style: WarmCounterTypography.bodyMedium),
      subtitle: Text(
        priceLabel,
        style: WarmCounterTypography.caption.copyWith(
          color: mod.priceDelta > 0
              ? WarmCounterColors.lightPrimaryAction
              : WarmCounterColors.lightSecondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
      value: isSelected,
      activeColor: WarmCounterColors.lightPrimaryAction,
      onChanged: (val) => _toggleModifier(mod, val == true),
    );
  }

  void _toggleModifier(Modifier mod, bool selected) {
    setState(() {
      final group = _groups.where((g) => g.id == mod.groupId).firstOrNull;
      if (selected && group?.selectionMode == 'SINGLE') {
        _selectedIds.removeAll(widget.availableModifiers.where((m) => m.groupId == group!.id).map((m) => m.id));
      }
      if (selected) {
        _selectedIds.add(mod.id);
      } else {
        _selectedIds.remove(mod.id);
      }
      _error = null;
    });
  }

  void _handleApply() {
    final selected = widget.availableModifiers.where((m) => _selectedIds.contains(m.id)).toList();
    try {
      ModifierSelection.validate(selected, _groups);
      Navigator.of(context).pop(selected);
    } on StateError catch (error) {
      setState(() => _error = error.message);
    }
  }
}
