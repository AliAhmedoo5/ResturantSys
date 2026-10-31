import 'order_item_allocation.dart';

/// Helper result representing an expanded deal component's allocated shares.
class DealComponentAllocation {
  const DealComponentAllocation({
    required this.index,
    required this.standalonePricePaisa,
    required this.grossSalesPaisa,
    required this.allocatedDiscountPaisa,
    required this.netSalesPaisa,
    required this.taxCarveOutPaisa,
    this.bomRecipeCostPaisa,
    this.contributionMarginPaisa,
  });

  final int index;
  final int standalonePricePaisa;
  final int grossSalesPaisa;
  final int allocatedDiscountPaisa;
  final int netSalesPaisa;
  final int taxCarveOutPaisa;
  final int? bomRecipeCostPaisa;
  final int? contributionMarginPaisa;
}

/// Pure domain allocation engine strictly implementing ADR-0021.
///
/// Features:
/// 1. Signed 64-bit Integer Paisa arithmetic.
/// 2. Proportional discount and tax carve-out allocation with zero-leak rounding
///    (floor division + 1 paisa residual to largest lines, tie-broken by cart index).
/// 3. Deal component expansion weighted by standalone regular catalog prices.
/// 4. Explicit contra-allocations for revisions, item voids, and returns.
abstract final class OrderAllocationEngine {
  /// Allocates an order-level discount across order lines proportionally to their gross values.
  ///
  /// Formula (ADR-0021 Section 1):
  /// raw_discount_i = (gross_i / gross_total) * total_discount
  /// base_discount_i = floor(raw_discount_i)
  /// residual Delta = total_discount - sum(base_discount_i)
  ///
  /// The residual Delta (0 <= Delta < n) is distributed by adding 1 paisa to the lines
  /// with the highest gross subtotal. Ties are broken deterministically by earliest index.
  static List<int> allocateDiscounts({
    required List<int> lineGrossPaisa,
    required int totalDiscountPaisa,
  }) {
    final count = lineGrossPaisa.length;
    if (count == 0) return const [];
    if (totalDiscountPaisa <= 0) return List<int>.filled(count, 0);

    final totalGross = lineGrossPaisa.fold<int>(0, (sum, g) => sum + g);
    if (totalGross <= 0) return List<int>.filled(count, 0);

    // If total discount exceeds or equals gross, discount equals gross
    if (totalDiscountPaisa >= totalGross) {
      return List<int>.from(lineGrossPaisa);
    }

    // 1. Integer floor division
    final baseDiscounts = List<int>.filled(count, 0);
    var baseSum = 0;
    for (var i = 0; i < count; i++) {
      final gross = lineGrossPaisa[i];
      if (gross <= 0) {
        baseDiscounts[i] = 0;
      } else {
        final base = (gross * totalDiscountPaisa) ~/ totalGross;
        baseDiscounts[i] = base;
        baseSum += base;
      }
    }

    // 2. Rounding residual
    var residual = totalDiscountPaisa - baseSum;
    if (residual <= 0) return baseDiscounts;

    // 3. Sort indices by lineGrossPaisa descending, then index ascending (tie-breaker)
    final sortedIndices = List<int>.generate(count, (i) => i)
      ..sort((a, b) {
        final grossCompare = lineGrossPaisa[b].compareTo(lineGrossPaisa[a]);
        if (grossCompare != 0) return grossCompare;
        return a.compareTo(b);
      });

    final finalDiscounts = List<int>.from(baseDiscounts);
    for (var rank = 0; rank < count && residual > 0; rank++) {
      final idx = sortedIndices[rank];
      // Only allocate residual to lines with positive gross
      if (lineGrossPaisa[idx] > finalDiscounts[idx]) {
        finalDiscounts[idx] += 1;
        residual -= 1;
      }
    }

    return finalDiscounts;
  }

