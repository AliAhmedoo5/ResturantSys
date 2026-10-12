import 'printer_target.dart';

/// Abstract hardware boundary seam for emitting raw byte commands to thermal printers
/// and RJ11 cash drawers.
abstract class HardwareDeviceAdapter {
  /// Sends raw ESC/POS byte sequence to the specified printer destination target.
  Future<void> sendBytes(PrinterTarget target, List<int> bytes);

  /// Emits an RJ11 kick pulse to actuate the connected cash drawer solenoid.
  Future<void> kickCashDrawer();

  /// Whether the cash drawer is physically plugged in and configured for auto-kick.
  bool get isDrawerConnected;

  /// Whether the primary printer device is connected and reachable.
  bool get isPrinterConnected;
}
