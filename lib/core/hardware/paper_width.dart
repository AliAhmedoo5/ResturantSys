/// Supported thermal paper roll widths and column limits.
enum PaperWidth {
  mm80(columns: 48, label: '80mm Standard'),
  mm58(columns: 32, label: '58mm Compact');

  const PaperWidth({
    required this.columns,
    required this.label,
  });

  final int columns;
  final String label;

  /// Parses a string representation (e.g. '80mm', '58mm') into a [PaperWidth].
  static PaperWidth fromSetting(String? value) {
    if (value != null && value.trim().toLowerCase().contains('58')) {
      return PaperWidth.mm58;
    }
    return PaperWidth.mm80;
  }
}
