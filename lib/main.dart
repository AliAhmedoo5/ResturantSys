import 'core/database/database_restore_service.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/database/pos_database.dart';
import 'core/auth/auth_service.dart';
import 'core/shifts/shift_and_cash_controller.dart';
import 'core/shifts/report_delivery_service.dart';
import 'core/catalog/catalog_and_recipe_controller.dart';
import 'core/orders/order_and_checkout_controller.dart';
import 'core/procurement/procurement_and_wastage_controller.dart';
import 'core/khata/vendor_khata_controller.dart';
import 'core/theme/warm_counter_theme.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI on desktop platforms (Windows, Linux, macOS)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  String? restoreMessage;
  try {
    restoreMessage = await DatabaseRestoreService.applyPending(databasePath: PosDatabase.resolveDefaultDatabasePath());
  } catch (error) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 640, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Backup restoration could not finish', style: TextStyle(fontSize: 24)),
      const SizedBox(height: 16), SelectableText('$error'),
      const Text('Original data and the safety backup are retained. Retry after resolving the reported problem.'),
      FilledButton(onPressed: main, child: const Text('Retry restoration')),
    ]))))));
    return;
  }
  final posDatabase = PosDatabase(seedDefaultStaff: false);
  final database = await posDatabase.initialize();
  ReportDeliveryService(database:database).start();
  final authService = AuthService(database: database);
  final shiftController = ShiftAndCashController(database: database);
  final catalogController = CatalogAndRecipeController(database: database);
  final orderController = OrderAndCheckoutController(database: database);
  final procurementController = ProcurementAndWastageController(
    database: database,
    authService: authService,
  );
  final vendorKhataController = VendorKhataController(
    database: database,
    shiftController: shiftController,
  );
  runApp(RestaurantPosApp(
    startupMessage: restoreMessage,
    authService: authService,
    shiftController: shiftController,
    catalogController: catalogController,
    orderController: orderController,
    procurementController: procurementController,
    vendorKhataController: vendorKhataController,
  ));
}

/// Root widget of the Restaurant POS desktop application.
class RestaurantPosApp extends StatelessWidget {
  const RestaurantPosApp({
    super.key,
    this.startupMessage,
    required this.authService,
    this.shiftController,
    this.catalogController,
    this.orderController,
    this.procurementController,
    this.vendorKhataController,
  });

  final String? startupMessage;
  final AuthService authService;
  final ShiftAndCashController? shiftController;
  final CatalogAndRecipeController? catalogController;
  final OrderAndCheckoutController? orderController;
  final ProcurementAndWastageController? procurementController;
  final VendorKhataController? vendorKhataController;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crunch Cartel POS',
      debugShowCheckedModeBanner: false,
      theme: WarmCounterTheme.darkTheme,
      darkTheme: WarmCounterTheme.darkTheme,
      themeMode: ThemeMode.dark,
      builder: (context, child) => Column(children: [
        if (startupMessage != null) Material(color: Theme.of(context).colorScheme.primaryContainer,
          child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.all(12), child: Text(startupMessage!)))),
        Expanded(child: child!),
      ]),
      home: AppShell(
        session: authService.session,
        onAuthenticatePin: authService.authenticateWithPin,
        shiftController: shiftController,
        catalogController: catalogController,
        orderController: orderController,
        procurementController: procurementController,
        vendorKhataController: vendorKhataController,
        authService: authService,
      ),
    );
  }
}
