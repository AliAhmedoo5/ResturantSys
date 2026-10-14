import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/procurement/quick_mandi_purchase_dialog.dart';
import 'package:resturant_sys/widgets/procurement/quick_mandi_purchase_workspace.dart';

void main() {
  group('QuickMandiPurchaseWorkspace Widget Tests', () {
    testWidgets('renders all traditional units and auto-calculates recipe unit cost live', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const onion = RawIngredient(
        id: 1,
        name: 'Red Onions',
        storageUnit: StorageUnit.g,
        currentStock: 10000.0,
        lowStockThreshold: 2000.0,
        costPerRecipeUnit: 0.08,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: const Scaffold(
            body: QuickMandiPurchaseWorkspace(
              initialIngredients: [onion],
              initialProcurements: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Form header and widgets
      expect(find.text('Quick Desi Mandi Purchase'), findsOneWidget);
      expect(find.byKey(const ValueKey('mandi_ingredient_dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('mandi_unit_dropdown')), findsOneWidget);
      expect(find.byKey(const ValueKey('mandi_quantity_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('mandi_total_cost_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm_mandi_purchase_button')), findsOneWidget);

      // Default unit is Mann, default quantity is 1
      // 1 Mann = 40,000 g
      expect(find.text('+40,000 g'), findsOneWidget);

      // Enter total cost of Rs. 4,000
      await tester.enterText(find.byKey(const ValueKey('mandi_total_cost_input')), '4000');
      await tester.pumpAndSettle();

      // Unit cost: 4000 / 40000 = Rs. 0.10 / g
      expect(find.text('Rs. 0.10 / g'), findsOneWidget);

      // Change quantity to 2 Mann (80,000 g)
      await tester.enterText(find.byKey(const ValueKey('mandi_quantity_input')), '2');
      await tester.pumpAndSettle();

      // 2 Mann = 80,000 g
      expect(find.text('+80,000 g'), findsOneWidget);
      // Unit cost: 4000 / 80000 = Rs. 0.05 / g
      expect(find.text('Rs. 0.05 / g'), findsOneWidget);

      // Switch traditional unit to Dharri (5 kg = 5,000 g)
      await tester.tap(find.byKey(const ValueKey('mandi_unit_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dharri (دھڑی) [5 kg]').last);
      await tester.pumpAndSettle();

      // 2 Dharri = 10,000 g
      expect(find.text('+10,000 g'), findsOneWidget);
      // Unit cost: 4000 / 10000 = Rs. 0.40 / g
      expect(find.text('Rs. 0.40 / g'), findsOneWidget);

      // Submit purchase
      await tester.tap(find.byKey(const ValueKey('confirm_mandi_purchase_button')));
      await tester.pumpAndSettle();

      // Verify SnackBar confirmation and added procurement
      expect(find.textContaining('Recorded 2.0 Dharri (دھڑی) of Red Onions for Rs. 4,000.00'), findsOneWidget);
      // Stock increased from 10,000 to 20,000
      expect(find.text('20,000 g'), findsOneWidget);
    });

    testWidgets('QuickMandiPurchaseDialog renders and closes correctly', (tester) async {
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
                  key: const ValueKey('open_dialog_button'),
                  onPressed: () {
                    showDialog<void>(
                      context: ctx,
                      builder: (_) => const QuickMandiPurchaseDialog(
                        initialIngredients: [
                          RawIngredient(
                            id: 2,
                            name: 'Basmati Rice',
                            storageUnit: StorageUnit.kg,
                            currentStock: 50.0,
                            lowStockThreshold: 10.0,
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

      await tester.tap(find.byKey(const ValueKey('open_dialog_button')));
      await tester.pumpAndSettle();

      expect(find.text('Quick Mandi Purchase'), findsWidgets);
      expect(find.byKey(const ValueKey('confirm_mandi_purchase_button')), findsOneWidget);

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('confirm_mandi_purchase_button')), findsNothing);
    });
  });
}
