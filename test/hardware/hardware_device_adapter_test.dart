import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/hardware/esc_pos_constants.dart';
import 'package:resturant_sys/core/hardware/in_memory_hardware_adapter.dart';
import 'package:resturant_sys/core/hardware/printer_target.dart';

void main() {
  group('InMemoryHardwareAdapter Tests', () {
    late InMemoryHardwareAdapter adapter;

    setUp(() {
      adapter = InMemoryHardwareAdapter();
    });

    test('Captures emitted byte streams for counter and kitchen independently', () async {
      final counterBytes = [0x1B, 0x40, 0x41, 0x42];
      final kitchenBytes = [0x1B, 0x40, 0x4B, 0x4F, 0x54];

      await adapter.sendBytes(PrinterTarget.counter, counterBytes);
      await adapter.sendBytes(PrinterTarget.kitchen, kitchenBytes);

      expect(adapter.counterPrintedBytes.length, equals(1));
      expect(adapter.kitchenPrintedBytes.length, equals(1));
      expect(adapter.counterPrintedBytes.first, equals(counterBytes));
      expect(adapter.kitchenPrintedBytes.first, equals(kitchenBytes));
    });

    test('kickCashDrawer records drawer pulse and increments kick count', () async {
      expect(adapter.drawerKickCount, equals(0));
      expect(adapter.drawerPulses, isEmpty);

      await adapter.kickCashDrawer();

      expect(adapter.drawerKickCount, equals(1));
      expect(adapter.drawerPulses.length, equals(1));
      expect(adapter.drawerPulses.first, equals(EscPosConstants.kickDrawerPulse));
    });

    test('Gracefully bypasses pulse when manual unpluggable drawer is configured', () async {
      adapter.isDrawerConnected = false;

      // Should complete without error and without logging hardware pulses
      await adapter.kickCashDrawer();

      expect(adapter.drawerKickCount, equals(0));
      expect(adapter.drawerPulses, isEmpty);
    });

    test('Throws hardware error when printer is marked disconnected', () async {
      adapter.isPrinterConnected = false;

      expect(
        () => adapter.sendBytes(PrinterTarget.counter, [0x1B, 0x40]),
        throwsStateError,
      );
    });

    test('Simulates counter printer hardware failure and recover on reset', () async {
      adapter.shouldFailCounterPrint = true;

      expect(
        () => adapter.sendBytes(PrinterTarget.counter, [0x1B, 0x40]),
        throwsStateError,
      );

      adapter.shouldFailCounterPrint = false;
      await adapter.sendBytes(PrinterTarget.counter, [0x1B, 0x40]);
      expect(adapter.counterPrintedBytes.length, equals(1));
    });

    test('Simulates kitchen network printer unreachable error', () async {
      adapter.shouldFailKitchenPrint = true;

      expect(
        () => adapter.sendBytes(PrinterTarget.kitchen, [0x1B, 0x40]),
        throwsStateError,
      );
    });

    test('reset clears all buffers and restores clean state', () async {
      await adapter.sendBytes(PrinterTarget.counter, [1, 2, 3]);
      await adapter.kickCashDrawer();
      expect(adapter.counterPrintedBytes.length, equals(1));
      expect(adapter.drawerKickCount, equals(1));

      adapter.reset();

      expect(adapter.counterPrintedBytes, isEmpty);
      expect(adapter.kitchenPrintedBytes, isEmpty);
      expect(adapter.drawerPulses, isEmpty);
      expect(adapter.drawerKickCount, equals(0));
    });
  });
}
