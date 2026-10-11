import 'package:flutter/material.dart';
import 'warm_counter_colors.dart';
import 'warm_counter_color_tokens.dart';
import 'warm_counter_spacing.dart';
import 'warm_counter_typography.dart';

/// Configures and builds the ThemeData instances for the Warm Counter restaurant interface.
///
/// Produces a clean, calm, and glare-free desktop experience with strict adherence to:
/// - 48px minimum touch targets.
/// - Tabular figures on prices and numerical data.
/// - Flat surfaces with 1px border outlines (zero heavy shadows or gradients).
/// - Deep green affirmative actions and pale green active states.
abstract final class WarmCounterTheme {
  // ---------------------------------------------------------------------------
  // Light Mode Theme Builder
  // ---------------------------------------------------------------------------
  static ThemeData get lightTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: WarmCounterColors.lightPrimaryAction,
      onPrimary: WarmCounterColors.lightTextOnPrimary,
      secondary: WarmCounterColors.lightSecondaryText,
      onSecondary: Colors.white,
      error: WarmCounterColors.lightDestructive,
      onError: Colors.white,
      surface: WarmCounterColors.lightCardBackground,
      onSurface: WarmCounterColors.lightPrimaryText,
      outline: WarmCounterColors.lightBorder,
      outlineVariant: WarmCounterColors.lightBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: WarmCounterColors.lightPageBackground,
      fontFamily: WarmCounterTypography.fontFamily,
      fontFamilyFallback: WarmCounterTypography.fontFallbacks,
      textTheme: WarmCounterTypography.createTextTheme(
        WarmCounterColors.lightPrimaryText,
        WarmCounterColors.lightSecondaryText,
      ),
      cardTheme: const CardThemeData(
        color: WarmCounterColors.lightCardBackground,
        elevation: 0.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          side: BorderSide(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: WarmCounterColors.lightCardBackground,
        foregroundColor: WarmCounterColors.lightPrimaryText,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: WarmCounterTypography.pageHeading,
        iconTheme: IconThemeData(
          color: WarmCounterColors.lightPrimaryText,
          size: 24.0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WarmCounterColors.lightPrimaryAction,
          foregroundColor: WarmCounterColors.lightTextOnPrimary,
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
            color: WarmCounterColors.lightTextOnPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WarmCounterColors.lightPrimaryText,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WarmCounterSpacing.space16,
            vertical: WarmCounterSpacing.space12,
          ),
          side: const BorderSide(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WarmCounterColors.lightPrimaryAction,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WarmCounterColors.lightCardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WarmCounterSpacing.space16,
          vertical: 14.0,
        ),
        border: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.lightPrimaryAction,
            width: 2.0,
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.lightDestructive,
            width: 1.0,
          ),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.lightDestructive,
            width: 2.0,
          ),
        ),
        labelStyle: WarmCounterTypography.secondaryLabel.copyWith(
          color: WarmCounterColors.lightSecondaryText,
        ),
        hintStyle: WarmCounterTypography.body.copyWith(
          color: WarmCounterColors.lightSecondaryText.withValues(alpha: 0.7),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: WarmCounterColors.lightBorder,
        thickness: 1.0,
        space: 1.0,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: WarmCounterColors.lightCardBackground,
        indicatorColor: WarmCounterColors.lightActiveNavHighlight,
        selectedIconTheme: IconThemeData(
          color: WarmCounterColors.lightPrimaryAction,
          size: 24.0,
        ),
        unselectedIconTheme: IconThemeData(
          color: WarmCounterColors.lightSecondaryText,
          size: 24.0,
        ),
        selectedLabelTextStyle: TextStyle(
          fontFamily: WarmCounterTypography.fontFamily,
          fontSize: 14.0,
          fontWeight: FontWeight.w600,
          color: WarmCounterColors.lightPrimaryText,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: WarmCounterTypography.fontFamily,
          fontSize: 14.0,
          fontWeight: FontWeight.w400,
          color: WarmCounterColors.lightSecondaryText,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: WarmCounterColors.lightCardBackground,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          side: BorderSide(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
        ),
        titleTextStyle: WarmCounterTypography.pageHeading,
        contentTextStyle: WarmCounterTypography.body,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        WarmCounterColorTokens.light,
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Dark Mode Theme Builder
  // ---------------------------------------------------------------------------
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: WarmCounterColors.darkPrimaryAction,
      onPrimary: WarmCounterColors.darkTextOnPrimary,
      secondary: WarmCounterColors.darkSecondaryText,
      onSecondary: Colors.black,
      error: WarmCounterColors.darkDestructive,
      onError: Colors.black,
      surface: WarmCounterColors.darkCardBackground,
      onSurface: WarmCounterColors.darkPrimaryText,
      outline: WarmCounterColors.darkBorder,
      outlineVariant: WarmCounterColors.darkBorder,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: WarmCounterColors.darkPageBackground,
      fontFamily: WarmCounterTypography.fontFamily,
      fontFamilyFallback: WarmCounterTypography.fontFallbacks,
      textTheme: WarmCounterTypography.createTextTheme(
        WarmCounterColors.darkPrimaryText,
        WarmCounterColors.darkSecondaryText,
      ),
      cardTheme: const CardThemeData(
        color: WarmCounterColors.darkCardBackground,
        elevation: 0.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          side: BorderSide(
            color: WarmCounterColors.darkBorder,
            width: 1.0,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: WarmCounterColors.darkCardBackground,
        foregroundColor: WarmCounterColors.darkPrimaryText,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: WarmCounterTypography.pageHeading,
        iconTheme: IconThemeData(
          color: WarmCounterColors.darkPrimaryText,
          size: 24.0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WarmCounterColors.darkPrimaryAction,
          foregroundColor: WarmCounterColors.darkTextOnPrimary,
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
            color: WarmCounterColors.darkTextOnPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: WarmCounterColors.darkPrimaryText,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WarmCounterSpacing.space16,
            vertical: WarmCounterSpacing.space12,
          ),
          side: const BorderSide(
            color: WarmCounterColors.darkBorder,
            width: 1.0,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: WarmCounterColors.darkPrimaryAction,
          minimumSize: const Size(
            WarmCounterSpacing.minTouchTargetSize,
            WarmCounterSpacing.minTouchTargetSize,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.controlBorderRadius,
          ),
          textStyle: WarmCounterTypography.bodyMedium,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WarmCounterColors.darkCardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: WarmCounterSpacing.space16,
          vertical: 14.0,
        ),
        border: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.darkBorder,
            width: 1.0,
          ),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.darkBorder,
            width: 1.0,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.darkPrimaryAction,
            width: 2.0,
          ),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.darkDestructive,
            width: 1.0,
          ),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          borderSide: BorderSide(
            color: WarmCounterColors.darkDestructive,
            width: 2.0,
          ),
        ),
        labelStyle: WarmCounterTypography.secondaryLabel.copyWith(
          color: WarmCounterColors.darkSecondaryText,
        ),
        hintStyle: WarmCounterTypography.body.copyWith(
          color: WarmCounterColors.darkSecondaryText.withValues(alpha: 0.7),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: WarmCounterColors.darkBorder,
        thickness: 1.0,
        space: 1.0,
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: WarmCounterColors.darkCardBackground,
        indicatorColor: WarmCounterColors.darkActiveNavHighlight,
        selectedIconTheme: IconThemeData(
          color: WarmCounterColors.darkPrimaryAction,
          size: 24.0,
        ),
        unselectedIconTheme: IconThemeData(
          color: WarmCounterColors.darkSecondaryText,
          size: 24.0,
        ),
        selectedLabelTextStyle: TextStyle(
          fontFamily: WarmCounterTypography.fontFamily,
          fontSize: 14.0,
          fontWeight: FontWeight.w600,
          color: WarmCounterColors.darkPrimaryText,
        ),
        unselectedLabelTextStyle: TextStyle(
          fontFamily: WarmCounterTypography.fontFamily,
          fontSize: 14.0,
          fontWeight: FontWeight.w400,
          color: WarmCounterColors.darkSecondaryText,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: WarmCounterColors.darkCardBackground,
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          side: BorderSide(
            color: WarmCounterColors.darkBorder,
            width: 1.0,
          ),
        ),
        titleTextStyle: WarmCounterTypography.pageHeading,
        contentTextStyle: WarmCounterTypography.body,
      ),
      extensions: const <ThemeExtension<dynamic>>[
        WarmCounterColorTokens.dark,
      ],
    );
  }
}
