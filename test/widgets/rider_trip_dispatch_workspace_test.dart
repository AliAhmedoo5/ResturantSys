import 'package:flutter/material.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/widgets/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'package:resturant_sys/core/delivery/rider_trip_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/widgets/delivery/rider_trip_dispatch_workspace.dart';
import 'package:resturant_sys/widgets/delivery/rider_trip_settlement_dialog.dart';

class FailingQueueController extends RiderTripController {
  FailingQueueController({required super.database});
  bool fail = true;

  @override
  Future<List<Order>> getPendingDeliveryOrders({int? shiftId, int? businessDayId}) async {
    if (fail) throw StateError('Synthetic queue load failure');
    return super.getPendingDeliveryOrders(shiftId: shiftId, businessDayId: businessDayId);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('RiderTripDispatchWorkspace Widget Tests', () {
    late PosDatabase posDb;
    late Database db;
    late ShiftAndCashController shiftController;
    late CatalogAndRecipeController catalogController;
    late OrderAndCheckoutController orderController;
    late DeliveryController deliveryController;
    late RiderTripController riderTripController;

    late Staff activeCashier;
    late Shift activeShift;
    late MenuItem burgerItem;
    late DeliveryArea deliveryArea;

    setUp(() async {
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await posDb.initialize();

      shiftController = ShiftAndCashController(database: db);
      catalogController = CatalogAndRecipeController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      deliveryController = DeliveryController(database: db);
      riderTripController = RiderTripController(database: db);

      await shiftController.openBusinessDay(openedByStaffId: 1);
      activeShift = await shiftController.openShift(
        staffId: 2,
        openingFloat: 5000.0,
      );

      activeCashier = const Staff(
        id: 2,
        name: 'Counter Cashier',
        departmentId: 1,
        pinHash: '1111',
        role: StaffRole.cashier,
        isActive: true,
      );

      // Create Rider staff
      await db.insert('staff', {
        'name': 'Ali Rider',
        'department_id': 1,
        'pin_hash': 'rider_hash_2',
        'role': 'CASHIER',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      final category = await catalogController.createCategory(
        name: 'Burgers',
        displayOrder: 1,
        colorHex: '#FFC400',
      );
      final beef = await catalogController.createRawIngredient(
        name: 'Beef Patty',
        storageUnit: StorageUnit.kg,
        currentStock: 50.0,
        costPerRecipeUnit: 150.0,
      );
      burgerItem = await catalogController.createMenuItem(
        categoryId: category.id,
        name: 'Smash Burger',
        basePrice: 650.0,
      );
      await catalogController.setRecipeForMenuItem(
        menuItemId: burgerItem.id,
        items: [(rawIngredientId: beef.id, quantity: 0.15)],
      );
      await catalogController.toggleMenuItemActive(burgerItem.id, true);

      deliveryArea = await deliveryController.saveArea(
        staffId: 1,
        name: 'DHA Phase 5',
        code: 'DHA5',
        deliveryFeePaisa: 20000,
        minOrderPaisa: 50000,
      );
    });

    tearDown(() async {
      await posDb.close();
    });

    Future<void> settleUntil(
      WidgetTester tester,
      bool Function() isReady,
      String description,
    ) async {
      // Pump frames in FakeAsync; only the SQLite isolate wait uses real time.
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: description);
        if (isReady() &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Timed out waiting for $description');
    }

    Future<void> pumpWorkspace(WidgetTester tester, Widget widget) async {
      await tester.pumpWidget(widget);
      await settleUntil(
        tester,
        () => find.text('Pending Deliveries').evaluate().isNotEmpty,
        'rider workspace database load',
      );
    }

    Future<void> tapAndSettle(
      WidgetTester tester,
      Finder finder,
      bool Function() isReady,
      String description,
    ) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await settleUntil(tester, isReady, description);
    }

    Future<Order> createTestOrder({bool prepaid = false}) async {
      final result = await orderController.checkoutOrder(
        businessDayId: activeShift.businessDayId,
        shiftId: activeShift.id,
        cashierId: activeCashier.id,
        diningType: DiningType.delivery,
        items: [CartItem(menuItem: burgerItem, quantity: 1)],
        payments: [PaymentTender(method: prepaid ? PaymentMethod.cash : PaymentMethod.cod,
          amountTendered: prepaid ? 850 : 0)],
        delivery: DeliveryDetails(
          areaId: deliveryArea.id,
          quotedFeePaisa: deliveryArea.deliveryFeePaisa,
          phone: '03001234567',
          customerName: 'Test Customer',
          fullAddress: 'Street 1, DHA Phase 5',
        ),
      );
      return result.order;
    }

    testWidgets('Preparing prepaid deliveries stay visible with legacy non-login staff', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = (await tester.runAsync(() async {
        await db.insert('staff', {'name': 'Legacy Kitchen Helper', 'department_id': 1,
          'pin_hash': 'legacy-kitchen-fixture', 'role': 'KITCHEN', 'is_active': 1,
          'login_enabled': 0, 'created_at': DateTime.now().toIso8601String()});
        return createTestOrder(prepaid: true);
      }))!;
      expect(order.tokenStatus, TokenStatus.preparing);
      expect(order.paymentStatus, 'SETTLED');
      final assignees = (await tester.runAsync(() => riderTripController.getAvailableRiders()))!;
      expect(assignees.map((rider) => rider.name), contains('Legacy Kitchen Helper'));
      await pumpWorkspace(tester, MaterialApp(home: Scaffold(body: RiderTripDispatchWorkspace(
        controller: riderTripController, currentStaff: activeCashier, shiftController: shiftController,
      ))));
      expect(find.text(order.tokenDisplay), findsOneWidget,
        reason: 'A non-login staff record must not hide a dispatchable Preparing delivery.');
      expect(find.byKey(const ValueKey('rider_load_error')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rider_select_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Legacy Kitchen Helper').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first);
      await tapAndSettle(tester, find.byKey(const ValueKey('dispatch_trip_btn')),
        () => find.text('COD: Rs. 0').evaluate().isNotEmpty, 'prepaid preparing dispatch');
      expect((await tester.runAsync(() => orderController.getOrder(order.id)))!.tokenStatus,
        TokenStatus.outForDelivery);
    });

    testWidgets('Manager sees a confirmed delivery after cashier shift handover', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = (await tester.runAsync(createTestOrder))!;
      await tester.runAsync(() async {
        await db.update('shifts', {'status': 'CLOSED', 'closed_at': DateTime.now().toIso8601String()},
          where: 'id=?', whereArgs: [activeShift.id]);
        await shiftController.openShift(staffId: activeCashier.id, openingFloat: 0);
      });
      await pumpWorkspace(tester, MaterialApp(home: Scaffold(body: RiderTripDispatchWorkspace(
        controller: riderTripController, shiftController: shiftController,
        currentStaff: const Staff(id: 1, name: 'Manager', departmentId: 1,
          pinHash: 'fixture', role: StaffRole.manager, isActive: true),
      ))));
      expect(find.text(order.tokenDisplay), findsOneWidget,
        reason: 'Unassigned deliveries belong to the Business Day, including earlier cashier shifts.');
    });

    testWidgets('Cashier opens Riders and assigns a confirmed delivery without switching session', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = (await tester.runAsync(createTestOrder))!;
      final session = SessionState()..login(activeCashier);
      addTearDown(session.dispose);
      await tester.pumpWidget(MaterialApp(home: AppShell(session: session,
        onAuthenticatePin: (_) async => null, shiftController: shiftController,
        orderController: orderController, riderTripController: riderTripController,
        catalogController: catalogController,
      )));
      final menuItem = find.byKey(ValueKey('menu_item_tile_${burgerItem.id}'));
      await settleUntil(tester, () => menuItem.evaluate().isNotEmpty, 'cashier register');
      await tester.tap(menuItem);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart_item_name_0')), findsOneWidget);
      final riders = find.byKey(const ValueKey('workspace_tab_riderTrips'));
      expect(riders, findsOneWidget);
      await tester.tap(riders);
      await settleUntil(tester, () => find.text(order.tokenDisplay).evaluate().isNotEmpty, 'cashier delivery queue');
      expect(find.byKey(const ValueKey('workspace_tab_supervisor')), findsNothing);
      expect(find.byKey(const ValueKey('workspace_tab_dashboard')), findsNothing);
      await tester.tap(find.byType(Checkbox).first);
      await tapAndSettle(tester, find.byKey(const ValueKey('dispatch_trip_btn')),
        () => find.text('COD: Rs. 850').evaluate().isNotEmpty, 'cashier dispatch');
      expect(session.currentStaff?.id, activeCashier.id);
      expect((await tester.runAsync(() => orderController.getOrder(order.id)))!.tokenStatus,
        TokenStatus.outForDelivery);
      await tester.tap(find.byKey(const ValueKey('workspace_tab_register')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cart_item_name_0')), findsOneWidget,
        reason: 'Opening Riders must preserve the unfinished cashier cart.');
    });

    testWidgets('delivery loading errors are visible and can be retried', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = (await tester.runAsync(createTestOrder))!;
      final controller = FailingQueueController(database: db);
      await pumpWorkspace(tester, MaterialApp(home: Scaffold(body: RiderTripDispatchWorkspace(
        controller: controller, currentStaff: activeCashier, shiftController: shiftController,
      ))));
      expect(find.byKey(const ValueKey('rider_load_error')), findsOneWidget);
      controller.fail = false;
      await tapAndSettle(tester, find.text('Retry'),
        () => find.text(order.tokenDisplay).evaluate().isNotEmpty, 'retry deliveries');
      expect(find.byKey(const ValueKey('rider_load_error')), findsNothing);
    });

    testWidgets('active rider trips remain visible across cashier handovers', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final order = (await tester.runAsync(createTestOrder))!;
      await tester.runAsync(() async {
        await riderTripController.createRiderTrip(riderStaffId: 3, shiftId: activeShift.id,
          businessDayId: activeShift.businessDayId, tripName: 'Carryover trip', orderIds: [order.id]);
        await db.update('shifts', {'status': 'CLOSED', 'closed_at': DateTime.now().toIso8601String()},
          where: 'id=?', whereArgs: [activeShift.id]);
        await shiftController.openShift(staffId: activeCashier.id, openingFloat: 0);
      });
      await pumpWorkspace(tester, MaterialApp(home: Scaffold(body: RiderTripDispatchWorkspace(
        controller: riderTripController, currentStaff: activeCashier, shiftController: shiftController,
      ))));
      expect(find.textContaining('Carryover trip'), findsOneWidget);
    });

    testWidgets('renders pending orders and batches into a new trip', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order = (await tester.runAsync(createTestOrder))!;

      await pumpWorkspace(
        tester,
        MaterialApp(
          home: Scaffold(
            body: RiderTripDispatchWorkspace(
              controller: riderTripController,
              currentStaff: activeCashier,
              shiftController: shiftController,
            ),
          ),
        ),
      );

      // Verify pending order card
      expect(find.text('Pending Deliveries'), findsOneWidget);
      expect(find.text(order.tokenDisplay), findsOneWidget);
      expect(find.textContaining('COD (Rs. 850)'), findsOneWidget);

      // Select order via checkbox
      final checkbox = find.byType(Checkbox).first;
      await tester.tap(checkbox);
      await tester.pump();

      // Tap Dispatch Rider Trip button
      final dispatchBtn = find.byKey(const ValueKey('dispatch_trip_btn'));
      expect(dispatchBtn, findsOneWidget);
      await tapAndSettle(
        tester,
        dispatchBtn,
        () => find.text('COD: Rs. 850').evaluate().isNotEmpty,
        'dispatched trip to reload',
      );

      // Order should now appear in Active Rider Trips
      expect(find.text('Active Rider Trips'), findsOneWidget);
      expect(find.textContaining('Trip #1'), findsOneWidget);
      expect(find.text('COD: Rs. 850'), findsOneWidget);
      // A database refresh must retain the rider by ID, not Staff identity.
      final riderDropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byKey(const ValueKey('rider_select_dropdown')),
      );
      expect(riderDropdown.initialValue, 3);
    });

