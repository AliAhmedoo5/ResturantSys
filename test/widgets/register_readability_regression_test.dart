import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/app_header.dart';
import 'package:resturant_sys/widgets/app_sidebar.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/orders/tender_checkout_dialog.dart';
import 'package:resturant_sys/widgets/shifts/register_shift_workspace.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
}

void expectReadableBanner(WidgetTester tester, Finder text) {
  final widget = tester.widget<Text>(text);
  final container = tester.widget<Container>(find.ancestor(
    of: text,
    matching: find.byWidgetPredicate((widget) =>
        widget is Container && widget.decoration is BoxDecoration),
  ).first);
  final background = (container.decoration! as BoxDecoration).color!;
  final foreground = widget.style?.color ??
      DefaultTextStyle.of(tester.element(text)).style.color!;
  expect(contrast(foreground, background), greaterThanOrEqualTo(4.5),
      reason: 'Checkout text must be readable against its actual banner fill.');
}

Future<void> captureCheckout(WidgetTester tester, String name) async {
  if (Platform.environment['CAPTURE_DESKTOP'] != 'true') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('checkout_preview')));
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory('build/desktop-previews').create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    // Match the existing desktop-preview harness instead of painting Ahem blocks.
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true' && await font.exists()) {
      final loader = FontLoader(WarmCounterTypography.fontFamily);
      loader.addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
  });

  testWidgets('cash change and shortfall banners have readable text', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: WarmCounterTheme.darkTheme,
      home: RepaintBoundary(key: const ValueKey('checkout_preview'), child: Scaffold(body: TenderCheckoutDialog(
        grandTotal: 500, onCompleteCheckout: (_) async {},
      ))),
    ));
    for (final amount in ['500', '1000', '100']) {
      await tester.enterText(find.byKey(const ValueKey('cash_tendered_input')), amount);
      await tester.pumpAndSettle();
      expectReadableBanner(tester, find.byKey(const ValueKey('return_change_display')));
      expectReadableBanner(tester, find.text(amount == '100'
          ? 'Remaining Unpaid Balance' : 'Return Change to Customer'));
      await captureCheckout(tester, 'checkout-cash-$amount');
    }
  });

  testWidgets('split tender allocation stays readable when balanced and unbalanced', (tester) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: WarmCounterTheme.darkTheme,
      home: RepaintBoundary(key: const ValueKey('checkout_preview'), child: Scaffold(body: TenderCheckoutDialog(
        grandTotal: 500, onCompleteCheckout: (_) async {},
      ))),
    ));
    await tester.tap(find.text('Split Tender'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('split_electronic_input')), '0');
    for (final amount in ['100', '500']) {
      await tester.enterText(find.byKey(const ValueKey('split_cash_input')), amount);
      await tester.pumpAndSettle();
      expectReadableBanner(tester, find.textContaining('Total Allocated:'));
      expectReadableBanner(tester, find.text(amount == '500' ? 'Balanced' : 'Remaining: Rs 400.00'));
      await captureCheckout(tester, 'checkout-split-$amount');
    }
  });

  group('active register role and pointer behavior', () {
    late Directory directory;
    late PosDatabase database;
    late ShiftAndCashController shifts;
    late CatalogAndRecipeController catalog;
    late OrderAndCheckoutController orders;
    late Staff manager;
    late Staff cashier;

    setUpAll(sqfliteFfiInit);
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('register_readability_');
      database = PosDatabase(factory: databaseFactoryFfi,
          customPath: '${directory.path}/fixture.db');
      final db = await database.initialize();
      final auth = AuthService(database: db);
      manager = (await auth.authenticateWithPin('1234'))!;
      cashier = (await auth.authenticateWithPin('1111'))!;
      shifts = ShiftAndCashController(database: db);
      catalog = CatalogAndRecipeController(database: db);
      orders = OrderAndCheckoutController(database: db);
      await shifts.openBusinessDay(openedByStaffId: manager.id);
      await shifts.openShift(staffId: cashier.id, openingFloat: 5000);
    });
    tearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    Future<void> mount(WidgetTester tester, Staff staff) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          theme: WarmCounterTheme.darkTheme,
          home: Scaffold(body: RegisterShiftWorkspace(
            controller: shifts, currentStaff: staff,
            orderController: orders, catalogController: catalog,
          )),
        ));
        for (var attempt = 0; attempt < 500; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.text('Loading POS Workspace...').evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
        fail('Register did not finish loading.');
      });
      await tester.pumpAndSettle();
    }

    testWidgets('manager sees shift details without an unusable billing toggle', (tester) async {
      await mount(tester, manager);
      expect(find.textContaining('Shift #1 Active'), findsOneWidget);
      expect(find.text('View Shift Details & Drawer Movements'), findsNothing);
      expect(find.text('Switch to Counter Billing Grid'), findsNothing);
      expect(find.byType(CounterBillingWorkspace), findsNothing);
    });

    testWidgets('cashier switches between billing and shift details', (tester) async {
      await mount(tester, cashier);
      expect(find.byType(CounterBillingWorkspace), findsOneWidget);
      await tester.tap(find.text('View Shift Details & Drawer Movements'));
      await tester.pumpAndSettle();
      expect(find.byType(CounterBillingWorkspace), findsNothing);
      expect(find.text('Recent Drawer Cash Movements'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Switch to Counter Billing Grid'));
        for (var attempt = 0; attempt < 500; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            return;
          }
        }
        fail('Billing did not finish reloading.');
      });
      await tester.pumpAndSettle();
      expect(find.byType(CounterBillingWorkspace), findsOneWidget);
      expect(find.text('Recent Drawer Cash Movements'), findsNothing);
    });

    testWidgets('sidebar and enabled actions show a hand pointer', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: WarmCounterTheme.darkTheme,
        home: Scaffold(body: Row(children: [
          AppSidebar(staff: manager, selected: AppWorkspaceTab.register,
              onSelected: (_) {}),
          Expanded(child: Column(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton(onPressed: () {}, child: const Text('Action')),
            FilledButton(onPressed: () {}, child: const Text('Filled action')),
            OutlinedButton(onPressed: () {}, child: const Text('Outline')),
            TextButton(onPressed: () {}, child: const Text('Text action')),
            IconButton(key: const ValueKey('icon_action'), onPressed: () {}, icon: const Icon(Icons.add)),
            Checkbox(key: const ValueKey('checkbox_action'), value: false, onChanged: (_) {}),
            Switch(key: const ValueKey('switch_action'), value: false, onChanged: (_) {}),
            ListTile(title: const Text('List action'), onTap: () {}),
            const ElevatedButton(onPressed: null, child: Text('Disabled')),
            const TextField(key: ValueKey('text_input')),
          ])),
        ])),
      ));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      for (final target in [
        find.byKey(const ValueKey('workspace_tab_register')), find.text('Action'),
        find.text('Filled action'), find.text('Outline'), find.text('Text action'),
        find.byKey(const ValueKey('icon_action')),
        find.byKey(const ValueKey('checkbox_action')), find.byKey(const ValueKey('switch_action')),
        find.text('List action'),
      ]) {
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump();
        expect(tester.binding.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click,
            reason: 'The enabled control at ${tester.getCenter(target)} must show a hand.');
      }
      await mouse.moveTo(tester.getCenter(find.text('Disabled')));
      await tester.pump();
      expect(tester.binding.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('text_input'))));
      await tester.pump();
      expect(tester.binding.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });
}
