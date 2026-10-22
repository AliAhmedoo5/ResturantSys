import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/orders/token_status.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/app_header.dart';

void main() {
  group('Chapter 34 Street-Food / Mafia Branding Theme Tokens', () {
    test('exact 6 authoritative Chapter 34 hex tokens are defined', () {
      expect(StreetFoodMafiaColors.obsidian, equals(const Color(0xFF050708)));
      expect(StreetFoodMafiaColors.darkNavy, equals(const Color(0xFF101820)));
      expect(StreetFoodMafiaColors.cartelYellow, equals(const Color(0xFFFFC400)));
      expect(StreetFoodMafiaColors.burntGold, equals(const Color(0xFFF5A623)));
      expect(StreetFoodMafiaColors.offWhite, equals(const Color(0xFFF5F7FA)));
      expect(StreetFoodMafiaColors.cardSurface, equals(const Color(0xFF14242D)));
    });

    test('BrandPalette is a direct alias of StreetFoodMafiaColors', () {
      expect(BrandPalette.obsidian, equals(const Color(0xFF050708)));
      expect(BrandPalette.darkNavy, equals(const Color(0xFF101820)));
      expect(BrandPalette.cartelYellow, equals(const Color(0xFFFFC400)));
      expect(BrandPalette.burntGold, equals(const Color(0xFFF5A623)));
      expect(BrandPalette.offWhite, equals(const Color(0xFFF5F7FA)));
      expect(BrandPalette.cardSurface, equals(const Color(0xFF14242D)));
    });

    test('legacy WarmCounterColors alias directly to Chapter 34 tokens', () {
      expect(WarmCounterColors.lightPageBackground, equals(StreetFoodMafiaColors.obsidian));
      expect(WarmCounterColors.darkPageBackground, equals(StreetFoodMafiaColors.obsidian));
      expect(WarmCounterColors.lightCardBackground, equals(StreetFoodMafiaColors.cardSurface));
      expect(WarmCounterColors.darkCardBackground, equals(StreetFoodMafiaColors.cardSurface));
      expect(WarmCounterColors.lightPrimaryAction, equals(StreetFoodMafiaColors.cartelYellow));
      expect(WarmCounterColors.darkPrimaryAction, equals(StreetFoodMafiaColors.cartelYellow));
      expect(WarmCounterColors.lightTextOnPrimary, equals(StreetFoodMafiaColors.textOnPrimary));
      expect(WarmCounterColors.darkTextOnPrimary, equals(StreetFoodMafiaColors.textOnPrimary));
      expect(WarmCounterColors.lightPrimaryText, equals(StreetFoodMafiaColors.offWhite));
      expect(WarmCounterColors.darkPrimaryText, equals(StreetFoodMafiaColors.offWhite));
      expect(WarmCounterColors.lightBorder, equals(StreetFoodMafiaColors.border));
      expect(WarmCounterColors.darkBorder, equals(StreetFoodMafiaColors.border));
      expect(WarmCounterColors.lightSurfaceMuted, equals(StreetFoodMafiaColors.darkNavy));
    });

    test('primary Cartel Yellow CTA text contrast ratio satisfies WCAG AAA (> 7:1)', () {
      // Calculate relative luminance per WCAG 2.1 specs
      double luminance(Color c) {
        double channel(double v) => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
      }

      final lYellow = luminance(StreetFoodMafiaColors.cartelYellow);
      final lText = luminance(StreetFoodMafiaColors.textOnPrimary);
      final ratio = (lYellow + 0.05) / (lText + 0.05);

      // Cartel Yellow #FFC400 against dark Obsidian #050708 exceeds 11:1 contrast ratio
      expect(ratio, greaterThan(11.0));
      // White on Cartel Yellow would fail WCAG contrast (~1.1:1)
      final lWhite = luminance(Colors.white);
      final whiteRatio = (lWhite + 0.05) / (lYellow + 0.05);
      expect(whiteRatio, lessThan(2.0));
    });

    test('offWhite text on dark surfaces satisfies WCAG AAA (> 11:1)', () {
      double luminance(Color c) {
        double channel(double v) => v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
      }

      final lWhite = luminance(StreetFoodMafiaColors.offWhite);
      final lCard = luminance(StreetFoodMafiaColors.cardSurface);
      final lObsidian = luminance(StreetFoodMafiaColors.obsidian);

      expect((lWhite + 0.05) / (lCard + 0.05), greaterThan(11.0));
      expect((lWhite + 0.05) / (lObsidian + 0.05), greaterThan(15.0));
    });

    test('parseHex utility parses 6-digit and 8-digit hex codes', () {
      expect(StreetFoodMafiaColors.parseHex('#FFC400'), equals(const Color(0xFFFFC400)));
      expect(StreetFoodMafiaColors.parseHex('101820'), equals(const Color(0xFF101820)));
      expect(StreetFoodMafiaColors.parseHex('invalid', fallback: Colors.red), equals(Colors.red));
    });
  });

  group('Chapter 34 Semantic Status Tokens & Badge Requirements', () {
    test('semantic status color tokens match Chapter 34 specification', () {
      expect(StreetFoodMafiaColors.statusReady, equals(const Color(0xFF58C78A)));
      expect(StreetFoodMafiaColors.statusPreparing, equals(const Color(0xFFF5A623)));
      expect(StreetFoodMafiaColors.statusOutForDelivery, equals(const Color(0xFF6BAEFF)));
      expect(StreetFoodMafiaColors.statusCanceled, equals(const Color(0xFFF47F7F)));
    });

    testWidgets('SemanticStatusBadge.ready renders both green outline icon and text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SemanticStatusBadge.ready(label: 'Ready on Pass'),
          ),
        ),
      );

      expect(find.text('Ready on Pass'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline_rounded));
      expect(iconWidget.color, equals(StreetFoodMafiaColors.statusReady));
    });

    testWidgets('SemanticStatusBadge.preparing renders both amber outline icon and text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SemanticStatusBadge.preparing(label: 'Preparing in Kitchen'),
          ),
        ),
      );

      expect(find.text('Preparing in Kitchen'), findsOneWidget);
      expect(find.byIcon(Icons.soup_kitchen_outlined), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.soup_kitchen_outlined));
      expect(iconWidget.color, equals(StreetFoodMafiaColors.statusPreparing));
    });

    testWidgets('SemanticStatusBadge.outForDelivery renders both blue outline icon and text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SemanticStatusBadge.outForDelivery(label: 'Out for Delivery'),
          ),
        ),
      );

      expect(find.text('Out for Delivery'), findsOneWidget);
      expect(find.byIcon(Icons.delivery_dining_outlined), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.delivery_dining_outlined));
      expect(iconWidget.color, equals(StreetFoodMafiaColors.statusOutForDelivery));
    });

    testWidgets('SemanticStatusBadge.canceled renders both red outline icon and text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SemanticStatusBadge.canceled(label: 'Canceled Order'),
          ),
        ),
      );

      expect(find.text('Canceled Order'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.cancel_outlined));
      expect(iconWidget.color, equals(StreetFoodMafiaColors.statusCanceled));
    });

    testWidgets('SemanticStatusBadge.fromTokenStatus resolves appropriate status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SemanticStatusBadge.fromTokenStatus(TokenStatus.ready),
                SemanticStatusBadge.fromTokenStatus(TokenStatus.preparing),
                SemanticStatusBadge.fromTokenStatus(TokenStatus.outForDelivery),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Ready on Pass'), findsOneWidget);
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Out for Delivery'), findsOneWidget);
    });
  });

  group('Chapter 34 Outline Icons and App Navigation Adherence', () {
    test('AppWorkspaceTab definitions use outline icons throughout', () {
      expect(AppWorkspaceTab.register.icon, equals(Icons.point_of_sale_outlined));
      expect(AppWorkspaceTab.catalog.icon, equals(Icons.restaurant_menu_outlined));
      expect(AppWorkspaceTab.khata.icon, equals(Icons.menu_book_outlined));
      expect(AppWorkspaceTab.mandi.icon, equals(Icons.shopping_basket_outlined));
      expect(AppWorkspaceTab.wastage.icon, equals(Icons.delete_outline_rounded));
      expect(AppWorkspaceTab.supervisor.icon, equals(Icons.admin_panel_settings_outlined));
      expect(AppWorkspaceTab.tokenQueue.icon, equals(Icons.confirmation_number_outlined));
    });
  });

  group('Chapter 34 ThemeData & DataTable Theme Adherence', () {
    test('ThemeData darkTheme adopts Street-Food / Mafia palette and DataTableTheme', () {
      final theme = WarmCounterTheme.darkTheme;

      expect(theme.brightness, equals(Brightness.dark));
      expect(theme.scaffoldBackgroundColor, equals(StreetFoodMafiaColors.obsidian));
      expect(theme.colorScheme.primary, equals(StreetFoodMafiaColors.cartelYellow));
      expect(theme.colorScheme.onPrimary, equals(StreetFoodMafiaColors.textOnPrimary));
      expect(theme.colorScheme.surface, equals(StreetFoodMafiaColors.cardSurface));
      expect(theme.colorScheme.onSurface, equals(StreetFoodMafiaColors.offWhite));
      expect(theme.appBarTheme.backgroundColor, equals(StreetFoodMafiaColors.darkNavy));

      // DataTable Theme
      final dataTableTheme = theme.dataTableTheme;
      expect(dataTableTheme.dataRowMinHeight, equals(38.0));
      expect(dataTableTheme.dataRowMaxHeight, equals(46.0));
      expect(dataTableTheme.headingRowHeight, equals(44.0));
      expect(dataTableTheme.headingRowColor?.resolve({}), equals(StreetFoodMafiaColors.darkNavy));
      expect(dataTableTheme.dataRowColor?.resolve({}), equals(StreetFoodMafiaColors.cardSurface));
      expect(
        dataTableTheme.dataTextStyle?.fontFeatures?.any((f) => f.feature == 'tnum'),
        isTrue,
      );
    });

    test('WarmCounterTheme.lightTheme defaults to dark Street-Food / Mafia aesthetic', () {
      final lightTheme = WarmCounterTheme.lightTheme;
      expect(lightTheme.brightness, equals(Brightness.dark));
      expect(lightTheme.scaffoldBackgroundColor, equals(StreetFoodMafiaColors.obsidian));
      expect(lightTheme.colorScheme.primary, equals(StreetFoodMafiaColors.cartelYellow));
    });
  });
}