    testWidgets('displays Rider Dispatch Alert and allows acknowledgment', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order = (await tester.runAsync(createTestOrder))!;

      await tester.runAsync(() async {
        // Dispatch trip
        await riderTripController.createRiderTrip(
          riderStaffId: 3,
          shiftId: activeShift.id,
          businessDayId: activeShift.businessDayId,
          tripName: 'Trip #1 - Alert Demo',
          orderIds: [order.id],
        );

        // Cancel order while Out for Delivery to trigger dispatch alert
        await orderController.cancelOrder(
          orderId: order.id,
          cashierId: activeCashier.id,
          reason: 'Customer cancelled at door',
          commandId: 'cmd-alert-widget-test',
        );
      });

      await pumpWorkspace(
        tester,
        MaterialApp(
          home: Scaffold(
            body: RiderTripDispatchWorkspace(
              controller: riderTripController,
              currentStaff: activeCashier,
              shiftController: shiftController,
            ),
          ),
        ),
      );

      // Verify high-contrast alert banner
      expect(find.textContaining('RIDER DISPATCH ALERTS'), findsOneWidget);
      expect(find.textContaining('Customer cancelled at door'), findsOneWidget);

      // Tap Acknowledge button
      final ackBtn = find.widgetWithText(ElevatedButton, 'Acknowledge');
      await tapAndSettle(
        tester,
        ackBtn,
        () => find.textContaining('RIDER DISPATCH ALERTS').evaluate().isEmpty,
        'dispatch alert acknowledgment',
      );

      // Alert banner should be dismissed
      expect(find.textContaining('RIDER DISPATCH ALERTS'), findsNothing);
    });

    testWidgets('opens settlement dialog and counts pouch cash to settle trip', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order = (await tester.runAsync(createTestOrder))!;

      final trip = (await tester.runAsync(() async {
        final trip = await riderTripController.createRiderTrip(
          riderStaffId: 3,
          shiftId: activeShift.id,
          businessDayId: activeShift.businessDayId,
          tripName: 'Trip #1 - Settle Demo',
          orderIds: [order.id],
        );

        // Deliver order
        await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order.id);

        return trip;
      }))!;

      await pumpWorkspace(
        tester,
        MaterialApp(
          home: Scaffold(
            body: RiderTripDispatchWorkspace(
              controller: riderTripController,
              currentStaff: activeCashier,
              shiftController: shiftController,
            ),
          ),
        ),
      );

      // Click Settle Trip button
      final settleBtn = find.byKey(ValueKey('settle_trip_btn_${trip.id}'));
      expect(settleBtn, findsOneWidget);
      await tapAndSettle(
        tester,
        settleBtn,
        () => find.byType(RiderTripSettlementDialog).evaluate().isNotEmpty,
        'settlement dialog to open',
      );

      // Dialog opens
      expect(find.byType(RiderTripSettlementDialog), findsOneWidget);
      expect(find.text('Rider Trip Settlement'), findsOneWidget);
      expect(find.text('Expected COD Cash (Pouch):'), findsOneWidget);
      expect(find.byKey(const ValueKey('rider_settlement_actual_time')), findsOneWidget);
      expect(find.byKey(ValueKey('rider_digital_reference_${order.id}')), findsOneWidget);


      // Confirm settlement
      final confirmBtn = find.byKey(const ValueKey('confirm_settlement_btn'));
      expect(confirmBtn, findsOneWidget);
      await tapAndSettle(
        tester,
        confirmBtn,
        () => find.byType(RiderTripSettlementDialog).evaluate().isEmpty &&
            find.text('No active trips currently dispatched.').evaluate().isNotEmpty,
        'settlement to deposit cash and reload trips',
      );

      // Dialog closed and trip completed
      expect(find.byType(RiderTripSettlementDialog), findsNothing);
      expect(find.text('No active trips currently dispatched.'), findsOneWidget);

      // Verify drawer balance increased by Rs. 850
      final expectedCash = await tester.runAsync(
        () => shiftController.calculateExpectedCash(activeShift.id),
      );
      expect(expectedCash, equals(5850.0));
    });
  });
}
