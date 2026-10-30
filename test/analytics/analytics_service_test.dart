import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('Manager sees COD value separately from cash after an explicit refund', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
    final auth = AuthService(database: db);
    auth.session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at':'2026-10-25 18:00:00','status':'OPEN','opened_by_staff_id':manager['id']});
    final shift = await db.insert('shifts', {'business_day_id':day,'staff_id':cashier['id'],'opened_at':'2026-10-25 18:00:00','opening_float':100,'status':'OPEN'});
    Future<int> order(int token, double value, String status) => db.insert('orders', {'business_day_id':day,'shift_id':shift,'cashier_id':cashier['id'],'token_number':token,'dining_type':'TAKEAWAY','subtotal':value,'grand_total':value,'payment_status':status,'created_at':'2026-10-26 01:00:00'});
    final paid = await order(1, 400, 'SETTLED');
    await order(2, 250, 'COLLECTION_DUE');
    await db.insert('order_payments', {'order_id':paid,'payment_method':'CASH','amount_tendered':500,'change_returned':0,'amount_tendered_paisa':50000,'change_returned_paisa':0});
    await db.insert('order_payments', {'order_id':paid,'payment_method':'CASH','amount_tendered':-100,'change_returned':0,'amount_tendered_paisa':-10000,'change_returned_paisa':0});
    await db.insert('cash_movements', {'shift_id':shift,'staff_id':cashier['id'],'type':'PAY_OUT','amount':100,'category':'REFUND','notes':'Synthetic refund','created_at':'2026-10-26 01:00:00'});
    final snapshot = await AnalyticsService(database:db, authService:auth).load(AnalyticsQuery(startDate:DateTime(2026,10,25),endDateExclusive:DateTime(2026,10,26)));
    num? metric(AnalyticsFamily family, String id) => snapshot.section(family).metrics.firstWhere((m)=>m.id==id).value;
    expect(metric(AnalyticsFamily.sales,'recorded_value'),65000);
    expect(metric(AnalyticsFamily.sales,'collected_tender'),40000);
    expect(metric(AnalyticsFamily.delivery,'collection_due'),25000);
    expect(metric(AnalyticsFamily.cash,'expected_drawer'),50000);
    expect(metric(AnalyticsFamily.cash,'variance'),isNull);
    expect(snapshot.businessDayIds,[day]);
  });
  test('all report families disclose missing accounting evidence and preserve scoped source facts', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
    final auth = AuthService(database:db)..session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at':'2026-10-25 18:00:00','status':'OPEN','opened_by_staff_id':manager['id']});
    final shift = await db.insert('shifts', {'business_day_id':day,'staff_id':cashier['id'],'opened_at':'2026-10-25 18:00:00','opening_float':0,'status':'OPEN'});
    final ingredient = await db.insert('raw_ingredients', {'name':'Synthetic flour','storage_unit':'kg','current_stock':-3,'low_stock_threshold':2,'created_at':'2026-10-25 18:00:00'});
    await db.insert('mandi_procurements', {'raw_ingredient_id':ingredient,'traditional_unit':'kg','quantity':5,'converted_quantity':5,'total_cost':400,'cost_per_recipe_unit':80,'created_at':'2026-10-26 00:30:00'});
    for (var i=1;i<=2;i++) {
      final order = await db.insert('orders', {'business_day_id':day,'shift_id':shift,'cashier_id':cashier['id'],'token_number':i,'dining_type':'TAKEAWAY','subtotal':100.005,'grand_total':100.005,'payment_status':'SETTLED','customer_phone': i==1 ? '+92 300 1234567' : '03001234567','delivery_address_snapshot':'Private location','created_at':'2026-10-26 01:00:00'});
      await db.insert('order_payments', {'order_id':order,'payment_method':'CASH','amount_tendered':50,'amount_tendered_paisa':5000});
      await db.insert('order_payments', {'order_id':order,'payment_method':'CARD','amount_tendered':50,'amount_tendered_paisa':5000});
    }
    final service = AnalyticsService(database:db,authService:auth);
    final query = AnalyticsQuery(startDate:DateTime(2026,10,25),endDateExclusive:DateTime(2026,10,26),paymentMethod:'CASH');
    final snapshot = await service.load(query);
    num? metric(AnalyticsFamily family,String id) => snapshot.section(family).metrics.firstWhere((m)=>m.id==id).value;
    expect(snapshot.sections.map((s)=>s.family).toSet(), AnalyticsFamily.values.toSet());
    expect(metric(AnalyticsFamily.sales,'recorded_value'),20002);
    expect(metric(AnalyticsFamily.sales,'collected_tender'),10000);
    expect(snapshot.section(AnalyticsFamily.sales).rows.singleWhere((r)=>r.cells['business_date']!=null).cells['business_date'],'2026-10-25');
    expect(metric(AnalyticsFamily.customers,'repeat_rate'),100);
    expect(metric(AnalyticsFamily.procurement,'purchase_spend'),40000);
    expect(metric(AnalyticsFamily.inventory,'negative_stock'),1);
    expect(snapshot.section(AnalyticsFamily.profitability).metrics.firstWhere((m)=>m.id=='gross_profit').quality,AnalyticsQuality.missing);
    expect(metric(AnalyticsFamily.profitability,'gross_profit'),isNull);
    expect(metric(AnalyticsFamily.staff,'salary_due'),isNull);
    final cells = snapshot.sections.expand((s)=>s.rows).map((r)=>r.cells.toString()).join();
    expect(cells, isNot(contains('Private location')));
    expect(cells, isNot(contains('03001234567')));
    expect(cells, isNot(contains('pin_hash')));
    expect(snapshot.sections.expand((s)=>s.rows).every((r)=>r.sourceId!=null),isTrue);
    final noOrders = await service.load(query.copyWith(cashierId:9999));
    expect(noOrders.section(AnalyticsFamily.sales).metrics.firstWhere((m)=>m.id=='recorded_value').value,0);
    expect(noOrders.section(AnalyticsFamily.inventory).metrics.firstWhere((m)=>m.id=='negative_stock').value,1);
    auth.session.lock();
    await expectLater(service.load(query),throwsStateError);
    auth.session.login(Staff.fromMap(manager));
    await db.update('staff',{'login_enabled':0},where:'id=?',whereArgs:[manager['id']]);
    await expectLater(service.load(query),throwsStateError);
  });
  test('menu popularity aggregates repeated lines and retains contributing source evidence', () async {
    final store = PosDatabase(factory:databaseFactoryFfi, customPath:inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r)=>r['role']!='CASHIER');
    final cashier = staff.firstWhere((r)=>r['role']=='CASHIER');
    final auth = AuthService(database:db)..session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at':'2026-10-25 18:00:00','status':'OPEN','opened_by_staff_id':manager['id']});
    final shift = await db.insert('shifts', {'business_day_id':day,'staff_id':cashier['id'],'opened_at':'2026-10-25 18:00:00','opening_float':0,'status':'OPEN'});
    final category = await db.insert('categories', {'name':'Synthetic menu','color_hex':'#FFFFFF','created_at':'2026-10-25 18:00:00'});
    final popular = await db.insert('menu_items', {'name':'Often ordered','category_id':category,'base_price':100,'created_at':'2026-10-25 18:00:00'});
    final other = await db.insert('menu_items', {'name':'One larger line','category_id':category,'base_price':100,'created_at':'2026-10-25 18:00:00'});
    final lineIds = <int>[];
    for(var i=1;i<=3;i++) {
      final order = await db.insert('orders', {'business_day_id':day,'shift_id':shift,'cashier_id':cashier['id'],'token_number':i,'dining_type':'TAKEAWAY','subtotal':100,'grand_total':100,'payment_status':'SETTLED','created_at':'2026-10-26 01:00:00'});
      lineIds.add(await db.insert('order_items', {'order_id':order,'menu_item_id':popular,'name':'Often ordered','quantity':1,'unit_price':100,'total_price':100,'created_at':'2026-10-26 01:00:00'}));
      if(i==1) await db.insert('order_items', {'order_id':order,'menu_item_id':other,'name':'One larger line','quantity':2,'unit_price':100,'total_price':200,'created_at':'2026-10-26 01:00:00'});
    }
    final snapshot = await AnalyticsService(database:db,authService:auth).load(AnalyticsQuery(startDate:DateTime(2026,10,25),endDateExclusive:DateTime(2026,10,26)));
    final menu = snapshot.section(AnalyticsFamily.menu);
    final aggregate = menu.rows.singleWhere((r)=>r.cells['catalog_id']==popular && r.cells['kind']=='Item/deal aggregate');
    expect(aggregate.cells['quantity'],3);
    expect(aggregate.cells['order_count'],3);
    expect(aggregate.cells['line_value_paisa'],30000);
    expect(aggregate.cells['popularity_rank'],1);
    expect(aggregate.sourceType,'order_items');
    expect(aggregate.sourceId,lineIds.join(','));
    expect(menu.metrics.firstWhere((m)=>m.id=='item_margin').value,isNull);
  });

  test('Supplier Khata reconciles opening-to-closing bridge and nonoverlapping aging buckets at cutoff', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));

    await db.insert('business_days', {
      'opened_at': '2026-10-25 18:00:00',
      'status': 'OPEN',
      'opened_by_staff_id': manager['id'],
    });

    // 1. Active vendor with 50,000 paisa opening
    final activeVendor = await db.insert('vendor_khata', {
      'name': 'Fresh Produce Co',
      'phone': '03001112233',
      'opening_balance': 500.0,
      'current_balance': 1600.0,
      'created_at': '2026-10-20 10:00:00',
      'updated_at': '2026-10-25 19:00:00',
    });

    // 2. Archived vendor with 20,000 paisa opening
    final archivedVendor = await db.insert('vendor_khata', {
      'name': 'Old Dairy Ltd',
      'phone': '03004445566',
      'opening_balance': 200.0,
      'current_balance': 200.0,
      'created_at': '2026-10-15 10:00:00',
      'updated_at': '2026-10-25 10:00:00',
      'archived_at': '2026-10-24 12:00:00',
    });

    // In-interval purchase on active vendor (due 2026-10-28 -> Current / not yet due at 2026-10-26)
    await db.insert('vendor_transactions', {
      'vendor_id': activeVendor,
      'type': 'PURCHASE_CREDIT',
      'amount': 1000.0,
      'amount_paisa': 100000,
      'due_date': '2026-10-28',
      'created_at': '2026-10-25 20:00:00',
    });

    // In-interval purchase on active vendor (due 2026-10-18 -> 8 days overdue at 2026-10-26 -> 8-30 days bucket)
    await db.insert('vendor_transactions', {
      'vendor_id': activeVendor,
      'type': 'PURCHASE_CREDIT',
      'amount': 400.0,
      'amount_paisa': 40000,
      'due_date': '2026-10-18',
      'created_at': '2026-10-25 21:00:00',
    });

    // In-interval payment (30,000 paisa allocated to opening balance)
    final pay1 = await db.insert('vendor_transactions', {
      'vendor_id': activeVendor,
      'type': 'PAYMENT_EXTERNAL',
      'amount': 300.0,
      'amount_paisa': 30000,
      'created_at': '2026-10-25 22:00:00',
    });
    await db.insert('supplier_payment_allocations', {
      'payment_id': pay1,
      'invoice_id': null,
      'amount_paisa': 30000,
      'created_at': '2026-10-25 22:00:00',
    });

    final query = AnalyticsQuery(
      startDate: DateTime(2026, 10, 25),
      endDateExclusive: DateTime(2026, 10, 26),
    );
    final snapshot = await AnalyticsService(database: db, authService: auth).load(query);
    final section = snapshot.section(AnalyticsFamily.suppliers);

    num? metric(String id) => section.metrics.firstWhere((m) => m.id == id).value;

    // Bridge: Opening (70,000) + Purchases (140,000) - Payments (30,000) = Closing (180,000)
    expect(metric('khata_opening_payable'), 70000);
    expect(metric('credit_purchases'), 140000);
    expect(metric('khata_payments'), 30000);
    expect(metric('khata_closing_payable'), 180000);

    // Aging: Current (100,000) + Days 8-30 (40,000) + Unknown (20,000 active opening + 20,000 archived opening = 40,000)
    expect(metric('aging_current'), 100000);
    expect(metric('aging_8_30'), 40000);
    expect(metric('aging_unknown'), 40000);
    expect(metric('aging_0_7'), 0);
    expect(metric('aging_31_60'), 0);
    expect(metric('aging_over_60'), 0);

    // Exact sum equals closing payable
    final sumAging = (metric('aging_current') ?? 0) +
        (metric('aging_0_7') ?? 0) +
        (metric('aging_8_30') ?? 0) +
        (metric('aging_31_60') ?? 0) +
        (metric('aging_over_60') ?? 0) +
        (metric('aging_unknown') ?? 0);
    expect(sumAging, equals(180000));

    // Coverage & Archiving disclosure
    final activeRow = section.rows.firstWhere((r) => r.cells['supplier_id'] == activeVendor && r.cells['kind'] == 'Vendor Khata bridge');
    final archivedRow = section.rows.firstWhere((r) => r.cells['supplier_id'] == archivedVendor && r.cells['kind'] == 'Vendor Khata bridge');
    expect(activeRow.cells['status'], 'Active');
    expect(archivedRow.cells['status'], 'Archived');
  });


  test('Ingredient normalized-unit stock bridge reconciles opening, receipts, consumption, waste, returns, adjustments to ending quantity', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));

    final day = await db.insert('business_days', {
      'opened_at': '2026-10-25 18:00:00',
      'status': 'OPEN',
      'opened_by_staff_id': manager['id'],
    });

    // 1. Create ingredient with base unit 'g'
    final ingId = await db.insert('raw_ingredients', {
      'name': 'Marinated Chicken',
      'storage_unit': 'g',
      'current_stock': 1260.0,
      'low_stock_threshold': 200.0,
      'cost_per_recipe_unit': 0.85,
      'created_at': '2026-10-20 10:00:00',
    });

    // Initial movement before interval start (recorded opening balance = 1000g)
    await db.insert('inventory_movements', {
      'ingredient_id': ingId,
      'business_day_id': day,
      'quantity_delta': 1000.0,
      'balance_after': 1000.0,
      'recorded_at': '2026-10-24 12:00:00',
    });

    // Mandi procurement receipt (+500g) in interval
    await db.insert('mandi_procurements', {
      'raw_ingredient_id': ingId,
      'traditional_unit': 'g',
      'quantity': 500.0,
      'converted_quantity': 500.0,
      'total_cost': 425.0,
      'cost_per_recipe_unit': 0.85,
      'created_at': '2026-10-25 19:00:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': ingId,
      'business_day_id': day,
      'quantity_delta': 500.0,
      'balance_after': 1500.0,
      'recorded_at': '2026-10-25 19:00:00',
    });

    final shift = await db.insert('shifts', {
      'business_day_id': day,
      'staff_id': manager['id'],
      'opened_at': '2026-10-25 18:00:00',
      'opening_float': 0,
      'status': 'OPEN',
    });

    // Order dummy row
    final orderId = await db.insert('orders', {
      'business_day_id': day,
      'shift_id': shift,
      'cashier_id': manager['id'],
      'token_number': 101,
      'dining_type': 'DINE_IN',
      'subtotal': 300,
      'grand_total': 300,
      'payment_status': 'SETTLED',
      'created_at': '2026-10-25 20:00:00',
    });

    // Consumption via order_cost_events (-200g)
    await db.insert('order_cost_events', {
      'order_id': orderId,
      'ingredient_id': ingId,
      'revision': 1,
      'kind': 'CONSUME',
      'quantity': 200.0,
      'unit_cost_rupees': 0.85,
      'cost_paisa': 17000,
      'recorded_at': '2026-10-25 20:15:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': ingId,
      'business_day_id': day,
      'quantity_delta': -200.0,
      'balance_after': 1300.0,
      'recorded_at': '2026-10-25 20:15:00',
    });

    // Kitchen wastage (-50g)
    await db.insert('kitchen_wastage', {
      'raw_ingredient_id': ingId,
      'staff_id': manager['id'],
      'quantity': 50.0,
      'cost_loss': 42.5,
      'reason': 'Burnt during prep',
      'created_at': '2026-10-25 21:00:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': ingId,
      'business_day_id': day,
      'quantity_delta': -50.0,
      'balance_after': 1250.0,
      'recorded_at': '2026-10-25 21:00:00',
    });

    // Order return (+20g)
    await db.insert('order_cost_events', {
      'order_id': orderId,
      'ingredient_id': ingId,
      'revision': 2,
      'kind': 'RETURN',
      'quantity': 20.0,
      'unit_cost_rupees': 0.85,
      'cost_paisa': 1700,
      'recorded_at': '2026-10-25 21:30:00',
    });
    await db.insert('inventory_movements', {
      'ingredient_id': ingId,
      'business_day_id': day,
      'quantity_delta': 20.0,
      'balance_after': 1270.0,
      'recorded_at': '2026-10-25 21:30:00',
    });

    // Posted stock count variance adjustment (-10g)
    final countId = await db.insert('stock_counts', {
      'status': 'DRAFT',
      'created_by': manager['id'],
      'reason': 'Shift close audit',
      'created_at': '2026-10-25 21:50:00',
    });
    await db.insert('stock_count_lines', {
      'count_id': countId,
      'ingredient_id': ingId,
      'expected': 1270.0,
      'counted': 1260.0,
      'variance': -10.0,
      'unit': 'g',
      'snapshot_sequence': 5,
    });
    await db.update('stock_counts', {
      'status': 'POSTED',
      'posted_at': '2026-10-25 22:00:00',
    }, where: 'id = ?', whereArgs: [countId]);
    await db.insert('inventory_movements', {
      'ingredient_id': ingId,
      'business_day_id': day,
      'quantity_delta': -10.0,
      'balance_after': 1260.0,
      'recorded_at': '2026-10-25 22:00:00',
    });

    final query = AnalyticsQuery(
      startDate: DateTime(2026, 10, 25),
      endDateExclusive: DateTime(2026, 10, 26),
    );
    final snapshot = await AnalyticsService(database: db, authService: auth).load(query);
    final invSection = snapshot.section(AnalyticsFamily.inventory);

    final bridgeRow = invSection.rows.firstWhere((r) => r.cells['ingredient_id'] == ingId && r.cells['kind'] == 'Normalized stock bridge');
    expect(bridgeRow.cells['opening_qty'], equals(1000.0));
    expect(bridgeRow.cells['receipts_qty'], equals(500.0));
    expect(bridgeRow.cells['consumption_qty'], equals(200.0));
    expect(bridgeRow.cells['waste_qty'], equals(50.0));
    expect(bridgeRow.cells['returns_qty'], equals(20.0));
    expect(bridgeRow.cells['adjustments_qty'], equals(-10.0));
    expect(bridgeRow.cells['unexplained_variance'], equals(0.0));
    expect(bridgeRow.cells['reconciliation_status'], equals('Reconciled'));
    expect(bridgeRow.cells['ending_qty'], equals(1260.0));
    expect(bridgeRow.cells['unit'], equals('g'));
    expect(bridgeRow.cells['has_opening_evidence'], equals('Verified'));

    // Verify procurement receipt row is exposed as contributor
    final receiptRow = invSection.rows.firstWhere((r) => r.cells['ingredient_id'] == ingId && r.cells['kind'] == 'Procurement receipt');
    expect(receiptRow.cells['quantity'], equals(500.0));

    // Check reconciliation: opening + receipts - consumption - waste + returns + adjustments = ending
    final calculatedEnding = (bridgeRow.cells['opening_qty'] as double) +
        (bridgeRow.cells['receipts_qty'] as double) -
        (bridgeRow.cells['consumption_qty'] as double) -
        (bridgeRow.cells['waste_qty'] as double) +
        (bridgeRow.cells['returns_qty'] as double) +
        (bridgeRow.cells['adjustments_qty'] as double);
    expect(calculatedEnding, equals(1260.0));

    // Verify stock valuation metric remains honestly missing (policy undecided until #90)
    final valMetric = invSection.metrics.firstWhere((m) => m.id == 'stock_valuation');
    expect(valMetric.quality, equals(AnalyticsQuality.missing));

    // Reconciled ingredients metric
    final recMetric = invSection.metrics.firstWhere((m) => m.id == 'reconciled_ingredients');
    expect(recMetric.value, greaterThanOrEqualTo(1));
  });

}