  /// Allocates order-level sales tax carve-out proportionally across taxable lines
  /// based on their line net sales (ADR-0021 Section 2).
  static List<int> allocateTaxCarveOut({
    required List<int> lineNetSalesPaisa,
    required List<bool> isTaxable,
    required int totalTaxPaisa,
  }) {
    final count = lineNetSalesPaisa.length;
    if (count == 0) return const [];
    if (totalTaxPaisa <= 0) return List<int>.filled(count, 0);

    var totalTaxableNet = 0;
    for (var i = 0; i < count; i++) {
      if (i < isTaxable.length && isTaxable[i] && lineNetSalesPaisa[i] > 0) {
        totalTaxableNet += lineNetSalesPaisa[i];
      }
    }

    if (totalTaxableNet <= 0) return List<int>.filled(count, 0);

    final baseTaxes = List<int>.filled(count, 0);
    var baseSum = 0;
    for (var i = 0; i < count; i++) {
      if (i < isTaxable.length && isTaxable[i] && lineNetSalesPaisa[i] > 0) {
        final base = (lineNetSalesPaisa[i] * totalTaxPaisa) ~/ totalTaxableNet;
        baseTaxes[i] = base;
        baseSum += base;
      }
    }

    var residual = totalTaxPaisa - baseSum;
    if (residual <= 0) return baseTaxes;

    final sortedIndices = List<int>.generate(count, (i) => i)
      ..sort((a, b) {
        final netCompare = lineNetSalesPaisa[b].compareTo(lineNetSalesPaisa[a]);
        if (netCompare != 0) return netCompare;
        return a.compareTo(b);
      });

    final finalTaxes = List<int>.from(baseTaxes);
    for (var rank = 0; rank < count && residual > 0; rank++) {
      final idx = sortedIndices[rank];
      if (idx < isTaxable.length && isTaxable[idx] && lineNetSalesPaisa[idx] > 0) {
        finalTaxes[idx] += 1;
        residual -= 1;
      }
    }

    return finalTaxes;
  }

