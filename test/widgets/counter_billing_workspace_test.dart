import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/orders/deal.dart';
import 'package:resturant_sys/core/orders/deal_item.dart';
import 'package:resturant_sys/core/orders/deal_item_option.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/orders/counter_billing_workspace.dart';
import 'package:resturant_sys/widgets/orders/deal_selection_dialog.dart';
import 'package:resturant_sys/widgets/orders/modifier_selection_dialog.dart';
import 'package:resturant_sys/widgets/orders/reprint_tray_dialog.dart';
import 'package:resturant_sys/widgets/orders/tender_checkout_dialog.dart';

void main() {
  group('CounterBillingWorkspace Widget Tests', () {
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
      const MenuCategory(id: 1, name: 'Burgers', displayOrder: 1, colorHex: '#E53935'),
      const MenuCategory(id: 2, name: 'Beverages', displayOrder: 2, colorHex: '#00897B'),
    ];

    final testMenuItems = [
      const MenuItem(
        id: 101,
        categoryId: 1,
        categoryName: 'Burgers',
        name: 'Zinger Burger',
        basePrice: 550.0,
      ),
      const MenuItem(
        id: 102,
        categoryId: 1,
        categoryName: 'Burgers',
        name: 'Beef Smash',
        basePrice: 650.0,
      ),
      const MenuItem(
        id: 201,
        categoryId: 2,
        categoryName: 'Beverages',
        name: 'Cola Can',
        basePrice: 120.0,
      ),
    ];

    final testDeals = [
      Deal(
        id: 1,
        name: 'Zinger Feast Deal',
        basePrice: 850.0,
        createdAt: DateTime(2026, 10, 12),
        items: const [
          DealItem(
            id: 1,
            dealId: 1,
            groupName: 'Main Burger',
            defaultMenuItemId: 101,
            defaultMenuItemName: 'Zinger Burger',
          ),
          DealItem(
            id: 2,
            dealId: 1,
            groupName: 'Beverage Choice',
            defaultMenuItemId: 201,
            options: [
              DealItemOption(
                id: 1,
                dealItemId: 2,
                menuItemId: 201,
                menuItemName: 'Cola Regular',
                isDefault: true,
                upgradePrice: 0.0,
              ),
              DealItemOption(
                id: 2,
                dealItemId: 2,
                menuItemId: 201,
                menuItemName: 'Cola Jumbo',
                isDefault: false,
                upgradePrice: 60.0,
              ),
            ],
          ),
        ],
      ),
    ];

    final testDiscounts = [
      const DiscountPreset(
        id: 1,
        name: 'Staff 20%',
        type: DiscountType.percentage,
        value: 20.0,
        isActive: true,
      ),
      const DiscountPreset(
        id: 2,
        name: 'Promo Rs 100',
        type: DiscountType.flat,
        value: 100.0,
        isActive: true,
      ),
    ];

    final testModifiers = [
      const Modifier(
        id: 1,
        menuItemId: 101,
        name: '+Extra Cheese',
        priceDelta: 60.0,
        ingredientQtyDelta: 1.0,
      ),
      const Modifier(
        id: 2,
        menuItemId: 101,
        name: 'No Mayo',
        priceDelta: 0.0,
        ingredientQtyDelta: 0.0,
      ),
    ];

    Widget buildTestHarness() {
      return MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(
          body: CounterBillingWorkspace(
            currentStaff: testStaff,
            businessDayId: 1,
            shiftId: 1,
            initialCategories: testCategories,
            initialMenuItems: testMenuItems,
            initialDeals: testDeals,
            initialDiscounts: testDiscounts,
            initialModifiers: testModifiers,
            initialNextTokenNumber: 3,
          ),
        ),
      );
    }

    testWidgets('renders category tabs, menu items, token preview, and dining selector', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Token preview #03
      expect(find.text('Token #03'), findsOneWidget);

      // Dining types
      expect(find.byKey(const ValueKey('dining_type_DINE_IN')), findsOneWidget);
      expect(find.byKey(const ValueKey('dining_type_TAKEAWAY')), findsOneWidget);
      expect(find.byKey(const ValueKey('dining_type_DELIVERY')), findsOneWidget);

      // Categories and Deals tab
      expect(find.byKey(const ValueKey('category_tab_deals')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_tab_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_tab_2')), findsOneWidget);

      // Default selected category is Burgers (id: 1)
      expect(find.text('Zinger Burger'), findsOneWidget);
      expect(find.text('Beef Smash'), findsOneWidget);

      // Cart is initially empty
      expect(find.textContaining('Cart is empty'), findsOneWidget);
      expect(find.byKey(const ValueKey('proceed_to_tender_button')), findsOneWidget);
    });

    testWidgets('tap on menu item adds to cart and updates subtotal & grand total', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Tap Zinger Burger (Rs 550.00)
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_101')));
      await tester.pumpAndSettle();

      // Should now be in cart
      expect(find.textContaining('Cart is empty'), findsNothing);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Rs 550.00'), findsWidgets);

      // Tap Zinger Burger again to increment quantity to 2
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_101')));
      await tester.pumpAndSettle();

      expect(find.text('Rs 1,100.00'), findsWidgets);

      // Switch to Beverages tab (id: 2)
      await tester.tap(find.byKey(const ValueKey('category_tab_2')));
      await tester.pumpAndSettle();

      expect(find.text('Cola Can'), findsOneWidget);

      // Add Cola Can (Rs 120.00) -> 1100 + 120 = 1220.00
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_201')));
      await tester.pumpAndSettle();

      expect(find.text('Rs 1,220.00'), findsWidgets);
    });

    testWidgets('1-tap pre-approved discount applies without PIN and updates grand total', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Add Beef Smash (Rs 650.00)
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_102')));
      await tester.pumpAndSettle();

      // Apply Promo Rs 100 discount preset
      expect(find.byKey(const ValueKey('discount_chip_2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('discount_chip_2')));
      await tester.pumpAndSettle();

      // Subtotal = 650, Discount = 100, Grand Total = 550
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('-Rs 100.00'), findsOneWidget);
      expect(find.text('Rs 550.00'), findsWidgets);

      // Switch to Staff 20% discount (20% of 650 = 130) -> Grand Total = 520
      await tester.tap(find.byKey(const ValueKey('discount_chip_1')));
      await tester.pumpAndSettle();

      expect(find.text('-Rs 130.00'), findsOneWidget);
      expect(find.text('Rs 520.00'), findsWidgets);
    });

    testWidgets('dining type selector toggles Takeaway and Delivery', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestHarness());
      await tester.pumpAndSettle();

      // Initially Dine-In
      expect(find.text('Dine-In'), findsWidgets);

      // Tap Takeaway
      await tester.tap(find.byKey(const ValueKey('dining_type_TAKEAWAY')));
      await tester.pumpAndSettle();
      expect(find.text('Takeaway'), findsWidgets);

      // Tap Delivery
      await tester.tap(find.byKey(const ValueKey('dining_type_DELIVERY')));
      await tester.pumpAndSettle();
      expect(find.text('Delivery'), findsWidgets);
    });

    testWidgets('deal choice modal opens and dynamic upgrade updates package price', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: DealSelectionDialog(
              deal: testDeals.first,
              availableMenuItems: testMenuItems,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zinger Feast Deal'), findsOneWidget);
      expect(find.text('Base Price: Rs 850.00'), findsOneWidget);
      expect(find.text('Beverage Choice'), findsOneWidget);

      // Select upgrade: Cola Jumbo (+Rs 60.00) -> total package price = 850 + 60 = 910.00
      expect(find.byKey(const ValueKey('deal_opt_2_2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('deal_opt_2_2')));
      await tester.pumpAndSettle();

      expect(find.text('Rs 910.00'), findsOneWidget);
    });

    testWidgets('modifiers selection modal allows selecting add-ons and removals', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: ModifierSelectionDialog(
              itemName: 'Zinger Burger',
              availableModifiers: testModifiers,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Customize: Zinger Burger'), findsOneWidget);
      expect(find.text('+Extra Cheese'), findsOneWidget);
      expect(find.text('No Mayo'), findsOneWidget);

      // Toggle +Extra Cheese
      await tester.tap(find.byKey(const ValueKey('modifier_tile_1')));
      await tester.pumpAndSettle();

      // Toggle No Mayo
      await tester.tap(find.byKey(const ValueKey('modifier_tile_2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('apply_modifiers_button')), findsOneWidget);
    });

    testWidgets('tender dialog calculates return change in large numerals for cash payment', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: TenderCheckoutDialog(
              grandTotal: 650.0,
              onCompleteCheckout: (tenders) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order Checkout & Tender'), findsOneWidget);
      expect(find.text('Grand Total Payable:'), findsOneWidget);
      expect(find.text('Rs 650.00'), findsWidgets);

      // Enter 1000 cash tendered
      await tester.enterText(find.byKey(const ValueKey('cash_tendered_input')), '1000');
      await tester.pumpAndSettle();

      // Return change: 1000 - 650 = 350.00
      expect(find.text('Return Change to Customer'), findsOneWidget);
      expect(find.text('Rs 350.00'), findsOneWidget);

      // Enter 600 (less than 650) -> shows unpaid balance
      await tester.enterText(find.byKey(const ValueKey('cash_tendered_input')), '600');
      await tester.pumpAndSettle();

      expect(find.text('Remaining Unpaid Balance'), findsOneWidget);
      expect(find.text('Rs 50.00'), findsOneWidget);
    });

    testWidgets('shows Reprint Tray button and opens ReprintTrayDialog when tapped', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final adapter = InMemoryHardwareAdapter();
      final reprintTray = ReprintTrayController(hardwareAdapter: adapter);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: CounterBillingWorkspace(
              currentStaff: testStaff,
              businessDayId: 1,
              shiftId: 1,
              reprintTrayController: reprintTray,
              initialCategories: testCategories,
              initialMenuItems: testMenuItems,
              initialDeals: testDeals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('open_reprint_tray_button')), findsOneWidget);
      expect(find.text('Reprint Tray'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open_reprint_tray_button')));
      await tester.pumpAndSettle();

      expect(find.byType(ReprintTrayDialog), findsOneWidget);
      expect(find.text('Hardware & Reprint Tray'), findsOneWidget);
    });

    testWidgets('renders primary thumbnail when image exists and falls back to placeholder with 0 images', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Create a temporary valid image file on disk
      final tempDir = await Directory.systemTemp.createTemp('cashier_image_test_');
      final validImgFile = File('${tempDir.path}${Platform.pathSeparator}zinger.png');
      await validImgFile.writeAsBytes([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
        0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
        0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: CounterBillingWorkspace(
              currentStaff: testStaff,
              businessDayId: 1,
              shiftId: 1,
              initialCategories: testCategories,
              initialMenuItems: testMenuItems,
              initialDeals: testDeals,
              initialMenuItemImages: {
                101: validImgFile.path, // Zinger burger has image
                // 102 (Beef Smash) has 0 images
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zinger Burger has an Image widget
      final zingerTile = find.byKey(const ValueKey('menu_item_tile_101'));
      expect(find.descendant(of: zingerTile, matching: find.byType(Image)), findsOneWidget);

      // Beef Smash has placeholder icon
      final beefTile = find.byKey(const ValueKey('menu_item_tile_102'));
      expect(find.descendant(of: beefTile, matching: find.byIcon(Icons.restaurant_outlined)), findsOneWidget);

      // Both items are functional: tap Zinger Burger then Beef Smash
      await tester.tap(zingerTile);
      await tester.pumpAndSettle();
      await tester.tap(beefTile);
      await tester.pumpAndSettle();

      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Rs 1,200.00'), findsWidgets); // 550 + 650

      await tempDir.delete(recursive: true);
    });

    testWidgets('gracefully handles missing or corrupted image paths without crashing UI', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: CounterBillingWorkspace(
              currentStaff: testStaff,
              businessDayId: 1,
              shiftId: 1,
              initialCategories: testCategories,
              initialMenuItems: testMenuItems,
              initialDeals: testDeals,
              initialMenuItemImages: const {
                101: r'C:\non_existent_directory\corrupted_photo.jpg',
                102: r'C:\invalid_path\missing.png',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // UI renders cleanly without crashing
      expect(find.text('Zinger Burger'), findsOneWidget);
      expect(find.text('Beef Smash'), findsOneWidget);

      // Fallback placeholder icons are displayed
      expect(find.byIcon(Icons.restaurant_outlined), findsAtLeastNWidgets(2));

      // Items still tap-add to cart normally
      await tester.tap(find.byKey(const ValueKey('menu_item_tile_101')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Cart is empty'), findsNothing);
      expect(find.text('Rs 550.00'), findsWidgets);
    });
  });
}
