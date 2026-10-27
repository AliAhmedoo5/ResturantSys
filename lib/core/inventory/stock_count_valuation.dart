/// v20 multiplied kg variances by 1000 despite acquisition rates being per kg.
/// Preserve that stored evidence and normalize its known unit error for reports.
abstract final class StockCountValuation {
  static int? paisa(Map<String, Object?> row) {
    final recorded = (row['estimated_cost_paisa'] as num?)?.toInt();
    if (recorded == null) return null;
    return row['unit'] == 'kg' && row['valuation_policy'] != 'STORAGE_UNIT_RATE_V1'
      ? (recorded / 1000).round() : recorded;
  }
}
