import 'package:flutter/material.dart';
import 'warm_counter_colors.dart';

import 'package:flutter/material.dart';
import 'warm_counter_colors.dart';

/// Semantic color tokens for the Chapter 34 Street-Food / Mafia theme exposed as a [ThemeExtension].
///
/// Allows type-safe access to domain-specific colors via `context.streetFoodMafiaColors`,
/// `context.warmCounterColors`, or `Theme.of(context).extension<StreetFoodMafiaColorTokens>()`.
@immutable
class StreetFoodMafiaColorTokens extends ThemeExtension<StreetFoodMafiaColorTokens> {
  const StreetFoodMafiaColorTokens({
    required this.pageBackground,
    required this.cardBackground,
    required this.darkNavy,
    required this.primaryText,
    required this.secondaryText,
    required this.primaryAction,
    required this.burntGold,
    required this.textOnPrimary,
    required this.border,
    required this.borderSubtle,
    required this.warning,
    required this.destructive,
    required this.activeNavHighlight,
    required this.focusOutline,
    required this.statusReady,
    required this.statusPreparing,
    required this.statusOutForDelivery,
    required this.statusCanceled,
  });

  /// Authoritative Chapter 34 dark theme semantic token configuration.
  static const StreetFoodMafiaColorTokens dark = StreetFoodMafiaColorTokens(
    pageBackground: StreetFoodMafiaColors.obsidian,
    cardBackground: StreetFoodMafiaColors.cardSurface,
    darkNavy: StreetFoodMafiaColors.darkNavy,
    primaryText: StreetFoodMafiaColors.offWhite,
    secondaryText: StreetFoodMafiaColors.secondaryText,
    primaryAction: StreetFoodMafiaColors.cartelYellow,
    burntGold: StreetFoodMafiaColors.burntGold,
    textOnPrimary: StreetFoodMafiaColors.textOnPrimary,
    border: StreetFoodMafiaColors.border,
    borderSubtle: StreetFoodMafiaColors.borderSubtle,
    warning: StreetFoodMafiaColors.statusPreparing,
    destructive: StreetFoodMafiaColors.statusCanceled,
    activeNavHighlight: StreetFoodMafiaColors.activeNavHighlight,
    focusOutline: StreetFoodMafiaColors.focusOutline,
    statusReady: StreetFoodMafiaColors.statusReady,
    statusPreparing: StreetFoodMafiaColors.statusPreparing,
    statusOutForDelivery: StreetFoodMafiaColors.statusOutForDelivery,
    statusCanceled: StreetFoodMafiaColors.statusCanceled,
  );

  /// Default configuration (also authoritative dark).
  static const StreetFoodMafiaColorTokens light = dark;

  final Color pageBackground;
  final Color cardBackground;
  final Color darkNavy;
  final Color primaryText;
  final Color secondaryText;
  final Color primaryAction;
  final Color burntGold;
  final Color textOnPrimary;
  final Color border;
  final Color borderSubtle;
  final Color warning;
  final Color destructive;
  final Color activeNavHighlight;
  final Color focusOutline;
  final Color statusReady;
  final Color statusPreparing;
  final Color statusOutForDelivery;
  final Color statusCanceled;

  @override
  StreetFoodMafiaColorTokens copyWith({
    Color? pageBackground,
    Color? cardBackground,
    Color? darkNavy,
    Color? primaryText,
    Color? secondaryText,
    Color? primaryAction,
    Color? burntGold,
    Color? textOnPrimary,
    Color? border,
    Color? borderSubtle,
    Color? warning,
    Color? destructive,
    Color? activeNavHighlight,
    Color? focusOutline,
    Color? statusReady,
    Color? statusPreparing,
    Color? statusOutForDelivery,
    Color? statusCanceled,
  }) {
    return StreetFoodMafiaColorTokens(
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      darkNavy: darkNavy ?? this.darkNavy,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      primaryAction: primaryAction ?? this.primaryAction,
      burntGold: burntGold ?? this.burntGold,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      warning: warning ?? this.warning,
      destructive: destructive ?? this.destructive,
      activeNavHighlight: activeNavHighlight ?? this.activeNavHighlight,
      focusOutline: focusOutline ?? this.focusOutline,
      statusReady: statusReady ?? this.statusReady,
      statusPreparing: statusPreparing ?? this.statusPreparing,
      statusOutForDelivery: statusOutForDelivery ?? this.statusOutForDelivery,
      statusCanceled: statusCanceled ?? this.statusCanceled,
    );
  }

  @override
  StreetFoodMafiaColorTokens lerp(
    ThemeExtension<StreetFoodMafiaColorTokens>? other,
    double t,
  ) {
    if (other is! StreetFoodMafiaColorTokens) {
      return this;
    }
    return StreetFoodMafiaColorTokens(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t) ?? pageBackground,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t) ?? cardBackground,
      darkNavy: Color.lerp(darkNavy, other.darkNavy, t) ?? darkNavy,
      primaryText: Color.lerp(primaryText, other.primaryText, t) ?? primaryText,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t) ?? secondaryText,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t) ?? primaryAction,
      burntGold: Color.lerp(burntGold, other.burntGold, t) ?? burntGold,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t) ?? textOnPrimary,
      border: Color.lerp(border, other.border, t) ?? border,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      destructive: Color.lerp(destructive, other.destructive, t) ?? destructive,
      activeNavHighlight: Color.lerp(activeNavHighlight, other.activeNavHighlight, t) ?? activeNavHighlight,
      focusOutline: Color.lerp(focusOutline, other.focusOutline, t) ?? focusOutline,
      statusReady: Color.lerp(statusReady, other.statusReady, t) ?? statusReady,
      statusPreparing: Color.lerp(statusPreparing, other.statusPreparing, t) ?? statusPreparing,
      statusOutForDelivery: Color.lerp(statusOutForDelivery, other.statusOutForDelivery, t) ?? statusOutForDelivery,
      statusCanceled: Color.lerp(statusCanceled, other.statusCanceled, t) ?? statusCanceled,
    );
  }
}

/// Backward-compatible alias for WarmCounterColorTokens.
typedef WarmCounterColorTokens = StreetFoodMafiaColorTokens;

/// Convenience extension on [BuildContext] to access [StreetFoodMafiaColorTokens] and [WarmCounterColorTokens].
extension StreetFoodMafiaColorContextExtension on BuildContext {
  StreetFoodMafiaColorTokens get streetFoodMafiaColors {
    return Theme.of(this).extension<StreetFoodMafiaColorTokens>() ?? StreetFoodMafiaColorTokens.dark;
  }

  WarmCounterColorTokens get warmCounterColors {
    return streetFoodMafiaColors;
  }
}
