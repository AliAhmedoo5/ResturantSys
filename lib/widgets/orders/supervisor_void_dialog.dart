import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_service.dart';
import '../../core/orders/order.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/orders/order_void.dart';
import '../../core/theme/theme.dart';
import '../pin_numpad.dart';

/// Transient modal dialog for supervisor-authorized order cancellation.
///
/// Opens over the active counter billing workspace WITHOUT logging the cashier out.
/// Captures mandatory cancellation reasons, verifies supervisor 4-digit PIN,
/// marks the order VOIDED and records the stock reversal without a kitchen print job.
class SupervisorVoidDialog extends StatefulWidget {
  const SupervisorVoidDialog({
    super.key,
    required this.order,
    required this.cashierId,
    required this.orderController,
    required this.authService,
    this.onVoidSuccess,
  });

  final Order order;
  final int cashierId;
  final OrderAndCheckoutController orderController;
  final AuthService authService;
  final VoidCallback? onVoidSuccess;

  @override
  State<SupervisorVoidDialog> createState() => _SupervisorVoidDialogState();
}

class _SupervisorVoidDialogState extends State<SupervisorVoidDialog> {
  String _selectedReason = VoidReason.customerCancelled;
  String _pin = '';
  String? _errorMessage;
  bool _isAuthorizing = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  void _onDigitPressed(String digit) {
    if (_pin.length < 4 && !_isAuthorizing) {
      setState(() {
        _errorMessage = null;
        _pin += digit;
      });

      if (_pin.length == 4) {
        _submitAuthorization();
      }
    }
  }

  void _onBackspacePressed() {
    if (_pin.isNotEmpty && !_isAuthorizing) {
      setState(() {
        _errorMessage = null;
        _pin = _pin.substring(0, _pin.length - 1);
      });
    }
  }

  void _onClearPressed() {
    if (_pin.isNotEmpty && !_isAuthorizing) {
      setState(() {
        _errorMessage = null;
        _pin = '';
      });
    }
  }

