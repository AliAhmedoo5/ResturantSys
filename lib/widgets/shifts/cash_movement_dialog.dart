import 'package:flutter/material.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for recording mid-shift drawer cash Pay-Ins and Pay-Outs.
class CashMovementDialog extends StatefulWidget {
  const CashMovementDialog({
    super.key,
    required this.onRecordMovement,
  });

  final Future<void> Function(
    CashMovementType type,
    double amount,
    String category,
    String notes,
  ) onRecordMovement;

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  CashMovementType _selectedType = CashMovementType.payIn;
  String _selectedCategory = 'Petty Cash';
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<String> _categories = const [
    'Petty Cash',
    'Milk',
    'Ice',
    'Cash Drop',
    'Vendor Khata',
    'Supplies',
    'Other',
  ];

  String? _amountError;
  String? _notesError;
  String? _generalError;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amountText = _amountController.text.trim();
    final notesText = _notesController.text.trim();
    final amount = double.tryParse(amountText);

    bool hasError = false;
    setState(() {
      _amountError = null;
      _notesError = null;
      _generalError = null;
    });

    if (amount == null || amount <= 0) {
      setState(() {
        _amountError = 'Amount must be greater than zero.';
      });
      hasError = true;
    }

    if (notesText.isEmpty) {
      setState(() {
        _notesError = 'Note is mandatory for cash movement audit.';
      });
      hasError = true;
    }

    if (hasError) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.onRecordMovement(
        _selectedType,
        amount!,
        _selectedCategory,
        notesText,
      );
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generalError = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                  decoration: BoxDecoration(
                    color: _selectedType == CashMovementType.payIn
                        ? WarmCounterColors.lightActiveNavHighlight
                        : WarmCounterColors.lightDestructiveHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: Icon(
                    _selectedType == CashMovementType.payIn
                        ? Icons.add_circle_outline_rounded
                        : Icons.remove_circle_outline_rounded,
                    color: _selectedType == CashMovementType.payIn
                        ? WarmCounterColors.lightPrimaryAction
                        : WarmCounterColors.lightDestructiveAction,
                    size: 28,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record Cash Movement',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Audited mid-shift drawer Pay-In or Pay-Out',
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space32, color: WarmCounterColors.lightBorder),

            // Type Selector (Pay-In vs Pay-Out)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('movement_type_payin'),
                    onTap: () => setState(() => _selectedType = CashMovementType.payIn),
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _selectedType == CashMovementType.payIn
                            ? WarmCounterColors.lightActiveNavHighlight
                            : WarmCounterColors.lightPageBackground,
                        border: Border.all(
                          color: _selectedType == CashMovementType.payIn
                              ? WarmCounterColors.lightPrimaryAction
                              : WarmCounterColors.lightBorder,
                          width: _selectedType == CashMovementType.payIn ? 2 : 1,
                        ),
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Pay-In (+ Cash In)',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _selectedType == CashMovementType.payIn
                              ? WarmCounterColors.lightPrimaryAction
                              : WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: InkWell(
                    key: const ValueKey('movement_type_payout'),
                    onTap: () => setState(() => _selectedType = CashMovementType.payOut),
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: _selectedType == CashMovementType.payOut
                            ? WarmCounterColors.lightDestructiveHighlight
                            : WarmCounterColors.lightPageBackground,
                        border: Border.all(
                          color: _selectedType == CashMovementType.payOut
                              ? WarmCounterColors.lightDestructiveAction
                              : WarmCounterColors.lightBorder,
                          width: _selectedType == CashMovementType.payOut ? 2 : 1,
                        ),
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Pay-Out (- Cash Out)',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _selectedType == CashMovementType.payOut
                              ? WarmCounterColors.lightDestructiveAction
                              : WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: WarmCounterSpacing.space16),

            // Category Selector
            Text(
              'Movement Category',
              style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: WarmCounterSpacing.space8),
            DropdownButtonFormField<String>(
              key: const ValueKey('cash_movement_category_dropdown'),
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                filled: true,
                fillColor: WarmCounterColors.lightPageBackground,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  borderSide: BorderSide(color: WarmCounterColors.lightBorder),
                ),
              ),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            const SizedBox(height: WarmCounterSpacing.space16),

            // Amount Input
            Text(
              'Amount (Rs)',
              style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: WarmCounterSpacing.space8),
            TextField(
              key: const ValueKey('cash_movement_amount_input'),
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: WarmCounterTypography.tabularNumbers.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'Rs ',
                hintText: '0.00',
                errorText: _amountError,
                filled: true,
                fillColor: WarmCounterColors.lightPageBackground,
                border: const OutlineInputBorder(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  borderSide: BorderSide(color: WarmCounterColors.lightBorder),
                ),
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space16),

            // Mandatory Notes
            Text(
              'Mandatory Reason / Note',
              style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: WarmCounterSpacing.space8),
            TextField(
              key: const ValueKey('cash_movement_notes_input'),
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'e.g. Purchased 2 packs of milk from grocery / Change replenishment',
                errorText: _notesError,
                filled: true,
                fillColor: WarmCounterColors.lightPageBackground,
                border: const OutlineInputBorder(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  borderSide: BorderSide(color: WarmCounterColors.lightBorder),
                ),
              ),
            ),

            if (_generalError != null) ...[
              const SizedBox(height: WarmCounterSpacing.space12),
              Text(
                _generalError!,
                style: const TextStyle(color: WarmCounterColors.lightDestructiveAction, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],

            const SizedBox(height: WarmCounterSpacing.space24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('submit_cash_movement_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedType == CashMovementType.payIn
                          ? WarmCounterColors.lightPrimaryAction
                          : WarmCounterColors.lightDestructiveAction,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: Text(_isSubmitting
                        ? 'Recording...'
                        : (_selectedType == CashMovementType.payIn ? 'Record Pay-In' : 'Record Pay-Out')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
