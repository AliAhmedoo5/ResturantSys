import '../delivery/delivery_controller.dart';
import 'paisa_engine.dart';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../catalog/discount_preset.dart';
import '../catalog/modifier.dart';
import '../catalog/modifier_group.dart';
import '../catalog/catalog_and_recipe_controller.dart';
import '../auth/staff_role.dart';
import '../database/pos_database_constants.dart';
import 'cart_item.dart';
import 'deal.dart';
import 'deal_item.dart';
import 'deal_item_option.dart';
import 'dining_type.dart';
import 'order.dart';
import 'order_item.dart';
import 'order_payment.dart';
import 'order_void.dart';
import 'payment_method.dart';
import 'token_status.dart';

/// Draft definition when creating or configuring a deal item slot.
class DealItemDraft {
  const DealItemDraft({
    required this.groupName,
    this.categoryId,
    this.defaultMenuItemId,
    this.isUpgradeable = false,
    this.upgradePrice = 0.0,
    this.options = const [],
  });

  final String groupName;
  final int? categoryId;
  final int? defaultMenuItemId;
  final bool isUpgradeable;
  final double upgradePrice;
  final List<DealOptionDraft> options;
}

/// Draft definition of an option inside a deal item slot.
class DealOptionDraft {
  const DealOptionDraft({
    required this.menuItemId,
    this.isDefault = false,
    this.upgradePrice = 0.0,
  });

  final int menuItemId;
  final bool isDefault;
  final double upgradePrice;
}

/// Payment tender tendered by customer during checkout.
class PaymentTender {
  const PaymentTender({
    required this.method,
    required this.amountTendered,
    this.changeReturned = 0.0,
    this.referenceCode,
  });

  final PaymentMethod method;
  final double amountTendered;
  final double changeReturned;
  final String? referenceCode;
}

/// Summary result of cart calculations.
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
  });

  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double grandTotal;
}

/// Low stock warning for an ingredient updated during checkout.
class LowStockWarning {
  const LowStockWarning({
    required this.ingredientId,
    required this.ingredientName,
    required this.currentStock,
    required this.threshold,
    required this.storageUnit,
  });

  final int ingredientId;
  final String ingredientName;
  final double currentStock;
  final double threshold;
  final String storageUnit;
}

/// Return record after committing an order.
class CheckoutResult {
  const CheckoutResult({
    required this.order,
    this.lowStockWarnings = const [],
  });

  final Order order;
  final List<LowStockWarning> lowStockWarnings;
}

/// Domain controller managing Deals, Cart calculations, Atomic Order checkout,
/// Daily sequential Tokens, and Soft BOM inventory deductions.
class OrderAndCheckoutController {
  OrderAndCheckoutController({required this.database});

  final Database database;

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  // ===========================================================================
  // DEALS MANAGEMENT
  // ===========================================================================

  Future<Deal> createDeal({
    required String name,
    required double basePrice,
    bool isActive = true,
    List<DealItemDraft> items = const [],
  }) async {
    final now = _formatTimestamp(DateTime.now());

    return await database.transaction((txn) async {
      final dealId = await txn.insert(
        PosDatabaseConstants.tableDeals,
        {
          'name': name.trim(),
          'base_price': basePrice,
          'is_active': isActive ? 1 : 0,
          'created_at': now,
        },
      );

      final createdDealItems = <DealItem>[];

      for (final itemDraft in items) {
        final itemId = await txn.insert(
          PosDatabaseConstants.tableDealItems,
          {
            'deal_id': dealId,
            'group_name': itemDraft.groupName.trim(),
            'category_id': itemDraft.categoryId,
            'default_menu_item_id': itemDraft.defaultMenuItemId,
            'is_upgradeable': itemDraft.isUpgradeable ? 1 : 0,
            'upgrade_price': itemDraft.upgradePrice,
          },
        );

        final createdOptions = <DealItemOption>[];
        for (final optDraft in itemDraft.options) {
          final optId = await txn.insert(
            PosDatabaseConstants.tableDealItemOptions,
            {
              'deal_item_id': itemId,
              'menu_item_id': optDraft.menuItemId,
              'is_default': optDraft.isDefault ? 1 : 0,
              'upgrade_price': optDraft.upgradePrice,
            },
          );

          createdOptions.add(DealItemOption(
            id: optId,
            dealItemId: itemId,
            menuItemId: optDraft.menuItemId,
            isDefault: optDraft.isDefault,
            upgradePrice: optDraft.upgradePrice,
          ));
        }

        createdDealItems.add(DealItem(
          id: itemId,
          dealId: dealId,
          groupName: itemDraft.groupName.trim(),
          categoryId: itemDraft.categoryId,
          defaultMenuItemId: itemDraft.defaultMenuItemId,
          isUpgradeable: itemDraft.isUpgradeable,
          upgradePrice: itemDraft.upgradePrice,
          options: createdOptions,
        ));
      }

      if (isActive) await validateDealRecipe(dealId, executor: txn);
      return Deal(
        id: dealId,
        name: name.trim(),
        basePrice: basePrice,
        isActive: isActive,
        createdAt: DateTime.parse(now),
        items: createdDealItems,
      );
    });
  }

