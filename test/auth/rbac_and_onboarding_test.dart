import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Seam 1: StaffRole Domain & Two-Role RBAC Model', () {
    test('StaffRole enum contains exactly two interactive roles: CASHIER and MANAGER', () {
      expect(StaffRole.values.length, equals(2));
      expect(StaffRole.values, contains(StaffRole.cashier));
      expect(StaffRole.values, contains(StaffRole.manager));
    });

    test('Supervisor and Owner are identical aliases of Manager', () {
      expect(StaffRole.supervisor, equals(StaffRole.manager));
      expect(StaffRole.owner, equals(StaffRole.manager));
      expect(StaffRole.fromCode('SUPERVISOR'), equals(StaffRole.manager));
      expect(StaffRole.fromCode('OWNER'), equals(StaffRole.manager));
      expect(StaffRole.fromCode('MANAGER'), equals(StaffRole.manager));
      expect(StaffRole.fromCode('CASHIER'), equals(StaffRole.cashier));
      expect(StaffRole.fromCode('kitchen'), equals(StaffRole.cashier)); // fallback
    });

    test('Staff role-based capabilities enforce strict two-role separation', () {
      const cashier = Staff(
        id: 1,
        name: 'Ali Cashier',
        departmentId: 1,
        pinHash: 'hash1',
        role: StaffRole.cashier,
        isActive: true,
      );

      const manager = Staff(
        id: 2,
        name: 'Boss Manager',
        departmentId: 2,
        pinHash: 'hash2',
        role: StaffRole.manager,
        isActive: true,
      );

      // Cashier permissions
      expect(cashier.canAccessRegister, isTrue);
      expect(cashier.canAccessSupervisorPortal, isFalse);
      expect(cashier.canAuthorizeOverrides, isFalse);
      expect(cashier.canVoidOrders, isFalse);
      expect(cashier.canPerformZReport, isFalse);

      // Manager permissions (hard-blocked from register)
      expect(manager.canAccessRegister, isFalse);
      expect(manager.canAccessSupervisorPortal, isTrue);
      expect(manager.canAuthorizeOverrides, isTrue);
      expect(manager.canVoidOrders, isTrue);
      expect(manager.canPerformZReport, isTrue);
    });
  });

  group('Seam 2: Controller & Service Hard-Blocked Authorization Boundary', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;
    late OrderAndCheckoutController orderController;
    late ShiftAndCashController shiftController;

    late Staff testManager;
    late Staff testCashier;
    late int activeDayId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_rbac_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}rbac_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
        seedDefaultStaff: false,
      );
      db = await posDb.initialize();
      authService = AuthService(database: db);
      orderController = OrderAndCheckoutController(database: db);
      shiftController = ShiftAndCashController(database: db);

      // Register Manager (with 6-digit PIN)
      testManager = await authService.registerStaff(
        name: 'Asad Manager',
        departmentId: 3, // Management
        role: StaffRole.manager,
        pin: '123456',
      );

      // Register Cashier (with 4-digit PIN)
      testCashier = await authService.registerStaff(
        name: 'Bilal Cashier',
        departmentId: 1, // Front Counter
        role: StaffRole.cashier,
        pin: '4321',
      );

      // Manager opens the business day
      final day = await shiftController.openBusinessDay(openedByStaffId: testManager.id);
      activeDayId = day.id;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('AuthService supports 4-8 digit PINs for managers and 4 digits for cashiers', () async {
      // Authenticate manager with 6-digit PIN
      final authedManager = await authService.authenticateWithPin('123456');
      expect(authedManager, isNotNull);
      expect(authedManager!.id, equals(testManager.id));
      expect(authedManager.role, equals(StaffRole.manager));

      // Authenticate cashier with 4-digit PIN
      final authedCashier = await authService.authenticateWithPin('4321');
      expect(authedCashier, isNotNull);
      expect(authedCashier!.id, equals(testCashier.id));
      expect(authedCashier.role, equals(StaffRole.cashier));

      // Rejects invalid PIN formats
      expect(
        () => authService.registerStaff(
          name: 'Invalid Cashier',
          departmentId: 1,
          role: StaffRole.cashier,
          pin: '12345', // 5 digits invalid for cashier
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => authService.registerStaff(
          name: 'Invalid Manager',
          departmentId: 3,
          role: StaffRole.manager,
          pin: '123456789', // 9 digits invalid for manager
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ShiftAndCashController strictly rejects Manager from opening a cashier shift', () async {
      // Manager attempts to open shift -> must throw StateError with authorization failure
      expect(
        () => shiftController.openShift(
          staffId: testManager.id,
          openingFloat: 1000.0,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Authorization error'),
          ),
        ),
      );

      // Cashier successfully opens shift
      final shift = await shiftController.openShift(
        staffId: testCashier.id,
        openingFloat: 1000.0,
      );
      expect(shift.id, isPositive);
      expect(shift.staffId, equals(testCashier.id));
    });

    test('ShiftAndCashController strictly rejects Manager from recording cash drawer movements', () async {
      final shift = await shiftController.openShift(
        staffId: testCashier.id,
        openingFloat: 1000.0,
      );

      // Manager attempts to record petty cash movement -> must throw StateError
      expect(
        () => shiftController.recordCashMovement(
          shiftId: shift.id,
          staffId: testManager.id,
          type: CashMovementType.payOut,
          amount: 200.0,
          category: 'Supplies',
          notes: 'Milk emergency',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Authorization error'),
          ),
        ),
      );

      // Cashier records movement -> succeeds
      final movement = await shiftController.recordCashMovement(
        shiftId: shift.id,
        staffId: testCashier.id,
        type: CashMovementType.payOut,
        amount: 200.0,
        category: 'Supplies',
        notes: 'Milk emergency',
      );
      expect(movement.id, isPositive);
    });

    test('OrderAndCheckoutController strictly rejects Manager from initiating checkout', () async {
      final shift = await shiftController.openShift(
        staffId: testCashier.id,
        openingFloat: 1000.0,
      );

      final catId = await db.insert(PosDatabaseConstants.tableCategories, {
        'name': 'Burgers',
        'display_order': 0,
        'color_hex': '#245C40',
        'created_at': DateTime.now().toIso8601String(),
      });
      final itemId = await db.insert(PosDatabaseConstants.tableMenuItems, {
        'category_id': catId,
        'name': 'Test Burger',
        'base_price': 500.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });

      final dummyItem = MenuItem(
        id: itemId,
        categoryId: catId,
        name: 'Test Burger',
        basePrice: 500.0,
        isActive: true,
        isTaxInclusive: true,
        taxRate: 0.0,
      );

      final cartItems = [CartItem(menuItem: dummyItem, quantity: 1)];
      final tenders = [
        const PaymentTender(
          method: PaymentMethod.cash,
          amountTendered: 500.0,
        ),
      ];

      // Manager attempts checkout -> must throw StateError
      expect(
        () => orderController.checkoutOrder(
          businessDayId: activeDayId,
          shiftId: shift.id,
          cashierId: testManager.id,
          diningType: DiningType.dineIn,
          items: cartItems,
          payments: tenders,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Authorization error'),
          ),
        ),
      );

      // Cashier checkout -> succeeds
      final result = await orderController.checkoutOrder(
        businessDayId: activeDayId,
        shiftId: shift.id,
        cashierId: testCashier.id,
        diningType: DiningType.dineIn,
        items: cartItems,
        payments: tenders,
      );
      expect(result.order.id, isPositive);
      expect(result.order.cashierId, equals(testCashier.id));
    });

    test('ShiftAndCashController rejects Cashier from opening or closing a Business Day', () async {
      // Cashier attempts to open another business day -> throws authorization StateError
      expect(
        () => shiftController.openBusinessDay(openedByStaffId: testCashier.id),
        throwsA(isA<StateError>()),
      );

      // Cashier attempts to close business day -> throws authorization StateError
      expect(
        () => shiftController.closeBusinessDay(
          closedByStaffId: testCashier.id,
          autoLockActiveShifts: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Authorization error'),
          ),
        ),
      );
    });

    test('AuthService.isOnboardingRequired detects clean uninitialized database', () async {
      // Currently has manager + cashier, so not uninitialized once completed
      await db.insert(
        PosDatabaseConstants.tableSystemSettings,
        {
          'key': PosDatabaseConstants.settingOnboardingCompleted,
          'value': 'true',
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(await authService.isOnboardingRequired(), isFalse);

      // If all cashiers deactivated -> onboarding / cashier requirement flagged
      await authService.updateStaffActiveStatus(staffId: testCashier.id, isActive: false);
      expect(await authService.hasActiveCashier(), isFalse);
    });
  });
}
