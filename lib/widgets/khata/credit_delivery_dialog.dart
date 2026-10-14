import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/khata/vendor.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for logging incoming stock shipments on credit,
/// recording delivery slip references and incrementing the vendor's payable balance.
class CreditDeliveryDialog extends StatefulWidget {
  const CreditDeliveryDialog({
    super.key,
    required this.vendor,
    this.rawIngredients = const [],
  });

  final Vendor vendor;
  final List<RawIngredient> rawIngredients;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Vendor vendor,
    List<RawIngredient> rawIngredients = const [],
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreditDeliveryDialog(
        vendor: vendor,
        rawIngredients: rawIngredients,
      ),
    );
  }

  @override
  State<CreditDeliveryDialog> createState() => _CreditDeliveryDialogState();
}

class _CreditDeliveryDialogState extends State<CreditDeliveryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _slipController = TextEditingController();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  int? _selectedIngredientId;

  @override
  void dispose() {
    _amountController.dispose();
    _slipController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());
    final quantity = _quantityController.text.trim().isNotEmpty
        ? double.tryParse(_quantityController.text.trim())
        : null;

    Navigator.of(context).pop({
      'amount': amount,
      'reference_slip': _slipController.text.trim().isNotEmpty
          ? _slipController.text.trim()
          : null,
      'raw_ingredient_id': _selectedIngredientId,
      'quantity': quantity,
      'notes': _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: WarmCounterSpacing.panelBorderRadius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
                        color: WarmCounterColors.lightAmber.withAlpha(30),
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                      ),
                      child: const Icon(
                        Icons.local_shipping_rounded,
                        color: WarmCounterColors.lightAmber,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Log Credit Delivery',
                            style: WarmCounterTypography.sectionHeading.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            widget.vendor.name,
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
                const SizedBox(height: WarmCounterSpacing.space16),

                // Notice Banner
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightSurface,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: WarmCounterColors.lightSecondaryText,
                        size: 20,
                      ),
                      const SizedBox(width: WarmCounterSpacing.space8),
                      Expanded(
                        child: Text(
                          'Current Balance: Rs. ${widget.vendor.currentBalance.toStringAsFixed(2)} payable. '
                          'This delivery will be added to the credit ledger without immediate cash outflow.',
                          style: WarmCounterTypography.captionText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Amount
                TextFormField(
                  key: const Key('credit_amount_field'),
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Total Delivery Amount (PKR) *',
                    hintText: 'e.g. 15000.00',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter delivery amount';
                    }
                    final val = double.tryParse(value);
                    if (val == null || val <= 0) {
                      return 'Amount must be greater than zero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Delivery Slip Number
                TextFormField(
                  key: const Key('credit_slip_field'),
                  controller: _slipController,
                  decoration: const InputDecoration(
                    labelText: 'Delivery Slip / Bilty / Invoice #',
                    hintText: 'e.g. DS-4091',
                    prefixIcon: Icon(Icons.receipt_long_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Optional Linked Raw Ingredient
                if (widget.rawIngredients.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    key: const Key('credit_ingredient_dropdown'),
                    value: _selectedIngredientId,
                    decoration: const InputDecoration(
                      labelText: 'Linked Stock Ingredient (Optional)',
                      prefixIcon: Icon(Icons.egg_alt_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('None (General Shipment)'),
                      ),
                      ...widget.rawIngredients.map((i) => DropdownMenuItem<int?>(
                            value: i.id,
                            child: Text('${i.name} (${i.storageUnit})'),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedIngredientId = val);
                    },
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  if (_selectedIngredientId != null) ...[
                    TextFormField(
                      key: const Key('credit_quantity_field'),
                      controller: _quantityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Received Stock Quantity *',
                        hintText: 'e.g. 50',
                        prefixIcon: Icon(Icons.scale_rounded),
                        border: OutlineInputBorder(),
                        helperText: 'Will automatically increment inventory stock balance',
                      ),
                      validator: (value) {
                        if (_selectedIngredientId != null) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter received stock quantity';
                          }
                          final val = double.tryParse(value);
                          if (val == null || val <= 0) {
                            return 'Quantity must be greater than zero';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: WarmCounterSpacing.space16),
                  ],
                ],

                // Notes
                TextFormField(
                  key: const Key('credit_notes_field'),
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Remarks (Optional)',
                    hintText: 'e.g. 2 crates received at back gate',
                    prefixIcon: Icon(Icons.note_alt_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space24),

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
                      key: const Key('confirm_credit_delivery_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                        foregroundColor: WarmCounterColors.lightTextOnPrimary,
                        minimumSize: const Size(160, 48),
                      ),
                      onPressed: _submit,
                      child: const Text('Log Delivery'),
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
