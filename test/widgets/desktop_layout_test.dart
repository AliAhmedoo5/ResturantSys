import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/department.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/app_shell.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/supervisor/supervisor_portal_workspace.dart';

const cashier = Staff(id: 1, name: 'Counter Cashier', departmentId: 1,
    departmentName: 'Front Counter', pinHash: 'unused', role: StaffRole.cashier, isActive: true);
const manager = Staff(id: 2, name: 'Restaurant Manager', departmentId: 2,
    departmentName: 'Management', pinHash: 'unused', role: StaffRole.manager, isActive: true);
const categories = [MenuCategory(id: 1, name: 'Burgers', displayOrder: 0, colorHex: '#FFC400')];
const menu = [
  MenuItem(id: 1, categoryId: 1, name: 'Classic Burger', basePrice: 350),
  MenuItem(id: 2, categoryId: 1, name: 'Chicken Burger', basePrice: 450),
  MenuItem(id: 3, categoryId: 1, name: 'Double Smash', basePrice: 650),
];

Widget counter() => const CounterBillingWorkspace(currentStaff: cashier,
  businessDayId: 1, shiftId: 1, initialCategories: categories, initialMenuItems: menu);

Future<void> pumpDesktop(WidgetTester tester, Size physicalSize, double scale,
    {Staff? staff, Widget? child}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = SessionState();
  if (staff != null) session.login(staff);
  addTearDown(session.dispose);
  await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
    home: RepaintBoundary(key: const ValueKey('desktop_preview'), child: AppShell(
      session: session, onAuthenticatePin: (_) async => null, child: child,
    )),
  ));
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: '$name must fit without layout errors');
  if (Platform.environment['CAPTURE_DESKTOP'] != 'true') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('desktop_preview')));
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
    // CI-only preview font. Production continues to use the system font fallback.
    final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true' && await file.exists()) {
      final loader = FontLoader(WarmCounterTypography.fontFamily);
      loader.addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });

  for (final viewport in [
    (name: 'desktop', size: const Size(1366, 768), scale: 1.0),
    (name: 'scaled-150', size: const Size(1920, 972), scale: 1.5),
    (name: 'compact', size: const Size(1024, 700), scale: 1.0),
  ]) {
    testWidgets('login fits ${viewport.name}', (tester) async {
      await pumpDesktop(tester, viewport.size, viewport.scale);
      final card = tester.getRect(find.byKey(const ValueKey('login_card')));
      expect(card.width, lessThanOrEqualTo(400));
      expect(find.text('9').hitTestable(), findsOneWidget);
      expect(find.text('0').hitTestable(), findsOneWidget);
      await capture(tester, 'login-${viewport.name}');
    });

    testWidgets('cashier cart remains pinned at ${viewport.name}', (tester) async {
      await pumpDesktop(tester, viewport.size, viewport.scale, staff: cashier, child: counter());
      expect(find.byKey(const ValueKey('workspace_tab_catalog')), findsNothing);
      final charge = find.byKey(const ValueKey('proceed_to_tender_button'));
      final before = tester.getRect(charge);
      expect(charge.hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_1')));
      await tester.pumpAndSettle();
      expect(tester.getRect(charge), before);
      expect(tester.widget<ElevatedButton>(charge).onPressed, isNotNull);
      await capture(tester, 'pos-${viewport.name}');
    });

    testWidgets('manager navigation and staff table fit ${viewport.name}', (tester) async {
      await pumpDesktop(tester, viewport.size, viewport.scale, staff: manager,
        child: SupervisorPortalWorkspace(
          initialDepartments: [Department(id: 1, name: 'Front Counter', createdAt: DateTime(2026))],
          initialStaff: const [cashier, manager],
        ));
      await tester.tap(find.byKey(const ValueKey('workspace_tab_supervisor')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('register_staff_button')).hitTestable(), findsOneWidget);
      await capture(tester, 'management-${viewport.name}');
    });
  }

  testWidgets('menu search filters and clears without changing the cart', (tester) async {
    await pumpDesktop(tester, const Size(1366, 768), 1, staff: cashier, child: counter());
    await tester.tap(find.byKey(const ValueKey('menu_item_tile_1')));
    final search = find.byKey(const ValueKey('catalog_search'));
    await tester.enterText(search, 'chicken');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_tile_1')), findsNothing);
    expect(find.byKey(const ValueKey('menu_item_tile_2')), findsOneWidget);
    expect(find.text('Classic Burger'), findsOneWidget); // Existing cart item.
    await tester.enterText(search, 'no match');
    await tester.pumpAndSettle();
    expect(find.text('No items match your search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('menu_item_tile_1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
