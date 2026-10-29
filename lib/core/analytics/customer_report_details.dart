part of 'analytics_service.dart';

class CustomerReportOrder {
  CustomerReportOrder({required this.id, required this.token, required this.totalPaisa,
    required this.createdAt, required this.diningType, required this.paymentStatus,
    required this.recordedName, required this.address, required this.area,
    List<String> items = const []}) : items = List.unmodifiable(items);
  final int id, token, totalPaisa;
  final String createdAt, diningType, paymentStatus, recordedName, address, area;
  final List<String> items;
}

class CustomerReportProfile {
  CustomerReportProfile({required this.name, required this.phone, required this.notes,
    this.primaryPhone = '', required List<CustomerReportOrder> orders}) : orders = List.unmodifiable(orders);
  final String name, phone, primaryPhone, notes;
  final List<CustomerReportOrder> orders;
  int get recordedValuePaisa => orders.fold(0, (sum, order) => sum + order.totalPaisa);
  List<String> get addresses => orders.map((o) => o.address).where((a) => a.isNotEmpty).toSet().toList();
}

/// An explicit Manager-only read over the same cohort as customer analytics.
/// These records never enter AnalyticsSnapshot or its export serialization.
class _CustomerInformationReader {
  _CustomerInformationReader(this.service);
  final AnalyticsService service;

  Future<List<CustomerReportProfile>> load(AnalyticsQuery query) async {
    final actor = service.authService.session.currentStaff;
    if (actor == null || !actor.isActive || !actor.loginEnabled || !actor.role.isManager) {
      throw StateError('An active Manager session is required.');
    }
    final profiles = await service.database.transaction((txn) async {
      final staff = await txn.query('staff', columns: ['role', 'is_active', 'login_enabled'],
        where: 'id = ?', whereArgs: [actor.id]);
      if (staff.isEmpty || staff.single['is_active'] != 1 || staff.single['login_enabled'] != 1 ||
          !StaffRole.fromCode(staff.single['role'] as String).isManager) {
        throw StateError('Manager access is no longer enabled.');
      }
      final tables = (await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((row) => row['name']).toSet();
      final columns = (await txn.rawQuery('PRAGMA table_info(orders)')).map((row) => row['name']).toSet();
      const names = ['id', 'business_day_id', 'token_number', 'grand_total', 'grand_total_paisa',
        'created_at', 'dining_type', 'payment_status', 'customer_id', 'customer_name',
        'customer_phone', 'delivery_address_snapshot', 'delivery_area_name_snapshot'];
      final fields = names.map((name) => columns.contains(name) ? 'o.$name' : 'NULL AS $name').join(',');
      final scope = 'FROM orders o JOIN business_days b ON b.id=o.business_day_id '
        'WHERE ${AnalyticsService._orderCohortScope(query)}';
      final args = AnalyticsService._orderCohortArgs(query);
      final orders = (await txn.rawQuery('SELECT $fields $scope ORDER BY o.id DESC', args)).where(_valid).toList();
      final directory = tables.contains('customers')
        ? await txn.query('customers', columns: ['id', 'name', 'phone', 'notes', 'merged_into']) : <_Record>[];
      final byId = {for (final person in directory) person['id']: person};
      _Record? canonical(Object? id) {
        final seen = <Object?>{};
        var person = byId[id];
        while (person != null && person['merged_into'] != null) {
          if (!seen.add(person['id'])) return null;
          person = byId[person['merged_into']];
        }
        return person;
      }
      final byPhone = <String, Map<Object?, _Record>>{};
      for (final person in directory) {
        final phone = _ReportBuilder._phone(person['phone']);
        final root = canonical(person['id']);
        if (phone != null && root != null) byPhone.putIfAbsent(phone, () => {})[root['id']] = root;
      }
      final links = tables.contains('customer_order_links') ? await txn.rawQuery(
        'SELECT l.order_id,l.customer_id FROM customer_order_links l JOIN orders o ON o.id=l.order_id '
        'JOIN business_days b ON b.id=o.business_day_id '
        'WHERE ${AnalyticsService._orderCohortScope(query)}', args) : <_Record>[];
      final linkedIds = {for (final link in links) link['order_id']: link['customer_id']};
      final lines = tables.contains('order_items') ? await txn.rawQuery(
        'SELECT i.order_id,i.name,i.quantity FROM order_items i JOIN orders o ON o.id=i.order_id '
        'JOIN business_days b ON b.id=o.business_day_id '
        'WHERE ${AnalyticsService._orderCohortScope(query)} ORDER BY i.id', args) : <_Record>[];
      final items = <Object?, List<String>>{};
      for (final line in lines) {
        items.putIfAbsent(line['order_id'], () => []).add('${line['quantity']} × ${line['name']}');
      }
      final groups = <String, List<_Record>>{};
      for (final order in orders) {
        final phone = _ReportBuilder._phone(order['customer_phone']);
        if (phone != null) groups.putIfAbsent(phone, () => []).add(order);
      }
      final result = <CustomerReportProfile>[];
      for (final entry in groups.entries) {
        final roots = <Object?, _Record>{};
        for (final order in entry.value) {
          final linked = canonical(order['customer_id']) ?? canonical(linkedIds[order['id']]);
          if (linked != null) roots[linked['id']] = linked;
        }
        final matches = byPhone[entry.key];
        final person = roots.length == 1 ? roots.values.single
          : roots.isEmpty && matches?.length == 1 ? matches!.values.single : null;
        var name = '${person?['name'] ?? ''}'.trim();
        if (name.isEmpty || _ReportBuilder._phone(name) == entry.key) {
          name = entry.value.map((o) => '${o['customer_name'] ?? ''}'.trim())
            .where((name) => name.isNotEmpty && _ReportBuilder._phone(name) != entry.key).firstOrNull ?? 'Name not recorded';
        }
        result.add(CustomerReportProfile(name: name, phone: entry.key,
          primaryPhone: _ReportBuilder._phone(person?['phone']) ?? '', notes: '${person?['notes'] ?? ''}',
          orders: [for (final order in entry.value) CustomerReportOrder(
            id: order['id'] as int, token: (order['token_number'] as int?) ?? 0,
            totalPaisa: _money(order, 'grand_total'), createdAt: '${order['created_at'] ?? ''}',
            diningType: '${order['dining_type'] ?? ''}', paymentStatus: '${order['payment_status'] ?? ''}',
            recordedName: '${order['customer_name'] ?? ''}', address: '${order['delivery_address_snapshot'] ?? ''}',
            area: '${order['delivery_area_name_snapshot'] ?? ''}', items: items[order['id']] ?? [])]));
      }
      result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    });
    if (!identical(service.authService.session.currentStaff, actor)) {
      throw StateError('Session changed while loading customer information.');
    }
    return profiles;
  }
}
