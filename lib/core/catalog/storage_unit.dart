/// Base physical storage and recipe measurement units for kitchen stock.
enum StorageUnit {
  g('g', 'Grams'),
  kg('kg', 'Kilograms'),
  ml('ml', 'Milliliters'),
  count('count', 'Count / Pieces');

  const StorageUnit(this.code, this.displayName);

  final String code;
  final String displayName;

  static StorageUnit fromCode(String code) {
    return StorageUnit.values.firstWhere(
      (u) => u.code.toLowerCase() == code.toLowerCase(),
      orElse: () => StorageUnit.count,
    );
  }
}
