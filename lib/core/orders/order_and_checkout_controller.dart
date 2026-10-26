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
import 'order_revision.dart';
import 'order_revision_line.dart';
import '../shifts/cash_movement.dart';
import 'payment_method.dart';
import 'token_status.dart';
import 'order_status_event.dart';

/// Immutable daily token allocation or lifecycle audit event.
class CheckoutTokenEvent {
  CheckoutTokenEvent.fromMap(Map<String, Object?> row)
      : orderId = row['order_id'] as int, tokenNumber = row['token_number'] as int,
        action = row['action'] as String, paymentStatus = row['payment_status'] as String,
        revision = row['revision'] as int;
  final int orderId, tokenNumber, revision;
  final String action, paymentStatus;
}

/// Result of an explicit Cashier disbursement action (cash payout or digital refund).
class RefundResult {
  const RefundResult({
    required this.orderId,
    required this.shiftId,
    required this.cashierId,
    required this.amountPaisa,
    required this.method,
    this.referenceCode,
    required this.reason,
    this.cashMovementId,
    required this.paymentStatus,
    required this.recordedAt,
  });

  final int orderId;
  final int shiftId;
  final int cashierId;
  final int amountPaisa;
  final PaymentMethod method;
  final String? referenceCode;
  final String reason;
  final int? cashMovementId;
  final String paymentStatus;
  final DateTime recordedAt;

