import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/paisa_engine.dart';

void main() {
  group('PaisaEngine Core Arithmetic & Cash Rounding Seam', () {
    test('converts decimal rupees to integer paisa without floating point drift', () {
      expect(PaisaEngine.rupeesToPaisa(616.25), equals(61625));
      expect(PaisaEngine.rupeesToPaisa(616.50), equals(61650));
      expect(PaisaEngine.rupeesToPaisa(500.0), equals(50000));
      expect(PaisaEngine.rupeesToPaisa(0.0), equals(0));
      expect(PaisaEngine.rupeesToPaisa(0.99), equals(99));
    });

    test('converts integer paisa to rupees accurately', () {
      expect(PaisaEngine.paisaToRupees(61625), equals(616.25));
      expect(PaisaEngine.paisaToRupees(61600), equals(616.0));
      expect(PaisaEngine.paisaToRupees(50), equals(0.50));
      expect(PaisaEngine.paisaToRupees(0), equals(0.0));
    });

    test('formats paisa to formatted currency string with and without symbol', () {
      expect(PaisaEngine.formatRupees(61625), equals('Rs. 616.25'));
      expect(PaisaEngine.formatRupees(61600), equals('Rs. 616.00'));
      expect(PaisaEngine.formatRupees(61600, includeSymbol: false), equals('616.00'));
    });

    group('roundCashPaisa (Half-Up Cash Rounding to Rupee)', () {
      test('rounds 50 paisa and above up to the next rupee (+50 delta)', () {
        // 61,650 paisa (Rs. 616.50) -> 61,700 paisa (Rs. 617.00)
        final rounded = PaisaEngine.roundCashPaisa(61650);
        expect(rounded, equals(61700));

        final delta = PaisaEngine.calculateCashRoundingDelta(
          exactDuePaisa: 61650,
          roundedCashPaisa: rounded,
        );
        expect(delta, equals(50));
      });

      test('rounds 49 paisa and below down to the whole rupee (-49 delta)', () {
        // 61,649 paisa (Rs. 616.49) -> 61,600 paisa (Rs. 616.00)
        final rounded = PaisaEngine.roundCashPaisa(61649);
        expect(rounded, equals(61600));

        final delta = PaisaEngine.calculateCashRoundingDelta(
          exactDuePaisa: 61649,
          roundedCashPaisa: rounded,
        );
        expect(delta, equals(-49));
      });

      test('rounds 25 paisa down to the whole rupee (-25 delta)', () {
        // 61,625 paisa (Rs. 616.25) -> 61,600 paisa (Rs. 616.00)
        final rounded = PaisaEngine.roundCashPaisa(61625);
        expect(rounded, equals(61600));

        final delta = PaisaEngine.calculateCashRoundingDelta(
          exactDuePaisa: 61625,
          roundedCashPaisa: rounded,
        );
        expect(delta, equals(-25));
      });

      test('leaves exact whole rupees unchanged with zero delta', () {
        // 61,600 paisa -> 61,600 paisa
        final rounded = PaisaEngine.roundCashPaisa(61600);
        expect(rounded, equals(61600));

        final delta = PaisaEngine.calculateCashRoundingDelta(
          exactDuePaisa: 61600,
          roundedCashPaisa: rounded,
        );
        expect(delta, equals(0));
      });

      test('safely handles zero and negative cash due', () {
        expect(PaisaEngine.roundCashPaisa(0), equals(0));
        expect(PaisaEngine.roundCashPaisa(-500), equals(0));
      });
    });

    group('Split Tender & Digital Payments', () {
      test('preserves digital payment exactness without rounding', () {
        // Digital tender exact 61,625 paisa -> rounding is 0
        final digitalDelta = PaisaEngine.calculateDigitalTenderDelta(61625);
        expect(digitalDelta, equals(0));
      });

      test('calculates split tender with exact digital deduction and single cash leg rounding', () {
        // Total Rs. 616.25 (61625 paisa) - Rs. 200.00 digital (20000 paisa)
        // Exact cash remaining = 41625 paisa -> rounded cash = 41600 paisa (-25 delta)
        final split = PaisaEngine.calculateSplitTender(
          totalInvoicePaisa: 61625,
          digitalTenderPaisa: 20000,
        );

        expect(split.exactCashDuePaisa, equals(41625));
        expect(split.roundedCashDuePaisa, equals(41600));
        expect(split.cashRoundingDeltaPaisa, equals(-25));
        expect(split.digitalTenderPaisa, equals(20000));
        expect(split.totalCollectedPaisa, equals(61600)); // 20000 + 41600
      });

      test('calculates split tender when digital payment leaves whole-rupee cash remainder', () {
        // Total Rs. 616.25 (61625) - Rs. 200.25 digital (20025) = Rs. 416.00 cash (41600)
        final split = PaisaEngine.calculateSplitTender(
          totalInvoicePaisa: 61625,
          digitalTenderPaisa: 20025,
        );

        expect(split.exactCashDuePaisa, equals(41600));
        expect(split.roundedCashDuePaisa, equals(41600));
        expect(split.cashRoundingDeltaPaisa, equals(0));
        expect(split.digitalTenderPaisa, equals(20025));
        expect(split.totalCollectedPaisa, equals(61625));
      });
    });

    group('Tax Carve-Out (Inclusive Pricing)', () {
      test('computes 0% default tax carve-out correctly', () {
        final result = PaisaEngine.calculateTaxCarveOut(
          totalPaisa: 50000,
          taxRateBps: 0,
        );

        expect(result.taxPaisa, equals(0));
        expect(result.taxableBasePaisa, equals(50000));
      });

      test('computes 13% tax carve-out from Rs. 500 catalog item without inflating shelf price', () {
        // Rs. 500 (50,000 paisa) at 1300 bps (13%)
        // Tax included = round(50000 * 1300 / 11300) = round(5752.21) = 5752 paisa
        // Taxable base = 50000 - 5752 = 44248 paisa
        final result = PaisaEngine.calculateTaxCarveOut(
          totalPaisa: 50000,
          taxRateBps: 1300,
        );

        expect(result.taxPaisa, equals(5752));
        expect(result.taxableBasePaisa, equals(44248));
        expect(result.taxPaisa + result.taxableBasePaisa, equals(50000));
      });
    });
  });
}
