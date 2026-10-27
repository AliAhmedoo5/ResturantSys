import '../orders/cart_item.dart';

/// Empty lists mean unrestricted. A checkout selects one non-stacking preset.
class DiscountRules {
  const DiscountRules({this.minimumSpendPaisa = 0, this.maximumDiscountPaisa,
    this.startsAt, this.endsAt, this.startMinute, this.endMinute,
    this.diningModes = const [], this.categoryIds = const [], this.dealIds = const [],
    this.cashierIds = const [], this.dailyLimit});

  final int minimumSpendPaisa;
  final int? maximumDiscountPaisa;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? startMinute;
  final int? endMinute;
  final List<String> diningModes;
  final List<int> categoryIds;
  final List<int> dealIds;
  final List<int> cashierIds;
  final int? dailyLimit;

  void validate() {
    if (minimumSpendPaisa < 0 || (maximumDiscountPaisa != null && maximumDiscountPaisa! <= 0) ||
        (dailyLimit != null && dailyLimit! <= 0) ||
        (startsAt != null && endsAt != null && !endsAt!.isAfter(startsAt!)) ||
        (startMinute == null) != (endMinute == null) ||
        [startMinute, endMinute].any((v) => v != null && (v < 0 || v > 1439)) ||
        diningModes.any((v) => !['DINE_IN','TAKEAWAY','DELIVERY'].contains(v)) ||
        [...categoryIds, ...dealIds, ...cashierIds].any((v) => v <= 0)) {
      throw ArgumentError('Invalid discount restrictions, dates, times or limits.');
    }
  }

  bool eligible({required int subtotalPaisa, required DateTime now, String? diningMode, int? cashierId}) {
    final minute = now.hour * 60 + now.minute;
    final inWindow = startMinute == null || (startMinute! <= endMinute!
      ? minute >= startMinute! && minute <= endMinute!
      : minute >= startMinute! || minute <= endMinute!);
    return subtotalPaisa >= minimumSpendPaisa &&
      (startsAt == null || !now.isBefore(startsAt!)) && (endsAt == null || now.isBefore(endsAt!)) &&
      inWindow && (diningModes.isEmpty || diningModes.contains(diningMode)) &&
      (cashierIds.isEmpty || cashierIds.contains(cashierId));
  }

  bool includes(CartItem item) => categoryIds.isEmpty && dealIds.isEmpty ||
    (item.menuItem != null && categoryIds.contains(item.menuItem!.categoryId)) ||
    (item.deal != null && dealIds.contains(item.deal!.id));

  Map<String, Object?> toMap() => {'minimum_spend_paisa': minimumSpendPaisa,
    'maximum_discount_paisa': maximumDiscountPaisa, 'starts_at': startsAt?.toIso8601String(),
    'ends_at': endsAt?.toIso8601String(), 'start_minute': startMinute, 'end_minute': endMinute,
    'dining_modes': diningModes, 'category_ids': categoryIds, 'deal_ids': dealIds,
    'cashier_ids': cashierIds, 'daily_limit': dailyLimit};

  factory DiscountRules.fromMap(Map<String, dynamic> map) => DiscountRules(
    minimumSpendPaisa: (map['minimum_spend_paisa'] as num?)?.toInt() ?? 0,
    maximumDiscountPaisa: (map['maximum_discount_paisa'] as num?)?.toInt(),
    startsAt: map['starts_at'] == null ? null : DateTime.parse(map['starts_at'] as String),
    endsAt: map['ends_at'] == null ? null : DateTime.parse(map['ends_at'] as String),
    startMinute: map['start_minute'] as int?, endMinute: map['end_minute'] as int?,
    diningModes: List<String>.from(map['dining_modes'] as List? ?? []),
    categoryIds: List<int>.from(map['category_ids'] as List? ?? []),
    dealIds: List<int>.from(map['deal_ids'] as List? ?? []),
    cashierIds: List<int>.from(map['cashier_ids'] as List? ?? []), dailyLimit: map['daily_limit'] as int?);
}
