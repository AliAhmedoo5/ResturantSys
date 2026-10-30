import '../../core/orders/paisa_engine.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/orders/payment_method.dart';
import '../../core/theme/theme.dart';

/// Modal dialog handling tender selection (Cash, Card, Raast QR, Split Tender)
/// and high-contrast return change calculations.
class TenderCheckoutDialog extends StatefulWidget {
  const TenderCheckoutDialog({
    super.key,
    required this.grandTotal,
    required this.onCompleteCheckout,
    this.roundPhysicalCash = true,
    this.allowCod = false,
  });

  final double grandTotal;
  final bool roundPhysicalCash;
  final bool allowCod;
  final Future<void> Function(List<PaymentTender> tenders) onCompleteCheckout;

  @override
  State<TenderCheckoutDialog> createState() => _TenderCheckoutDialogState();
}

class _TenderCheckoutDialogState extends State<TenderCheckoutDialog> {
  PaymentMethod _selectedMethod = PaymentMethod.cash;

  // Controllers
  final TextEditingController _cashTenderController = TextEditingController();
  final TextEditingController _splitCashController = TextEditingController();
  final TextEditingController _splitElectronicController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();

  PaymentMethod _splitElectronicMethod = PaymentMethod.raast;
  bool _isCommitting = false;
  String? _errorMessage;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _cashTenderController.text = _cashDue.toStringAsFixed(0);
    _splitCashController.text = (widget.grandTotal / 2).toStringAsFixed(0);
    _splitElectronicController.text = (widget.grandTotal - (widget.grandTotal / 2)).toStringAsFixed(widget.roundPhysicalCash ? 2 : 0);
    if (widget.roundPhysicalCash) _splitCashController.text = (_splitDue - _splitElectronicAmount).toStringAsFixed(0);
  }

  @override
  void dispose() {
    _cashTenderController.dispose();
    _splitCashController.dispose();
    _splitElectronicController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  int? _parsePaisa(String text) {
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(text.trim())) return null;
    final parts = text.trim().split('.');
    return int.tryParse('${parts.first}${(parts.length == 1 ? '' : parts.last).padRight(2, '0')}');
  }

  int get _totalPaisa => PaisaEngine.rupeesToPaisa(widget.grandTotal);
  int _roundCashPaisa(int paisa) => ((paisa + 50) ~/ 100) * 100;
  double get _cashDue => _roundCashPaisa(_totalPaisa) / 100;
  int get _splitElectronicPaisa => _parsePaisa(_splitElectronicController.text) ?? 0;
  double get _splitDue => (_splitElectronicPaisa + _roundCashPaisa(_totalPaisa - _splitElectronicPaisa)) / 100;
  double get _cashTenderAmount => (_parsePaisa(_cashTenderController.text) ?? 0) / 100;
  double get _cashReturnChange {
    final change = (_parsePaisa(_cashTenderController.text) ?? 0) - _roundCashPaisa(_totalPaisa);
    return change > 0 ? change / 100 : 0;
  }
  double get _splitCashAmount => (_parsePaisa(_splitCashController.text) ?? 0) / 100;
  double get _splitElectronicAmount => _splitElectronicPaisa / 100;
  double get _splitTotalPaid => _splitCashAmount + _splitElectronicAmount;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(WarmCounterSpacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order Checkout & Tender',
                    style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: _isCommitting ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: WarmCounterSpacing.space12),

              // Grand Total Banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WarmCounterSpacing.space16,
                  vertical: WarmCounterSpacing.space12,
                ),
                decoration: BoxDecoration(
                  color: WarmCounterColors.lightPageBackground,
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  border: Border.all(color: WarmCounterColors.lightBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Grand Total Payable:',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ),
                    Text(
                      'Rs ${_currencyFormat.format(widget.grandTotal)}',
                      style: WarmCounterTypography.pageHeading.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: WarmCounterColors.lightPrimaryAction,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space16),

              // All methods are recorded manually by the cashier.
              Wrap(
                spacing: WarmCounterSpacing.space8,
                runSpacing: WarmCounterSpacing.space8,
                children: [
                  for (final method in PaymentMethod.values.where((method) => method != PaymentMethod.digitalWallet && (widget.allowCod || method != PaymentMethod.cod)))
                    _buildTenderTab(method, method.displayName, method == PaymentMethod.cash ? Icons.payments_rounded : Icons.credit_card_rounded),
                ],
              ),
              const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

              // Method Body
              Expanded(
                child: SingleChildScrollView(
                  child: _buildSelectedMethodBody(),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: WarmCounterSpacing.space8),
                Text(
                  _errorMessage!,
                  style: WarmCounterTypography.caption.copyWith(
                    color: WarmCounterColors.lightDestructiveAction,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],

              const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

              // Commit Checkout Button
              ElevatedButton.icon(
                key: const ValueKey('commit_checkout_button'),
                icon: _isCommitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: StreetFoodMafiaColors.textOnPrimary, strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 22),
                label: Text(
                  _isCommitting ? 'Committing Order...' : 'Complete Checkout',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isCommitting ? null : _handleCheckoutSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: StreetFoodMafiaColors.cartelYellow,
                  foregroundColor: StreetFoodMafiaColors.textOnPrimary,
                  minimumSize: const Size(double.infinity, 52),
                  shape: const RoundedRectangleBorder(
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTenderTab(PaymentMethod method, String label, IconData icon) {
    final isSelected = _selectedMethod == method;
    return SizedBox(
      width: 132,
      child: InkWell(
        key: ValueKey('tender_tab_${method.name}'),
        onTap: () => setState(() => _selectedMethod = method),
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? WarmCounterColors.lightActiveNavHighlight : Colors.transparent,
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            border: Border.all(
              color: isSelected ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightSecondaryText,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightPrimaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedMethodBody() {
    switch (_selectedMethod) {
      case PaymentMethod.cash:
        return _buildCashTenderBody();
      case PaymentMethod.jazzCash:
      case PaymentMethod.easypaisa:
      case PaymentMethod.digitalWallet:
      case PaymentMethod.bankTransfer:
      case PaymentMethod.card:
        return _buildElectronicTenderBody(_selectedMethod);
      case PaymentMethod.raast:
        return _buildElectronicTenderBody(PaymentMethod.raast);
      case PaymentMethod.cod:
        return const Text('Collection Due: no cash is received now. Payment is collected during rider trip settlement.');
      case PaymentMethod.split:
        return _buildSplitTenderBody();
    }
  }

  Widget _buildCashTenderBody() {
    final tendered = _cashTenderAmount;
    final change = _cashReturnChange;
    final isShort = tendered < _cashDue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.roundPhysicalCash)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Cash payable: Rs ${_currencyFormat.format(_cashDue)} (rounding: Rs ${_currencyFormat.format(_cashDue - widget.grandTotal)})',
              textAlign: TextAlign.right,
              style: WarmCounterTypography.tabularNumbers,
            ),
          ),
        // Quick Denominations
        Text(
          'Quick Cash Presets:',
          style: WarmCounterTypography.secondaryLabel.copyWith(color: WarmCounterColors.lightSecondaryText),
        ),
        const SizedBox(height: WarmCounterSpacing.space8),
        Wrap(
          spacing: WarmCounterSpacing.space8,
          runSpacing: WarmCounterSpacing.space8,
          children: [
            _buildDenominationChip(_cashDue, 'Exact Cash'),
            _buildDenominationChip(500.0, 'Rs 500'),
            _buildDenominationChip(1000.0, 'Rs 1,000'),
            _buildDenominationChip(2000.0, 'Rs 2,000'),
            _buildDenominationChip(5000.0, 'Rs 5,000'),
          ],
        ),
        const SizedBox(height: WarmCounterSpacing.space16),

        // Cash Input Field
        Text(
          'Physical Amount Tendered:',
          style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: WarmCounterSpacing.space8),
        TextField(
          key: const ValueKey('cash_tendered_input'),
          controller: _cashTenderController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixText: 'Rs ',
            border: OutlineInputBorder(),
            hintText: 'Enter cash received',
          ),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: WarmCounterSpacing.space16),

        // Large Return Change Display
        Container(
          padding: const EdgeInsets.all(WarmCounterSpacing.space16),
          decoration: BoxDecoration(
            color: isShort
                ? const Color(0xFFFFF3E0) // Warm warning tint
                : const Color(0xFFE8F5E9), // Clean green tint
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(
              color: isShort
                  ? WarmCounterColors.lightWarning
                  : WarmCounterColors.lightPrimaryAction,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                isShort ? 'Remaining Unpaid Balance' : 'Return Change to Customer',
                style: WarmCounterTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isShort
                      ? const Color(0xFFE65100)
                      : WarmCounterColors.lightPrimaryAction,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isShort
                    ? 'Rs ${_currencyFormat.format(_cashDue - tendered)}'
                    : 'Rs ${_currencyFormat.format(change)}',
                key: const ValueKey('return_change_display'),
                style: WarmCounterTypography.tokenAndChange.copyWith(
                  fontSize: 36,
                  color: WarmCounterColors.lightPrimaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDenominationChip(double amount, String label) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        setState(() {
          _cashTenderController.text = amount.toStringAsFixed(0);
        });
      },
    );
  }

  Widget _buildElectronicTenderBody(PaymentMethod method) {
    final isRaast = method == PaymentMethod.raast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(WarmCounterSpacing.space16),
          decoration: BoxDecoration(
            color: WarmCounterColors.lightActiveNavHighlight,
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Row(
            children: [
              Icon(
                isRaast ? Icons.qr_code_scanner_rounded : Icons.credit_score_rounded,
                size: 32,
                color: WarmCounterColors.lightPrimaryAction,
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.displayName,
                      style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Manually confirm Rs ${_currencyFormat.format(widget.grandTotal)} received before completing checkout.',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WarmCounterSpacing.space16),
        Text(
          'Reference Code / Slip # (Optional):',
          style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: WarmCounterSpacing.space8),
        TextField(
          key: const ValueKey('electronic_reference_input'),
          controller: _referenceController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g. STAN / RRN / Raast Txn ID',
          ),
        ),
      ],
    );
  }

  Widget _buildSplitTenderBody() {
    final isMatched = PaisaEngine.rupeesToPaisa(_splitTotalPaid) == PaisaEngine.rupeesToPaisa(_splitDue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Split Payment Configuration:',
          style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: WarmCounterSpacing.space12),

        if (widget.roundPhysicalCash) Text('Cash balance rounds to whole rupees. Digital amounts stay exact.', style: WarmCounterTypography.caption),
        // Cash Portion
        const Text('1. Cash Portion Amount:', style: WarmCounterTypography.secondaryLabel),
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('split_cash_input'),
          controller: _splitCashController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixText: 'Rs ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: WarmCounterSpacing.space12),

        // Electronic Method Selector & Amount
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('2. Electronic Portion Method:', style: WarmCounterTypography.secondaryLabel),
            DropdownButton<PaymentMethod>(
              value: _splitElectronicMethod,
              items: const [
                DropdownMenuItem(value: PaymentMethod.raast, child: Text('Raast QR')),
                DropdownMenuItem(value: PaymentMethod.card, child: Text('Card')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _splitElectronicMethod = val);
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          key: const ValueKey('split_electronic_input'),
          controller: _splitElectronicController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixText: 'Rs ', border: OutlineInputBorder()),
        ),
        const SizedBox(height: WarmCounterSpacing.space16),

        // Split Summary Banner
        Container(
          padding: const EdgeInsets.all(WarmCounterSpacing.space12),
          decoration: BoxDecoration(
            color: isMatched ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            border: Border.all(color: isMatched ? Colors.green : Colors.red),
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Total Allocated: Rs ${_currencyFormat.format(_splitTotalPaid)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                isMatched ? 'Balanced' : 'Remaining: Rs ${_currencyFormat.format(_splitDue - _splitTotalPaid)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isMatched ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleCheckoutSubmit() async {
    setState(() {
      _errorMessage = null;
    });

    final tenders = <PaymentTender>[];

    if (_selectedMethod == PaymentMethod.cash) {
      final cashPaisa = _parsePaisa(_cashTenderController.text);
      if (cashPaisa == null || cashPaisa % 100 != 0) {
        setState(() => _errorMessage = 'Enter physical cash in whole rupees.');
        return;
      }
      final cash = _cashTenderAmount;
      if (cash < _cashDue) {
        setState(() => _errorMessage = 'Cash tendered is less than Grand Total.');
        return;
      }
      tenders.add(PaymentTender(
        method: PaymentMethod.cash,
        amountTendered: cash,
        changeReturned: _cashReturnChange,
      ));
    } else if (_selectedMethod == PaymentMethod.cod) {
      if (!widget.allowCod) return;
      tenders.add(PaymentTender(method: PaymentMethod.cod, amountTendered: 0));
    } else if (_selectedMethod != PaymentMethod.split) {
      tenders.add(PaymentTender(
        method: _selectedMethod,
        amountTendered: widget.grandTotal,
        changeReturned: 0.0,
        referenceCode: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
      ));
    } else if (_selectedMethod == PaymentMethod.split) {
      final cashPaisa = _parsePaisa(_splitCashController.text);
      final electronicPaisa = _parsePaisa(_splitElectronicController.text);
      if (cashPaisa == null || cashPaisa % 100 != 0 || electronicPaisa == null) {
        setState(() => _errorMessage = 'Enter whole-rupee cash and electronic amounts with at most two decimal places.');
        return;
      }
      final cashPortion = _splitCashAmount;
      final elecPortion = _splitElectronicAmount;
      if (cashPortion < 0 || elecPortion < 0 || elecPortion > widget.grandTotal || cashPaisa + electronicPaisa != PaisaEngine.rupeesToPaisa(_splitDue)) {
        setState(() => _errorMessage = 'Split tenders do not match Grand Total.');
        return;
      }
      if (cashPortion > 0 || (widget.roundPhysicalCash && elecPortion < widget.grandTotal)) {
        tenders.add(PaymentTender(
          method: PaymentMethod.cash,
          amountTendered: cashPortion,
          changeReturned: 0.0,
        ));
      }
      if (elecPortion > 0) {
        tenders.add(PaymentTender(
          method: _splitElectronicMethod,
          amountTendered: elecPortion,
          changeReturned: 0.0,
          referenceCode: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        ));
      }
    }

    setState(() => _isCommitting = true);
    try {
      await widget.onCompleteCheckout(tenders);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCommitting = false;
          _errorMessage = 'Checkout failed: $e';
        });
      }
    }
  }
}



