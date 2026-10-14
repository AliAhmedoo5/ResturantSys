import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/procurement/desi_unit.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/procurement/wastage_reason.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ProcurementAndWastageController Domain Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;
    late ProcurementAndWastageController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('procurement_controller_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_procurement_controller.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      authService = AuthService(database: db);
      controller = ProcurementAndWastageController(
        database: db,
        authService: authService,
      );
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<int> insertTestIngredient({
      required String name,
      required StorageUnit unit,
      double initialStock = 0.0,
      double costPerRecipeUnit = 0.0,
    }) async {
      return await db.insert(
        PosDatabaseConstants.tableRawIngredients,
        {
          'name': name,
          'storage_unit': unit.code,
          'current_stock': initialStock,
          'low_stock_threshold': 500.0,
          'cost_per_recipe_unit': costPerRecipeUnit,
          'created_at': '2026-10-14 12:00:00',
        },
      );
    }

    test('recordMandiPurchase converts traditional units, increments stock, and updates recipe unit cost', () async {
      // 1. Create an ingredient tracked in grams (e.g. Onions)
      final onionId = await insertTestIngredient(
        name: 'Onions',
        unit: StorageUnit.g,
        initialStock: 5000.0,
        costPerRecipeUnit: 0.05,
      );

      // 2. Buy 1 Mann (40,000 g) of Onions for Rs. 4,000
      final purchase = await controller.recordMandiPurchase(
        rawIngredientId: onionId,
        unit: DesiUnit.mann,
        quantity: 1.0,
        totalCost: 4000.0,
        notes: 'Sabzi Mandi Islamabad Stall 14',
      );

      expect(purchase.rawIngredientId, equals(onionId));
      expect(purchase.traditionalUnit, equals(DesiUnit.mann));
      expect(purchase.quantity, equals(1.0));
      expect(purchase.totalCost, equals(4000.0));
      expect(purchase.convertedQuantity, equals(40000.0));
      // Unit cost: 4000 / 40000 = Rs. 0.10 / g
      expect(purchase.costPerRecipeUnit, equals(0.10));

      // 3. Verify raw ingredient row updated in SQLite
      final updatedRows = await db.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [onionId],
      );
      final updatedOnion = updatedRows.first;
      // Initial 5000 + 40000 = 45000 g
      expect(updatedOnion['current_stock'], equals(45000.0));
      expect(updatedOnion['cost_per_recipe_unit'], equals(0.10));

      // 4. Verify procurement log persisted
      final procurements = await controller.getProcurements(rawIngredientId: onionId);
      expect(procurements.length, equals(1));
      expect(procurements.first.rawIngredientName, equals('Onions'));
      expect(procurements.first.notes, equals('Sabzi Mandi Islamabad Stall 14'));
    });

    test('recordMandiPurchase handles dozen (Darjan) and crate (Peti) conversions', () async {
      // Eggs in count
      final eggId = await insertTestIngredient(
        name: 'Farm Eggs',
        unit: StorageUnit.count,
        initialStock: 24.0,
        costPerRecipeUnit: 20.0,
      );

      // Buy 5 Darjan (60 count) for Rs. 1,800
      final eggPurchase = await controller.recordMandiPurchase(
        rawIngredientId: eggId,
        unit: DesiUnit.darjan,
        quantity: 5.0,
        totalCost: 1800.0,
      );

      expect(eggPurchase.convertedQuantity, equals(60.0));
      expect(eggPurchase.costPerRecipeUnit, equals(30.0)); // 1800 / 60

      final eggRows = await db.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [eggId],
      );
      expect(eggRows.first['current_stock'], equals(84.0)); // 24 + 60
      expect(eggRows.first['cost_per_recipe_unit'], equals(30.0));

      // Cooking Oil in ml
      final oilId = await insertTestIngredient(
        name: 'Cooking Oil',
        unit: StorageUnit.ml,
        initialStock: 4000.0,
        costPerRecipeUnit: 0.40,
      );

      // Buy 1 Peti (16,000 ml) for Rs. 8,000
      final oilPurchase = await controller.recordMandiPurchase(
        rawIngredientId: oilId,
        unit: DesiUnit.peti,
        quantity: 1.0,
        totalCost: 8000.0,
      );

      expect(oilPurchase.convertedQuantity, equals(16000.0));
      expect(oilPurchase.costPerRecipeUnit, equals(0.50)); // 8000 / 16000

      final oilRows = await db.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [oilId],
      );
      expect(oilRows.first['current_stock'], equals(20000.0)); // 4000 + 16000
      expect(oilRows.first['cost_per_recipe_unit'], equals(0.50));
    });

    test('recordMandiPurchase rejects non-positive quantities or costs', () async {
      final ingId = await insertTestIngredient(name: 'Salt', unit: StorageUnit.g);

      expect(
        () async => await controller.recordMandiPurchase(
          rawIngredientId: ingId,
          unit: DesiUnit.mann,
          quantity: 0.0,
          totalCost: 1000.0,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(
        () async => await controller.recordMandiPurchase(
          rawIngredientId: ingId,
          unit: DesiUnit.mann,
          quantity: 1.0,
          totalCost: -100.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('recordKitchenWastage verifies staff PIN, deducts stock, and computes financial cost loss', () async {
      // 1. Insert ingredient with unit cost
      final beefId = await insertTestIngredient(
        name: 'Beef Patty Mince',
        unit: StorageUnit.g,
        initialStock: 10000.0,
        costPerRecipeUnit: 0.80, // Rs. 0.80 / g = Rs. 800 / kg
      );

      // 2. Kitchen Cook (default PIN 2222) logs burned stock (500g)
      final wastage = await controller.recordKitchenWastage(
        staffPin: PosDatabaseConstants.defaultKitchenPin, // 2222
        rawIngredientId: beefId,
        quantity: 500.0,
        reason: WastageReason.burned,
        notes: 'Grill temperature spike charred patties',
      );

      expect(wastage.rawIngredientId, equals(beefId));
      expect(wastage.staffName, equals(PosDatabaseConstants.defaultKitchenName));
      expect(wastage.quantity, equals(500.0));
      expect(wastage.reason, equals(WastageReason.burned));
      // Cost loss: 500g * Rs. 0.80 = Rs. 400.00
      expect(wastage.costLoss, equals(400.0));

      // 3. Verify stock was deducted immediately in SQLite
      final beefRows = await db.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [beefId],
      );
      // 10000 - 500 = 9500 g
      expect(beefRows.first['current_stock'], equals(9500.0));

      // 4. Verify wastage audit record persisted
      final logs = await controller.getWastageLogs(rawIngredientId: beefId);
      expect(logs.length, equals(1));
      expect(logs.first.reason, equals(WastageReason.burned));
      expect(logs.first.costLoss, equals(400.0));

      // 5. Total wastage loss aggregation
      final totalLoss = await controller.getTotalWastageLoss();
      expect(totalLoss, equals(400.0));
    });

    test('recordKitchenWastage rejects invalid staff PIN', () async {
      final ingId = await insertTestIngredient(
        name: 'Cheese Slices',
        unit: StorageUnit.count,
        initialStock: 100.0,
        costPerRecipeUnit: 35.0,
      );

      expect(
        () async => await controller.recordKitchenWastage(
          staffPin: '9999', // Non-existent PIN
          rawIngredientId: ingId,
          quantity: 5.0,
          reason: WastageReason.dropped,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('recordKitchenWastage allows soft negative stock under rush conditions', () async {
      final bunId = await insertTestIngredient(
        name: 'Brioche Bun',
        unit: StorageUnit.count,
        initialStock: 2.0,
        costPerRecipeUnit: 40.0,
      );

      // Discard 5 buns when only 2 are in system stock (soft deduction)
      final wastage = await controller.recordKitchenWastage(
        staffPin: PosDatabaseConstants.defaultKitchenPin,
        rawIngredientId: bunId,
        quantity: 5.0,
        reason: WastageReason.expired,
      );

      expect(wastage.costLoss, equals(200.0)); // 5 * 40

      final bunRows = await db.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [bunId],
      );
      // 2.0 - 5.0 = -3.0
      expect(bunRows.first['current_stock'], equals(-3.0));
    });
  });
}
