import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/kpi_contributors.dart';

void main() {
  group('KpiContributors', () {
    test('Reconciles Sales recorded_value and orders to daily total rows', () {
      final salesRows = [
        AnalyticsRow(
          id: 'day-1',
          sourceType: 'business_days',
          sourceId: '1',
          cells: {
            'kind': 'Daily total',
            'business_date': '2026-10-25',
            'orders': 10,
            'recorded_value_paisa': 50000,
          },
        ),
        AnalyticsRow(
          id: 'day-2',
          sourceType: 'business_days',
          sourceId: '2',
          cells: {
            'kind': 'Daily total',
            'business_date': '2026-10-26',
            'orders': 15,
            'recorded_value_paisa': 75000,
          },
        ),
        // Independent dimension breakdown should NOT be summed into the daily total
        AnalyticsRow(
          id: 'sales-dining-TAKEAWAY',
          sourceType: 'orders',
          sourceId: '1,2',
          cells: {
            'kind': 'Independent dimension',
            'dimension': 'Dining type',
            'dimension_value': 'TAKEAWAY',
            'orders': 25,
            'recorded_value_paisa': 125000,
          },
        ),
      ];

      final salesSection = AnalyticsSection(
        family: AnalyticsFamily.sales,
        title: 'Sales',
        metrics: const [
          AnalyticsMetric(
            id: 'recorded_value',
            label: 'Recorded order value',
            value: 125000,
            unit: AnalyticsUnit.paisa,
            explanation: 'Eligible orders including Collection Due.',
          ),
          AnalyticsMetric(
            id: 'orders',
            label: 'Eligible orders',
            value: 25,
            unit: AnalyticsUnit.count,
            explanation: 'Committed orders.',
          ),
          AnalyticsMetric(
            id: 'average_ticket',
            label: 'Average ticket',
            value: 5000.0,
            unit: AnalyticsUnit.paisa,
            explanation: 'Recorded value / orders',
            sampleCount: 25,
          ),
        ],
        rows: salesRows,
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 27),
        ),
        generatedAt: DateTime(2026, 10, 27, 12),
        businessDayIds: const [1, 2],
        sections: [salesSection],
      );

      // 1. recorded_value
      final valResult = KpiContributors.resolve(
        snapshot: snapshot,
        section: salesSection,
        metric: salesSection.metrics[0],
      );
      expect(valResult.isReconciled, isTrue);
      expect(valResult.contributingRows.length, 2);
      expect(valResult.formulaTotal, 125000);
      expect(valResult.formula, contains('PKR 1,250.00'));

      // 2. orders
      final ordersResult = KpiContributors.resolve(
        snapshot: snapshot,
        section: salesSection,
        metric: salesSection.metrics[1],
      );
      expect(ordersResult.isReconciled, isTrue);
      expect(ordersResult.contributingRows.length, 2);
      expect(ordersResult.formulaTotal, 25);

      // 3. average_ticket
      final ticketResult = KpiContributors.resolve(
        snapshot: snapshot,
        section: salesSection,
        metric: salesSection.metrics[2],
      );
      expect(ticketResult.isReconciled, isTrue);
      expect(ticketResult.formulaTotal, 5000.0);
      expect(ticketResult.formula, contains('PKR 1,250.00'));
      expect(ticketResult.formula, contains('25'));
    });

    test('Reconciles Cash expected_drawer and variance with signed components', () {
      final cashRows = [
        AnalyticsRow(
          id: 'shift-1',
          sourceType: 'shifts',
          sourceId: '1',
          cells: {
            'kind': 'Shift reconciliation',
            'shift_id': 1,
            'opening_paisa': 10000,
            'counted_paisa': 35000,
            'expected_paisa': 32000,
            'variance_paisa': 3000,
          },
        ),
        AnalyticsRow(
          id: 'effect-1',
          sourceType: 'order_payments',
          sourceId: '10',
          cells: {
            'kind': 'Physical cash effect',
            'component': 'customer_receipts',
            'amount_paisa': 30000,
          },
        ),
        AnalyticsRow(
          id: 'effect-2',
          sourceType: 'cash_movements',
          sourceId: '20',
          cells: {
            'kind': 'Physical cash effect',
            'component': 'expenses',
            'amount_paisa': -8000,
          },
        ),
      ];

      final cashSection = AnalyticsSection(
        family: AnalyticsFamily.cash,
        title: 'Cash and shifts',
        metrics: const [
          AnalyticsMetric(
            id: 'expected_drawer',
            label: 'Expected drawer',
            value: 32000,
            unit: AnalyticsUnit.paisa,
            explanation: 'Opening float + receipts - outflows',
          ),
          AnalyticsMetric(
            id: 'variance',
            label: 'Discrepancy',
            value: 3000,
            unit: AnalyticsUnit.paisa,
            explanation: 'Counted minus expected',
          ),
        ],
        rows: cashRows,
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 26),
        ),
        generatedAt: DateTime(2026, 10, 26, 12),
        businessDayIds: const [1],
        sections: [cashSection],
      );

      final drawerResult = KpiContributors.resolve(
        snapshot: snapshot,
        section: cashSection,
        metric: cashSection.metrics[0],
      );
      expect(drawerResult.isReconciled, isTrue);
      expect(drawerResult.formulaTotal, 32000);
      expect(drawerResult.formula, contains('Opening Float'));
      expect(drawerResult.formula, contains('Receipts'));
      expect(drawerResult.formula, contains('Outflows'));

      final varianceResult = KpiContributors.resolve(
        snapshot: snapshot,
        section: cashSection,
        metric: cashSection.metrics[1],
      );
      expect(varianceResult.isReconciled, isTrue);
      expect(varianceResult.formulaTotal, 3000);
      expect(varianceResult.formula, contains('Counted'));
      expect(varianceResult.formula, contains('Expected'));
    });

    test('Reconciles Inventory negative_stock and low_stock', () {
      final inventoryRows = [
        AnalyticsRow(
          id: 'ing-1',
          sourceType: 'raw_ingredients',
          sourceId: '1',
          cells: {
            'ingredient_id': 1,
            'name': 'Beef Patty',
            'current_stock': -5.0,
            'low_stock_threshold': 10.0,
            'storage_unit': 'kg',
          },
        ),
        AnalyticsRow(
          id: 'ing-2',
          sourceType: 'raw_ingredients',
          sourceId: '2',
          cells: {
            'ingredient_id': 2,
            'name': 'Cheese Slice',
            'current_stock': 8.0,
            'low_stock_threshold': 10.0,
            'storage_unit': 'packs',
          },
        ),
        AnalyticsRow(
          id: 'ing-3',
          sourceType: 'raw_ingredients',
          sourceId: '3',
          cells: {
            'ingredient_id': 3,
            'name': 'Burger Buns',
            'current_stock': 50.0,
            'low_stock_threshold': 20.0,
            'storage_unit': 'packs',
          },
        ),
      ];

      final inventorySection = AnalyticsSection(
        family: AnalyticsFamily.inventory,
        title: 'Inventory',
        metrics: const [
          AnalyticsMetric(
            id: 'negative_stock',
            label: 'Negative stock items',
            value: 1,
            unit: AnalyticsUnit.count,
            explanation: 'Ingredients with stock < 0',
          ),
        ],
        rows: inventoryRows,
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 26),
        ),
        generatedAt: DateTime(2026, 10, 26, 12),
        businessDayIds: const [1],
        sections: [inventorySection],
      );

      final negResult = KpiContributors.resolve(
        snapshot: snapshot,
        section: inventorySection,
        metric: inventorySection.metrics[0],
      );
      expect(negResult.isReconciled, isTrue);
      expect(negResult.contributingRows.length, 1);
      expect(negResult.contributingRows.first.cells['name'], 'Beef Patty');
      expect(negResult.formulaTotal, 1);
    });

    test('Overview KPIs delegate to their underlying report sections', () {
      final salesSection = AnalyticsSection(
        family: AnalyticsFamily.sales,
        title: 'Sales',
        metrics: const [
          AnalyticsMetric(
            id: 'recorded_value',
            label: 'Recorded order value',
            value: 80000,
            unit: AnalyticsUnit.paisa,
            explanation: 'Sales recorded value',
          ),
        ],
        rows: [
          AnalyticsRow(
            id: 'day-1',
            sourceType: 'business_days',
            sourceId: '1',
            cells: {
              'kind': 'Daily total',
              'business_date': '2026-10-25',
              'orders': 8,
              'recorded_value_paisa': 80000,
            },
          ),
        ],
      );

      const overviewMetric = AnalyticsMetric(
        id: 'recorded_value',
        label: 'Recorded order value',
        value: 80000,
        unit: AnalyticsUnit.paisa,
        explanation: 'Overview recorded value',
      );

      final overviewSection = AnalyticsSection(
        family: AnalyticsFamily.overview,
        title: 'Overview',
        metrics: [overviewMetric],
        rows: const [],
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 26),
        ),
        generatedAt: DateTime(2026, 10, 26, 12),
        businessDayIds: const [1],
        sections: [overviewSection, salesSection],
      );

      final result = KpiContributors.resolve(
        snapshot: snapshot,
        section: overviewSection,
        metric: overviewMetric,
      );
      expect(result.isReconciled, isTrue);
      expect(result.contributingRows.length, 1);
      expect(result.formulaTotal, 80000);
    });

    test('Safely handles missing or null metric values', () {
      const missingMetric = AnalyticsMetric(
        id: 'gross_profit',
        label: 'Gross profit',
        unit: AnalyticsUnit.paisa,
        quality: AnalyticsQuality.missing,
        explanation: 'Event-time costs are not recorded.',
      );

      final section = AnalyticsSection(
        family: AnalyticsFamily.profitability,
        title: 'Profitability',
        metrics: const [missingMetric],
        rows: const [],
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 26),
        ),
        generatedAt: DateTime(2026, 10, 26, 12),
        businessDayIds: const [1],
        sections: [section],
      );

      final result = KpiContributors.resolve(
        snapshot: snapshot,
        section: section,
        metric: missingMetric,
      );
      expect(result.isReconciled, isFalse);
      expect(result.contributingRows, isEmpty);
      expect(result.emptyOrMissingNote, contains('Missing'));
    });
  });
}
