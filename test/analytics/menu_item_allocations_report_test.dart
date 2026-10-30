import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('Menu Analytics with Allocated Net Sales, Margins and Legacy Coverage', () {
    test('reports allocated net sales, BOM recipe cost, and contribution margins for orders with allocations', () async {
      final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      final db = await store.initialize();
      addTearDown(store.close);

      final staff = await db.query('staff');
      final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
      final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
      final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));

      final dayId = await db.insert('business_days', {
        'opened_at': '2026-10-30 10:00:00',
        'status': 'OPEN',
        'opened_by_staff_id': manager['id'],
      });
      final shiftId = await db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': cashier['id'],
        'opened_at': '2026-10-30 10:00:00',
        'opening_float': 1000,
        'status': 'OPEN',
      });

      // Insert catalog items and recipes
      final categoryId = await db.insert('categories', {
        'name': 'Burgers',
        'color_hex': '#FF0000',
        'created_at': '2026-10-30 10:00:00',
      });
      final beefBurgerId = await db.insert('menu_items', {
        'name': 'Beef Burger',
        'category_id': categoryId,
        'base_price': 650.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': '2026-10-30 10:00:00',
      });
      final loadedFriesId = await db.insert('menu_items', {
        'name': 'Loaded Fries',
        'category_id': categoryId,
        'base_price': 350.0,
        'tax_rate': 0.0,
        'is_tax_inclusive': 1,
        'is_active': 1,
        'created_at': '2026-10-30 10:00:00',
      });

      // Ingredients & recipes
      final beefIngId = await db.insert('raw_ingredients', {
        'name': 'Beef Patty',
        'storage_unit': 'piece',
        'current_stock': 100,
        'low_stock_threshold': 10,
        'cost_per_recipe_unit': 200.0, // 200 PKR = 20,000 paisa
        'created_at': '2026-10-30 10:00:00',
      });
      final potatoIngId = await db.insert('raw_ingredients', {
        'name': 'Potato Fries',
        'storage_unit': 'portion',
        'current_stock': 100,
        'low_stock_threshold': 10,
        'cost_per_recipe_unit': 100.0, // 100 PKR = 10,000 paisa
        'created_at': '2026-10-30 10:00:00',
      });
      await db.insert('recipes', {
        'menu_item_id': beefBurgerId,
        'raw_ingredient_id': beefIngId,
        'quantity_per_recipe_unit': 1.0,
        'created_at': '2026-10-30 10:00:00',
      });
      await db.insert('recipes', {
        'menu_item_id': loadedFriesId,
        'raw_ingredient_id': potatoIngId,
        'quantity_per_recipe_unit': 1.0,
        'created_at': '2026-10-30 10:00:00',
      });

      // Insert discount preset
      final discountId = await db.insert('discount_presets', {
        'name': 'Flat 100 Off',
        'type': 'FLAT',
        'value': 100.0, // 100 PKR = 10,000 paisa
        'is_active': 1,
        'rules_json': '{}',
        'created_at': '2026-10-30T10:00:00.000Z',
      });
      final discount = DiscountPreset.fromMap(
        (await db.query('discount_presets', where: 'id = ?', whereArgs: [discountId])).single,
      );

      // Perform checkout via OrderAndCheckoutController
      final controller = OrderAndCheckoutController(database: db);
      final burgerItem = CartItem(
        menuItem: MenuItem(
          id: beefBurgerId,
          categoryId: categoryId,
          name: 'Beef Burger',
          basePrice: 650.0,
          taxRate: 0.0,
          isTaxInclusive: true,
          isActive: true,
          createdAt: DateTime.parse('2026-10-30T10:00:00Z'),
        ),
        quantity: 1,
      );
      final friesItem = CartItem(
        menuItem: MenuItem(
          id: loadedFriesId,
          categoryId: categoryId,
          name: 'Loaded Fries',
          basePrice: 350.0,
          taxRate: 0.0,
          isTaxInclusive: true,
          isActive: true,
          createdAt: DateTime.parse('2026-10-30T10:00:00Z'),
        ),
        quantity: 1,
      );

      // Subtotal: 650 + 350 = 1,000 PKR (100,000 paisa). Discount: 100 PKR (10,000 paisa).
      // Grand Total: 900 PKR (90,000 paisa).
      await controller.checkoutOrder(
        businessDayId: dayId,
        shiftId: shiftId,
        cashierId: cashier['id'] as int,
        diningType: DiningType.takeaway,
        items: [burgerItem, friesItem],
        discount: discount,
        payments: const [
          PaymentTender(method: PaymentMethod.cash, amountTendered: 900.0),
        ],
      );

      // Verify that allocations were persisted to order_item_allocations
      final allocations = await db.query('order_item_allocations');
      expect(allocations, isNotEmpty, reason: 'Line-level allocations must be persisted at checkout');

      // Proportional discount check:
      // Burger gross 65,000 / 100,000 * 10,000 = 6,500 paisa discount -> net 58,500 paisa
      // Fries gross 35,000 / 100,000 * 10,000 = 3,500 paisa discount -> net 31,500 paisa
      // Burger BOM cost = 20,000 paisa -> Margin = 58,500 - 20,000 = 38,500 paisa
      // Fries BOM cost = 10,000 paisa -> Margin = 31,500 - 10,000 = 21,500 paisa
      final burgerAlloc = allocations.firstWhere((a) => a['menu_item_id'] == beefBurgerId);
      expect(burgerAlloc['gross_sales_paisa'], 65000);
      expect(burgerAlloc['allocated_discount_paisa'], 6500);
      expect(burgerAlloc['net_sales_paisa'], 58500);
      expect(burgerAlloc['bom_recipe_cost_paisa'], 20000);
      expect(burgerAlloc['contribution_margin_paisa'], 38500);

      // Load analytics
      final service = AnalyticsService(database: db, authService: auth);
      final snapshot = await service.load(AnalyticsQuery(
        startDate: DateTime(2026, 10, 30),
        endDateExclusive: DateTime(2026, 10, 31),
      ));

      final menuSection = snapshot.section(AnalyticsFamily.menu);

      // 100% allocation coverage
      final coverage = menuSection.metrics.firstWhere((m) => m.id == 'allocation_coverage');
      expect(coverage.value, 100.0);

      // Check item_net_sales and item_margin metrics
      final netSalesMetric = menuSection.metrics.firstWhere((m) => m.id == 'item_net_sales');
      expect(netSalesMetric.value, 90000, reason: 'Total net sales must be 90,000 paisa');

      final marginMetric = menuSection.metrics.firstWhere((m) => m.id == 'item_margin');
      expect(marginMetric.value, 60000, reason: 'Total margin: 38,500 + 21,500 = 60,000 paisa');

      // Check aggregate rows
      final burgerRow = menuSection.rows.firstWhere((r) => r.cells['catalog_id'] == beefBurgerId);
      expect(burgerRow.cells['line_value_paisa'], 65000);
      expect(burgerRow.cells['allocated_discount_paisa'], 6500);
      expect(burgerRow.cells['net_sales_paisa'], 58500);
      expect(burgerRow.cells['bom_recipe_cost_paisa'], 20000);
      expect(burgerRow.cells['margin_paisa'], 38500);

      // Check export parity (CSV includes net sales and margins)
      final csvData = AnalyticsExportService().csv(snapshot, AnalyticsFamily.menu);
      expect(csvData, contains('allocated discount paisa'));
      expect(csvData, contains('net sales paisa'));
      expect(csvData, contains('bom recipe cost paisa'));
      expect(csvData, contains('margin paisa'));
    });

    test('reconciles legacy unallocated orders explicitly using Legacy Unallocated bucket without retroactive estimation', () async {
      final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      final db = await store.initialize();
      addTearDown(store.close);

      final staff = await db.query('staff');
      final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
      final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
      final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));

      final dayId = await db.insert('business_days', {
        'opened_at': '2026-10-30 10:00:00',
        'status': 'OPEN',
        'opened_by_staff_id': manager['id'],
      });
      final shiftId = await db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': cashier['id'],
        'opened_at': '2026-10-30 10:00:00',
        'opening_float': 1000,
        'status': 'OPEN',
      });

      // Insert legacy closed order directly into orders and order_items (NO order_item_allocations)
      final legacyOrderId = await db.insert('orders', {
        'business_day_id': dayId,
        'shift_id': shiftId,
        'cashier_id': cashier['id'],
        'token_number': 101,
        'dining_type': 'TAKEAWAY',
        'subtotal': 500.0,
        'discount_amount': 50.0, // 5,000 paisa discount
        'tax_amount': 0.0,
        'grand_total': 450.0, // 45,000 paisa net
        'payment_status': 'SETTLED',
        'created_at': '2026-10-30 11:00:00',
      });
      await db.insert('order_items', {
        'order_id': legacyOrderId,
        'name': 'Legacy Sandwich',
        'quantity': 1,
        'unit_price': 500.0,
        'total_price': 500.0,
        'created_at': '2026-10-30 11:00:00',
      });

      // Load analytics
      final service = AnalyticsService(database: db, authService: auth);
      final snapshot = await service.load(AnalyticsQuery(
        startDate: DateTime(2026, 10, 30),
        endDateExclusive: DateTime(2026, 10, 31),
      ));

      final menuSection = snapshot.section(AnalyticsFamily.menu);

      // Allocation coverage must be 0% (0 / 1 order allocated)
      final coverage = menuSection.metrics.firstWhere((m) => m.id == 'allocation_coverage');
      expect(coverage.value, 0.0);
      expect(coverage.sampleCount, 0);
      expect(coverage.populationCount, 1);

      // Explicit "Legacy Unallocated Order Discounts" row must be present
      final legacyRow = menuSection.rows.firstWhere((r) => r.id == 'menu-legacy-unallocated-discounts');
      expect(legacyRow.cells['name'], 'Legacy Unallocated Order Discounts');
      expect(legacyRow.cells['allocated_discount_paisa'], 5000);
      expect(legacyRow.cells['net_sales_paisa'], -5000);

      // Reconciliation:
      // Item gross = 50,000 paisa
      // Legacy unallocated discount = 5,000 paisa
      // Total net sales = 45,000 paisa = Order grand total!
      final itemRow = menuSection.rows.firstWhere((r) => r.cells['name'] == 'Legacy Sandwich');
      expect(itemRow.cells['line_value_paisa'], 50000);
    });
  });
}
