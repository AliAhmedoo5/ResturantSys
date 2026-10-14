import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resturant_sys/core/khata/vendor.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for recording Vendor Khata settlements with multi-source payment routing
/// ('Paid from Active Drawer' vs 'Paid Outside Drawer').
class SettlementPaymentDialog extends StatefulWidget {
  const SettlementPaymentDialog({
    super.key,
    required this.vendor,
    this.activeShiftId,
    this.activeStaffName,
  });

  final Vendor vendor;
  final int? activeShiftId;
  final String? activeStaffName;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Vendor vendor,
    int? activeShiftId,
    String? activeStaffName,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SettlementPaymentDialog(
        vendor: vendor,
        activeShiftId: activeShiftId,
        activeStaffName: activeStaffName,
      ),
    );
  }

  @override
  State<SettlementPaymentDialog> createState() => _SettlementPaymentDialogState();
}

class _SettlementPaymentDialogState extends State<SettlementPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final _slipController = TextEditingController();
  final _notesController = TextEditingController();

  late VendorPaymentSource _paymentSource;

  bool get hasActiveShift => widget.activeShiftId != null;

  @override
  void initState() {
    super.initState();
    // Quick-fill with current outstanding payable if positive, otherwise empty
    _amountController = TextEditingController(
      text: widget.vendor.currentBalance > 0
          ? widget.vendor.currentBalance.toStringAsFixed(2)
          : '',
    );
    _paymentSource = hasActiveShift
        ? VendorPaymentSource.paidFromActiveDrawer
        : VendorPaymentSource.paidOutsideDrawer;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _slipController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text.trim());

    Navigator.of(context).pop({
      'amount': amount,
      'payment_source': _paymentSource,
      'reference_slip': _slipController.text.trim().isNotEmpty
          ? _slipController.text.trim()
          : null,
      'notes': _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: WarmCounterSpacing.panelBorderRadius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 520),
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
                        Icons.payments_rounded,
                        color: WarmCounterColors.lightPrimaryAction,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settle Supplier Balance',
                            style: WarmCounterTypography.pageHeading.copyWith(
                              fontSize: 20,
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

                // Current Payable Balance Card
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: BoxDecoration(
                    color: widget.vendor.hasOutstandingPayable
                        ? WarmCounterColors.lightWarning.withAlpha(20)
                        : WarmCounterColors.lightSurfaceMuted,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(
                      color: widget.vendor.hasOutstandingPayable
                          ? WarmCounterColors.lightWarning
                          : WarmCounterColors.lightBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Current Net Payable Due:',
                          style: WarmCounterTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        'Rs. ${widget.vendor.currentBalance.toStringAsFixed(2)}',
                        style: WarmCounterTypography.tableAmount.copyWith(
                          color: widget.vendor.hasOutstandingPayable
                              ? WarmCounterColors.lightWarning
                              : WarmCounterColors.lightPrimaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Payment Source Selection
                Text(
                  'Payment Source *',
                  style: WarmCounterTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),

                // Radio 1: Paid from Active Drawer
                Material(
                  color: _paymentSource == VendorPaymentSource.paidFromActiveDrawer
                      ? WarmCounterColors.lightPrimaryAction.withAlpha(10)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: _paymentSource == VendorPaymentSource.paidFromActiveDrawer
                          ? WarmCounterColors.lightPrimaryAction
                          : WarmCounterColors.lightBorder,
                    ),
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: RadioListTile<VendorPaymentSource>(
                    key: const Key('source_drawer_tile'),
                    value: VendorPaymentSource.paidFromActiveDrawer,
                    groupValue: _paymentSource,
                    title: const Text('Paid from Active Drawer'),
                    subtitle: Text(
                      hasActiveShift
                          ? 'Auto-logs Cash Pay-Out in Shift #${widget.activeShiftId} (${widget.activeStaffName ?? "Cashier"})'
                          : 'No shift open in cash drawer (Disabled)',
                      style: WarmCounterTypography.caption.copyWith(
                        color: hasActiveShift
                            ? WarmCounterColors.lightSecondaryText
                            : WarmCounterColors.lightDestructive,
                      ),
                    ),
                    activeColor: WarmCounterColors.lightPrimaryAction,
                    onChanged: hasActiveShift
                        ? (val) {
                            if (val != null) setState(() => _paymentSource = val);
                          }
                        : null,
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),

                // Radio 2: Paid Outside Drawer
                Material(
                  color: _paymentSource == VendorPaymentSource.paidOutsideDrawer
                      ? WarmCounterColors.lightPrimaryAction.withAlpha(10)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: _paymentSource == VendorPaymentSource.paidOutsideDrawer
                          ? WarmCounterColors.lightPrimaryAction
                          : WarmCounterColors.lightBorder,
                    ),
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: RadioListTile<VendorPaymentSource>(
                    key: const Key('source_external_tile'),
                    value: VendorPaymentSource.paidOutsideDrawer,
                    groupValue: _paymentSource,
                    title: const Text('Paid Outside Drawer'),
                    subtitle: const Text(
                      'Bank transfer, cheque, or owner personal pocket. Does not touch cash drawer float.',
                      style: WarmCounterTypography.caption,
                    ),
                    activeColor: WarmCounterColors.lightPrimaryAction,
                    onChanged: (val) {
                      if (val != null) setState(() => _paymentSource = val);
                    },
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Payment Amount
                TextFormField(
                  key: const Key('settlement_amount_field'),
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Settlement Amount (PKR) *',
                    hintText: 'e.g. 5000.00',
                    prefixIcon: Icon(Icons.currency_rupee_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter payment amount';
                    }
                    final val = double.tryParse(value);
                    if (val == null || val <= 0) {
                      return 'Amount must be greater than zero';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Reference / Slip
                TextFormField(
                  key: const Key('settlement_slip_field'),
                  controller: _slipController,
                  decoration: InputDecoration(
                    labelText: _paymentSource == VendorPaymentSource.paidFromActiveDrawer
                        ? 'Payment Receipt / Voucher # (Optional)'
                        : 'Bank Reference / Cheque # / Transfer ID',
                    hintText: 'e.g. TXN-8902 or CHQ-00129',
                    prefixIcon: const Icon(Icons.tag_rounded),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Notes
                TextFormField(
                  key: const Key('settlement_notes_field'),
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes / Description (Optional)',
                    hintText: 'e.g. Cleared pending invoice for potato delivery',
                    prefixIcon: Icon(Icons.note_alt_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space24),

                // Actions
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
                      key: const Key('confirm_settlement_button'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                        foregroundColor: WarmCounterColors.lightTextOnPrimary,
                        minimumSize: const Size(160, 48),
                      ),
                      onPressed: _submit,
                      child: const Text('Record Payment'),
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
