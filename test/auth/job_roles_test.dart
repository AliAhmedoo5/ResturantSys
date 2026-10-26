import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('job roles support CRUD without granting login or losing staff assignments', () async {
    final pos = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath, seedDefaultStaff: false);
    final db = await pos.initialize();
    addTearDown(pos.close);
    final auth = AuthService(database: db);
    final riderRole = await auth.createJobRole('Rider');
    final department = await auth.createDepartment('Delivery');
    final rider = await auth.registerStaff(name: 'Rider', departmentId: department.id,
        role: StaffRole.cashier, pin: '', jobRoleId: riderRole.id, loginEnabled: false);
    expect(rider.jobRoleName, 'Rider');
    expect(rider.canAccessRegister, isFalse);
    expect(rider.canAccessSupervisorPortal, isFalse);
    await expectLater(ShiftAndCashController(database: db).openShift(
        staffId: rider.id, openingFloat: 0), throwsStateError);
    expect(await auth.authenticateWithPin('1234'), isNull);
    expect(await auth.hasActiveCashier(), isFalse);
    await expectLater(auth.completeOnboarding(), throwsStateError);
    await expectLater(auth.updateStaff(staffId: rider.id, name: rider.name,
        departmentId: department.id, role: StaffRole.cashier,
        jobRoleId: riderRole.id, loginEnabled: true), throwsArgumentError);
    await auth.updateJobRole(riderRole.id, 'Delivery Rider');
    expect((await auth.getAllStaff()).singleWhere((s) => s.id == rider.id).jobRoleName, 'Delivery Rider');
    await expectLater(auth.deleteJobRole(riderRole.id), throwsStateError);
    await auth.updateStaff(staffId: rider.id, name: rider.name,
        departmentId: department.id, role: StaffRole.cashier,
        jobRoleId: riderRole.id, loginEnabled: true, newPin: '7890');
    expect((await auth.authenticateWithPin('7890'))?.id, rider.id);
    await auth.updateStaff(staffId: rider.id, name: rider.name,
        departmentId: department.id, role: StaffRole.cashier,
        jobRoleId: null, loginEnabled: false);
    expect(await auth.authenticateWithPin('7890'), isNull);
    await auth.deleteJobRole(riderRole.id);
    expect((await auth.getJobRoles()).any((r) => r.id == riderRole.id), isFalse);
    await expectLater(auth.createJobRole(' '), throwsArgumentError);
    await auth.createJobRole('Cook');
    await expectLater(auth.createJobRole('cook'), throwsA(anything));
  });

  test('v14 migration preserves existing staff and enables their previous logins', () async {
    final temp = await Directory.systemTemp.createTemp('job_role_migration_');
    addTearDown(() => temp.delete(recursive: true));
    final path = '${temp.path}/pos.db';
    final original = PosDatabase(factory: databaseFactoryFfi, customPath: path);
    final db = await original.initialize();
    final before = await db.query('staff');
    // Remove only the v15 additions to recreate the preceding production schema.
    await db.execute('ALTER TABLE staff DROP COLUMN job_role_id');
    await db.execute('ALTER TABLE staff DROP COLUMN login_enabled');
    await db.execute('DROP TABLE job_roles');
    await db.setVersion(14);
    await original.close();
    final upgraded = PosDatabase(factory: databaseFactoryFfi, customPath: path);
    final migrated = await upgraded.initialize();
    addTearDown(upgraded.close);
    final after = await migrated.query('staff');
    expect(after.length, before.length);
    for (final old in before) {
      final row = after.singleWhere((r) => r['id'] == old['id']);
      expect(row['pin_hash'], old['pin_hash']);
      expect(row['role'], old['role']);
      expect(row['login_enabled'], 1);
      expect(row['job_role_id'], isNull);
    }
    expect(await AuthService(database: migrated).getJobRoles(), isEmpty);
  });
}
