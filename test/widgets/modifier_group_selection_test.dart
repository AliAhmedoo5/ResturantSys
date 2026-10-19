import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/modifier_group.dart';
import 'package:resturant_sys/widgets/orders/modifier_selection_dialog.dart';

void main() {
  const group = ModifierGroup(
    id: 10,
    menuItemId: 1,
    name: 'Patty size',
    isRequired: true,
  );
  const options = [
    Modifier(id: 1, menuItemId: 1, groupId: 10, group: group, name: 'Regular'),
    Modifier(id: 2, menuItemId: 1, groupId: 10, group: group, name: 'Large'),
  ];

  Future<void> openDialog(
    WidgetTester tester,
    ValueChanged<List<Modifier>?> onResult,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            onResult(await showDialog<List<Modifier>>(
              context: context,
              builder: (_) => const ModifierSelectionDialog(
                itemName: 'Burger',
                availableModifiers: options,
                groups: [group],
              ),
            ));
          },
          child: const Text('Customize'),
        )),
      ),
    ));
    await tester.tap(find.text('Customize'));
    await tester.pumpAndSettle();
  }

  testWidgets('single choice replaces the previous option in the applied result', (tester) async {
    List<Modifier>? result;
    await openDialog(tester, (selected) => result = selected);
    await tester.tap(find.byKey(const ValueKey('modifier_tile_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('modifier_tile_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply_modifiers_button')));
    await tester.pumpAndSettle();

    expect(find.byType(ModifierSelectionDialog), findsNothing);
    expect(result?.map((modifier) => modifier.id), [2]);
  });

  testWidgets('required group blocks empty Apply and accepts a choice after correction', (tester) async {
    var completed = false;
    List<Modifier>? result;
    await openDialog(tester, (selected) {
      completed = true;
      result = selected;
    });
    await tester.tap(find.byKey(const ValueKey('apply_modifiers_button')));
    await tester.pumpAndSettle();

    expect(completed, isFalse);
    expect(find.byType(ModifierSelectionDialog), findsOneWidget);
    expect(find.text('Patty size: choose 1 to 1 options.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('modifier_tile_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('modifier_selection_error')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('apply_modifiers_button')));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result?.map((modifier) => modifier.id), [1]);
  });
}
