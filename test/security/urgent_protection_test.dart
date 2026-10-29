import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late PosDatabase store;
  late Database db;
  late int managerId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('urgent_protection_');
    store = PosDatabase(
      factory: databaseFactoryFfi,
      customPath: '${directory.path}/pos.db',
      seedDefaultStaff: false,
    );
    db = await store.initialize();
    // Historical fixture credentials exercise migration without repeatedly
    // deriving slow verifiers during unrelated supplier test setup.
    for (final fixture in [('Manager', 'SUPERVISOR', '1234', 3), ('Cashier', 'CASHIER', '1111', 1)]) {
      await db.insert('staff', {
        'name': fixture.$1, 'role': fixture.$2, 'department_id': fixture.$4,
        'pin_hash': sha256.convert(utf8.encode('resturant_pos_pin_salt_v1:${fixture.$3}')).toString(),
        'is_active': 1, 'created_at': '2026-10-27 12:00:00',
      });
    }
    managerId = (await db.query('staff', where: "role='SUPERVISOR'")).single['id'] as int;
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('removing a supplier preserves its settled financial history', () async {
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'History', phone: '03000000000');
    await khata.recordCreditDelivery(vendorId: supplier.id, amount: 500);
    await khata.recordSettlementPayment(vendorId: supplier.id, amount: 500,
        paymentSource: VendorPaymentSource.paidOutsideDrawer, staffId: managerId);
    await khata.deleteVendor(supplier.id);
    expect((await khata.getVendorById(supplier.id))!.isArchived, isTrue);
    expect(await khata.getVendorTransactions(vendorId: supplier.id), hasLength(2));
    expect((await khata.getVendorStatement(supplier.id)).currentBalance, 0);
    expect(await khata.getVendors(), isEmpty);
    expect(await khata.getVendors(includeArchived: true), hasLength(1));
  });

  test('new PIN verifiers use independent random salts', () {
    final first = PinHasher.hashPin('7391');
    final second = PinHasher.hashPin('7391');
    expect(first, isNot(second));
    expect(PinHasher.verifyPin('7391', first), isTrue);
    expect(PinHasher.verifyPin('7392', first), isFalse);
  });

  test('failed PIN attempts remain locked after database reopen', () async {
    final auth = AuthService(database: db);
    for (var attempt = 0; attempt < 5; attempt++) {
      expect(await auth.authenticateWithPin('9999'), isNull);
    }
    await store.close();
    db = await store.initialize();
    expect(await AuthService(database: db).authenticateWithPin('1234'), isNull);
  });

  test('database rejects direct deletion of referenced suppliers', () async {
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'Protected', phone: '1');
    await khata.recordCreditDelivery(vendorId: supplier.id, amount: 200);
    await expectLater(db.delete('vendor_khata', where: 'id = ?', whereArgs: [supplier.id]),
        throwsA(isA<DatabaseException>()));
    expect(await khata.getVendorTransactions(vendorId: supplier.id), hasLength(1));
  });

  test('unused suppliers can be permanently removed', () async {
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'Unused', phone: '1');
    await khata.deleteVendor(supplier.id);
    expect(await khata.getVendorById(supplier.id), isNull);
  });

  test('opening balances survive removal and archived suppliers can settle', () async {
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'Opening', phone: '1', openingBalance: 200);
    await khata.deleteVendor(supplier.id);
    await expectLater(khata.recordCreditDelivery(vendorId: supplier.id, amount: 10), throwsStateError);
    await khata.recordSettlementPayment(vendorId: supplier.id, amount: 200,
        paymentSource: VendorPaymentSource.paidOutsideDrawer, staffId: managerId);
    expect((await khata.getVendorStatement(supplier.id)).openingBalance, 200);
    await khata.setVendorArchived(supplier.id, false);
    await khata.recordCreditDelivery(vendorId: supplier.id, amount: 10);
    expect((await khata.getVendorStatement(supplier.id)).currentBalance, 10);
  });

  test('legacy credentials upgrade on successful login', () async {
    final legacy = sha256.convert(utf8.encode('resturant_pos_pin_salt_v1:1234')).toString();
    await db.update('staff', {'pin_hash': legacy}, where: "role = 'SUPERVISOR'");
    final staff = await AuthService(database: db).authenticateWithPin('1234');
    expect(staff, isNotNull);
    expect(staff!.pinHash, startsWith(r'pbkdf2-sha256$600000$'));
    expect(PinHasher.verifyPin('1234', staff.pinHash), isTrue);
    final row = (await db.query('staff', where: 'id = ?', whereArgs: [staff.id])).single;
    expect(row['pin_fingerprint'], isNotNull);
    expect(row['pin_fingerprint'], isNot(legacy));
  });

  test('duplicate PINs rejected across creation reset and change', () async {
    final auth = AuthService(database: db);
    final manager = (await auth.authenticateWithPin('1234'))!;
    final cashier = (await auth.authenticateWithPin('1111'))!;
    await expectLater(auth.registerStaff(name: 'Duplicate', departmentId: manager.departmentId,
        role: cashier.role, pin: '1234'), throwsStateError);
    await expectLater(auth.updateStaffPin(staffId: cashier.id, newPin: '1234'), throwsStateError);
    await expectLater(auth.changePin(staffId: cashier.id, oldPin: '1111', newPin: '1234'), throwsStateError);
    expect(await auth.authenticateWithPin('1111'), isNotNull);
  });

  test('lock expires and does not change credentials or create a session', () async {
    var now = DateTime.utc(2026, 10, 27);
    final auth = AuthService(database: db, clock: () => now);
    for (var i = 0; i < 5; i++) {
      await auth.authenticateSupervisorPin('9999');
    }
    expect(await auth.authenticateAndLogin('1234'), isNull);
    expect(auth.session.isAuthenticated, isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(await auth.authenticateAndLogin('1234'), isNotNull);
    expect(auth.session.isAuthenticated, isTrue);
  });

  test('parallel failures share a durable lockout', () async {
    await Future.wait(List.generate(5, (_) => AuthService(database: db).authenticateWithPin('9999')));
    expect(await AuthService(database: db).authenticateWithPin('1234'), isNull);
  });

  test('cashier PIN cannot reset failed manager approvals', () async {
    final auth = AuthService(database: db);
    for (var i = 0; i < 5; i++) {
      expect(await auth.authenticateSupervisorPin('1111'), isNull);
    }
    expect(await auth.authenticateSupervisorPin('1234'), isNull);
  });

  test('successful cashier logins cannot erase manager approval failures', () async {
    final auth = AuthService(database: db);
    for (var i = 0; i < 5; i++) {
      expect(await auth.authenticateWithPin('1111'), isNotNull);
      expect(await auth.authenticateSupervisorPin('9999'), isNull);
    }
    expect(await auth.authenticateSupervisorPin('1234'), isNull);
  });

  test('missing OS key fails closed for an initialized database', () async {
    final auth = AuthService(database: db);
    expect(await auth.authenticateWithPin('1234'), isNotNull);
    await const FlutterSecureStorage().deleteAll();
    await expectLater(AuthService(database: db).authenticateWithPin('1234'), throwsStateError);
  });

  test('malformed stored verifiers fail safely', () {
    expect(PinHasher.verifyPin('1234', r'pbkdf2-sha256$999999999$bad$bad'), isFalse);
    expect(PinHasher.verifyPin('1234', r'pbkdf2-sha256$600000$bad$bad'), isFalse);
    expect(PinHasher.verifyPin('1234', 'NO_LOGIN_123'), isFalse);
  });

  test('v16 migration preserves existing ledger and legacy credentials', () async {
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'Migrated', phone: '1');
    await khata.recordCreditDelivery(vendorId: supplier.id, amount: 350);
    final legacy = sha256.convert(utf8.encode('resturant_pos_pin_salt_v1:1234')).toString();
    await db.update('staff', {'pin_hash': legacy}, where: "role = 'SUPERVISOR'");
    // Remove exactly the v17 additions to reconstruct the previous schema.
    await db.execute('DROP TRIGGER vendor_financial_history_delete_guard');
    await db.execute('DROP INDEX staff_pin_fingerprint_unique');
    await db.execute('ALTER TABLE vendor_khata DROP COLUMN archived_at');
    await db.execute('ALTER TABLE staff DROP COLUMN pin_fingerprint');
    await db.execute('DROP TABLE auth_security_state');
    await db.execute('PRAGMA user_version = 16');
    await store.close();
    db = await store.initialize();
    final migrated = VendorKhataController(database: db);
    expect((await migrated.getVendorStatement(supplier.id)).currentBalance, 350);
    expect(await AuthService(database: db).authenticateWithPin('1234'), isNotNull);
    await migrated.deleteVendor(supplier.id);
    expect((await migrated.getVendorById(supplier.id))!.isArchived, isTrue);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
