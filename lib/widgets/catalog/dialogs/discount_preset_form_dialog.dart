import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for creating or updating a Pre-Approved Discount Preset.
class DiscountPresetFormDialog extends StatefulWidget {
  const DiscountPresetFormDialog({
    super.key,
    this.preset,
    required this.onSave,
  });

  final DiscountPreset? preset;
  final Future<void> Function({
    required String name,
    required DiscountType type,
    required double value,
    required bool isActive,
  }) onSave;

  @override
  State<DiscountPresetFormDialog> createState() => _DiscountPresetFormDialogState();
}

class _DiscountPresetFormDialogState extends State<DiscountPresetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late DiscountType _selectedType;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset?.name ?? '');
    _valueController = TextEditingController(
      text: widget.preset != null ? widget.preset!.value.toString() : '10.0',
    );
    _selectedType = widget.preset?.type ?? DiscountType.percentage;
    _isActive = widget.preset?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final value = double.tryParse(_valueController.text.trim()) ?? 0.0;

      await widget.onSave(
        name: name,
        type: _selectedType,
        value: value,
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
    final isEditing = widget.preset != null;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Text(isEditing ? 'Edit Discount Preset' : 'Add Discount Preset', style: WarmCounterTypography.pageHeading),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('discount_name_field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Discount Name',
                  hintText: 'e.g. Staff Meal 20%, Owner Courtesy 100%, Promo Rs 100',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter discount name';
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              DropdownButtonFormField<DiscountType>(
                key: const ValueKey('discount_type_dropdown'),
                initialValue: _selectedType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Discount Calculation Type'),
                items: DiscountType.values.map((t) {
                  return DropdownMenuItem<DiscountType>(
                    value: t,
                    child: Text(t.displayName),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedType = val);
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              TextFormField(
                key: const ValueKey('discount_value_field'),
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _selectedType == DiscountType.percentage ? 'Percentage Value (%)' : 'Flat Amount (Rs)',
                  suffixText: _selectedType == DiscountType.percentage ? '%' : 'Rs',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter discount value';
                  final num = double.tryParse(val.trim());
                  if (num == null || num <= 0) return 'Must be a positive value';
                  if (_selectedType == DiscountType.percentage && num > 100) {
                    return 'Percentage cannot exceed 100%';
                  }
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active for Cashiers'),
                subtitle: const Text('Enables 1-tap selection on counter register without supervisor PIN'),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const ValueKey('save_discount_button'),
          onPressed: _isSaving ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightPrimaryAction,
            foregroundColor: WarmCounterColors.lightTextOnPrimary,
          ),
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEditing ? 'Save Changes' : 'Create Preset'),
        ),
      ],
    );
  }
}
