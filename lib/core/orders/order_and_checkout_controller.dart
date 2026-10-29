import 'historical_costs.dart';
import '../payments/payment_event.dart';
import '../catalog/discount_stack.dart';
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

export '../catalog/deal_draft.dart';

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

/// Domain controller managing Cart calculations, Atomic Order checkout,
/// Daily sequential Tokens, and Soft BOM inventory deductions.
class OrderAndCheckoutController {
  OrderAndCheckoutController({required this.database});

  final Database database;
  late final _catalog = CatalogAndRecipeController(database: database);

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

  // Compatibility for existing Order callers; catalog owns Deal definitions.
  Future<Deal> createDeal({required String name, required double basePrice,
    bool isActive = true, List<DealItemDraft> items = const []}) =>
      _catalog.createDeal(name: name, basePrice: basePrice, isActive: isActive, items: items);

  Future<void> saveDeal({required int managerId, int? id, required String name,
    required double basePrice, required bool isActive, required List<DealItemDraft> items}) =>
      _catalog.saveDeal(managerId: managerId, id: id, name: name, basePrice: basePrice,
        isActive: isActive, items: items);

  Map<String, Object?> encodeDraftLine(CartItem item) => {
    'menu_item_id': item.menuItem?.id, 'deal_id': item.deal?.id, 'quantity': item.quantity,
    'modifiers': item.selectedModifiers.map((m) => m.id).toList(),
    'choices': item.selectedDealChoices.map((c) => c.toJson()).toList(),
  };

  /// Rehydrate with today's catalog; no historical price or tender is trusted.
  Future<List<CartItem>> restoreDraftLines(List<dynamic> lines) async {
    final catalog = CatalogAndRecipeController(database: database);
    final menu = {for (final item in await catalog.getMenuItems(activeOnly: true)) item.id: item};
    final deals = {for (final deal in await getDeals(activeOnly: true)) deal.id: deal};
    final modifiers = {for (final m in await catalog.getModifiers(activeOnly: true)) m.id: m};
    final restored = <CartItem>[];
    for (final raw in lines) {
      final row = Map<String, dynamic>.from(raw as Map);
      final menuId = row['menu_item_id'] as int?;
      final dealId = row['deal_id'] as int?;
      if ((menuId == null) == (dealId == null) || (menuId != null && !menu.containsKey(menuId)) ||
          (dealId != null && !deals.containsKey(dealId))) throw StateError('An item is unavailable. Choose a replacement in a new cart.');
      final selected = <Modifier>[];
      for (final id in row['modifiers'] as List<dynamic>) {
        final modifier = modifiers[id];
        if (modifier == null) throw StateError('A modifier is unavailable. Choose a replacement.');
        selected.add(modifier);
      }
      final choices = <SelectedDealChoice>[];
      for (final rawChoice in row['choices'] as List<dynamic>) {
        final choice = SelectedDealChoice.fromJson(Map<String, dynamic>.from(rawChoice as Map));
        final matching = deals[dealId]?.items.where((s) => s.id == choice.dealItemId).toList() ?? [];
        if (matching.length != 1 || !menu.containsKey(choice.menuItemId)) throw StateError('This deal changed; choose its components again.');
        final slot = matching.single;
        final options = slot.options.where((o) => o.menuItemId == choice.menuItemId).toList();
        if (options.isEmpty && slot.defaultMenuItemId != choice.menuItemId &&
            !(slot.options.isEmpty && slot.categoryId == menu[choice.menuItemId]!.categoryId)) {
          throw StateError('This deal changed; choose a replacement.');
        }
        choices.add(SelectedDealChoice(dealItemId: slot.id, groupName: slot.groupName,
          menuItemId: choice.menuItemId, menuItemName: menu[choice.menuItemId]!.name,
          upgradePrice: options.isNotEmpty ? options.single.upgradePrice :
            (slot.isUpgradeable && choice.menuItemId != slot.defaultMenuItemId ? slot.upgradePrice : 0)));
      }
      final item = CartItem(menuItem: menu[menuId], deal: deals[dealId], quantity: row['quantity'] as int,
        selectedModifiers: selected, selectedDealChoices: choices);
      await _validateCartItem(item, database);
      restored.add(item);
    }
    if (restored.isEmpty) throw StateError('The saved cart has no items.');
    return restored;
  }

