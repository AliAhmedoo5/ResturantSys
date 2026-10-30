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

  group('Ticket #80: Separate verified rider-held cash from customer debt', () {
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
      tempDir = await Directory.systemTemp.createTemp('rider_cash_sep_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      db = await posDb.initialize();

      catalogController = CatalogAndRecipeController(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      deliveryController = DeliveryController(database: db);
      riderTripController = RiderTripController(database: db);
      authService = AuthService(database: db);

      final manager = (await db.query('staff', where: 'id = 1')).single;
      authService.session.login(Staff.fromMap(manager));

      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      businessDayId = day.id;
      final shift = await shiftController.openShift(
        staffId: cashierId,
        openingFloat: 1000.0,
      );
      shiftId = shift.id;

      riderStaffId = await db.insert('staff', {
        'name': 'Test Rider Tariq',
        'department_id': 1,
        'role': 'RIDER',
        'pin_hash': 'dummy_hash',
        'is_active': 1,
        'login_enabled': 0,
        'created_at': DateTime.now().toIso8601String(),
      });

      final category = await catalogController.createCategory(
        name: 'Pizza',
        displayOrder: 1,
        colorHex: '#FFC400',
      );
      final pizzaItem = await catalogController.createMenuItem(
        categoryId: category.id,
        name: 'Fajita Pizza',
        basePrice: 1000.0,
      );
      await catalogController.toggleMenuItemActive(pizzaItem.id, true);

      gulbergArea = await deliveryController.saveArea(
        staffId: 1,
        name: 'Gulberg Main',
        code: 'GULM',
        deliveryFeePaisa: 10000,
        minOrderPaisa: 50000,
      );

      Future<int> checkoutOrder(String phone) async {
        final result = await orderController.checkoutOrder(
          businessDayId: businessDayId,
          shiftId: shiftId,
          cashierId: cashierId,
          diningType: DiningType.delivery,
          items: [CartItem(menuItem: pizzaItem, quantity: 1)],
          payments: const [PaymentTender(method: PaymentMethod.cod, amountTendered: 0.0)],
          delivery: DeliveryDetails(
            areaId: gulbergArea.id,
            quotedFeePaisa: gulbergArea.deliveryFeePaisa,
            phone: phone,
            customerName: 'Customer $phone',
            fullAddress: 'Gulberg Main Blvd',
          ),
        );
        return result.order.id;
      }

      // Order 1: 1000 + 100 fee = 110000 paisa
      final order1 = await checkoutOrder('03011112233');
      // Order 2: 1000 + 100 fee = 110000 paisa
      final order2 = await checkoutOrder('03022223344');

      final trip = await riderTripController.createRiderTrip(
        businessDayId: businessDayId,
        shiftId: shiftId,
        riderStaffId: riderStaffId,
        tripName: 'Trip 1',
        orderIds: [order1, order2],
      );

      await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order1);
      await riderTripController.markOrderDelivered(tripId: trip.id, orderId: order2);

      // Confirm collection for order1 only (rider collected 110000 paisa from customer 1)
      await riderTripController.confirmCustomerCollection(
        tripId: trip.id,
        orderId: order1,
        cashierStaffId: cashierId,
      );
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Confirmed customer collection creates rider-held cash separate from customer debt and drawer cash', () async {
      final now = DateTime.now();
      final query = AnalyticsQuery(
        startDate: DateTime(now.year, now.month, now.day),
        endDateExclusive: DateTime(now.year, now.month, now.day + 1),
      );

      final service = AnalyticsService(database: db, authService: authService);
      var snapshot = await service.load(query);
      var deliverySection = snapshot.section(AnalyticsFamily.delivery);

      AnalyticsMetric metric(String id) => deliverySection.metrics.firstWhere((m) => m.id == id);

      // Order 1 is confirmed collected -> Rider-held cash = 110000 paisa
      // Order 2 is delivered but NOT confirmed collected -> Customer debt (Collection Due) = 110000 paisa
      // Drawer cash accepted from rider handover = 0 (not yet handed over)
      expect(metric('collection_due').value, 110000, reason: 'Order 2 remains customer debt');
      expect(metric('rider_held_cash').value, 110000, reason: 'Order 1 is confirmed collected, held by rider');
      expect(metric('accepted_drawer_cash').value, 0, reason: 'No cash handed over to drawer yet');

      // Now settle trip with counted cash: Rider hands over Rs. 2000 (200000 paisa)
      // Since order 2 was COD, settle converts order 2 to settled.
      // Expected COD was 220000 paisa, counted is 200000 paisa -> shortage of 20000 paisa.
      await riderTripController.settleRiderTrip(
        tripId: 1,
        cashierStaffId: cashierId,
        shiftId: shiftId,
        cashCountedPaisa: 200000, // 20000 shortage against 220000
      );

      snapshot = await service.load(query);
      deliverySection = snapshot.section(AnalyticsFamily.delivery);

      expect(metric('collection_due').value, 0, reason: 'All orders on settled trip are now settled');
      expect(metric('rider_held_cash').value, 0, reason: 'Active trip is settled; no active rider-held cash');
      expect(metric('accepted_drawer_cash').value, 200000, reason: 'Accepted pouch handover cash in till');
      expect(metric('rider_shortages').value, 20000, reason: 'Recorded shortage evidence');

      // Export check
      final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.delivery);
      expect(csv, contains('Accepted rider drawer cash'));
      expect(csv, contains('Rider-held cash'));
      expect(csv, contains('Rider settlement shortage'));
    });
  });
}
