import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';

void main() {
  late PosDatabase store;
  late DeliveryController delivery;
  setUp(() async {
    sqfliteFfiInit();
    store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    delivery = DeliveryController(database: await store.initialize());
  });
  tearDown(() => store.close());

  test('Only Manager can configure fixed delivery fees and archive areas', () async {
    await expectLater(delivery.saveArea(staffId: 2, name: 'Garden', code: 'G', deliveryFeePaisa: 12550), throwsStateError);
    final area = await delivery.saveArea(staffId: 1, name: 'Garden', code: 'G', deliveryFeePaisa: 12550);
    expect((await delivery.getAreas()).single.deliveryFeePaisa, 12550);
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden East', code: 'G', deliveryFeePaisa: 15025, isActive: false);
    expect(await delivery.getAreas(activeOnly: true), isEmpty);
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden East', code: 'G', deliveryFeePaisa: 15025);
    expect((await delivery.getAreas(activeOnly: true)).single.name, 'Garden East');
    await expectLater(delivery.archiveArea(staffId: 2, id: area.id), throwsStateError);
    await delivery.archiveArea(staffId: 1, id: area.id);
    expect(await delivery.getAreas(), isEmpty);
    expect((await delivery.getAreas(includeArchived: true)).single.isArchived, isTrue);
  });
}
