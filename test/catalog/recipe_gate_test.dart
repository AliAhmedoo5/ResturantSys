import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';

void main() {
  test('Deal publishing requires a recipe on every alternative', () async {
    sqfliteFfiInit();
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final catalog = CatalogAndRecipeController(database: db);
    final orders = OrderAndCheckoutController(database: db);
    final cat = await catalog.createCategory(name: 'Drinks', displayOrder: 0, colorHex: '#000000');
    final normal = await catalog.createMenuItem(categoryId: cat.id, name: 'Regular', basePrice: 10);
    final large = await catalog.createMenuItem(categoryId: cat.id, name: 'Large', basePrice: 20);
    final ingredient = await catalog.createRawIngredient(name: 'Cola', storageUnit: StorageUnit.ml);
    await catalog.setRecipeForMenuItem(menuItemId: normal.id, items: [(rawIngredientId: ingredient.id, quantity: 200.0)]);
    await catalog.toggleMenuItemActive(normal.id, true);
    final slots = [DealItemDraft(groupName: 'Drink', defaultMenuItemId: normal.id, options: [DealOptionDraft(menuItemId: normal.id), DealOptionDraft(menuItemId: large.id)])];
    await expectLater(orders.createDeal(name: 'Unsafe', basePrice: 10, isActive: true, items: slots), throwsStateError);
    expect(await orders.getDeals(), isEmpty);
    final draft = await orders.createDeal(name: 'Draft', basePrice: 10, isActive: false, items: slots);
    expect((await orders.getDeal(draft.id)).isActive, isFalse);
    await catalog.setRecipeForMenuItem(menuItemId: large.id, items: [(rawIngredientId: ingredient.id, quantity: 300.0)]);
    await catalog.toggleMenuItemActive(large.id, true);
    final valid = await orders.createDeal(name: 'Valid', basePrice: 10, isActive: true, items: slots);
    expect((await orders.getDeals(activeOnly: true)).single.id, valid.id);
    await catalog.removeRecipeItem(menuItemId: large.id, rawIngredientId: ingredient.id);
    expect(await orders.getDeals(activeOnly: true), isEmpty);
  });
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
    await expectLater(catalog.createMenuItem(categoryId: category.id, name: 'Unsafe', basePrice: 1, isActive: true), throwsStateError);
    await expectLater(catalog.updateMenuItem(draft.copyWith(isActive: true)), throwsStateError);
    final mayo = await catalog.createRawIngredient(name: 'Mayo', storageUnit: StorageUnit.g);
    await catalog.setRecipeForMenuItem(menuItemId: draft.id, items: [(rawIngredientId: mayo.id, quantity: 20.0)]);
    await catalog.toggleMenuItemActive(draft.id, true);
    expect((await catalog.getMenuItems(activeOnly: true)).single.id, draft.id);
    await expectLater(catalog.setRecipeForMenuItem(menuItemId: draft.id, items: [(rawIngredientId: mayo.id, quantity: -1.0)]), throwsArgumentError);
    await catalog.removeRecipeItem(menuItemId: draft.id, rawIngredientId: mayo.id);
    expect(await catalog.getMenuItems(activeOnly: true), isEmpty);
  });
}
