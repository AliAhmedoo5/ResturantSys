/// Categorized reasons for logging kitchen ingredient waste and food-cost losses.
enum WastageReason {
  burned(
    code: 'BURNED',
    displayName: 'Burned / Prep Mistake',
    description: 'Ingredient burned during cooking, seasoning error, or preparation mistake',
  ),
  dropped(
    code: 'DROPPED',
    displayName: 'Dropped / Contaminated',
    description: 'Fell on floor, contaminated by unhygienic surface, or spilled',
  ),
  expired(
    code: 'EXPIRED',
    displayName: 'Expired / Spoiled',
    description: 'Past shelf life, sour, rotten, or storage temperature failure',
  ),
  testing(
    code: 'TESTING',
    displayName: 'R&D / Testing',
    description: 'Recipe testing, quality sampling, or staff culinary training',
  ),
  wastedCooked(
    code: 'WASTED_COOKED',
    displayName: 'Cooked Wastage / Order Revision',
    description: 'Item removed or order canceled after food preparation commenced',
  );

  const WastageReason({
    required this.code,
    required this.displayName,
    required this.description,
  });

  final String code;
  final String displayName;
  final String description;

  static WastageReason fromCode(String code) {
    return WastageReason.values.firstWhere(
      (r) => r.code.toUpperCase() == code.trim().toUpperCase(),
      orElse: () => WastageReason.burned,
    );
  }
}
