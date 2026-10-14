import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/procurement/kitchen_wastage_dialog.dart';
import 'package:resturant_sys/widgets/procurement/kitchen_wastage_workspace.dart';

void main() {
  group('KitchenWastageWorkspace Widget Tests', () {
    testWidgets('renders wastage form, enforces mandatory reason, and calculates financial cost loss live', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const chicken = RawIngredient(
        id: 1,
        name: 'Chicken Fillet',
        storageUnit: StorageUnit.g,
        currentStock: 15000.0,
        lowStockThreshold: 3000.0,
        costPerRecipeUnit: 0.90, // Rs. 0.90 / g
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: KitchenWastageWorkspace(
              initialIngredients: [chicken],
              initialWastageLogs: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify form elements
      expect(find.text('Kitchen Wastage Log'), findsOneWidget);
      expect(find.byKey(const ValueKey('wastage_ingredient_dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('wastage_quantity_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('wastage_reason_dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('wastage_pin_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm_kitchen_wastage_button')), findsOneWidget);

      // Initial financial loss display is 0.00
      expect(find.text('Rs. 0.00'), findsWidgets);

      // Enter 500g wasted quantity
      await tester.enterText(find.byKey(const ValueKey('wastage_quantity_input')), '500');
      await tester.pumpAndSettle();

      // Cost Loss: 500 * 0.90 = Rs. 450.00
      expect(find.text('Rs. 450.00'), findsOneWidget);
      expect(find.text('-500 g'), findsOneWidget);

      // Select mandatory reason: Dropped / Contaminated
      await tester.tap(find.byKey(const ValueKey('wastage_reason_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dropped / Contaminated').last);
      await tester.pumpAndSettle();

      // Enter valid Staff PIN (1234)
      await tester.enterText(find.byKey(const ValueKey('wastage_pin_input')), '1234');
      await tester.pumpAndSettle();

      // Tap confirm button
      await tester.tap(find.byKey(const ValueKey('confirm_kitchen_wastage_button')));
      await tester.pumpAndSettle();

      // Verify SnackBar confirmation and updated stock
      expect(find.textContaining('Logged 500 g wastage (Dropped / Contaminated) — Cost Loss: Rs. 450.00'), findsOneWidget);
      // Stock deducted from 15,000 to 14,500
      expect(find.text('14,500 g'), findsOneWidget);
      // Total wastage loss summary updated to Rs. 450.00
      expect(find.byKey(const ValueKey('total_wastage_loss_summary')), findsOneWidget);
    });

    testWidgets('KitchenWastageDialog renders and closes correctly', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_wastage_dialog_button'),
                  onPressed: () {
                    showDialog<void>(
                      context: ctx,
                      builder: (_) => const KitchenWastageDialog(
                        initialIngredients: [
                          RawIngredient(
                            id: 3,
                            name: 'Milk',
                            storageUnit: StorageUnit.ml,
                            currentStock: 10000.0,
                            lowStockThreshold: 1000.0,
                            costPerRecipeUnit: 0.20,
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_wastage_dialog_button')));
      await tester.pumpAndSettle();

      expect(find.text('Kitchen Wastage Log'), findsWidgets);
      expect(find.byKey(const ValueKey('confirm_kitchen_wastage_button')), findsOneWidget);

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('confirm_kitchen_wastage_button')), findsNothing);
    });
  });
}
