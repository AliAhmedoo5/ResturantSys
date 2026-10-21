/// Payment tender types supported at checkout.
enum PaymentMethod {
  cash('CASH', 'Cash'),
  card('CARD', 'Card'),
  jazzCash('JAZZCASH', 'JazzCash'),
  easypaisa('EASYPAISA', 'Easypaisa'),
  bankTransfer('BANK_TRANSFER', 'Bank Transfer'),
  raast('RAAST', 'Raast QR'),
  split('SPLIT', 'Split Tender');

  const PaymentMethod(this.code, this.displayName);

  final String code;
  final String displayName;

  static PaymentMethod fromCode(String code) {
    return PaymentMethod.values.firstWhere(
      (method) => method.code == code,
      orElse: () => PaymentMethod.cash,
    );
  }
}
