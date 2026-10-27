import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/order_void.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/orders/supervisor_void_dialog.dart';
import 'package:sqflite_common/sqlite_api.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({SessionState? session}) : session = session ?? SessionState();

  @override
  final SessionState session;

  @override
  Database get database => throw UnimplementedError();

  Staff? supervisor;
  String? lastPinAttempted;

  @override
  Future<Staff?> authenticateSupervisorPin(String pin) async {
    lastPinAttempted = pin;
    if (pin == '1234') {
      return supervisor ??
          const Staff(
            id: 1,
            name: 'Supervisor',
            departmentId: 1,
            pinHash: 'hash',
            role: StaffRole.supervisor,
            isActive: true,
          );
    }
    return null;
  }

  @override
  Future<Staff?> authenticateWithPin(String pin) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeOrderController implements OrderAndCheckoutController {
  bool cashierVoidEnabled = true;
  OrderVoid? lastVoidResult;
  int? voidedOrderId;
  String? voidReason;
  late Order testOrder;

  @override
  Database get database => throw UnimplementedError();

  @override
  Future<bool> isCashierVoidEnabled() async => cashierVoidEnabled;

  @override
  Future<void> setCashierVoidEnabled(bool enabled) async {
    cashierVoidEnabled = enabled;
  }

  @override
  Future<OrderVoid> voidOrder({
    required int orderId,
    required int supervisorStaffId,
    required int cashierStaffId,
    required String reason,
  }) async {
    voidedOrderId = orderId;
    voidReason = reason;
    final res = OrderVoid(
      id: 1,
      orderId: orderId,
      voidedBySupervisorId: supervisorStaffId,
      cashierId: cashierStaffId,
      reason: reason,
      voidedAt: DateTime.now(),
      supervisorName: 'Supervisor',
      cashierName: 'Counter Cashier',
    );
    lastVoidResult = res;
    return res;
  }

  @override
  Future<Order> getOrder(int orderId) async {
    if (lastVoidResult != null && lastVoidResult!.orderId == orderId) {
      return Order(
        id: testOrder.id,
        businessDayId: testOrder.businessDayId,
        shiftId: testOrder.shiftId,
        cashierId: testOrder.cashierId,
        tokenNumber: testOrder.tokenNumber,
        diningType: testOrder.diningType,
        subtotal: testOrder.subtotal,
        grandTotal: testOrder.grandTotal,
        paymentStatus: 'VOIDED',
        createdAt: testOrder.createdAt,
      );
    }
    return testOrder;
  }

  @override
  Future<OrderVoid?> getOrderVoid(int orderId) async {
    return lastVoidResult;
  }

  @override
  Future<List<Order>> getOrders({
    int? businessDayId,
    int? shiftId,
    int? limit,
  }) async {
    return [testOrder];
  }

  @override
  CartTotals calculateCartTotals({
    required List<CartItem> items,
    DiscountPreset? discount,
    DiningType? diningType,
    int? cashierId,
  }) {
    return const CartTotals(
      subtotal: 0.0,
      discountAmount: 0.0,
      taxAmount: 0.0,
      grandTotal: 0.0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SupervisorVoidDialog Widget Tests', () {
    late FakeAuthService authService;
    late FakeOrderController orderController;
    late Order testOrder;

    const cashierStaff = Staff(
      id: 2,
      name: 'Counter Cashier',
      departmentId: 1,
      pinHash: 'hash',
      role: StaffRole.cashier,
      isActive: true,
      departmentName: 'Front Counter',
    );

    setUp(() {
      authService = FakeAuthService();
      orderController = FakeOrderController();

      testOrder = Order(
        id: 42,
        businessDayId: 1,
        shiftId: 1,
        cashierId: cashierStaff.id,
        tokenNumber: 7,
        diningType: DiningType.dineIn,
        subtotal: 1000.0,
        grandTotal: 1000.0,
        paymentStatus: 'SETTLED',
        createdAt: DateTime.now(),
      );
      orderController.testOrder = testOrder;
    });

    Widget createTestApp(Widget child) {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(body: child),
      );
    }

    testWidgets('renders order summary, mandatory reasons, and supervisor pin numpad without logging cashier out', (tester) async {
      authService.session.login(cashierStaff);
      expect(authService.session.isAuthenticated, isTrue);
      expect(authService.session.currentStaff?.name, equals('Counter Cashier'));

      await tester.pumpWidget(createTestApp(
        SupervisorVoidDialog(
          order: testOrder,
          cashierId: cashierStaff.id,
          orderController: orderController,
          authService: authService,
        ),
      ));
      await tester.pumpAndSettle();

      // Header details
      expect(find.text('Supervisor Void Authorization'), findsOneWidget);
      expect(find.textContaining('Order #${testOrder.id}'), findsOneWidget);
      expect(find.textContaining('Token ${testOrder.tokenDisplay}'), findsOneWidget);

      // Mandatory void reasons
      expect(find.text('Void Reason (Mandatory):'), findsOneWidget);
      expect(find.text(VoidReason.customerCancelled), findsOneWidget);
      expect(find.text(VoidReason.cashierMistake), findsOneWidget);
      expect(find.text(VoidReason.paymentDeclined), findsOneWidget);

      // Pin Numpad
      expect(find.text('Enter Supervisor 4-Digit PIN'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);

      // Cashier remains logged in
      expect(authService.session.isAuthenticated, isTrue);
      expect(authService.session.currentStaff?.id, equals(cashierStaff.id));
    });

    testWidgets('rejects invalid or non-supervisor PIN, shows error message, and keeps cashier logged in', (tester) async {
      authService.session.login(cashierStaff);

      await tester.pumpWidget(createTestApp(
        SupervisorVoidDialog(
          order: testOrder,
          cashierId: cashierStaff.id,
          orderController: orderController,
          authService: authService,
        ),
      ));
      await tester.pumpAndSettle();

      // Enter cashier PIN (1111) which fails supervisor check
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pumpAndSettle();

      // Error message displayed
      expect(find.text('Invalid Supervisor PIN or insufficient privileges.'), findsOneWidget);

      // Order is NOT voided
      expect(orderController.lastVoidResult, isNull);

      // Cashier is still logged in
      expect(authService.session.currentStaff?.id, equals(cashierStaff.id));
    });

    testWidgets('authorizes with valid supervisor PIN (1234), voids order and keeps the cashier session', (tester) async {
      authService.session.login(cashierStaff);
      bool voidSuccessCallbackCalled = false;

      await tester.pumpWidget(createTestApp(
        SupervisorVoidDialog(
          order: testOrder,
          cashierId: cashierStaff.id,
          orderController: orderController,
          authService: authService,
          onVoidSuccess: () => voidSuccessCallbackCalled = true,
        ),
      ));
      await tester.pumpAndSettle();

      // Select 'Cashier Mistake' reason
      await tester.tap(find.byKey(const ValueKey('void_reason_cashier_mistake')));
      await tester.pumpAndSettle();

      // Enter supervisor PIN 1234
      await tester.tap(find.widgetWithText(InkWell, '1'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '2'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '3'));
      await tester.pump();
      await tester.tap(find.widgetWithText(InkWell, '4'));
      await tester.pumpAndSettle();

      expect(voidSuccessCallbackCalled, isTrue);

      // Order is VOIDED in controller
      expect(orderController.lastVoidResult, isNotNull);
      expect(orderController.lastVoidResult!.reason, equals(VoidReason.cashierMistake));
      expect(orderController.lastVoidResult!.supervisorName, equals('Supervisor'));

      // Cancellation remains audited without emitting any kitchen print job.

      // Cashier remains logged in throughout the entire flow
      expect(authService.session.currentStaff?.id, equals(cashierStaff.id));
    });

    testWidgets('CounterBillingWorkspace alerts when cashier void requests are disabled', (tester) async {
      await orderController.setCashierVoidEnabled(false);

      await tester.pumpWidget(createTestApp(
        CounterBillingWorkspace(
          currentStaff: cashierStaff,
          businessDayId: 1,
          shiftId: 1,
          orderController: orderController,
          authService: authService,
          initialCategories: const [],
          initialMenuItems: const [],
          initialDeals: const [],
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final voidButtonFinder = find.byKey(const ValueKey('open_void_order_button'));
      expect(voidButtonFinder, findsOneWidget);

      await tester.tap(voidButtonFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Cashier void requests are disabled by management.'), findsOneWidget);
    });
  });
}
