import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for creating or updating a Menu Category.
class CategoryFormDialog extends StatefulWidget {
  const CategoryFormDialog({
    super.key,
    this.category,
    required this.onSave,
  });

  final MenuCategory? category;
  final Future<void> Function({
    required String name,
    required int displayOrder,
    required String colorHex,
  }) onSave;

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _orderController;
  late String _selectedColorHex;
  bool _isSaving = false;

  static const List<String> _palette = [
    '#E53935', // Red
    '#FB8C00', // Orange
    '#FDD835', // Yellow
    '#2E7D32', // Green
    '#00897B', // Teal
    '#1E88E5', // Blue
    '#5E35B1', // Deep Purple
    '#8E24AA', // Purple
    '#6D4C41', // Brown
    '#546E7A', // Slate
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _orderController = TextEditingController(
      text: (widget.category?.displayOrder ?? 0).toString(),
    );
    _selectedColorHex = widget.category?.colorHex ?? _palette[3];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final name = _nameController.text.trim();
      final order = int.tryParse(_orderController.text.trim()) ?? 0;
      await widget.onSave(
        name: name,
        displayOrder: order,
        colorHex: _selectedColorHex,
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
    final isEditing = widget.category != null;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Text(isEditing ? 'Edit Category' : 'Add Menu Category', style: WarmCounterTypography.pageHeading),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                key: const ValueKey('category_name_field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Category Name',
                  hintText: 'e.g. Burgers, Beverages, Combos',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter category name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              TextFormField(
                key: const ValueKey('category_order_field'),
                controller: _orderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Display Order',
                  hintText: 'e.g. 1, 2, 3',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter display order';
                  if (int.tryParse(val.trim()) == null) return 'Must be a valid integer';
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              const Text('Tile Color Coding', style: WarmCounterTypography.secondaryLabel),
              const SizedBox(height: WarmCounterSpacing.space8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _palette.map((hex) {
                  final color = WarmCounterColors.parseHex(hex);
                  final isSelected = _selectedColorHex.toUpperCase() == hex.toUpperCase();
                  return InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    onTap: () => setState(() => _selectedColorHex = hex),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      constraints: WarmCounterSpacing.minTouchTargetConstraints,
                      alignment: Alignment.center,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.black : Colors.transparent,
                            width: isSelected ? 3.0 : 1.0,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 20, color: Colors.white)
                            : null,
                      ),
                    ),
                  );
                }).toList(),
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
          key: const ValueKey('save_category_button'),
          onPressed: _isSaving ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightPrimaryAction,
            foregroundColor: WarmCounterColors.lightTextOnPrimary,
          ),
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEditing ? 'Save Changes' : 'Create Category'),
        ),
      ],
    );
  }
}
