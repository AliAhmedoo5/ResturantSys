import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Universal Staff & Department Directory Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late AuthService authService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_dept_staff_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}staff_test.db';
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

    test('creates custom departments and lists all departments', () async {
      final initialDepartments = await authService.getDepartments();
      expect(initialDepartments.length, greaterThanOrEqualTo(3));

      final ridersDept = await authService.createDepartment('Riders');
      expect(ridersDept.id, isPositive);
      expect(ridersDept.name, equals('Riders'));

      final updatedDepartments = await authService.getDepartments();
      expect(updatedDepartments.any((d) => d.name == 'Riders'), isTrue);
    });

    test('rejects blank department name or duplicate department name', () async {
      expect(
        () => authService.createDepartment('   '),
        throwsA(isA<ArgumentError>()),
      );

      await authService.createDepartment('Delivery');
      expect(
        () => authService.createDepartment('Delivery'),
        throwsA(isA<Exception>()),
      );
    });

    test('registers new staff member with 4-digit PIN and verifies authentication', () async {
      final depts = await authService.getDepartments();
      final frontCounterDept = depts.firstWhere((d) => d.name == 'Front Counter');

      final newStaff = await authService.registerStaff(
        name: 'Ahmad Bilal',
        departmentId: frontCounterDept.id,
        role: StaffRole.cashier,
        pin: '5555',
      );

      expect(newStaff.id, isPositive);
      expect(newStaff.name, equals('Ahmad Bilal'));
      expect(newStaff.departmentName, equals('Front Counter'));
      expect(newStaff.role, equals(StaffRole.cashier));
      expect(newStaff.isActive, isTrue);

      final authenticated = await authService.authenticateWithPin('5555');
      expect(authenticated, isNotNull);
      expect(authenticated!.id, equals(newStaff.id));
      expect(authenticated.name, equals('Ahmad Bilal'));
    });

    test('rejects registration with invalid PIN or duplicate PIN', () async {
      final depts = await authService.getDepartments();
      final deptId = depts.first.id;

      expect(
        () => authService.registerStaff(
          name: 'Invalid Pin Staff',
          departmentId: deptId,
          role: StaffRole.cashier,
          pin: '123', // only 3 digits
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () => authService.registerStaff(
          name: 'Alpha Pin Staff',
          departmentId: deptId,
          role: StaffRole.cashier,
          pin: 'abcd',
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Default supervisor uses PIN '1234'
      expect(
        () => authService.registerStaff(
          name: 'Duplicate Pin Staff',
          departmentId: deptId,
          role: StaffRole.cashier,
          pin: '1234',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('updates staff PIN and verifies old PIN is invalidated while new PIN works', () async {
      final depts = await authService.getDepartments();
      final kitchenDept = depts.firstWhere((d) => d.name == 'Kitchen');

      final staff = await authService.registerStaff(
        name: 'Tariq Chef',
        departmentId: kitchenDept.id,
        role: StaffRole.kitchen,
        pin: '4444',
      );

      final updateSuccess = await authService.updateStaffPin(
        staffId: staff.id,
        newPin: '7777',
      );
      expect(updateSuccess, isTrue);

      expect(await authService.authenticateWithPin('4444'), isNull);

      final authenticatedNew = await authService.authenticateWithPin('7777');
      expect(authenticatedNew, isNotNull);
      expect(authenticatedNew!.name, equals('Tariq Chef'));
    });

    test('fetches all staff and toggles active status', () async {
      final staffList = await authService.getAllStaff();
      expect(staffList.length, greaterThanOrEqualTo(3));

      final cashier = staffList.firstWhere((s) => s.role == StaffRole.cashier);

      // Deactivate
      final deactivated = await authService.updateStaffActiveStatus(
        staffId: cashier.id,
        isActive: false,
      );
      expect(deactivated, isTrue);
      expect(await authService.authenticateWithPin('1111'), isNull);

      // Reactivate
      final reactivated = await authService.updateStaffActiveStatus(
        staffId: cashier.id,
        isActive: true,
      );
      expect(reactivated, isTrue);
      expect(await authService.authenticateWithPin('1111'), isNotNull);
    });
  });
}
