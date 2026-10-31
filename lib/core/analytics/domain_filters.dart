part of 'analytics_service.dart';

List<String> _domainOrderSql(AnalyticsQuery q) {
  final f = q.domainFilters;
  final lines = <String>[
    if (f.containsKey(AnalyticsDimension.menuItem)) 'di.menu_item_id=?',
    if (f.containsKey(AnalyticsDimension.menuCategory)) 'di.menu_item_id IN(SELECT id FROM menu_items WHERE category_id=?)',
    if (f.containsKey(AnalyticsDimension.deal)) 'di.deal_id=?',
  ];
  // Match the same sold line when multiple menu predicates are selected.
  final phone = "replace(replace(replace(replace(replace(COALESCE(o.customer_phone,''),'+',''),' ',''),'-',''),'(',''),')','')";
  final usable = "length($phone) BETWEEN 7 AND 15 AND $phone NOT GLOB '*[^0-9]*'";
  return [
    if (lines.isNotEmpty) 'EXISTS(SELECT 1 FROM order_items di WHERE di.order_id=o.id AND ${lines.join(' AND ')})',
    if (f.containsKey(AnalyticsDimension.discount)) '(o.discount_id=? OR EXISTS(SELECT 1 FROM order_discounts od WHERE od.order_id=o.id AND od.discount_id=?))',
    if (f.containsKey(AnalyticsDimension.deliveryArea)) 'o.delivery_area_id=?',
    if (f.containsKey(AnalyticsDimension.rider)) 'EXISTS(SELECT 1 FROM rider_trip_orders dr JOIN rider_trips dt ON dt.id=dr.trip_id WHERE dr.order_id=o.id AND dt.rider_staff_id=?)',
    if (f[AnalyticsDimension.customerSegment] == 'known') '($usable)',
    if (f[AnalyticsDimension.customerSegment] == 'guest') 'NOT ($usable)',
  ];
}

List<Object?> _domainOrderArgs(AnalyticsQuery q) => [
  for (final d in [AnalyticsDimension.menuItem, AnalyticsDimension.menuCategory,
    AnalyticsDimension.deal, AnalyticsDimension.discount, AnalyticsDimension.deliveryArea,
    AnalyticsDimension.rider])
    if (q.domainFilters[d] != null) ...[
      int.parse(q.domainFilters[d]!),
      if (d == AnalyticsDimension.discount) int.parse(q.domainFilters[d]!),
    ],
];

/// Each family receives its own evidence view. Filtering a financial posting
/// must never remove the linked physical effect from the whole-Shift bridge.
_Evidence _domainEvidence(_Evidence source, AnalyticsFamily family) {
  final e = _Evidence(source.query, source.actor, source.now)
    ..sourceSchemaVersion = source.sourceSchemaVersion
    ..filterOptions = source.filterOptions;
  e.rows.addAll(source.rows);
  e.absent.addAll(source.absent);
  final filters = source.query.domainFilters;
  void keep(String key, bool Function(_Record) test) => e.rows[key] = e.get(key).where(test).toList();
  final category = filters[AnalyticsDimension.expenseCategory];
  if (family == AnalyticsFamily.expenses) {
    if (category != null) keep('expense_entries', (r) => '${r['category_id']}' == category);
    keep('payment_events', (r) => _matchesFinanceDomain(e, r));
  }
  if (family == AnalyticsFamily.staff && filters[AnalyticsDimension.department] != null) {
    keep('staff', (r) => '${r['department_id']}' == filters[AnalyticsDimension.department]);
  }
  final supplier = filters[AnalyticsDimension.supplier];
  if (family == AnalyticsFamily.suppliers && supplier != null) {
    keep('vendors', (r) => '${r['id']}' == supplier);
    for (final key in ['vendor_events', 'all_vendor_transactions', 'all_supplier_allocations', 'supplier_opening_adjustments', 'invoice_balances']) {
      keep(key, (r) => '${r['vendor_id']}' == supplier);
    }
  }
  final ingredient = filters[AnalyticsDimension.ingredient];
  if ([AnalyticsFamily.inventory, AnalyticsFamily.procurement].contains(family) && ingredient != null) {
    keep('ingredients', (r) => '${r['id']}' == ingredient);
    for (final key in ['inventory', 'balances', 'all_inventory_movements', 'all_cost_events', 'physical_counts', 'all_physical_counts']) {
      keep(key, (r) => '${r['ingredient_id']}' == ingredient);
    }
    for (final key in ['purchases', 'all_mandi_purchases', 'waste', 'all_waste', 'vendor_events', 'all_vendor_transactions']) {
      keep(key, (r) => '${r['raw_ingredient_id']}' == ingredient);
    }
  }
  if (family == AnalyticsFamily.procurement) {
    e.rows['domain_unlinked_mandi'] = source.get('purchases');
    if (supplier != null) {
      keep('vendor_events', (r) => '${r['vendor_id']}' == supplier);
      // Mandi has no retained supplier link. Never infer it from today's SKU map.
      e.rows['purchases'] = [];
      e.rows['previous_purchases'] = [];
    }
    final acquisition = filters[AnalyticsDimension.acquisition];
    if (acquisition == 'supplier') { e.rows['purchases'] = []; e.rows['previous_purchases'] = []; }
    if (acquisition == 'mandi') e.rows['vendor_events'] = [];
    if (ingredient != null) e.rows['previous_purchases'] = [];
  }
  if (family == AnalyticsFamily.menu) {
    final item = filters[AnalyticsDimension.menuItem];
    final menuCategory = filters[AnalyticsDimension.menuCategory];
    final deal = filters[AnalyticsDimension.deal];
    final itemIds = e.get('catalog').where((r) => menuCategory == null || '${r['category_id']}' == menuCategory).map((r) => r['id']).toSet();
    keep('items', (r) => (item == null || '${r['menu_item_id']}' == item) &&
      (deal == null || '${r['deal_id']}' == deal) && (menuCategory == null || itemIds.contains(r['menu_item_id'])));
    keep('catalog', (r) => deal == null && (item == null || '${r['id']}' == item) && (menuCategory == null || itemIds.contains(r['id'])));
    keep('deals', (r) => item == null && menuCategory == null && (deal == null || '${r['id']}' == deal));
  }
  return e;
}

