import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';

/// Any parent-database read would escape checkout's transaction (and deadlock).
class _ForbiddenDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Deal selection must use the supplied transaction.');
}

void main() {
  setUpAll(sqfliteFfiInit);
  test('legacy Deal choices and Recipe Gate use only the checkout transaction', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Drinks', displayOrder: 0, colorHex: '#000000');
    final item = await catalog.createMenuItem(categoryId: category.id, name: 'Cola', basePrice: 100);
    final ingredient = await catalog.createRawIngredient(name: 'Cola syrup', storageUnit: StorageUnit.ml);
    await catalog.setRecipeForMenuItem(menuItemId: item.id,
      items: [(rawIngredientId: ingredient.id, quantity: 20.0)]);
    await catalog.toggleMenuItemActive(item.id, true);
    final deal = await catalog.createDeal(name: 'Legacy category Deal', basePrice: 90,
      items: [DealItemDraft(groupName: 'Drink', categoryId: category.id,
        defaultMenuItemId: item.id, isUpgradeable: true, upgradePrice: 10)]);
    final slot = deal.items.single;
    expect(slot.categoryId, category.id);
    expect(slot.upgradePrice, 10);
    final selection = [SelectedDealChoice(dealItemId: slot.id, groupName: slot.groupName,
      menuItemId: item.id, menuItemName: item.name)];
    final transactionCatalog = CatalogAndRecipeController(database: _ForbiddenDatabase());
    await db.transaction((txn) async {
      expect(await transactionCatalog.validateDealSelection(deal.id, selection, executor: txn), [item.id]);
      await expectLater(transactionCatalog.validateDealSelection(deal.id, [], executor: txn), throwsStateError);
      await txn.delete('recipes', where: 'menu_item_id = ?', whereArgs: [item.id]);
      await expectLater(transactionCatalog.validateDealSelection(deal.id, selection, executor: txn), throwsStateError);
    });
  });
}
