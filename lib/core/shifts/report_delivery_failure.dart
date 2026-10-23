class ReportDeliveryFailure implements Exception {
  const ReportDeliveryFailure(this.message, {this.retryable = false, this.ambiguous = false});
  final String message;
  final bool retryable;
  final bool ambiguous;
}
