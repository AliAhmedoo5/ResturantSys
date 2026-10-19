import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/delivery/delivery_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  late PosDatabase store;
  late DeliveryController delivery;
  setUp(() async {
    sqfliteFfiInit();
    store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    delivery = DeliveryController(database: await store.initialize());
  });
  tearDown(() => store.close());

  test('Only Manager can configure fixed delivery fees and archive areas', () async {
    await expectLater(delivery.saveArea(staffId: 2, name: 'Garden', code: 'G', deliveryFeePaisa: 12550), throwsStateError);
    final area = await delivery.saveArea(staffId: 1, name: 'Garden', code: 'G', deliveryFeePaisa: 12550);
    expect((await delivery.getAreas()).single.deliveryFeePaisa, 12550);
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden East', code: 'G', deliveryFeePaisa: 15025, isActive: false);
    expect(await delivery.getAreas(activeOnly: true), isEmpty);
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden East', code: 'G', deliveryFeePaisa: 15025);
    expect((await delivery.getAreas(activeOnly: true)).single.name, 'Garden East');
    await expectLater(delivery.archiveArea(staffId: 2, id: area.id), throwsStateError);
    await delivery.archiveArea(staffId: 1, id: area.id);
    expect(await delivery.getAreas(), isEmpty);
    expect((await delivery.getAreas(includeArchived: true)).single.isArchived, isTrue);
  });
  test('Delivery commit retains cart on stale area, protects fee and remembers customer address', () async {
    final db = store.database!;
    final catalog = CatalogAndRecipeController(database: db);
    final shifts = ShiftAndCashController(database: db);
    final orders = OrderAndCheckoutController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final category = await catalog.createCategory(name: 'Food', displayOrder: 0, colorHex: '#000000');
    final food = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 500);
    final ingredient = await catalog.createRawIngredient(name: 'Portion', storageUnit: StorageUnit.count, currentStock: 10);
    await catalog.setRecipeForMenuItem(menuItemId: food.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
    await catalog.toggleMenuItemActive(food.id, true);
    final discount = await catalog.createDiscountPreset(name: '10%', type: DiscountType.percentage, value: 10);
    final area = await delivery.saveArea(staffId: 1, name: 'Garden', code: 'G', deliveryFeePaisa: 12550);
    final cart = [CartItem(menuItem: food, quantity: 1)];
    final details = DeliveryDetails(areaId: area.id, quotedFeePaisa: 12550, phone: '+92 300 1234567', customerName: 'Sara', fullAddress: 'House 7', landmark: 'School', notes: 'Call at gate');
    Future<CheckoutResult> commit() => orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
      diningType: DiningType.delivery, items: cart, discount: discount, delivery: details,
      payments: [const PaymentTender(method: PaymentMethod.raast, amountTendered: 575.50)]);
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden', code: 'G', deliveryFeePaisa: 12550, isActive: false);
    await expectLater(commit(), throwsA(isA<DeliveryCheckoutException>()));
    expect(cart.single.quantity, 1);
    expect(await orders.getOrders(), isEmpty);
    expect(await orders.getNextTokenNumber(day.id), 1);
    expect((await catalog.getRawIngredient(ingredient.id)).currentStock, 10);
    expect(await delivery.lookupAddresses('03001234567'), isEmpty);
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden', code: 'G', deliveryFeePaisa: 15000);
    await expectLater(commit(), throwsA(isA<DeliveryCheckoutException>()));
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden', code: 'G', deliveryFeePaisa: 12550);
    final result = await commit();
    expect(result.order.grandTotal, 575.50);
    expect(result.order.deliveryFeePaisa, 12550);
    final cashResult = await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
      diningType: DiningType.delivery, items: cart, discount: discount, delivery: details,
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600, changeReturned: 24)]);
    expect(cashResult.order.grandTotal, 575.50);
    expect(cashResult.order.cashRoundingPaisa, 50);
    final splitResult = await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
      diningType: DiningType.delivery, items: cart, discount: discount, delivery: details,
      payments: [const PaymentTender(method: PaymentMethod.raast, amountTendered: 200.25), const PaymentTender(method: PaymentMethod.cash, amountTendered: 375)]);
    expect(splitResult.order.cashRoundingPaisa, -25);
    expect((await orders.getOrder(splitResult.order.id)).cashRoundingPaisa, -25);
    final addresses = await delivery.lookupAddresses('0300123');
    expect(addresses.single.customerName, 'Sara');
    expect(addresses.single.fullAddress, 'House 7');
    expect(addresses.single.landmark, 'School');
    await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden', code: 'G', deliveryFeePaisa: 12550, minOrderPaisa: 45001);
    await expectLater(commit(), throwsA(isA<DeliveryCheckoutException>()));
    for (final example in [(12549, 575.0, -49), (12550, 576.0, 50), (12500, 575.0, 0)]) {
      await delivery.saveArea(staffId: 1, id: area.id, name: 'Garden', code: 'G', deliveryFeePaisa: example.$1);
      final rounded = await orders.checkoutOrder(businessDayId: day.id, shiftId: shift.id, cashierId: 2,
        diningType: DiningType.delivery, items: cart, discount: discount,
        delivery: DeliveryDetails(areaId: area.id, quotedFeePaisa: example.$1, phone: details.phone, fullAddress: details.fullAddress),
        payments: [PaymentTender(method: PaymentMethod.cash, amountTendered: example.$2)]);
      expect(rounded.order.cashRoundingPaisa, example.$3);
      expect(rounded.order.deliveryFeePaisa, example.$1);
    }    await delivery.archiveArea(staffId: 1, id: area.id);
    final saved = await orders.getOrder(result.order.id);
    expect(saved.deliveryAreaName, 'Garden');
    expect(saved.deliveryFeePaisa, 12550);
    expect(saved.deliveryAddress, contains('Call at gate'));
  });}




