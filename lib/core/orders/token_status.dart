/// Fulfillment progression status for kitchen and pickup queue.
enum TokenStatus {
  preparing('PREPARING', 'Preparing'),
  ready('READY', 'Ready'),
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

  /// 1-tap progression: Preparing -> Ready -> Delivered -> null
  TokenStatus? get nextStatus {
    switch (this) {
      case TokenStatus.preparing:
        return TokenStatus.ready;
      case TokenStatus.ready:
        return TokenStatus.delivered;
      case TokenStatus.delivered:
        return null;
    }
  }

  bool get isPreparing => this == TokenStatus.preparing;
  bool get isReady => this == TokenStatus.ready;
  bool get isDelivered => this == TokenStatus.delivered;
}
