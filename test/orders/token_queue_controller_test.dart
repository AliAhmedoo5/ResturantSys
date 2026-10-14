import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/token_queue_controller.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Token Queue & Kitchen Token Station Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late AuthService authService;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;
    late TokenQueueController tokenQueueController;
    late int businessDayId;
    late int shiftId;
    late int cashierId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_token_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}token_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      final db = await posDb.initialize();

      authService = AuthService(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
      tokenQueueController = TokenQueueController(
        database: db,
        authService: authService,
      );

      // Open business day & shift
      final supStaff = (await authService.authenticateWithPin('1234'))!;
      final bDay = await shiftController.openBusinessDay(openedByStaffId: supStaff.id);
      businessDayId = bDay.id;

      final cashStaff = (await authService.authenticateWithPin('1111'))!;
      cashierId = cashStaff.id;
      final shift = await shiftController.openShift(
        businessDayId: businessDayId,
        staffId: cashierId,
        openingFloat: 5000.0,
      );
      shiftId = shift.id;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('newly checked out order has PREPARING token status by default', () async {
      final order = await orderController.commitSettledOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.dineIn,
        items: [],
        payments: [
          const TenderPayment(
            method: TenderMethod.cash,
            amountTendered: 1000.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(order.tokenNumber, equals(1));
      expect(order.tokenDisplay, equals('#01'));
      expect(order.tokenStatus, equals(TokenStatus.preparing));

      await tokenQueueController.loadTokens(businessDayId: businessDayId);
      expect(tokenQueueController.activeTokens.length, equals(1));
      expect(tokenQueueController.preparingTokens.length, equals(1));
      expect(tokenQueueController.readyTokens.length, equals(0));
      expect(tokenQueueController.deliveredTokens.length, equals(0));
    });

    test('1-tap progression advances token through Preparing -> Ready -> Delivered', () async {
      final order = await orderController.commitSettledOrder(
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        diningType: DiningType.takeaway,
        items: [],
        payments: [
          const TenderPayment(
            method: TenderMethod.cash,
            amountTendered: 500.0,
            changeReturned: 0.0,
          ),
        ],
      );

      await tokenQueueController.loadTokens(businessDayId: businessDayId);
      expect(tokenQueueController.preparingTokens.length, equals(1));

      // 1-tap: Preparing -> Ready
      final step1 = await tokenQueueController.advanceToken(order.id);
      expect(step1, equals(TokenStatus.ready));
      expect(tokenQueueController.preparingTokens.length, equals(0));
      expect(tokenQueueController.readyTokens.length, equals(1));
      expect(tokenQueueController.activeTokens.length, equals(1));

      // 1-tap: Ready -> Delivered
      final step2 = await tokenQueueController.advanceToken(order.id);
      expect(step2, equals(TokenStatus.delivered));
      expect(tokenQueueController.preparingTokens.length, equals(0));
      expect(tokenQueueController.readyTokens.length, equals(0));
      expect(tokenQueueController.activeTokens.length, equals(0));
      expect(tokenQueueController.deliveredTokens.length, equals(1));

      // Attempting further advance throws StateError
      expect(
        () => tokenQueueController.advanceToken(order.id),
        throwsA(isA<StateError>()),
      );
    });

    test('Kitchen station PIN authentication allows Kitchen Cook and Supervisor but rejects Cashier', () async {
      // Kitchen Cook PIN: 2222
      final cookAuth = await tokenQueueController.authenticateKitchenPin('2222');
      expect(cookAuth, isNotNull);
      expect(cookAuth!.canAccessKitchen, isTrue);

      // Supervisor PIN: 1234
      final supAuth = await tokenQueueController.authenticateKitchenPin('1234');
      expect(supAuth, isNotNull);
      expect(supAuth!.canAccessKitchen, isTrue);

      // Cashier PIN: 1111 (cannot access kitchen station)
      final cashierAuth = await tokenQueueController.authenticateKitchenPin('1111');
      expect(cashierAuth, isNull);

      // Unknown PIN
      final invalidAuth = await tokenQueueController.authenticateKitchenPin('9999');
      expect(invalidAuth, isNull);
    });

    test('feature toggles (Token Tray & Cashier Void) persist and toggle correctly', () async {
      // Default state
      expect(await orderController.isTokenTrayEnabled(), isTrue);
      expect(await orderController.isCashierVoidEnabled(), isTrue);

      // Toggle Token Tray off
      await orderController.setTokenTrayEnabled(false);
      expect(await orderController.isTokenTrayEnabled(), isFalse);

      // Toggle Cashier Void off
      await orderController.setCashierVoidEnabled(false);
      expect(await orderController.isCashierVoidEnabled(), isFalse);

      // Toggle back on
      await orderController.setTokenTrayEnabled(true);
      await orderController.setCashierVoidEnabled(true);
      expect(await orderController.isTokenTrayEnabled(), isTrue);
      expect(await orderController.isCashierVoidEnabled(), isTrue);
    });
  });
}
