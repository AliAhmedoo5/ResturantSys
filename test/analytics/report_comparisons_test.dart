import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('AnalyticsComparisonMode query windows', () {
    test('precedingPeriod computes exact prior window for 1 day', () {
      final query = AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.precedingPeriod,
      );
      expect(query.priorStartDate, DateTime.utc(2026, 10, 24));
      expect(query.priorEndDateExclusive, DateTime.utc(2026, 10, 25));
      expect(query.priorQuery, isNotNull);
      expect(query.priorQuery!.startDate, DateTime.utc(2026, 10, 24));
      expect(query.priorQuery!.endDateExclusive, DateTime.utc(2026, 10, 25));
      expect(query.priorQuery!.live, isFalse);
    });

    test('precedingPeriod computes exact prior window for 7 days', () {
      final query = AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 19),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.precedingPeriod,
      );
      expect(query.priorStartDate, DateTime.utc(2026, 10, 12));
      expect(query.priorEndDateExclusive, DateTime.utc(2026, 10, 19));
    });

    test('comparableWeekday computes 7-day shifted prior window (e.g. Sunday to Sunday)', () {
      // 2026-10-25 is a Sunday
      final query = AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.comparableWeekday,
      );
      // Previous Sunday is 2026-10-18
      expect(query.priorStartDate, DateTime.utc(2026, 10, 18));
      expect(query.priorEndDateExclusive, DateTime.utc(2026, 10, 19));
      expect(query.priorQuery!.startDate, DateTime.utc(2026, 10, 18));
      expect(query.priorQuery!.endDateExclusive, DateTime.utc(2026, 10, 19));
    });

    test('none comparison mode has null prior windows', () {
      final query = AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.none,
      );
      expect(query.priorStartDate, isNull);
      expect(query.priorEndDateExclusive, isNull);
      expect(query.priorQuery, isNull);
    });

    test('priorQuery preserves domain filters and cashier/shift filters', () {
      final query = AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.comparableWeekday,
        cashierId: 5,
        shiftId: 12,
        diningType: 'DINE_IN',
        paymentMethod: 'CASH',
        domainFilters: {AnalyticsDimension.menuItem: '42'},
      );
      final prior = query.priorQuery!;
      expect(prior.cashierId, 5);
      expect(prior.shiftId, 12);
      expect(prior.diningType, 'DINE_IN');
      expect(prior.paymentMethod, 'CASH');
      expect(prior.domainFilters[AnalyticsDimension.menuItem], '42');
      expect(prior.live, isFalse);
    });
  });

  group('AnalyticsService comparisons with SQLite', () {
    late PosDatabase store;
    late Database db;
    late AuthService auth;
    late Map<String, Object?> manager;
    late Map<String, Object?> cashier;

    setUp(() async {
      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await store.initialize();
      final staff = await db.query('staff');
      manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
      cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
      auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    });

    tearDown(() => store.close());

    Future<int> seedDay({
      required String openDate,
      required String closeDate,
      required String status,
      required int orderCount,
      required double orderPrice,
    }) async {
      final dayId = await db.insert('business_days', {
        'opened_at': '$openDate 18:00:00',
        'closed_at': '$closeDate 02:00:00',
        'status': 'OPEN',
        'opened_by_staff_id': manager['id'],
      });
      final shiftId = await db.insert('shifts', {
        'business_day_id': dayId,
        'staff_id': cashier['id'],
        'opened_at': '$openDate 18:00:00',
        'closed_at': '$closeDate 02:00:00',
        'opening_float': 0,
        'status': status,
      });
      for (var i = 1; i <= orderCount; i++) {
        final orderId = await db.insert('orders', {
          'business_day_id': dayId,
          'shift_id': shiftId,
          'cashier_id': cashier['id'],
          'token_number': i,
          'dining_type': 'TAKEAWAY',
          'subtotal': orderPrice,
          'grand_total': orderPrice,
          'payment_status': 'SETTLED',
          'created_at': '$openDate 20:00:00',
        });
        await db.insert('order_payments', {
          'order_id': orderId,
          'payment_method': 'CASH',
          'amount_tendered': orderPrice,
          'amount_tendered_paisa': (orderPrice * 100).toInt(),
          'change_returned': 0,
          'change_returned_paisa': 0,
        });
      }
      if (status == 'CLOSED') {
        await db.update('business_days', {'status': 'CLOSED'}, where: 'id = ?', whereArgs: [dayId]);
      }
      return dayId;
    }

    test('precedingPeriod vs comparableWeekday report distinct comparators for Sunday', () async {
      // Day 1: Sunday 2026-10-18 (2 orders @ 150 each = 300 PKR / 30000 paisa)
      await seedDay(
        openDate: '2026-10-18',
        closeDate: '2026-10-19',
        status: 'CLOSED',
        orderCount: 2,
        orderPrice: 150,
      );
      // Day 2: Saturday 2026-10-24 (4 orders @ 100 each = 400 PKR / 40000 paisa)
      await seedDay(
        openDate: '2026-10-24',
        closeDate: '2026-10-25',
        status: 'CLOSED',
        orderCount: 4,
        orderPrice: 100,
      );
      // Day 3: Sunday 2026-10-25 (5 orders @ 100 each = 500 PKR / 50000 paisa)
      await seedDay(
        openDate: '2026-10-25',
        closeDate: '2026-10-26',
        status: 'CLOSED',
        orderCount: 5,
        orderPrice: 100,
      );

      final service = AnalyticsService(database: db, authService: auth);

      // 1. Preceding Period: compares Sunday (Oct 25) with Saturday (Oct 24)
      final precedingSnapshot = await service.load(AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.precedingPeriod,
      ));
      final salesPreceding = precedingSnapshot.section(AnalyticsFamily.sales);
      final valuePreceding = salesPreceding.metrics.firstWhere((m) => m.id == 'recorded_value');
      final ordersPreceding = salesPreceding.metrics.firstWhere((m) => m.id == 'orders');

      // Current: 50000 paisa, Prior (Saturday): 40000 paisa
      expect(valuePreceding.value, 50000);
      expect(valuePreceding.priorValue, 40000);
      expect(valuePreceding.changeAbsolute, 10000);
      expect(valuePreceding.changePercent, 25.0); // (10000 / 40000) * 100

      // Orders: Current: 5, Prior: 4
      expect(ordersPreceding.value, 5);
      expect(ordersPreceding.priorValue, 4);
      expect(ordersPreceding.changeAbsolute, 1);
      expect(ordersPreceding.changePercent, 25.0);

      // 2. Comparable Weekday: compares Sunday (Oct 25) with previous Sunday (Oct 18)
      final weekdaySnapshot = await service.load(AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.comparableWeekday,
      ));
      final salesWeekday = weekdaySnapshot.section(AnalyticsFamily.sales);
      final valueWeekday = salesWeekday.metrics.firstWhere((m) => m.id == 'recorded_value');
      final ordersWeekday = salesWeekday.metrics.firstWhere((m) => m.id == 'orders');

      // Current: 50000 paisa, Prior (previous Sunday): 30000 paisa
      expect(valueWeekday.value, 50000);
      expect(valueWeekday.priorValue, 30000);
      expect(valueWeekday.changeAbsolute, 20000);
      expect(valueWeekday.changePercent, closeTo(66.67, 0.01)); // (20000 / 30000) * 100

      // Orders: Current: 5, Prior: 2
      expect(ordersWeekday.value, 5);
      expect(ordersWeekday.priorValue, 2);
      expect(ordersWeekday.changeAbsolute, 3);
      expect(ordersWeekday.changePercent, 150.0); // (3 / 2) * 100

      // 3. None: no comparison values computed
      final noneSnapshot = await service.load(AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.none,
      ));
      final valueNone = noneSnapshot.section(AnalyticsFamily.sales).metrics.firstWhere((m) => m.id == 'recorded_value');
      expect(valueNone.value, 50000);
      expect(valueNone.priorValue, isNull);
      expect(valueNone.changeAbsolute, isNull);
      expect(valueNone.changePercent, isNull);
    });

    test('zero baseline leaves changePercent unavailable (null) and not infinity or zero', () async {
      // Day on Oct 25 has activity, but Oct 24 has 0 activity
      await seedDay(
        openDate: '2026-10-25',
        closeDate: '2026-10-26',
        status: 'CLOSED',
        orderCount: 3,
        orderPrice: 100,
      );

      final service = AnalyticsService(database: db, authService: auth);
      final snapshot = await service.load(AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.precedingPeriod,
      ));
      final valueMetric = snapshot.section(AnalyticsFamily.sales).metrics.firstWhere((m) => m.id == 'recorded_value');
      expect(valueMetric.value, 30000);
      expect(valueMetric.priorValue, 0);
      expect(valueMetric.changeAbsolute, 30000);
      expect(valueMetric.changePercent, isNull, reason: 'Zero baseline cannot divide by zero');
    });

    test('open business day coverage withholds comparison calculations', () async {
      // Day is OPEN (live/partial)
      await seedDay(
        openDate: '2026-10-25',
        closeDate: '2026-10-26',
        status: 'OPEN',
        orderCount: 3,
        orderPrice: 100,
      );

      final service = AnalyticsService(database: db, authService: auth);
      final snapshot = await service.load(AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.precedingPeriod,
      ));
      final valueMetric = snapshot.section(AnalyticsFamily.sales).metrics.firstWhere((m) => m.id == 'recorded_value');
      expect(valueMetric.value, 30000);
      expect(valueMetric.priorValue, isNull);
      expect(valueMetric.changeAbsolute, isNull);
      expect(valueMetric.changePercent, isNull);
      expect(snapshot.notes.any((n) => n.contains('Percentage comparisons withheld')), isTrue);
    });

    test('snapshot balances are excluded from historical comparisons with isBalance = true', () async {
      await seedDay(
        openDate: '2026-10-25',
        closeDate: '2026-10-26',
        status: 'CLOSED',
        orderCount: 2,
        orderPrice: 100,
      );
      final service = AnalyticsService(database: db, authService: auth);
      final snapshot = await service.load(AnalyticsQuery(
        startDate: DateTime.utc(2026, 10, 25),
        endDateExclusive: DateTime.utc(2026, 10, 26),
        comparisonMode: AnalyticsComparisonMode.comparableWeekday,
      ));

      // Inventory: low_stock and negative_stock are snapshot balances
      final lowStock = snapshot.section(AnalyticsFamily.inventory).metrics.firstWhere((m) => m.id == 'low_stock');
      final negStock = snapshot.section(AnalyticsFamily.inventory).metrics.firstWhere((m) => m.id == 'negative_stock');
      expect(lowStock.isBalance, isTrue);
      expect(lowStock.priorValue, isNull);
      expect(lowStock.changeAbsolute, isNull);
      expect(lowStock.changePercent, isNull);

      expect(negStock.isBalance, isTrue);
      expect(negStock.priorValue, isNull);
      expect(negStock.changeAbsolute, isNull);
      expect(negStock.changePercent, isNull);

      // Supplier Khata: closing payable and current payable are snapshot balances
      final closingPayable = snapshot.section(AnalyticsFamily.suppliers).metrics.firstWhere((m) => m.id == 'khata_closing_payable');
      final currentPayable = snapshot.section(AnalyticsFamily.suppliers).metrics.firstWhere((m) => m.id == 'current_payable');
      expect(closingPayable.isBalance, isTrue);
      expect(closingPayable.changeAbsolute, isNull);
      expect(currentPayable.isBalance, isTrue);
      expect(currentPayable.changeAbsolute, isNull);

      // Cash: expected drawer and variance are balances
      final expectedDrawer = snapshot.section(AnalyticsFamily.cash).metrics.firstWhere((m) => m.id == 'expected_drawer');
      expect(expectedDrawer.isBalance, isTrue);
      expect(expectedDrawer.changeAbsolute, isNull);
    });
  });

  group('AnalyticsExportService comparator provenance', () {
    test('CSV export contains comparison_mode and prior window metadata', () {
      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime.utc(2026, 10, 25),
          endDateExclusive: DateTime.utc(2026, 10, 26),
          comparisonMode: AnalyticsComparisonMode.comparableWeekday,
        ),
        generatedAt: DateTime.utc(2026, 10, 25, 23),
        businessDayIds: [1],
        sections: [
          AnalyticsSection(
            family: AnalyticsFamily.sales,
            title: 'Sales',
            metrics: [
              const AnalyticsMetric(
                id: 'recorded_value',
                label: 'Recorded order value',
                value: 50000,
                unit: AnalyticsUnit.paisa,
                explanation: 'Sales flow',
                priorValue: 30000,
                changeAbsolute: 20000,
                changePercent: 66.67,
              ),
              const AnalyticsMetric(
                id: 'negative_stock',
                label: 'Negative stock',
                value: 0,
                unit: AnalyticsUnit.count,
                explanation: 'Snapshot balance',
                isBalance: true,
              ),
            ],
          ),
        ],
      );

      final exports = AnalyticsExportService();
      final csv = exports.csv(snapshot, AnalyticsFamily.sales);
      expect(csv, contains('comparison_mode,comparableWeekday'));
      expect(csv, contains('prior_window_start,2026-10-18'));
      expect(csv, contains('prior_window_end_exclusive,2026-10-19'));
    });
  });
}
