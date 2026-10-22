import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for creating or updating a Raw Ingredient in inventory.
class RawIngredientFormDialog extends StatefulWidget {
  const RawIngredientFormDialog({
    super.key,
    this.ingredient,
    required this.onSave,
  });

  final RawIngredient? ingredient;
  final Future<void> Function({
    required String name,
    required StorageUnit storageUnit,
    required double currentStock,
    required double lowStockThreshold,
    required double costPerRecipeUnit,
  }) onSave;

  @override
  State<RawIngredientFormDialog> createState() => _RawIngredientFormDialogState();
}

class _RawIngredientFormDialogState extends State<RawIngredientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _stockController;
  late final TextEditingController _thresholdController;
  late final TextEditingController _costController;
  late StorageUnit _selectedUnit;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.ingredient?.name ?? '');
    _stockController = TextEditingController(
      text: widget.ingredient != null ? widget.ingredient!.currentStock.toString() : '0',
    );
    _thresholdController = TextEditingController(
      text: widget.ingredient != null ? widget.ingredient!.lowStockThreshold.toString() : '0',
    );
    _costController = TextEditingController(
      text: widget.ingredient != null ? widget.ingredient!.costPerRecipeUnit.toString() : '0.00',
    );
    _selectedUnit = widget.ingredient?.storageUnit ?? StorageUnit.count;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _stockController.dispose();
    _thresholdController.dispose();
    _costController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final stock = double.tryParse(_stockController.text.trim()) ?? 0.0;
      final threshold = double.tryParse(_thresholdController.text.trim()) ?? 0.0;
      final cost = double.tryParse(_costController.text.trim()) ?? 0.0;

      await widget.onSave(
        name: name,
        storageUnit: _selectedUnit,
        currentStock: stock,
        lowStockThreshold: threshold,
        costPerRecipeUnit: cost,
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
    final isEditing = widget.ingredient != null;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Text(isEditing ? 'Edit Raw Ingredient' : 'Add Raw Ingredient', style: WarmCounterTypography.pageHeading),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('ingredient_name_field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Ingredient Name',
                    hintText: 'e.g. Beef Patty 150g, Burger Bun, Regular Mayo',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter ingredient name';
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                DropdownButtonFormField<StorageUnit>(
                  key: const ValueKey('ingredient_unit_dropdown'),
                  initialValue: _selectedUnit,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Base Storage Unit'),
                  items: StorageUnit.values.map((u) {
                    return DropdownMenuItem<StorageUnit>(
                      value: u,
                      child: Text(u.displayName),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedUnit = val);
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('ingredient_stock_field'),
                        controller: _stockController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Current Stock',
                          suffixText: _selectedUnit.code,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter current stock';
                          final num = double.tryParse(val.trim());
                          if (num == null) return 'Invalid number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space16),
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('ingredient_threshold_field'),
                        controller: _thresholdController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Low-Stock Alert',
                          suffixText: _selectedUnit.code,
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Enter threshold';
                          final num = double.tryParse(val.trim());
                          if (num == null || num < 0) return 'Invalid threshold';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                TextFormField(
                  key: const ValueKey('ingredient_cost_field'),
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Cost Per Unit (Rs)',
                    prefixText: 'Rs ',
                    suffixText: 'per ${_selectedUnit.code}',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Enter unit cost';
                    final num = double.tryParse(val.trim());
                    if (num == null || num < 0) return 'Invalid cost';
                    return null;
                  },
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
          key: const ValueKey('save_ingredient_button'),
          onPressed: _isSaving ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightPrimaryAction,
            foregroundColor: WarmCounterColors.lightTextOnPrimary,
          ),
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEditing ? 'Save Changes' : 'Create Ingredient'),
        ),
      ],
    );
  }
}
