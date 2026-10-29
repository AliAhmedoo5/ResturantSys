import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  for (final target in ['category', 'menu item']) {
    test('deletes $target with grouped modifiers', () async {
      final pos = PosDatabase(factory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath, seedDefaultStaff: false);
      addTearDown(pos.close);
      final db = await pos.initialize();
      final catalog = CatalogAndRecipeController(database: db);
      final category = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#FFFFFF');
      final item = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 100);
      final group = await catalog.createModifierGroup(menuItemId: item.id, name: 'Sauce');
      await catalog.createModifier(menuItemId: item.id, groupId: group.id, name: 'Ketchup');
      if (target == 'category') {
        await catalog.deleteCategory(category.id);
        expect(await catalog.getCategories(), isEmpty);
      } else {
        await catalog.deleteMenuItem(item.id);
      }
      expect(await catalog.getMenuItems(), isEmpty);
      expect(await catalog.getModifiers(), isEmpty);
      expect(await catalog.getModifierGroups(), isEmpty);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}