  Future<int> holdCart({required int cashierId, required String label, required List<CartItem> items,
    required DiningType diningType, DeliveryDetails? delivery, int? customerId, int? discountId, List<int> discountIds = const [], int? previousHoldId}) async {
    return database.transaction((txn) async {
      await _requireActiveCashier(txn, cashierId);
      if (items.isEmpty || label.trim().isEmpty) throw ArgumentError('Enter a hold label and add items.');
      if (previousHoldId != null) {
        await txn.delete('held_carts', where: 'id = ? AND cashier_id = ?', whereArgs: [previousHoldId, cashierId]);
      }
      return txn.insert('held_carts', {'cashier_id': cashierId, 'label': label.trim(),
        'created_at': DateTime.now().toIso8601String(), 'payload': jsonEncode({
          'items': items.map(encodeDraftLine).toList(), 'dining_type': diningType.code,
          'customer_id': customerId, 'discount_id': discountId, 'discount_ids': discountIds,
          'delivery': delivery == null ? null : {'area_id': delivery.areaId, 'fee': delivery.quotedFeePaisa,
            'phone': delivery.phone, 'name': delivery.customerName, 'address': delivery.fullAddress,
            'landmark': delivery.landmark, 'notes': delivery.notes}})});
    });
  }

  Future<List<Map<String, Object?>>> getHolds(int cashierId) async {
    await _requireActiveCashier(database, cashierId);
    return database.query('held_carts', where: 'cashier_id = ?', whereArgs: [cashierId], orderBy: 'id DESC');
  }

  Future<void> removeHold(int cashierId, int id) async {
    await database.transaction((txn) async {
      await _requireActiveCashier(txn, cashierId);
      if (await txn.delete('held_carts', where: 'id = ? AND cashier_id = ?', whereArgs: [id, cashierId]) != 1) {
        throw StateError('Hold no longer exists.');
      }
    });
  }

  Future<List<CartItem>> repeatOrder({required int cashierId, required int orderId}) async {
    await _requireActiveCashier(database, cashierId);
    final order = await getOrder(orderId);
    if (order.isCancelled || order.isVoided) throw StateError('Cancelled orders cannot be repeated.');
    return restoreDraftLines(order.items.map((item) => {
      'menu_item_id': item.menuItemId, 'deal_id': item.dealId, 'quantity': item.quantity,
      'modifiers': item.decodedModifiers.map((m) => m['id']).toList(), 'choices': item.decodedDealChoices,
    }).toList());
  }

  Future<List<Deal>> getDeals({bool? activeOnly}) => _catalog.getDeals(activeOnly: activeOnly);

  Future<void> validateDealRecipe(int dealId, {DatabaseExecutor? executor}) =>
      _catalog.validateDealRecipe(dealId, executor: executor);

  Future<void> toggleDealActive(int id, bool active) => _catalog.toggleDealActive(id, active);

  Future<Deal> getDeal(int id) => _catalog.getDeal(id);

