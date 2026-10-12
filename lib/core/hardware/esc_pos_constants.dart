/// Standard ESC/POS byte commands and control codes for thermal receipt printers
/// and RJ11 cash drawers.
abstract final class EscPosConstants {
  // Control Characters
  static const int esc = 0x1B; // 27
  static const int gs = 0x1D;  // 29
  static const int lf = 0x0A;  // 10

  // Printer Initialization
  // ESC @: Resets printer buffer, modes, and font settings to defaults
  static const List<int> initPrinter = [esc, 0x40];

  // Paper Auto-Cutter
  // GS V 0: Full paper cut
  static const List<int> cutPaperFull = [gs, 0x56, 0x00];
  // GS V 1: Partial paper cut (leaves a tiny bridge)
  static const List<int> cutPaperPartial = [gs, 0x56, 0x01];

  // RJ11 Cash Drawer Kick Pulse
  // ESC p m t1 t2:
  // m = 0 (Pin 2 of RJ11 connector)
  // t1 = 25 (ON pulse: 25 * 2ms = 50ms)
  // t2 = 250 (OFF pulse: 250 * 2ms = 500ms)
  static const List<int> kickDrawerPulse = [esc, 0x70, 0x00, 25, 250];

  // Text Alignment (ESC a n)
  static const List<int> alignLeft = [esc, 0x61, 0x00];
  static const List<int> alignCenter = [esc, 0x61, 0x01];
  static const List<int> alignRight = [esc, 0x61, 0x02];

  // Bold / Emphasized (ESC E n)
  static const List<int> boldOn = [esc, 0x45, 0x01];
  static const List<int> boldOff = [esc, 0x45, 0x00];

  // Character Size Multipliers (GS ! n)
  // Normal size (1x width, 1x height)
  static const List<int> sizeNormal = [gs, 0x21, 0x00];
  // Double height & Double width (2x width, 2x height)
  static const List<int> sizeLargeBold = [gs, 0x21, 0x11];
  // Double width (2x width, 1x height)
  static const List<int> sizeDoubleWidth = [gs, 0x21, 0x10];
  // Double height (1x width, 2x height)
  static const List<int> sizeDoubleHeight = [gs, 0x21, 0x01];

  // Inverse (White text on Black background) (GS B n)
  static const List<int> inverseOn = [gs, 0x42, 0x01];
  static const List<int> inverseOff = [gs, 0x42, 0x00];

  // Underline (ESC - n)
  static const List<int> underlineOn = [esc, 0x2D, 0x01];
  static const List<int> underlineOff = [esc, 0x2D, 0x00];
}
