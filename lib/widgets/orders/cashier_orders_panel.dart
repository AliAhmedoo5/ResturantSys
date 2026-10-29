import '../../core/time/actual_event_time.dart';
import 'package:flutter/material.dart';
import '../../core/orders/dining_type.dart';
import '../../core/orders/order.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/orders/token_status.dart';
import '../../core/orders/payment_method.dart';

/// Cashier records observed fulfillment milestones without a kitchen station.
class CashierOrdersPanel extends StatefulWidget {
  const CashierOrdersPanel({super.key, required this.controller,
    required this.cashierId, required this.businessDayId, this.shiftId});
  final int? shiftId;
  final OrderAndCheckoutController controller;
  final int cashierId, businessDayId;
  @override
  State<CashierOrdersPanel> createState() => _CashierOrdersPanelState();
}

class _CashierOrdersPanelState extends State<CashierOrdersPanel> {
  List<Order> _orders = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await widget.controller.getOrders(businessDayId: widget.businessDayId);
      if (mounted) setState(() { _orders = orders; _busy = false; _error = null; });
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = error.toString(); });
    }
  }

  Future<void> _advance(Order order) async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.controller.advanceOrderStatus(orderId: order.id,
        cashierId: widget.cashierId, expectedStatus: order.tokenStatus);
      await _load();
    } catch (error) {
      if (mounted) setState(() { _busy = false; _error = error.toString(); });
    }
  }

  Future<void> _collect(Order order) async {
    final amount = TextEditingController();
    final actual = TextEditingController();
    var method = PaymentMethod.cash;
    final commandId = 'receipt-${order.id}-${DateTime.now().microsecondsSinceEpoch}';
    final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, change) => AlertDialog(
      title: const Text('Record customer receipt'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount received (Rs)')),
        DropdownButtonFormField<PaymentMethod>(initialValue: method, decoration: const InputDecoration(labelText: 'Manual tender'), items: PaymentMethod.values.where((m) => m != PaymentMethod.cod && m != PaymentMethod.split).map((m) => DropdownMenuItem(value: m, child: Text(m.displayName))).toList(), onChanged: (value) => change(() => method = value!)),
        TextField(controller: actual, decoration: const InputDecoration(labelText: 'Late actual time (optional)', helperText: 'Pakistan time: YYYY-MM-DD HH:MM. Blank uses entry time.')),
        const Text('Final cash rounds half-up to whole rupees. The receiving Shift must be open. This does not record a rider handover.'),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record receipt'))],
    )));
    if (accepted == true && mounted) {
      try {
        final value = amount.text.trim();
        if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) throw ArgumentError('Enter a positive amount with at most two decimal places.');
        final parts = value.split('.');
        final paisa = int.parse(parts.first) * 100 + (parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0')));
        final input = actual.text.trim();
        final time = parseActualEventTime(input);
        await widget.controller.recordCashierReceipt(orderId: order.id, shiftId: widget.shiftId!, cashierId: widget.cashierId, amountPaisa: paisa, method: method, commandId: commandId, actualAt: time);
        await _load();
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
    amount.dispose(); actual.dispose();
  }

  String _stage(Order order) {
    if (order.isCancelled) return 'Cancelled';
    if (order.tokenStatus != TokenStatus.delivered || order.diningType == DiningType.delivery) {
      return order.tokenStatus.displayName;
    }
    return order.diningType == DiningType.takeaway ? 'Collected' : 'Served';
  }

  String? _action(Order order) {
    if (order.isCancelled || order.isVoided) return null;
    switch (order.tokenStatus) {
      case TokenStatus.confirmed: return 'Start Preparing';
      case TokenStatus.preparing: return 'Mark Ready';
      case TokenStatus.ready:
        if (order.diningType == DiningType.delivery) return null;
        return order.diningType == DiningType.takeaway ? 'Mark Collected' : 'Mark Served';
      case TokenStatus.outForDelivery:
      case TokenStatus.delivered: return null;
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
    Row(children: [const Expanded(child: Text('Orders', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
      TextButton.icon(onPressed: _busy ? null : () { setState(() => _busy = true); _load(); },
        icon: const Icon(Icons.refresh), label: const Text('Refresh'))]),
    if (_busy) const LinearProgressIndicator(),
    if (_error != null) Padding(padding: const EdgeInsets.all(8),
      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    Expanded(child: _orders.isEmpty && !_busy
      ? const Center(child: Text('No orders in this Business Day.'))
      : ListView.separated(itemCount: _orders.length,
          separatorBuilder: (_, index) => const Divider(),
          itemBuilder: (context, index) {
            final order = _orders[index];
            final action = _action(order);
            return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Wrap(
              alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16, runSpacing: 8, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Token ${order.tokenDisplay} • ${order.diningType.displayName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('${_stage(order)} • ${order.paymentStatus}'),
                  Text(order.items.map((item) => '${item.quantity} × ${item.name}').join(', ')),
                  if (order.diningType == DiningType.delivery && action == null &&
                      order.tokenStatus != TokenStatus.delivered)
                    const Text('Dispatch and delivery are recorded in Rider Trips.'),
                ]),
                if (action != null) FilledButton(onPressed: _busy ? null : () => _advance(order),
                  child: Text(action)),
                if (widget.shiftId != null && order.paymentStatus == 'COLLECTION_DUE') OutlinedButton(onPressed: _busy ? null : () => _collect(order), child: const Text('Record receipt')),
              ]));
          })),
  ]);
}
