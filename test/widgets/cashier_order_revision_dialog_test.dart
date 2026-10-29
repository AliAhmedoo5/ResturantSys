import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/modifier_group.dart';
import 'package:resturant_sys/core/orders/deal.dart';
import 'package:resturant_sys/core/orders/deal_item.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_item.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/order_revision.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/orders/paisa_engine.dart';
import 'package:resturant_sys/widgets/orders/cashier_order_revision_dialog.dart';

class FakeOrderController implements OrderAndCheckoutController {
  FakeOrderController({required this.order, this.pendingRefundPaisa = 0});

  Order order;
  int pendingRefundPaisa;
  OrderRevision? lastRevision;
  RefundResult? lastRefund;
  String? lastCancelReason;
  String? lastRevisionReason;
  List<CartItem>? submittedItems;
  List<Deal> deals = [];

  @override
  Future<List<Deal>> getDeals({bool? activeOnly}) async => deals;

  @override
  Database get database => throw UnimplementedError();

  @override
  Future<int> getOrderPendingRefundPaisa(int orderId) async {
    return pendingRefundPaisa;
  }

  @override
  Future<Order> getOrder(int id) async => order;

  @override
  Future<OrderRevision> cancelOrder({
    required int orderId,
    required int cashierId,
    required String reason,
    required String commandId,
  }) async {
    lastCancelReason = reason;
    pendingRefundPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
    order = Order(
      id: order.id,
      businessDayId: order.businessDayId,
      shiftId: order.shiftId,
      cashierId: cashierId,
      tokenNumber: order.tokenNumber,
      diningType: order.diningType,
      subtotal: 0.0,
      grandTotal: 0.0,
      paymentStatus: 'REFUND_PENDING',
      tokenStatus: order.tokenStatus,
      createdAt: order.createdAt,
      items: const [],
      currentRevision: order.currentRevision + 1,
    );
    final rev = OrderRevision(
      id: 1,
      orderId: orderId,
      revisionNo: order.currentRevision,
      action: 'CANCEL',
      reason: reason,
      cashierId: cashierId,
      businessDayId: order.businessDayId,
      createdAtUtc: DateTime.now().toUtc(),
      oldTotalPaisa: 100000,
      newTotalPaisa: 0,
      moneyDeltaPaisa: -100000,
      priorSnapshotJson: '{}',
      newSnapshotJson: '{}',
      commandId: commandId,
      lines: const [],
    );
    lastRevision = rev;
    return rev;
  }

  @override
  Future<OrderRevision> reviseOrder({
    required int orderId,
    required int cashierId,
    required String reason,
    required String commandId,
    required List<CartItem> newItems,
    String action = 'CHANGE',
  }) async {
    lastRevisionReason = reason;
    submittedItems = List.of(newItems);
    final newSubtotal = newItems.fold<double>(0.0, (sum, i) => sum + i.totalPrice);
    final oldTotalPaisa = PaisaEngine.rupeesToPaisa(order.grandTotal);
    final newTotalPaisa = PaisaEngine.rupeesToPaisa(newSubtotal);
    if (newTotalPaisa < oldTotalPaisa) {
      pendingRefundPaisa = oldTotalPaisa - newTotalPaisa;
    }
    order = Order(
      id: order.id,
      businessDayId: order.businessDayId,
      shiftId: order.shiftId,
      cashierId: cashierId,
      tokenNumber: order.tokenNumber,
      diningType: order.diningType,
      subtotal: newSubtotal,
      grandTotal: newSubtotal,
      paymentStatus: pendingRefundPaisa > 0 ? 'REFUND_PENDING' : order.paymentStatus,
      tokenStatus: order.tokenStatus,
      createdAt: order.createdAt,
      items: newItems
          .map((ci) => OrderItem(
                id: 1,
                orderId: order.id,
                menuItemId: ci.menuItem?.id,
                dealId: ci.deal?.id,
                name: ci.name,
                quantity: ci.quantity,
                unitPrice: ci.unitPrice,
                totalPrice: ci.totalPrice,
                createdAt: DateTime.now(),
              ))
          .toList(),
      currentRevision: order.currentRevision + 1,
    );
    final rev = OrderRevision(
      id: 2,
      orderId: orderId,
      revisionNo: order.currentRevision,
      action: action,
      reason: reason,
      cashierId: cashierId,
      businessDayId: order.businessDayId,
      createdAtUtc: DateTime.now().toUtc(),
      oldTotalPaisa: oldTotalPaisa,
      newTotalPaisa: newTotalPaisa,
      moneyDeltaPaisa: newTotalPaisa - oldTotalPaisa,
      priorSnapshotJson: '{}',
      newSnapshotJson: '{}',
      commandId: commandId,
      lines: const [],
    );
    lastRevision = rev;
    return rev;
  }

