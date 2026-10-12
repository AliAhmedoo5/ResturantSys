/// Physical printer destination target for a print job.
enum PrinterTarget {
  counter('Counter Printer'),
  kitchen('Kitchen Printer');

  const PrinterTarget(this.label);
  final String label;
}
