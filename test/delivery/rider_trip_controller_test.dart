import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'package:resturant_sys/core/delivery/rider_trip.dart';
import 'package:resturant_sys/core/delivery/rider_trip_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Rider Trips, Dispatch Alerts & Settlement Lock Boundary Suite', () {
    late Directory tempDir;
    late String dbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogAndRecipeController catalogController;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late DeliveryController deliveryController;
    late RiderTripController riderTripController;

    late int businessDayId;
    late int shiftId;
    const cashierId = 2; // Default seeded cashier
    late int riderStaffId;
    late MenuItem burgerItem;
    late DeliveryArea gulbergArea;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rider_trip_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      db = await posDb.initialize();

      catalogController = CatalogAndRecipeController(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      deliveryController = DeliveryController(database: db);
      riderTripController = RiderTripController(database: db);

      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      businessDayId = day.id;

      final shift = await shiftController.openShift(
        businessDayId: businessDayId,
        staffId: cashierId,
        openingFloat: 5000.0,
      );
      shiftId = shift.id;

      // Create Rider staff
      riderStaffId = await db.insert('staff', {
        'name': 'Kamran Rider',
        'pin_hash': 'dummy_hash',
        'salt': 'dummy_salt',
        'role': 'CASHIER',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Setup Catalog & Recipe Gate
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

      // Create Delivery Area
      gulbergArea = await deliveryController.saveArea(
        staffId: 1,
        name: 'Gulberg III',
        code: 'GUL3',
        deliveryFeePaisa: 15000, // Rs. 150
        minOrderPaisa: 50000,
      );
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<Order> createTestDeliveryOrder({
      required String phone,
      required bool isCod,
      int quantity = 1,
    }) async {
      final cartItem = CartItem(
        menuItem: burgerItem,
        quantity: quantity,
      );

      final deliveryDetails = DeliveryDetails(
        areaId: gulbergArea.id,
        quotedFeePaisa: gulbergArea.deliveryFeePaisa,
        phone: phone,
        customerName: 'Customer $phone',
        fullAddress: 'Street 5, House 12, Gulberg III',
      );

      final List<PaymentTender> tenders;
      if (isCod) {
        tenders = [const PaymentTender(method: PaymentMethod.cod, amountTendered: 0.0)];
      } else {
        // Grand total: Rs. 650 * quantity + Rs. 150 delivery fee
        final totalDue = (650.0 * quantity) + 150.0;
        tenders = [PaymentTender(method: PaymentMethod.cash, amountTendered: totalDue)];
      }

      return await orderController.checkout(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.delivery,
        items: [cartItem],
        payments: tenders,
        delivery: deliveryDetails,
      );
    }

    test('1. Delivery orders can be batched and assigned to named rider trips', () async {
      final order1 = await createTestDeliveryOrder(phone: '03001234567', isCod: true);
      final order2 = await createTestDeliveryOrder(phone: '03007654321', isCod: true);

      // Expected cash = (Rs. 650 + Rs. 150) * 2 = Rs. 800 * 2 = Rs. 1600 = 160000 paisa
      final trip = await riderTripController.createRiderTrip(
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        tripName: 'Trip #1 - Gulberg Lunch Rush',
        orderIds: [order1.id, order2.id],
      );

      expect(trip.id, isPositive);
      expect(trip.tripName, equals('Trip #1 - Gulberg Lunch Rush'));
      expect(trip.riderStaffId, equals(riderStaffId));
      expect(trip.isDispatched, isTrue);
      expect(trip.cashExpectedPaisa, equals(160000));
      expect(trip.orders.length, equals(2));

      // Verify orders transitioned to TokenStatus.outForDelivery
      final updatedOrder1 = await orderController.getOrder(order1.id);
      final updatedOrder2 = await orderController.getOrder(order2.id);
      expect(updatedOrder1.tokenStatus, equals(TokenStatus.outForDelivery));
      expect(updatedOrder2.tokenStatus, equals(TokenStatus.outForDelivery));

      // Cannot assign already dispatched order to another active trip
      expect(
        () => riderTripController.createRiderTrip(
          riderStaffId: riderStaffId,
          shiftId: shiftId,
          businessDayId: businessDayId,
          tripName: 'Trip #2',
          orderIds: [order1.id],
        ),
        throwsStateError,
      );
    });

    test('2. Delivered COD orders strictly remain in Collection Due status until trip settlement', () async {
      final order = await createTestDeliveryOrder(phone: '03001112233', isCod: true);
      expect(order.paymentStatus, equals('COLLECTION_DUE'));

      final trip = await riderTripController.createRiderTrip(
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        tripName: 'Trip #2 - Express',
        orderIds: [order.id],
      );

      // Rider physically delivers the order
      await riderTripController.markOrderDelivered(
        tripId: trip.id,
        orderId: order.id,
      );

      final deliveredOrder = await orderController.getOrder(order.id);
      expect(deliveredOrder.tokenStatus, equals(TokenStatus.delivered));
      // CRITICAL INVARIANT: Delivery does NOT mark paid!
      expect(deliveredOrder.paymentStatus, equals('COLLECTION_DUE'));
      expect(deliveredOrder.isSettled, isFalse);

      // Drawer cash sales must NOT include this unpaid COD delivery
      final cashSales = await shiftController.calculateCashSales(shiftId);
      expect(cashSales, equals(0.0));
    });

    test('3. Modifying or cancelling an order in Out for Delivery triggers an auditable dispatch alert', () async {
      final order = await createTestDeliveryOrder(phone: '03009998877', isCod: true);

      final trip = await riderTripController.createRiderTrip(
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        tripName: 'Trip #3 - Alert Test',
        orderIds: [order.id],
      );
      expect(trip.cashExpectedPaisa, equals(80000)); // Rs. 800

      // Cashier autonomously cancels the order while Out for Delivery
      await orderController.cancelOrder(
        orderId: order.id,
        cashierId: cashierId,
        reason: 'Customer called: duplicate order, please cancel',
        commandId: 'cmd-cancel-out-for-delivery-1',
      );

      // Trip must now have an unacknowledged Rider Dispatch Alert
      final reloadedTrip = await riderTripController.getTrip(trip.id);
      expect(reloadedTrip.hasActiveAlerts, isTrue);
      expect(reloadedTrip.unacknowledgedAlertsCount, equals(1));

      final alert = reloadedTrip.alerts.first;
      expect(alert.alertType, equals('ORDER_CANCELLED'));
      expect(alert.message, contains('Customer called: duplicate order'));
      expect(alert.isAcknowledged, isFalse);

      // COD cash expected for this cancelled order must be updated to 0
      expect(reloadedTrip.cashExpectedPaisa, equals(0));

      // Cashier acknowledges the alert
      await riderTripController.acknowledgeDispatchAlert(
        alertId: alert.id,
        staffId: cashierId,
      );

      final reloadedTrip2 = await riderTripController.getTrip(trip.id);
      expect(reloadedTrip2.hasActiveAlerts, isFalse);
    });

    test('4. Rider trip settlement counts physical cash into cashier shift drawer and marks orders Settled', () async {
      final order1 = await createTestDeliveryOrder(phone: '03005554433', isCod: true);
      final order2 = await createTestDeliveryOrder(phone: '03006667788', isCod: true);

      final trip = await riderTripController.createRiderTrip(
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        tripName: 'Trip #4 - Pouch Handover',
        orderIds: [order1.id, order2.id],
      );
      expect(trip.cashExpectedPaisa, equals(160000)); // Rs. 1600

      // Rider delivers both orders
      await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order1.id);
      await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order2.id);

      // Prior to settlement: drawer expected cash equals opening float only
      final expectedCashBefore = await shiftController.calculateExpectedCash(shiftId);
      expect(expectedCashBefore, equals(5000.0));

      // Rider returns to store. Cashier counts Rs. 1600 from pouch and executes settlement
      final settledTrip = await riderTripController.settleRiderTrip(
        tripId: trip.id,
        cashierStaffId: cashierId,
        shiftId: shiftId,
        cashCountedPaisa: 160000, // Rs. 1600
        notes: 'Pouch count exact, all delivered',
      );

      expect(settledTrip.isSettled, isTrue);
      expect(settledTrip.cashCollectedPaisa, equals(160000));

      // Orders must now be SETTLED
      final settledOrder1 = await orderController.getOrder(order1.id);
      final settledOrder2 = await orderController.getOrder(order2.id);
      expect(settledOrder1.paymentStatus, equals('SETTLED'));
      expect(settledOrder2.paymentStatus, equals('SETTLED'));

      // Cash movement was recorded into the active shift drawer
      final movements = await shiftController.getCashMovements(shiftId);
      expect(movements.any((m) => m.category == 'Rider Settlement' && m.amount == 1600.0), isTrue);

      // Drawer expected cash is now 5000 + 1600 = 6600
      final expectedCashAfter = await shiftController.calculateExpectedCash(shiftId);
      expect(expectedCashAfter, equals(6600.0));
    });

    test('5. Settled rider trips strictly reject subsequent direct line revisions or cancellations', () async {
      final order = await createTestDeliveryOrder(phone: '03004443322', isCod: true);

      final trip = await riderTripController.createRiderTrip(
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        tripName: 'Trip #5 - Lock Test',
        orderIds: [order.id],
      );

      await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order.id);

      await riderTripController.settleRiderTrip(
        tripId: trip.id,
        cashierStaffId: cashierId,
        shiftId: shiftId,
        cashCountedPaisa: 80000,
      );

      // Attempting revision on an order whose trip is settled MUST throw StateError
      expect(
        () => orderController.reviseOrder(
          orderId: order.id,
          cashierId: cashierId,
          reason: 'Attempt late edit after rider settlement',
          commandId: 'cmd-illegal-revision',
          newItems: [CartItem(menuItem: burgerItem, quantity: 2)],
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Associated rider trip is settled and locked'),
        )),
      );

      // Attempting cancellation on an order whose trip is settled MUST throw StateError
      expect(
        () => orderController.cancelOrder(
          orderId: order.id,
          cashierId: cashierId,
          reason: 'Attempt late cancel after rider settlement',
          commandId: 'cmd-illegal-cancel',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Associated rider trip is settled and locked'),
        )),
      );
    });

    test('6. Returned undelivered orders remain editable until trip settlement', () async {
      final order = await createTestDeliveryOrder(phone: '03001239999', isCod: true);

      final trip = await riderTripController.createRiderTrip(
        riderStaffId: riderStaffId,
        shiftId: shiftId,
        businessDayId: businessDayId,
        tripName: 'Trip #6 - Return Test',
        orderIds: [order.id],
      );

      // Rider returns undelivered order (e.g. customer phone unreachable)
      await riderTripController.markOrderReturned(
        tripId: trip.id,
        orderId: order.id,
        reason: 'Customer phone switched off at gate',
      );

      final reloadedTrip = await riderTripController.getTrip(trip.id);
      expect(reloadedTrip.cashExpectedPaisa, equals(0)); // COD expected cash cleared

      // Order is returned, but trip is NOT yet settled. Order MUST remain editable!
      final revision = await orderController.reviseOrder(
        orderId: order.id,
        cashierId: cashierId,
        reason: 'Customer called back, updated order to 2 burgers',
        commandId: 'cmd-revise-returned-order',
        newItems: [CartItem(menuItem: burgerItem, quantity: 2)],
      );

      expect(revision.action, equals('CHANGE'));
      final revisedOrder = await orderController.getOrder(order.id);
      expect(revisedOrder.items.single.quantity, equals(2));

      // Now settle the trip (0 cash collected for this returned order)
      await riderTripController.settleRiderTrip(
        tripId: trip.id,
        cashierStaffId: cashierId,
        shiftId: shiftId,
        cashCountedPaisa: 0,
      );

      // Once the trip is settled, the returned order is locked as well!
      expect(
        () => orderController.cancelOrder(
          orderId: order.id,
          cashierId: cashierId,
          reason: 'Attempt cancel after trip settlement',
          commandId: 'cmd-cancel-after-settlement',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Associated rider trip is settled and locked'),
        )),
      );
    });
  });
}
