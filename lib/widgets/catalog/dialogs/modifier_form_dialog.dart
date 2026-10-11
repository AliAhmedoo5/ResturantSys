import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for creating or updating a Menu Item Modifier.
class ModifierFormDialog extends StatefulWidget {
  const ModifierFormDialog({
    super.key,
    this.modifier,
    required this.menuItems,
    required this.rawIngredients,
    required this.onSave,
  });

  final Modifier? modifier;
  final List<MenuItem> menuItems;
  final List<RawIngredient> rawIngredients;
  final Future<void> Function({
    int? menuItemId,
    required String name,
    required double priceDelta,
    int? rawIngredientId,
    required double ingredientQtyDelta,
    required bool isActive,
  }) onSave;

  @override
  State<ModifierFormDialog> createState() => _ModifierFormDialogState();
}

class _ModifierFormDialogState extends State<ModifierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceDeltaController;
  late final TextEditingController _qtyDeltaController;
  late int? _selectedMenuItemId;
  late int? _selectedRawIngredientId;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.modifier?.name ?? '');
    _priceDeltaController = TextEditingController(
      text: widget.modifier != null ? widget.modifier!.priceDelta.toString() : '0.0',
    );
    _qtyDeltaController = TextEditingController(
      text: widget.modifier != null ? widget.modifier!.ingredientQtyDelta.toString() : '0.0',
    );
    _selectedMenuItemId = widget.modifier?.menuItemId;
    _selectedRawIngredientId = widget.modifier?.rawIngredientId;
    _isActive = widget.modifier?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceDeltaController.dispose();
    _qtyDeltaController.dispose();
    super.dispose();
  }

  RawIngredient? get _selectedIngredient {
    if (_selectedRawIngredientId == null) return null;
    try {
      return widget.rawIngredients.firstWhere((i) => i.id == _selectedRawIngredientId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final priceDelta = double.tryParse(_priceDeltaController.text.trim()) ?? 0.0;
      final qtyDelta = double.tryParse(_qtyDeltaController.text.trim()) ?? 0.0;

      await widget.onSave(
        menuItemId: _selectedMenuItemId,
        name: name,
        priceDelta: priceDelta,
        rawIngredientId: _selectedRawIngredientId,
        ingredientQtyDelta: qtyDelta,
        isActive: _isActive,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.modifier != null;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Text(isEditing ? 'Edit Modifier' : 'Add Modifier', style: WarmCounterTypography.pageHeading),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<int?>(
                  key: const ValueKey('modifier_item_dropdown'),
                  initialValue: _selectedMenuItemId,
                  decoration: const InputDecoration(
                    labelText: 'Target Menu Item (Optional)',
                    hintText: 'Leave empty for global modifier',
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('All Menu Items (Global)'),
                    ),
                    ...widget.menuItems.map((m) {
                      return DropdownMenuItem<int?>(
                        value: m.id,
                        child: Text(m.name),
                      );
                    }),
                  ],
                  onChanged: (val) => setState(() => _selectedMenuItemId = val),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                TextFormField(
                  key: const ValueKey('modifier_name_field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Modifier Name',
                    hintText: 'e.g. +Extra Cheese, No Mayo, Extra Patty',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter modifier name';
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('modifier_price_delta_field'),
                        controller: _priceDeltaController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: const InputDecoration(
                          labelText: 'Price Delta (Rs)',
                          hintText: 'e.g. +80, 0, -20',
                          prefixText: 'Rs ',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter price delta';
                          if (double.tryParse(val.trim()) == null) return 'Invalid number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space16),
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        key: const ValueKey('modifier_ingredient_dropdown'),
                        initialValue: _selectedRawIngredientId,
                        decoration: const InputDecoration(labelText: 'Raw Ingredient (BOM)'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('None (Price Only)'),
                          ),
                          ...widget.rawIngredients.map((i) {
                            return DropdownMenuItem<int?>(
                              value: i.id,
                              child: Text('${i.name} (${i.storageUnit.code})'),
                            );
                          }),
                        ],
                        onChanged: (val) => setState(() => _selectedRawIngredientId = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                TextFormField(
                  key: const ValueKey('modifier_qty_delta_field'),
                  controller: _qtyDeltaController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(
                    labelText: 'Ingredient Quantity Delta',
                    hintText: 'e.g. +1, 0, -20',
                    suffixText: _selectedIngredient?.storageUnit.code ?? '',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter quantity delta';
                    if (double.tryParse(val.trim()) == null) return 'Invalid number';
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active for Billing'),
                  subtitle: const Text('Available for counter selection during checkout'),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const ValueKey('save_modifier_button'),
          onPressed: _isSaving ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightPrimaryAction,
            foregroundColor: Colors.white,
          ),
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEditing ? 'Save Changes' : 'Create Modifier'),
        ),
      ],
    );
  }
}
