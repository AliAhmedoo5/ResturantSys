import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/auth_service.dart';
import '../auth/staff.dart';
import '../database/pos_database_constants.dart';
import 'order.dart';
import 'order_item.dart';
import 'token_status.dart';

/// Coordinates real-time token progression across the counter Token Queue Tray
/// and the back-of-house Kitchen Token Station.
class TokenQueueController extends ChangeNotifier {
  TokenQueueController({
    this.database,
    this.authService,
    List<Order>? initialOrders,
  }) {
    if (initialOrders != null) {
      _orders.addAll(initialOrders);
    }
  }

  final Database? database;
  final AuthService? authService;

  final List<Order> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;

  UnmodifiableListView<Order> get allOrders => UnmodifiableListView(_orders);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Active tokens currently being prepared or waiting on the pass.
  List<Order> get activeTokens => _orders
      .where((o) => o.isSettled && o.tokenStatus != TokenStatus.delivered)
      .toList();

  /// Orders currently being prepared in the kitchen.
  List<Order> get preparingTokens => _orders
      .where((o) => o.isSettled && o.tokenStatus == TokenStatus.preparing)
      .toList();

  /// Orders plated on the pass, ready for customer pickup.
  List<Order> get readyTokens => _orders
      .where((o) => o.isSettled && o.tokenStatus == TokenStatus.ready)
      .toList();

  /// Orders fulfilled and handed over to customer / rider.
  List<Order> get deliveredTokens => _orders
      .where((o) => o.isSettled && o.tokenStatus == TokenStatus.delivered)
      .toList();

  /// Loads all settled orders and items for [businessDayId] (or latest if null).
  Future<void> loadTokens({int? businessDayId}) async {
    if (database == null) {
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final whereClause = StringBuffer("o.payment_status = 'SETTLED'");
      final whereArgs = <Object?>[];

      if (businessDayId != null) {
        whereClause.write(' AND o.business_day_id = ?');
        whereArgs.add(businessDayId);
      }

      final orderRows = await database!.rawQuery('''
        SELECT 
          o.*,
          st.name AS cashier_name
        FROM ${PosDatabaseConstants.tableOrders} o
        LEFT JOIN ${PosDatabaseConstants.tableStaff} st ON o.cashier_id = st.id
        WHERE $whereClause
        ORDER BY o.token_number ASC;
      ''', whereArgs);

      _orders.clear();

      for (final row in orderRows) {
        final orderId = row['id'] as int;

        final itemRows = await database!.query(
          PosDatabaseConstants.tableOrderItems,
          where: 'order_id = ?',
          whereArgs: [orderId],
          orderBy: 'id ASC',
        );

        final items = itemRows.map((ir) => OrderItem.fromMap(ir)).toList();
        final order = Order.fromMap(row, items: items);
        _orders.add(order);
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 1-tap progression: Preparing -> Ready -> Delivered.
  Future<TokenStatus> advanceToken(int orderId) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      throw StateError('Order #$orderId not found in token queue.');
    }

    final currentOrder = _orders[index];
    final nextStatus = currentOrder.tokenStatus.nextStatus;
    if (nextStatus == null) {
      throw StateError('Token ${currentOrder.tokenDisplay} is already in final status (${currentOrder.tokenStatus.displayName}).');
    }

    if (database != null) {
      await database!.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': nextStatus.code},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }

    _orders[index] = Order(
      id: currentOrder.id,
      businessDayId: currentOrder.businessDayId,
      shiftId: currentOrder.shiftId,
      cashierId: currentOrder.cashierId,
      tokenNumber: currentOrder.tokenNumber,
      diningType: currentOrder.diningType,
      subtotal: currentOrder.subtotal,
      discountAmount: currentOrder.discountAmount,
      discountId: currentOrder.discountId,
      taxAmount: currentOrder.taxAmount,
      grandTotal: currentOrder.grandTotal,
      paymentStatus: currentOrder.paymentStatus,
      createdAt: currentOrder.createdAt,
      tokenStatus: nextStatus,
      items: currentOrder.items,
      payments: currentOrder.payments,
      cashierName: currentOrder.cashierName,
    );

    notifyListeners();
    return nextStatus;
  }

  /// Marks an order as Ready (plated on the pass).
  Future<void> markTokenReady(int orderId) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      throw StateError('Order #$orderId not found.');
    }
    final currentOrder = _orders[index];
    if (currentOrder.tokenStatus == TokenStatus.ready) return;

    if (database != null) {
      await database!.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': TokenStatus.ready.code},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }

    _orders[index] = Order(
      id: currentOrder.id,
      businessDayId: currentOrder.businessDayId,
      shiftId: currentOrder.shiftId,
      cashierId: currentOrder.cashierId,
      tokenNumber: currentOrder.tokenNumber,
      diningType: currentOrder.diningType,
      subtotal: currentOrder.subtotal,
      discountAmount: currentOrder.discountAmount,
      discountId: currentOrder.discountId,
      taxAmount: currentOrder.taxAmount,
      grandTotal: currentOrder.grandTotal,
      paymentStatus: currentOrder.paymentStatus,
      createdAt: currentOrder.createdAt,
      tokenStatus: TokenStatus.ready,
      items: currentOrder.items,
      payments: currentOrder.payments,
      cashierName: currentOrder.cashierName,
    );

    notifyListeners();
  }

  /// Marks an order as Delivered (handed over to customer / rider).
  Future<void> markTokenDelivered(int orderId) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index == -1) {
      throw StateError('Order #$orderId not found.');
    }
    final currentOrder = _orders[index];
    if (currentOrder.tokenStatus == TokenStatus.delivered) return;

    if (database != null) {
      await database!.update(
        PosDatabaseConstants.tableOrders,
        {'token_status': TokenStatus.delivered.code},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    }

    _orders[index] = Order(
      id: currentOrder.id,
      businessDayId: currentOrder.businessDayId,
      shiftId: currentOrder.shiftId,
      cashierId: currentOrder.cashierId,
      tokenNumber: currentOrder.tokenNumber,
      diningType: currentOrder.diningType,
      subtotal: currentOrder.subtotal,
      discountAmount: currentOrder.discountAmount,
      discountId: currentOrder.discountId,
      taxAmount: currentOrder.taxAmount,
      grandTotal: currentOrder.grandTotal,
      paymentStatus: currentOrder.paymentStatus,
      createdAt: currentOrder.createdAt,
      tokenStatus: TokenStatus.delivered,
      items: currentOrder.items,
      payments: currentOrder.payments,
      cashierName: currentOrder.cashierName,
    );

    notifyListeners();
  }

  /// Authenticates a kitchen staff member with their 4-digit PIN for station access.
  Future<Staff?> authenticateKitchenPin(String pin) async {
    if (authService != null) {
      final staff = await authService!.authenticateWithPin(pin);
      if (staff != null && staff.canAccessKitchen) {
        return staff;
      }
      return null;
    }
    if (pin == '2222' || pin == '1234') {
      return Staff(
        id: 3,
        name: 'Kitchen Cook',
        departmentId: 2,
        departmentName: 'Kitchen',
        pinHash: pin,
        role: StaffRole.kitchen,
        isActive: true,
      );
    }
    return null;
  }
}
