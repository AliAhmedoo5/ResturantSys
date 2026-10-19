import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';

void main() {
  test('v9 upgrade preserves explicit legacy removal quantities and quarantines ambiguous global removals', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('recipe_v10_');
    final path = '${directory.path}/pos.db';
    final original = PosDatabase(factory: databaseFactoryFfi, customPath: path);
    final db = await original.initialize();
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 0, colorHex: '#000000');
    final item = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 300);
    final mayo = await catalog.createRawIngredient(name: 'Mayo', storageUnit: StorageUnit.g, currentStock: 100);
    await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: mayo.id, quantity: 20.0)]);
    await catalog.toggleMenuItemActive(item.id, true);
    final removal = await catalog.createModifier(menuItemId: item.id, name: 'No Mayo', rawIngredientId: mayo.id, ingredientQtyDelta: 0);
    final global = await catalog.createModifier(name: 'No Mayo everywhere', rawIngredientId: mayo.id, ingredientQtyDelta: 0);
    // Restore the old schema shape to exercise the actual versioned upgrade.
    await db.execute('ALTER TABLE modifiers DROP COLUMN group_id');
    await db.execute('ALTER TABLE order_items DROP COLUMN bom_json');
    await db.execute('DROP TABLE modifier_groups');
    await db.execute('PRAGMA user_version = 9');
    await original.close();
    final upgraded = PosDatabase(factory: databaseFactoryFfi, customPath: path);
    addTearDown(() async { await upgraded.close(); await directory.delete(recursive: true); });
    final upgradedDb = await upgraded.initialize();
    final updated = CatalogAndRecipeController(database: upgradedDb);
    final modifiers = await updated.getModifiers();
    expect(modifiers.singleWhere((m) => m.id == removal.id).ingredientQtyDelta, -20);
    expect(modifiers.singleWhere((m) => m.id == global.id).isActive, isFalse);
    expect((await updated.getRawIngredient(mayo.id)).currentStock, 100);
    expect((await updated.getMenuItems(activeOnly: true)).single.id, item.id);
    final group = await updated.createModifierGroup(menuItemId: item.id, name: 'Sauce', isRequired: true);
    expect((await updated.getModifierGroups()).single.id, group.id);
    await upgraded.close();
    final reopened = CatalogAndRecipeController(database: await upgraded.initialize());
    expect((await reopened.getModifierGroups()).single.id, group.id);
  });
}
