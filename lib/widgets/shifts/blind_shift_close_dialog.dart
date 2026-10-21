import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for blind shift-close cash handover.
///
/// Intentionally conceals expected system cash, sales, and transaction totals
/// to prevent cashier count biasing and ensure strict physical drawer integrity.
class BlindShiftCloseDialog extends StatefulWidget {
  const BlindShiftCloseDialog({
    super.key,
    required this.shiftId,
    required this.cashierName,
    required this.onSubmitBlindCount,
  });

  final int shiftId;
  final String cashierName;
  final Future<void> Function(double countedCash) onSubmitBlindCount;

  @override
  State<BlindShiftCloseDialog> createState() => _BlindShiftCloseDialogState();
}

class _BlindShiftCloseDialogState extends State<BlindShiftCloseDialog> {
  bool _useDenominationCounter = false;
  final TextEditingController _directCountController = TextEditingController();

  // Denomination note counters
  final Map<int, int> _denominations = {
    5000: 0,
    1000: 0,
    500: 0,
    100: 0,
    50: 0,
    20: 0,
    10: 0,
  };
  final TextEditingController _looseCoinsController = TextEditingController();

  String? _errorMessage;
  bool _isSubmitting = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void dispose() {
    _directCountController.dispose();
    _looseCoinsController.dispose();
    super.dispose();
  }

  double _computeTotal() {
    if (!_useDenominationCounter) {
      final parsed = double.tryParse(_directCountController.text.trim());
      return parsed ?? 0.0;
    }

    double sum = 0.0;
    _denominations.forEach((denom, count) {
      sum += denom * count;
    });

    final coins = double.tryParse(_looseCoinsController.text.trim()) ?? 0.0;
    return sum + coins;
  }

  Future<void> _submit() async {
    if (!_useDenominationCounter) {
      final text = _directCountController.text.trim();
      if (text.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter physical counted cash amount.';
        });
        return;
      }
      final parsed = double.tryParse(text);
      if (parsed == null || parsed < 0) {
        setState(() {
          _errorMessage = 'Physical counted cash cannot be negative.';
        });
        return;
      }
    } else {
      final coinsText = _looseCoinsController.text.trim();
      if (coinsText.isNotEmpty) {
        final coins = double.tryParse(coinsText);
        if (coins == null || coins < 0) {
          setState(() {
            _errorMessage = 'Loose coins amount cannot be negative.';
          });
          return;
        }
      }
    }

    final total = _computeTotal();

    if (total < 0) {
      setState(() {
        _errorMessage = 'Physical counted cash cannot be negative.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    try {
      await widget.onSubmitBlindCount(total);
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTotal = _computeTotal();

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                  decoration: const BoxDecoration(
                    color: WarmCounterColors.lightActiveNavHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: WarmCounterColors.lightPrimaryAction,
                    size: 28,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Blind Shift Handover (Shift #${widget.shiftId})',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Cashier: ${widget.cashierName} • Blind Physical Drawer Count',
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

            // Mode Selector: Direct Total vs Denomination Note Counter
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Direct Cash Total'),
                    selected: !_useDenominationCounter,
                    onSelected: (val) {
                      if (val) setState(() => _useDenominationCounter = false);
                    },
                    selectedColor: WarmCounterColors.lightActiveNavHighlight,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Currency Note Breakdown'),
                    selected: _useDenominationCounter,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _useDenominationCounter = true;
                          _directCountController.clear();
                        });
                      }
                    },
                    selectedColor: WarmCounterColors.lightActiveNavHighlight,
                  ),
                ),
              ],
            ),
            const SizedBox(height: WarmCounterSpacing.space16),

            // Content Area
            Expanded(
              child: SingleChildScrollView(
                child: _useDenominationCounter
                    ? _buildDenominationList()
                    : _buildDirectCountInput(),
              ),
            ),

            const SizedBox(height: WarmCounterSpacing.space16),

            // Total Counted Banner (Blind - Only shows what the cashier counted)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: WarmCounterSpacing.space16,
                vertical: WarmCounterSpacing.space12,
              ),
              decoration: BoxDecoration(
                color: WarmCounterColors.lightSurfaceMuted,
                borderRadius: WarmCounterSpacing.controlBorderRadius,
                border: Border.all(color: WarmCounterColors.lightBorder),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Total Physical Counted:',
                    style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Rs ${_currencyFormat.format(currentTotal)}',
                    style: WarmCounterTypography.tabularNumbers.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: WarmCounterColors.lightPrimaryAction,
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: WarmCounterSpacing.space8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: WarmCounterColors.lightDestructiveAction, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],

            const SizedBox(height: WarmCounterSpacing.space16),

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
                    key: const ValueKey('submit_blind_close_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: Text(_isSubmitting ? 'Closing Shift...' : 'Submit Blind Count & Close'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectCountInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Counted Cash in Drawer (Rs)',
          style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: WarmCounterSpacing.space8),
        TextField(
          key: const ValueKey('direct_counted_cash_input'),
          controller: _directCountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: WarmCounterTypography.tabularNumbers.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixText: 'Rs ',
            hintText: '0.00',
            filled: true,
            fillColor: WarmCounterColors.lightPageBackground,
            border: OutlineInputBorder(
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              borderSide: BorderSide(color: WarmCounterColors.lightBorder),
            ),
          ),
        ),
        const SizedBox(height: WarmCounterSpacing.space12),
        Text(
          'Count physical cash and coins inside the drawer and enter the sum. System totals are hidden.',
          style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
        ),
      ],
    );
  }

  Widget _buildDenominationList() {
    return Column(
      children: [
        ..._denominations.keys.map((denom) {
          final count = _denominations[denom] ?? 0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 90,
                  child: Text(
                    'Rs $denom',
                    style: WarmCounterTypography.tabularNumbers.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: count > 0 ? () => setState(() => _denominations[denom] = count - 1) : null,
                ),
                SizedBox(
                  width: 50,
                  child: Center(
                    child: Text(
                      '$count',
                      style: WarmCounterTypography.tabularNumbers.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _denominations[denom] = count + 1),
                ),
                const Spacer(),
                Text(
                  'Rs ${_currencyFormat.format(denom * count)}',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    color: WarmCounterColors.lightSecondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(color: WarmCounterColors.lightBorder),
        Row(
          children: [
            const SizedBox(
              width: 140,
              child: Text('Loose Coins / Cash:', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: TextField(
                controller: _looseCoinsController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixText: 'Rs ',
                  hintText: '0.00',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
