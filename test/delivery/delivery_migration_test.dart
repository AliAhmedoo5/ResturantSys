import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';

void main() {
  test('Existing v10 delivery areas survive upgrade and can be archived', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('delivery_upgrade_');
    final path = '${dir.path}/pos.db';
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: path);
    final db = await store.initialize();
    final service = DeliveryController(database: db);
    final area = await service.saveArea(staffId: 1, name: 'Legacy area', code: 'OLD', deliveryFeePaisa: 12345);
    // Reconstruct the exact pre-archive schema, retaining historical data.
    await db.execute('ALTER TABLE delivery_areas DROP COLUMN archived_at');
    await db.setVersion(10);
    await store.close();
    final upgraded = PosDatabase(factory: databaseFactoryFfi, customPath: path);
    try {
      final delivery = DeliveryController(database: await upgraded.initialize());
      expect((await delivery.getAreas()).single.deliveryFeePaisa, 12345);
      await delivery.archiveArea(staffId: 1, id: area.id);
      expect(await delivery.getAreas(activeOnly: true), isEmpty);
      expect((await delivery.getAreas(includeArchived: true)).single.name, 'Legacy area');
    } finally {
      await upgraded.close();
      await dir.delete(recursive: true);
    }
  });
}
