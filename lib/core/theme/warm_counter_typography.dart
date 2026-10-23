import 'package:flutter/material.dart';

/// Typography hierarchy and text styles for the Warm Counter theme.
///
/// Standardizes on Inter with Segoe UI and sans-serif fallbacks, incorporating
/// tabular figures for zero-jitter currency and quantity alignment.
abstract final class WarmCounterTypography {
  /// Primary font family.
  static const String fontFamily = 'Inter';

  /// Fallback font families in priority order.
  static const List<String> fontFallbacks = [
    'Segoe UI',
    'Roboto',
    'Arial',
    'sans-serif',
  ];

  /// OpenType feature list enforcing consistent-width tabular numerals.
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  // ---------------------------------------------------------------------------
  // Core Text Styles
  // ---------------------------------------------------------------------------

  /// Page headings: 22px, semibold (600).
  static const TextStyle pageHeading = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 22.0,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -0.3,
  );

  /// Body text and input field content: 14px, regular (400).
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Body medium (buttons, active list items): 14px, medium (500).
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// Secondary labels and metadata: 12px, regular (400).
  static const TextStyle secondaryLabel = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  /// Secondary label medium (table headers, field captions): 12px, medium (500).
  static const TextStyle secondaryLabelMedium = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// Order totals: 32px, bold (700) with tabular numerals.
  static const TextStyle orderTotal = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 32.0,
    fontWeight: FontWeight.w700,
    height: 1.2,
    fontFeatures: tabularFigures,
    letterSpacing: -0.5,
  );

  /// Kitchen tokens and cash change: 40px (within 36–44px spec), extra bold (800) with tabular numerals.
  static const TextStyle tokenAndChange = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 40.0,
    fontWeight: FontWeight.w800,
    height: 1.1,
    fontFeatures: tabularFigures,
    letterSpacing: -0.5,
  );

  /// Table amount cell: 14px, medium (500) with tabular numerals for right-aligned columns.
  static const TextStyle tableAmount = TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    height: 1.4,
    fontFeatures: tabularFigures,
  );

  /// Tabular numbers text style for aligned monetary and quantity figures.
  static const TextStyle tabularNumbers = tableAmount;

  /// Tabular price text style alias.
  static const TextStyle tabularPrice = tabularNumbers;

  /// Secondary metadata and small caption style.
  static const TextStyle caption = secondaryLabel;

  /// Small body text style.
  static const TextStyle bodySmall = secondaryLabel;

  /// Large body text style.
  static const TextStyle bodyLarge = body;

  /// Factory creating the standard Material [TextTheme] bound to [textColor].
  static TextTheme createTextTheme(Color textColor, Color secondaryTextColor) {
    return TextTheme(
      displayLarge: tokenAndChange.copyWith(color: textColor),
      displayMedium: orderTotal.copyWith(color: textColor),
      headlineMedium: pageHeading.copyWith(color: textColor),
      titleLarge: pageHeading.copyWith(color: textColor),
      titleMedium: bodyMedium.copyWith(color: textColor),
      titleSmall: secondaryLabelMedium.copyWith(color: textColor),
      bodyLarge: body.copyWith(color: textColor),
      bodyMedium: body.copyWith(color: textColor),
      bodySmall: secondaryLabel.copyWith(color: secondaryTextColor),
      labelLarge: bodyMedium.copyWith(color: textColor),
      labelMedium: secondaryLabelMedium.copyWith(color: secondaryTextColor),
      labelSmall: secondaryLabel.copyWith(color: secondaryTextColor),
    );
  }
}
