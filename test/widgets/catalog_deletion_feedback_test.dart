import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/catalog/supervisor_catalog_workspace.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('No database calls expected');
}

class _FailingDeletes extends CatalogAndRecipeController {
  _FailingDeletes() : super(database: _UnusedDatabase());
  @override
  Future<void> deleteCategory(int id) async => throw Exception('Storage failure');
  @override
  Future<void> deleteMenuItem(int id) async => throw Exception('Storage failure');
  @override
  Future<void> deleteModifier(int id) async => throw Exception('Storage failure');
  @override
  Future<void> deleteManagedDiscount({required int managerId, required int id}) async => throw StateError('Manager session expired.');
}

Future<void> _showWorkspace(WidgetTester tester, {CatalogAndRecipeController? controller}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme, home: Scaffold(
    body: SupervisorCatalogWorkspace(controller: controller, managerId: 1,
      initialCategories: const [MenuCategory(id: 1, name: 'Pizza', displayOrder: 0, colorHex: '#FFFFFF')],
      initialMenuItems: const [MenuItem(id: 1, categoryId: 1, name: 'Slice', basePrice: 100)],
      initialModifiers: const [Modifier(id: 1, menuItemId: 1, name: 'Extra cheese', priceDelta: 10)],
      initialDiscounts: const [DiscountPreset(id: 1, name: 'Lunch offer', type: DiscountType.flat, value: 10, isActive: true)],
    ))));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
  await tester.pumpAndSettle();
}

void main() {
  for (final record in [
    ('categories', 'category', 'Pizza'),
    ('menu_items', 'menu_item', 'Slice'),
    ('modifiers', 'modifier', 'Extra cheese'),
    ('discounts', 'discount', 'Lunch offer'),
  ]) {
    testWidgets('${record.$2} delete failure stays visible with feedback', (tester) async {
      await _showWorkspace(tester, controller: _FailingDeletes());
      await tester.tap(find.byKey(ValueKey('tab_${record.$1}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('delete_${record.$2}_1')));
      await tester.pumpAndSettle();
      await _confirm(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(record.$3), findsOneWidget);
      if (record.$2 == 'discount') expect(find.text('Manager session expired.'), findsOneWidget);
    });
  }

  testWidgets('cancel preserves category; confirmed deletion removes its items and modifiers', (tester) async {
    await _showWorkspace(tester);
    await tester.tap(find.byKey(const ValueKey('delete_category_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete_category_1')));
    await tester.pumpAndSettle();
    await _confirm(tester);
    expect(find.text('Pizza'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab_menu_items')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Slice'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab_modifiers')));
    await tester.pumpAndSettle();
    expect(find.text('Extra cheese'), findsNothing);
  });
}
