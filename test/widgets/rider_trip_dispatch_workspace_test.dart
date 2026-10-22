import 'dart:io';
import 'package:flutter/material.dart';
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
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/widgets/delivery/rider_trip_dispatch_workspace.dart';
import 'package:resturant_sys/widgets/delivery/rider_trip_settlement_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('RiderTripDispatchWorkspace Widget Tests', () {
    late Directory tempDir;
    late String dbPath;
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
      tempDir = await Directory.systemTemp.createTemp('rider_trip_widget_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
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
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<Order> createTestOrder() async {
      final result = await orderController.checkoutOrder(
        businessDayId: activeShift.businessDayId,
        shiftId: activeShift.id,
        cashierId: activeCashier.id,
        diningType: DiningType.delivery,
        items: [CartItem(menuItem: burgerItem, quantity: 1)],
        payments: const [PaymentTender(method: PaymentMethod.cod, amountTendered: 0)],
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

    testWidgets('renders pending orders and batches into a new trip', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final order = await createTestOrder();

      await tester.pumpWidget(
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
      await tester.pumpAndSettle();

      // Verify pending order card
      expect(find.text('Pending Deliveries'), findsOneWidget);
      expect(find.text(order.tokenDisplay), findsOneWidget);
      expect(find.textContaining('COD (Rs. 850)'), findsOneWidget);

      // Select order via checkbox
      final checkbox = find.byType(Checkbox).first;
      await tester.tap(checkbox);
      await tester.pumpAndSettle();

      // Tap Dispatch Rider Trip button
      final dispatchBtn = find.byKey(const ValueKey('dispatch_trip_btn'));
      expect(dispatchBtn, findsOneWidget);
      await tester.tap(dispatchBtn);
      await tester.pumpAndSettle();

      // Order should now appear in Active Rider Trips
      expect(find.text('Active Rider Trips'), findsOneWidget);
      expect(find.textContaining('Trip #1'), findsOneWidget);
      expect(find.text('COD: Rs. 850'), findsOneWidget);
    });

    testWidgets('displays Rider Dispatch Alert and allows acknowledgment', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final order = await createTestOrder();

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

      await tester.pumpWidget(
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
      await tester.pumpAndSettle();

      // Verify high-contrast alert banner
      expect(find.textContaining('RIDER DISPATCH ALERTS'), findsOneWidget);
      expect(find.textContaining('Customer cancelled at door'), findsOneWidget);

      // Tap Acknowledge button
      final ackBtn = find.widgetWithText(ElevatedButton, 'Acknowledge');
      await tester.tap(ackBtn);
      await tester.pumpAndSettle();

      // Alert banner should be dismissed
      expect(find.textContaining('RIDER DISPATCH ALERTS'), findsNothing);
    });

    testWidgets('opens settlement dialog and counts pouch cash to settle trip', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final order = await createTestOrder();

      final trip = await riderTripController.createRiderTrip(
        riderStaffId: 3,
        shiftId: activeShift.id,
        businessDayId: activeShift.businessDayId,
        tripName: 'Trip #1 - Settle Demo',
        orderIds: [order.id],
      );

      // Deliver order
      await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order.id);

      await tester.pumpWidget(
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
      await tester.pumpAndSettle();

      // Click Settle Trip button
      final settleBtn = find.byKey(ValueKey('settle_trip_btn_${trip.id}'));
      expect(settleBtn, findsOneWidget);
      await tester.tap(settleBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.byType(RiderTripSettlementDialog), findsOneWidget);
      expect(find.text('Rider Trip Settlement'), findsOneWidget);
      expect(find.text('Expected COD Cash (Pouch):'), findsOneWidget);

      // Confirm settlement
      final confirmBtn = find.byKey(const ValueKey('confirm_settlement_btn'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Dialog closed and trip completed
      expect(find.byType(RiderTripSettlementDialog), findsNothing);
      expect(find.text('No active trips currently dispatched.'), findsOneWidget);

      // Verify drawer balance increased by Rs. 850
      final expectedCash = await shiftController.calculateExpectedCash(activeShift.id);
      expect(expectedCash, equals(5850.0));
    });
  });
}