List<String> _domainScopeNotes(_Evidence e, AnalyticsFamily family) => [
  'Domain scope: Menu Item/category/Deal select matching Order cohorts (full Order values); Menu reports select matching sold lines. Delivery Area, rider (any retained attempt) and customer identity segment select Orders. Multiple dimensions intersect. No Deal component membership is inferred from current recipes.',
  'Menu category uses the current Menu Item classification, not a historical category snapshot. Deleted or unlinked catalog IDs cannot match that category; their old category is unavailable. Stable Menu Item/Deal/discount/Delivery Area IDs use retained source relationships. Current picker names are context; historical source names remain in rows where retained.',
  'Customer segments: known = usable normalized phone (7–15 digits); guest = no usable phone. These are identity coverage segments, not lifetime loyalty. First-time/returning classifications remain limited to available installation history and are not offered as lifetime filters.',
  if (family == AnalyticsFamily.expenses) 'Expense category filters expense ledger and its linked finance events by stable source IDs, independently of posting date. Supplier filters linked supplier finance events; unrelated expense postings remain outside supplier scope. Whole-drawer outflows and other money-flow domains are outside scope of category selection; legacy rows without category IDs cannot match.',
  if (family == AnalyticsFamily.staff) 'Department filters the current staff directory only. Payroll, current liabilities and historical department allocation are outside scope: no effective historical department evidence exists. Changing department does not rewrite earned payroll.',
  if (family == AnalyticsFamily.inventory) 'Raw Ingredient selects the same IDs for stock bridges, rows and totals. Stock category is unavailable: no category evidence is stored. Supplier/acquisition, order and expense dimensions are outside scope of inventory balances.',
  if (family == AnalyticsFamily.procurement) 'Raw Ingredient, supplier and acquisition evidence select retained acquisition identities. Unlinked Mandi evidence before supplier/acquisition narrowing: ${e.get('domain_unlinked_mandi').length} rows, ${_sum(e.get('domain_unlinked_mandi'), 'total_cost')} paisa. Supplier selection excludes unlinked Mandi rows (supplier unknown). Mandi spend and supplier credit acquisitions are separate evidence views; never add them without retained deduplication links. Stock categories and supplier punctuality are unavailable.',
  if (family == AnalyticsFamily.suppliers) 'Supplier selects Vendor Khata history and current position for that stable supplier ID. Ingredient/acquisition filters are outside scope of payable balances: a supplier payment cannot be allocated to ingredients without evidence.',
  if (family == AnalyticsFamily.cash || family == AnalyticsFamily.delivery) 'Whole-Shift drawer reconciliation, whole trips and all-outstanding current balances are outside scope of Order/domain filters; their existing owning/receiving scope remains explicit.',
  if (family == AnalyticsFamily.profitability) 'Non-order domain filters are outside scope of profitability. No ingredient/supplier/category/department overhead allocation is inferred.',
];

/// Full-history source identity maps preserve independently selected actual-time
/// events, including a posting outside the selected Business Day opening dates.
bool _matchesFinanceDomain(_Evidence e, _Record event) {
  final category = e.query.domainFilters[AnalyticsDimension.expenseCategory];
  if (category != null && (event['source_table'] != 'expense_entries' ||
      !e.get('expense_identities').any((r) => r['id'] == event['source_id'] && '${r['category_id']}' == category))) return false;
  final supplier = e.query.domainFilters[AnalyticsDimension.supplier];
  if (supplier != null && (event['source_table'] != 'vendor_transactions' ||
      !e.get('supplier_identities').any((r) => r['id'] == event['source_id'] && '${r['vendor_id']}' == supplier))) return false;
  return true;
}
