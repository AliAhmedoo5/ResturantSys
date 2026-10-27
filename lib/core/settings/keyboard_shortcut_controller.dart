import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'managed_configuration.dart';

class KeyboardShortcutController {
  KeyboardShortcutController(this.database);
  final Database database;
  static const settingKey = 'keyboard_shortcuts';
  static final actionLabels = <String, String>{
    'checkout': 'Checkout', 'checkoutAlternate': 'Checkout (alternate)', 'clear': 'Clear cart',
    'hold': 'Hold cart', 'recall': 'Recall held cart', 'customers': 'Customers', 'search': 'Search menu',
    for (var i = 1; i <= 12; i++) 'category$i': 'Category $i',
  };
  static final defaults = <String, String>{
    'checkout': 'Space', 'checkoutAlternate': 'Numpad Enter', 'clear': 'Escape',
    'hold': '', 'recall': '', 'customers': '', 'search': '',
    for (var i = 1; i <= 12; i++) 'category$i': 'F$i',
  };
  // Deliberately excludes Alt, Windows, OS and accessibility combinations.
  static final allowedKeys = <String>['', 'Space', 'Numpad Enter', 'Escape',
    for (var i = 1; i <= 12; i++) 'F$i',
    for (var i = 1; i <= 12; i++) 'Shift+F$i'];

  Future<Map<String, String>> load() async {
    final rows = await database.query('system_settings', where: 'key=?', whereArgs: [settingKey]);
    final result = rows.isEmpty ? Map<String, String>.from(defaults)
      : Map<String, String>.from(jsonDecode(rows.single['value'] as String) as Map);
    validate(result);
    return result;
  }

  static void validate(Map<String, String> bindings) {
    if (bindings.length != defaults.length || !defaults.keys.every(bindings.containsKey) ||
        bindings.values.any((v) => !allowedKeys.contains(v))) throw ArgumentError('Unsupported shortcut action or reserved key.');
    final assigned = bindings.values.where((v) => v.isNotEmpty).toList();
    if (assigned.toSet().length != assigned.length) throw ArgumentError('Each key can be assigned only once in the cashier context.');
  }

  Future<void> save({required int managerId, required Map<String, String> bindings, required Map<String, String> expected}) async {
    validate(bindings);
    await database.transaction((txn) async {
      await requireManager(txn, managerId);
      final rows = await txn.query('system_settings', where: 'key=?', whereArgs: [settingKey]);
      final current = rows.isEmpty ? Map<String, String>.from(defaults)
        : Map<String, String>.from(jsonDecode(rows.single['value'] as String) as Map);
      if (current.length != expected.length || current.entries.any((e) => expected[e.key] != e.value)) {
        throw StateError('Shortcuts changed in another session. Reopen settings.');
      }
      await txn.insert('system_settings', {'key': settingKey, 'value': jsonEncode(bindings),
        'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
      await auditConfiguration(txn, managerId, 'SHORTCUTS', current, bindings);
    });
  }

  Future<Map<String, String>> prior(int managerId) async {
    await requireManager(database, managerId);
    final rows = await database.query('configuration_audit', where: "kind='SHORTCUTS'", orderBy: 'id DESC', limit: 1);
    return rows.isEmpty ? Map<String, String>.from(defaults)
      : Map<String, String>.from(jsonDecode(rows.single['before_json'] as String) as Map);
  }
}
