import 'package:flutter/material.dart';
import '../../core/delivery/rider_trip.dart';
import '../../core/delivery/rider_trip_controller.dart';
import '../../core/orders/paisa_engine.dart';
import '../../core/time/actual_event_time.dart';
import '../../core/theme/theme.dart';

/// Modal dialog where the Cashier counts physical cash handed over from a rider's pouch,
/// reconciling delivered COD orders, recording a drawer PAY_IN, and locking the trip.
class RiderTripSettlementDialog extends StatefulWidget {
  const RiderTripSettlementDialog({
    super.key,
    required this.trip,
    required this.cashierStaffId,
    required this.shiftId,
    required this.controller,
    this.onSettled,
  });

  final RiderTrip trip;
  final int cashierStaffId;
  final int shiftId;
  final RiderTripController controller;
  final VoidCallback? onSettled;

  @override
  State<RiderTripSettlementDialog> createState() => _RiderTripSettlementDialogState();
}

class _RiderTripSettlementDialogState extends State<RiderTripSettlementDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _cashController;
  late TextEditingController _notesController;
  final _actualTime = TextEditingController();
  final _digitalReferences = <int, TextEditingController>{};
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final expectedRupees = PaisaEngine.paisaToRupees(widget.trip.cashExpectedPaisa);
    _cashController = TextEditingController(text: expectedRupees > 0 ? expectedRupees.toStringAsFixed(0) : '0');
    _notesController = TextEditingController();
    for (final item in widget.trip.orders) {
      if (item.isDelivered && item.order?.paymentStatus == 'COLLECTION_DUE') {
        _digitalReferences[item.orderId] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _cashController.dispose();
    _notesController.dispose();
    _actualTime.dispose();
    for (final controller in _digitalReferences.values) { controller.dispose(); }
    super.dispose();
  }

  int get _countedPaisa {
    final parsed = double.tryParse(_cashController.text.trim()) ?? 0.0;
    return PaisaEngine.rupeesToPaisa(parsed);
  }

  int get _variancePaisa => _countedPaisa - widget.trip.cashExpectedPaisa;

  Future<void> _handleSettlement() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.controller.settleRiderTrip(
        tripId: widget.trip.id,
        cashierStaffId: widget.cashierStaffId,
        shiftId: widget.shiftId,
        cashCountedPaisa: _countedPaisa,
        notes: _notesController.text.trim(),
        settledAt: parseActualEventTime(_actualTime.text),
        digitalWalletReferences: {for (final entry in _digitalReferences.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim()},
      );

      if (mounted) {
        widget.onSettled?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expectedRupees = PaisaEngine.paisaToRupees(widget.trip.cashExpectedPaisa);
    final deliveredOrders = widget.trip.orders.where((o) => o.isDelivered).length;
    final returnedOrders = widget.trip.orders.where((o) => o.isReturned).length;
    final inTransitOrders = widget.trip.orders.where((o) => o.isDispatched).length;

    return Dialog(
      backgroundColor: StreetFoodMafiaColors.darkNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StreetFoodMafiaColors.border, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: StreetFoodMafiaColors.activeNavHighlight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.point_of_sale_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Rider Trip Settlement',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: StreetFoodMafiaColors.offWhite,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            '${widget.trip.tripName} • Rider: ${widget.trip.riderName ?? "ID #${widget.trip.riderStaffId}"}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: StreetFoodMafiaColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: StreetFoodMafiaColors.secondaryText),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Trip Order Stats
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: StreetFoodMafiaColors.obsidian,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StreetFoodMafiaColors.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn('Total Orders', '${widget.trip.orders.length}', StreetFoodMafiaColors.offWhite),
                      _buildStatColumn('Delivered', '$deliveredOrders', StreetFoodMafiaColors.statusReady),
                      _buildStatColumn('Returned', '$returnedOrders', StreetFoodMafiaColors.statusCanceled),
                      if (inTransitOrders > 0)
                        _buildStatColumn('Pending', '$inTransitOrders', StreetFoodMafiaColors.cartelYellow),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Cash Reconciliation Details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: StreetFoodMafiaColors.obsidian,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StreetFoodMafiaColors.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Expected COD Cash (Pouch):',
                            style: TextStyle(fontSize: 14, color: StreetFoodMafiaColors.secondaryText),
                          ),
                          Text(
                            'Rs. ${expectedRupees.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: StreetFoodMafiaColors.cartelYellow,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const ValueKey('counted_cash_input'),
                        controller: _cashController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: StreetFoodMafiaColors.offWhite,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Counted Cash Handover (Rs.)',
                          labelStyle: TextStyle(color: StreetFoodMafiaColors.secondaryText),
                          prefixText: 'Rs. ',
                          prefixStyle: TextStyle(color: StreetFoodMafiaColors.cartelYellow, fontWeight: FontWeight.w700),
                          filled: true,
                          fillColor: StreetFoodMafiaColors.darkNavy,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Enter counted cash amount';
                          final numVal = double.tryParse(value.trim());
                          if (numVal == null || numVal < 0) return 'Enter a valid non-negative amount';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      // Variance badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Counted minus dispatch estimate:', style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
                          Text(
                            _variancePaisa == 0
                                ? 'Exact (Rs. 0)'
                                : (_variancePaisa > 0
                                    ? '+${PaisaEngine.formatRupees(_variancePaisa)} Surplus'
                                    : '-${PaisaEngine.formatRupees(-_variancePaisa)} Shortage'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _variancePaisa == 0
                                  ? StreetFoodMafiaColors.statusReady
                                  : (_variancePaisa > 0 ? StreetFoodMafiaColors.cartelYellow : StreetFoodMafiaColors.statusCanceled),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                TextFormField(
                  key: const ValueKey('settlement_notes_input'),
                  controller: _notesController,
                  maxLines: 2,
                  style: const TextStyle(color: StreetFoodMafiaColors.offWhite, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Settlement Notes (Optional)',
                    labelStyle: TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 13),
                    filled: true,
                    fillColor: StreetFoodMafiaColors.obsidian,
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('rider_settlement_actual_time'),
                  controller: _actualTime,
                  decoration: const InputDecoration(
                    labelText: 'Actual handover / confirmation time (Pakistan)',
                    hintText: 'YYYY-MM-DD HH:MM; blank = now',
                    helperText: 'Must be within this open receiving Shift. Recording time stays unchanged.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    try { parseActualEventTime(value); return null; }
                    on FormatException catch (error) { return error.message; }
                  },
                ),
                for (final entry in _digitalReferences.entries) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: ValueKey('rider_digital_reference_${entry.key}'),
                    controller: entry.value,
                    decoration: InputDecoration(
                      labelText: 'Order #${entry.key}: confirmed direct digital reference',
                      helperText: 'Leave blank for COD. Confirm the bank receipt; count only physical cash above.',
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Dispatch estimates are not proof of customer collection. Digital payments and later receipts can change the expected pouch; this difference is not verified rider debt.',
                  style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: StreetFoodMafiaColors.statusCanceled.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: StreetFoodMafiaColors.statusCanceled),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: StreetFoodMafiaColors.statusCanceled, fontSize: 12),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Allow the long confirmation label to wrap onto its own row.
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel', style: TextStyle(color: StreetFoodMafiaColors.secondaryText)),
                    ),
                    ElevatedButton.icon(
                      key: const ValueKey('confirm_settlement_btn'),
                      icon: _isSubmitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: StreetFoodMafiaColors.textOnPrimary))
                          : const Icon(Icons.check_circle_rounded, color: StreetFoodMafiaColors.textOnPrimary),
                      label: const Text(
                        'Confirm Settlement & Deposit Cash',
                        style: TextStyle(fontWeight: FontWeight.w800, color: StreetFoodMafiaColors.textOnPrimary),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: StreetFoodMafiaColors.cartelYellow,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      onPressed: _isSubmitting ? null : _handleSettlement,
                    ),
                  ],
                ),
              ],
            ),
          )),
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText)),
      ],
    );
  }
}
