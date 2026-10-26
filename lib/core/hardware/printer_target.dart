/// Physical printer destination target for a print job.
enum PrinterTarget {
  counter('Counter Printer');

  const PrinterTarget(this.label);
  final String label;
}
