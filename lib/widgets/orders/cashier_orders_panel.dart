import 'package:flutter/material.dart';
import '../../core/orders/dining_type.dart';
import '../../core/orders/order.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/orders/token_status.dart';

/// Cashier records observed fulfillment milestones without a kitchen station.
class CashierOrdersPanel extends StatefulWidget {
  const CashierOrdersPanel({super.key, required this.controller,
    required this.cashierId, required this.businessDayId});
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
              ]));
          })),
  ]);
}
