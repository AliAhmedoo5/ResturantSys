import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/modifier_group.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/orders/deal.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/widgets/catalog/supervisor_catalog_workspace.dart';

class _Catalog implements CatalogAndRecipeController {
  @override
  Future<List<Deal>> getDeals({bool? activeOnly}) async => [];
  bool active = true;
  Completer<List<MenuCategory>>? reload;
  bool rejectToggle = false;

  @override
  Future<List<MenuCategory>> getCategories() async => reload == null
      ? const [MenuCategory(id: 1, name: 'Burgers', displayOrder: 0, colorHex: '#FF0000')]
      : reload!.future;

  @override
  Future<List<MenuItem>> getMenuItems({int? categoryId, bool? activeOnly}) async => [
    MenuItem(id: 1, categoryId: 1, name: 'Zinger', basePrice: 333, isActive: active),
    const MenuItem(id: 2, categoryId: 2, name: 'Pizza', basePrice: 500),
  ];

  @override
  Future<void> toggleMenuItemActive(int id, bool isActive) async {
    if (rejectToggle) throw StateError('Recipe is incomplete');
    active = isActive;
  }

  @override
  Future<List<RawIngredient>> getRawIngredients({bool? lowStockOnly}) async => [];
  @override
  Future<List<Modifier>> getModifiers({int? menuItemId, bool? activeOnly}) async => [];
  @override
  Future<List<ModifierGroup>> getModifierGroups({int? menuItemId, DatabaseExecutor? executor}) async => [];
  @override
  Future<List<DiscountPreset>> getDiscountPresets({bool? activeOnly}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Orders implements OrderAndCheckoutController {
  @override
  Future<bool> isCashierVoidEnabled() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('repeated persisted toggles retain menu tab and category through delayed reloads', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = _Catalog();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      SupervisorCatalogWorkspace(controller: catalog, orderController: _Orders()),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burgers'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('toggle_menu_item_active_1'));

    for (final expected in [false, true, false, true]) {
      catalog.reload = Completer<List<MenuCategory>>();
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      catalog.reload!.complete(const [
        MenuCategory(id: 1, name: 'Burgers', displayOrder: 0, colorHex: '#FF0000'),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Menu Items & Recipe BOM'), findsOneWidget);
      expect(find.text('Menu Categories'), findsNothing);
      expect(find.text('Pizza'), findsNothing, reason: 'Keep the selected category too.');
      expect(tester.widget<Switch>(toggle).value, expected);
      expect(tester.takeException(), isNull);
    }

    catalog.rejectToggle = true;
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Recipe is incomplete'), findsOneWidget);
    expect(find.text('Menu Items & Recipe BOM'), findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });
}
