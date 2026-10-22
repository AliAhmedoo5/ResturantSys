import 'package:flutter/material.dart';
import 'warm_counter_colors.dart';
import 'warm_counter_color_tokens.dart';
import 'warm_counter_spacing.dart';
import 'warm_counter_typography.dart';

/// Configures and builds the ThemeData instances for the Chapter 34 Street-Food / Mafia restaurant interface.
///
/// Produces a high-contrast, dark-first desktop experience with strict adherence to:
/// - 48px minimum touch targets.
/// - Tabular figures on prices, financial numbers, quantities, and data tables.
/// - Flat surfaces with 1px border outlines (zero heavy shadows or gradients).
/// - Cartel Yellow primary CTAs with dark readable text and visible focus indicator.
/// - Compact data tables with clear contrast across Windows scaling factors (100%, 125%, 150%).
abstract final class WarmCounterTheme {
  // ---------------------------------------------------------------------------
  // Street-Food / Mafia Theme Builder (Authoritative Dark Aesthetic)
  // ---------------------------------------------------------------------------
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: StreetFoodMafiaColors.cartelYellow,
      onPrimary: StreetFoodMafiaColors.textOnPrimary,
      secondary: StreetFoodMafiaColors.burntGold,
      onSecondary: StreetFoodMafiaColors.textOnPrimary,
      error: StreetFoodMafiaColors.statusCanceled,
      onError: StreetFoodMafiaColors.textOnPrimary,
      surface: StreetFoodMafiaColors.cardSurface,
      onSurface: StreetFoodMafiaColors.offWhite,
      outline: StreetFoodMafiaColors.border,
      outlineVariant: StreetFoodMafiaColors.borderSubtle,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: StreetFoodMafiaColors.obsidian,
      fontFamily: WarmCounterTypography.fontFamily,
      fontFamilyFallback: WarmCounterTypography.fontFallbacks,
      textTheme: WarmCounterTypography.createTextTheme(
        StreetFoodMafiaColors.offWhite,
        StreetFoodMafiaColors.secondaryText,
      ),
      cardTheme: const CardThemeData(
        color: StreetFoodMafiaColors.cardSurface,
        elevation: 0.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          side: BorderSide(
            color: StreetFoodMafiaColors.border,
            width: 1.0,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: StreetFoodMafiaColors.darkNavy,
        foregroundColor: StreetFoodMafiaColors.offWhite,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: WarmCounterTypography.pageHeading,
        iconTheme: IconThemeData(
          color: StreetFoodMafiaColors.offWhite,
          size: 24.0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: StreetFoodMafiaColors.cartelYellow,
          foregroundColor: StreetFoodMafiaColors.textOnPrimary,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WarmCounterSpacing.space16,
            vertical: WarmCounterSpacing.space12,
          ),
          elevation: 0.0,
          shadowColor: Colors.transparent,
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium.copyWith(
            color: StreetFoodMafiaColors.textOnPrimary,
            fontWeight: FontWeight.w700,
          ),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: Colors.white, width: 2.0);
            }
            return BorderSide.none;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: StreetFoodMafiaColors.offWhite,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WarmCounterSpacing.space16,
            vertical: WarmCounterSpacing.space12,
          ),
          side: const BorderSide(
            color: StreetFoodMafiaColors.border,
            width: 1.0,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium,
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: StreetFoodMafiaColors.cartelYellow, width: 2.0);
            }
            return const BorderSide(color: StreetFoodMafiaColors.border, width: 1.0);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: StreetFoodMafiaColors.cartelYellow,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: StreetFoodMafiaColors.darkNavy,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WarmCounterSpacing.space16,
          vertical: 14.0,
        ),
        border: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: StreetFoodMafiaColors.border,
            width: 1.0,
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: StreetFoodMafiaColors.border,
            width: 1.0,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: StreetFoodMafiaColors.cartelYellow,
            width: 2.0,
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: StreetFoodMafiaColors.statusCanceled,
            width: 1.0,
          ),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: StreetFoodMafiaColors.statusCanceled,
            width: 2.0,
          ),
        ),
        labelStyle: WarmCounterTypography.secondaryLabel.copyWith(
          color: StreetFoodMafiaColors.secondaryText,
        ),
        hintStyle: WarmCounterTypography.body.copyWith(
          color: StreetFoodMafiaColors.secondaryText.withValues(alpha: 0.7),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: StreetFoodMafiaColors.border,
        thickness: 1.0,
        space: 1.0,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(StreetFoodMafiaColors.darkNavy),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return StreetFoodMafiaColors.darkNavy;
          }
          return StreetFoodMafiaColors.cardSurface;
        }),
        headingTextStyle: WarmCounterTypography.secondaryLabelMedium.copyWith(
          color: StreetFoodMafiaColors.offWhite,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: WarmCounterTypography.tableAmount.copyWith(
          color: StreetFoodMafiaColors.offWhite,
        ),
        dividerThickness: 1.0,
        dataRowMinHeight: 38.0,
        dataRowMaxHeight: 46.0,
        headingRowHeight: 44.0,
        horizontalMargin: WarmCounterSpacing.space16,
        columnSpacing: WarmCounterSpacing.space16,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: StreetFoodMafiaColors.darkNavy,
        indicatorColor: StreetFoodMafiaColors.activeNavHighlight,
        selectedIconTheme: IconThemeData(
          color: StreetFoodMafiaColors.cartelYellow,
          size: 24.0,
        ),
        unselectedIconTheme: IconThemeData(
          color: StreetFoodMafiaColors.secondaryText,
          size: 24.0,
        ),
        selectedLabelTextStyle: TextStyle(
          fontFamily: WarmCounterTypography.fontFamily,
          fontSize: 14.0,
          fontWeight: FontWeight.w700,
          color: StreetFoodMafiaColors.offWhite,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: WarmCounterTypography.fontFamily,
          fontSize: 14.0,
          fontWeight: FontWeight.w400,
          color: StreetFoodMafiaColors.secondaryText,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: StreetFoodMafiaColors.cardSurface,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          side: BorderSide(
            color: StreetFoodMafiaColors.border,
            width: 1.0,
          ),
        ),
        titleTextStyle: WarmCounterTypography.pageHeading,
        contentTextStyle: WarmCounterTypography.body,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        StreetFoodMafiaColorTokens.dark,
      ],
    );
  }

  /// Default theme builder aliased to darkTheme for authoritative Chapter 34 aesthetic.
  static ThemeData get lightTheme => darkTheme;
}

/// Official Chapter 34 theme alias.
abstract final class StreetFoodMafiaTheme {
  static ThemeData get theme => WarmCounterTheme.darkTheme;
}
