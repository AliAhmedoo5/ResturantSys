import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/discount_rules.dart';
import 'package:resturant_sys/core/settings/keyboard_shortcut_controller.dart';
import 'package:resturant_sys/widgets/catalog/dialogs/discount_preset_form_dialog.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shortcuts extends KeyboardShortcutController {
  _Shortcuts() : super(_UnusedDatabase());
  @override
  Future<Map<String, String>> load() async => Map.of(KeyboardShortcutController.defaults)
    ..['category2'] = 'Shift+F2';
}

void main() {
  testWidgets('remapped category shortcut works, old mapping and text-entry invocation do not', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CounterBillingWorkspace(
      shortcutController: _Shortcuts(),
      currentStaff: const Staff(id: 2, name: 'Cashier', departmentId: 1, pinHash: '', role: StaffRole.cashier, isActive: true),
      businessDayId: 1, shiftId: 1,
      initialCategories: const [MenuCategory(id: 1, name: 'Meals', displayOrder: 1, colorHex: '#FF0000'),
        MenuCategory(id: 2, name: 'Drinks', displayOrder: 2, colorHex: '#00FF00')],
      initialMenuItems: const [MenuItem(id: 1, categoryId: 1, name: 'Burger', basePrice: 100),
        MenuItem(id: 2, categoryId: 2, name: 'Cola', basePrice: 50)],
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Burger'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
    expect(find.text('Burger'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Cola'), findsOneWidget);
    expect(find.text('Burger'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('catalog_search')));
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('Cola'), findsOneWidget);
    expect(find.text('Burger'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Manager discount form saves advanced terms and rejects invalid cap', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    DiscountRules? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () => showDialog<void>(context: context, builder: (_) => DiscountPresetFormDialog(
        onSave: ({required name, required type, required value, required bool isActive, required DiscountRules rules}) async { saved = rules; })),
      child: const Text('Configure'))))));
    await tester.tap(find.text('Configure')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('discount_name_field')), 'Lunch');
    final minimum = find.widgetWithText(TextFormField, 'Minimum spend (Rs)');
    await tester.ensureVisible(minimum);
    await tester.enterText(minimum, '200');
    final maximum = find.widgetWithText(TextFormField, 'Maximum discount (Rs)');
    await tester.ensureVisible(maximum);
    await tester.enterText(maximum, '0');
    await tester.tap(find.byKey(const ValueKey('save_discount_button'))); await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.enterText(maximum, '50');
    await tester.tap(find.byKey(const ValueKey('save_discount_button'))); await tester.pumpAndSettle();
    expect(saved?.minimumSpendPaisa, 20000);
    expect(saved?.maximumDiscountPaisa, 5000);
    expect(tester.takeException(), isNull);
  });
}
