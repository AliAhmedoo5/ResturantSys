import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resturant_sys/core/khata/vendor.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for creating or updating a supplier in the directory.
class VendorFormDialog extends StatefulWidget {
  const VendorFormDialog({
    super.key,
    this.vendor,
  });

  final Vendor? vendor;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    Vendor? vendor,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => VendorFormDialog(vendor: vendor),
    );
  }

  @override
  State<VendorFormDialog> createState() => _VendorFormDialogState();
}

class _VendorFormDialogState extends State<VendorFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _ingredientsController;
  late final TextEditingController _openingBalanceController;

  bool get isEditing => widget.vendor != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.vendor?.name ?? '');
    _phoneController = TextEditingController(text: widget.vendor?.phone ?? '');
    _ingredientsController =
        TextEditingController(text: widget.vendor?.suppliedIngredients ?? '');
    _openingBalanceController = TextEditingController(
      text: widget.vendor != null
          ? widget.vendor!.openingBalance.toStringAsFixed(2)
          : '0.00',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _ingredientsController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final openingBalance = double.tryParse(_openingBalanceController.text) ?? 0.0;

    Navigator.of(context).pop({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'supplied_ingredients': _ingredientsController.text.trim().isEmpty
          ? null
          : _ingredientsController.text.trim(),
      'opening_balance': openingBalance,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: WarmCounterSpacing.panelBorderRadius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(WarmCounterSpacing.space24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                      decoration: BoxDecoration(
                        color: WarmCounterColors.lightPrimaryAction.withAlpha(25),
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                      ),
                      child: const Icon(
                        Icons.store_mall_directory_rounded,
                        color: WarmCounterColors.lightPrimaryAction,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space12),
                    Expanded(
                      child: Text(
                        isEditing ? 'Edit Supplier' : 'New Supplier (Vendor)',
                        style: WarmCounterTypography.sectionHeading.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Vendor Name
                TextFormField(
                  key: const Key('vendor_name_field'),
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier / Vendor Name *',
                    hintText: 'e.g. Al-Madina Poultry',
                    prefixIcon: Icon(Icons.business_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter vendor name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Phone Number
                TextFormField(
                  key: const Key('vendor_phone_field'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number *',
                    hintText: 'e.g. 03001234567',
                    prefixIcon: Icon(Icons.phone_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Supplied Ingredients
                TextFormField(
                  key: const Key('vendor_ingredients_field'),
                  controller: _ingredientsController,
                  decoration: const InputDecoration(
                    labelText: 'Supplied Raw Ingredients (Optional)',
                    hintText: 'e.g. Chicken Breast, Wings, Cheese',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Opening Balance (Only on create)
                if (!isEditing) ...[
                  TextFormField(
                    key: const Key('vendor_opening_balance_field'),
                    controller: _openingBalanceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Opening Payable Balance (PKR)',
                      hintText: '0.00',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      border: OutlineInputBorder(),
                      helperText: 'Initial amount owed to supplier, if any',
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final val = double.tryParse(value);
                        if (val == null || val < 0) {
                          return 'Enter a valid non-negative number';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: WarmCounterSpacing.space24),
                ] else ...[
                  const SizedBox(height: WarmCounterSpacing.space8),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(100, 48),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space12),
                    ElevatedButton(
                      key: const Key('save_vendor_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                        foregroundColor: WarmCounterColors.lightTextOnPrimary,
                        minimumSize: const Size(140, 48),
                      ),
                      onPressed: _submit,
                      child: Text(isEditing ? 'Save Changes' : 'Add Supplier'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
