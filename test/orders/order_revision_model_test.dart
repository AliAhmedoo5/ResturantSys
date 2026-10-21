import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_revision.dart';
import 'package:resturant_sys/core/orders/order_revision_line.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/procurement/wastage_reason.dart';

void main() {
  group('Order Revision Domain Models & Enums Tests', () {
    test('TokenStatus supports confirmed and outForDelivery stages', () {
      expect(TokenStatus.fromCode('CONFIRMED'), equals(TokenStatus.confirmed));
      expect(TokenStatus.fromCode('OUT_FOR_DELIVERY'), equals(TokenStatus.outForDelivery));
      expect(TokenStatus.confirmed.isConfirmed, isTrue);
      expect(TokenStatus.outForDelivery.isOutForDelivery, isTrue);
      expect(TokenStatus.confirmed.nextStatus, equals(TokenStatus.preparing));
      expect(TokenStatus.preparing.nextStatus, equals(TokenStatus.ready));
      expect(TokenStatus.ready.nextStatus, equals(TokenStatus.delivered));
    });

    test('WastageReason supports WASTED_COOKED for prep-stage removals', () {
      final reason = WastageReason.fromCode('WASTED_COOKED');
      expect(reason, equals(WastageReason.wastedCooked));
      expect(reason.code, equals('WASTED_COOKED'));
    });

    test('Order model exposes currentRevision, isCancelled, and isRefundPending', () {
      final order = Order(
        id: 10,
        businessDayId: 1,
        shiftId: 1,
        cashierId: 2,
        tokenNumber: 5,
        diningType: DiningType.dineIn,
        subtotal: 1000.0,
        grandTotal: 1000.0,
        paymentStatus: 'REFUND_PENDING',
        createdAt: DateTime.parse('2026-10-22T00:00:00Z'),
        tokenStatus: TokenStatus.confirmed,
        currentRevision: 2,
      );

      expect(order.currentRevision, equals(2));
      expect(order.isRefundPending, isTrue);
      expect(order.isCancelled, isFalse);

      final map = order.toMap();
      expect(map['current_revision'], equals(2));

      final fromMap = Order.fromMap(map);
      expect(fromMap.currentRevision, equals(2));
      expect(fromMap.tokenStatus, equals(TokenStatus.confirmed));
      expect(fromMap.isRefundPending, isTrue);
    });

    test('OrderRevision and OrderRevisionLine map serialization round-trip', () {
      final line = const OrderRevisionLine(
        id: 1,
        revisionId: 10,
        originalOrderLineId: 101,
        itemId: 5,
        action: 'REMOVE',
        oldQtyDecimal: '2',
        newQtyDecimal: '0',
        linePriceDeltaPaisa: -50000,
        bomDisposition: 'RESTOCK_RAW',
        ingredientDeltaSnapshotJson: '[{"ingredient_id":1,"qty":200.0}]',
      );

      final lineMap = line.toMap();
      expect(lineMap['bom_disposition'], equals('RESTOCK_RAW'));
      expect(lineMap['line_price_delta_paisa'], equals(-50000));

      final restoredLine = OrderRevisionLine.fromMap(lineMap);
      expect(restoredLine.bomDisposition, equals('RESTOCK_RAW'));
      expect(restoredLine.oldQtyDecimal, equals('2'));
      expect(restoredLine.newQtyDecimal, equals('0'));

      final revision = OrderRevision(
        id: 10,
        orderId: 5,
        revisionNo: 2,
        priorRevisionId: null,
        action: 'CHANGE',
        reason: 'Customer altered toppings',
        cashierId: 3,
        businessDayId: 1,
        createdAtUtc: DateTime.parse('2026-10-22T00:10:00Z'),
        oldTotalPaisa: 150000,
        newTotalPaisa: 100000,
        moneyDeltaPaisa: -50000,
        priorSnapshotJson: '{"items":[]}',
        newSnapshotJson: '{"items":[]}',
        commandId: 'CMD-REV-001',
        lines: [line],
      );

      expect(revision.isCancellation, isFalse);
      expect(revision.hasFinancialReduction, isTrue);

      final revMap = revision.toMap();
      expect(revMap['command_id'], equals('CMD-REV-001'));
      expect(revMap['money_delta_paisa'], equals(-50000));

      final restoredRev = OrderRevision.fromMap(revMap, lines: [line]);
      expect(restoredRev.commandId, equals('CMD-REV-001'));
      expect(restoredRev.lines.length, equals(1));
      expect(restoredRev.lines.first.bomDisposition, equals('RESTOCK_RAW'));
    });
  });
}
