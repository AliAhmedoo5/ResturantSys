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

  /// Returns the multiplier converting 1 purchase unit of this [DesiUnit]
  /// into the target [StorageUnit] used by the recipe / inventory system.
  double conversionMultiplier(StorageUnit targetUnit) {
    switch (this) {
      case DesiUnit.mann:
        switch (targetUnit) {
          case StorageUnit.kg:
            return 40.0;
          case StorageUnit.g:
            return 40000.0;
          case StorageUnit.ml:
            return 40000.0;
          case StorageUnit.count:
            return 40.0;
        }

      case DesiUnit.darjan:
        switch (targetUnit) {
          case StorageUnit.count:
            return 12.0;
          case StorageUnit.kg:
            return 12.0;
          case StorageUnit.g:
            return 12.0;
          case StorageUnit.ml:
            return 12.0;
        }

      case DesiUnit.peti:
        switch (targetUnit) {
          case StorageUnit.ml:
            return 16000.0; // 16 Liters = 16,000 ml
          case StorageUnit.kg:
            return 16.0;
          case StorageUnit.g:
            return 16000.0;
          case StorageUnit.count:
            return 16.0;
        }

      case DesiUnit.bori:
        switch (targetUnit) {
          case StorageUnit.kg:
            return 50.0;
          case StorageUnit.g:
            return 50000.0;
          case StorageUnit.ml:
            return 50000.0;
          case StorageUnit.count:
            return 50.0;
        }

      case DesiUnit.dharri:
        switch (targetUnit) {
          case StorageUnit.kg:
            return 5.0;
          case StorageUnit.g:
            return 5000.0;
          case StorageUnit.ml:
            return 5000.0;
          case StorageUnit.count:
            return 5.0;
        }

      case DesiUnit.pao:
        switch (targetUnit) {
          case StorageUnit.g:
            return 250.0;
          case StorageUnit.kg:
            return 0.25;
          case StorageUnit.ml:
            return 250.0;
          case StorageUnit.count:
            return 0.25;
        }
    }
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
