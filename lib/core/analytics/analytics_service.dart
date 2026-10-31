import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite_common/sqlite_api.dart';
import '../auth/auth_service.dart';
import '../auth/staff_role.dart';
import '../orders/paisa_engine.dart';
import '../payments/payment_event.dart';
import '../inventory/stock_count_valuation.dart';
import 'analytics_models.dart';

part 'analytics_reports.dart';
part 'order_workload.dart';
part 'weekday_order_peaks.dart';
part 'finance_timeline.dart';
part 'money_flow_peaks.dart';
part 'customer_report_details.dart';
part 'earned_payroll.dart';
part 'shift_cash_bridge.dart';
part 'hold_aging.dart';
part 'domain_filters.dart';
typedef _Record = Map<String, Object?>;

/// Consistent, authorized reads. Computation runs after releasing SQLite.
class AnalyticsService {
  AnalyticsService({required this.database, required this.authService});
  final Database database;
  final AuthService authService;

  /// Contact information is loaded separately from masked analytics/exports.
  Future<List<CustomerReportProfile>> loadCustomerDetails(AnalyticsQuery query) =>
      _CustomerInformationReader(this).load(query);

  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async {
    final actor = authService.session.currentStaff;
    if (actor == null || !actor.isActive || !actor.canAccessSupervisorPortal) {
      throw StateError('An active Manager session is required.');
    }
    final evidence = await database.transaction((txn) async {
      final staff = await txn.query('staff', columns: ['id', 'role', 'is_active', 'login_enabled'], where: 'id=?', whereArgs: [actor.id]);
      if (staff.isEmpty || staff.single['is_active'] != 1 || staff.single['login_enabled'] != 1 || !StaffRole.fromCode(staff.single['role'] as String).isManager) {
        throw StateError('Manager access is no longer enabled.');
      }
      return _read(txn, query, actor.id);
    });
    if (!identical(authService.session.currentStaff, actor)) throw StateError('Session changed while loading analytics.');
    return _ReportBuilder(evidence).build();
  }

