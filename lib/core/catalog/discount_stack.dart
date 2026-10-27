import 'dart:math' as math;
import '../orders/cart_item.dart';
import 'discount_preset.dart';

/// Stable preset-ID order, applied to remaining eligible line balances.
/// Every participating preset must explicitly permit stacking.
class DiscountStack {
  static Map<int, int> amounts({required List<CartItem> items, required List<DiscountPreset> discounts,
      String? diningMode, int? cashierId, DateTime? now}) {
    if (discounts.map((d) => d.id).toSet().length != discounts.length) throw ArgumentError('A discount can be selected only once.');
    if (discounts.length > 1 && discounts.any((d) => !d.rules.stackable)) throw StateError('These discounts cannot be combined.');
    final ordered = [...discounts]..sort((a, b) => a.id.compareTo(b.id));
    final balances = items.map((i) => (i.totalPrice * 100).round()).toList();
    final subtotal = balances.fold<int>(0, (sum, n) => sum + n);
    final result = <int, int>{};
    final time = now ?? DateTime.now();
    for (final discount in ordered) {
      if (!discount.isActive || !discount.value.isFinite || discount.value <= 0 ||
          !discount.rules.eligible(subtotalPaisa: subtotal, now: time, diningMode: diningMode, cashierId: cashierId)) {
        result[discount.id] = 0; continue;
      }
      final indices = [for (var i = 0; i < items.length; i++) if (discount.rules.includes(items[i])) i];
      final eligible = indices.fold<int>(0, (sum, i) => sum + balances[i]);
      var amount = discount.type == DiscountType.percentage
        ? (eligible * (discount.value * 100).round() + 5000) ~/ 10000 : (discount.value * 100).round();
      amount = math.min(amount, eligible);
      if (discount.rules.maximumDiscountPaisa != null) amount = math.min(amount, discount.rules.maximumDiscountPaisa!);
      result[discount.id] = amount;
      // Running proportions allocate every paisa and never discount a line below zero.
      var left = amount, basis = eligible;
      for (final i in indices) {
        final share = basis == 0 ? 0 : left * balances[i] ~/ basis;
        basis -= balances[i]; balances[i] -= share; left -= share;
      }
    }
    return result;
  }
}
