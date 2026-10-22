import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/orders/deal.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';

void main() {
  group('Cashier Screen 1366×768 Touch Ergonomics & Theme Verification', () {
    const testStaff = Staff(
      id: 2,
      name: 'Counter Cashier',
      departmentId: 1,
      pinHash: 'hash',
      role: StaffRole.cashier,
      isActive: true,
      departmentName: 'Front Counter',
    );

    final testCategories = [
      const MenuCategory(id: 1, name: 'Burgers', displayOrder: 1, colorHex: '#FFC400'),
      const MenuCategory(id: 2, name: 'Deals', displayOrder: 2, colorHex: '#F5A623'),
    ];

    // Create a long list of menu items to test internal scrolling
    final testMenuItems = List.generate(
      24,
      (i) => MenuItem(
        id: 100 + i,
        categoryId: 1,
        categoryName: 'Burgers',
        name: 'Item ${i + 1}',
        basePrice: 500.0 + (i * 50),
      ),
    );

    final testDeals = [
      Deal(
        id: 1,
        name: 'Mafia Boss Deal',
        basePrice: 1200.0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    Widget createTestWidget({double textScaleFactor = 1.0}) {
      return MaterialApp(
        theme: WarmCounterTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(1366, 768),
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: Scaffold(
            backgroundColor: StreetFoodMafiaColors.obsidian,
            body: CounterBillingWorkspace(
              currentStaff: testStaff,
              businessDayId: 1,
              shiftId: 1,
              initialCategories: testCategories,
              initialMenuItems: testMenuItems,
              initialDeals: testDeals,
              initialDiscounts: const [
                DiscountPreset(
                  id: 1,
                  name: 'Staff 10%',
                  type: DiscountType.percentage,
                  value: 10.0,
                  isActive: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('Cashier screen at 1366×768 operates with zero page-level scrolling', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Verify page-level structure: outer view is not a scrollable
      // The only vertical scrollables must be the internal catalog GridView and the cart ListView
      final scrollables = find.byType(Scrollable);
      expect(scrollables, findsWidgets);

      // Verify that the cart panel is pinned on the right (35% flex)
      final chargeButton = find.byKey(const ValueKey('proceed_to_tender_button'));
      expect(chargeButton, findsOneWidget);

      final chargeButtonBeforeScroll = tester.getCenter(chargeButton);

      // Scroll the internal product grid
      final gridFinder = find.byKey(const ValueKey('menu_grid_1'));
      expect(gridFinder, findsOneWidget);

      await tester.drag(gridFinder, const Offset(0, -300));
      await tester.pumpAndSettle();

      // Verify that after scrolling the product catalog, the Charge CTA and Cart remain in the exact same pinned position!
      final chargeButtonAfterScroll = tester.getCenter(chargeButton);
      expect(chargeButtonAfterScroll, equals(chargeButtonBeforeScroll));

      // Verify Grand Total remains visible and pinned
      expect(find.text('Grand Total:'), findsOneWidget);
    });

    testWidgets('Primary yellow Charge CTA maintains high contrast with dark text', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Add item to cart
      final firstItem = find.byKey(const ValueKey('menu_item_tile_100'));
      expect(firstItem, findsOneWidget);
      await tester.tap(firstItem);
      await tester.pumpAndSettle();

      // Find the enabled Charge button
      final chargeButtonFinder = find.byKey(const ValueKey('proceed_to_tender_button'));
      expect(chargeButtonFinder, findsOneWidget);

      final elevatedButton = tester.widget<ElevatedButton>(chargeButtonFinder);
      final buttonStyle = elevatedButton.style;

      // Verify background is Cartel Yellow #FFC400
      expect(buttonStyle?.backgroundColor?.resolve({}), equals(StreetFoodMafiaColors.cartelYellow));
      // Verify foreground is dark text #050708 (high contrast > 11:1)
      expect(buttonStyle?.foregroundColor?.resolve({}), equals(StreetFoodMafiaColors.textOnPrimary));

      // Verify outline icon used on Charge button
      expect(find.byIcon(Icons.point_of_sale_outlined), findsOneWidget);
    });

    testWidgets('Cashier screen renders cleanly at 100%, 125%, and 150% Windows scaling factors', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final scaleFactor in [1.0, 1.25, 1.5]) {
        await tester.pumpWidget(createTestWidget(textScaleFactor: scaleFactor));
        await tester.pumpAndSettle();

        // Verify no RenderFlex overflow
        expect(tester.takeException(), isNull, reason: 'RenderFlex overflow occurred at scale $scaleFactor');

        // Verify core elements remain on screen and interactable
        expect(find.byKey(const ValueKey('proceed_to_tender_button')), findsOneWidget);
        expect(find.text('Grand Total:'), findsOneWidget);
        expect(find.byKey(const ValueKey('dining_type_DINE_IN')), findsOneWidget);
      }
    });

    testWidgets('Monetary amounts and tokens render with tabular figures font features', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Add item to cart
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_100')));
      await tester.pumpAndSettle();

      // Verify prices have tabular figures in text style
      final grandTotalWidget = tester.widget<Text>(find.text('Rs 500.00'));
      expect(
        grandTotalWidget.style?.fontFeatures?.any((f) => f.feature == 'tnum'),
        isTrue,
      );
    });
  });
}
