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

    test('rejects malformed or non-4-digit input', () async {
      expect(await authService.authenticateWithPin('12'), isNull);
      expect(await authService.authenticateWithPin('12345'), isNull);
      expect(await authService.authenticateWithPin('abcd'), isNull);
      expect(await authService.authenticateWithPin(''), isNull);
    });

    test('authenticates cashier and verifies cashier-specific capabilities', () async {
      final db = await posDb.initialize();
      // Insert a front counter cashier with PIN 2222
      final deptResult = await db.query('departments', where: 'name = ?', whereArgs: ['Front Counter']);
      final deptId = deptResult.first['id'] as int;

      await db.insert('staff', {
        'name': 'Hamza Cashier',
        'department_id': deptId,
        'pin_hash': PinHasher.hashPin('2222'),
        'role': 'CASHIER',
        'is_active': 1,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      final staff = await authService.authenticateWithPin('2222');
      expect(staff, isNotNull);
      expect(staff!.name, equals('Hamza Cashier'));
      expect(staff.role, equals(StaffRole.cashier));
      expect(staff.departmentName, equals('Front Counter'));
      expect(staff.canAccessRegister, isTrue);
      expect(staff.canAccessSupervisorPortal, isFalse);
      expect(staff.canAuthorizeOverrides, isFalse);
      expect(staff.canVoidOrders, isFalse);
    });

    test('rejects inactive staff even with correct PIN', () async {
      final db = await posDb.initialize();
      final deptResult = await db.query('departments', where: 'name = ?', whereArgs: ['Kitchen']);
      final deptId = deptResult.first['id'] as int;

      await db.insert('staff', {
        'name': 'Inactive Cook',
        'department_id': deptId,
        'pin_hash': PinHasher.hashPin('3333'),
        'role': 'KITCHEN',
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

      final dummyStaff = Staff(
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
  });
}
