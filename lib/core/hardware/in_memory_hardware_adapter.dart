import 'esc_pos_constants.dart';
import 'hardware_device_adapter.dart';
import 'printer_target.dart';

/// In-memory fake hardware device adapter capturing emitted ESC/POS bytes, cutter commands,
/// and drawer pulses for automated testing and offline development.
class InMemoryHardwareAdapter implements HardwareDeviceAdapter {
  InMemoryHardwareAdapter({
    this.isDrawerConnected = true,
    this.isPrinterConnected = true,
  });

  @override
  bool isDrawerConnected;

  @override
  bool isPrinterConnected;

  // Emitted Byte Buffers
  final List<List<int>> counterPrintedBytes = [];
  final List<List<int>> kitchenPrintedBytes = [];
  final List<List<int>> drawerPulses = [];
  int drawerKickCount = 0;

  // Fault Injection Flags for Resilience Testing
  bool shouldFailCounterPrint = false;
  String counterPrintErrorMessage = 'Printer hardware error / paper jam';

  bool shouldFailKitchenPrint = false;
  String kitchenPrintErrorMessage = 'Kitchen network printer unreachable';

  bool shouldFailDrawerKick = false;
  String drawerKickErrorMessage = 'Drawer solenoid disconnect';

  @override
  Future<void> sendBytes(PrinterTarget target, List<int> bytes) async {
    if (!isPrinterConnected) {
      throw StateError('Printer hardware is disconnected or turned off.');
    }

    if (target == PrinterTarget.counter) {
      if (shouldFailCounterPrint) {
        throw StateError(counterPrintErrorMessage);
      }
      counterPrintedBytes.add(List<int>.unmodifiable(bytes));
    } else if (target == PrinterTarget.kitchen) {
      if (shouldFailKitchenPrint) {
        throw StateError(kitchenPrintErrorMessage);
      }
      kitchenPrintedBytes.add(List<int>.unmodifiable(bytes));
    }
  }

  @override
  Future<void> kickCashDrawer() async {
    if (!isDrawerConnected) {
      // Manual / unpluggable cash drawer: pulse bypassed gracefully without throwing error
      return;
    }

    if (shouldFailDrawerKick) {
      throw StateError(drawerKickErrorMessage);
    }

    drawerKickCount++;
    drawerPulses.add(List<int>.unmodifiable(EscPosConstants.kickDrawerPulse));
  }

  /// Clears all recorded buffers and resets fault injection flags.
  void reset() {
    counterPrintedBytes.clear();
    kitchenPrintedBytes.clear();
    drawerPulses.clear();
    drawerKickCount = 0;
    isDrawerConnected = true;
    isPrinterConnected = true;
    shouldFailCounterPrint = false;
    shouldFailKitchenPrint = false;
    shouldFailDrawerKick = false;
  }
}
