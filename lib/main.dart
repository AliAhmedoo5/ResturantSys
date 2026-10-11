import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'core/database/pos_database.dart';
import 'core/auth/auth_service.dart';
import 'core/theme/warm_counter_theme.dart';
import 'widgets/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite FFI on desktop platforms (Windows, Linux, macOS)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final posDatabase = PosDatabase();
  final database = await posDatabase.initialize();
  final authService = AuthService(database: database);

  runApp(RestaurantPosApp(authService: authService));
}

/// Root widget of the Restaurant POS desktop application.
class RestaurantPosApp extends StatelessWidget {
  const RestaurantPosApp({
    super.key,
    required this.authService,
  });

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResturantPOS',
      debugShowCheckedModeBanner: false,
      theme: WarmCounterTheme.lightTheme,
      darkTheme: WarmCounterTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: AppShell(
        session: authService.session,
        onAuthenticatePin: authService.authenticateWithPin,
      ),
    );
  }
}
