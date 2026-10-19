import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';

void main() {
  test('Recipe gate rejects activation and keeps incomplete drafts off counter', () async {
    sqfliteFfiInit();
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#000000');
    final draft = await catalog.createMenuItem(categoryId: category.id, name: 'Mayo burger', basePrice: 300, isActive: false);
    await expectLater(catalog.toggleMenuItemActive(draft.id, true), throwsStateError);
    expect(await catalog.getMenuItems(activeOnly: true), isEmpty);
  });
}
