import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/catalog/supervisor_catalog_workspace.dart';

void main() {
  testWidgets('category name opens its menu items and All Categories clears filter', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: WarmCounterTheme.lightTheme,
      home: const Scaffold(body: SupervisorCatalogWorkspace(
        initialCategories: [
          MenuCategory(id: 1, name: 'Burgers', displayOrder: 0, colorHex: '#FF0000'),
          MenuCategory(id: 2, name: 'Pizza', displayOrder: 1, colorHex: '#00FF00'),
        ],
        initialMenuItems: [
          MenuItem(id: 1, categoryId: 1, name: 'Zinger', basePrice: 333),
          MenuItem(id: 2, categoryId: 2, name: 'Margherita', basePrice: 500),
        ],
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burgers'));
    await tester.pumpAndSettle();
    expect(find.text('Menu Items & Recipe BOM'), findsOneWidget);
    expect(find.text('Zinger'), findsOneWidget);
    expect(find.text('Margherita'), findsNothing);
    await tester.tap(find.text('All Categories'));
    await tester.pumpAndSettle();
    expect(find.text('Margherita'), findsOneWidget);
  });
}
