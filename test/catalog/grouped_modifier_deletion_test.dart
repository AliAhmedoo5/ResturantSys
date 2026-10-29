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
      final option = await catalog.createModifier(menuItemId: item.id, groupId: group.id, name: 'Ketchup');
      final otherCategory = await catalog.createCategory(name: 'Drinks', displayOrder: 1, colorHex: '#000000');
      final otherItem = await catalog.createMenuItem(categoryId: otherCategory.id, name: 'Cola', basePrice: 50);
      final otherGroup = await catalog.createModifierGroup(menuItemId: otherItem.id, name: 'Ice');
      final otherOption = await catalog.createModifier(menuItemId: otherItem.id, groupId: otherGroup.id, name: 'No ice');
      Future<void> remove() => target == 'category'
          ? catalog.deleteCategory(category.id) : catalog.deleteMenuItem(item.id);
      // Force a later cascade to fail after the options have been removed.
      // SQLite must restore those options together with their parent records.
      await db.execute('''CREATE TRIGGER reject_group_delete BEFORE DELETE ON modifier_groups
        BEGIN SELECT RAISE(ABORT, 'simulated delete failure'); END''');
      await expectLater(remove(), throwsA(isA<DatabaseException>()));
      expect((await catalog.getModifiers()).map((m) => m.id), contains(option.id));
      expect((await catalog.getModifierGroups()).map((g) => g.id), contains(group.id));
      expect((await catalog.getMenuItems()).map((m) => m.id), contains(item.id));
      await db.execute('DROP TRIGGER reject_group_delete');
      await remove();
      if (target == 'category') {
        expect((await catalog.getCategories()).single.id, otherCategory.id);
      }
      expect((await catalog.getMenuItems()).single.id, otherItem.id);
      expect((await catalog.getModifiers()).single.id, otherOption.id);
      expect((await catalog.getModifierGroups()).single.id, otherGroup.id);
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }
}
