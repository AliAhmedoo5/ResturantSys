import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/khata/vendor.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/khata/vendor_statement.dart';
import 'package:resturant_sys/core/khata/vendor_transaction.dart';
import 'package:resturant_sys/core/theme/warm_counter_theme.dart';
import 'package:resturant_sys/widgets/khata/credit_delivery_dialog.dart';
import 'package:resturant_sys/widgets/khata/settlement_payment_dialog.dart';
import 'package:resturant_sys/widgets/khata/vendor_form_dialog.dart';
import 'package:resturant_sys/widgets/khata/vendor_khata_workspace.dart';

void main() {
  group('VendorKhataWorkspace & Dialogs Widget Tests', () {
    const testStaff = Staff(
      id: 1,
      name: 'Supervisor Ali',
      departmentId: 1,
      departmentName: 'Management',
      pinHash: 'hash',
      role: StaffRole.supervisor,
      isActive: true,
    );

    testWidgets('VendorFormDialog validates inputs and submits supplier data', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Map<String, dynamic>? formResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_vendor_dialog_btn'),
                  onPressed: () async {
                    formResult = await VendorFormDialog.show(ctx);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_vendor_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.text('New Supplier (Vendor)'), findsOneWidget);

      // Attempt to save without inputs -> shows validation errors
      await tester.tap(find.byKey(const Key('save_vendor_button')));
      await tester.pumpAndSettle();
      expect(find.text('Please enter vendor name'), findsOneWidget);

      // Fill in valid details
      await tester.enterText(
        find.byKey(const Key('vendor_name_field')),
        'Chenab Poultry',
      );
      await tester.enterText(
        find.byKey(const Key('vendor_phone_field')),
        '03001234567',
      );
      await tester.enterText(
        find.byKey(const Key('vendor_ingredients_field')),
        'Chicken Boneless, Wings',
      );
      await tester.enterText(
        find.byKey(const Key('vendor_opening_balance_field')),
        '8500.00',
      );

      await tester.tap(find.byKey(const Key('save_vendor_button')));
      await tester.pumpAndSettle();

      expect(formResult, isNotNull);
      expect(formResult!['name'], equals('Chenab Poultry'));
      expect(formResult!['phone'], equals('03001234567'));
      expect(formResult!['supplied_ingredients'], equals('Chicken Boneless, Wings'));
      expect(formResult!['opening_balance'], equals(8500.0));
    });

    testWidgets('CreditDeliveryDialog validates amount and returns delivery data', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final vendor = Vendor(
        id: 1,
        name: 'Khyber Spices',
        phone: '03129876543',
        openingBalance: 2000.0,
        currentBalance: 2000.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      Map<String, dynamic>? deliveryResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_delivery_dialog_btn'),
                  onPressed: () async {
                    deliveryResult = await CreditDeliveryDialog.show(
                      ctx,
                      vendor: vendor,
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_delivery_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Log Credit Delivery'), findsOneWidget);
      expect(find.text('Khyber Spices'), findsOneWidget);

      // Fill in details
      await tester.enterText(
        find.byKey(const Key('credit_amount_field')),
        '12000',
      );
      await tester.enterText(
        find.byKey(const Key('credit_slip_field')),
        'SLIP-894',
      );
      await tester.enterText(
        find.byKey(const Key('credit_notes_field')),
        'Spices and garlic powder delivery',
      );

      await tester.tap(find.byKey(const Key('confirm_credit_delivery_button')));
      await tester.pumpAndSettle();

      expect(deliveryResult, isNotNull);
      expect(deliveryResult!['amount'], equals(12000.0));
      expect(deliveryResult!['reference_slip'], equals('SLIP-894'));
      expect(deliveryResult!['notes'], equals('Spices and garlic powder delivery'));
    });

    testWidgets('SettlementPaymentDialog supports dual payment sources', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final vendor = Vendor(
        id: 1,
        name: 'Makkah Oil Traders',
        phone: '03215556667',
        openingBalance: 15000.0,
        currentBalance: 15000.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      Map<String, dynamic>? settlementResult;

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open_settle_dialog_btn'),
                  onPressed: () async {
                    settlementResult = await SettlementPaymentDialog.show(
                      ctx,
                      vendor: vendor,
                      activeShiftId: 5,
                      activeStaffName: 'Cashier Ahmed',
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open_settle_dialog_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Settle Supplier Balance'), findsOneWidget);
      expect(find.text('Paid from Active Drawer'), findsOneWidget);
      expect(find.text('Paid Outside Drawer'), findsOneWidget);

      // Default with activeShiftId is drawer
      // Toggle to outside drawer
      await tester.tap(find.byKey(const Key('source_external_tile')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('settlement_amount_field')),
        '10000',
      );
      await tester.enterText(
        find.byKey(const Key('settlement_slip_field')),
        'BANK-FT-99',
      );
      await tester.enterText(
        find.byKey(const Key('settlement_notes_field')),
        'HBL transfer by owner',
      );

      await tester.tap(find.byKey(const Key('confirm_settlement_button')));
      await tester.pumpAndSettle();

      expect(settlementResult, isNotNull);
      expect(settlementResult!['amount'], equals(10000.0));
      expect(settlementResult!['payment_source'], equals(VendorPaymentSource.paidOutsideDrawer));
      expect(settlementResult!['reference_slip'], equals('BANK-FT-99'));
    });

    testWidgets('VendorKhataWorkspace renders directory, filters by search, and shows statements', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Pre-seed 2 vendors
      final v1 = Vendor(
        id: 1,
        name: 'Al-Siddiq Poultry',
        phone: '03001112233',
        suppliedIngredients: 'Chicken Fillets',
        openingBalance: 5000.0,
        currentBalance: 20000.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final v2 = Vendor(
        id: 2,
        name: 'Bilal Packaging',
        phone: '03451112233',
        suppliedIngredients: 'Burger Boxes, Wrapping',
        openingBalance: 0.0,
        currentBalance: 0.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final statement = VendorStatement(
        vendor: v1,
        openingBalance: 5000.0,
        currentBalance: 20000.0,
        entries: [
          VendorStatementEntry(
            transaction: VendorTransaction(
              id: 1,
              vendorId: 1,
              type: VendorTransactionType.purchaseCredit,
              amount: 15000.0,
              referenceSlip: 'BILL-100',
              notes: 'Chicken fillets delivery',
              staffId: 1,
              createdAt: DateTime.now(),
            ),
            creditAmount: 15000.0,
            debitAmount: 0.0,
            runningBalance: 20000.0,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: WarmCounterTheme.lightTheme,
          home: Material(
            child: VendorKhataWorkspace(
              currentStaff: testStaff,
              initialVendors: [v1, v2],
              initialSelectedVendor: v1,
              initialStatement: statement,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top control bar
      expect(find.text('Vendor Khata (Supplier Credit Ledger)'), findsOneWidget);
      expect(find.byKey(const Key('add_supplier_button')), findsOneWidget);

      // Directory list contains both vendors
      expect(find.text('Al-Siddiq Poultry'), findsWidgets);
      expect(find.text('Bilal Packaging'), findsWidgets);

      // Net payable for Al-Siddiq is 20,000
      expect(find.textContaining('20,000.00'), findsWidgets);

      // Search filter
      await tester.enterText(find.byKey(const Key('vendor_search_field')), 'Packaging');
      await tester.pumpAndSettle();

      expect(find.text('Bilal Packaging'), findsWidgets);
      expect(find.text('Al-Siddiq Poultry'), findsNothing);

      // Clear search
      await tester.enterText(find.byKey(const Key('vendor_search_field')), '');
      await tester.pumpAndSettle();

      expect(find.text('Al-Siddiq Poultry'), findsWidgets);

      // Select Al-Siddiq Poultry
      await tester.tap(find.byKey(Key('vendor_tile_${v1.id}')), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Statement view shows delivery line
      expect(find.text('Statement of Accounts'), findsOneWidget);
      expect(find.text('BILL-100'), findsOneWidget);
      expect(find.text('Credit Delivery'), findsWidgets);
      expect(find.byKey(const Key('log_credit_delivery_button')), findsOneWidget);
      expect(find.byKey(const Key('settle_payment_button')), findsOneWidget);
    });
  });
}
