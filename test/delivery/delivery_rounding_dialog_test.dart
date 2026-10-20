import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/widgets/orders/tender_checkout_dialog.dart';

void main() {
  testWidgets('Rounded-down cash is paid and split retains a zero rounded cash leg', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<PaymentTender>? paid;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => showDialog<void>(context: context, builder: (_) => TenderCheckoutDialog(
        grandTotal: 575.49, roundPhysicalCash: true, onCompleteCheckout: (tenders) async => paid = tenders)), child: const Text('Pay'))))));
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Remaining Unpaid Balance'), findsNothing);
    expect(find.text('Return Change to Customer'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tender_tab_split')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('split_cash_input')), '0');
    await tester.enterText(find.byKey(const ValueKey('split_electronic_input')), '575');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('commit_checkout_button')));
    await tester.pumpAndSettle();
    expect(paid!.where((p) => p.method == PaymentMethod.cash).single.amountTendered, 0);
    expect(paid!.where((p) => p.method == PaymentMethod.raast).single.amountTendered, 575);
  });
}
