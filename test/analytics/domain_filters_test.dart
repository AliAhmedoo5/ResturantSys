import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/discount_rules.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import '../orders/order_and_checkout_controller_test.dart' show publishFixtures;
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/procurement/desi_unit.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('expense category scope reconciles postings and exports while drawer stays whole', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((r) => r['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final cashierId = people.firstWhere((r) => r['role'] == 'CASHIER')['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    final shift = await shifts.openShift(staffId: cashierId, openingFloat: 1000);
    final operations = OperationsController(db);
    final utilities = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    final repairs = await operations.saveCategory(managerId: managerId, name: 'Repairs');
    for (final item in [(utilities, 12000), (repairs, 7000)]) {
      await operations.postExpense(managerId: managerId, categoryId: item.$1,
        amountPaisa: item.$2, description: 'Synthetic expense', source: FundingSource.drawer,
        shiftId: shift.id, reason: 'Paid', requestKey: 'filter-${item.$1}');
    }
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100),
      live: true, domainFilters: {AnalyticsDimension.expenseCategory: '$utilities'});
    final snapshot = await service.load(query);
    expect(snapshot.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'operating_expense').value, 12000);
    expect(snapshot.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Expense ledger'), hasLength(1));
    expect(snapshot.section(AnalyticsFamily.cash).metrics.singleWhere((m) => m.id == 'expected_drawer').value, 81000);
    expect(snapshot.filterOptions.singleWhere((o) => o.dimension == AnalyticsDimension.expenseCategory && o.id == '$utilities').label, 'Utilities');
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(csv, contains('expenseCategory'));
    expect(csv, contains('Utilities'));
    expect(snapshot.notes.join(' '), contains('outside scope'));
    final clear = await service.load(query.copyWith(domainFilters: {}));
    expect(clear.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'operating_expense').value, 19000);
    expect(snapshot.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'operating_expense').value, 12000);
  });
  test('supplier acquisitions use retained identities and disclose unlinked Mandi coverage', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((r) => r['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    await ShiftAndCashController(database: db).openBusinessDay(openedByStaffId: managerId);
    final catalog = CatalogAndRecipeController(database: db);
    final flour = await catalog.createRawIngredient(name: 'Synthetic flour', storageUnit: StorageUnit.kg);
    final khata = VendorKhataController(database: db);
    final supplier = await khata.createVendor(name: 'Selected supplier', phone: '03001112233');
    final other = await khata.createVendor(name: 'Other supplier', phone: '03009998877');
    for (final vendor in [supplier, other]) {
      await khata.setSuppliedItems(managerId: managerId, vendorId: vendor.id, ingredientIds: {flour.id});
    }
    final selected = await khata.recordCreditDelivery(vendorId: supplier.id, amount: 400,
      rawIngredientId: flour.id, quantity: 5, staffId: managerId, requestKey: 'selected');
    await khata.recordCreditDelivery(vendorId: other.id, amount: 300,
      rawIngredientId: flour.id, quantity: 3, staffId: managerId, requestKey: 'other');
    await ProcurementAndWastageController(database: db).recordMandiPurchase(
      rawIngredientId: flour.id, unit: DesiUnit.dharri, quantity: 1, totalCost: 200);
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100), live: true,
        domainFilters: {AnalyticsDimension.supplier: '${supplier.id}', AnalyticsDimension.ingredient: '${flour.id}'}));
    final report = snapshot.section(AnalyticsFamily.procurement);
    expect(report.metrics.singleWhere((m) => m.id == 'supplier_acquisition_value').value, 40000);
    expect(report.metrics.singleWhere((m) => m.id == 'purchase_spend').value, 0);
    expect(report.charts.singleWhere((c) => c.id == 'supplier_acquisition_dates').points.single.value, 40000);
    expect(report.rows.where((r) => r.cells['kind'] == 'Supplier credit acquisition').single.sourceId, '${selected.id}');
    expect(report.notes.join(' '), contains('supplier unknown'));
    expect(snapshot.section(AnalyticsFamily.suppliers).rows.where((r) => r.sourceType == 'vendor_transactions').every((r) => r.cells['supplier_id'] == supplier.id), isTrue);
    expect(AnalyticsExportService().csv(snapshot, AnalyticsFamily.procurement), contains('Selected supplier'));
  });

  test('expense category follows actual event time independently of posting window', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final manager = (await db.query('staff')).firstWhere((r) => r['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    await ShiftAndCashController(database: db).openBusinessDay(openedByStaffId: managerId, openedAt: DateTime.utc(2026, 8, 31, 8));
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Late bank expense');
    await operations.postExpense(managerId: managerId, categoryId: category, amountPaisa: 9000,
      description: 'Posted later', source: FundingSource.bank, reason: 'Late entry',
      requestKey: 'late-bank', actualAt: DateTime.utc(2026, 9, 1, 8));
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final snapshot = await AnalyticsService(database: db, authService: auth).load(AnalyticsQuery(
      startDate: DateTime(2026, 9, 1), endDateExclusive: DateTime(2026, 9, 2),
      timeBasis: AnalyticsTimeBasis.calendarTime, domainFilters: {AnalyticsDimension.expenseCategory: '$category'}));
    expect(snapshot.section(AnalyticsFamily.expenses).metrics.singleWhere((m) => m.id == 'finance_bank_outflow').value, 9000);
    expect(snapshot.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Finance payment'), hasLength(1));
  });

  test('Menu Item predicates reconcile full Order cohorts and matching Menu lines', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((r) => r['role'] != 'CASHIER');
    final cashierId = people.firstWhere((r) => r['role'] == 'CASHIER')['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    final shift = await shifts.openShift(staffId: cashierId, openingFloat: 0);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Synthetic meals', displayOrder: 1, colorHex: '#FFFFFF');
    final tea = await catalog.createMenuItem(categoryId: category.id, name: 'Selected tea', basePrice: 100);
    final meal = await catalog.createMenuItem(categoryId: category.id, name: 'Other meal', basePrice: 200);
    await publishFixtures(catalog);
    final orders = OrderAndCheckoutController(database: db);
    final selected = await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id,
      cashierId: cashierId, diningType: DiningType.takeaway,
      items: [CartItem(menuItem: await catalog.getMenuItem(tea.id)), CartItem(menuItem: await catalog.getMenuItem(meal.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 300)]);
    await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id,
      cashierId: cashierId, diningType: DiningType.takeaway,
      items: [CartItem(menuItem: await catalog.getMenuItem(meal.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 200)]);
    final discounts = <DiscountPreset>[];
    for (final name in ['First saving', 'Second saving']) {
      final preset = await catalog.createDiscountPreset(name: name, type: DiscountType.flat, value: 10);
      await catalog.saveManagedDiscount(managerId: manager['id'] as int, preset: DiscountPreset(
        id: preset.id, name: name, type: DiscountType.flat, value: 10, isActive: true,
        rules: const DiscountRules(stackable: true)));
      discounts.add(preset);
    }
    await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id,
      cashierId: cashierId, diningType: DiningType.takeaway,
      items: [CartItem(menuItem: await catalog.getMenuItem(meal.id))],
      discountIds: discounts.map((d) => d.id).toList(),
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 180)]);
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100), live: true,
      domainFilters: {AnalyticsDimension.menuItem: '${tea.id}', AnalyticsDimension.menuCategory: '${category.id}', AnalyticsDimension.customerSegment: 'guest'});
    final snapshot = await service.load(query);
    final sales = snapshot.section(AnalyticsFamily.sales);
    expect(sales.metrics.singleWhere((m) => m.id == 'recorded_value').value, 30000);
    expect(sales.rows.where((r) => r.cells['kind'] == 'Daily total').single.cells['orders'], 1);
    expect(snapshot.section(AnalyticsFamily.orders).rows.where((r) => r.sourceType == 'orders').single.sourceId, '${selected.order.id}');
    final menu = snapshot.section(AnalyticsFamily.menu);
    expect(menu.metrics.singleWhere((m) => m.id == 'line_value').value, 10000);
    expect(menu.charts.singleWhere((c) => c.id == 'menu_value').points.single.value, 10000);
    expect(snapshot.section(AnalyticsFamily.cash).metrics.singleWhere((m) => m.id == 'expected_drawer').value, 68000);
    expect(await service.loadCustomerDetails(query.copyWith(domainFilters: {AnalyticsDimension.menuItem: '${tea.id}', AnalyticsDimension.customerSegment: 'known'})), isEmpty);
    expect(AnalyticsExportService().csv(snapshot, AnalyticsFamily.menu), contains('Selected tea'));
    final secondary = await service.load(query.copyWith(domainFilters: {AnalyticsDimension.discount: '${discounts.last.id}'}));
    expect(secondary.section(AnalyticsFamily.sales).metrics.singleWhere((m) => m.id == 'recorded_value').value, 18000);
  });

}
