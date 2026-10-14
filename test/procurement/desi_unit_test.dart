import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/procurement/desi_unit.dart';
import 'package:resturant_sys/core/procurement/wastage_reason.dart';

void main() {
  group('DesiUnit Traditional Wholesale Unit Tests', () {
    test('Mann conversion multipliers (40kg equivalence)', () {
      expect(DesiUnit.mann.conversionMultiplier(StorageUnit.kg), equals(40.0));
      expect(DesiUnit.mann.conversionMultiplier(StorageUnit.g), equals(40000.0));

      // 2.5 Mann into grams = 100,000 g
      expect(DesiUnit.mann.toRecipeUnits(2.5, StorageUnit.g), equals(100000.0));
      // 2.5 Mann into kilograms = 100 kg
      expect(DesiUnit.mann.toRecipeUnits(2.5, StorageUnit.kg), equals(100.0));

      // Auto-calculated unit cost per gram: Rs. 10,000 for 2.5 Mann (100,000g) = Rs. 0.10/g
      final unitCostG = DesiUnit.mann.calculateCostPerRecipeUnit(
        totalCost: 10000.0,
        quantity: 2.5,
        targetUnit: StorageUnit.g,
      );
      expect(unitCostG, equals(0.10));

      // Auto-calculated unit cost per kg: Rs. 10,000 for 2.5 Mann (100kg) = Rs. 100.00/kg
      final unitCostKg = DesiUnit.mann.calculateCostPerRecipeUnit(
        totalCost: 10000.0,
        quantity: 2.5,
        targetUnit: StorageUnit.kg,
      );
      expect(unitCostKg, equals(100.0));
    });

    test('Darjan conversion multipliers (12 count equivalence)', () {
      expect(DesiUnit.darjan.conversionMultiplier(StorageUnit.count), equals(12.0));

      // 5 Darjan into count = 60 count
      expect(DesiUnit.darjan.toRecipeUnits(5, StorageUnit.count), equals(60.0));

      // Auto-calculated unit cost per count: Rs. 1,500 for 5 Darjan = Rs. 25.00/count
      final unitCost = DesiUnit.darjan.calculateCostPerRecipeUnit(
        totalCost: 1500.0,
        quantity: 5,
        targetUnit: StorageUnit.count,
      );
      expect(unitCost, equals(25.0));
    });

    test('Peti conversion multipliers (16L/crate equivalence)', () {
      expect(DesiUnit.peti.conversionMultiplier(StorageUnit.ml), equals(16000.0));
      expect(DesiUnit.peti.conversionMultiplier(StorageUnit.count), equals(16.0));

      // 2 Peti of cooking oil into ml = 32,000 ml
      expect(DesiUnit.peti.toRecipeUnits(2, StorageUnit.ml), equals(32000.0));

      // Auto-calculated unit cost per ml: Rs. 16,000 for 2 Peti = Rs. 0.50/ml
      final unitCost = DesiUnit.peti.calculateCostPerRecipeUnit(
        totalCost: 16000.0,
        quantity: 2,
        targetUnit: StorageUnit.ml,
      );
      expect(unitCost, equals(0.50));
    });

    test('Bori conversion multipliers (50kg sack equivalence)', () {
      expect(DesiUnit.bori.conversionMultiplier(StorageUnit.kg), equals(50.0));
      expect(DesiUnit.bori.conversionMultiplier(StorageUnit.g), equals(50000.0));

      // 1 Bori of flour into grams = 50,000 g
      expect(DesiUnit.bori.toRecipeUnits(1, StorageUnit.g), equals(50000.0));

      // Auto-calculated unit cost: Rs. 6,000 for 1 Bori = Rs. 0.12/g
      final unitCost = DesiUnit.bori.calculateCostPerRecipeUnit(
        totalCost: 6000.0,
        quantity: 1,
        targetUnit: StorageUnit.g,
      );
      expect(unitCost, closeTo(0.12, 0.0001));
    });

    test('Dharri conversion multipliers (5kg measure equivalence)', () {
      expect(DesiUnit.dharri.conversionMultiplier(StorageUnit.kg), equals(5.0));
      expect(DesiUnit.dharri.conversionMultiplier(StorageUnit.g), equals(5000.0));

      // 4 Dharri of potatoes into kg = 20 kg
      expect(DesiUnit.dharri.toRecipeUnits(4, StorageUnit.kg), equals(20.0));

      // Auto-calculated unit cost: Rs. 1,600 for 4 Dharri = Rs. 80.00/kg
      final unitCost = DesiUnit.dharri.calculateCostPerRecipeUnit(
        totalCost: 1600.0,
        quantity: 4,
        targetUnit: StorageUnit.kg,
      );
      expect(unitCost, equals(80.0));
    });

    test('Pao conversion multipliers (250g measure equivalence)', () {
      expect(DesiUnit.pao.conversionMultiplier(StorageUnit.g), equals(250.0));
      expect(DesiUnit.pao.conversionMultiplier(StorageUnit.kg), equals(0.25));

      // 4 Pao into grams = 1,000 g
      expect(DesiUnit.pao.toRecipeUnits(4, StorageUnit.g), equals(1000.0));

      // Auto-calculated unit cost: Rs. 500 for 4 Pao = Rs. 0.50/g
      final unitCost = DesiUnit.pao.calculateCostPerRecipeUnit(
        totalCost: 500.0,
        quantity: 4,
        targetUnit: StorageUnit.g,
      );
      expect(unitCost, equals(0.50));
    });

    test('DesiUnit.fromCode parses code safely with fallback', () {
      expect(DesiUnit.fromCode('MANN'), equals(DesiUnit.mann));
      expect(DesiUnit.fromCode('darjan'), equals(DesiUnit.darjan));
      expect(DesiUnit.fromCode('PETI'), equals(DesiUnit.peti));
      expect(DesiUnit.fromCode('bori'), equals(DesiUnit.bori));
      expect(DesiUnit.fromCode('dharri'), equals(DesiUnit.dharri));
      expect(DesiUnit.fromCode('pao'), equals(DesiUnit.pao));
      expect(DesiUnit.fromCode('UNKNOWN'), equals(DesiUnit.mann));
    });

    test('calculateCostPerRecipeUnit handles zero or negative quantities safely', () {
      expect(
        DesiUnit.mann.calculateCostPerRecipeUnit(totalCost: 1000, quantity: 0, targetUnit: StorageUnit.g),
        equals(0.0),
      );
      expect(
        DesiUnit.mann.calculateCostPerRecipeUnit(totalCost: 1000, quantity: -1, targetUnit: StorageUnit.g),
        equals(0.0),
      );
    });
  });

  group('WastageReason Tests', () {
    test('WastageReason contains all 4 mandatory categorized reasons', () {
      expect(WastageReason.values.length, equals(4));
      expect(WastageReason.burned.code, equals('BURNED'));
      expect(WastageReason.dropped.code, equals('DROPPED'));
      expect(WastageReason.expired.code, equals('EXPIRED'));
      expect(WastageReason.testing.code, equals('TESTING'));

      expect(WastageReason.burned.displayName, equals('Burned / Prep Mistake'));
      expect(WastageReason.dropped.displayName, equals('Dropped / Contaminated'));
      expect(WastageReason.expired.displayName, equals('Expired / Spoiled'));
      expect(WastageReason.testing.displayName, equals('R&D / Testing'));
    });

    test('WastageReason.fromCode parses code safely with fallback', () {
      expect(WastageReason.fromCode('BURNED'), equals(WastageReason.burned));
      expect(WastageReason.fromCode('dropped'), equals(WastageReason.dropped));
      expect(WastageReason.fromCode('EXPIRED'), equals(WastageReason.expired));
      expect(WastageReason.fromCode('testing'), equals(WastageReason.testing));
      expect(WastageReason.fromCode('INVALID'), equals(WastageReason.burned));
    });
  });
}
