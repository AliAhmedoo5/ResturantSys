import 'package:resturant_sys/core/catalog/storage_unit.dart';

/// Localized Pakistani traditional wholesale market units ("Desi Units")
/// for wholesale procurement with automatic recipe unit conversion.
enum DesiUnit {
  /// Mann: Standard wholesale weight unit = 40 kg.
  mann(
    code: 'MANN',
    displayName: 'Mann (من)',
    metricEquivalence: '40 kg',
  ),

  /// Darjan: Standard dozen count unit = 12 units.
  darjan(
    code: 'DARJAN',
    displayName: 'Darjan (درجن)',
    metricEquivalence: '12 count',
  ),

  /// Peti: Wholesale crate/box = 16 L (for liquids/oil) or 16 units.
  peti(
    code: 'PETI',
    displayName: 'Peti (پیٹی)',
    metricEquivalence: '16 L / crate',
  ),

  /// Bori: Standard wholesale sack = 50 kg (e.g., flour, sugar, potatoes).
  bori(
    code: 'BORI',
    displayName: 'Bori (بوری)',
    metricEquivalence: '50 kg',
  ),

  /// Dharri: Traditional 5 kg measure (common in Punjab & Sindh vegetable markets).
  dharri(
    code: 'DHARRI',
    displayName: 'Dharri (دھڑی)',
    metricEquivalence: '5 kg',
  ),

  /// Pao: Traditional quarter-kilogram measure = 250 g.
  pao(
    code: 'PAO',
    displayName: 'Pao (پاؤ)',
    metricEquivalence: '250 g',
  );

  const DesiUnit({
    required this.code,
    required this.displayName,
    required this.metricEquivalence,
  });

  final String code;
  final String displayName;
  final String metricEquivalence;

  static const Map<(DesiUnit, StorageUnit), double> _conversionMap = {
    // Mann = 40 kg
    (DesiUnit.mann, StorageUnit.kg): 40.0,
    (DesiUnit.mann, StorageUnit.g): 40000.0,
    (DesiUnit.mann, StorageUnit.ml): 40000.0,
    (DesiUnit.mann, StorageUnit.count): 40.0,

    // Darjan = 12 count
    (DesiUnit.darjan, StorageUnit.count): 12.0,
    (DesiUnit.darjan, StorageUnit.kg): 12.0,
    (DesiUnit.darjan, StorageUnit.g): 12.0,
    (DesiUnit.darjan, StorageUnit.ml): 12.0,

    // Peti = 16 L / crate
    (DesiUnit.peti, StorageUnit.ml): 16000.0,
    (DesiUnit.peti, StorageUnit.kg): 16.0,
    (DesiUnit.peti, StorageUnit.g): 16000.0,
    (DesiUnit.peti, StorageUnit.count): 16.0,

    // Bori = 50 kg
    (DesiUnit.bori, StorageUnit.kg): 50.0,
    (DesiUnit.bori, StorageUnit.g): 50000.0,
    (DesiUnit.bori, StorageUnit.ml): 50000.0,
    (DesiUnit.bori, StorageUnit.count): 50.0,

    // Dharri = 5 kg
    (DesiUnit.dharri, StorageUnit.kg): 5.0,
    (DesiUnit.dharri, StorageUnit.g): 5000.0,
    (DesiUnit.dharri, StorageUnit.ml): 5000.0,
    (DesiUnit.dharri, StorageUnit.count): 5.0,

    // Pao = 250 g
    (DesiUnit.pao, StorageUnit.g): 250.0,
    (DesiUnit.pao, StorageUnit.kg): 0.25,
    (DesiUnit.pao, StorageUnit.ml): 250.0,
    (DesiUnit.pao, StorageUnit.count): 0.25,
  };

  /// Returns the multiplier converting 1 purchase unit of this [DesiUnit]
  /// into the target [StorageUnit] used by the recipe / inventory system.
  double conversionMultiplier(StorageUnit targetUnit) {
    return _conversionMap[(this, targetUnit)] ?? 1.0;
  }

  /// Converts a purchased quantity in this [DesiUnit] into the recipe [StorageUnit].
  double toRecipeUnits(double quantity, StorageUnit targetUnit) {
    return quantity * conversionMultiplier(targetUnit);
  }

  /// Calculates the unit cost per recipe unit (e.g. Rs./g, Rs./kg, Rs./ml, Rs./count)
  /// given the total amount paid and purchased quantity.
  double calculateCostPerRecipeUnit({
    required double totalCost,
    required double quantity,
    required StorageUnit targetUnit,
  }) {
    final recipeUnits = toRecipeUnits(quantity, targetUnit);
    if (recipeUnits <= 0) {
      return 0.0;
    }
    return totalCost / recipeUnits;
  }

  static DesiUnit fromCode(String code) {
    return DesiUnit.values.firstWhere(
      (u) => u.code.toUpperCase() == code.trim().toUpperCase(),
      orElse: () => DesiUnit.mann,
    );
  }
}
