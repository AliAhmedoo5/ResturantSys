/// Fulfillment progression status for kitchen and pickup queue.
enum TokenStatus {
  confirmed('CONFIRMED', 'Confirmed'),
  preparing('PREPARING', 'Preparing'),
  ready('READY', 'Ready'),
  outForDelivery('OUT_FOR_DELIVERY', 'Out for Delivery'),
  delivered('DELIVERED', 'Delivered');

  const TokenStatus(this.code, this.displayName);

  final String code;
  final String displayName;

  static TokenStatus fromCode(String code) {
    return TokenStatus.values.firstWhere(
      (s) => s.code.toUpperCase() == code.toUpperCase(),
      orElse: () => TokenStatus.preparing,
    );
  }

  /// 1-tap progression: Confirmed -> Preparing -> Ready -> Delivered -> null
  TokenStatus? get nextStatus {
    switch (this) {
      case TokenStatus.confirmed:
        return TokenStatus.preparing;
      case TokenStatus.preparing:
        return TokenStatus.ready;
      case TokenStatus.ready:
        return TokenStatus.delivered;
      case TokenStatus.outForDelivery:
        return TokenStatus.delivered;
      case TokenStatus.delivered:
        return null;
    }
  }

  bool get isConfirmed => this == TokenStatus.confirmed;
  bool get isPreparing => this == TokenStatus.preparing;
  bool get isReady => this == TokenStatus.ready;
  bool get isOutForDelivery => this == TokenStatus.outForDelivery;
  bool get isDelivered => this == TokenStatus.delivered;
}
