import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/order_void.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OrderAndCheckoutController Integration Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late CatalogAndRecipeController catalogController;
    late ShiftAndCashController shiftController;
    late OrderAndCheckoutController orderController;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('order_controller_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}test_order.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      catalogController = CatalogAndRecipeController(database: db);
      shiftController = ShiftAndCashController(database: db);
      orderController = OrderAndCheckoutController(database: db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Walk-in cash rounds half-up and records the rounding variance', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 0);
      final category = await catalogController.createCategory(name: 'Rounding', displayOrder: 1, colorHex: '#FFFFFF');
      final item = await catalogController.createMenuItem(categoryId: category.id, name: 'Tea', basePrice: 100.50);
      await publishFixtures(catalogController);
      final result = await orderController.checkoutOrder(
        businessDayId: day.id, shiftId: shift.id, cashierId: 2,
        diningType: DiningType.dineIn, items: [CartItem(menuItem: item)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 101)],
      );
      expect(result.order.cashRoundingPaisa, 50);
      expect((await orderController.getOrder(result.order.id)).cashRoundingPaisa, 50);
    });

    test('Retrying a checkout command returns the same order and consumes stock once', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 0);
      final category = await catalogController.createCategory(name: 'Retry', displayOrder: 1, colorHex: '#FFFFFF');
      final item = await catalogController.createMenuItem(categoryId: category.id, name: 'Retry tea', basePrice: 100);
      await publishFixtures(catalogController);
      Future<CheckoutResult> submit() => orderController.checkoutOrder(
        commandId: 'checkout-retry-1', businessDayId: day.id, shiftId: shift.id, cashierId: 2,
        diningType: DiningType.dineIn, items: [CartItem(menuItem: item)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)],
      );
      final first = await submit();
      final stocks = await catalogController.getRawIngredients();
      final retry = await submit();
      expect(retry.order.id, first.order.id);
      expect(await orderController.getNextTokenNumber(day.id), 2);
      expect((await catalogController.getRawIngredients()).map((i) => i.currentStock), stocks.map((i) => i.currentStock));
    });

    test('Digital manual tenders retain exact paisa without cash rounding', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 0);
      final category = await catalogController.createCategory(name: 'Digital', displayOrder: 1, colorHex: '#FFFFFF');
      final item = await catalogController.createMenuItem(categoryId: category.id, name: 'Digital tea', basePrice: 100.49);
      await publishFixtures(catalogController);
      for (final method in [PaymentMethod.jazzCash, PaymentMethod.easypaisa, PaymentMethod.bankTransfer, PaymentMethod.card, PaymentMethod.raast]) {
        final result = await orderController.checkoutOrder(
          businessDayId: day.id, shiftId: shift.id, cashierId: 2,
          diningType: DiningType.dineIn, items: [CartItem(menuItem: item)],
          payments: [PaymentTender(method: method, amountTendered: 100.49, referenceCode: 'manual-reference')],
        );
        final saved = await orderController.getOrder(result.order.id);
        expect(saved.cashRoundingPaisa, 0);
        expect(saved.payments.single.amountTenderedPaisa, 10049);
        expect(saved.payments.single.paymentMethod, method);
      }
    });

    test('Daily sequential token increments (#01, #02...) and resets at new Business Day', () async {
      // 1. Open Business Day 1 & Shift
      final day1 = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift1 = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      // Create a category and item
      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final burger = await catalogController.createMenuItem(
        categoryId: cat.id,
        name: 'Zinger',
        basePrice: 500.0,
      );

      // Check initial token
      final token1Num = await orderController.getNextTokenNumber(day1.id);
      expect(token1Num, equals(1));

      // Checkout Order 1 in Day 1
      final cart1 = [CartItem(menuItem: burger, quantity: 1)];
      await publishFixtures(catalogController);
      final result1 = await orderController.checkoutOrder(
        businessDayId: day1.id,
        shiftId: shift1.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: cart1,
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 500.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(result1.order.tokenNumber, equals(1));
      expect(result1.order.tokenDisplay, equals('#01'));

      // Checkout Order 2 in Day 1
      final cart2 = [CartItem(menuItem: burger, quantity: 2)];
      await publishFixtures(catalogController);
      final result2 = await orderController.checkoutOrder(
        businessDayId: day1.id,
        shiftId: shift1.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: cart2,
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 1000.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(result2.order.tokenNumber, equals(2));
      expect(result2.order.tokenDisplay, equals('#02'));

      // Close shift 1 and day 1
      await shiftController.closeShift(shiftId: shift1.id, staffId: shift1.staffId, countedCash: 2500.0);
      await shiftController.closeBusinessDay(closedByStaffId: 1);

      // Open Business Day 2 & Shift 2
      final day2 = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift2 = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      // Next token in Day 2 MUST reset to 1
      final tokenDay2 = await orderController.getNextTokenNumber(day2.id);
      expect(tokenDay2, equals(1));

      await publishFixtures(catalogController);
      final result3 = await orderController.checkoutOrder(
        businessDayId: day2.id,
        shiftId: shift2.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 500.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(result3.order.tokenNumber, equals(1));
      expect(result3.order.tokenDisplay, equals('#01'));
    });

    test('Atomic checkout commits orders, items, and multi-tender split payments (Cash + Raast)', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final cat = await catalogController.createCategory(name: 'Mains', displayOrder: 1, colorHex: '#00FF00');
      final item = await catalogController.createMenuItem(
        categoryId: cat.id,
        name: 'Crispy Box',
        basePrice: 1200.0,
      );

      final discount = await catalogController.createDiscountPreset(
        name: 'Staff 10%',
        type: DiscountType.percentage,
        value: 10.0,
      );

      // Cart: 1 Crispy Box (1200.0) with 10% discount -> discount = 120.0, grand total = 1080.0
      final cart = [CartItem(menuItem: item, quantity: 1)];
      final totals = orderController.calculateCartTotals(items: cart, discount: discount);
      expect(totals.subtotal, equals(1200.0));
      expect(totals.discountAmount, equals(120.0));
      expect(totals.grandTotal, equals(1080.0));

      // Settle via Split Tender: 500 Cash, 580 Raast QR
      await publishFixtures(catalogController);
      final result = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: cart,
        discount: discount,
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 500.0,
            changeReturned: 0.0,
          ),
          const PaymentTender(
            method: PaymentMethod.raast,
            amountTendered: 580.0,
            referenceCode: 'RAAST-TXN-9988',
          ),
        ],
      );

      expect(result.order.grandTotal, equals(1080.0));
      expect(result.order.discountAmount, equals(120.0));
      expect(result.order.discountId, equals(discount.id));
      expect(result.order.items.length, equals(1));
      expect(result.order.payments.length, equals(2));

      // Verify payments in database
      final payments = await orderController.getOrderPayments(result.order.id);
      expect(payments.length, equals(2));
      expect(payments[0].paymentMethod, equals(PaymentMethod.cash));
      expect(payments[0].amountTendered, equals(500.0));
      expect(payments[1].paymentMethod, equals(PaymentMethod.raast));
      expect(payments[1].amountTendered, equals(580.0));
      expect(payments[1].referenceCode, equals('RAAST-TXN-9988'));
    });

    test('Soft BOM inventory deduction allows checkout on negative stock and flags low-stock warnings', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#0000FF');
      final burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Beef Burger', basePrice: 600.0);

      // Ingredient with 2 patties in stock, low stock threshold = 5
      final patty = await catalogController.createRawIngredient(
        name: 'Beef Patty',
        storageUnit: StorageUnit.count,
        currentStock: 2.0,
        lowStockThreshold: 5.0,
      );

      // Recipe: 1 patty per burger
      await catalogController.setRecipeForMenuItem(
        menuItemId: burger.id,
        items: [(rawIngredientId: patty.id, quantity: 1.0)],
      );

      // Order 5 burgers: needs 5 patties, but stock is only 2!
      // Soft deduction policy: does NOT throw, stock becomes 2 - 5 = -3!
      final cart = [CartItem(menuItem: burger, quantity: 5)];
      await publishFixtures(catalogController);
      final result = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: cart,
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 3000.0,
            changeReturned: 0.0,
          ),
        ],
      );

      expect(result.order.tokenNumber, equals(1));

      // Verify stock in database is now -3.0
      final updatedPatty = await catalogController.getRawIngredient(patty.id);
      expect(updatedPatty.currentStock, equals(-3.0));
      expect(updatedPatty.isLowStock, isTrue);

      // Verify low stock warning was returned
      expect(result.lowStockWarnings.any((w) => w.ingredientId == patty.id), isTrue);
    });

    test('3-Tier Deal decomposition deducts bundled recipe ingredients and handles upgrades', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final catBurgers = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final catDrinks = await catalogController.createCategory(name: 'Drinks', displayOrder: 2, colorHex: '#0000FF');

      final burger = await catalogController.createMenuItem(categoryId: catBurgers.id, name: 'Zinger', basePrice: 500.0);
      final colaRegular = await catalogController.createMenuItem(categoryId: catDrinks.id, name: 'Cola Reg', basePrice: 120.0);
      final colaLarge = await catalogController.createMenuItem(categoryId: catDrinks.id, name: 'Cola Lrg', basePrice: 180.0);

      // Ingredients
      final chicken = await catalogController.createRawIngredient(
        name: 'Fried Chicken Fillet',
        storageUnit: StorageUnit.count,
        currentStock: 20.0,
      );
      final colaSyrup = await catalogController.createRawIngredient(
        name: 'Cola Syrup',
        storageUnit: StorageUnit.ml,
        currentStock: 1000.0,
      );

      // Recipes
      await catalogController.setRecipeForMenuItem(
        menuItemId: burger.id,
        items: [(rawIngredientId: chicken.id, quantity: 1.0)],
      );
      await catalogController.setRecipeForMenuItem(
        menuItemId: colaRegular.id,
        items: [(rawIngredientId: colaSyrup.id, quantity: 30.0)],
      );
      await catalogController.setRecipeForMenuItem(
        menuItemId: colaLarge.id,
        items: [(rawIngredientId: colaSyrup.id, quantity: 50.0)],
      );

      // Create Deal: "Zinger Combo" base price 600
      await publishFixtures(catalogController);
      final deal = await orderController.createDeal(
        name: 'Zinger Combo',
        basePrice: 600.0,
        items: [
          DealItemDraft(
            groupName: 'Burger',
            defaultMenuItemId: burger.id,
          ),
          DealItemDraft(
            groupName: 'Drink',
            defaultMenuItemId: colaRegular.id,
            options: [
              DealOptionDraft(menuItemId: colaRegular.id, isDefault: true, upgradePrice: 0.0),
              DealOptionDraft(menuItemId: colaLarge.id, isDefault: false, upgradePrice: 50.0),
            ],
          ),
        ],
      );

      // Cashier selects Deal with Large Cola upgrade (+50.0) -> unit price = 600 + 50 = 650.0
      final cart = [
        CartItem(
          deal: deal,
          quantity: 2,
          selectedDealChoices: [
            SelectedDealChoice(
              dealItemId: deal.items[0].id,
              groupName: 'Burger',
              menuItemId: burger.id,
              menuItemName: burger.name,
              upgradePrice: 0.0,
            ),
            SelectedDealChoice(
              dealItemId: deal.items[1].id,
              groupName: 'Drink',
              menuItemId: colaLarge.id,
              menuItemName: colaLarge.name,
              upgradePrice: 50.0,
            ),
          ],
        ),
      ];

      expect(cart.first.unitPrice, equals(650.0));
      expect(cart.first.totalPrice, equals(1300.0));

      // Checkout
      await publishFixtures(catalogController);
      final result = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: cart,
        payments: [
          const PaymentTender(
            method: PaymentMethod.card,
            amountTendered: 1300.0,
          ),
        ],
      );

      expect(result.order.grandTotal, equals(1300.0));

      // Verify inventory was decomposed:
      // 2 deals = 2 chickens deducted (20 - 2 = 18)
      // 2 large colas = 2 * 50ml = 100ml cola syrup deducted (1000 - 100 = 900)
      final updatedChicken = await catalogController.getRawIngredient(chicken.id);
      expect(updatedChicken.currentStock, equals(18.0));

      final updatedSyrup = await catalogController.getRawIngredient(colaSyrup.id);
      expect(updatedSyrup.currentStock, equals(900.0));
    });

    test('Modifiers: +Add-on increases price & BOM, -Removal maintains 0 price delta and 0g BOM', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Deluxe Burger', basePrice: 500.0);

      final beef = await catalogController.createRawIngredient(name: 'Beef', storageUnit: StorageUnit.count, currentStock: 10.0);
      final cheese = await catalogController.createRawIngredient(name: 'Cheese', storageUnit: StorageUnit.count, currentStock: 20.0);
      final mayo = await catalogController.createRawIngredient(name: 'Mayo Sauce', storageUnit: StorageUnit.g, currentStock: 500.0);

      // Recipe: 1 beef, 20g mayo
      await catalogController.setRecipeForMenuItem(
        menuItemId: burger.id,
        items: [
          (rawIngredientId: beef.id, quantity: 1.0),
          (rawIngredientId: mayo.id, quantity: 20.0),
        ],
      );

      // Modifiers:
      // +Extra Cheese: +Rs 60, +1 cheese
      final addCheese = await catalogController.createModifier(
        menuItemId: burger.id,
        name: '+Extra Cheese',
        priceDelta: 60.0,
        rawIngredientId: cheese.id,
        ingredientQtyDelta: 1.0,
      );

      // No Mayo: Rs 0, 0g BOM (cancels mayo deduction)
      final noMayo = await catalogController.createModifier(
        menuItemId: burger.id,
        name: 'No Mayo',
        priceDelta: 0.0,
        rawIngredientId: mayo.id,
        ingredientQtyDelta: -20.0,
      );

      final cart = [
        CartItem(
          menuItem: burger,
          quantity: 1,
          selectedModifiers: [addCheese, noMayo],
        ),
      ];

      // Base: 500 + 60 = 560
      expect(cart.first.unitPrice, equals(560.0));

      await publishFixtures(catalogController);
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: cart,
        payments: [
          const PaymentTender(
            method: PaymentMethod.cash,
            amountTendered: 560.0,
            changeReturned: 0.0,
          ),
        ],
      );

      // Inventory check:
      // Beef: 10 - 1 = 9
      // Cheese: 20 - 1 = 19
      // Mayo: No Mayo selected -> 0g deducted! Stock stays 500.0!
      final updatedBeef = await catalogController.getRawIngredient(beef.id);
      expect(updatedBeef.currentStock, equals(9.0));

      final updatedCheese = await catalogController.getRawIngredient(cheese.id);
      expect(updatedCheese.currentStock, equals(19.0));

      final updatedMayo = await catalogController.getRawIngredient(mayo.id);
      expect(updatedMayo.currentStock, equals(500.0));
    });

    test('Dining Type Takeaway and Delivery automatically deducts packaging material from inventory', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Burger', basePrice: 400.0);

      // Packaging box ingredient
      final packaging = await catalogController.createRawIngredient(
        name: 'Takeaway Packaging Box',
        storageUnit: StorageUnit.count,
        currentStock: 100.0,
      );

      // 1. Order Dine-In: packaging must NOT be deducted
      await publishFixtures(catalogController);
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: burger, quantity: 2)],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 800.0),
        ],
      );

      var checkPackaging = await catalogController.getRawIngredient(packaging.id);
      expect(checkPackaging.currentStock, equals(100.0));

      // 2. Order Takeaway: packaging material IS automatically deducted (1 per order)
      await publishFixtures(catalogController);
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.takeaway,
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 400.0),
        ],
      );

      checkPackaging = await catalogController.getRawIngredient(packaging.id);
      expect(checkPackaging.currentStock, equals(99.0));

      final area = await DeliveryController(database: db).saveArea(staffId: 1, name: 'Local', code: 'LOCAL', deliveryFeePaisa: 0);
      // 3. Order Delivery: packaging material IS automatically deducted
      await publishFixtures(catalogController);
      await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.delivery,
        delivery: DeliveryDetails(areaId: area.id, quotedFeePaisa: 0, phone: '03001234567', fullAddress: 'House 1'),
        items: [CartItem(menuItem: burger, quantity: 1)],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 400.0),
        ],
      );

      checkPackaging = await catalogController.getRawIngredient(packaging.id);
      expect(checkPackaging.currentStock, equals(98.0));
    });

    test('voidOrder marks order VOIDED, records immutable audit entry, and accurately reverses BOM & packaging stock', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      // Create ingredients
      final beef = await catalogController.createRawIngredient(
        name: 'Beef Patty',
        storageUnit: StorageUnit.count,
        currentStock: 50.0,
      );
      final cheese = await catalogController.createRawIngredient(
        name: 'Cheese Slice',
        storageUnit: StorageUnit.count,
        currentStock: 40.0,
      );
      final packaging = await catalogController.createRawIngredient(
        name: 'Takeaway Packaging Box',
        storageUnit: StorageUnit.count,
        currentStock: 30.0,
      );

      final cat = await catalogController.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FF0000');
      final burger = await catalogController.createMenuItem(categoryId: cat.id, name: 'Double Cheese', basePrice: 600.0);

      // Recipe: 2 beef patties, 1 cheese slice
      await catalogController.addOrUpdateRecipeItem(menuItemId: burger.id, rawIngredientId: beef.id, quantity: 2.0);
      await catalogController.addOrUpdateRecipeItem(menuItemId: burger.id, rawIngredientId: cheese.id, quantity: 1.0);

      // Modifier: +1 extra cheese slice
      final extraCheeseMod = await catalogController.createModifier(
        menuItemId: burger.id,
        name: 'Extra Cheese',
        priceDelta: 50.0,
        rawIngredientId: cheese.id,
        ingredientQtyDelta: 1.0,
      );

      // Checkout Takeaway: 2 Double Cheese with 1 Extra Cheese
      // Expected deduction:
      // Beef: 2 burgers * 2 patties = 4 patties
      // Cheese: 2 burgers * 1 cheese + 1 extra cheese = 3 cheese slices
      // Packaging: 1 box (takeaway)
      final cartItem = CartItem(
        menuItem: burger,
        quantity: 2,
        selectedModifiers: [extraCheeseMod],
      );

      await publishFixtures(catalogController);
      final checkoutRes = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.takeaway,
        items: [cartItem],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 1300.0),
        ],
      );

      final orderId = checkoutRes.order.id;

      // Verify stock post-checkout
      var curBeef = await catalogController.getRawIngredient(beef.id);
      expect(curBeef.currentStock, equals(46.0)); // 50 - 4 = 46

      var curCheese = await catalogController.getRawIngredient(cheese.id);
      expect(curCheese.currentStock, equals(36.0)); // 40 - 4 = 36 (2 burgers * 2 cheese each)

      var curPackaging = await catalogController.getRawIngredient(packaging.id);
      expect(curPackaging.currentStock, equals(29.0)); // 30 - 1 = 29

      // Void Order with Supervisor authorization
      final voidResult = await orderController.voidOrder(
        orderId: orderId,
        supervisorStaffId: 1,
        cashierStaffId: 2,
        reason: VoidReason.customerCancelled,
      );

      // Assert audit record
      expect(voidResult.orderId, equals(orderId));
      expect(voidResult.voidedBySupervisorId, equals(1));
      expect(voidResult.cashierId, equals(2));
      expect(voidResult.reason, equals('Customer Cancelled'));
      expect(voidResult.supervisorName, equals('Supervisor'));
      expect(voidResult.cashierName, equals('Counter Cashier'));

      // Assert order is marked VOIDED in database
      final updatedOrder = await orderController.getOrder(orderId);
      expect(updatedOrder.isVoided, isTrue);
      expect(updatedOrder.paymentStatus, equals('VOIDED'));

      // Assert persisted audit record matches
      final persistedAudit = await orderController.getOrderVoid(orderId);
      expect(persistedAudit, isNotNull);
      expect(persistedAudit!.reason, equals('Customer Cancelled'));
      expect(persistedAudit.voidedBySupervisorId, equals(1));

      // Assert BOM and Packaging inventory deductions are fully restored!
      curBeef = await catalogController.getRawIngredient(beef.id);
      expect(curBeef.currentStock, equals(50.0)); // Restored to 50!

      curCheese = await catalogController.getRawIngredient(cheese.id);
      expect(curCheese.currentStock, equals(40.0)); // Restored to 40!

      curPackaging = await catalogController.getRawIngredient(packaging.id);
      expect(curPackaging.currentStock, equals(30.0)); // Restored to 30!
    });

    test('voidOrder prevents double-voiding and non-existent orders', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final cat = await catalogController.createCategory(name: 'Drinks', displayOrder: 1, colorHex: '#0000FF');
      final drink = await catalogController.createMenuItem(categoryId: cat.id, name: 'Cola', basePrice: 100.0);

      await publishFixtures(catalogController);
      final checkoutRes = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: drink, quantity: 1)],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 100.0),
        ],
      );

      // First void succeeds
      await orderController.voidOrder(
        orderId: checkoutRes.order.id,
        supervisorStaffId: 1,
        cashierStaffId: 2,
        reason: VoidReason.cashierMistake,
      );

      // Second void fails
      expect(
        () => orderController.voidOrder(
          orderId: checkoutRes.order.id,
          supervisorStaffId: 1,
          cashierStaffId: 2,
          reason: VoidReason.cashierMistake,
        ),
        throwsStateError,
      );

      // Non-existent order fails
      expect(
        () => orderController.voidOrder(
          orderId: 999999,
          supervisorStaffId: 1,
          cashierStaffId: 2,
          reason: VoidReason.paymentDeclined,
        ),
        throwsStateError,
      );
    });

    test('voidOrder validates mandatory cancellation reasons', () async {
      final day = await shiftController.openBusinessDay(openedByStaffId: 1);
      final shift = await shiftController.openShift(staffId: 2, openingFloat: 1000.0);

      final cat = await catalogController.createCategory(name: 'Sides', displayOrder: 1, colorHex: '#FFFF00');
      final fries = await catalogController.createMenuItem(categoryId: cat.id, name: 'Fries', basePrice: 200.0);

      await publishFixtures(catalogController);
      final checkoutRes = await orderController.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [CartItem(menuItem: fries, quantity: 1)],
        payments: [
          const PaymentTender(method: PaymentMethod.cash, amountTendered: 200.0),
        ],
      );

      // Arbitrary reason throws ArgumentError
      expect(
        () => orderController.voidOrder(
          orderId: checkoutRes.order.id,
          supervisorStaffId: 1,
          cashierStaffId: 2,
          reason: 'Arbitrary Reason',
        ),
        throwsArgumentError,
      );

      // Valid mandatory reason succeeds
      final res = await orderController.voidOrder(
        orderId: checkoutRes.order.id,
        supervisorStaffId: 1,
        cashierStaffId: 2,
        reason: VoidReason.paymentDeclined,
      );
      expect(res.reason, equals(VoidReason.paymentDeclined));
    });

    test('feature toggle reads and sets cashier void requests enabled in settings', () async {
      // Default is enabled (true)
      expect(await orderController.isCashierVoidEnabled(), isTrue);

      // Disable toggle
      await orderController.setCashierVoidEnabled(false);
      expect(await orderController.isCashierVoidEnabled(), isFalse);

      // Re-enable toggle
      await orderController.setCashierVoidEnabled(true);
      expect(await orderController.isCashierVoidEnabled(), isTrue);
    });
  });
}

// Existing checkout scenarios use publishable fixtures. Missing recipes use a
// separate counted ingredient so the scenario's stock assertions stay unchanged.
Future<void> publishFixtures(CatalogAndRecipeController catalog) async {
  for (final item in await catalog.getMenuItems()) {
    if ((await catalog.getRecipeForMenuItem(item.id)).isEmpty) {
      final ingredient = await catalog.createRawIngredient(name: 'Fixture portion ${item.id}', storageUnit: StorageUnit.count, currentStock: 1000);
      await catalog.setRecipeForMenuItem(menuItemId: item.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
    }
    await catalog.toggleMenuItemActive(item.id, true);
  }
}

