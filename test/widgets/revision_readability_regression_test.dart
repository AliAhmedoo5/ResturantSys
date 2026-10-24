import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order.dart';
import 'package:resturant_sys/core/orders/order_item.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/cashier_order_revision_dialog.dart';
import 'cashier_order_revision_dialog_test.dart' show FakeOrderController;

void main() {
  testWidgets('revision item text is readable against its actual dark-theme surface', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final order = Order(id: 10, businessDayId: 1, shiftId: 1, cashierId: 2,
      tokenNumber: 1, diningType: DiningType.dineIn, subtotal: 333, grandTotal: 333,
      paymentStatus: 'SETTLED', createdAt: DateTime(2026), items: [
        OrderItem(id: 1, orderId: 10, menuItemId: 1, name: 'Zinger',
          quantity: 1, unitPrice: 333, totalPrice: 333, createdAt: DateTime(2026)),
      ]);
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: Scaffold(body: CashierOrderRevisionDialog(order: order, cashierId: 2,
        shiftId: 1, orderController: FakeOrderController(order: order)))));
    await tester.pumpAndSettle();
    final title = find.text('Zinger');
    final panel = tester.widgetList<Container>(find.ancestor(of: title,
      matching: find.byType(Container))).firstWhere((c) =>
        c.decoration is BoxDecoration && (c.decoration as BoxDecoration).color != null);
    final background = (panel.decoration as BoxDecoration).color!;
    for (final text in ['Zinger', 'Rs 333.00 each', 'Rs 333.00']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
      final foreground = paragraph.text.style!.color!;
      final a = foreground.computeLuminance();
      final b = background.computeLuminance();
      final contrast = ((a > b ? a : b) + 0.05) / ((a > b ? b : a) + 0.05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: '$text must remain readable in the item editor.');
    }
  });
}
