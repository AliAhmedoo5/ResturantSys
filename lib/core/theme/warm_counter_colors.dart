import 'package:flutter/material.dart';

/// Raw color palette tokens for the Warm Counter restaurant theme.
///
/// Implements high-contrast, glare-reducing surfaces with deep forest green actions
/// and clean neutral backdrops in both Light and Dark modes.
abstract final class WarmCounterColors {
  // ---------------------------------------------------------------------------
  // Light Mode Palette
  // ---------------------------------------------------------------------------
  /// Page background: Warm stone neutral reducing eye fatigue under harsh lighting.
  static const Color lightPageBackground = Color(0xFFF5F3EE);

  /// Cards and panels: Crisp flat white containers with no heavy shadows.
  static const Color lightCardBackground = Color(0xFFFFFFFF);

  /// Primary text: High-contrast charcoal for clear legibility during rushes.
  static const Color lightPrimaryText = Color(0xFF202822);

  /// Secondary text: Subdued olive-gray for timestamps, metadata, and captions.
  static const Color lightSecondaryText = Color(0xFF59635B);

  /// Primary action: Deep forest green for primary workflows and selected states.
  static const Color lightPrimaryAction = Color(0xFF245C40);

  /// Text on primary: Pure white text on primary green buttons and active pills.
  static const Color lightTextOnPrimary = Color(0xFFFFFFFF);

  /// Borders: Subtle structural divider separating panels and cards.
  static const Color lightBorder = Color(0xFFD9DED5);

  /// Warning: Warm amber for discrepancies, low-stock, and paper status.
  static const Color lightWarning = Color(0xFFD97706);

  /// Destructive: Muted red for voids, cart discards, and cancellations.
  static const Color lightDestructive = Color(0xFFDC2626);

  /// Destructive action button background.
  static const Color lightDestructiveAction = lightDestructive;

  /// Destructive container / background tint: Soft pale red background for badges, chips, and error banners.
  static const Color lightDestructiveHighlight = Color(0xFFFEE2E2);

  /// Warning container / background tint: Soft pale amber background for warning chips.
  static const Color lightWarningHighlight = Color(0xFFFEF3C7);

  /// Active section highlight: Pale green background for selected navigation items.
  static const Color lightActiveNavHighlight = Color(0xFFE3EFE7);

  /// Muted container surface for secondary panels and subtle chips.
  static const Color lightSurfaceMuted = Color(0xFFECEAE4);

  // ---------------------------------------------------------------------------
  // Dark Mode Palette
  // ---------------------------------------------------------------------------
  /// Page background: Deep charcoal neutral for evening shifts and low-light counters.
  static const Color darkPageBackground = Color(0xFF151A17);

  /// Cards and panels: Elevated dark stone containers.
  static const Color darkCardBackground = Color(0xFF202722);

  /// Primary text: Soft off-white for high contrast on dark panels.
  static const Color darkPrimaryText = Color(0xFFF0F3EE);

  /// Secondary text: Muted sage gray for secondary labels.
  static const Color darkSecondaryText = Color(0xFFB2BEB4);

  /// Primary action: Luminous mint green for high visibility on dark surfaces.
  static const Color darkPrimaryAction = Color(0xFF9ED3AC);

  /// Text on primary: Deep forest charcoal text on mint action buttons.
  static const Color darkTextOnPrimary = Color(0xFF142B1C);

  /// Borders: Deep muted border separating dark panels.
  static const Color darkBorder = Color(0xFF414D43);

  /// Warning: Soft amber warning indicator.
  static const Color darkWarning = Color(0xFFFBBF24);

  /// Destructive: Soft red for destructive warnings and voids.
  static const Color darkDestructive = Color(0xFFF87171);

  /// Active section highlight: Muted deep green tint for active sidebar items.
  static const Color darkActiveNavHighlight = Color(0xFF1C3324);

  // ---------------------------------------------------------------------------
  // Hex Utility Helper
  // ---------------------------------------------------------------------------
  /// Safely parses a hex color string (e.g. '#2E7D32' or '2E7D32') into a [Color].
  static Color parseHex(String hex, {Color fallback = WarmCounterColors.lightPrimaryAction}) {
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.length == 6) {
      final value = int.tryParse('FF$clean', radix: 16);
      if (value != null) return Color(value);
    } else if (clean.length == 8) {
      final value = int.tryParse(clean, radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }
}