  Future<List<Deal>> getDeals({bool? activeOnly}) async {
    String? where;
    if (activeOnly == true) {
      where = 'is_active = 1';
    }

    final dealRows = await database.query(
      PosDatabaseConstants.tableDeals,
      where: where,
      orderBy: 'name ASC',
    );

    final deals = <Deal>[];
    for (final row in dealRows) {
      final dealId = row['id'] as int;
      if (activeOnly == true) {
        try { await validateDealRecipe(dealId); } on StateError { continue; }
      }
      final dealItems = await _getDealItemsForDeal(dealId, database);
      deals.add(Deal.fromMap(row, items: dealItems));
    }
    return deals;
  }

  Future<void> validateDealRecipe(int dealId, {DatabaseExecutor? executor}) async {
    final db = executor ?? database;
    final slots = await _getDealItemsForDeal(dealId, db);
    if (slots.isEmpty) throw StateError('A published deal must contain at least one component.');
    final catalog = CatalogAndRecipeController(database: database);
    for (final slot in slots) {
      final ids = {if (slot.defaultMenuItemId != null) slot.defaultMenuItemId!, ...slot.options.map((option) => option.menuItemId)};
      if (slot.categoryId != null) {
        final candidates = await db.query('menu_items', where: 'category_id = ? AND is_active = 1', whereArgs: [slot.categoryId]);
        ids.addAll(candidates.map((row) => row['id'] as int));
      }
      if (ids.isEmpty) throw StateError('Every deal component needs a recipe-backed menu item.');
      for (final id in ids) {
        final rows = await db.query('menu_items', where: 'id = ? AND is_active = 1', whereArgs: [id]);
        if (rows.isEmpty) throw StateError('Deal components must be active menu items.');
        await catalog.validateRecipe(id, executor: db);
      }
    }
  }

