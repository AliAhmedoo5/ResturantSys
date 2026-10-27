import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/orders/cashier_orders_panel.dart';

class StatusOrders implements OrderAndCheckoutController {
  Order order = Order(id: 1, businessDayId: 1, shiftId: 1, cashierId: 2,
    tokenNumber: 7, diningType: DiningType.takeaway, subtotal: 500,
    grandTotal: 500, paymentStatus: 'SETTLED', createdAt: DateTime(2026));
  int? actor;
  @override
  CartTotals calculateCartTotals({required List<CartItem> items, DiscountPreset? discount, DiningType? diningType, int? cashierId}) =>
    const CartTotals(subtotal: 0, discountAmount: 0, taxAmount: 0, grandTotal: 0);
  @override
  Future<List<Order>> getOrders({int? businessDayId, int? shiftId, int? limit}) async => [order];
  @override
  Future<TokenStatus> advanceOrderStatus({required int orderId, required int cashierId,
    required TokenStatus expectedStatus}) async {
    actor = cashierId;
    order = Order.fromMap({...order.toMap(), 'token_status': expectedStatus.nextStatus!.code});
    return order.tokenStatus;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Cashier opens Orders and explicitly records ready then collected', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orders = StatusOrders();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CounterBillingWorkspace(
      orderController: orders, currentStaff: const Staff(id: 2, name: 'Cashier',
        departmentId: 1, pinHash: 'hash', role: StaffRole.cashier, isActive: true),
      businessDayId: 1, shiftId: 1, initialCategories: const [], initialMenuItems: const [],
      initialDeals: const [], initialDiscounts: const [], initialModifiers: const [],
      initialNextTokenNumber: 8))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_order_status_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Token #07'), findsOneWidget);
    await tester.tap(find.text('Mark Ready'));
    await tester.pumpAndSettle();
    expect(orders.actor, 2);
    expect(find.text('Mark Collected'), findsOneWidget);
    await tester.tap(find.text('Mark Collected'));
    await tester.pumpAndSettle();
    expect(orders.order.tokenStatus, TokenStatus.delivered);
    expect(find.textContaining('Collected •'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (name: 'partially revised prepaid order awaiting refund', total: 300.0, payment: 'REFUND_PENDING'),
    (name: 'fully discounted valid order', total: 0.0, payment: 'SETTLED'),
  ]) {
    testWidgets('${scenario.name} still permits food fulfillment', (tester) async {
      final orders = StatusOrders();
      orders.order = Order.fromMap({...orders.order.toMap(), 'grand_total': scenario.total,
        'payment_status': scenario.payment});
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CashierOrdersPanel(
        controller: orders, cashierId: 2, businessDayId: 1))));
      await tester.pumpAndSettle();
      expect(find.text('Mark Ready'), findsOneWidget);
      await tester.tap(find.text('Mark Ready'));
      await tester.pumpAndSettle();
      expect(orders.order.tokenStatus, TokenStatus.ready);
      expect(find.text('Mark Collected'), findsOneWidget);
    });
  }

  testWidgets('cancelled prepaid order shows cancellation separately from refund owed', (tester) async {
    final orders = StatusOrders();
    orders.order = Order.fromMap({...orders.order.toMap(), 'grand_total': 0.0,
      'payment_status': 'REFUND_PENDING', 'has_cancellation_revision': 1});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CashierOrdersPanel(
      controller: orders, cashierId: 2, businessDayId: 1))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cancelled • REFUND_PENDING'), findsOneWidget);
    expect(find.text('Mark Ready'), findsNothing);
  });
}
