import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('Ticket #92: Supplier acquisition prices, frequency and receipt punctuality', () {
    late PosDatabase posDb;
    late Database db;
    late AuthService auth;
    late Staff manager;
    late VendorKhataController vendorController;

    setUp(() async {
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await posDb.initialize();
      auth = AuthService(database: db);

      final staffRows = await db.query('staff');
      manager = Staff.fromMap(staffRows.firstWhere((r) => r['role'] != 'CASHIER'));
      auth.session.login(manager);

      vendorController = VendorKhataController(database: db);
    });

    tearDown(() async {
      await posDb.close();
    });

    test('supplier_receipt_evidence is append-only and rejects UPDATE and DELETE', () async {
      final vendor = await vendorController.createVendor(name: 'Metro Cash & Carry', phone: '03001234567');

      final evidenceId = await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendor.id,
        promisedAt: DateTime.parse('2026-10-26 10:00:00'),
        actualAt: DateTime.parse('2026-10-26 09:45:00'),
        notes: 'Initial on-time delivery commitment',
      );
      expect(evidenceId, greaterThan(0));

      // Assert UPDATE is rejected by trigger
      expect(
        () => db.rawUpdate('UPDATE supplier_receipt_evidence SET notes = ? WHERE id = ?', ['Tampered note', evidenceId]),
        throwsA(isA<DatabaseException>()),
      );

      // Assert DELETE is rejected by trigger
      expect(
        () => db.rawDelete('DELETE FROM supplier_receipt_evidence WHERE id = ?', [evidenceId]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('supports amending delivery promises append-only without silently overwriting', () async {
      final vendor = await vendorController.createVendor(name: 'Al-Madina Farms', phone: '03111234567');

      // Original promise
      final originalId = await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendor.id,
        promisedAt: DateTime.parse('2026-10-26 12:00:00'),
        notes: 'Original ETA noon',
      );

      // Amend promise append-only pointing to earlier promise
      final amendedId = await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendor.id,
        promisedAt: DateTime.parse('2026-10-26 14:00:00'),
        amendmentOf: originalId,
        notes: 'Supplier requested 2-hour delay',
      );
      expect(amendedId, greaterThan(originalId));

      // Verify earlier record remains unchanged
      final originalRow = (await db.query('supplier_receipt_evidence', where: 'id = ?', whereArgs: [originalId])).single;
      expect(originalRow['promised_at'], '2026-10-26 12:00:00');
      expect(originalRow['notes'], 'Original ETA noon');

      // Verify amendment points to original
      final amendedRow = (await db.query('supplier_receipt_evidence', where: 'id = ?', whereArgs: [amendedId])).single;
      expect(amendedRow['promised_at'], '2026-10-26 14:00:00');
      expect(amendedRow['amendment_of'], originalId);
    });

    test('normalizes acquisition prices, unifies linked purchases without double-counting, and reports punctuality', () async {
      await db.insert('business_days', {
        'opened_at': '2026-10-26 00:00:00',
        'closed_at': '2026-10-26 23:59:59',
        'status': 'CLOSED',
        'opened_by_staff_id': manager.id,
      });

      final chicken = await db.insert('raw_ingredients', {
        'name': 'Fresh Chicken',
        'storage_unit': 'g',
        'current_stock': 10000,
        'low_stock_threshold': 2000,
        'cost_per_recipe_unit': 0.8,
        'created_at': '2026-10-25 12:00:00',
      });

      final flour = await db.insert('raw_ingredients', {
        'name': 'Premium Flour',
        'storage_unit': 'kg',
        'current_stock': 50,
        'low_stock_threshold': 10,
        'cost_per_recipe_unit': 120.0,
        'created_at': '2026-10-25 12:00:00',
      });

      final vendorA = await vendorController.createVendor(name: 'Habib Poultry', phone: '03221234567');
      final vendorB = await vendorController.createVendor(name: 'Shaheen Mills', phone: '03331234567');

      // Map chicken to vendorA
      await vendorController.setSuppliedItems(managerId: manager.id, vendorId: vendorA.id, ingredientIds: {chicken});

      // 1. Mandi procurement of chicken: 5 kg = 5000 g @ Rs 400 (40,000 paisa) = 8 paisa/g
      final mandiPurchase = await db.insert('mandi_procurements', {
        'raw_ingredient_id': chicken,
        'traditional_unit': 'kg',
        'quantity': 5,
        'total_cost': 400.0,
        'converted_quantity': 5000,
        'cost_per_recipe_unit': 0.08,
        'notes': 'Habib poultry wholesale delivery',
        'created_at': '2026-10-26 08:00:00',
      });

      // 2. Vendor Khata credit delivery for the same shipment: Rs 400
      final creditDelivery = await vendorController.recordCreditDelivery(
        vendorId: vendorA.id,
        amount: 400.0,
        referenceSlip: 'INV-HP-101',
        rawIngredientId: chicken,
        quantity: 5000,
        notes: 'Credit invoice for 5kg chicken',
        staffId: manager.id,
        createdAt: DateTime.parse('2026-10-26 08:00:00'),
      );

      // Link them together!
      await vendorController.linkProcurementToCreditDelivery(
        managerId: manager.id,
        procurementId: mandiPurchase,
        vendorTransactionId: creditDelivery.id,
      );

      // 3. Unlinked Mandi procurement: 20 kg flour @ Rs 2,400 = 240,000 paisa = 12,000 paisa/kg
      await db.insert('mandi_procurements', {
        'raw_ingredient_id': flour,
        'traditional_unit': 'kg',
        'quantity': 20,
        'total_cost': 2400.0,
        'converted_quantity': 20,
        'cost_per_recipe_unit': 120.0,
        'notes': 'Unlinked Mandi wholesale purchase',
        'created_at': '2026-10-26 11:00:00',
      });

      // 4. Unlinked credit purchase with missing ingredient/quantity (disclosed honestly)
      await db.insert('vendor_transactions', {
        'vendor_id': vendorB.id,
        'type': 'PURCHASE_CREDIT',
        'amount': 1500.0,
        'amount_paisa': 150000,
        'reference_slip': 'LEGACY-GENERIC-1',
        'notes': 'Unlinked generic bulk delivery',
        'created_at': '2026-10-26 14:00:00',
      });

      // Receipt evidence:
      // a) On-time delivery for chicken: promised 08:30, arrived 08:00 (30 min early)
      await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendorA.id,
        ingredientId: chicken,
        procurementId: mandiPurchase,
        vendorTransactionId: creditDelivery.id,
        promisedAt: DateTime.parse('2026-10-26 08:30:00'),
        actualAt: DateTime.parse('2026-10-26 08:00:00'),
        notes: 'Chicken arrived 30 mins before promised deadline',
        recordedAt: DateTime.parse('2026-10-26 08:00:00'),
      );

      // b) Late delivery: promised 10:00, arrived 11:30 (90 min late)
      await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendorB.id,
        ingredientId: flour,
        promisedAt: DateTime.parse('2026-10-26 10:00:00'),
        actualAt: DateTime.parse('2026-10-26 11:30:00'),
        notes: 'Flour transport delayed by puncture',
        recordedAt: DateTime.parse('2026-10-26 11:30:00'),
      );

      // c) Unknown promise: actual arrived at 14:00, but no delivery promise was ever recorded
      await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendorB.id,
        actualAt: DateTime.parse('2026-10-26 14:00:00'),
        notes: 'Spontaneous delivery without prior commitment',
        recordedAt: DateTime.parse('2026-10-26 14:00:00'),
      );

      // d) Pending / unknown receipt: promise for 18:00, but actual receipt not yet recorded
      await vendorController.recordReceiptEvidence(
        managerId: manager.id,
        vendorId: vendorA.id,
        promisedAt: DateTime.parse('2026-10-26 18:00:00'),
        notes: 'Evening order pending arrival',
        recordedAt: DateTime.parse('2026-10-26 10:00:00'),
      );

      // Load analytics query
      final analyticsService = AnalyticsService(database: db, authService: auth);
      final query = AnalyticsQuery(startDate: DateTime(2026, 10, 26), endDateExclusive: DateTime(2026, 10, 27));
      final snapshot = await analyticsService.load(query);

      final procurementSection = snapshot.section(AnalyticsFamily.procurement);
      final suppliersSection = snapshot.section(AnalyticsFamily.suppliers);

      AnalyticsMetric procMetric(String id) => procurementSection.metrics.firstWhere((m) => m.id == id);
      AnalyticsMetric suppMetric(String id) => suppliersSection.metrics.firstWhere((m) => m.id == id);
      expect(suppMetric('credit_purchases').value, 190000);

      // 1. Normalization & Deduplication:
      // Unified spend = 40,000 (chicken) + 240,000 (flour) + 150,000 (unlinked vendor B) = 430,000 paisa
      // Mandi spend = 40,000 + 240,000 = 280,000 paisa
      expect(procMetric('purchase_spend').value, 280000);
      expect(procMetric('unified_spend').value, 430000);

      // Unified purchases = 3 (1 linked pair counted once + 1 unlinked mandi + 1 unlinked credit)
      expect(procMetric('unified_purchase_count').value, 3);
      expect(procMetric('linked_purchases_count').value, 1);
      expect(procMetric('unlinked_purchases_count').value, 2);

      // Purchase frequency: 3 purchases over 1 selected business day = 3.0 / day
      expect(procMetric('purchase_frequency').value, 3.0);

      // 2. Receipt Punctuality & Honest Disclosures:
      // Valid sample has BOTH promised & actual timestamps: 2 (chicken on-time, flour late)
      // Total commitments: 4
      // Punctual count: 1 (50% on-time)
      // Late count: 1
      // Unknown promises: 1 (NOT classified as failed!)
      // Pending/unknown receipts: 1 (NOT classified as failed!)
      expect(procMetric('supplier_performance').value, 50);
      expect(procMetric('supplier_performance').sampleCount, 2);
      expect(procMetric('supplier_performance').populationCount, 4);
      expect(procMetric('valid_punctuality_sample').value, 2);
      expect(procMetric('punctual_receipts').value, 1);
      expect(procMetric('late_receipts').value, 1);
      expect(procMetric('unknown_promises').value, 1);
      expect(procMetric('unknown_receipts').value, 1);

      // Verify safe contributor rows in procurement section
      final chickenProcRow = procurementSection.rows.firstWhere((r) => r.cells['ingredient_id'] == chicken && r.cells['is_linked'] == true);
      expect(chickenProcRow.cells['spend_paisa'], 40000);
      expect(chickenProcRow.cells['base_quantity'], 5000);
      expect(chickenProcRow.cells['base_unit'], 'g');
      expect(chickenProcRow.cells['unit_price_paisa'], 8); // 8 paisa per gram

      final flourProcRow = procurementSection.rows.firstWhere((r) => r.cells['ingredient_id'] == flour);
      expect(flourProcRow.cells['spend_paisa'], 240000);
      expect(flourProcRow.cells['base_quantity'], 20);
      expect(flourProcRow.cells['base_unit'], 'kg');
      expect(flourProcRow.cells['unit_price_paisa'], 12000); // 12,000 paisa per kg

      // Unlinked purchase with missing unit/ingredient discloses null unit_price_paisa without guessing
      final unlinkedGenericRow = procurementSection.rows.firstWhere((r) => r.cells['purchase_id'] == null && r.cells['is_linked'] == false);
      expect(unlinkedGenericRow.cells['spend_paisa'], 150000);
      expect(unlinkedGenericRow.cells['base_quantity'], isNull);
      expect(unlinkedGenericRow.cells['unit_price_paisa'], isNull);

      // Check receipt evidence rows
      final evidenceRows = procurementSection.rows.where((r) => r.sourceType == 'supplier_receipt_evidence').toList();
      expect(evidenceRows, hasLength(4));
      final onTimeEvidence = evidenceRows.firstWhere((r) => r.cells['punctuality_status'] == 'ON_TIME');
      expect(onTimeEvidence.cells['delay_minutes'], -30);
      expect(onTimeEvidence.cells['supplier_name'], 'Habib Poultry');

      final lateEvidence = evidenceRows.firstWhere((r) => r.cells['punctuality_status'] == 'LATE');
      expect(lateEvidence.cells['delay_minutes'], 90);
      expect(lateEvidence.cells['supplier_name'], 'Shaheen Mills');

      // 3. Export validation
      final exports = AnalyticsExportService();
      final csv = exports.csv(snapshot, AnalyticsFamily.procurement);
      expect(csv, contains('unified_spend'));
      expect(csv, contains('supplier_performance'));
      expect(csv, contains('Habib Poultry'));
      expect(csv, contains('Shaheen Mills'));
      expect(csv, contains('ON_TIME'));
      expect(csv, contains('LATE'));
    });

    test('discloses unavailable punctuality when no valid receipt evidence exists', () async {
      await db.insert('business_days', {
        'opened_at': '2026-10-26 00:00:00',
        'closed_at': '2026-10-26 23:59:59',
        'status': 'CLOSED',
        'opened_by_staff_id': manager.id,
      });

      final analyticsService = AnalyticsService(database: db, authService: auth);
      final query = AnalyticsQuery(startDate: DateTime(2026, 10, 26), endDateExclusive: DateTime(2026, 10, 27));
      final snapshot = await analyticsService.load(query);

      final procMetric = snapshot.section(AnalyticsFamily.procurement).metrics.firstWhere((m) => m.id == 'supplier_performance');
      expect(procMetric.value, isNull);
      expect(procMetric.quality, AnalyticsQuality.missing);
      expect(procMetric.explanation, contains('No delivery commitments'));
    });
  });
}
