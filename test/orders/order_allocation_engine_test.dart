import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/order_allocation_engine.dart';
import 'package:resturant_sys/core/orders/order_item_allocation.dart';

void main() {
  group('OrderAllocationEngine - ADR-0021 Specification Tests', () {
    test('Example 1: Multi-Item Order with 15% Discount and Zero Residual', () {
      // Order #2001 from ADR-0021
      // Item 1: Beef Burger (Gross PKR 650.00 = 65,000 paisa)
      // Item 2: Loaded Fries (Gross PKR 350.00 = 35,000 paisa)
      // Item 3: Soft Drink (Gross PKR 120.00 = 12,000 paisa)
      // Gross Subtotal = 112,000 paisa
      // 15% Student Discount = floor(112,000 * 0.15) = 16,800 paisa
      final lineGross = [65000, 35000, 12000];
      const totalDiscount = 16800;

      final allocatedDiscounts = OrderAllocationEngine.allocateDiscounts(
        lineGrossPaisa: lineGross,
        totalDiscountPaisa: totalDiscount,
      );

      // Expected base discounts: 9,750, 5,250, 1,800. Sum = 16,800. Residual = 0.
      expect(allocatedDiscounts, [9750, 5250, 1800]);
      expect(allocatedDiscounts.reduce((a, b) => a + b), totalDiscount);

      // Net sales
      final netSales = [
        lineGross[0] - allocatedDiscounts[0],
        lineGross[1] - allocatedDiscounts[1],
        lineGross[2] - allocatedDiscounts[2],
      ];
      expect(netSales, [55250, 29750, 10200]);
      expect(netSales.reduce((a, b) => a + b), 95200);
      expect(netSales.reduce((a, b) => a + b), 112000 - totalDiscount);
    });

    test('Example 2: Flat PKR 100 Discount Generating Non-Zero Rounding Residual', () {
      // Order #2002 from ADR-0021
      // Item 1: Club Sandwich (Gross PKR 450.00 = 45,000 paisa)
      // Item 2: Mineral Water (Gross PKR 70.00 = 7,000 paisa)
      // Item 3: Fresh Juice (Gross PKR 250.00 = 25,000 paisa)
      // Gross Subtotal = 77,000 paisa
      // Flat Voucher Discount = PKR 100.00 = 10,000 paisa
      final lineGross = [45000, 7000, 25000];
      const totalDiscount = 10000;

      final allocatedDiscounts = OrderAllocationEngine.allocateDiscounts(
        lineGrossPaisa: lineGross,
        totalDiscountPaisa: totalDiscount,
      );

      // Proportional:
      // Item 1 raw = 5,844.1558 -> base 5,844
      // Item 2 raw = 909.0909   -> base 909
      // Item 3 raw = 3,246.7532 -> base 3,246
      // Sum = 9,999. Residual = 1 paisa.
      // Residual assigned to Item 1 (largest gross subtotal 45,000 paisa).
      expect(allocatedDiscounts, [5845, 909, 3246]);
      expect(allocatedDiscounts.reduce((a, b) => a + b), totalDiscount);

      final netSales = [
        lineGross[0] - allocatedDiscounts[0],
        lineGross[1] - allocatedDiscounts[1],
        lineGross[2] - allocatedDiscounts[2],
      ];
      // Item 1: 45,000 - 5,845 = 39,155 paisa
      // Item 2:  7,000 -   909 =  6,091 paisa
      // Item 3: 25,000 - 3,246 = 21,754 paisa
      expect(netSales, [39155, 6091, 21754]);
      expect(netSales.reduce((a, b) => a + b), 67000);
      expect(netSales.reduce((a, b) => a + b), 77000 - totalDiscount);
    });

    test('Residual distribution breaks ties by earliest cart index', () {
      // Two identical gross lines with 1 paisa residual
      final lineGross = [50000, 50000];
      const totalDiscount = 3333; // base: 1,666 each (sum 3332), residual 1
      final allocated = OrderAllocationEngine.allocateDiscounts(
        lineGrossPaisa: lineGross,
        totalDiscountPaisa: totalDiscount,
      );
      expect(allocated, [1667, 1666]);
      expect(allocated.reduce((a, b) => a + b), totalDiscount);
    });

    test('Example 3: Deal Expansion with 3 Components and Recipe BOM Costing', () {
      // Order #2003 from ADR-0021
      // Deal selling price = PKR 850.00 = 85,000 paisa
      // Standalone regular menu prices:
      // Component A: Zinger Burger = 55,000 paisa, BOM cost = 22,000 paisa
      // Component B: Regular Fries = 25,000 paisa, BOM cost = 7,000 paisa
      // Component C: Drink         = 15,000 paisa, BOM cost = 4,500 paisa
      // Standalone sum = 95,000 paisa
      const dealSellingPrice = 85000;
      final standalonePrices = [55000, 25000, 15000];
      final bomCosts = [22000, 7000, 4500];

      final expanded = OrderAllocationEngine.expandDealComponents(
        dealGrossPaisa: dealSellingPrice,
        dealAllocatedDiscountPaisa: 0,
        dealTaxCarveOutPaisa: 0,
        componentStandalonePricesPaisa: standalonePrices,
        componentBomCostsPaisa: bomCosts,
      );

      expect(expanded.length, 3);

      // Component A: base = floor(55/95 * 85,000) = 49,210. Residual +1 -> 49,211
      // Component B: base = floor(25/95 * 85,000) = 22,368
      // Component C: base = floor(15/95 * 85,000) = 13,421
      expect(expanded[0].grossSalesPaisa, 49211);
      expect(expanded[1].grossSalesPaisa, 22368);
      expect(expanded[2].grossSalesPaisa, 13421);
      expect(expanded.map((e) => e.grossSalesPaisa).reduce((a, b) => a + b), dealSellingPrice);

      // Net sales match gross since deal discount is 0
      expect(expanded[0].netSalesPaisa, 49211);
      expect(expanded[1].netSalesPaisa, 22368);
      expect(expanded[2].netSalesPaisa, 13421);

      // Component contribution margins:
      // Component A: 49,211 - 22,000 = 27,211 paisa
      // Component B: 22,368 -  7,000 = 15,368 paisa
      // Component C: 13,421 -  4,500 =  8,921 paisa
      expect(expanded[0].contributionMarginPaisa, 27211);
      expect(expanded[1].contributionMarginPaisa, 15368);
      expect(expanded[2].contributionMarginPaisa, 8921);

      // Total Deal Margin: 85,000 - 33,500 = 51,500 paisa
      final totalMargin = expanded.map((e) => e.contributionMarginPaisa!).reduce((a, b) => a + b);
      expect(totalMargin, 51500);
      expect(totalMargin, dealSellingPrice - bomCosts.reduce((a, b) => a + b));
    });

    test('Deal with order-level discount allocates discount to deal then expands net across components', () {
      const dealSellingPrice = 85000;
      const dealDiscount = 8500; // 10% discount on deal
      final standalonePrices = [55000, 25000, 15000];
      final bomCosts = [22000, 7000, 4500];

      final expanded = OrderAllocationEngine.expandDealComponents(
        dealGrossPaisa: dealSellingPrice,
        dealAllocatedDiscountPaisa: dealDiscount,
        dealTaxCarveOutPaisa: 0,
        componentStandalonePricesPaisa: standalonePrices,
        componentBomCostsPaisa: bomCosts,
      );

      // Gross shares sum to 85,000
      expect(expanded.map((e) => e.grossSalesPaisa).reduce((a, b) => a + b), dealSellingPrice);
      // Discount shares sum to 8,500
      expect(expanded.map((e) => e.allocatedDiscountPaisa).reduce((a, b) => a + b), dealDiscount);
      // Net sales sum to 76,500
      expect(expanded.map((e) => e.netSalesPaisa).reduce((a, b) => a + b), dealSellingPrice - dealDiscount);
    });

    test('Tax carve-out allocates proportionally across taxable lines with zero leakage', () {
      final lineNetSales = [55250, 29750, 10200];
      final isTaxable = [true, true, false]; // Third item is non-taxable
      const totalTax = 14000; // 140 PKR tax

      final taxes = OrderAllocationEngine.allocateTaxCarveOut(
        lineNetSalesPaisa: lineNetSales,
        isTaxable: isTaxable,
        totalTaxPaisa: totalTax,
      );

      expect(taxes[2], 0, reason: 'Non-taxable item receives zero tax carve-out');
      expect(taxes[0] + taxes[1] + taxes[2], totalTax, reason: 'Zero tax leakage');
      expect(taxes[0] >= taxes[1], isTrue, reason: 'Higher net sales gets higher tax share');
    });

    test('Contra-allocation negates all original values', () {
      final original = OrderItemAllocation(
        id: 1,
        orderId: 2004,
        orderItemId: 10,
        revision: 0,
        lineKind: 'ITEM',
        entryType: 'SALE',
        menuItemId: 5,
        dealId: null,
        componentMenuItemId: null,
        itemNameSnapshot: 'Pizza',
        quantity: 2,
        grossSalesPaisa: 200000,
        allocatedDiscountPaisa: 20000,
        netSalesPaisa: 180000,
        taxCarveOutPaisa: 0,
        bomRecipeCostPaisa: 80000,
        contributionMarginPaisa: 100000,
        recordedAt: DateTime.parse('2026-10-30T12:00:00Z'),
      );

      final contra = OrderAllocationEngine.createContraAllocation(
        original: original,
        revision: 1,
        quantityToReverse: 1,
        recordedAt: DateTime.parse('2026-10-30T12:15:00Z'),
      );

      expect(contra.orderId, 2004);
      expect(contra.revision, 1);
      expect(contra.entryType, 'CONTRA');
      expect(contra.quantity, -1);
      expect(contra.grossSalesPaisa, -100000);
      expect(contra.allocatedDiscountPaisa, -10000);
      expect(contra.netSalesPaisa, -90000);
      expect(contra.bomRecipeCostPaisa, -40000);
      expect(contra.contributionMarginPaisa, -50000);
    });
  });
}
