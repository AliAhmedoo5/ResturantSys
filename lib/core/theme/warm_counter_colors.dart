import 'package:flutter/material.dart';

/// Authoritative color palette tokens for Chapter 34 Street-Food / Mafia Branding design system.
///
/// Implements high-contrast dark surfaces tailored for counter readability,
/// 1366x768 non-scrolling touch/keyboard ergonomics, and dense financial tables.
abstract final class StreetFoodMafiaColors {
  // ---------------------------------------------------------------------------
  // Chapter 34 Authoritative Color Tokens
  // ---------------------------------------------------------------------------
  /// Obsidian Black: Primary application background.
  static const Color obsidian = Color(0xFF050708);

  /// Dark Navy: Compact fixed sidebar, deepest surfaces, table headers.
  static const Color darkNavy = Color(0xFF101820);

  /// Cartel Yellow: Primary CTAs, active navigation indicators, key highlights.
  static const Color cartelYellow = Color(0xFFFFC400);

  /// Burnt Gold: Secondary accents, subtle brand styling, crown highlights.
  static const Color burntGold = Color(0xFFF5A623);

  /// Off-White: Primary readable text on dark surfaces.
  static const Color offWhite = Color(0xFFF5F7FA);

  /// Card Surface: Cards, dialogs, modals, and dense data tables.
  static const Color cardSurface = Color(0xFF14242D);

  // ---------------------------------------------------------------------------
  // Supplemental Accessible Neutral & Focus Tokens
  // ---------------------------------------------------------------------------
  /// Text on primary: Dark high-contrast text on Cartel Yellow (contrast ratio > 11:1).
  static const Color textOnPrimary = Color(0xFF050708);

  /// Secondary text: Accessible muted slate/silver text for captions, timestamps, and metadata.
  static const Color secondaryText = Color(0xFF94A3B8);

  /// Muted border: Restrained 1px structural divider separating panels and cards.
  static const Color border = Color(0xFF1F333E);

  /// Subtle border: Fainter divider for nested items and subtle chips.
  static const Color borderSubtle = Color(0xFF16252E);

  /// Active navigation container highlight: Dark navy/slate highlight for selected navigation items.
  static const Color activeNavHighlight = Color(0xFF1C2C36);

  /// Visible keyboard focus outline color: Vibrant yellow outline ensuring clear keyboard accessibility.
  static const Color focusOutline = Color(0xFFFFC400);

  // ---------------------------------------------------------------------------
  // Chapter 34 Semantic Status Palette (Always icon + text)
  // ---------------------------------------------------------------------------
  /// Ready: High-contrast green status token.
  static const Color statusReady = Color(0xFF58C78A);

  /// Preparing: Amber / Burnt gold attention status token.
  static const Color statusPreparing = Color(0xFFF5A623);

  /// Out for Delivery: Accessible blue status token.
  static const Color statusOutForDelivery = Color(0xFF6BAEFF);

  /// Canceled / Failed / Destructive: High-contrast red status token.
  static const Color statusCanceled = Color(0xFFF47F7F);

  // ---------------------------------------------------------------------------
  // Hex Utility Helper
  // ---------------------------------------------------------------------------
  /// Safely parses a hex color string (e.g. '#FFC400' or 'FFC400') into a [Color].
  static Color parseHex(String hex, {Color fallback = StreetFoodMafiaColors.cartelYellow}) {
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

/// BrandPalette alias per Chapter 34 specification.
typedef BrandPalette = StreetFoodMafiaColors;

/// Backward-compatible wrapper aliasing legacy Warm Counter references directly
/// to Chapter 34 Street-Food / Mafia tokens, ensuring zero regression across legacy call sites.
abstract final class WarmCounterColors {
  // ---------------------------------------------------------------------------
  // Street-Food / Mafia Themed Palette (Replaces legacy warm counter tokens)
  // ---------------------------------------------------------------------------
  /// Page background: Obsidian Black.
  static const Color lightPageBackground = StreetFoodMafiaColors.obsidian;

  /// Cards and panels: Card Surface.
  static const Color lightCardBackground = StreetFoodMafiaColors.cardSurface;

  /// Primary text: Off-White.
  static const Color lightPrimaryText = StreetFoodMafiaColors.offWhite;

  /// Secondary text: Muted slate.
  static const Color lightSecondaryText = StreetFoodMafiaColors.secondaryText;

  /// Primary action: Cartel Yellow.
  static const Color lightPrimaryAction = StreetFoodMafiaColors.cartelYellow;

  /// Text on primary: Dark Obsidian text on Cartel Yellow.
  static const Color lightTextOnPrimary = StreetFoodMafiaColors.textOnPrimary;

  /// Borders: 1px structural divider.
  static const Color lightBorder = StreetFoodMafiaColors.border;

  /// Warning / Preparing: Amber.
  static const Color lightWarning = StreetFoodMafiaColors.statusPreparing;

  /// Destructive / Canceled: Red.
  static const Color lightDestructive = StreetFoodMafiaColors.statusCanceled;

  /// Destructive action button background.
  static const Color lightDestructiveAction = StreetFoodMafiaColors.statusCanceled;

  /// Destructive container / background tint.
  static const Color lightDestructiveHighlight = Color(0xFF2C1518);

  /// Warning container / background tint.
  static const Color lightWarningHighlight = Color(0xFF2D2310);

  /// Active section highlight: Navy/slate highlight.
  static const Color lightActiveNavHighlight = StreetFoodMafiaColors.activeNavHighlight;

  /// Muted container surface: Dark Navy.
  static const Color lightSurfaceMuted = StreetFoodMafiaColors.darkNavy;

  // ---------------------------------------------------------------------------
  // Dark Mode Palette (Identical dark Street-Food / Mafia tokens)
  // ---------------------------------------------------------------------------
  static const Color darkPageBackground = StreetFoodMafiaColors.obsidian;
  static const Color darkCardBackground = StreetFoodMafiaColors.cardSurface;
  static const Color darkPrimaryText = StreetFoodMafiaColors.offWhite;
  static const Color darkSecondaryText = StreetFoodMafiaColors.secondaryText;
  static const Color darkPrimaryAction = StreetFoodMafiaColors.cartelYellow;
  static const Color darkTextOnPrimary = StreetFoodMafiaColors.textOnPrimary;
  static const Color darkBorder = StreetFoodMafiaColors.border;
  static const Color darkWarning = StreetFoodMafiaColors.statusPreparing;
  static const Color darkDestructive = StreetFoodMafiaColors.statusCanceled;
  static const Color darkActiveNavHighlight = StreetFoodMafiaColors.activeNavHighlight;

  static Color parseHex(String hex, {Color fallback = StreetFoodMafiaColors.cartelYellow}) {
    return StreetFoodMafiaColors.parseHex(hex, fallback: fallback);
  }
}
