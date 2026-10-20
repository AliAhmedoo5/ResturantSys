import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/orders/tender_checkout_dialog.dart';
import 'package:resturant_sys/widgets/delivery/delivery_details_dialog.dart';

void main() {
  testWidgets('Phone prefill, saved-address choice, and stale delivery checkout retain the counter cart', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late PosDatabase store;
    late DeliveryController delivery;
    late OrderAndCheckoutController orders;
    late DeliveryArea area;
    late MenuCategory category;
    late MenuItem food;
    late int dayId, shiftId;
    await tester.runAsync(() async {
      sqfliteFfiInit();
      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      final db = await store.initialize();
      delivery = DeliveryController(database: db);
      orders = OrderAndCheckoutController(database: db);
      final catalog = CatalogAndRecipeController(database: db);
      final shifts = ShiftAndCashController(database: db);
      dayId = (await shifts.openBusinessDay(openedByStaffId: 1)).id;
      shiftId = (await shifts.openShift(staffId: 2, openingFloat: 0)).id;
      category = await catalog.createCategory(name: 'Food', displayOrder: 0, colorHex: '#000000');
      food = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 500);
      final portion = await catalog.createRawIngredient(name: 'Portion', storageUnit: StorageUnit.count, currentStock: 10);
      await catalog.setRecipeForMenuItem(menuItemId: food.id, items: [(rawIngredientId: portion.id, quantity: 1.0)]);
      await catalog.toggleMenuItemActive(food.id, true);
      area = await delivery.saveArea(staffId: 1, name: 'Garden', code: 'G', deliveryFeePaisa: 12550);
      await db.transaction((txn) async {
        await DeliveryController.rememberAddress(txn, DeliveryDetails(areaId: area.id, quotedFeePaisa: 12550, phone: '03001234567', customerName: 'Sara', fullAddress: 'Home'));
        await DeliveryController.rememberAddress(txn, DeliveryDetails(areaId: area.id, quotedFeePaisa: 12550, phone: '03001234567', customerName: 'Sara', fullAddress: 'Office'));
      });
    });
    addTearDown(() => store.close());
    Future<void> settle() async {
      // Build the dialog first so its SQLite lookup starts, then allow real
      // isolate work to finish between frames instead of advancing fake time.
      for (var attempt = 0; attempt < 50; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('SQLite-backed screen did not become ready');
    }    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CounterBillingWorkspace(
      currentStaff: const Staff(id: 2, name: 'Cashier', departmentId: 1, pinHash: '', role: StaffRole.cashier, isActive: true),
      businessDayId: dayId, shiftId: shiftId, orderController: orders,
      initialCategories: [category], initialMenuItems: [food], initialDeals: const [], initialModifiers: const [], initialDiscounts: const [], initialNextTokenNumber: 1,
    ))));
    await tester.tap(find.byKey(ValueKey('menu_item_tile_${food.id}')));
    await settle();
    expect(find.text('Burger'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('dining_type_DELIVERY')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('proceed_to_tender_button')));
    await settle();
    for (var attempt = 0; attempt < 50 && find.byKey(const ValueKey('delivery_phone')).evaluate().isEmpty; attempt++) { await settle(); }
    expect(find.byKey(const ValueKey('delivery_phone')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('delivery_phone')), '0300123');
    await settle();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('delivery_address'))).controller!.text, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('delivery_phone')), '+92 300 1234567');
    await settle();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('delivery_name'))).controller!.text, 'Sara');
    expect(find.text('Home'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('delivery_address'))).controller!.text, 'Home');
    await tester.enterText(find.byKey(const ValueKey('delivery_phone')), '03111111111');
    await settle();
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('delivery_name'))).controller!.text, isEmpty);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('delivery_address'))).controller!.text, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('delivery_phone')), '03001234567');
    await settle();
    await tester.tap(find.text('Continue to payment'));
    await settle();
    expect(find.byType(TenderCheckoutDialog), findsOneWidget);
    expect(tester.widget<TenderCheckoutDialog>(find.byType(TenderCheckoutDialog)).grandTotal, 625.50);
    await tester.runAsync(() => delivery.saveArea(staffId: 1, id: area.id, name: 'Garden', code: 'G', deliveryFeePaisa: 12550, isActive: false));
    await tester.tap(find.byKey(const ValueKey('commit_checkout_button')));
    await settle();
    expect(find.textContaining('Delivery area is no longer available'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(TenderCheckoutDialog), matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(find.text('Burger'), findsNWidgets(2));
    expect(await tester.runAsync(() => orders.getOrders()), isEmpty);
    await tester.tap(find.byKey(const ValueKey('dining_type_TAKEAWAY')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('proceed_to_tender_button')));
    await tester.pumpAndSettle();
    expect(find.byType(DeliveryDetailsDialog), findsNothing);
    expect(tester.widget<TenderCheckoutDialog>(find.byType(TenderCheckoutDialog)).grandTotal, 500);
  });
}