  @override
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
    pendingRefundPaisa = 0;
    order = Order(
      id: order.id,
      businessDayId: order.businessDayId,
      shiftId: shiftId,
      cashierId: cashierId,
      tokenNumber: order.tokenNumber,
      diningType: order.diningType,
      subtotal: order.subtotal,
      grandTotal: order.grandTotal,
      paymentStatus: order.grandTotal == 0 ? 'CANCELLED' : 'SETTLED',
      tokenStatus: order.tokenStatus,
      createdAt: order.createdAt,
      items: order.items,
      currentRevision: order.currentRevision,
    );
    final res = RefundResult(
      orderId: orderId,
      shiftId: shiftId,
      cashierId: cashierId,
      amountPaisa: amountPaisa,
      method: method,
      referenceCode: referenceCode,
      reason: reason,
      cashMovementId: method == PaymentMethod.cash ? 1 : null,
      paymentStatus: order.paymentStatus,
      recordedAt: DateTime.now(),
    );
    lastRefund = res;
    return res;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RevisionCatalog implements CatalogAndRecipeController {
  bool fail = false;
  bool? requestedActiveOnly;
  List<Modifier> modifiers = [];
  @override
  Future<List<MenuItem>> getMenuItems({int? categoryId, bool? activeOnly}) async {
    requestedActiveOnly = activeOnly;
    if (fail) throw StateError('Menu unavailable');
    return const [
      MenuItem(id: 101, categoryId: 1, name: 'Zinger Burger', basePrice: 500),
      MenuItem(id: 102, categoryId: 1, name: 'Fries', basePrice: 200),
    ];
  }
  @override
  Future<List<Modifier>> getModifiers({int? menuItemId, bool? activeOnly}) async => modifiers;
  @override
  Future<List<ModifierGroup>> getModifierGroups({int? menuItemId, DatabaseExecutor? executor}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CashierOrderRevisionDialog Widget Tests', () {
    const cashierId = 2;
    const shiftId = 10;
    late Order initialOrder;
    late FakeOrderController fakeOrderController;

    setUp(() {
      initialOrder = Order(
        id: 1,
        businessDayId: 1,
        shiftId: shiftId,
        cashierId: cashierId,
        tokenNumber: 1,
        diningType: DiningType.dineIn,
        subtotal: 1000.0,
        grandTotal: 1000.0,
        paymentStatus: 'SETTLED',
        tokenStatus: TokenStatus.confirmed,
        createdAt: DateTime.now(),
        currentRevision: 0,
        items: [
          OrderItem(
            id: 1,
            orderId: 1,
            menuItemId: 101,
            name: 'Zinger Burger',
            quantity: 2,
            unitPrice: 500.0,
            totalPrice: 1000.0,
            createdAt: DateTime.now(),
          ),
        ],
      );
      fakeOrderController = FakeOrderController(order: initialOrder);
    });

    Future<void> pumpRevision(WidgetTester tester, _RevisionCatalog catalog) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: CashierOrderRevisionDialog(
        order: initialOrder, cashierId: cashierId, shiftId: shiftId,
        orderController: fakeOrderController, catalogController: catalog,
      ))));
      await tester.pumpAndSettle();
    }

    testWidgets('adds a menu item absent from original order and retains its token', (tester) async {
      final catalog = _RevisionCatalog();
      await pumpRevision(tester, catalog);
      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      expect(catalog.requestedActiveOnly, isTrue);
      await tester.enterText(find.byKey(const ValueKey('revision_catalog_search')), 'fries');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('revision_catalog_item_101')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('revision_catalog_item_102')));
      await tester.pumpAndSettle();
      expect(find.text('New Total: Rs 1,200.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('apply_revision_button')));
      await tester.pumpAndSettle();
      expect(fakeOrderController.submittedItems!.map((i) => i.menuItem?.id), [101, 102]);
      expect(fakeOrderController.order.id, initialOrder.id);
      expect(fakeOrderController.order.tokenNumber, initialOrder.tokenNumber);
      expect(fakeOrderController.order.grandTotal, 1200);
    });

    testWidgets('adds a new deal using the deal choice dialog', (tester) async {
      fakeOrderController.deals = [Deal(id: 7, name: 'Burger Deal', basePrice: 700,
        createdAt: DateTime(2026), items: const [
          DealItem(id: 9, dealId: 7, groupName: 'Burger', defaultMenuItemId: 101),
        ])];
      await pumpRevision(tester, _RevisionCatalog());
      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revision_catalog_deal_7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add_deal_to_order_button')));
      await tester.pumpAndSettle();
      expect(find.text('New Total: Rs 1,700.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('apply_revision_button')));
      await tester.pumpAndSettle();
      final added = fakeOrderController.submittedItems!.last;
      expect(added.deal!.id, 7);
      expect(added.selectedDealChoices.single.menuItemId, 101);
      expect(added.selectedDealChoices.single.dealItemId, 9);
    });

    testWidgets('adding an item preserves an existing deal, upgrades and modifiers', (tester) async {
      initialOrder = Order(id: 1, businessDayId: 1, shiftId: shiftId, cashierId: cashierId,
        tokenNumber: 1, diningType: DiningType.dineIn, subtotal: 800, grandTotal: 800,
        paymentStatus: 'SETTLED', createdAt: DateTime(2026), items: [
          OrderItem(id: 1, orderId: 1, dealId: 7, name: 'Original Deal',
            quantity: 1, unitPrice: 800, totalPrice: 800, createdAt: DateTime(2026),
            modifiersJson: jsonEncode([{'id': 4, 'name': 'Cheese', 'price_delta': 50,
              'raw_ingredient_id': 3, 'ingredient_qty_delta': 1}]),
            dealChoicesJson: jsonEncode([{'deal_item_id': 9, 'group_name': 'Burger',
              'menu_item_id': 101, 'menu_item_name': 'Zinger Burger', 'upgrade_price': 100}]),
          ),
        ]);
      fakeOrderController = FakeOrderController(order: initialOrder);
      await pumpRevision(tester, _RevisionCatalog());
      expect(find.text('New Total: Rs 800.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revision_catalog_item_102')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply_revision_button')));
      await tester.pumpAndSettle();
      final original = fakeOrderController.submittedItems!.first;
      expect(original.menuItem, isNull);
      expect(original.deal!.id, 7);
      expect(original.basePrice, 650);
      expect(original.unitPrice, 800);
      expect(original.selectedModifiers.single.rawIngredientId, 3);
      expect(original.selectedDealChoices.single.upgradePrice, 100);
    });

    testWidgets('canceling picker and retrying a failed menu load leave lines intact', (tester) async {
      final catalog = _RevisionCatalog()..fail = true;
      await pumpRevision(tester, catalog);
      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Menu unavailable'), findsOneWidget);
      expect(find.text('New Total: Rs 1,000.00'), findsOneWidget);
      catalog.fail = false;
      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.text('New Total: Rs 1,000.00'), findsOneWidget);
      expect(fakeOrderController.submittedItems, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new item supports modifiers and canceling customization does not add it', (tester) async {
      final catalog = _RevisionCatalog()..modifiers = const [
        Modifier(id: 8, menuItemId: 102, name: 'Extra cheese', priceDelta: 50),
      ];
      await pumpRevision(tester, catalog);
      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revision_catalog_item_102')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New Total: Rs 1,000.00'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add_revision_items_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('revision_catalog_item_102')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('modifier_tile_8')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply_modifiers_button')));
      await tester.pumpAndSettle();
      expect(find.text('New Total: Rs 1,250.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('apply_revision_button')));
      await tester.pumpAndSettle();
      expect(fakeOrderController.submittedItems!.last.selectedModifiers.single.id, 8);
    });

    testWidgets('renders dialog with order details and stage notice without requiring PIN', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierOrderRevisionDialog(
              order: initialOrder,
              cashierId: cashierId,
              shiftId: shiftId,
              orderController: fakeOrderController,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cashier_order_revision_dialog')), findsOneWidget);
      expect(find.text('#01'), findsOneWidget);
      expect(find.textContaining('Order #${initialOrder.id} Revision'), findsOneWidget);
      expect(find.textContaining('Cashier Autonomy (No PIN)'), findsOneWidget);

      // Buttons present
      expect(find.byKey(const ValueKey('apply_revision_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel_entire_order_button')), findsOneWidget);
    });

    testWidgets('canceling order autonomously updates order and shows refund prompt', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool callbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierOrderRevisionDialog(
              order: initialOrder,
              cashierId: cashierId,
              shiftId: shiftId,
              orderController: fakeOrderController,
              onRevisionCompleted: () => callbackCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter mandatory cancellation reason
      await tester.enterText(
        find.byKey(const ValueKey('revision_reason_input')),
        'Customer changed mind',
      );
      await tester.pump();

      // Tap Cancel Entire Order
      await tester.tap(find.byKey(const ValueKey('cancel_entire_order_button')));
      await tester.pumpAndSettle();

      expect(callbackCalled, isTrue);
      expect(fakeOrderController.lastCancelReason, equals('Customer changed mind'));

      // Pending refund banner should now appear since order was cancelled and paid with cash
      expect(find.byKey(const ValueKey('pending_refund_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('disburse_cash_refund_button')), findsOneWidget);

      // Tap Cash Payout
      await tester.tap(find.byKey(const ValueKey('disburse_cash_refund_button')));
      await tester.pumpAndSettle();

      final updated = await fakeOrderController.getOrder(initialOrder.id);
      expect(updated.isCancelled, isTrue);
      expect(updated.isRefundPending, isFalse);
    });

    testWidgets('modifying item quantity and applying revision updates order with revision record', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool callbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierOrderRevisionDialog(
              order: initialOrder,
              cashierId: cashierId,
              shiftId: shiftId,
              orderController: fakeOrderController,
              onRevisionCompleted: () => callbackCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Decrement item quantity from 2 to 1
      await tester.tap(find.byKey(const ValueKey('decrement_item_0')));
      await tester.pump();

      // Enter mandatory reason
      await tester.enterText(
        find.byKey(const ValueKey('revision_reason_input')),
        'Customer changed quantity to 1',
      );
      await tester.pump();

      // Tap Apply Revision
      await tester.tap(find.byKey(const ValueKey('apply_revision_button')));
      await tester.pumpAndSettle();

      expect(callbackCalled, isTrue);
      expect(fakeOrderController.lastRevisionReason, equals('Customer changed quantity to 1'));

      // Verify updated order
      final updated = await fakeOrderController.getOrder(initialOrder.id);
      expect(updated.currentRevision, 1);
      expect(updated.items.first.quantity, 1);
      expect(updated.isRefundPending, isTrue);

      // Pending refund banner should be visible for Rs 500 delta
      expect(find.byKey(const ValueKey('pending_refund_banner')), findsOneWidget);
      expect(find.textContaining('Rs 500.00'), findsWidgets);
    });
  });
}