  Future<void> deleteDeal(int id) => _catalog.deleteDeal(id);

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
    List<DiscountPreset> discounts = const [],
    DiningType? diningType,
    int? cashierId,
    DateTime? now,
  }) {
    final subtotal = items.fold<int>(0, (sum, item) => sum + PaisaEngine.rupeesToPaisa(item.totalPrice)) / 100.0;
    final selected = [if (discount != null) discount, ...discounts];
    final balances = <int>[];
    final discountAmounts = DiscountStack.amounts(items: items, discounts: selected, diningMode: diningType?.code,
      cashierId: cashierId, now: now, remainingLinePaisa: balances);
    final discountAmount = discountAmounts.values.fold<int>(0, (sum, n) => sum + n) / 100.0;
    var taxPaisa = 0;
    for (var index = 0; index < items.length; index++) {
      final menu = items[index].menuItem;
      if (menu != null && menu.taxRate > 0) {
        // Shelf prices include tax; discounts reduce only their eligible lines.
        taxPaisa += (balances[index] * menu.taxRate / (100 + menu.taxRate)).round();
      }
    }
    final taxAmount = taxPaisa / 100.0;

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
    List<DiscountPreset> discounts = const [],
    required List<PaymentTender> payments,
    DeliveryDetails? delivery,
    String? commandId,
    int? customerId,
    int? heldCartId,
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
      final selectedDiscounts = [if (discount != null) discount, ...discounts]..sort((a, b) => a.id.compareTo(b.id));
      final discountAmounts = DiscountStack.amounts(items: items, discounts: selectedDiscounts, diningMode: diningType.code, cashierId: cashierId, now: now);
      for (final discount in selectedDiscounts) {
        final rows = await txn.query('discount_presets', where: 'id=?', whereArgs: [discount.id]);
        if (rows.isEmpty) throw StateError('Discount no longer exists. Refresh your cart.');
        final current = DiscountPreset.fromMap(rows.single);
        if (jsonEncode(current.toMap()) != jsonEncode(discount.toMap())) {
          throw StateError('Discount terms changed. Refresh your cart and review the new price.');
        }
        final subtotal = items.fold<double>(0, (sum, item) => sum + item.totalPrice);
        if (!current.isActive || current.calculateDiscount(subtotal, items: items, diningMode: diningType.code, cashierId: cashierId, now: now) <= 0) {
          throw StateError('Discount is not eligible for this order. Remove it and review payment.');
        }
        if (current.rules.dailyLimit != null) {
          final used = await txn.rawQuery('SELECT COUNT(*) AS n FROM orders o WHERE business_day_id=? AND (discount_id=? OR EXISTS(SELECT 1 FROM order_discounts d WHERE d.order_id=o.id AND d.discount_id=?))', [businessDayId, current.id, current.id]);
          if ((used.single['n'] as int) >= current.rules.dailyLimit!) throw StateError('Discount limit reached for this Business Day.');
        }
      }
      final totals = calculateCartTotals(items: items, discount: discount, discounts: discounts, diningType: diningType, cashierId: cashierId, now: now);
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

      if (heldCartId != null && await txn.delete('held_carts', where: 'id = ? AND cashier_id = ?',
          whereArgs: [heldCartId, cashierId]) != 1) {
        throw StateError('Held cart was already checked out or removed.');
      }
      if (customerId == null && delivery != null) {
        final phone = DeliveryController.normalizePhone(delivery.phone);
        final matches = await txn.query('customers', where: 'phone = ?', whereArgs: [phone]);
        if (matches.isEmpty) {
          customerId = await txn.insert('customers', {'name': delivery.customerName.trim().isEmpty ? phone : delivery.customerName.trim(),
            'phone': phone, 'created_at': formattedNow});
        } else {
          final match = matches.single;
          if (delivery.customerName.trim().isNotEmpty && match['name'] != delivery.customerName.trim()) {
            throw StateError('This phone belongs to a saved customer. Confirm the identity in Customers before checkout.');
          }
          customerId = (match['merged_into'] ?? match['id']) as int;
        }
      }
      Map<String, Object?>? selectedCustomer;
      if (customerId != null) {
        final customers = await txn.query('customers', where: 'id = ? AND merged_into IS NULL', whereArgs: [customerId]);
        if (customers.isEmpty) throw StateError('Customer was merged. Select the current customer record.');
        selectedCustomer = customers.single;
      }
      final customerPhoneSnapshot = deliveryArea != null ? DeliveryController.normalizePhone(delivery!.phone)
        : (selectedCustomer == null ? null : selectedCustomer['phone'] as String?);
      final customerNameSnapshot = deliveryArea != null ? delivery!.customerName.trim()
        : (selectedCustomer == null ? null : selectedCustomer['name'] as String?);
      // 2. Commit Order Header
      final orderId = await txn.insert(
        PosDatabaseConstants.tableOrders,
        {
          'checkout_command_id': commandId,
          'customer_id': customerId,
          'business_day_id': businessDayId,
          'shift_id': shiftId,
          'cashier_id': cashierId,
          'token_number': tokenNumber,
          'dining_type': diningType.code,
          'subtotal': totals.subtotal,
          'discount_amount': totals.discountAmount,
          'discount_id': selectedDiscounts.isEmpty ? null : selectedDiscounts.first.id,
          'tax_amount': totals.taxAmount,
          'grand_total': grandTotal,
          'cash_rounding_paisa': cashRoundingPaisa,
          'delivery_area_id': deliveryArea?.id,
          'delivery_area_name_snapshot': deliveryArea?.name,
          'delivery_fee_paisa': deliveryFeePaisa,
          'delivery_address_snapshot': deliveryArea == null ? null : delivery!.addressSnapshot,
          'customer_phone': customerPhoneSnapshot,
          'customer_name': customerNameSnapshot,
          'payment_status': isCod ? 'COLLECTION_DUE' : 'SETTLED',
          'token_status': TokenStatus.preparing.code,
          'created_at': formattedNow,
        },
      );

      for (final discount in selectedDiscounts) {
        await txn.insert('order_discounts', {'order_id': orderId, 'discount_id': discount.id,
          'sequence': (selectedDiscounts.map((d) => d.id).toList()..sort()).indexOf(discount.id),
          'name_snapshot': discount.name, 'terms_json': jsonEncode(discount.toMap()), 'amount_paisa': discountAmounts[discount.id]});
      }
      await txn.insert('order_cost_coverage', {'order_id': orderId, 'policy': 'EVENT_ACQUISITION_RATE_V1', 'recorded_at': formattedNow});
      final costQuantities = <int, double>{};
      for (final item in items) {
        for (final entry in (await _lineBom(item, txn)).entries) {
          costQuantities[entry.key] = (costQuantities[entry.key] ?? 0) + entry.value;
        }
      }
      if (diningType.requiresPackaging) {
        final packaging = await _findPackagingIngredientId(txn);
        if (packaging != null) costQuantities[packaging] = (costQuantities[packaging] ?? 0) + 1;
      }
      await HistoricalCosts.consume(txn, orderId, 0, costQuantities);
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

        if (tender.method != PaymentMethod.cod) {
          await PaymentEvent.record(txn, eventKey: 'tender-$paymentId', kind: 'RECEIPT',
            amountPaisa: PaisaEngine.rupeesToPaisa(tender.amountTendered) - PaisaEngine.rupeesToPaisa(tender.changeReturned),
            paymentSource: tender.method == PaymentMethod.cash ? 'DRAWER' : 'BANK',
            paymentMethod: tender.method.code, recordedBy: cashierId, recordedAt: now,
            businessDayId: businessDayId, shiftId: shiftId, orderId: orderId, tenderId: paymentId,
            changePaisa: PaisaEngine.rupeesToPaisa(tender.changeReturned),
            roundingPaisa: createdPayments.isEmpty ? cashRoundingPaisa : 0,
            sourceTable: 'order_payments', sourceId: paymentId);
        }
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
        discountId: selectedDiscounts.isEmpty ? null : selectedDiscounts.first.id,
        taxAmount: totals.taxAmount,
        grandTotal: grandTotal,
        cashRoundingPaisa: cashRoundingPaisa,
        deliveryAreaId: deliveryArea?.id,
        deliveryAreaName: deliveryArea?.name,
        deliveryFeePaisa: deliveryFeePaisa,
        deliveryAddress: deliveryArea == null ? null : delivery!.addressSnapshot,
        customerId: customerId,
        customerPhone: customerPhoneSnapshot,
        customerName: customerNameSnapshot,
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
      componentIds.addAll(await catalog.validateDealSelection(item.deal!.id,
        item.selectedDealChoices, executor: txn));
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
      for (final entry in (await _lineBom(item, executor)).entries) {
        deductions[entry.key] = (deductions[entry.key] ?? 0) + entry.value;
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
      SELECT o.*, st.name as cashier_name,
        EXISTS(SELECT 1 FROM order_revisions r WHERE r.order_id = o.id AND r.action = 'CANCEL') AS has_cancellation_revision
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
      SELECT o.*, st.name as cashier_name,
        EXISTS(SELECT 1 FROM order_revisions r WHERE r.order_id = o.id AND r.action = 'CANCEL') AS has_cancellation_revision
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

      await HistoricalCosts.remove(txn, orderId, order.currentRevision + 1, reversals, restock: true);
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
    if (order.isVoided || order.isCancelled) {
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

        await HistoricalCosts.remove(txn, orderId, nextRevisionNo, itemBom, restock: isUnstartedPrep);
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

      if (order.diningType.requiresPackaging) {
        final packagingLots = await txn.rawQuery("SELECT ingredient_id,SUM(CASE WHEN kind='CONSUME' THEN quantity ELSE -quantity END) AS remaining FROM order_cost_events WHERE order_id=? GROUP BY ingredient_id", [orderId]);
        for (final lot in packagingLots) {
          final remaining = (lot['remaining'] as num).toDouble();
          if (remaining <= 0) continue;
          final ingredientId = lot['ingredient_id'] as int;
          await HistoricalCosts.remove(txn, orderId, nextRevisionNo, {ingredientId: remaining}, restock: isUnstartedPrep);
          if (isUnstartedPrep) await txn.rawUpdate('UPDATE raw_ingredients SET current_stock=current_stock+? WHERE id=?', [remaining, ingredientId]);
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
    if (order.isVoided || order.isCancelled) {
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

      final discountRows = await txn.query('order_discounts', where: 'order_id=?', whereArgs: [orderId], orderBy: 'sequence');
      final originalDiscounts = discountRows.map((r) => DiscountPreset.fromMap(Map<String, Object?>.from(jsonDecode(r['terms_json'] as String) as Map))).toList();
      final totals = calculateCartTotals(items: newItems, discounts: originalDiscounts,
        diningType: order.diningType, cashierId: order.cashierId, now: order.createdAt);

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

      final costAdded = <int, double>{}, costRemoved = <int, double>{};
      for (final id in {...oldIngredientTotals.keys, ...newIngredientTotals.keys}) {
        final delta = (newIngredientTotals[id] ?? 0) - (oldIngredientTotals[id] ?? 0);
        if (delta > 0) costAdded[id] = delta;
        if (delta < 0) costRemoved[id] = -delta;
      }
      await HistoricalCosts.consume(txn, orderId, nextRevisionNo, costAdded);
      await HistoricalCosts.remove(txn, orderId, nextRevisionNo, costRemoved, restock: isUnstartedPrep);
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
          'discount_amount': totals.discountAmount,
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

  /// Accepts an independent partial collection in the current Cashier's Shift.
  /// The original Order's Business Day and Shift remain unchanged.
  Future<int> recordCashierReceipt({required int orderId, required int shiftId,
    required int cashierId, required int amountPaisa, required PaymentMethod method,
    required String commandId, DateTime? actualAt, String? referenceCode}) async {
    if (amountPaisa <= 0 || commandId.trim().isEmpty || method == PaymentMethod.cod || method == PaymentMethod.split) {
      throw ArgumentError('A positive manual tender and stable command identity are required.');
    }
    if (method == PaymentMethod.cash && amountPaisa % 100 != 0) throw ArgumentError('Physical cash receipts require whole rupees.');
    return database.transaction((txn) async {
      await _requireActiveCashier(txn, cashierId);
      final previous = await txn.query('payment_events', where: 'event_key=?', whereArgs: ['receipt-$commandId']);
      if (previous.isNotEmpty) {
        final row = previous.single;
        if (row['order_id'] != orderId || row['shift_id'] != shiftId || row['recorded_by'] != cashierId || row['amount_paisa'] != amountPaisa || row['payment_method'] != method.code) throw StateError('Receipt retry does not match its original operation.');
        return row['id'] as int;
      }
      final shifts = await txn.query('shifts', where: 'id=? AND staff_id=? AND status=?', whereArgs: [shiftId, cashierId, 'OPEN']);
      if (shifts.isEmpty) throw StateError('A Cashier-owned open receiving Shift is required.');
      final orders = await txn.query('orders', where: 'id=?', whereArgs: [orderId]);
      if (orders.isEmpty || orders.single['payment_status'] != 'COLLECTION_DUE') throw StateError('Only Collection Due orders accept further receipts.');
      final locked = await txn.rawQuery("SELECT t.id FROM rider_trips t JOIN rider_trip_orders x ON x.trip_id=t.id WHERE x.order_id=? AND t.status='SETTLED'", [orderId]);
      if (locked.isNotEmpty) throw StateError('Settled Trip Lock prevents direct tender changes.');
      final payments = await txn.query('order_payments', where: 'order_id=?', whereArgs: [orderId]);
      final paid = payments.fold<int>(0, (sum,p) => sum + ((p['amount_tendered_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((p['amount_tendered'] as num).toDouble())) - ((p['change_returned_paisa'] as int?) ?? PaisaEngine.rupeesToPaisa((p['change_returned'] as num?)?.toDouble() ?? 0)));
      final due = PaisaEngine.rupeesToPaisa((orders.single['grand_total'] as num).toDouble()) - paid;
      if (amountPaisa > due) throw StateError('Receipt exceeds the remaining Collection Due.');
      final tender = await txn.insert('order_payments', {'order_id': orderId, 'payment_method': method.code, 'amount_tendered': PaisaEngine.paisaToRupees(amountPaisa), 'amount_tendered_paisa': amountPaisa, 'change_returned': 0, 'change_returned_paisa': 0, 'reference_code': referenceCode});
      final id = await PaymentEvent.record(txn, eventKey: 'receipt-$commandId', kind: 'RECEIPT', amountPaisa: amountPaisa,
        paymentSource: method == PaymentMethod.cash ? 'DRAWER' : 'BANK', paymentMethod: method.code,
        recordedBy: cashierId, recordedAt: DateTime.now().toUtc(), actualAt: actualAt,
        businessDayId: shifts.single['business_day_id'] as int, shiftId: shiftId, orderId: orderId, tenderId: tender, sourceTable: 'order_payments', sourceId: tender);
      if (amountPaisa == due) await txn.update('orders', {'payment_status': 'SETTLED'}, where: 'id=?', whereArgs: [orderId]);
      return id;
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
    DateTime? actualAt,
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

      final receiving = await txn.query('shifts', where: 'id=? AND staff_id=? AND status=?', whereArgs: [shiftId, cashierId, 'OPEN']);
      if (receiving.isEmpty) throw StateError('A Cashier-owned open receiving Shift is required.');
      if (commandId != null) {
        final previous = await txn.query('payment_events', where: 'event_key=?', whereArgs: ['refund-$commandId']);
        if (previous.isNotEmpty) {
          final row = previous.single;
          if (row['order_id'] != orderId || row['shift_id'] != shiftId || row['recorded_by'] != cashierId || row['amount_paisa'] != -amountPaisa || row['payment_method'] != method.code) throw StateError('Refund retry does not match its original operation.');
          return RefundResult(orderId: orderId, shiftId: shiftId, cashierId: cashierId, amountPaisa: amountPaisa, method: method, reason: trimmedReason, referenceCode: referenceCode, cashMovementId: row['movement_id'] as int?, paymentStatus: order.paymentStatus, recordedAt: DateTime.parse(row['recorded_at'] as String));
        }
      }

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
      final refundTenderId = await txn.insert(
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

      await PaymentEvent.record(txn, eventKey: commandId == null ? 'tender-$refundTenderId' : 'refund-$commandId', kind: 'REFUND',
        amountPaisa: -amountPaisa, paymentSource: method == PaymentMethod.cash ? 'DRAWER' : 'BANK', paymentMethod: method.code,
        recordedBy: cashierId, recordedAt: now, actualAt: actualAt,
        businessDayId: receiving.single['business_day_id'] as int, shiftId: shiftId,
        orderId: orderId, tenderId: refundTenderId, movementId: cashMovementId,
        sourceTable: 'order_payments', sourceId: refundTenderId);

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
        updatedStatus = grandTotalPaisa == 0 ? 'CANCELLED' : netPaidPaisa < grandTotalPaisa ? 'COLLECTION_DUE' : 'SETTLED';
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




