/// Payment tender types supported at checkout.
enum PaymentMethod {
  cash('CASH', 'Cash'),
  card('CARD', 'Card'),
  jazzCash('JAZZCASH', 'JazzCash'),
  easypaisa('EASYPAISA', 'Easypaisa'),
  bankTransfer('BANK_TRANSFER', 'Bank Transfer'),
  digitalWallet('DIGITAL_WALLET', 'Direct digital'),
  raast('RAAST', 'Raast QR'),
  cod('COD', 'Cash on Delivery'),
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
