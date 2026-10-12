/// Printer network/hardware topology configuration.
enum PrinterTopology {
  /// Single physical printer at counter. Both Customer Receipt and Kitchen Order
  /// Ticket are output sequentially on this single device, separated by auto-cuts.
  single('Single Printer (Sequential Dual Cuts)'),

  /// Dedicated counter printer and dedicated kitchen printer (e.g. Counter USB + Kitchen Network/USB).
  dual('Dual Printer (Counter USB + Kitchen Network/USB)');

  const PrinterTopology(this.label);
  final String label;

  /// Parses a string representation (e.g. 'SINGLE', 'DUAL') into a [PrinterTopology].
  static PrinterTopology fromSetting(String? value) {
    if (value != null && value.trim().toUpperCase() == 'DUAL') {
      return PrinterTopology.dual;
    }
    return PrinterTopology.single;
  }
}