  Future<void> _submitAuthorization() async {
    if (_pin.length != 4 || _isAuthorizing) return;

    setState(() {
      _isAuthorizing = true;
      _errorMessage = null;
    });

    try {
      // 1. Verify supervisor PIN without altering cashier session
      final supervisor = await widget.authService.authenticateSupervisorPin(_pin);
      if (supervisor == null) {
        if (mounted) {
          setState(() {
            _isAuthorizing = false;
            _pin = '';
            _errorMessage = 'Invalid Supervisor PIN or insufficient privileges.';
          });
        }
        return;
      }

      // 2. Execute void transaction and inventory reversal
      final voidResult = await widget.orderController.voidOrder(
        orderId: widget.order.id,
        supervisorStaffId: supervisor.id,
        cashierStaffId: widget.cashierId,
        reason: _selectedReason,
      );

      if (mounted) {
        widget.onVoidSuccess?.call();
        Navigator.of(context).pop(voidResult);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthorizing = false;
          _pin = '';
          _errorMessage = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WarmCounterColors.lightCardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: WarmCounterSpacing.panelBorderRadius,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(WarmCounterSpacing.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                          decoration: const BoxDecoration(
                            color: WarmCounterColors.lightDestructiveHighlight,
                            borderRadius: WarmCounterSpacing.controlBorderRadius,
                          ),
                          child: const Icon(
                            Icons.cancel_outlined,
                            size: 26,
                            color: WarmCounterColors.lightDestructiveAction,
                          ),
                        ),
                        const SizedBox(width: WarmCounterSpacing.space12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Supervisor Void Authorization',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WarmCounterTypography.pageHeading.copyWith(
                                  fontSize: 18,
                                  color: WarmCounterColors.lightDestructiveAction,
                                ),
                              ),
                              Text(
                                'Order #${widget.order.id} • Token ${widget.order.tokenDisplay} • Rs ${_currencyFormat.format(widget.order.grandTotal)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WarmCounterTypography.tabularNumbers.copyWith(
                                  color: WarmCounterColors.lightSecondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close_void_dialog_button'),
                    icon: const Icon(Icons.close_rounded),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: _isAuthorizing ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: WarmCounterSpacing.space16),

              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Order Summary & Mandatory Reason Selection
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Order items summary box
                            Container(
                              padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                              decoration: BoxDecoration(
                                color: WarmCounterColors.lightPageBackground,
                                borderRadius: WarmCounterSpacing.controlBorderRadius,
                                border: Border.all(color: WarmCounterColors.lightBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Dining: ${widget.order.diningType.displayName}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${widget.order.items.length} item(s)',
                                        style: WarmCounterTypography.caption,
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 12),
                                  ...widget.order.items.map((item) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                                        child: Text(
                                          '${item.quantity}x ${item.name}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: WarmCounterTypography.tabularNumbers.copyWith(
                                            fontSize: 13,
                                            color: WarmCounterColors.lightPrimaryText,
                                          ),
                                        ),
                                      )),
                                ],
                              ),
                            ),
                            const SizedBox(height: WarmCounterSpacing.space16),

                            // Mandatory Void Reason
                            Text(
                              'Void Reason (Mandatory):',
                              style: WarmCounterTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: WarmCounterSpacing.space8),

                            ...VoidReason.mandatoryReasons.map((reason) {
                              final isSelected = _selectedReason == reason;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: InkWell(
                                  mouseCursor: WidgetStateMouseCursor.clickable,
                                  key: ValueKey('void_reason_${reason.replaceAll(' ', '_').toLowerCase()}'),
                                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                                  onTap: _isAuthorizing
                                      ? null
                                      : () => setState(() => _selectedReason = reason),
                                  child: Container(
                                    constraints: const BoxConstraints(minHeight: WarmCounterSpacing.minTouchTargetSize),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? WarmCounterColors.lightDestructiveHighlight
                                          : WarmCounterColors.lightPageBackground,
                                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                                      border: Border.all(
                                        color: isSelected
                                            ? WarmCounterColors.lightDestructiveAction
                                            : WarmCounterColors.lightBorder,
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked_rounded
                                              : Icons.radio_button_off_rounded,
                                          size: 18,
                                          color: isSelected
                                              ? WarmCounterColors.lightDestructiveAction
                                              : WarmCounterColors.lightSecondaryText,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            reason,
                                            style: TextStyle(
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              color: isSelected
                                                  ? WarmCounterColors.lightDestructiveAction
                                                  : WarmCounterColors.lightPrimaryText,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),

                            const SizedBox(height: WarmCounterSpacing.space8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: WarmCounterColors.lightDestructiveHighlight.withValues(alpha: 0.5),
                                borderRadius: WarmCounterSpacing.controlBorderRadius,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.info_outline_rounded,
                                    size: 16,
                                    color: WarmCounterColors.lightDestructiveAction,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Voiding records the cancellation and restores eligible BOM stock.',
                                      style: WarmCounterTypography.caption.copyWith(
                                        fontSize: 11,
                                        color: WarmCounterColors.lightDestructiveAction,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: WarmCounterSpacing.space24),

                    // Right Column: Supervisor PIN Entry & Numpad
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Enter Supervisor 4-Digit PIN',
                            style: WarmCounterTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: WarmCounterSpacing.space12),

                          // PIN dots indicator
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(4, (index) {
                              final isFilled = index < _pin.length;
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 6),
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isFilled
                                      ? WarmCounterColors.lightDestructiveAction
                                      : WarmCounterColors.lightPageBackground,
                                  border: Border.all(
                                    color: isFilled
                                        ? WarmCounterColors.lightDestructiveAction
                                        : WarmCounterColors.lightBorder,
                                    width: 2,
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: WarmCounterSpacing.space8),

                          // Error Message or loading indicator
                          SizedBox(
                            height: 24,
                            child: _isAuthorizing
                                ? const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : (_errorMessage != null
                                    ? Text(
                                        _errorMessage!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: WarmCounterColors.lightDestructive,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : null),
                          ),
                          const SizedBox(height: WarmCounterSpacing.space8),

                          // Pin Numpad
                          PinNumpad(
                            isEnabled: !_isAuthorizing,
                            onDigitPressed: _onDigitPressed,
                            onClearPressed: _onClearPressed,
                            onBackspacePressed: _onBackspacePressed,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
