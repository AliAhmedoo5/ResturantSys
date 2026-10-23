import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

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
    expect(await auth.authenticateWithPin('1234'), isNull);
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
}
