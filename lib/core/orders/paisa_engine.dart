
/// Core 64-bit integer paisa financial engine.
///
/// Implements exact money calculation (Rs. 1.00 = 100 paisa), mathematical
/// half-up physical cash rounding, tax carve-outs, and split tender balance allocation.
abstract final class PaisaEngine {
  /// Converts rupees (floating point / decimal) to exact integer paisa.
  static int rupeesToPaisa(num rupees) {
    return (rupees * 100).round();
  }

  /// Converts integer paisa to rupees as double for display or legacy compatibility.
  static double paisaToRupees(int paisa) {
    return paisa / 100.0;
  }

  /// Formats integer paisa to standard Pakistani Rupee currency notation.
  static String formatRupees(int paisa, {bool includeSymbol = true}) {
    final rupees = paisa / 100.0;
    final formatted = rupees.toStringAsFixed(2);
    return includeSymbol ? 'Rs. $formatted' : formatted;
  }

  /// Rounds physical cash payable to the nearest whole rupee (100 paisa)
  /// using exact mathematical half-up arithmetic.
  ///
  /// Formula: floor((cash_due + 50) / 100) * 100
  ///
  /// Examples:
  /// - 61,650 paisa (Rs. 616.50) -> 61,700 paisa (Rs. 617.00)
  /// - 61,649 paisa (Rs. 616.49) -> 61,600 paisa (Rs. 616.00)
  /// - 61,625 paisa (Rs. 616.25) -> 61,600 paisa (Rs. 616.00)
  /// - 61,600 paisa (Rs. 616.00) -> 61,600 paisa (Rs. 616.00)
  static int roundCashPaisa(int cashDueExactPaisa) {
    return ((cashDueExactPaisa + 50) / 100.0).floor() * 100;
  }

  /// Computes the rounding variance between exact cash due and rounded cash due.
  ///
  /// Formula: rounded_cash_due_paisa - cash_due_exact_paisa
  ///
  /// A positive delta represents rounding gain; negative represents rounding discount.
  static int calculateCashRoundingDelta({
    required int exactDuePaisa,
    required int roundedCashPaisa,
  }) {
    return roundedCashPaisa - exactDuePaisa;
  }

  /// Digital payments (JazzCash, Easypaisa, Raast, Card) remain exact without cash rounding.
  static int calculateDigitalTenderDelta(int digitalPaisa) {
    return 0;
  }

  /// Allocates split payments by deducting exact valid non-cash tenders from total invoice,
  /// then rounding the final balancing physical cash leg exactly once.
  static SplitTenderResult calculateSplitTender({
    required int totalInvoicePaisa,
    required int digitalTenderPaisa,
  }) {
    final exactCashDuePaisa = totalInvoicePaisa - digitalTenderPaisa;
    final roundedCashDuePaisa = roundCashPaisa(exactCashDuePaisa);
    final cashRoundingDeltaPaisa = calculateCashRoundingDelta(
      exactDuePaisa: exactCashDuePaisa,
      roundedCashPaisa: roundedCashDuePaisa,
    );
    final totalCollectedPaisa = digitalTenderPaisa + roundedCashDuePaisa;

    return SplitTenderResult(
      exactCashDuePaisa: exactCashDuePaisa,
      roundedCashDuePaisa: roundedCashDuePaisa,
      cashRoundingDeltaPaisa: cashRoundingDeltaPaisa,
      digitalTenderPaisa: digitalTenderPaisa,
      totalCollectedPaisa: totalCollectedPaisa,
    );
  }

  /// Computes sales tax carve-out from tax-inclusive catalog shelf prices.
  ///
  /// In tax-inclusive pricing, the catalog price already includes tax.
  /// Formula: tax_included = round(totalPaisa * taxRateBps / (10000 + taxRateBps))
  /// Taxable base = totalPaisa - tax_included
  static TaxCarveOutResult calculateTaxCarveOut({
    required int totalPaisa,
    required int taxRateBps,
  }) {
    if (taxRateBps <= 0 || totalPaisa <= 0) {
      return TaxCarveOutResult(
        taxPaisa: 0,
        taxableBasePaisa: totalPaisa,
      );
    }

    final denominator = 10000 + taxRateBps;
    final taxPaisa = ((totalPaisa * taxRateBps) + (denominator ~/ 2)) ~/ denominator;
    final taxableBasePaisa = totalPaisa - taxPaisa;

    return TaxCarveOutResult(
      taxPaisa: taxPaisa,
      taxableBasePaisa: taxableBasePaisa,
    );
  }

  /// Allocates an integer amount of paisa proportionally across weights or parts
  /// using integer floor division, distributing any remainder paisa to the largest bucket.
  ///
  /// Guarantees that the sum of allocated parts exactly equals [totalPaisa] (zero lost or duplicate paisa).
  static List<int> allocateProportionally({
    required int totalPaisa,
    required List<int> parts,
  }) {
    if (parts.isEmpty) return const [];
    if (totalPaisa <= 0) return List.filled(parts.length, 0);

    final totalWeight = parts.fold<int>(0, (sum, w) => sum + (w > 0 ? w : 0));
    if (totalWeight <= 0) {
      final base = totalPaisa ~/ parts.length;
      final rem = totalPaisa % parts.length;
      final result = List.filled(parts.length, base);
      result[0] += rem;
      return result;
    }

    final allocated = List<int>.filled(parts.length, 0);
    var allocatedSum = 0;
    var maxWeight = -1;
    var maxIndex = 0;

    for (var i = 0; i < parts.length; i++) {
      final weight = parts[i] > 0 ? parts[i] : 0;
      if (weight > maxWeight) {
        maxWeight = weight;
        maxIndex = i;
      }
      final share = (totalPaisa * weight) ~/ totalWeight;
      allocated[i] = share;
      allocatedSum += share;
    }

    final remainder = totalPaisa - allocatedSum;
    if (remainder > 0 && parts.isNotEmpty) {
      allocated[maxIndex] += remainder;
    }

    return allocated;
  }
}

/// Standalone proportional allocation helper adhering to integer floor division and largest-bucket remainder distribution.
List<int> allocatePaisaProportionally(int totalPaisa, List<int> parts) =>
    PaisaEngine.allocateProportionally(totalPaisa: totalPaisa, parts: parts);

/// Result of a split-tender calculation.
class SplitTenderResult {
  const SplitTenderResult({
    required this.exactCashDuePaisa,
    required this.roundedCashDuePaisa,
    required this.cashRoundingDeltaPaisa,
    required this.digitalTenderPaisa,
    required this.totalCollectedPaisa,
  });

  final int exactCashDuePaisa;
  final int roundedCashDuePaisa;
  final int cashRoundingDeltaPaisa;
  final int digitalTenderPaisa;
  final int totalCollectedPaisa;
}

/// Result of an inclusive tax carve-out calculation.
class TaxCarveOutResult {
  const TaxCarveOutResult({
    required this.taxPaisa,
    required this.taxableBasePaisa,
  });

  final int taxPaisa;
  final int taxableBasePaisa;
}
