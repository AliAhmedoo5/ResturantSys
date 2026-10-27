import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late Directory directory;
  late PosDatabase store;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('urgent_protection_');
    store = PosDatabase(
      factory: databaseFactoryFfi,
      customPath: '${directory.path}/pos.db',
    );
    db = await store.initialize();
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('removing a supplier preserves its settled financial history', () async {
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'History', phone: '03000000000');
    await khata.recordCreditDelivery(vendorId: supplier.id, amount: 500);
    await khata.deleteVendor(supplier.id);
    expect(await khata.getVendorById(supplier.id), isNotNull);
    expect(await khata.getVendorTransactions(vendorId: supplier.id), hasLength(1));
    expect((await khata.getVendorStatement(supplier.id)).currentBalance, 500);
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
}
