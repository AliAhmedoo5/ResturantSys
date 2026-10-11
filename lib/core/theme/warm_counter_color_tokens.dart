import 'package:flutter/material.dart';
import 'warm_counter_colors.dart';

/// Semantic color tokens for the Warm Counter theme exposed as a [ThemeExtension].
///
/// Allows type-safe access to domain-specific colors via `context.warmCounterColors`
/// or `Theme.of(context).extension<WarmCounterColorTokens>()`.
@immutable
class WarmCounterColorTokens extends ThemeExtension<WarmCounterColorTokens> {
  const WarmCounterColorTokens({
    required this.pageBackground,
    required this.cardBackground,
    required this.primaryText,
    required this.secondaryText,
    required this.primaryAction,
    required this.textOnPrimary,
    required this.border,
    required this.warning,
    required this.destructive,
    required this.activeNavHighlight,
  });

  /// Light mode semantic token configuration.
  static const WarmCounterColorTokens light = WarmCounterColorTokens(
    pageBackground: WarmCounterColors.lightPageBackground,
    cardBackground: WarmCounterColors.lightCardBackground,
    primaryText: WarmCounterColors.lightPrimaryText,
    secondaryText: WarmCounterColors.lightSecondaryText,
    primaryAction: WarmCounterColors.lightPrimaryAction,
    textOnPrimary: WarmCounterColors.lightTextOnPrimary,
    border: WarmCounterColors.lightBorder,
    warning: WarmCounterColors.lightWarning,
    destructive: WarmCounterColors.lightDestructive,
    activeNavHighlight: WarmCounterColors.lightActiveNavHighlight,
  );

  /// Dark mode semantic token configuration.
  static const WarmCounterColorTokens dark = WarmCounterColorTokens(
    pageBackground: WarmCounterColors.darkPageBackground,
    cardBackground: WarmCounterColors.darkCardBackground,
    primaryText: WarmCounterColors.darkPrimaryText,
    secondaryText: WarmCounterColors.darkSecondaryText,
    primaryAction: WarmCounterColors.darkPrimaryAction,
    textOnPrimary: WarmCounterColors.darkTextOnPrimary,
    border: WarmCounterColors.darkBorder,
    warning: WarmCounterColors.darkWarning,
    destructive: WarmCounterColors.darkDestructive,
    activeNavHighlight: WarmCounterColors.darkActiveNavHighlight,
  );

  final Color pageBackground;
  final Color cardBackground;
  final Color primaryText;
  final Color secondaryText;
  final Color primaryAction;
  final Color textOnPrimary;
  final Color border;
  final Color warning;
  final Color destructive;
  final Color activeNavHighlight;

  @override
  WarmCounterColorTokens copyWith({
    Color? pageBackground,
    Color? cardBackground,
    Color? primaryText,
    Color? secondaryText,
    Color? primaryAction,
    Color? textOnPrimary,
    Color? border,
    Color? warning,
    Color? destructive,
    Color? activeNavHighlight,
  }) {
    return WarmCounterColorTokens(
      pageBackground: pageBackground ?? this.pageBackground,
      cardBackground: cardBackground ?? this.cardBackground,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      primaryAction: primaryAction ?? this.primaryAction,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      border: border ?? this.border,
      warning: warning ?? this.warning,
      destructive: destructive ?? this.destructive,
      activeNavHighlight: activeNavHighlight ?? this.activeNavHighlight,
    );
  }

  @override
  WarmCounterColorTokens lerp(
    ThemeExtension<WarmCounterColorTokens>? other,
    double t,
  ) {
    if (other is! WarmCounterColorTokens) {
      return this;
    }
    return WarmCounterColorTokens(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t) ?? pageBackground,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t) ?? cardBackground,
      primaryText: Color.lerp(primaryText, other.primaryText, t) ?? primaryText,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t) ?? secondaryText,
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t) ?? primaryAction,
      textOnPrimary: Color.lerp(textOnPrimary, other.textOnPrimary, t) ?? textOnPrimary,
      border: Color.lerp(border, other.border, t) ?? border,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      destructive: Color.lerp(destructive, other.destructive, t) ?? destructive,
      activeNavHighlight: Color.lerp(activeNavHighlight, other.activeNavHighlight, t) ?? activeNavHighlight,
    );
  }
}

/// Convenience extension on [BuildContext] to access [WarmCounterColorTokens].
extension WarmCounterColorContextExtension on BuildContext {
  WarmCounterColorTokens get warmCounterColors {
    return Theme.of(this).extension<WarmCounterColorTokens>() ?? WarmCounterColorTokens.light;
  }
}
