import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../catalog/discount_preset.dart';
import '../catalog/modifier.dart';
import '../database/pos_database_constants.dart';
import 'cart_item.dart';
import 'deal.dart';
import 'deal_item.dart';
import 'deal_item_option.dart';
import 'dining_type.dart';
import 'order.dart';
import 'order_item.dart';
import 'order_payment.dart';
import 'payment_method.dart';

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
      final dealItems = await _getDealItemsForDeal(dealId, database);
      deals.add(Deal.fromMap(row, items: dealItems));
    }
    return deals;
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
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('Cannot checkout an empty order.');
    }
    if (payments.isEmpty) {
      throw ArgumentError('Order must have at least one payment tender.');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);
    final totals = calculateCartTotals(items: items, discount: discount);

    return await database.transaction((txn) async {
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
          'grand_total': totals.grandTotal,
          'payment_status': 'SETTLED',
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
        grandTotal: totals.grandTotal,
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
      // Find raw ingredient representing takeaway packaging box / materials
      final packagingRows = await executor.rawQuery('''
        SELECT id FROM ${PosDatabaseConstants.tableRawIngredients}
        WHERE LOWER(name) LIKE '%packaging%' OR LOWER(name) LIKE '%takeaway%'
        LIMIT 1;
      ''');

      if (packagingRows.isNotEmpty) {
        final packagingId = packagingRows.first['id'] as int;
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
    // 1. Fetch item recipe
    final recipes = await executor.query(
      PosDatabaseConstants.tableRecipes,
      where: 'menu_item_id = ?',
      whereArgs: [menuItemId],
    );

    // Identify removals: modifiers where ingredientQtyDelta == 0.0 (or negative) with a rawIngredientId
    final removedIngredientIds = <int>{};
    for (final mod in selectedModifiers) {
      if (mod.rawIngredientId != null &&
          (mod.ingredientQtyDelta == 0.0 || mod.name.toLowerCase().contains('no '))) {
        removedIngredientIds.add(mod.rawIngredientId!);
      }
    }

    for (final recipe in recipes) {
      final ingredientId = recipe['raw_ingredient_id'] as int;
      final recipeQty = (recipe['quantity_per_recipe_unit'] as num).toDouble();

      // If removal was selected for this ingredient, deduction is 0g (ADR-0002)
      if (removedIngredientIds.contains(ingredientId)) {
        continue;
      }

      deductions[ingredientId] = (deductions[ingredientId] ?? 0.0) + (recipeQty * quantity);
    }

    // 2. Modifiers: Add-ons with positive ingredient deltas
    for (final mod in selectedModifiers) {
      if (mod.rawIngredientId != null &&
          mod.ingredientQtyDelta > 0.0 &&
          !removedIngredientIds.contains(mod.rawIngredientId!)) {
        final ingredientId = mod.rawIngredientId!;
        final delta = mod.ingredientQtyDelta;
        deductions[ingredientId] = (deductions[ingredientId] ?? 0.0) + (delta * quantity);
      }
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
}
