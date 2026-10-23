import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_media_service.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import '../../../core/catalog/catalog_photo_change.dart';
import '../catalog_photo_field.dart';

/// Modal dialog for creating or updating a Menu Item with tax-inclusive pricing.
class MenuItemFormDialog extends StatefulWidget {
  const MenuItemFormDialog({
    super.key,
    this.item,
    required this.categories,
    required this.onSave,
    this.mediaService,
    this.currentStaff,
  });

  final MenuItem? item;
  final List<MenuCategory> categories;
  final CatalogMediaService? mediaService;
  final Staff? currentStaff;
  final Future<void> Function({
    required int categoryId,
    required String name,
    required double basePrice,
    required double taxRate,
    required bool isTaxInclusive,
    required bool isActive,
    required CatalogPhotoChange? photoChange,
  }) onSave;

  @override
  State<MenuItemFormDialog> createState() => _MenuItemFormDialogState();
}

class _MenuItemFormDialogState extends State<MenuItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _taxRateController;
  late int? _selectedCategoryId;
  late bool _isTaxInclusive;
  late bool _isActive;
  bool _isSaving = false;
  bool _photoBusy = false;
  CatalogPhotoChange? _photoChange;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _priceController = TextEditingController(
      text: widget.item != null ? widget.item!.basePrice.toStringAsFixed(2) : '',
    );
    _taxRateController = TextEditingController(
      text: widget.item != null ? widget.item!.taxRate.toStringAsFixed(2) : '16.00',
    );
    _selectedCategoryId = widget.item?.categoryId ??
        (widget.categories.isNotEmpty ? widget.categories.first.id : null);
    _isTaxInclusive = widget.item?.isTaxInclusive ?? true;
    _isActive = widget.item?.isActive ?? false;
    _photoBusy = widget.item != null && widget.mediaService != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  double get _currentPrice => double.tryParse(_priceController.text.trim()) ?? 0.0;
  double get _currentTaxRate => double.tryParse(_taxRateController.text.trim()) ?? 0.0;

  double get _calculatedNet {
    if (_currentTaxRate <= 0) return _currentPrice;
    if (_isTaxInclusive) {
      return _currentPrice / (1.0 + (_currentTaxRate / 100.0));
    }
    return _currentPrice;
  }

  double get _calculatedTax {
    if (_currentTaxRate <= 0) return 0.0;
    if (_isTaxInclusive) {
      return _currentPrice - _calculatedNet;
    }
    return _currentPrice * (_currentTaxRate / 100.0);
  }

  Future<void> _handleSubmit() async {
    if (_photoBusy || _isSaving || !_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.onSave(
        categoryId: _selectedCategoryId!,
        name: _nameController.text.trim(),
        basePrice: _currentPrice,
        taxRate: _currentTaxRate,
        isTaxInclusive: _isTaxInclusive,
        isActive: _isActive,
        photoChange: _photoChange,
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
    final isEditing = widget.item != null;

    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
        title: Text(isEditing ? 'Edit Menu Item' : 'Add Menu Item', style: WarmCounterTypography.pageHeading),
        content: SizedBox(
          width: 500,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.mediaService != null) ...[
                    CatalogPhotoField(
                      mediaService: widget.mediaService,
                      entityType: 'menu_item',
                      entityId: widget.item?.id,
                      enabled: !_isSaving,
                      onChanged: (change) => _photoChange = change,
                      onBusyChanged: (busy) { if (mounted) setState(() => _photoBusy = busy); },
                    ),
                    const SizedBox(height: WarmCounterSpacing.space16),
                  ],
                  DropdownButtonFormField<int>(
                    key: const ValueKey('menu_item_category_dropdown'),
                    initialValue: _selectedCategoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: widget.categories.map((c) {
                      return DropdownMenuItem<int>(
                        value: c.id,
                        child: Text(c.name),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedCategoryId = val),
                    validator: (val) => val == null ? 'Please select category' : null,
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),
                  TextFormField(
                    key: const ValueKey('menu_item_name_field'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Item Name',
                      hintText: 'e.g. Zinger Burger, Fries, Mint Lemonade',
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Enter item name';
                      return null;
                    },
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('menu_item_price_field'),
                          controller: _priceController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Retail Price (Rs)',
                            hintText: 'e.g. 550.00',
                            prefixText: 'Rs ',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Enter price';
                            final num = double.tryParse(val.trim());
                            if (num == null || num < 0) return 'Invalid price';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space16),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('menu_item_tax_rate_field'),
                          controller: _taxRateController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Tax Rate (%)',
                            hintText: 'e.g. 16.0',
                            suffixText: '%',
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) return 'Enter tax rate';
                            final num = double.tryParse(val.trim());
                            if (num == null || num < 0) return 'Invalid rate';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  // Tax breakdown card
                  Container(
                    padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                    decoration: BoxDecoration(
                      color: WarmCounterColors.lightSurfaceMuted,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                      border: Border.all(color: WarmCounterColors.lightBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Net Base', style: WarmCounterTypography.caption),
                            Text(
                              'Rs ${_currencyFormat.format(_calculatedNet)}',
                              style: WarmCounterTypography.tabularNumbers.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tax Portion', style: WarmCounterTypography.caption),
                            Text(
                              'Rs ${_currencyFormat.format(_calculatedTax)}',
                              style: WarmCounterTypography.tabularNumbers.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Retail Price', style: WarmCounterTypography.caption),
                            Text(
                              'Rs ${_currencyFormat.format(_isTaxInclusive ? _currentPrice : _currentPrice + _calculatedTax)}',
                              style: WarmCounterTypography.tabularNumbers.copyWith(
                                fontWeight: FontWeight.bold,
                                color: WarmCounterColors.lightPrimaryAction,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  // Toggles
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tax-Inclusive Price'),
                    subtitle: const Text('Customer price includes sales tax (back-calculated for receipts)'),
                    value: _isTaxInclusive,
                    onChanged: (val) => setState(() => _isTaxInclusive = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active for Billing'),
                    subtitle: const Text('Visible on counter cashier touch grid and hotkey shortcuts'),
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
            key: const ValueKey('save_menu_item_button'),
            onPressed: _isSaving || _photoBusy ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: WarmCounterColors.lightPrimaryAction,
              foregroundColor: WarmCounterColors.lightTextOnPrimary,
            ),
            child: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isEditing ? 'Save Changes' : 'Create Menu Item'),
          ),
        ],
      ),
    );
  }
}
