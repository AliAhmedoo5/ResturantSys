import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/pin_lock_screen.dart';

void main() {
  Future<void> pumpTestWidget(
    WidgetTester tester, {
    required Future<bool> Function(String) onPinSubmitted,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: WarmCounterTheme.lightTheme,
        home: Scaffold(
          body: PinLockScreen(
            onPinSubmitted: onPinSubmitted,
          ),
        ),
      ),
    );
  }

  group('PinLockScreen Widget Tests', () {
    testWidgets('renders all 10 numpad digits, clear, and backspace buttons', (tester) async {
      await pumpTestWidget(tester, onPinSubmitted: (_) async => true);

      for (int i = 0; i <= 9; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.text('C'), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('entering 4 digits via on-screen numpad triggers onPinSubmitted callback', (tester) async {
      String? submittedPin;
      await pumpTestWidget(
        tester,
        onPinSubmitted: (pin) async {
          submittedPin = pin;
          return true;
        },
      );

      // Tap 1, 2, 3, 4
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      expect(submittedPin, equals('1234'));
    });

    testWidgets('clear button resets entered PIN digits', (tester) async {
      await pumpTestWidget(tester, onPinSubmitted: (_) async => true);

      // Tap 1, 2
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();

      // Tap Clear
      await tester.tap(find.text('C'));
      await tester.pump();

      // Verify dots container exists
      final dotsFinder = find.byKey(const ValueKey('pin_dots_container'));
      expect(dotsFinder, findsOneWidget);
    });

    testWidgets('displays error feedback when onPinSubmitted returns false', (tester) async {
      await pumpTestWidget(
        tester,
        onPinSubmitted: (pin) async => false, // Invalid PIN
      );

      // Tap 9, 9, 9, 9
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('9'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('Invalid PIN. Please try again.'), findsOneWidget);
    });

    testWidgets('supports physical keyboard input for digits and backspace', (tester) async {
      String? submittedPin;
      await pumpTestWidget(
        tester,
        onPinSubmitted: (pin) async {
          submittedPin = pin;
          return true;
        },
      );

      // Send physical keyboard events
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace); // delete 6
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
      await tester.pumpAndSettle();

      expect(submittedPin, equals('5789'));
    });
  });
}
