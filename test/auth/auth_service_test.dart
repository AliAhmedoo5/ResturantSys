import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('AuthService & Staff Capabilities Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late AuthService authService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_auth_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}auth_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
        seedDefaultStaff: true,
      );
      final db = await posDb.initialize();
      authService = AuthService(database: db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('authenticates default seeded supervisor with default PIN 1234', () async {
      final staff = await authService.authenticateWithPin('1234');

      expect(staff, isNotNull);
      expect(staff!.name, equals(PosDatabaseConstants.defaultSupervisorName));
      expect(staff.role, equals(StaffRole.supervisor));
      expect(staff.departmentName, equals('Management'));
      expect(staff.canAccessSupervisorPortal, isTrue);
      expect(staff.canAuthorizeOverrides, isTrue);
      expect(staff.canVoidOrders, isTrue);
    });

    test('rejects incorrect 4-digit PIN', () async {
      final staff = await authService.authenticateWithPin('9999');
      expect(staff, isNull);
    });

    test('rejects malformed or invalid length input', () async {
      expect(await authService.authenticateWithPin('12'), isNull);
      expect(await authService.authenticateWithPin('123456789'), isNull);
      expect(await authService.authenticateWithPin('abcd'), isNull);
      expect(await authService.authenticateWithPin(''), isNull);
    });

    test('authenticates default seeded cashier (PIN 1111) and verifies cashier capabilities', () async {
      final staff = await authService.authenticateWithPin('1111');
      expect(staff, isNotNull);
      expect(staff!.name, equals(PosDatabaseConstants.defaultCashierName));
      expect(staff.role, equals(StaffRole.cashier));
      expect(staff.departmentName, equals('Front Counter'));
      expect(staff.canAccessRegister, isTrue);
      expect(staff.canAccessSupervisorPortal, isFalse);
      expect(staff.canAuthorizeOverrides, isFalse);
      expect(staff.canVoidOrders, isFalse);
    });

    test('verifies interactive kitchen role is eliminated and manager handles back-office', () async {
      expect(StaffRole.values.length, equals(2));
      expect(StaffRole.values, contains(StaffRole.cashier));
      expect(StaffRole.values, contains(StaffRole.manager));
      expect(await authService.authenticateWithPin('2222'), isNull);
    });

    test('legacy kitchen credentials cannot log in as a cashier', () async {
      final db = await posDb.initialize();
      await db.insert('staff', {
        'name': 'Legacy Kitchen',
        'department_id': 2,
        'pin_hash': PinHasher.hashPin('5678'),
        'role': 'KITCHEN',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(await authService.authenticateAndLogin('5678'), isNull);
      expect(authService.session.isAuthenticated, isFalse);
    });

    test('authenticateAndLogin establishes active session on authService.session', () async {
      expect(authService.session.isAuthenticated, isFalse);
      final staff = await authService.authenticateAndLogin('1234');
      expect(staff, isNotNull);
      expect(authService.session.isAuthenticated, isTrue);
      expect(authService.session.currentStaff?.id, equals(staff!.id));
    });

    test('rejects inactive staff even with correct PIN', () async {
      final db = await posDb.initialize();
      final deptResult = await db.query('departments', where: 'name = ?', whereArgs: ['Kitchen']);
      final deptId = deptResult.first['id'] as int;

      await db.insert('staff', {
        'name': 'Inactive Cashier',
        'department_id': deptId,
        'pin_hash': PinHasher.hashPin('3333'),
        'role': 'CASHIER',
        'is_active': 0, // Inactive
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final staff = await authService.authenticateWithPin('3333');
      expect(staff, isNull);
    });

    test('manages active session state correctly (login and lock)', () {
      final session = authService.session;
      expect(session.isAuthenticated, isFalse);
      expect(session.currentStaff, isNull);

      const dummyStaff = Staff(
        id: 1,
        name: 'Test Staff',
        departmentId: 1,
        departmentName: 'Front Counter',
        pinHash: 'dummy',
        role: StaffRole.cashier,
        isActive: true,
      );

      session.login(dummyStaff);
      expect(session.isAuthenticated, isTrue);
      expect(session.currentStaff?.name, equals('Test Staff'));

      session.lock();
      expect(session.isAuthenticated, isFalse);
      expect(session.currentStaff, isNull);
    });

    test('authenticateSupervisorPin validates supervisor and does not alter cashier session', () async {
      // 1. Log in as cashier
      final cashier = await authService.authenticateAndLogin('1111');
      expect(cashier, isNotNull);
      expect(authService.session.currentStaff?.id, equals(cashier!.id));

      // 2. Kitchen cook PIN cannot authorize supervisor voids
      final rejectedCook = await authService.authenticateSupervisorPin('2222');
      expect(rejectedCook, isNull);
      expect(authService.session.currentStaff?.id, equals(cashier.id)); // Cashier stays logged in!

      // 3. Cashier cannot authorize supervisor voids
      final rejectedCashier = await authService.authenticateSupervisorPin('1111');
      expect(rejectedCashier, isNull);
      expect(authService.session.currentStaff?.id, equals(cashier.id));

      // 4. Invalid PIN returns null
      final rejectedInvalid = await authService.authenticateSupervisorPin('9999');
      expect(rejectedInvalid, isNull);
      expect(authService.session.currentStaff?.id, equals(cashier.id));

      // 5. Supervisor PIN authorizes successfully without logging cashier out
      final supervisor = await authService.authenticateSupervisorPin('1234');
      expect(supervisor, isNotNull);
      expect(supervisor!.role, equals(StaffRole.supervisor));
      expect(supervisor.canVoidOrders, isTrue);
      expect(authService.session.currentStaff?.id, equals(cashier.id)); // Still logged in as cashier!
    });
  });
}
