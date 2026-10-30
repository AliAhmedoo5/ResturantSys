import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'package:resturant_sys/core/delivery/rider_trip_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Ticket #78: Recorded delivery reasons, reattempts and safe redaction', () {
    late Directory tempDir;
    late String dbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogAndRecipeController catalogController;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late DeliveryController deliveryController;
    late RiderTripController riderTripController;
    late AuthService authService;

    late int businessDayId;
    late int shiftId;
    const cashierId = 2;
    late int riderStaffId;
    late DeliveryArea gulbergArea;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('delivery_reasons_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      db = await posDb.initialize();

      catalogController = CatalogAndRecipeController(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      deliveryController = DeliveryController(database: db);
      riderTripController = RiderTripController(database: db);
      authService = AuthService(database: db);

      // Seed manager session
      final manager = (await db.query('staff', where: 'id = 1')).single;
      authService.session.login(Staff.fromMap(manager));

      // Open Day and Shift
      businessDayId = await shiftController.openBusinessDay(cashierId);
      shiftId = await shiftController.startShift(
        businessDayId: businessDayId,
        staffId: cashierId,
        openingFloat: 1000.0,
      );

      // Create rider staff
      riderStaffId = await db.insert('staff', {
        'name': 'Test Rider Bilal',
        'role': 'RIDER',
        'pin_hash': 'dummy_hash',
        'is_active': 1,
        'login_enabled': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Create category and menu item
      final category = await catalogController.createCategory(name: 'Burgers');
      final burgerItem = await catalogController.createMenuItem(
        categoryId: category.id,
        name: 'Zinger Burger',
        basePrice: 500.0,
      );
      await catalogController.toggleMenuItemActive(burgerItem.id, true);

      // Create delivery area
      gulbergArea = await deliveryController.saveArea(
        staffId: 1,
        name: 'Gulberg III',
        code: 'GUL3',
        deliveryFeePaisa: 15000,
        minOrderPaisa: 50000,
      );

      // Helper to checkout delivery orders
      Future<int> checkoutDeliveryOrder({required String phone, required String customerName}) async {
        final result = await orderController.checkoutOrder(
          businessDayId: businessDayId,
          shiftId: shiftId,
          cashierId: cashierId,
          diningType: DiningType.delivery,
          items: [CartItem(menuItem: burgerItem, quantity: 1)],
          payments: const [PaymentTender(method: PaymentMethod.cod, amountTendered: 0.0)],
          delivery: DeliveryDetails(
            areaId: gulbergArea.id,
            quotedFeePaisa: gulbergArea.deliveryFeePaisa,
            phone: phone,
            customerName: customerName,
            fullAddress: 'House 12, Street 4, Gulberg III',
          ),
        );
        return result.order.id;
      }

      // Order 1: Will be returned on Trip 1, then re-attempted and delivered on Trip 2
      final order1 = await checkoutDeliveryOrder(phone: '03001234567', customerName: 'Ahmed Ali');
      // Order 2: Will be returned with absent/legacy notes
      final order2 = await checkoutDeliveryOrder(phone: '03219876543', customerName: 'Sara Khan');

      // Trip 1 with Order 1
      final trip1 = await riderTripController.createRiderTrip(
        businessDayId: businessDayId,
        shiftId: shiftId,
        riderStaffId: riderStaffId,
        tripName: 'Trip 1',
        orderIds: [order1],
      );

      // Return Order 1 with reason containing phone number
      await riderTripController.markOrderReturned(
        tripId: trip1.id,
        orderId: order1,
        reason: 'Customer phone 03001234567 was unreachable after 3 attempts',
      );

      // Trip 2 with Order 1 (reattempt) and Order 2 (first attempt)
      final trip2 = await riderTripController.createRiderTrip(
        businessDayId: businessDayId,
        shiftId: shiftId,
        riderStaffId: riderStaffId,
        tripName: 'Trip 2',
        orderIds: [order1, order2],
      );

      // Deliver Order 1 on Trip 2
      await riderTripController.markOrderDelivered(
        tripId: trip2.id,
        orderId: order1,
      );

      // Return Order 2 on Trip 2 with reason
      await riderTripController.markOrderReturned(
        tripId: trip2.id,
        orderId: order2,
        reason: 'Gate locked, customer requested cancellation',
      );

      // Insert a synthetic legacy attempt with null notes directly in DB to simulate older history
      final tripLegacy = await riderTripController.createRiderTrip(
        businessDayId: businessDayId,
        shiftId: shiftId,
        riderStaffId: riderStaffId,
        tripName: 'Trip Legacy',
        orderIds: [],
      );
      await db.insert('rider_trip_orders', {
        'trip_id': tripLegacy.id,
        'order_id': order2,
        'status': 'RETURNED',
        'assigned_at': DateTime.now().toIso8601String(),
        'returned_at': DateTime.now().toIso8601String(),
        'notes': null, // legacy missing evidence
      });
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Analytics separates attempts from unique orders, identifies reattempts, and redacts reasons safely', () async {
      final now = DateTime.now();
      final query = AnalyticsQuery(
        startDate: DateTime(now.year, now.month, now.day),
        endDateExclusive: DateTime(now.year, now.month, now.day + 1),
      );

      final service = AnalyticsService(database: db, authService: authService);
      final snapshot = await service.load(query);

      final deliverySection = snapshot.section(AnalyticsFamily.delivery);

      // Assert metrics
      AnalyticsMetric metric(String id) => deliverySection.metrics.firstWhere((m) => m.id == id);

      expect(metric('unique_attempted_orders').value, 2, reason: '2 unique orders were dispatched');
      expect(metric('reattempted_orders').value, 2, reason: 'Both order1 and order2 had multiple attempts');
      expect(metric('total_reattempts').value, 2, reason: '4 total attempts - 2 unique orders = 2 reattempts');
      expect(metric('returned_attempts').value, 3, reason: '3 return attempts (order1 trip1, order2 trip2, order2 legacy)');
      expect(metric('delivered_attempts').value, 1, reason: '1 delivered attempt (order1 trip2)');

      // Verify attempts contributor rows
      final attemptRows = deliverySection.rows.where((r) => r.sourceType == 'rider_trip_orders').toList();
      expect(attemptRows.length, 4);

      // Safe redaction check: raw phone number 03001234567 MUST be masked
      final order1Attempt1 = attemptRows.firstWhere((r) => r.cells['order_id'] == 1 && r.cells['status'] == 'RETURNED');
      expect(order1Attempt1.cells['return_reason'], contains('[phone masked]'));
      expect(order1Attempt1.cells['return_reason'], isNot(contains('03001234567')));
      expect(order1Attempt1.cells['is_reattempt'], 'No');

      // Order 1 Attempt 2 on Trip 2 is a reattempt
      final order1Attempt2 = attemptRows.firstWhere((r) => r.cells['order_id'] == 1 && r.cells['status'] == 'DELIVERED');
      expect(order1Attempt2.cells['is_reattempt'], 'Yes');
      expect(order1Attempt2.cells['area'], 'Gulberg III');

      // Legacy attempt with null notes discloses absent historical evidence
      final legacyAttempt = attemptRows.firstWhere((r) => r.cells['return_reason'] == 'Absent historical reason evidence');
      expect(legacyAttempt.cells['status'], 'RETURNED');

      // Verify export parity
      final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.delivery);
      expect(csv, contains('[phone masked]'));
      expect(csv, isNot(contains('03001234567')));
      expect(csv, contains('Absent historical reason evidence'));
      expect(csv, contains('Reattempted orders'));
    });
  });
}
