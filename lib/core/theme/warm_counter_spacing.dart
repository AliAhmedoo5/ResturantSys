import 'package:flutter/material.dart';

/// Spacing, dimension, corner radii, and touch target tokens for the Warm Counter theme.
abstract final class WarmCounterSpacing {
  // ---------------------------------------------------------------------------
  // Base Spacing Scale (8, 12, 16, 24, 32px)
  // ---------------------------------------------------------------------------
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  // ---------------------------------------------------------------------------
  // Corner Radii Tokens
  // ---------------------------------------------------------------------------
  /// 8px corner radius for controls (buttons, inputs, chips, numpad keys).
  static const double controlCornerRadius = 8.0;

  /// 12px corner radius for panels (cards, side sheets, modals, dialogs).
  static const double panelCornerRadius = 12.0;

  /// Control border radius object.
  static const BorderRadius controlBorderRadius = BorderRadius.all(
    Radius.circular(controlCornerRadius),
  );

  /// Panel border radius object.
  static const BorderRadius panelBorderRadius = BorderRadius.all(
    Radius.circular(panelCornerRadius),
  );

  // ---------------------------------------------------------------------------
  // Touch Target & Minimum Dimension Metrics
  // ---------------------------------------------------------------------------
  /// Minimum touch target dimension (48px × 48px) ensuring practical, mistake-free tapping.
  static const double minTouchTargetSize = 48.0;

  /// Box constraints ensuring a minimum 48px square touch target.
  static const BoxConstraints minTouchTargetConstraints = BoxConstraints(
    minWidth: minTouchTargetSize,
    minHeight: minTouchTargetSize,
  );

  // ---------------------------------------------------------------------------
  // Insets Helpers
  // ---------------------------------------------------------------------------
  static const EdgeInsets padding8 = EdgeInsets.all(space8);
  static const EdgeInsets padding12 = EdgeInsets.all(space12);
  static const EdgeInsets padding16 = EdgeInsets.all(space16);
  static const EdgeInsets padding24 = EdgeInsets.all(space24);
  static const EdgeInsets padding32 = EdgeInsets.all(space32);

  static const EdgeInsets horizontal8 = EdgeInsets.symmetric(horizontal: space8);
  static const EdgeInsets horizontal12 = EdgeInsets.symmetric(horizontal: space12);
  static const EdgeInsets horizontal16 = EdgeInsets.symmetric(horizontal: space16);
  static const EdgeInsets horizontal24 = EdgeInsets.symmetric(horizontal: space24);

  static const EdgeInsets vertical8 = EdgeInsets.symmetric(vertical: space8);
  static const EdgeInsets vertical12 = EdgeInsets.symmetric(vertical: space12);
  static const EdgeInsets vertical16 = EdgeInsets.symmetric(vertical: space16);
  static const EdgeInsets vertical24 = EdgeInsets.symmetric(vertical: space24);

  // ---------------------------------------------------------------------------
  // Standard Animation Durations (Subtle & Brief UX Guideline)
  // ---------------------------------------------------------------------------
  /// Quick, responsive micro-interaction duration (150ms).
  static const Duration fastAnimation = Duration(milliseconds: 150);

  /// Standard screen transition duration (200ms).
  static const Duration standardAnimation = Duration(milliseconds: 200);
}