  Future<void> toggleDealActive(int id, bool active) async {
    await database.transaction((txn) async {
      if (active) await validateDealRecipe(id, executor: txn);
      await txn.update('deals', {'is_active': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Deal> getDeal(int id) async {
    final dealRows = await database.query(
      PosDatabaseConstants.tableDeals,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (dealRows.isEmpty) {
      throw StateError('Deal with id $id not found.');
    }

    final dealItems = await _getDealItemsForDeal(id, database);
    return Deal.fromMap(dealRows.first, items: dealItems);
  }

  Future<List<DealItem>> _getDealItemsForDeal(int dealId, DatabaseExecutor executor) async {
    final itemRows = await executor.rawQuery('''
      SELECT di.*, mi.name as default_menu_item_name
      FROM ${PosDatabaseConstants.tableDealItems} di
      LEFT JOIN ${PosDatabaseConstants.tableMenuItems} mi ON di.default_menu_item_id = mi.id
      WHERE di.deal_id = ?
      ORDER BY di.id ASC;
    ''', [dealId]);

    final items = <DealItem>[];
    for (final row in itemRows) {
      final itemId = row['id'] as int;
      final optRows = await executor.rawQuery('''
        SELECT dio.*, mi.name as menu_item_name
        FROM ${PosDatabaseConstants.tableDealItemOptions} dio
        JOIN ${PosDatabaseConstants.tableMenuItems} mi ON dio.menu_item_id = mi.id
        WHERE dio.deal_item_id = ?
        ORDER BY dio.id ASC;
      ''', [itemId]);

      final options = optRows.map((o) => DealItemOption.fromMap(o)).toList();
      items.add(DealItem.fromMap(row, options: options));
    }
    return items;
  }

  Future<void> deleteDeal(int id) async {
    await database.delete(
      PosDatabaseConstants.tableDeals,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===========================================================================
  // TOKEN NUMBER GENERATION
  // ===========================================================================

  /// Returns the next daily sequential token number (#01, #02...) for the specified Business Day.
  /// Automatically resets when a new Business Day begins.
  Future<int> getNextTokenNumber(int businessDayId, [DatabaseExecutor? executor]) async {
    final dbExec = executor ?? database;
    final result = await dbExec.rawQuery('''
      SELECT COALESCE(MAX(token_number), 0) + 1 AS next_token
      FROM ${PosDatabaseConstants.tableOrders}
      WHERE business_day_id = ?;
    ''', [businessDayId]);

    if (result.isNotEmpty) {
      return (result.first['next_token'] as num).toInt();
    }
    return 1;
  }

  // ===========================================================================
  // CART CALCULATIONS
  // ===========================================================================

  CartTotals calculateCartTotals({
    required List<CartItem> items,
    DiscountPreset? discount,
  }) {
    double subtotal = 0.0;
    double taxAmount = 0.0;

    for (final item in items) {
      subtotal += item.totalPrice;
      if (item.menuItem != null) {
        final mi = item.menuItem!;
        if (mi.taxRate > 0) {
          if (mi.isTaxInclusive) {
            final net = item.totalPrice / (1.0 + (mi.taxRate / 100.0));
            taxAmount += (item.totalPrice - net);
          } else {
            taxAmount += item.totalPrice * (mi.taxRate / 100.0);
          }
        }
      }
    }

    double discountAmount = 0.0;
    if (discount != null) {
      discountAmount = discount.calculateDiscount(subtotal);
    }

    final grandTotal = (subtotal - discountAmount) < 0.0 ? 0.0 : (subtotal - discountAmount);

    return CartTotals(
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxAmount: taxAmount,
      grandTotal: grandTotal,
    );
  }

  // ===========================================================================
  // ATOMIC CHECKOUT & SOFT BOM DEDUCTION
  // ===========================================================================

  /// Executes an atomic order checkout:
  /// 1. Generates the daily sequential Token (#01, #02...).
  /// 2. Commits orders, order_items, and order_payments in a single SQLite transaction.
  /// 3. Performs soft BOM inventory deduction: allows negative stock balances and records low-stock warnings.
  /// 4. Automatically deducts takeaway packaging materials if dining type is Takeaway or Delivery.
  Future<CheckoutResult> checkoutOrder({
    required int businessDayId,
    required int shiftId,
    required int cashierId,
    required DiningType diningType,
    required List<CartItem> items,
    DiscountPreset? discount,
    required List<PaymentTender> payments,
    DeliveryDetails? delivery,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Cannot checkout an empty order.');
    }
    if (payments.isEmpty) {
      throw ArgumentError('Order must have at least one payment tender.');
    }

    // Hard-block Manager credentials from initiating checkout or tenders (ADR-0009)
    final staffRows = await database.query(
      PosDatabaseConstants.tableStaff,
      where: 'id = ?',
      whereArgs: [cashierId],
      limit: 1,
    );
    if (staffRows.isEmpty) {
      throw StateError('Authorization error: Cashier ID #$cashierId not found.');
    }
    final role = StaffRole.fromCode(staffRows.first['role'] as String);
    if (role != StaffRole.cashier) {
      throw StateError('Authorization error: Manager credentials cannot initiate checkout or process payments.');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);
    final totals = calculateCartTotals(items: items, discount: discount);

    return await database.transaction((txn) async {
      DeliveryArea? deliveryArea;
      if (diningType == DiningType.delivery) {
        if (delivery == null) throw const DeliveryCheckoutException('Select delivery details before payment. Your cart is unchanged.');
        deliveryArea = await DeliveryController.validateCheckout(txn, delivery, PaisaEngine.rupeesToPaisa(totals.grandTotal));
      }
      final deliveryFeePaisa = deliveryArea?.deliveryFeePaisa ?? 0;
      final grandTotalPaisa = PaisaEngine.rupeesToPaisa(totals.grandTotal) + deliveryFeePaisa;
      final grandTotal = PaisaEngine.paisaToRupees(grandTotalPaisa);
      if (deliveryArea != null) {
        final paid = payments.fold<int>(0, (sum, p) => sum + PaisaEngine.rupeesToPaisa(p.amountTendered - p.changeReturned));
        if (payments.any((p) => !p.amountTendered.isFinite || !p.changeReturned.isFinite || p.amountTendered < 0 || p.changeReturned < 0 || p.changeReturned > p.amountTendered) || paid != grandTotalPaisa) {
          throw const DeliveryCheckoutException('Payment must cover the food total and fixed delivery fee exactly. Your cart is unchanged.');
        }
        await DeliveryController.rememberAddress(txn, delivery!);
      }
      for (final item in items) { await _validateCartItem(item, txn); }
      // 1. Daily Sequential Token
      final tokenNumber = await getNextTokenNumber(businessDayId, txn);

      // 2. Commit Order Header
      final orderId = await txn.insert(
        PosDatabaseConstants.tableOrders,
        {
          'business_day_id': businessDayId,
          'shift_id': shiftId,
          'cashier_id': cashierId,
          'token_number': tokenNumber,
          'dining_type': diningType.code,
          'subtotal': totals.subtotal,
          'discount_amount': totals.discountAmount,
          'discount_id': discount?.id,
          'tax_amount': totals.taxAmount,
          'grand_total': grandTotal,
          'delivery_area_id': deliveryArea?.id,
          'delivery_area_name_snapshot': deliveryArea?.name,
          'delivery_fee_paisa': deliveryFeePaisa,
          'delivery_address_snapshot': deliveryArea == null ? null : delivery!.addressSnapshot,
          'customer_phone': deliveryArea == null ? null : DeliveryController.normalizePhone(delivery!.phone),
          'customer_name': deliveryArea == null ? null : delivery!.customerName.trim(),
          'payment_status': 'SETTLED',
          'token_status': TokenStatus.preparing.code,
          'created_at': formattedNow,
        },
      );

      // 3. Commit Order Items
      final createdOrderItems = <OrderItem>[];
      for (final cartItem in items) {
        String? modifiersJson;
        if (cartItem.selectedModifiers.isNotEmpty) {
          modifiersJson = jsonEncode(cartItem.selectedModifiers.map((m) => {
            'id': m.id,
            'name': m.name,
            'price_delta': m.priceDelta,
            'raw_ingredient_id': m.rawIngredientId,
            'ingredient_qty_delta': m.ingredientQtyDelta,
          }).toList());
        }

        String? dealChoicesJson;
        if (cartItem.selectedDealChoices.isNotEmpty) {
          dealChoicesJson = jsonEncode(
            cartItem.selectedDealChoices.map((c) => c.toJson()).toList(),
          );
        }

        final bom = await _lineBom(cartItem, txn);
        final bomJson = jsonEncode(bom.map((key, value) => MapEntry('$key', value)));
        final itemId = await txn.insert(
          PosDatabaseConstants.tableOrderItems,
          {
            'order_id': orderId,
            'menu_item_id': cartItem.menuItem?.id,
            'deal_id': cartItem.deal?.id,
            'name': cartItem.name,
            'quantity': cartItem.quantity,
            'unit_price': cartItem.unitPrice,
            'total_price': cartItem.totalPrice,
            'modifiers_json': modifiersJson,
            'deal_choices_json': dealChoicesJson,
            'bom_json': bomJson,
            'created_at': formattedNow,
          },
        );

        createdOrderItems.add(OrderItem(
          id: itemId,
          orderId: orderId,
          menuItemId: cartItem.menuItem?.id,
          dealId: cartItem.deal?.id,
          name: cartItem.name,
          quantity: cartItem.quantity,
          unitPrice: cartItem.unitPrice,
          totalPrice: cartItem.totalPrice,
          modifiersJson: modifiersJson,
          dealChoicesJson: dealChoicesJson,
          bomJson: bomJson,
          createdAt: now,
        ));
      }

      // 4. Commit Order Payments
      final createdPayments = <OrderPayment>[];
      for (final tender in payments) {
        final paymentId = await txn.insert(
          PosDatabaseConstants.tableOrderPayments,
          {
            'order_id': orderId,
            'payment_method': tender.method.code,
            'amount_tendered': tender.amountTendered,
            'change_returned': tender.changeReturned,
            'reference_code': tender.referenceCode,
          },
        );

        createdPayments.add(OrderPayment(
          id: paymentId,
          orderId: orderId,
          paymentMethod: tender.method,
          amountTendered: tender.amountTendered,
          changeReturned: tender.changeReturned,
          referenceCode: tender.referenceCode,
        ));
      }

      // 5. Soft BOM Inventory Deduction
      final lowStockWarnings = await _executeSoftBOMDeductions(
        items: items,
        diningType: diningType,
        executor: txn,
      );

      final order = Order(
        id: orderId,
        businessDayId: businessDayId,
        shiftId: shiftId,
        cashierId: cashierId,
        tokenNumber: tokenNumber,
        diningType: diningType,
        subtotal: totals.subtotal,
        discountAmount: totals.discountAmount,
        discountId: discount?.id,
        taxAmount: totals.taxAmount,
        grandTotal: grandTotal,
        deliveryAreaId: deliveryArea?.id,
        deliveryAreaName: deliveryArea?.name,
        deliveryFeePaisa: deliveryFeePaisa,
        deliveryAddress: deliveryArea == null ? null : delivery!.addressSnapshot,
        customerPhone: deliveryArea == null ? null : DeliveryController.normalizePhone(delivery!.phone),
        customerName: deliveryArea == null ? null : delivery!.customerName.trim(),
        paymentStatus: 'SETTLED',
        createdAt: now,
        items: createdOrderItems,
        payments: createdPayments,
      );

      return CheckoutResult(
        order: order,
        lowStockWarnings: lowStockWarnings,
      );
    });
  }

  Future<void> _validateCartItem(CartItem item, DatabaseExecutor txn) async {
    if (item.quantity <= 0 || (item.menuItem == null) == (item.deal == null)) throw StateError('Choose one valid menu item or deal per line.');
    final catalog = CatalogAndRecipeController(database: database);
    final componentIds = <int>[];
    if (item.menuItem != null) {
      if (item.selectedDealChoices.isNotEmpty) throw StateError('Menu items cannot contain deal choices.');
      componentIds.add(item.menuItem!.id);
    } else {
      final deals = await txn.query('deals', where: 'id = ? AND is_active = 1', whereArgs: [item.deal!.id]);
      if (deals.isEmpty) throw StateError('This deal is no longer active.');
      await validateDealRecipe(item.deal!.id, executor: txn);
      final slots = await _getDealItemsForDeal(item.deal!.id, txn);
      if (item.selectedDealChoices.length != slots.length || item.selectedDealChoices.map((c) => c.dealItemId).toSet().length != slots.length) throw StateError('Select exactly one option for each deal component.');
      for (final slot in slots) {
        final choices = item.selectedDealChoices.where((c) => c.dealItemId == slot.id);
        if (choices.length != 1) throw StateError('Missing deal component.');
        final choice = choices.single;
        final allowed = {if (slot.defaultMenuItemId != null) slot.defaultMenuItemId!, ...slot.options.map((o) => o.menuItemId)};
        if (slot.categoryId != null && slot.options.isEmpty) {
          final rows = await txn.query('menu_items', where: 'category_id = ? AND is_active = 1', whereArgs: [slot.categoryId]);
          allowed.addAll(rows.map((r) => r['id'] as int));
        }
        if (!allowed.contains(choice.menuItemId)) throw StateError('This menu item is not an allowed deal choice.');
        componentIds.add(choice.menuItemId);
      }
    }
    final canonical = <Modifier>[];
    for (final supplied in item.selectedModifiers) {
      final rows = await txn.query('modifiers', where: 'id = ? AND is_active = 1', whereArgs: [supplied.id]);
      if (rows.isEmpty) throw StateError('Selected modifier is no longer available.');
      final current = Modifier.fromMap(rows.single);
      if ((current.menuItemId != null && !componentIds.contains(current.menuItemId)) || current.menuItemId != supplied.menuItemId || current.rawIngredientId != supplied.rawIngredientId || current.ingredientQtyDelta != supplied.ingredientQtyDelta || current.priceDelta != supplied.priceDelta || current.groupId != supplied.groupId) throw StateError('Modifier changed; select it again.');
      if (!current.ingredientQtyDelta.isFinite || (current.rawIngredientId == null && current.ingredientQtyDelta != 0)) throw StateError('Invalid modifier ingredient delta.');
      if (current.rawIngredientId != null && (await txn.query('raw_ingredients', where: 'id = ?', whereArgs: [current.rawIngredientId])).isEmpty) throw StateError('Modifier ingredient no longer exists.');
      canonical.add(current);
    }
    final groups = <ModifierGroup>[];
    for (final id in componentIds.toSet()) {
      final rows = await txn.query('menu_items', where: 'id = ? AND is_active = 1', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('This menu item is no longer active.');
      await catalog.validateRecipe(id, executor: txn);
      groups.addAll(await catalog.getModifierGroups(menuItemId: id, executor: txn));
    }
    ModifierSelection.validate(canonical, groups);
  }

  Future<Map<int, double>> _lineBom(CartItem item, DatabaseExecutor executor) async {
    final quantities = <int, double>{};
    final ids = item.menuItem != null ? [item.menuItem!.id] : item.selectedDealChoices.map((c) => c.menuItemId);
    for (final id in ids) {
      await _accumulateMenuItemDeductions(menuItemId: id, quantity: item.quantity, selectedModifiers: item.selectedModifiers.where((m) => m.menuItemId == null || m.menuItemId == id).toList(), deductions: quantities, executor: executor);
    }
    return quantities;
  }

  /// Finds raw ingredient ID representing takeaway packaging box / materials.
  Future<int?> _findPackagingIngredientId(DatabaseExecutor executor) async {
    final packagingRows = await executor.rawQuery('''
      SELECT id FROM ${PosDatabaseConstants.tableRawIngredients}
      WHERE LOWER(name) LIKE '%packaging%' OR LOWER(name) LIKE '%takeaway%'
      LIMIT 1;
    ''');
    if (packagingRows.isNotEmpty) {
      return packagingRows.first['id'] as int;
    }
    return null;
  }

  /// Calculates BOM ingredient consumption and applies soft deductions.
  /// Handles removals with 0g BOM, add-ons with ingredient qty deltas, deal decomposition,
  /// and automatic takeaway packaging material deduction.
  Future<List<LowStockWarning>> _executeSoftBOMDeductions({
    required List<CartItem> items,
    required DiningType diningType,
    required DatabaseExecutor executor,
  }) async {
    // Map of rawIngredientId -> total quantity to deduct
    final deductions = <int, double>{};

    for (final item in items) {
      if (item.menuItem != null) {
        await _accumulateMenuItemDeductions(
          menuItemId: item.menuItem!.id,
          quantity: item.quantity,
          selectedModifiers: item.selectedModifiers,
          deductions: deductions,
          executor: executor,
        );
      } else if (item.deal != null) {
        // Decompose deal into customer-selected menu items
        for (final choice in item.selectedDealChoices) {
          await _accumulateMenuItemDeductions(
            menuItemId: choice.menuItemId,
            quantity: item.quantity,
            selectedModifiers: item.selectedModifiers,
            deductions: deductions,
            executor: executor,
          );
        }
      }
    }

    // Takeaway & Delivery Packaging Material Deduction
    if (diningType.requiresPackaging) {
      final packagingId = await _findPackagingIngredientId(executor);
      if (packagingId != null) {
        deductions[packagingId] = (deductions[packagingId] ?? 0.0) + 1.0;
      }
    }

    // Apply deductions softly: allows stock to become <= 0
    final warnings = <LowStockWarning>[];

    for (final entry in deductions.entries) {
      final ingredientId = entry.key;
      final qtyToDeduct = entry.value;

      await executor.rawUpdate('''
        UPDATE ${PosDatabaseConstants.tableRawIngredients}
        SET current_stock = current_stock - ?
        WHERE id = ?;
      ''', [qtyToDeduct, ingredientId]);

      // Check current stock and low stock threshold
      final ingRows = await executor.query(
        PosDatabaseConstants.tableRawIngredients,
        where: 'id = ?',
        whereArgs: [ingredientId],
      );

      if (ingRows.isNotEmpty) {
        final ing = ingRows.first;
        final currentStock = (ing['current_stock'] as num).toDouble();
        final threshold = (ing['low_stock_threshold'] as num).toDouble();
        final name = ing['name'] as String;
        final unit = ing['storage_unit'] as String;

        if (currentStock <= threshold) {
          warnings.add(LowStockWarning(
            ingredientId: ingredientId,
            ingredientName: name,
            currentStock: currentStock,
            threshold: threshold,
            storageUnit: unit,
          ));
        }
      }
    }

    return warnings;
  }

  Future<void> _accumulateMenuItemDeductions({
    required int menuItemId,
    required int quantity,
    required List<Modifier> selectedModifiers,
    required Map<int, double> deductions,
    required DatabaseExecutor executor,
  }) async {
    final recipes = await executor.query('recipes', where: 'menu_item_id = ?', whereArgs: [menuItemId]);
    final perPortion = <int, double>{for (final row in recipes) row['raw_ingredient_id'] as int: (row['quantity_per_recipe_unit'] as num).toDouble()};
    // Sum deltas in stable ID order, independent of click order or option names.
    final modifiers = [...selectedModifiers]..sort((a, b) => a.id.compareTo(b.id));
    for (final mod in modifiers) {
      if (mod.menuItemId != null && mod.menuItemId != menuItemId) continue;
      if (mod.rawIngredientId != null) {
        final id = mod.rawIngredientId!;
        perPortion[id] = (perPortion[id] ?? 0) + mod.ingredientQtyDelta;
      }
    }
    for (final entry in perPortion.entries) {
      if (!entry.value.isFinite || entry.value < 0) throw StateError('Modifier deltas cannot make recipe consumption negative.');
      deductions[entry.key] = (deductions[entry.key] ?? 0) + entry.value * quantity;
    }
  }

  // ===========================================================================
  // ORDER QUERIES
  // ===========================================================================

  Future<List<Order>> getOrders({
    int? businessDayId,
    int? shiftId,
    int? limit,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];

    if (businessDayId != null) {
      conditions.add('o.business_day_id = ?');
      args.add(businessDayId);
    }
    if (shiftId != null) {
      conditions.add('o.shift_id = ?');
      args.add(shiftId);
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    final limitClause = limit != null ? 'LIMIT $limit' : '';

    final rows = await database.rawQuery('''
      SELECT o.*, st.name as cashier_name
      FROM ${PosDatabaseConstants.tableOrders} o
      JOIN ${PosDatabaseConstants.tableStaff} st ON o.cashier_id = st.id
      $whereClause
      ORDER BY o.id DESC
      $limitClause;
    ''', args);

    final orders = <Order>[];
    for (final r in rows) {
      final orderId = r['id'] as int;
      final items = await getOrderItems(orderId);
      final payments = await getOrderPayments(orderId);
      orders.add(Order.fromMap(r, items: items, payments: payments, cashierName: r['cashier_name'] as String?));
    }
    return orders;
  }

  Future<Order> getOrder(int id) async {
    final rows = await database.rawQuery('''
      SELECT o.*, st.name as cashier_name
      FROM ${PosDatabaseConstants.tableOrders} o
      JOIN ${PosDatabaseConstants.tableStaff} st ON o.cashier_id = st.id
      WHERE o.id = ?;
    ''', [id]);

    if (rows.isEmpty) {
      throw StateError('Order with id $id not found.');
    }

    final items = await getOrderItems(id);
    final payments = await getOrderPayments(id);
    return Order.fromMap(rows.first, items: items, payments: payments, cashierName: rows.first['cashier_name'] as String?);
  }

  Future<List<OrderItem>> getOrderItems(int orderId) async {
    final rows = await database.query(
      PosDatabaseConstants.tableOrderItems,
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    return rows.map((r) => OrderItem.fromMap(r)).toList();
  }

  Future<List<OrderPayment>> getOrderPayments(int orderId) async {
    final rows = await database.query(
      PosDatabaseConstants.tableOrderPayments,
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'id ASC',
    );
    return rows.map((r) => OrderPayment.fromMap(r)).toList();
  }

  // ===========================================================================
  // SUPERVISOR ORDER VOID & INVENTORY REVERSAL
  // ===========================================================================

  /// Reads whether cashier-initiated void requests are currently enabled from system settings.
  Future<bool> isCashierVoidEnabled() async {
    final rows = await database.query(
      PosDatabaseConstants.tableSystemSettings,
      where: 'key = ?',
      whereArgs: [PosDatabaseConstants.settingCashierVoidRequestsEnabled],
    );
    if (rows.isNotEmpty) {
      return (rows.first['value'] as String).toLowerCase() == 'true';
    }
    return true; // Default enabled
  }

  /// Sets whether cashier-initiated void requests are enabled in system settings.
  Future<void> setCashierVoidEnabled(bool enabled) async {
    final now = _formatTimestamp(DateTime.now());
    await database.insert(
      PosDatabaseConstants.tableSystemSettings,
      {
        'key': PosDatabaseConstants.settingCashierVoidRequestsEnabled,
        'value': enabled ? 'true' : 'false',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Reads whether the interactive Token Queue Tray is enabled from system settings.
  Future<bool> isTokenTrayEnabled() async {
    final rows = await database.query(
      PosDatabaseConstants.tableSystemSettings,
      where: 'key = ?',
      whereArgs: [PosDatabaseConstants.settingTokenTrayEnabled],
    );
    if (rows.isNotEmpty) {
      return (rows.first['value'] as String).toLowerCase() == 'true';
    }
    return true; // Default enabled
  }

  /// Sets whether the interactive Token Queue Tray is enabled in system settings.
  Future<void> setTokenTrayEnabled(bool enabled) async {
    final now = _formatTimestamp(DateTime.now());
    await database.insert(
      PosDatabaseConstants.tableSystemSettings,
      {
        'key': PosDatabaseConstants.settingTokenTrayEnabled,
        'value': enabled ? 'true' : 'false',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Voids a settled order with supervisor authorization:
  /// 1. Verifies the order exists and is currently 'SETTLED'.
  /// 2. Validates mandatory cancellation reason.
  /// 3. Updates order status to 'VOIDED' in SQLite.
  /// 4. Immutably records audit entry in order_voids (cashier ID, supervisor ID, reason, timestamp).
  /// 5. Accurately reverses all BOM ingredient deductions, restoring raw ingredient stock.
  Future<OrderVoid> voidOrder({
    required int orderId,
    required int supervisorStaffId,
    required int cashierStaffId,
    required String reason,
  }) async {
    if (!VoidReason.isValid(reason)) {
      throw ArgumentError(
        'Invalid cancellation reason "$reason". Mandatory reasons: ${VoidReason.mandatoryReasons.join(', ')}',
      );
    }

    final order = await getOrder(orderId);
    if (order.isVoided) {
      throw StateError('Order #$orderId is already voided.');
    }
    if (!order.isSettled) {
      throw StateError('Only settled orders can be voided (current status: ${order.paymentStatus}).');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    return await database.transaction((txn) async {
      // 1. Mark order as VOIDED
      await txn.update(
        PosDatabaseConstants.tableOrders,
        {'payment_status': 'VOIDED'},
        where: 'id = ?',
        whereArgs: [orderId],
      );

      // 2. Insert immutable order_voids audit row
      final voidId = await txn.insert(
        PosDatabaseConstants.tableOrderVoids,
        {
          'order_id': orderId,
          'voided_by_supervisor_id': supervisorStaffId,
          'cashier_id': cashierStaffId,
          'reason': reason,
          'voided_at': formattedNow,
        },
      );

      // 3. Reverses BOM ingredient consumption
      final reversals = <int, double>{};
      for (final item in order.items) {
        await _accumulateOrderItemReversals(
          item: item,
          reversals: reversals,
          executor: txn,
        );
      }

      // Reverse packaging if Takeaway or Delivery
      if (order.diningType.requiresPackaging) {
        final packagingId = await _findPackagingIngredientId(txn);
        if (packagingId != null) {
          reversals[packagingId] = (reversals[packagingId] ?? 0.0) + 1.0;
        }
      }

      // Apply stock reversals: adds stock back
      for (final entry in reversals.entries) {
        await txn.rawUpdate('''
          UPDATE ${PosDatabaseConstants.tableRawIngredients}
          SET current_stock = current_stock + ?
          WHERE id = ?;
        ''', [entry.value, entry.key]);
      }

      // Lookup staff names for audit result
      final supervisorRows = await txn.query(
        PosDatabaseConstants.tableStaff,
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [supervisorStaffId],
      );
      final cashierRows = await txn.query(
        PosDatabaseConstants.tableStaff,
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [cashierStaffId],
      );

      return OrderVoid(
        id: voidId,
        orderId: orderId,
        voidedBySupervisorId: supervisorStaffId,
        cashierId: cashierStaffId,
        reason: reason,
        voidedAt: now,
        supervisorName: supervisorRows.isNotEmpty ? supervisorRows.first['name'] as String? : null,
        cashierName: cashierRows.isNotEmpty ? cashierRows.first['name'] as String? : null,
      );
    });
  }

  Future<void> _accumulateOrderItemReversals({
    required OrderItem item,
    required Map<int, double> reversals,
    required DatabaseExecutor executor,
  }) async {
    final bom = item.decodedBom;
    if (bom != null) {
      for (final entry in bom.entries) {
        reversals[entry.key] = (reversals[entry.key] ?? 0) + entry.value;
      }
      return;
    }
    final modifiers = item.decodedModifiers;
    final removedIngredientIds = <int>{};
    final positiveModifiers = <(int rawIngredientId, double delta)>[];

    for (final mod in modifiers) {
      final rawIngredientId = mod['raw_ingredient_id'] as int?;
      final name = (mod['name'] as String? ?? '').toLowerCase();
      final delta = (mod['ingredient_qty_delta'] as num?)?.toDouble() ?? 0.0;

      if (rawIngredientId != null) {
        if (delta == 0.0 || name.contains('no ')) {
          removedIngredientIds.add(rawIngredientId);
        } else if (delta > 0.0) {
          positiveModifiers.add((rawIngredientId, delta));
        }
      }
    }

    Future<void> reverseMenuItem(int menuItemId) async {
      final recipes = await executor.query(
        PosDatabaseConstants.tableRecipes,
        where: 'menu_item_id = ?',
        whereArgs: [menuItemId],
      );

      for (final recipe in recipes) {
        final ingredientId = recipe['raw_ingredient_id'] as int;
        final recipeQty = (recipe['quantity_per_recipe_unit'] as num).toDouble();

        if (removedIngredientIds.contains(ingredientId)) {
          continue; // 0g removal was consumed, nothing to reverse
        }

        reversals[ingredientId] = (reversals[ingredientId] ?? 0.0) + (recipeQty * item.quantity);
      }

      for (final mod in positiveModifiers) {
        if (!removedIngredientIds.contains(mod.$1)) {
          reversals[mod.$1] = (reversals[mod.$1] ?? 0.0) + (mod.$2 * item.quantity);
        }
      }
    }

    if (item.menuItemId != null) {
      await reverseMenuItem(item.menuItemId!);
    } else if (item.dealId != null) {
      for (final choice in item.decodedDealChoices) {
        final menuItemId = choice['menu_item_id'] as int?;
        if (menuItemId != null) {
          await reverseMenuItem(menuItemId);
        }
      }
    }
  }

  /// Retrieves the immutable void audit record for a voided order, if any.
  Future<OrderVoid?> getOrderVoid(int orderId) async {
    final rows = await database.rawQuery('''
      SELECT ov.*, 
             s1.name as supervisor_name, 
             s2.name as cashier_name
      FROM ${PosDatabaseConstants.tableOrderVoids} ov
      LEFT JOIN ${PosDatabaseConstants.tableStaff} s1 ON ov.voided_by_supervisor_id = s1.id
      LEFT JOIN ${PosDatabaseConstants.tableStaff} s2 ON ov.cashier_id = s2.id
      WHERE ov.order_id = ?
      ORDER BY ov.id DESC
      LIMIT 1;
    ''', [orderId]);

    if (rows.isEmpty) return null;
    return OrderVoid.fromMap(rows.first);
  }
}

