import 'package:flutter/material.dart';
import '../../core/orders/token_status.dart';
import '../../core/theme/theme.dart';

/// Semantic status categories mandated by Chapter 34 Street-Food / Mafia Branding.
enum SemanticStatusKind {
  ready(
    label: 'Ready',
    color: StreetFoodMafiaColors.statusReady,
    icon: Icons.check_circle_outline_rounded,
  ),
  preparing(
    label: 'Preparing',
    color: StreetFoodMafiaColors.statusPreparing,
    icon: Icons.soup_kitchen_outlined,
  ),
  outForDelivery(
    label: 'Out for Delivery',
    color: StreetFoodMafiaColors.statusOutForDelivery,
    icon: Icons.delivery_dining_outlined,
  ),
  canceled(
    label: 'Canceled',
    color: StreetFoodMafiaColors.statusCanceled,
    icon: Icons.cancel_outlined,
  );

  const SemanticStatusKind({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;
}

/// Accessible high-contrast status badge rendering BOTH icon and readable text.
///
/// Implements Chapter 34 requirement:
/// "green Ready, amber Preparing, blue Out for Delivery, red Cancelled/Failed;
/// always text + icon, never color alone."
class SemanticStatusBadge extends StatelessWidget {
  const SemanticStatusBadge({
    super.key,
    required this.kind,
    this.customLabel,
    this.fontSize = 12.0,
    this.iconSize = 14.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  });

  final SemanticStatusKind kind;
  final String? customLabel;
  final double fontSize;
  final double iconSize;
  final EdgeInsetsGeometry padding;

  const SemanticStatusBadge.ready({
    Key? key,
    String? label,
    double fontSize = 12.0,
    double iconSize = 14.0,
  }) : this(
          key: key,
          kind: SemanticStatusKind.ready,
          customLabel: label,
          fontSize: fontSize,
          iconSize: iconSize,
        );

  const SemanticStatusBadge.preparing({
    Key? key,
    String? label,
    double fontSize = 12.0,
    double iconSize = 14.0,
  }) : this(
          key: key,
          kind: SemanticStatusKind.preparing,
          customLabel: label,
          fontSize: fontSize,
          iconSize: iconSize,
        );

  const SemanticStatusBadge.outForDelivery({
    Key? key,
    String? label,
    double fontSize = 12.0,
    double iconSize = 14.0,
  }) : this(
          key: key,
          kind: SemanticStatusKind.outForDelivery,
          customLabel: label,
          fontSize: fontSize,
          iconSize: iconSize,
        );

  const SemanticStatusBadge.canceled({
    Key? key,
    String? label,
    double fontSize = 12.0,
    double iconSize = 14.0,
  }) : this(
          key: key,
          kind: SemanticStatusKind.canceled,
          customLabel: label,
          fontSize: fontSize,
          iconSize: iconSize,
        );

  /// Factory creating an appropriate semantic badge from a [TokenStatus].
  factory SemanticStatusBadge.fromTokenStatus(
    TokenStatus status, {
    Key? key,
    double fontSize = 12.0,
    double iconSize = 14.0,
  }) {
    switch (status) {
      case TokenStatus.ready:
        return SemanticStatusBadge.ready(
          key: key,
          label: 'Ready on Pass',
          fontSize: fontSize,
          iconSize: iconSize,
        );
      case TokenStatus.preparing:
        return SemanticStatusBadge.preparing(
          key: key,
          label: 'Preparing',
          fontSize: fontSize,
          iconSize: iconSize,
        );
      case TokenStatus.outForDelivery:
        return SemanticStatusBadge.outForDelivery(
          key: key,
          label: 'Out for Delivery',
          fontSize: fontSize,
          iconSize: iconSize,
        );
      case TokenStatus.delivered:
        return SemanticStatusBadge.ready(
          key: key,
          label: 'Delivered',
          fontSize: fontSize,
          iconSize: iconSize,
        );
      case TokenStatus.confirmed:
        return SemanticStatusBadge.preparing(
          key: key,
          label: 'Confirmed',
          fontSize: fontSize,
          iconSize: iconSize,
        );
    }
  }

  /// Factory resolving payment/revision/fulfillment status strings.
  factory SemanticStatusBadge.fromStatusCode(
    String code, {
    Key? key,
    double fontSize = 12.0,
    double iconSize = 14.0,
  }) {
    final upper = code.toUpperCase().trim();
    if (upper == 'READY' || upper == 'DELIVERED' || upper == 'SETTLED' || upper == 'COMPLETED') {
      return SemanticStatusBadge.ready(
        key: key,
        label: code,
        fontSize: fontSize,
        iconSize: iconSize,
      );
    } else if (upper == 'PREPARING' || upper == 'CONFIRMED' || upper == 'PENDING' || upper == 'ATTENTION') {
      return SemanticStatusBadge.preparing(
        key: key,
        label: code,
        fontSize: fontSize,
        iconSize: iconSize,
      );
    } else if (upper == 'OUT_FOR_DELIVERY' || upper == 'OUT FOR DELIVERY' || upper == 'DISPATCHED' || upper == 'IN_TRANSIT') {
      return SemanticStatusBadge.outForDelivery(
        key: key,
        label: code.replaceAll('_', ' '),
        fontSize: fontSize,
        iconSize: iconSize,
      );
    } else {
      return SemanticStatusBadge.canceled(
        key: key,
        label: code.replaceAll('_', ' '),
        fontSize: fontSize,
        iconSize: iconSize,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayLabel = customLabel ?? kind.label;
    final color = kind.color;

    return Semantics(
      label: 'Status: $displayLabel',
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withAlpha(160),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              kind.icon,
              size: iconSize,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              displayLabel,
              style: TextStyle(
                fontFamily: WarmCounterTypography.fontFamily,
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: fontSize,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
