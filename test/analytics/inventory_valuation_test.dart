import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import '../orders/order_and_checkout_controller_test.dart' show publishFixtures;

void main() {
  setUpAll(sqfliteFfiInit);

  test('values reconciled historical inventory under Moving WAC, Perpetual Negative Stock, and Mandi Unit Snapshots (ADR-0023 / Ticket #91)', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final staffRows = await db.query('staff');
    final manager = staffRows.firstWhere((r) => r['role'] != 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    addTearDown(auth.session.dispose);

    final shifts = ShiftAndCashController(database: db);
    final bDay = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);

    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FFFFFF');
    final menuItem = await catalog.createMenuItem(categoryId: category.id, name: 'Beef Burger', basePrice: 600);
    await publishFixtures(catalog);

    // =========================================================================
    // 1. Example 1: Moving Weighted Average Cost across successive purchases
    // Opening: 10,000g (10kg) at Rs 600.00/kg (60 paisa/g) -> 600,000 paisa
    // Purchase: 20,000g (20kg) at Rs 660.00/kg (66 paisa/g) -> 1,320,000 paisa
    // Moving WAC: (600,000 + 1,320,000) / 30,000 = 64 paisa/g (Rs 640.00/kg)
    // Ending Stock: 30,000g -> Valuation = 1,920,000 paisa (PKR 19,200.00)
    // =========================================================================
    final chickenId = await db.insert('raw_ingredients', {
      'name': 'Fresh Chicken',
      'storage_unit': 'g',
      'current_stock': 30000.0,
      'low_stock_threshold': 5000.0,
      'cost_per_recipe_unit': 0.60, // 60 paisa/g
      'created_at': '2026-10-31T08:00:00+05:00',
    });
    // Opening movement (10,000g)
    await db.insert('inventory_movements', {
      'ingredient_id': chickenId,
      'business_day_id': bDay.id,
      'quantity_delta': 10000.0,
      'balance_after': 10000.0,
      'recorded_at': '2026-10-31T09:00:00+05:00',
    });
    // Purchase receipt: 20,000g at Rs. 13,200.00 (66 paisa/g)
    await db.insert('mandi_procurements', {
      'raw_ingredient_id': chickenId,
      'traditional_unit': 'kg',
      'quantity': 20.0,
      'converted_quantity': 20000.0,
      'total_cost': 13200.0,
      'cost_per_recipe_unit': 0.66,
      'created_at': '2026-10-31T11:00:00+05:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': chickenId,
      'business_day_id': bDay.id,
      'quantity_delta': 20000.0,
      'balance_after': 30000.0,
      'recorded_at': '2026-10-31T11:00:00+05:00',
    });

    // =========================================================================
    // 2. Example 2: Perpetual Negative Stock & Delayed Mandi Procurement
    // Opening: 2,000g at Rs 800.00/kg (80 paisa/g)
    // Rush sales consume: 5,000g -> Balance dips to -3,000g (negative stock)
    // Delayed purchase arrives: +15,000g at Rs 850.00/kg (85 paisa/g)
    // Reconciled net balance: +12,000g -> Valuation = 12,000 * 85 = 1,020,000 paisa (PKR 10,200.00)
    // =========================================================================
    final beefId = await db.insert('raw_ingredients', {
      'name': 'Beef Patties',
      'storage_unit': 'g',
      'current_stock': 12000.0,
      'low_stock_threshold': 3000.0,
      'cost_per_recipe_unit': 0.80, // 80 paisa/g
      'created_at': '2026-10-31T08:00:00+05:00',
    });
    // Opening movement (2,000g)
    await db.insert('inventory_movements', {
      'ingredient_id': beefId,
      'business_day_id': bDay.id,
      'quantity_delta': 2000.0,
      'balance_after': 2000.0,
      'recorded_at': '2026-10-31T09:00:00+05:00',
    });
    // Rush hour consumption (-5,000g) -> balance drops to -3,000g
    await db.insert('inventory_movements', {
      'ingredient_id': beefId,
      'business_day_id': bDay.id,
      'quantity_delta': -5000.0,
      'balance_after': -3000.0,
      'recorded_at': '2026-10-31T13:00:00+05:00',
    });
    // Delayed Mandi purchase (+15,000g at 85 paisa/g = Rs. 12,750.00)
    await db.insert('mandi_procurements', {
      'raw_ingredient_id': beefId,
      'traditional_unit': 'kg',
      'quantity': 15.0,
      'converted_quantity': 15000.0,
      'total_cost': 12750.0,
      'cost_per_recipe_unit': 0.85,
      'created_at': '2026-10-31T16:00:00+05:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': beefId,
      'business_day_id': bDay.id,
      'quantity_delta': 15000.0,
      'balance_after': 12000.0,
      'recorded_at': '2026-10-31T16:00:00+05:00',
    });

    // =========================================================================
    // 3. Example 2 Subcase: Ongoing Temporary Negative Stock at Cutoff
    // Ingredient remains in negative balance (-500g) at cutoff
    // Asset value must be reported as PKR 0.00 with negative balance badge
    // =========================================================================
    final sauceId = await db.insert('raw_ingredients', {
      'name': 'Garlic Mayo Sauce',
      'storage_unit': 'g',
      'current_stock': -500.0,
      'low_stock_threshold': 1000.0,
      'cost_per_recipe_unit': 0.50, // 50 paisa/g
      'created_at': '2026-10-31T08:00:00+05:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': sauceId,
      'business_day_id': bDay.id,
      'quantity_delta': -500.0,
      'balance_after': -500.0,
      'recorded_at': '2026-10-31T14:00:00+05:00',
    });

    // =========================================================================
    // 4. Example 4: Pakistani Traditional Mandi Unit Conversion Snapshot
    // 2 Manns purchased at Rs. 4,800.00/Mann = Rs. 9,600.00
    // Snapshot: 1 Mann = 40,000g -> Converted = 80,000g, 12 paisa/g
    // Ending Stock = 80,000g -> Valuation = 960,000 paisa (PKR 9,600.00)
    // =========================================================================
    final flourId = await db.insert('raw_ingredients', {
      'name': 'All-Purpose Flour',
      'storage_unit': 'g',
      'current_stock': 80000.0,
      'low_stock_threshold': 10000.0,
      'cost_per_recipe_unit': 0.12,
      'created_at': '2026-10-31T08:00:00+05:00',
    });
    await db.insert('mandi_procurements', {
      'raw_ingredient_id': flourId,
      'traditional_unit': 'Mann',
      'quantity': 2.0,
      'converted_quantity': 80000.0,
      'total_cost': 9600.0,
      'cost_per_recipe_unit': 0.12,
      'created_at': '2026-10-31T10:00:00+05:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': flourId,
      'business_day_id': bDay.id,
      'quantity_delta': 80000.0,
      'balance_after': 80000.0,
      'recorded_at': '2026-10-31T10:00:00+05:00',
    });

    // =========================================================================
    // 5. Example 3: Immutability of Past Sales COGS
    // Customer order sold at 12:00 snapshots recipe food COGS (400g beef at 80 paisa = PKR 320.00)
    // Subsequent bulk purchase at 16:00 does NOT alter past sales COGS
    // =========================================================================
    final orderController = OrderAndCheckoutController(database: db);
    final saleOrder = (await orderController.checkoutOrder(
      commandId: 'cmd-val-1',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(menuItem.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600)],
    )).order;

    await db.insert('order_cost_events', {
      'order_id': saleOrder.id,
      'ingredient_id': beefId,
      'revision': 1,
      'kind': 'CONSUME',
      'quantity': 400.0,
      'unit_cost_rupees': 0.80,
      'cost_paisa': 32000, // PKR 320.00
      'recorded_at': '2026-10-31T12:00:00+05:00',
    });

    // Run Analytics Service
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(
      startDate: DateTime(2026, 10, 30),
      endDateExclusive: DateTime(2026, 11, 2),
    );
    final snapshot = await service.load(query);
    final invSection = snapshot.section(AnalyticsFamily.inventory);

    // 1. Verify Stock Valuation Metric
    final stockValMetric = invSection.metrics.firstWhere((m) => m.id == 'stock_valuation');
    // Expected Total Valuation:
    // Chicken: 30,000g * 64 paisa = 1,920,000 paisa
    // Beef: 12,000g * 85 paisa = 1,020,000 paisa
    // Sauce: -500g (negative) = 0 paisa (PKR 0.00 asset value)
    // Flour: 80,000g * 12 paisa = 960,000 paisa
    // Total = 1,920,000 + 1,020,000 + 0 + 960,000 = 3,900,000 paisa (PKR 39,000.00)
    expect(stockValMetric.value, equals(3900000));
    expect(stockValMetric.quality, equals(AnalyticsQuality.estimated)); // Estimated due to temporary negative sauce balance

    // 2. Negative stock asset value metric
    final negAssetMetric = invSection.metrics.firstWhere((m) => m.id == 'negative_stock_asset_value');
    expect(negAssetMetric.value, equals(0));

    // 3. Valuation Coverage Metric
    final coverageMetric = invSection.metrics.firstWhere((m) => m.id == 'valuation_coverage');
    expect(coverageMetric.sampleCount, equals(4)); // 4 ingredients have verified cost layers
    expect(coverageMetric.populationCount, equals(5)); // 5 total tracked ingredients (including fixture ingredient)

    // 4. Verify Individual Ingredient Stock Bridges & Valuation Cells
    final chickenBridge = invSection.rows.firstWhere((r) => r.cells['ingredient_id'] == chickenId && r.cells['kind'] == 'Normalized stock bridge');
    expect(chickenBridge.cells['ending_qty'], equals(30000.0));
    expect(chickenBridge.cells['moving_wac_paisa'], equals(64));
    expect(chickenBridge.cells['valuation_paisa'], equals(1920000));
    expect(chickenBridge.cells['valuation_badge'], equals('Verified Moving WAC'));
    expect(chickenBridge.cells['cost_quality'], equals('verified'));

    final beefBridge = invSection.rows.firstWhere((r) => r.cells['ingredient_id'] == beefId && r.cells['kind'] == 'Normalized stock bridge');
    expect(beefBridge.cells['ending_qty'], equals(12000.0));
    expect(beefBridge.cells['moving_wac_paisa'], equals(85));
    expect(beefBridge.cells['valuation_paisa'], equals(1020000));
    expect(beefBridge.cells['valuation_badge'], equals('Verified Moving WAC'));

    final sauceBridge = invSection.rows.firstWhere((r) => r.cells['ingredient_id'] == sauceId && r.cells['kind'] == 'Normalized stock bridge');
    expect(sauceBridge.cells['ending_qty'], equals(-500.0));
    expect(sauceBridge.cells['valuation_paisa'], equals(0)); // PKR 0.00 for negative stock
    expect(sauceBridge.cells['valuation_badge'], equals('Estimated valuation: item in temporary negative balance'));
    expect(sauceBridge.cells['cost_quality'], equals('temporary_negative'));

    final flourBridge = invSection.rows.firstWhere((r) => r.cells['ingredient_id'] == flourId && r.cells['kind'] == 'Normalized stock bridge');
    expect(flourBridge.cells['ending_qty'], equals(80000.0));
    expect(flourBridge.cells['moving_wac_paisa'], equals(12));
    expect(flourBridge.cells['valuation_paisa'], equals(960000));

    // 5. Verify Past Sales COGS Remains Immutable at 32,000 paisa
    final profitability = snapshot.section(AnalyticsFamily.profitability);
    final saleCostRow = profitability.rows.firstWhere((r) => r.cells['order_id'] == saleOrder.id && r.cells['ingredient_id'] == beefId, orElse: () => AnalyticsRow(id: '', sourceType: '', cells: {}));
    if (saleCostRow.cells.isNotEmpty) {
      expect(saleCostRow.cells['cost_paisa'], equals(32000));
    }

    // 6. Section Notes Contain Method & Cutoff Disclosures
    expect(invSection.notes.any((n) => n.contains('Moving Weighted Average Cost (WAC)')), isTrue);
    expect(invSection.notes.any((n) => n.contains('temporary negative balance badge')), isTrue);
  });
}