  bool get isCashPayout => cashMovementId != null;
}

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

  Future<void> _requireActiveCashier(DatabaseExecutor executor, int cashierId) async {
    final rows = await executor.query('staff',
      where: 'id = ? AND is_active = 1 AND login_enabled = 1', whereArgs: [cashierId]);
    if (rows.isEmpty || rows.single['role'] != StaffRole.cashier.code) {
      throw StateError('Only an active Cashier can modify customer orders.');
    }
  }

  Future<List<OrderStatusEvent>> getOrderStatusEvents(int orderId) async {
    final rows = await database.query('order_status_events',
      where: 'order_id = ?', whereArgs: [orderId], orderBy: 'id');
    return List.unmodifiable(rows.map(OrderStatusEvent.fromMap));
  }

  /// Records one explicitly observed milestone; stale clicks cannot skip stages.
  /// Delivery completion belongs exclusively to the existing rider trip workflow.
  Future<TokenStatus> advanceOrderStatus({required int orderId,
    required int cashierId, required TokenStatus expectedStatus}) async {
    return database.transaction((txn) async {
      await _requireActiveCashier(txn, cashierId);
      final rows = await txn.rawQuery('''SELECT o.* FROM orders o
        JOIN business_days b ON b.id = o.business_day_id
        WHERE o.id = ? AND b.status = 'OPEN'
        AND NOT EXISTS (SELECT 1 FROM order_revisions r WHERE r.order_id = o.id AND r.action = 'CANCEL')''', [orderId]);
      if (rows.isEmpty) throw StateError('Order is unavailable, cancelled, or its Business Day is closed.');
      final order = Order.fromMap(rows.single);
      if (order.isCancelled || order.isVoided || order.tokenStatus != expectedStatus) {
        throw StateError('Order changed. Refresh its current status before continuing.');
      }
      final next = expectedStatus.nextStatus;
      if (next == null || expectedStatus == TokenStatus.outForDelivery ||
          (order.diningType == DiningType.delivery && next == TokenStatus.delivered)) {
        throw StateError('Use Rider Trips for delivery fulfillment; completed orders cannot advance.');
      }
      await txn.update('orders', {'token_status': next.code}, where: 'id = ?', whereArgs: [orderId]);
      await txn.insert('order_status_events', {'order_id': orderId, 'cashier_id': cashierId,
        'from_status': expectedStatus.code, 'to_status': next.code,
        'recorded_at': DateTime.now().toUtc().toIso8601String()});
      return next;
    });
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
      FROM checkout_tokens
      WHERE business_day_id = ?;
    ''', [businessDayId]);

    if (result.isNotEmpty) {
      return (result.first['next_token'] as num).toInt();
    }
    return 1;
  }

  Future<List<CheckoutTokenEvent>> getTokenAudit(int businessDayId) async {
    final rows = await database.query('checkout_token_audit', where: 'business_day_id = ?',
      whereArgs: [businessDayId], orderBy: 'id');
    return rows.map(CheckoutTokenEvent.fromMap).toList();
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
    String? commandId,
  }) async {
    if (commandId != null && commandId.trim().isEmpty) throw ArgumentError('Checkout command ID must not be blank.');
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
    if (role != StaffRole.cashier || staffRows.first['login_enabled'] == 0 || staffRows.first['is_active'] != 1) {
      throw StateError('Authorization error: Manager credentials cannot initiate checkout or process payments.');
    }

    final now = DateTime.now();
    final formattedNow = _formatTimestamp(now);

    return await database.transaction((txn) async {
      if (commandId != null) {
        final committed = await txn.query('orders', where: 'checkout_command_id = ?', whereArgs: [commandId]);
        if (committed.isNotEmpty) {
          final prior = committed.single;
          if (prior['cashier_id'] != cashierId || prior['business_day_id'] != businessDayId || prior['shift_id'] != shiftId) {
            throw StateError('Checkout command belongs to a different cashier session.');
          }
          final id = prior['id'] as int;
          final lines = await txn.query('order_items', where: 'order_id = ?', whereArgs: [id]);
          final tenders = await txn.query('order_payments', where: 'order_id = ?', whereArgs: [id]);
          return CheckoutResult(order: Order.fromMap(prior,
            items: lines.map(OrderItem.fromMap).toList(), payments: tenders.map(OrderPayment.fromMap).toList()));
        }
      }
    if (items.isEmpty) {
      throw ArgumentError('Cannot checkout an empty order.');
    }
    if (payments.isEmpty) {
      throw ArgumentError('Order must have at least one payment tender.');
    }

      final activeSession = await txn.rawQuery("""
        SELECT s.id FROM shifts s JOIN business_days d ON d.id = s.business_day_id
        JOIN staff st ON st.id = s.staff_id
        WHERE s.id = ? AND s.business_day_id = ? AND s.staff_id = ?
          AND s.status = 'OPEN' AND d.status = 'OPEN' AND st.is_active = 1
      """, [shiftId, businessDayId, cashierId]);
      if (activeSession.isEmpty) throw StateError('Checkout requires the cashier current open shift and business day.');
      final totals = calculateCartTotals(items: items, discount: discount);
      DeliveryArea? deliveryArea;
      if (diningType == DiningType.delivery) {
        if (delivery == null) throw const DeliveryCheckoutException('Select delivery details before payment. Your cart is unchanged.');
        deliveryArea = await DeliveryController.validateCheckout(txn, delivery, PaisaEngine.rupeesToPaisa(totals.grandTotal));
      }
      final deliveryFeePaisa = deliveryArea?.deliveryFeePaisa ?? 0;
      final grandTotalPaisa = PaisaEngine.rupeesToPaisa(totals.grandTotal) + deliveryFeePaisa;
      final grandTotal = PaisaEngine.paisaToRupees(grandTotalPaisa);
      var cashRoundingPaisa = 0;
      final isCod = payments.any((p) => p.method == PaymentMethod.cod);
      if (isCod) {
        if (diningType != DiningType.delivery || payments.length != 1 || payments.single.amountTendered != 0 || payments.single.changeReturned != 0) {
          throw StateError('COD requires delivery and records zero received until collection.');
        }
        await DeliveryController.rememberAddress(txn, delivery!);
      } else {
        if (payments.any((p) => !p.amountTendered.isFinite || !p.changeReturned.isFinite || p.amountTendered < 0 || p.changeReturned < 0 || p.changeReturned > p.amountTendered || p.method == PaymentMethod.split)) {
          throw const DeliveryCheckoutException('Enter valid individual payment tenders. Your cart is unchanged.');
        }
        for (final tender in payments) {
          final received = tender.amountTendered * 100;
          final returned = tender.changeReturned * 100;
          if ((received - received.round()).abs() > 0.000001 || (returned - returned.round()).abs() > 0.000001 ||
              (tender.method == PaymentMethod.cash && (received.round() % 100 != 0 || returned.round() % 100 != 0)) ||
              (tender.method != PaymentMethod.cash && tender.changeReturned != 0)) {
            throw const DeliveryCheckoutException('Record exact paisa for digital tenders and whole rupees for cash received and change.');
          }
        }
        final digitalPaid = payments.where((p) => p.method != PaymentMethod.cash).fold<int>(0,
          (sum, p) => sum + PaisaEngine.rupeesToPaisa(p.amountTendered) - PaisaEngine.rupeesToPaisa(p.changeReturned));
        final cashPaid = payments.where((p) => p.method == PaymentMethod.cash).fold<int>(0,
          (sum, p) => sum + PaisaEngine.rupeesToPaisa(p.amountTendered) - PaisaEngine.rupeesToPaisa(p.changeReturned));
        final hasCash = payments.any((p) => p.method == PaymentMethod.cash);
        final cashExact = grandTotalPaisa - digitalPaid;
        final cashDue = hasCash ? ((cashExact + 50) ~/ 100) * 100 : 0;
        if (digitalPaid > grandTotalPaisa || (hasCash ? cashPaid != cashDue : digitalPaid != grandTotalPaisa)) {
          throw const DeliveryCheckoutException('Payment must cover the food total and fixed delivery fee, with only the cash balance rounded to whole rupees. Your cart is unchanged.');
        }
        cashRoundingPaisa = hasCash ? cashDue - cashExact : 0;
        if (deliveryArea != null) await DeliveryController.rememberAddress(txn, delivery!);
      }      for (final item in items) { await _validateCartItem(item, txn); }
      // 1. Daily Sequential Token
      final tokenNumber = await getNextTokenNumber(businessDayId, txn);

      // 2. Commit Order Header
      final orderId = await txn.insert(
        PosDatabaseConstants.tableOrders,
        {
          'checkout_command_id': commandId,
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
          'cash_rounding_paisa': cashRoundingPaisa,
          'delivery_area_id': deliveryArea?.id,
          'delivery_area_name_snapshot': deliveryArea?.name,
          'delivery_fee_paisa': deliveryFeePaisa,
          'delivery_address_snapshot': deliveryArea == null ? null : delivery!.addressSnapshot,
          'customer_phone': deliveryArea == null ? null : DeliveryController.normalizePhone(delivery!.phone),
          'customer_name': deliveryArea == null ? null : delivery!.customerName.trim(),
          'payment_status': isCod ? 'COLLECTION_DUE' : 'SETTLED',
          'token_status': TokenStatus.preparing.code,
          'created_at': formattedNow,
        },
      );

      if (cashRoundingPaisa != 0) {
        await txn.insert(PosDatabaseConstants.tableRoundingVarianceLedger, {
          'order_id': orderId, 'shift_id': shiftId, 'cash_rounding_paisa': cashRoundingPaisa,
          'reason': 'Checkout cash balance half-up rounding', 'created_at': formattedNow,
        });
      }
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
            'amount_tendered_paisa': PaisaEngine.rupeesToPaisa(tender.amountTendered),
            'change_returned_paisa': PaisaEngine.rupeesToPaisa(tender.changeReturned),
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

      for (final warning in lowStockWarnings) {
        await txn.insert('checkout_stock_alerts', {
          'order_id': orderId, 'ingredient_id': warning.ingredientId,
          'stock_at_checkout': warning.currentStock, 'created_at': formattedNow,
        });
      }

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
        cashRoundingPaisa: cashRoundingPaisa,
        deliveryAreaId: deliveryArea?.id,
        deliveryAreaName: deliveryArea?.name,
        deliveryFeePaisa: deliveryFeePaisa,
        deliveryAddress: deliveryArea == null ? null : delivery!.addressSnapshot,
        customerPhone: deliveryArea == null ? null : DeliveryController.normalizePhone(delivery!.phone),
        customerName: deliveryArea == null ? null : delivery!.customerName.trim(),
        paymentStatus: isCod ? 'COLLECTION_DUE' : 'SETTLED',
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

  /// Outstanding stock alerts survive checkout and clear naturally on replenishment.
  Future<List<LowStockWarning>> getManagerStockAlerts() async {
    final rows = await database.rawQuery("""
      SELECT DISTINCT i.* FROM raw_ingredients i
      JOIN checkout_stock_alerts a ON a.ingredient_id = i.id
      WHERE i.current_stock <= i.low_stock_threshold
      ORDER BY i.current_stock, i.name
    """);
    return rows.map((row) => LowStockWarning(
      ingredientId: row['id'] as int, ingredientName: row['name'] as String,
      currentStock: (row['current_stock'] as num).toDouble(),
      threshold: (row['low_stock_threshold'] as num).toDouble(),
      storageUnit: row['storage_unit'] as String,
    )).toList();
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

  Future<List<OrderItem>> _getOrderItemsTxn(int orderId, DatabaseExecutor txn) async {
    final rows = await txn.query(
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

  // ===========================================================================
  // AUTONOMOUS CASHIER ORDER REVISIONS, STAGE-AWARE STOCK & DECOUPLED REFUNDS
  // ===========================================================================

  Future<Map<int, double>> _computeBOMForOrderItem(
    OrderItem item,
    DatabaseExecutor executor,
  ) async {
    final quantities = <int, double>{};
    if (item.menuItemId != null) {
      await _accumulateMenuItemDeductions(
        menuItemId: item.menuItemId!,
        quantity: item.quantity,
        selectedModifiers: [],
        deductions: quantities,
        executor: executor,
      );
    } else if (item.dealId != null) {
      for (final choice in item.decodedDealChoices) {
        final menuItemId = choice['menu_item_id'] as int?;
        if (menuItemId != null) {
          await _accumulateMenuItemDeductions(
            menuItemId: menuItemId,
            quantity: item.quantity,
            selectedModifiers: [],
            deductions: quantities,
            executor: executor,
          );
        }
      }
    }
    return quantities;
  }

  /// Cancels a confirmed order autonomously without requiring a Manager PIN.
  /// Appends an immutable record to `order_revisions` and `order_revision_lines`.
  /// Stage-aware stock disposition:
  /// - Confirmed (unstarted prep): RESTOCK_RAW (restores raw ingredients to bulk stock).
  /// - Preparing, Ready, Out for Delivery: WASTED_COOKED (posts to kitchen_wastage, cannot restore).
  /// Decoupled refund:
  /// - If prepaid, marks balance as Refund Owed/Pending (payment_status = 'REFUND_PENDING') without opening drawer.
  /// - Concurrent calls with identical commandId are strictly idempotent.
  Future<OrderRevision> cancelOrder({
    required int orderId,
    required int cashierId,
    required String reason,
    required String commandId,
  }) async {
    await _requireActiveCashier(database, cashierId);
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Cancellation reason is mandatory.');
    }

    final existingRevisions = await database.query(
      PosDatabaseConstants.tableOrderRevisions,
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    if (existingRevisions.isNotEmpty) {
      final revRow = existingRevisions.first;
      final revId = revRow['id'] as int;
      final lineRows = await database.query(
        PosDatabaseConstants.tableOrderRevisionLines,
        where: 'revision_id = ?',
        whereArgs: [revId],
      );
      final lines = lineRows.map((lr) => OrderRevisionLine.fromMap(lr)).toList();
      return OrderRevision.fromMap(revRow, lines: lines);
    }

    final order = await getOrder(orderId);
    if (order.isVoided || order.paymentStatus == 'CANCELLED') {
      throw StateError('Cannot cancel order #$orderId: Order is already voided or canceled.');
    }

    final bdayRows = await database.query(
      PosDatabaseConstants.tableBusinessDays,
      where: 'id = ?',
      whereArgs: [order.businessDayId],
    );
    if (bdayRows.isNotEmpty && bdayRows.first['status'] != 'OPEN') {
      throw StateError('Cannot cancel order: Business Day is closed.');
    }

    return await database.transaction((txn) async {
      await _requireActiveCashier(txn, cashierId);
      final settledTripRows = await txn.rawQuery('''
        SELECT rt.id, rt.trip_name
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = ? AND rt.status = 'SETTLED'
        LIMIT 1
      ''', [orderId]);
      if (settledTripRows.isNotEmpty) {
        throw StateError('Cannot cancel order #$orderId: Associated rider trip is settled and locked.');
      }

      final tripStopRows = await txn.rawQuery('''
        SELECT rto.status
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = ? AND rt.status != 'CANCELLED'
        LIMIT 1
      ''', [orderId]);
      if (tripStopRows.isNotEmpty && tripStopRows.first['status'] == 'DELIVERED') {
        throw StateError('Cannot cancel order #$orderId: Order has already been delivered.');
      }

      final now = DateTime.now();
      final formattedNow = _formatTimestamp(now);
      final utcNowIso = now.toUtc().toIso8601String();

      final oldOrderItems = await _getOrderItemsTxn(orderId, txn);
      final priorSnapshot = {
        'order_id': order.id,
        'token_number': order.tokenNumber,
        'grand_total': order.grandTotal,
        'subtotal': order.subtotal,
        'tax_amount': order.taxAmount,
        'payment_status': order.paymentStatus,
        'token_status': order.tokenStatus.code,
        'items': oldOrderItems.map((i) => i.toMap()).toList(),
      };

      final oldTotalPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
      const newTotalPaisa = 0;
      final moneyDeltaPaisa = -oldTotalPaisa;

      final nextRevisionNo = order.currentRevision + 1;
      final priorRevRows = await txn.query(
        PosDatabaseConstants.tableOrderRevisions,
        columns: ['id'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'revision_no DESC',
        limit: 1,
      );
      final priorRevisionId = priorRevRows.isNotEmpty ? priorRevRows.first['id'] as int : null;

      final isUnstartedPrep = order.tokenStatus == TokenStatus.confirmed;
      final disposition = isUnstartedPrep ? 'RESTOCK_RAW' : 'WASTED_COOKED';

      final linesToInsert = <Map<String, Object?>>[];
      for (final oldItem in oldOrderItems) {
        final itemBom = oldItem.decodedBom ?? await _computeBOMForOrderItem(oldItem, txn);
        linesToInsert.add({
          'original_order_line_id': oldItem.id,
          'item_id': oldItem.menuItemId ?? oldItem.dealId,
          'action': 'CANCEL',
          'old_qty_decimal': '${oldItem.quantity}',
          'new_qty_decimal': '0',
          'line_price_delta_paisa': -PaisaEngine.rupeesToPaisa(oldItem.totalPrice),
          'bom_disposition': disposition,
          'ingredient_delta_snapshot_json': jsonEncode(
            itemBom.entries.map((e) => {'ingredient_id': e.key, 'qty_delta': -e.value}).toList(),
          ),
        });

        for (final entry in itemBom.entries) {
          final ingId = entry.key;
          final qty = entry.value;
          if (isUnstartedPrep) {
            await txn.rawUpdate(
              'UPDATE ${PosDatabaseConstants.tableRawIngredients} SET current_stock = current_stock + ? WHERE id = ?',
              [qty, ingId],
            );
          } else {
            final ingRows = await txn.query(
              PosDatabaseConstants.tableRawIngredients,
              columns: ['cost_per_recipe_unit'],
              where: 'id = ?',
              whereArgs: [ingId],
            );
            final costPerUnit = ingRows.isNotEmpty ? (ingRows.first['cost_per_recipe_unit'] as num?)?.toDouble() ?? 0.0 : 0.0;
            final costLoss = qty * costPerUnit;
            await txn.insert(
              PosDatabaseConstants.tableKitchenWastage,
              {
                'staff_id': cashierId,
                'raw_ingredient_id': ingId,
                'quantity': qty,
                'cost_loss': costLoss,
                'reason': 'WASTED_COOKED',
                'notes': 'Order #${order.id} canceled cooked wastage: $trimmedReason',
                'created_at': formattedNow,
              },
            );
          }
        }
      }

      final paymentRows = await txn.query(
        PosDatabaseConstants.tableOrderPayments,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      final totalPaidPaisa = paymentRows.fold<int>(
        0,
        (sum, r) => sum + ((r['amount_tendered_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['amount_tendered'] as num).toDouble()))
                        - ((r['change_returned_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['change_returned'] as num?)?.toDouble() ?? 0.0)),
      );

      final wasPrepaid = totalPaidPaisa > 0 || order.isSettled;
      final newPaymentStatus = wasPrepaid ? 'REFUND_PENDING' : 'CANCELLED';

      await txn.update(
        PosDatabaseConstants.tableOrders,
        {
          'current_revision': nextRevisionNo,
          'grand_total': 0.0,
          'subtotal': 0.0,
          'tax_amount': 0.0,
          'discount_amount': 0.0,
          'payment_status': newPaymentStatus,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      final newSnapshot = {
        'order_id': order.id,
        'revision_no': nextRevisionNo,
        'grand_total': 0.0,
        'subtotal': 0.0,
        'tax_amount': 0.0,
        'payment_status': newPaymentStatus,
        'items': <Map<String, dynamic>>[],
      };

      final revisionId = await txn.insert(
        PosDatabaseConstants.tableOrderRevisions,
        {
          'order_id': orderId,
          'revision_no': nextRevisionNo,
          'prior_revision_id': priorRevisionId,
          'action': 'CANCEL',
          'reason': trimmedReason,
          'cashier_id': cashierId,
          'business_day_id': order.businessDayId,
          'created_at_utc': utcNowIso,
          'old_total_paisa': oldTotalPaisa,
          'new_total_paisa': newTotalPaisa,
          'money_delta_paisa': moneyDeltaPaisa,
          'prior_snapshot_json': jsonEncode(priorSnapshot),
          'new_snapshot_json': jsonEncode(newSnapshot),
          'command_id': commandId,
        },
      );

      final activeTripRows = await txn.rawQuery('''
        SELECT rt.id, rt.trip_name, rt.cash_expected_paisa, rto.status as stop_status
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = ? AND rt.status IN ('DISPATCHED', 'RETURNED')
        LIMIT 1
      ''', [orderId]);

      if (activeTripRows.isNotEmpty) {
        final tripRow = activeTripRows.first;
        final tripId = tripRow['id'] as int;
        final stopStatus = tripRow['stop_status'] as String?;

        if (order.tokenStatus == TokenStatus.outForDelivery) {
          final alertMsg = 'Order #${order.tokenDisplay} was CANCELLED by Cashier while Out for Delivery: $trimmedReason';

          await txn.insert(PosDatabaseConstants.tableRiderDispatchAlerts, {
            'trip_id': tripId,
            'order_id': orderId,
            'revision_id': revisionId,
            'alert_type': 'ORDER_CANCELLED',
            'message': alertMsg,
            'is_acknowledged': 0,
            'created_at': formattedNow,
          });
        }

        // Only deduct COD cash if stop is not already RETURNED (avoids double deduction)
        if (order.paymentStatus == 'COLLECTION_DUE' && stopStatus != 'RETURNED') {
          final oldPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
          await txn.rawUpdate('''
            UPDATE ${PosDatabaseConstants.tableRiderTrips}
            SET cash_expected_paisa = MAX(0, cash_expected_paisa - ?)
            WHERE id = ?
          ''', [oldPaisa, tripId]);
        }
      }

      final createdLines = <OrderRevisionLine>[];
      for (final line in linesToInsert) {
        final lineId = await txn.insert(
          PosDatabaseConstants.tableOrderRevisionLines,
          {
            'revision_id': revisionId,
            ...line,
          },
        );
        createdLines.add(OrderRevisionLine.fromMap({
          'id': lineId,
          'revision_id': revisionId,
          ...line,
        }));
      }

      return OrderRevision(
        id: revisionId,
        orderId: orderId,
        revisionNo: nextRevisionNo,
        priorRevisionId: priorRevisionId,
        action: 'CANCEL',
        reason: trimmedReason,
        cashierId: cashierId,
        businessDayId: order.businessDayId,
        createdAtUtc: now.toUtc(),
        oldTotalPaisa: oldTotalPaisa,
        newTotalPaisa: newTotalPaisa,
        moneyDeltaPaisa: moneyDeltaPaisa,
        priorSnapshotJson: jsonEncode(priorSnapshot),
        newSnapshotJson: jsonEncode(newSnapshot),
        commandId: commandId,
        lines: createdLines,
      );
    });
  }

  /// Revises an existing order autonomously without requiring a Manager PIN.
  /// Appends an immutable record to `order_revisions` and `order_revision_lines`.
  /// Stage-aware stock disposition:
  /// - Confirmed (unstarted prep): RESTOCK_RAW (restores raw ingredients to bulk stock).
  /// - Preparing, Ready, Out for Delivery: WASTED_COOKED (posts to kitchen_wastage, cannot restore).
  /// - Additions / increases: DEDUCT_RAW (deducts raw ingredient bulk stock).
  /// Decoupled refund:
  /// - If order was prepaid and monetary total is reduced, flags balance as Refund Owed/Pending
  ///   (payment_status = 'REFUND_PENDING') without opening drawer.
  /// - Concurrent calls with identical commandId are strictly idempotent.
  Future<OrderRevision> reviseOrder({
    required int orderId,
    required int cashierId,
    required String reason,
    required String commandId,
    required List<CartItem> newItems,
    String action = 'CHANGE',
  }) async {
    await _requireActiveCashier(database, cashierId);
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Revision reason is mandatory.');
    }

    final existingRevisions = await database.query(
      PosDatabaseConstants.tableOrderRevisions,
      where: 'command_id = ?',
      whereArgs: [commandId],
    );
    if (existingRevisions.isNotEmpty) {
      final revRow = existingRevisions.first;
      final revId = revRow['id'] as int;
      final lineRows = await database.query(
        PosDatabaseConstants.tableOrderRevisionLines,
        where: 'revision_id = ?',
        whereArgs: [revId],
      );
      final lines = lineRows.map((lr) => OrderRevisionLine.fromMap(lr)).toList();
      return OrderRevision.fromMap(revRow, lines: lines);
    }

    final order = await getOrder(orderId);
    if (order.isVoided || order.paymentStatus == 'CANCELLED') {
      throw StateError('Cannot revise order #$orderId: Order is already voided or canceled.');
    }

    final bdayRows = await database.query(
      PosDatabaseConstants.tableBusinessDays,
      where: 'id = ?',
      whereArgs: [order.businessDayId],
    );
    if (bdayRows.isNotEmpty && bdayRows.first['status'] != 'OPEN') {
      throw StateError('Cannot revise order: Business Day is closed.');
    }

    return await database.transaction((txn) async {
      await _requireActiveCashier(txn, cashierId);
      final settledTripRows = await txn.rawQuery('''
        SELECT rt.id, rt.trip_name
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = ? AND rt.status = 'SETTLED'
        LIMIT 1
      ''', [orderId]);
      if (settledTripRows.isNotEmpty) {
        throw StateError('Cannot revise order #$orderId: Associated rider trip is settled and locked.');
      }

      final tripStopRows = await txn.rawQuery('''
        SELECT rto.status
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = ? AND rt.status != 'CANCELLED'
        LIMIT 1
      ''', [orderId]);
      if (tripStopRows.isNotEmpty && tripStopRows.first['status'] == 'DELIVERED') {
        throw StateError('Cannot revise order #$orderId: Order has already been delivered.');
      }

      final now = DateTime.now();
      final formattedNow = _formatTimestamp(now);
      final utcNowIso = now.toUtc().toIso8601String();

      final oldOrderItems = await _getOrderItemsTxn(orderId, txn);
      final priorSnapshot = {
        'order_id': order.id,
        'token_number': order.tokenNumber,
        'grand_total': order.grandTotal,
        'subtotal': order.subtotal,
        'tax_amount': order.taxAmount,
        'payment_status': order.paymentStatus,
        'token_status': order.tokenStatus.code,
        'items': oldOrderItems.map((i) => i.toMap()).toList(),
      };

      final totals = calculateCartTotals(
        items: newItems,
      );

      final oldTotalPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
      final newTotalPaisa = PaisaEngine.rupeesToPaisa(totals.grandTotal);
      final moneyDeltaPaisa = newTotalPaisa - oldTotalPaisa;

      final nextRevisionNo = order.currentRevision + 1;
      final priorRevRows = await txn.query(
        PosDatabaseConstants.tableOrderRevisions,
        columns: ['id'],
        where: 'order_id = ?',
        whereArgs: [orderId],
        orderBy: 'revision_no DESC',
        limit: 1,
      );
      final priorRevisionId = priorRevRows.isNotEmpty ? priorRevRows.first['id'] as int : null;

      final isUnstartedPrep = order.tokenStatus == TokenStatus.confirmed;

      final oldIngredientTotals = <int, double>{};
      for (final oldItem in oldOrderItems) {
        final bom = oldItem.decodedBom ?? await _computeBOMForOrderItem(oldItem, txn);
        for (final entry in bom.entries) {
          oldIngredientTotals[entry.key] = (oldIngredientTotals[entry.key] ?? 0.0) + entry.value;
        }
      }

      final newIngredientTotals = <int, double>{};
      for (final newItem in newItems) {
        final bom = await _lineBom(newItem, txn);
        for (final entry in bom.entries) {
          newIngredientTotals[entry.key] = (newIngredientTotals[entry.key] ?? 0.0) + entry.value;
        }
      }

      final linesToInsert = <Map<String, Object?>>[];
      final matchedItemIndices = <int>{};

      for (final oldItem in oldOrderItems) {
        final matchIdx = newItems.indexWhere((ni) =>
            !matchedItemIndices.contains(newItems.indexOf(ni)) &&
            ((oldItem.menuItemId != null && ni.menuItem?.id == oldItem.menuItemId) ||
             (oldItem.dealId != null && ni.deal?.id == oldItem.dealId)));

        if (matchIdx == -1) {
          final itemBom = oldItem.decodedBom ?? await _computeBOMForOrderItem(oldItem, txn);
          final disposition = isUnstartedPrep ? 'RESTOCK_RAW' : 'WASTED_COOKED';
          linesToInsert.add({
            'original_order_line_id': oldItem.id,
            'item_id': oldItem.menuItemId ?? oldItem.dealId,
            'action': 'REMOVE',
            'old_qty_decimal': '${oldItem.quantity}',
            'new_qty_decimal': '0',
            'line_price_delta_paisa': -PaisaEngine.rupeesToPaisa(oldItem.totalPrice),
            'bom_disposition': disposition,
            'ingredient_delta_snapshot_json': jsonEncode(
              itemBom.entries.map((e) => {'ingredient_id': e.key, 'qty_delta': -e.value}).toList(),
            ),
          });
        } else {
          matchedItemIndices.add(matchIdx);
          final matchedNew = newItems[matchIdx];
          if (matchedNew.quantity != oldItem.quantity) {
            final oldQty = oldItem.quantity;
            final newQty = matchedNew.quantity;
            final qtyDelta = newQty - oldQty;
            final priceDelta = PaisaEngine.rupeesToPaisa(matchedNew.totalPrice) - PaisaEngine.rupeesToPaisa(oldItem.totalPrice);
            final itemBom = await _lineBom(matchedNew, txn);
            final disposition = qtyDelta < 0
                ? (isUnstartedPrep ? 'RESTOCK_RAW' : 'WASTED_COOKED')
                : 'DEDUCT_RAW';
            linesToInsert.add({
              'original_order_line_id': oldItem.id,
              'item_id': oldItem.menuItemId ?? oldItem.dealId,
              'action': 'CHANGE_QTY',
              'old_qty_decimal': '$oldQty',
              'new_qty_decimal': '$newQty',
              'line_price_delta_paisa': priceDelta,
              'bom_disposition': disposition,
              'ingredient_delta_snapshot_json': jsonEncode(
                itemBom.entries.map((e) => {'ingredient_id': e.key, 'qty_delta': e.value * (qtyDelta / newQty)}).toList(),
              ),
            });
          }
        }
      }

      for (int i = 0; i < newItems.length; i++) {
        if (!matchedItemIndices.contains(i)) {
          final newItem = newItems[i];
          final itemBom = await _lineBom(newItem, txn);
          linesToInsert.add({
            'original_order_line_id': null,
            'item_id': newItem.menuItem?.id ?? newItem.deal?.id,
            'action': 'ADD',
            'old_qty_decimal': '0',
            'new_qty_decimal': '${newItem.quantity}',
            'line_price_delta_paisa': PaisaEngine.rupeesToPaisa(newItem.totalPrice),
            'bom_disposition': 'DEDUCT_RAW',
            'ingredient_delta_snapshot_json': jsonEncode(
              itemBom.entries.map((e) => {'ingredient_id': e.key, 'qty_delta': e.value}).toList(),
            ),
          });
        }
      }

      if (linesToInsert.isEmpty) {
        linesToInsert.add({
          'original_order_line_id': null,
          'item_id': null,
          'action': action,
          'old_qty_decimal': '1',
          'new_qty_decimal': '1',
          'line_price_delta_paisa': moneyDeltaPaisa,
          'bom_disposition': isUnstartedPrep ? 'RESTOCK_RAW' : 'WASTED_COOKED',
          'ingredient_delta_snapshot_json': '[]',
        });
      }

      final allIngredientIds = {...oldIngredientTotals.keys, ...newIngredientTotals.keys};
      for (final ingId in allIngredientIds) {
        final oldQty = oldIngredientTotals[ingId] ?? 0.0;
        final newQty = newIngredientTotals[ingId] ?? 0.0;
        final diff = newQty - oldQty;
        if (diff > 0) {
          await txn.rawUpdate(
            'UPDATE ${PosDatabaseConstants.tableRawIngredients} SET current_stock = current_stock - ? WHERE id = ?',
            [diff, ingId],
          );
        } else if (diff < 0) {
          final returnedQty = -diff;
          if (isUnstartedPrep) {
            await txn.rawUpdate(
              'UPDATE ${PosDatabaseConstants.tableRawIngredients} SET current_stock = current_stock + ? WHERE id = ?',
              [returnedQty, ingId],
            );
          } else {
            final ingRows = await txn.query(
              PosDatabaseConstants.tableRawIngredients,
              columns: ['cost_per_recipe_unit'],
              where: 'id = ?',
              whereArgs: [ingId],
            );
            final costPerUnit = ingRows.isNotEmpty ? (ingRows.first['cost_per_recipe_unit'] as num?)?.toDouble() ?? 0.0 : 0.0;
            final costLoss = returnedQty * costPerUnit;
            await txn.insert(
              PosDatabaseConstants.tableKitchenWastage,
              {
                'staff_id': cashierId,
                'raw_ingredient_id': ingId,
                'quantity': returnedQty,
                'cost_loss': costLoss,
                'reason': 'WASTED_COOKED',
                'notes': 'Order #${order.id} revision cooked wastage: $trimmedReason',
                'created_at': formattedNow,
              },
            );
          }
        }
      }

      final paymentRows = await txn.query(
        PosDatabaseConstants.tableOrderPayments,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      final totalPaidPaisa = paymentRows.fold<int>(
        0,
        (sum, r) => sum + ((r['amount_tendered_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['amount_tendered'] as num).toDouble()))
                        - ((r['change_returned_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['change_returned'] as num?)?.toDouble() ?? 0.0)),
      );

      String newPaymentStatus = order.paymentStatus;
      if (totalPaidPaisa > newTotalPaisa) {
        newPaymentStatus = 'REFUND_PENDING';
      }

      await txn.update(
        PosDatabaseConstants.tableOrders,
        {
          'current_revision': nextRevisionNo,
          'subtotal': totals.subtotal,
          'tax_amount': totals.taxAmount,
          'grand_total': totals.grandTotal,
          'payment_status': newPaymentStatus,
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );

      await txn.delete(
        PosDatabaseConstants.tableOrderItems,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      final createdOrderItems = <OrderItem>[];
      for (final cartItem in newItems) {
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

      final newSnapshot = {
        'order_id': order.id,
        'revision_no': nextRevisionNo,
        'grand_total': totals.grandTotal,
        'subtotal': totals.subtotal,
        'tax_amount': totals.taxAmount,
        'payment_status': newPaymentStatus,
        'items': createdOrderItems.map((i) => i.toMap()).toList(),
      };

      final revisionId = await txn.insert(
        PosDatabaseConstants.tableOrderRevisions,
        {
          'order_id': orderId,
          'revision_no': nextRevisionNo,
          'prior_revision_id': priorRevisionId,
          'action': action,
          'reason': trimmedReason,
          'cashier_id': cashierId,
          'business_day_id': order.businessDayId,
          'created_at_utc': utcNowIso,
          'old_total_paisa': oldTotalPaisa,
          'new_total_paisa': newTotalPaisa,
          'money_delta_paisa': moneyDeltaPaisa,
          'prior_snapshot_json': jsonEncode(priorSnapshot),
          'new_snapshot_json': jsonEncode(newSnapshot),
          'command_id': commandId,
        },
      );

      final activeTripRows = await txn.rawQuery('''
        SELECT rt.id, rt.trip_name, rt.cash_expected_paisa, rto.status as stop_status
        FROM ${PosDatabaseConstants.tableRiderTripOrders} rto
        JOIN ${PosDatabaseConstants.tableRiderTrips} rt ON rto.trip_id = rt.id
        WHERE rto.order_id = ? AND rt.status IN ('DISPATCHED', 'RETURNED')
        LIMIT 1
      ''', [orderId]);

      if (activeTripRows.isNotEmpty) {
        final tripRow = activeTripRows.first;
        final tripId = tripRow['id'] as int;
        final stopStatus = tripRow['stop_status'] as String?;

        if (order.tokenStatus == TokenStatus.outForDelivery) {
          final alertMsg = 'Order #${order.tokenDisplay} was MODIFIED by Cashier while Out for Delivery: $trimmedReason';

          await txn.insert(PosDatabaseConstants.tableRiderDispatchAlerts, {
            'trip_id': tripId,
            'order_id': orderId,
            'revision_id': revisionId,
            'alert_type': 'ORDER_MODIFIED',
            'message': alertMsg,
            'is_acknowledged': 0,
            'created_at': formattedNow,
          });
        }

        // Only adjust expected cash if stop is not already RETURNED
        if (order.paymentStatus == 'COLLECTION_DUE' && stopStatus != 'RETURNED') {
          final oldPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
          final newPaisa = PaisaEngine.rupeesToPaisa(totals.grandTotal);
          final delta = newPaisa - oldPaisa;
          if (delta != 0) {
            await txn.rawUpdate('''
              UPDATE ${PosDatabaseConstants.tableRiderTrips}
              SET cash_expected_paisa = MAX(0, cash_expected_paisa + ?)
              WHERE id = ?
            ''', [delta, tripId]);
          }
        }
      }

      final createdLines = <OrderRevisionLine>[];
      for (final line in linesToInsert) {
        final lineId = await txn.insert(
          PosDatabaseConstants.tableOrderRevisionLines,
          {
            'revision_id': revisionId,
            ...line,
          },
        );
        createdLines.add(OrderRevisionLine.fromMap({
          'id': lineId,
          'revision_id': revisionId,
          ...line,
        }));
      }

      return OrderRevision(
        id: revisionId,
        orderId: orderId,
        revisionNo: nextRevisionNo,
        priorRevisionId: priorRevisionId,
        action: action,
        reason: trimmedReason,
        cashierId: cashierId,
        businessDayId: order.businessDayId,
        createdAtUtc: now.toUtc(),
        oldTotalPaisa: oldTotalPaisa,
        newTotalPaisa: newTotalPaisa,
        moneyDeltaPaisa: moneyDeltaPaisa,
        priorSnapshotJson: jsonEncode(priorSnapshot),
        newSnapshotJson: jsonEncode(newSnapshot),
        commandId: commandId,
        lines: createdLines,
      );
    });
  }

  /// Executes an explicit cashier disbursement action (drawer cash payout or digital refund).
  /// Decouples order reductions/cancellations from cash drawer opening.
  /// Cash refunds insert a `PAY_OUT` movement into `cash_movements` preserving cash drawer variance integrity.
  Future<RefundResult> recordCashierRefund({
    required int orderId,
    required int shiftId,
    required int cashierId,
    required int amountPaisa,
    required PaymentMethod method,
    String? referenceCode,
    required String reason,
    String? commandId,
  }) async {
    if (amountPaisa <= 0) {
      throw ArgumentError('Refund amount must be greater than zero.');
    }
    await _requireActiveCashier(database, cashierId);
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError('Refund reason is mandatory.');
    }

    final order = await getOrder(orderId);

    return await database.transaction((txn) async {
      final now = DateTime.now();
      final formattedNow = _formatTimestamp(now);

      int? cashMovementId;
      if (method == PaymentMethod.cash) {
        cashMovementId = await txn.insert(
          PosDatabaseConstants.tableCashMovements,
          {
            'shift_id': shiftId,
            'staff_id': cashierId,
            'type': CashMovementType.payOut.dbValue,
            'amount': PaisaEngine.paisaToRupees(amountPaisa),
            'category': 'REFUND',
            'notes': 'Order #$orderId refund: $trimmedReason',
            'approved_by': null,
            'created_at': formattedNow,
          },
        );
      }

      // Record refund payment line in order_payments
      // Negative amount records the refund credit
      await txn.insert(
        PosDatabaseConstants.tableOrderPayments,
        {
          'order_id': orderId,
          'payment_method': method.code,
          'amount_tendered': -PaisaEngine.paisaToRupees(amountPaisa),
          'change_returned': 0.0,
          'amount_tendered_paisa': -amountPaisa,
          'change_returned_paisa': 0,
          'reference_code': referenceCode ?? (commandId ?? 'REFUND-$orderId'),
        },
      );

      final paymentRows = await txn.query(
        PosDatabaseConstants.tableOrderPayments,
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      final netPaidPaisa = paymentRows.fold<int>(
        0,
        (sum, r) => sum + ((r['amount_tendered_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['amount_tendered'] as num).toDouble()))
                        - ((r['change_returned_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['change_returned'] as num?)?.toDouble() ?? 0.0)),
      );

      final grandTotalPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
      String updatedStatus = order.paymentStatus;
      if (netPaidPaisa <= grandTotalPaisa) {
        updatedStatus = grandTotalPaisa == 0 ? 'CANCELLED' : 'SETTLED';
        await txn.update(
          PosDatabaseConstants.tableOrders,
          {'payment_status': updatedStatus},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }

      return RefundResult(
        orderId: orderId,
        shiftId: shiftId,
        cashierId: cashierId,
        amountPaisa: amountPaisa,
        method: method,
        referenceCode: referenceCode,
        reason: trimmedReason,
        cashMovementId: cashMovementId,
        paymentStatus: updatedStatus,
        recordedAt: now,
      );
    });
  }

  /// Retrieves all immutable revisions recorded for [orderId], ordered chronologically.
  Future<List<OrderRevision>> getOrderRevisions(int orderId) async {
    final revRows = await database.query(
      PosDatabaseConstants.tableOrderRevisions,
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'revision_no ASC',
    );
    final revisions = <OrderRevision>[];
    for (final r in revRows) {
      final revId = r['id'] as int;
      final lineRows = await database.query(
        PosDatabaseConstants.tableOrderRevisionLines,
        where: 'revision_id = ?',
        whereArgs: [revId],
        orderBy: 'id ASC',
      );
      final lines = lineRows.map((lr) => OrderRevisionLine.fromMap(lr)).toList();
      revisions.add(OrderRevision.fromMap(r, lines: lines));
    }
    return revisions;
  }

  /// Calculates net pending refund amount in integer paisa for [orderId].
  Future<int> getOrderPendingRefundPaisa(int orderId) async {
    final order = await getOrder(orderId);
    final paymentRows = await database.query(
      PosDatabaseConstants.tableOrderPayments,
      where: 'order_id = ?',
      whereArgs: [orderId],
    );
    final netPaidPaisa = paymentRows.fold<int>(
      0,
      (sum, r) => sum + ((r['amount_tendered_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['amount_tendered'] as num).toDouble()))
                      - ((r['change_returned_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((r['change_returned'] as num?)?.toDouble() ?? 0.0)),
    );
    final grandTotalPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
    final pending = netPaidPaisa - grandTotalPaisa;
    return pending > 0 ? pending : 0;
  }
}



