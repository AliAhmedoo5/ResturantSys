import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/modifier_group.dart';
import 'package:resturant_sys/core/orders/deal.dart';
import 'package:resturant_sys/core/orders/deal_item.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';

void main() {
  testWidgets('Cashier selects required modifiers for a deal component before adding the deal', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const group = ModifierGroup(id: 1, menuItemId: 1, name: 'Sauce', isRequired: true);
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.lightTheme, home: Scaffold(body: CounterBillingWorkspace(
      currentStaff: const Staff(id: 2, name: 'Cashier', departmentId: 1, pinHash: 'hash', role: StaffRole.cashier, isActive: true),
      businessDayId: 1, shiftId: 1,
      initialCategories: const [MenuCategory(id: 1, name: 'Burgers', displayOrder: 0, colorHex: '#000000')],
      initialMenuItems: const [MenuItem(id: 1, categoryId: 1, name: 'Burger', basePrice: 300)],
      initialDeals: [Deal(id: 1, name: 'Meal', basePrice: 300, createdAt: DateTime(2026), items: [DealItem(id: 1, dealId: 1, groupName: 'Main', defaultMenuItemId: 1)])],
      initialModifiers: const [Modifier(id: 1, menuItemId: 1, name: 'Extra sauce', groupId: 1, group: group, priceDelta: 30)],
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category_tab_deals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deal_tile_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add_deal_to_order_button')));
    await tester.pumpAndSettle();
    expect(find.text('Customize: Burger'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('apply_modifiers_button')));
    await tester.pumpAndSettle();
    expect(find.text('Customize: Burger'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('modifier_tile_1')));
    await tester.tap(find.byKey(const ValueKey('apply_modifiers_button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Extra sauce'), findsOneWidget);
    expect(find.byKey(const ValueKey('customize_item_0')), findsOneWidget);
  });
}