  Future<_Evidence> _read(Transaction txn, AnalyticsQuery query, int actor) async {
    final e = _Evidence(query, actor, DateTime.now().toUtc());
    e.sourceSchemaVersion = (await txn.rawQuery('PRAGMA user_version')).single.values.first as int;
    final dayScope = _dayScope(query);
    final dayArgs = _dayArgs(query);
    final orderScope = _orderCohortScope(query);
    final orderArgs = _orderCohortArgs(query);
    final tables = (await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
    Future<void> read(String key, String table, String sql, [List<Object?> args = const []]) async {
      if (!tables.contains(table)) { e.absent.add(table); e.rows[key] = []; return; }
      e.rows[key] = await txn.rawQuery(sql, args);
    }
    await read('days', 'business_days', 'SELECT b.id,b.opened_at,b.closed_at,b.status FROM business_days b WHERE $dayScope ORDER BY b.opened_at', dayArgs);
    if (query.timeBasis == AnalyticsTimeBasis.calendarTime) {
      await read('peak_coverage_days', 'business_days',
        "SELECT b.id,b.opened_at,b.closed_at,b.status FROM business_days b WHERE ${_localSql('b.opened_at')} < ? AND (b.closed_at IS NULL OR ${_localSql('b.closed_at')} > ?) ORDER BY b.opened_at,b.id",
        [_sqlTime(analyticsWallClock(query.endDateExclusive)), _sqlTime(analyticsWallClock(query.startDate))]);
    }
    const fields = 'o.id,o.business_day_id,o.shift_id,o.cashier_id,o.token_number,o.dining_type,o.subtotal,o.discount_amount,o.discount_id,o.tax_amount,o.grand_total,o.payment_status,o.token_status,o.cash_rounding_paisa,o.delivery_area_id,o.delivery_area_name_snapshot,o.delivery_fee_paisa,o.customer_phone,o.created_at,$outstandingCollectionPaisaSql AS collection_due_paisa';
    final orderFrom = 'FROM orders o JOIN business_days b ON b.id=o.business_day_id WHERE $orderScope';
    await read('orders', 'orders', 'SELECT $fields $orderFrom ORDER BY o.id', orderArgs);
    // Current Holds have no Business Day/Shift assignment or retained deleted
    // lifecycle. Never read private draft content into reporting evidence.
    await read('active_holds', 'held_carts', 'SELECT id,cashier_id,created_at FROM held_carts${query.cashierId == null ? '' : ' WHERE cashier_id=?'} ORDER BY created_at,id', [if (query.cashierId != null) query.cashierId]);
    await read('hold_lifecycle_events', 'hold_lifecycle_events', 'SELECT id,hold_id,cashier_id,event_type,order_id,previous_hold_id,recorded_at FROM hold_lifecycle_events${query.cashierId == null ? '' : ' WHERE cashier_id=?'} ORDER BY recorded_at,id', [if (query.cashierId != null) query.cashierId]);
    await read('first_purchases', 'orders', "SELECT o.id,o.customer_phone,o.created_at FROM orders o WHERE o.customer_phone IS NOT NULL AND o.customer_phone != '' AND o.payment_status NOT IN ('CANCELLED','VOIDED','REFUNDED') ORDER BY o.id");
    await read('order_days', 'business_days', 'SELECT DISTINCT b.id,b.opened_at,b.closed_at,b.status FROM business_days b JOIN orders o ON o.business_day_id=b.id WHERE $orderScope ORDER BY b.opened_at,b.id', orderArgs);
    await read('order_shifts', 'shifts', 'SELECT DISTINCT s.* FROM shifts s JOIN orders o ON o.shift_id=s.id JOIN business_days b ON b.id=o.business_day_id WHERE $orderScope ORDER BY s.id', orderArgs);
    final joinedOrder = 'JOIN orders o ON o.id=x.order_id JOIN business_days b ON b.id=o.business_day_id WHERE $orderScope';
    await read('payments', 'order_payments', 'SELECT x.* FROM order_payments x $joinedOrder', orderArgs);
    // Independent receiving evidence must survive an originating order outside scope.
    await read('payment_events', 'payment_events', 'SELECT x.*,o.business_day_id AS originating_business_day_id,o.shift_id AS originating_shift_id,s.staff_id AS shift_owner_id FROM payment_events x LEFT JOIN orders o ON o.id=x.order_id LEFT JOIN shifts s ON s.id=x.shift_id');
    // Receiving context belongs to independently selected events, including
    // assignments outside the calendar order cohort. It is not drawer scope.
    final selectedDayIds = e.get('days').map((d) => d['id']).toSet();
    final selectedEvents = e.get('payment_events').where((p) {
      if (query.shiftId != null && p['shift_id'] != query.shiftId) return false;
      if (query.cashierId != null && p['shift_owner_id'] != query.cashierId) return false;
      if (['RECEIPT','REFUND'].contains(p['kind']) && query.paymentMethod != null && p['payment_method'] != query.paymentMethod) return false;
      if (query.timeBasis == AnalyticsTimeBasis.calendarTime) {
        final actual = _karachi(p['actual_at']);
        return actual != null && !actual.isBefore(analyticsWallClock(query.startDate)) && actual.isBefore(analyticsWallClock(query.endDateExclusive));
      }
      return selectedDayIds.contains(p['business_day_id']);
    }).toList();
    final eventDayIds = selectedEvents.map((p) => p['business_day_id']).whereType<int>().toSet().toList();
    final eventShiftIds = selectedEvents.map((p) => p['shift_id']).whereType<int>().toSet().toList();
    if (eventDayIds.isNotEmpty) await read('event_days', 'business_days', 'SELECT id,opened_at,closed_at,status FROM business_days WHERE id IN (${List.filled(eventDayIds.length, '?').join(',')})', eventDayIds);
    if (eventShiftIds.isNotEmpty) await read('event_shifts', 'shifts', 'SELECT * FROM shifts WHERE id IN (${List.filled(eventShiftIds.length, '?').join(',')})', eventShiftIds);
    await read('items', 'order_items', 'SELECT x.id,x.order_id,x.menu_item_id,x.deal_id,x.name,x.quantity,x.unit_price,x.total_price,x.modifiers_json,x.deal_choices_json,x.bom_json FROM order_items x $joinedOrder', orderArgs);
    await read('allocations', 'order_item_allocations', 'SELECT x.* FROM order_item_allocations x $joinedOrder', orderArgs);
    await read('revisions', 'order_revisions', 'SELECT x.id,x.order_id,x.revision_no,x.action,x.reason,x.cashier_id,x.created_at_utc,x.money_delta_paisa FROM order_revisions x $joinedOrder', orderArgs);
    await read('order_status_events', 'order_status_events', 'SELECT x.* FROM order_status_events x $joinedOrder ORDER BY x.id', orderArgs);
    await read('cost_coverage', 'order_cost_coverage', 'SELECT x.* FROM order_cost_coverage x $joinedOrder', orderArgs);
    await read('cost_events', 'order_cost_events', 'SELECT x.* FROM order_cost_events x $joinedOrder', orderArgs);
    // A physical drawer uses all orders in its shifts; order filters never alter it.
    await read('shifts', 'shifts', 'SELECT s.* FROM shifts s JOIN business_days b ON b.id=s.business_day_id WHERE $dayScope', dayArgs);
    await read('cash_payments', 'order_payments', "SELECT p.*,COALESCE(pe.shift_id,o.shift_id) AS shift_id FROM order_payments p JOIN orders o ON o.id=p.order_id LEFT JOIN payment_events pe ON pe.tender_id=p.id JOIN business_days b ON b.id=COALESCE(pe.business_day_id,o.business_day_id) WHERE $dayScope AND (pe.id IS NOT NULL OR o.payment_status IN ('SETTLED','REFUND_PENDING','CANCELLED','REFUNDED'))", dayArgs);
    await read('movements', 'cash_movements', 'SELECT m.id,m.shift_id,m.staff_id,m.type,m.amount,m.category,m.approved_by,m.created_at FROM cash_movements m JOIN shifts s ON s.id=m.shift_id JOIN business_days b ON b.id=s.business_day_id WHERE $dayScope', dayArgs);
    // A selected drawer is reconciled over its entire Shift. Calendar buckets
    // and order-only filters never turn a balance into partial cash activity.
    final bridgeScope = query.shiftId == null ? dayScope : 's.id=?';
    final bridgeArgs = query.shiftId == null ? dayArgs : <Object?>[query.shiftId];
    await read('bridge_shifts', 'shifts', 'SELECT s.* FROM shifts s JOIN business_days b ON b.id=s.business_day_id WHERE $bridgeScope${query.cashierId == null ? '' : ' AND s.staff_id=?'}', [...bridgeArgs, if (query.cashierId != null) query.cashierId]);
    final bridgeIds = e.get('bridge_shifts').map((s) => s['id']).toList();
    if (bridgeIds.isNotEmpty) {
      final slots = List.filled(bridgeIds.length, '?').join(',');
      await read('bridge_movements', 'cash_movements', 'SELECT * FROM cash_movements WHERE shift_id IN ($slots)', bridgeIds);
      await read('bridge_payments', 'order_payments', 'SELECT p.*,o.shift_id AS originating_shift_id FROM order_payments p JOIN orders o ON o.id=p.order_id WHERE o.shift_id IN ($slots) OR p.id IN (SELECT tender_id FROM payment_events WHERE shift_id IN ($slots))', [...bridgeIds, ...bridgeIds]);
      await read('bridge_days', 'business_days', 'SELECT DISTINCT b.* FROM business_days b JOIN shifts s ON s.business_day_id=b.id WHERE s.id IN ($slots)', bridgeIds);
    }
    await read('trips', 'rider_trips', 'SELECT t.* FROM rider_trips t JOIN business_days b ON b.id=t.business_day_id WHERE $dayScope', dayArgs);
    await read('attempts', 'rider_trip_orders', 'SELECT x.id,x.order_id,x.trip_id,x.status,x.assigned_at,x.delivered_at,x.returned_at,x.notes,t.dispatched_at,t.returned_at AS trip_returned_at,t.rider_staff_id,t.shift_id AS trip_shift_id,o.delivery_area_id,o.delivery_area_name_snapshot,o.created_at AS order_created_at,o.payment_status AS order_payment_status,da.target_eta_minutes FROM rider_trip_orders x JOIN rider_trips t ON t.id=x.trip_id $joinedOrder LEFT JOIN delivery_areas da ON da.id=o.delivery_area_id ORDER BY x.id', orderArgs);
    await read('ingredients', 'raw_ingredients', 'SELECT id,name,storage_unit,current_stock,low_stock_threshold,cost_per_recipe_unit FROM raw_ingredients');
    await read('inventory', 'inventory_movements', 'SELECT m.* FROM inventory_movements m JOIN business_days b ON b.id=m.business_day_id WHERE $dayScope', dayArgs);
    final cutoff = e.get('days').map((d) => _karachi(d['closed_at']) ?? _karachi(e.now.toIso8601String())!).fold<DateTime?>(null, (latest, time) => latest == null || time.isAfter(latest) ? time : latest);
    if (cutoff != null) {
      await read('balances', 'inventory_movements', 'SELECT id,ingredient_id,balance_after,recorded_at FROM (SELECT m.*,ROW_NUMBER() OVER(PARTITION BY ingredient_id ORDER BY ${_localSql('m.recorded_at')} DESC,id DESC) AS evidence_rank FROM inventory_movements m WHERE ${_localSql('m.recorded_at')}<=?) WHERE evidence_rank=1', [_sqlTime(cutoff)]);
    }
    final interval = _intervalScope(query, 'x.created_at');
    final intervalArgs = [...dayArgs, _sqlTime(_karachi(e.now.toIso8601String())!.add(const Duration(seconds: 1)))];
    final mandiCols = tables.contains('mandi_procurements')
        ? (await txn.rawQuery("PRAGMA table_info(mandi_procurements)")).map((c) => c['name'] as String).toSet()
        : <String>{};
    final mandiVendorId = mandiCols.contains('vendor_id') ? 'x.vendor_id' : 'NULL AS vendor_id';
    final mandiTxnId = mandiCols.contains('vendor_transaction_id') ? 'x.vendor_transaction_id' : 'NULL AS vendor_transaction_id';
    await read('purchases', 'mandi_procurements', 'SELECT x.id,x.raw_ingredient_id,x.traditional_unit,x.quantity,x.converted_quantity,x.total_cost,x.cost_per_recipe_unit,x.created_at,$mandiVendorId,$mandiTxnId FROM mandi_procurements x WHERE $interval', intervalArgs);
    await read('physical_counts', 'stock_count_lines', 'SELECT x.*,c.status,c.reason,c.created_by,c.approved_by,c.posted_by,c.posted_at AS created_at FROM stock_count_lines x JOIN stock_counts c ON c.id=x.count_id WHERE ${_intervalScope(query, 'c.posted_at')} AND c.status=\'POSTED\'', intervalArgs);
    e.rows['physical_counts'] = e.get('physical_counts').map((row) => <String, Object?>{...row, 'recorded_estimated_cost_paisa': row['estimated_cost_paisa'], 'estimated_cost_paisa': StockCountValuation.paisa(row)}).toList();
    await read('waste', 'kitchen_wastage', 'SELECT x.id,x.staff_id,x.raw_ingredient_id,x.quantity,x.cost_loss,x.reason,x.created_at FROM kitchen_wastage x WHERE $interval', intervalArgs);
    final effectiveCutoff = query.live ? _karachi(e.now.toIso8601String())! : _karachi(analyticsWallClock(query.endDateExclusive).toIso8601String())!;
    final effectiveCutoffStr = _sqlTime(effectiveCutoff);
    await read('all_mandi_purchases', 'mandi_procurements', 'SELECT id,raw_ingredient_id,traditional_unit,quantity,converted_quantity,total_cost,cost_per_recipe_unit,created_at,${mandiCols.contains('vendor_id') ? 'vendor_id' : 'NULL AS vendor_id'},${mandiCols.contains('vendor_transaction_id') ? 'vendor_transaction_id' : 'NULL AS vendor_transaction_id'} FROM mandi_procurements WHERE created_at <= ? ORDER BY created_at,id', [effectiveCutoffStr]);
    await read('all_waste', 'kitchen_wastage', 'SELECT id,staff_id,raw_ingredient_id,quantity,cost_loss,reason,created_at FROM kitchen_wastage WHERE created_at <= ? ORDER BY created_at,id', [effectiveCutoffStr]);
    await read('all_inventory_movements', 'inventory_movements', 'SELECT id,ingredient_id,business_day_id,quantity_delta,balance_after,recorded_at FROM inventory_movements WHERE recorded_at <= ? ORDER BY recorded_at,id', [effectiveCutoffStr]);
    if (tables.contains('order_cost_events')) {
      await read('all_cost_events', 'order_cost_events', 'SELECT id,order_id,ingredient_id,revision,kind,quantity,unit_cost_rupees,cost_paisa,recorded_at,classification FROM order_cost_events WHERE recorded_at <= ? ORDER BY recorded_at,id', [effectiveCutoffStr]);
    }
    if (tables.contains('stock_count_lines')) {
      await read('all_physical_counts', 'stock_count_lines', "SELECT x.*,c.status,c.reason,c.posted_at AS created_at FROM stock_count_lines x JOIN stock_counts c ON c.id=x.count_id WHERE c.status='POSTED' AND c.posted_at <= ? ORDER BY c.posted_at,x.count_id", [effectiveCutoffStr]);
    }
    final vendorCols = tables.contains('vendor_transactions')
        ? (await txn.rawQuery("PRAGMA table_info(vendor_transactions)")).map((c) => c['name'] as String).toSet()
        : <String>{};
    final vendorProcId = vendorCols.contains('procurement_id') ? 'x.procurement_id' : 'NULL AS procurement_id';
    final vendorUnit = vendorCols.contains('unit_snapshot') ? 'x.unit_snapshot' : 'NULL AS unit_snapshot';
    final vendorIngName = vendorCols.contains('ingredient_name_snapshot') ? 'x.ingredient_name_snapshot' : 'NULL AS ingredient_name_snapshot';
    await read('vendor_events', 'vendor_transactions', 'SELECT x.id,x.vendor_id,x.shift_id,x.staff_id,x.type,x.amount,COALESCE(x.amount_paisa,CAST(ROUND(x.amount*100) AS INTEGER)) amount_paisa,x.due_date,x.raw_ingredient_id,x.quantity,x.created_at,$vendorProcId,$vendorUnit,$vendorIngName,x.reference_slip,x.notes FROM vendor_transactions x WHERE $interval', intervalArgs);
    await read('all_vendor_transactions', 'vendor_transactions', 'SELECT id,vendor_id,shift_id,staff_id,type,amount,COALESCE(amount_paisa,CAST(ROUND(amount*100) AS INTEGER)) amount_paisa,due_date,raw_ingredient_id,quantity,created_at,${vendorCols.contains('procurement_id') ? 'procurement_id' : 'NULL AS procurement_id'},${vendorCols.contains('unit_snapshot') ? 'unit_snapshot' : 'NULL AS unit_snapshot'},${vendorCols.contains('ingredient_name_snapshot') ? 'ingredient_name_snapshot' : 'NULL AS ingredient_name_snapshot'} FROM vendor_transactions WHERE created_at <= ? ORDER BY created_at,id', [effectiveCutoffStr]);
    if (tables.contains('procurement_vendor_links')) {
      await read('procurement_links', 'procurement_vendor_links', 'SELECT * FROM procurement_vendor_links');
    }
    if (tables.contains('supplier_receipt_evidence')) {
      await read('all_receipt_evidence', 'supplier_receipt_evidence', 'SELECT * FROM supplier_receipt_evidence WHERE recorded_at <= ? ORDER BY recorded_at, id', [effectiveCutoffStr]);
      await read('interval_receipt_evidence', 'supplier_receipt_evidence', 'SELECT x.* FROM supplier_receipt_evidence x WHERE ${_intervalScope(query, 'x.recorded_at')} ORDER BY x.recorded_at, x.id', intervalArgs);
    } else {
      e.absent.add('supplier_receipt_evidence');
    }
    await read('expense_entries', 'expense_entries', 'SELECT x.* FROM expense_entries x JOIN business_days b ON b.id=x.business_day_id WHERE $dayScope', dayArgs);
    await read('payroll_entries', 'payroll_entries', 'SELECT x.* FROM payroll_entries x WHERE $interval', intervalArgs);
    // Earned months survive late posting and later settlement. Never constrain
    // this evidence to the posting window or substitute current salary rates.
    await read('all_payroll_entries', 'payroll_entries', 'SELECT * FROM payroll_entries ORDER BY id');
    await read('payroll_balances', 'payroll_entries', 'SELECT employee_id AS id,SUM(payable_delta_paisa) payable_paisa,SUM(advance_delta_paisa) advance_paisa FROM payroll_entries GROUP BY employee_id');
    if (tables.contains('supplier_payment_allocations')) {
      await read('invoice_balances', 'vendor_transactions', "SELECT t.id,t.vendor_id,t.due_date,COALESCE(t.amount_paisa,CAST(ROUND(t.amount*100) AS INTEGER))-COALESCE(SUM(a.amount_paisa),0) due_paisa FROM vendor_transactions t LEFT JOIN supplier_payment_allocations a ON a.invoice_id=t.id WHERE t.type='PURCHASE_CREDIT' GROUP BY t.id");
      await read('all_supplier_allocations', 'supplier_payment_allocations', 'SELECT a.id,a.payment_id,a.invoice_id,a.amount_paisa,COALESCE(a.created_at,t.created_at) AS created_at,t.vendor_id FROM supplier_payment_allocations a JOIN vendor_transactions t ON t.id=a.payment_id WHERE COALESCE(a.created_at,t.created_at) <= ? ORDER BY a.id', [effectiveCutoffStr]);
    } else {
      e.absent.add('supplier_payment_allocations');
    }
    if (tables.contains('supplier_opening_adjustments')) {
      await read('supplier_opening_adjustments', 'supplier_opening_adjustments', 'SELECT * FROM supplier_opening_adjustments WHERE recorded_at <= ? ORDER BY recorded_at,id', [effectiveCutoffStr]);
    } else {
      e.absent.add('supplier_opening_adjustments');
    }
    await read('identity_snapshots', 'reporting_identity_snapshots', 'SELECT * FROM reporting_identity_snapshots');
    await read('expense_identities', 'expense_entries', 'SELECT id,category_id FROM expense_entries');
    await read('supplier_identities', 'vendor_transactions', 'SELECT id,vendor_id FROM vendor_transactions');
    await read('expense_categories', 'expense_categories', 'SELECT id,name FROM expense_categories');
    await read('vendors', 'vendor_khata', 'SELECT id,name,opening_balance,current_balance,created_at,archived_at FROM vendor_khata ORDER BY name');
    await read('staff', 'staff', 'SELECT s.id,s.name,s.department_id,s.job_role_id,s.role,s.is_active,s.login_enabled,d.name AS department,j.name AS job_role FROM staff s LEFT JOIN departments d ON d.id=s.department_id LEFT JOIN job_roles j ON j.id=s.job_role_id');
    await read('catalog', 'menu_items', 'SELECT id,name,category_id,is_active FROM menu_items');
    await read('deals', 'deals', 'SELECT id,name,is_active FROM deals');
    await read('reports', 'report_runs', 'SELECT r.id,r.business_day_id,r.content_hash,r.created_by,r.created_at,r.status FROM report_runs r JOIN business_days b ON b.id=r.business_day_id WHERE $dayScope', dayArgs);
    await read('outbox', 'report_outbox', 'SELECT r.id,r.business_day_id,r.channel,r.status,r.retry_count,r.created_at FROM report_outbox r JOIN business_days b ON b.id=r.business_day_id WHERE $dayScope', dayArgs);
    await read('delivery_audit', 'report_delivery_audit', 'SELECT x.id,x.staff_id,x.action,x.created_at FROM report_delivery_audit x WHERE $interval', intervalArgs);
    await read('configuration_audit', 'configuration_audit', 'SELECT x.id,x.actor_id,x.kind,x.before_json,x.after_json,x.created_at,s.name AS actor_name FROM configuration_audit x LEFT JOIN staff s ON s.id=x.actor_id WHERE $interval', intervalArgs);
    await read('operations_audit', 'operations_audit', 'SELECT x.id,x.manager_id,x.entity,x.entity_id,x.action,x.detail,x.created_at,s.name AS manager_name FROM operations_audit x LEFT JOIN staff s ON s.id=x.manager_id WHERE $interval', intervalArgs);
    if (tables.contains('backup_attempts')) {
      await read('backup_attempts', 'backup_attempts', 'SELECT x.*, s.name AS manager_name FROM backup_attempts x LEFT JOIN staff s ON s.id=x.manager_id WHERE $interval ORDER BY x.created_at DESC, x.id DESC', intervalArgs);
      await read('all_backup_attempts', 'backup_attempts', 'SELECT x.*, s.name AS manager_name FROM backup_attempts x LEFT JOIN staff s ON s.id=x.manager_id WHERE x.created_at <= ? ORDER BY x.created_at DESC, x.id DESC', [effectiveCutoffStr]);
    } else {
      e.absent.add('backup_attempts');
    }
    await read('token_audit', 'checkout_token_audit', 'SELECT x.id,x.order_id,x.token_number,x.action,x.payment_status,x.revision,x.recorded_at FROM checkout_token_audit x $joinedOrder', orderArgs);
    await read('rounding', 'rounding_variance_ledger', 'SELECT x.id,x.order_id,x.shift_id,x.cash_rounding_paisa,x.created_at FROM rounding_variance_ledger x $joinedOrder', orderArgs);
    await read('stock_alerts', 'checkout_stock_alerts', 'SELECT x.order_id,x.ingredient_id,x.stock_at_checkout,x.created_at FROM checkout_stock_alerts x $joinedOrder', orderArgs);
    await read('all_due', 'orders', "SELECT o.id,$outstandingCollectionPaisaSql AS collection_due_paisa FROM orders o WHERE o.payment_status='COLLECTION_DUE'");
    await read('all_trips', 'rider_trips', 'SELECT id,status,cash_expected_paisa,dispatched_at,returned_at,shift_id,business_day_id FROM rider_trips');
    await read('all_shifts', 'shifts', 'SELECT id,business_day_id,status,opened_at,closed_at FROM shifts');
    if (!query.live && query.comparisonMode != AnalyticsComparisonMode.none) {
      final prior = query.priorQuery;
      if (prior != null) {
        await read('previous_orders', 'orders', 'SELECT o.id,o.grand_total,o.payment_status FROM orders o JOIN business_days b ON b.id=o.business_day_id WHERE ${_orderCohortScope(prior)}', _orderCohortArgs(prior));
        final priorIntervalArgs = [..._dayArgs(prior), _sqlTime(_karachi(e.now.toIso8601String())!)];
        await read('previous_purchases', 'mandi_procurements', 'SELECT x.id,x.total_cost FROM mandi_procurements x WHERE ${_intervalScope(prior, 'x.created_at')}', priorIntervalArgs);
        await read('previous_waste', 'kitchen_wastage', 'SELECT x.id,x.cost_loss FROM kitchen_wastage x WHERE ${_intervalScope(prior, 'x.created_at')}', priorIntervalArgs);
      }
    }
    final optionSources = <AnalyticsDimension, String>{
      AnalyticsDimension.menuItem: 'catalog', AnalyticsDimension.menuCategory: 'menu_categories',
      AnalyticsDimension.deal: 'deals', AnalyticsDimension.discount: 'discounts',
      AnalyticsDimension.deliveryArea: 'delivery_areas', AnalyticsDimension.rider: 'staff',
      AnalyticsDimension.supplier: 'vendors', AnalyticsDimension.expenseCategory: 'expense_categories',
      AnalyticsDimension.department: 'departments', AnalyticsDimension.ingredient: 'ingredients',
    };
    for (final pair in [('menu_categories','categories'), ('discounts','discount_presets'), ('delivery_areas','delivery_areas'), ('departments','departments')]) {
      await read(pair.$1, pair.$2, 'SELECT id,name FROM ${pair.$2}');
    }
    e.filterOptions = [for (final source in optionSources.entries)
      for (final row in e.get(source.value)) AnalyticsFilterOption(dimension: source.key,
        id: '${row['id']}', label: _ReportBuilder._safeText(row['name'])),
      const AnalyticsFilterOption(dimension: AnalyticsDimension.customerSegment, id: 'known', label: 'Known phone identity'),
      const AnalyticsFilterOption(dimension: AnalyticsDimension.customerSegment, id: 'guest', label: 'Guest / unknown identity'),
      const AnalyticsFilterOption(dimension: AnalyticsDimension.acquisition, id: 'mandi', label: 'Mandi (supplier unknown)'),
      const AnalyticsFilterOption(dimension: AnalyticsDimension.acquisition, id: 'supplier', label: 'Supplier credit acquisitions'),
    ];
    return e;
  }

  // Calendar selection is independent of the assigned Business Day opening date.
  // Other ledgers retain their explicitly disclosed operational scope.
  static String _orderCohortScope(AnalyticsQuery q) => '${q.timeBasis == AnalyticsTimeBasis.businessDay ? _dayScope(q) : '(${_localSql('o.created_at')}>=? AND ${_localSql('o.created_at')}<?)'} AND ${_orderScope(q)}';
  static List<Object?> _orderCohortArgs(AnalyticsQuery q) => [
    if (q.timeBasis == AnalyticsTimeBasis.businessDay) ..._dayArgs(q)
    else ...[_sqlTime(q.startDate), _sqlTime(q.endDateExclusive)],
    ..._orderArgs(q),
  ];

  static String _dayScope(AnalyticsQuery q) => q.live ? "b.status='OPEN'" : '(${_localSql('b.opened_at', dateOnly: true)}>=? AND ${_localSql('b.opened_at', dateOnly: true)}<?)';
  static List<Object?> _dayArgs(AnalyticsQuery q) => q.live ? [] : [_sqlDate(q.startDate), _sqlDate(q.endDateExclusive)];
  static String _orderScope(AnalyticsQuery q) => [..._domainOrderSql(q), if (q.cashierId != null) 'o.cashier_id=?', if (q.shiftId != null) 'o.shift_id=?', if (q.diningType != null) 'o.dining_type=?', if (q.paymentMethod != null) 'o.id IN(SELECT fp.order_id FROM order_payments fp WHERE fp.payment_method=?)', '1=1'].join(' AND ');
  static List<Object?> _orderArgs(AnalyticsQuery q) => [..._domainOrderArgs(q), if (q.cashierId != null) q.cashierId, if (q.shiftId != null) q.shiftId, if (q.diningType != null) q.diningType, if (q.paymentMethod != null) q.paymentMethod];
  static String _intervalScope(AnalyticsQuery q, String timestamp) => 'EXISTS(SELECT 1 FROM business_days b WHERE ${_dayScope(q)} AND ${_localSql(timestamp)}>=${_localSql('b.opened_at')} AND ${_localSql(timestamp)}<COALESCE(${_localSql('b.closed_at')},?))';
}

class _Evidence {
  _Evidence(this.query, this.actor, this.now);
  final AnalyticsQuery query;
  final int actor;
  final DateTime now;
  final Map<String, List<_Record>> rows = {};
  final Set<String> absent = {};
  int? sourceSchemaVersion;
  List<AnalyticsFilterOption> filterOptions = [];
  List<_Record> get(String name) => rows[name] ?? const [];
}

int _money(_Record row, String key) => (row['${key}_paisa'] as num?)?.toInt() ?? PaisaEngine.rupeesToPaisa((row[key] as num?) ?? 0);
int _sum(Iterable<_Record> rows, String key) => rows.fold(0, (sum, row) => sum + _money(row, key));
int _integers(Iterable<_Record> rows, String key) => rows.fold(0, (sum, row) => sum + ((row[key] as num?)?.toInt() ?? 0));
bool _valid(_Record o) => !['VOIDED', 'CANCELLED', 'REFUNDED'].contains(o['payment_status']);
bool _collected(_Record o) => ['SETTLED', 'REFUND_PENDING', 'CANCELLED', 'REFUNDED'].contains(o['payment_status']);
DateTime _date(DateTime t) => DateTime.utc(t.year, t.month, t.day);
String _sqlDate(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
String _sqlTime(DateTime t) => '${_sqlDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
String _localSql(String column, {bool dateOnly = false}) {
  final function = dateOnly ? 'date' : 'datetime';
  return "CASE WHEN $column LIKE '%Z' OR substr($column,-6,1) IN ('+','-') THEN $function($column,'+5 hours') ELSE $function($column) END";
}
DateTime? _karachi(Object? raw) => analyticsKarachiTime(raw);