  /// Expands a Deal bundle package price across constituent components weighted by
  /// their standalone catalog regular menu prices (ADR-0021 Section 3).
  static List<DealComponentAllocation> expandDealComponents({
    required int dealGrossPaisa,
    required int dealAllocatedDiscountPaisa,
    required int dealTaxCarveOutPaisa,
    required List<int> componentStandalonePricesPaisa,
    required List<int?> componentBomCostsPaisa,
  }) {
    final k = componentStandalonePricesPaisa.length;
    if (k == 0) return const [];

    final totalStandalone = componentStandalonePricesPaisa.fold<int>(0, (sum, p) => sum + p);
    final componentGross = List<int>.filled(k, 0);
    final componentDiscounts = List<int>.filled(k, 0);

    if (totalStandalone <= 0) {
      // Degenerate case: distribute gross and discount equally
      final eachGross = dealGrossPaisa ~/ k;
      final remGross = dealGrossPaisa % k;
      final eachDisc = dealAllocatedDiscountPaisa ~/ k;
      final remDisc = dealAllocatedDiscountPaisa % k;
      for (var i = 0; i < k; i++) {
        componentGross[i] = eachGross + (i < remGross ? 1 : 0);
        componentDiscounts[i] = eachDisc + (i < remDisc ? 1 : 0);
      }
    } else {
      // 1. Proportional gross share
      var baseGrossSum = 0;
      for (var i = 0; i < k; i++) {
        final p = componentStandalonePricesPaisa[i];
        final base = (p * dealGrossPaisa) ~/ totalStandalone;
        componentGross[i] = base;
        baseGrossSum += base;
      }
      var grossResidual = dealGrossPaisa - baseGrossSum;

      // 2. Proportional discount share
      var baseDiscountSum = 0;
      if (dealAllocatedDiscountPaisa > 0) {
        for (var i = 0; i < k; i++) {
          final p = componentStandalonePricesPaisa[i];
          final base = (p * dealAllocatedDiscountPaisa) ~/ totalStandalone;
          componentDiscounts[i] = base;
          baseDiscountSum += base;
        }
      }
      var discountResidual = dealAllocatedDiscountPaisa - baseDiscountSum;

      // Sort components by standalone price descending, then index ascending
      final sortedIndices = List<int>.generate(k, (i) => i)
        ..sort((a, b) {
          final priceCompare = componentStandalonePricesPaisa[b].compareTo(componentStandalonePricesPaisa[a]);
          if (priceCompare != 0) return priceCompare;
          return a.compareTo(b);
        });

      // Distribute gross residual +1 to highest standalone prices
      for (var rank = 0; rank < k && grossResidual > 0; rank++) {
        componentGross[sortedIndices[rank]] += 1;
        grossResidual -= 1;
      }

      // Distribute discount residual +1 to highest standalone prices
      for (var rank = 0; rank < k && discountResidual > 0; rank++) {
        componentDiscounts[sortedIndices[rank]] += 1;
        discountResidual -= 1;
      }
    }

    // 3. Compute net sales per component
    final componentNet = List<int>.generate(k, (i) => componentGross[i] - componentDiscounts[i]);

    // 4. Carve out tax across components
    final componentTaxes = dealTaxCarveOutPaisa > 0
        ? allocateTaxCarveOut(
            lineNetSalesPaisa: componentNet,
            isTaxable: List<bool>.filled(k, true),
            totalTaxPaisa: dealTaxCarveOutPaisa,
          )
        : List<int>.filled(k, 0);

    // 5. Build component allocation results
    final results = <DealComponentAllocation>[];
    for (var i = 0; i < k; i++) {
      final bomCost = i < componentBomCostsPaisa.length ? componentBomCostsPaisa[i] : null;
      final margin = bomCost == null ? null : (componentNet[i] - bomCost);
      results.add(DealComponentAllocation(
        index: i,
        standalonePricePaisa: componentStandalonePricesPaisa[i],
        grossSalesPaisa: componentGross[i],
        allocatedDiscountPaisa: componentDiscounts[i],
        netSalesPaisa: componentNet[i],
        taxCarveOutPaisa: componentTaxes[i],
        bomRecipeCostPaisa: bomCost,
        contributionMarginPaisa: margin,
      ));
    }

    return results;
  }

  /// Creates a contra-allocation line for an item void, revision reduction, or refund (ADR-0021 Section 5).
  static OrderItemAllocation createContraAllocation({
    required OrderItemAllocation original,
    required int revision,
    required int quantityToReverse,
    required DateTime recordedAt,
  }) {
    final originalQty = original.quantity.abs();
    final factor = originalQty == 0 ? 1.0 : (quantityToReverse.abs() / originalQty);

    final contraQty = -quantityToReverse.abs();
    final contraGross = -(original.grossSalesPaisa * factor).round();
    final contraDiscount = -(original.allocatedDiscountPaisa * factor).round();
    final contraNet = contraGross - contraDiscount;
    final contraTax = -(original.taxCarveOutPaisa * factor).round();
    final contraBom = original.bomRecipeCostPaisa == null
        ? null
        : -(original.bomRecipeCostPaisa! * factor).round();
    final contraMargin = contraBom == null ? null : (contraNet - contraBom);

    return OrderItemAllocation(
      orderId: original.orderId,
      orderItemId: original.orderItemId,
      revision: revision,
      lineKind: original.lineKind,
      entryType: 'CONTRA',
      menuItemId: original.menuItemId,
      dealId: original.dealId,
      componentMenuItemId: original.componentMenuItemId,
      itemNameSnapshot: original.itemNameSnapshot,
      quantity: contraQty,
      grossSalesPaisa: contraGross,
      allocatedDiscountPaisa: contraDiscount,
      netSalesPaisa: contraNet,
      taxCarveOutPaisa: contraTax,
      bomRecipeCostPaisa: contraBom,
      contributionMarginPaisa: contraMargin,
      recordedAt: recordedAt,
    );
  }
}
