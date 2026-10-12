import 'printer_target.dart';

/// The category of hardware print job.
enum PrintJobType {
  customerReceipt('Customer Tax Receipt'),
  kitchenOrderTicket('Kitchen Order Ticket (KOT)'),
  kitchenVoidSlip('Kitchen Order Void Slip'),
  cashDrawerKick('RJ11 Cash Drawer Pulse');

  const PrintJobType(this.label);
  final String label;
}

/// Execution status of a print job.
enum PrintJobStatus {
  pending,
  success,
  failed,
}

/// Represents an atomic document or hardware command submitted to the printer adapter.
class PrintJob {
  PrintJob({
    required this.id,
    required this.target,
    required this.type,
    required this.bytes,
    required this.orderId,
    required this.tokenDisplay,
    required this.createdAt,
    this.status = PrintJobStatus.pending,
    this.errorMessage,
    this.attempts = 0,
  });

  final String id;
  final PrinterTarget target;
  final PrintJobType type;
  final List<int> bytes;
  final int orderId;
  final String tokenDisplay;
  final DateTime createdAt;
  PrintJobStatus status;
  String? errorMessage;
  int attempts;

  bool get isFailed => status == PrintJobStatus.failed;
  bool get isSuccess => status == PrintJobStatus.success;

  void markSuccess() {
    status = PrintJobStatus.success;
    errorMessage = null;
    attempts += 1;
  }

  void markFailed(String error) {
    status = PrintJobStatus.failed;
    errorMessage = error;
    attempts += 1;
  }
}
