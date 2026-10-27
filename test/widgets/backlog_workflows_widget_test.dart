import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/orders/customer_controller.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/widgets/catalog/dialogs/deal_form_dialog.dart';
import 'package:resturant_sys/widgets/orders/customer_directory.dart';

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Customers extends CustomerController {
  _Customers() : super(_UnusedDatabase());
  @override
  Future<List<Customer>> search(String query) async => [Customer.fromMap({
    'id': 1, 'name': 'Sample Customer', 'phone': '03001234567', 'notes': 'Call at gate',
  })];
  @override
  Future<List<Map<String, Object?>>> history(int customerId) async => [{
    'id': 7, 'created_at': '2026-10-27', 'grand_total': 100,
    'dining_type': 'TAKEAWAY', 'payment_status': 'SETTLED', 'token_status': 'DELIVERED',
  }];
}

class _Deals extends OrderAndCheckoutController {
  _Deals() : super(database: _UnusedDatabase());
  List<DealItemDraft>? saved;
  @override
  Future<void> saveDeal({required int managerId, int? id, required String name,
    required double basePrice, required bool isActive, required List<DealItemDraft> items}) async {
    saved = items;
  }
}

void main() {
  testWidgets('Cashier selects a previous order to repeat; Manager sees merge only', (tester) async {
    CustomerSelection? result;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => TextButton(
      onPressed: () async { result = await showDialog<CustomerSelection>(context: context, builder: (_) => Dialog(
        child: SizedBox(width: 750, height: 450, child: CustomerDirectory(controller: _Customers(), staffId: 2)))); },
      child: const Text('Open customers'))))));
    await tester.tap(find.text('Open customers')); await tester.pumpAndSettle();
    await tester.tap(find.text('Sample Customer')); await tester.pumpAndSettle();
    expect(find.text('Merge duplicate'), findsNothing);
    await tester.tap(find.text('Repeat')); await tester.pumpAndSettle();
    expect(result?.repeatOrderId, 7);
    expect(result?.customer.id, 1);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CustomerDirectory(controller: _Customers(), staffId: 1, manager: true))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sample Customer')); await tester.pumpAndSettle();
    expect(find.text('Merge duplicate'), findsOneWidget);
    expect(find.text('Repeat'), findsNothing);
    expect(find.text('Use customer'), findsNothing);
  });

  testWidgets('Manager configures a deal with a selectable component and default', (tester) async {
    final controller = _Deals();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DealFormDialog(controller: controller, managerId: 1,
      menuItems: const [MenuItem(id: 4, categoryId: 1, name: 'Burger', basePrice: 100)]))));
    await tester.enterText(find.widgetWithText(TextFormField, 'Deal name'), 'Lunch');
    await tester.tap(find.text('Add component')); await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Component name'), 'Main');
    await tester.tap(find.byType(Checkbox)); await tester.pumpAndSettle();
    await tester.tap(find.text('Save Deal')); await tester.pumpAndSettle();
    expect(controller.saved?.single.groupName, 'Main');
    expect(controller.saved?.single.options.single.menuItemId, 4);
    expect(controller.saved?.single.options.single.isDefault, isTrue);
    expect(tester.takeException(), isNull);
  });
}
