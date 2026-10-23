import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../auth/staff_role.dart';

class DeliveryArea {
  DeliveryArea.fromMap(Map<String, Object?> row)
      : id = row['id'] as int,
        name = row['name'] as String,
        code = row['code'] as String? ?? '',
        coverageDescription = row['coverage_description'] as String? ?? '',
        deliveryFeePaisa = row['delivery_fee_paisa'] as int,
        minOrderPaisa = row['min_order_paisa'] as int,
        isActive = row['is_active'] == 1,
        isArchived = row['archived_at'] != null;
  final int id, deliveryFeePaisa, minOrderPaisa;
  final String name, code, coverageDescription;
  final bool isActive, isArchived;
}

/// Manager configuration and the counter's read-only delivery area directory.
class DeliveryController {
  DeliveryController({required this.database});
  final Database database;

  static String normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0092')) digits = '0${digits.substring(4)}';
    if (digits.startsWith('92')) digits = '0${digits.substring(2)}';
    return digits;
  }

  Future<List<CustomerAddress>> lookupAddresses(String phone) async {
    final normalized = normalizePhone(phone);
    if (normalized.length < 3) return [];
    final rows = await database.query('customer_addresses', where: 'customer_phone LIKE ?', whereArgs: ['$normalized%'],
      orderBy: 'is_default DESC, updated_at DESC, id DESC', limit: 30);
    return rows.map(CustomerAddress.fromMap).toList();
  }

  /// Runs only inside the caller's checkout transaction, before any stock or token writes.
  static Future<DeliveryArea> validateCheckout(DatabaseExecutor txn, DeliveryDetails details, int foodTotalPaisa) async {
    if (normalizePhone(details.phone).length < 7 || details.fullAddress.trim().isEmpty) {
      throw const DeliveryCheckoutException('Enter a customer phone and full delivery address. Your cart is unchanged.');
    }
    final rows = await txn.query('delivery_areas', where: 'id = ? AND is_active = 1 AND archived_at IS NULL', whereArgs: [details.areaId]);
    if (rows.isEmpty) throw const DeliveryCheckoutException('Delivery area is no longer available. Return to customer details and choose an active area. Your cart is unchanged.');
    final area = DeliveryArea.fromMap(rows.single);
    if (area.deliveryFeePaisa != details.quotedFeePaisa) throw const DeliveryCheckoutException('Delivery fee changed. Return to customer details to review the current fee. Your cart is unchanged.');
    if (foodTotalPaisa < area.minOrderPaisa) throw DeliveryCheckoutException('Minimum food order for ${area.name} is Rs ${(area.minOrderPaisa / 100).toStringAsFixed(2)} after discounts. Your cart is unchanged.');
    return area;
  }

  static Future<void> rememberAddress(DatabaseExecutor txn, DeliveryDetails details) async {
    final phone = normalizePhone(details.phone);
    final rows = await txn.query('customer_addresses', where: 'customer_phone = ? AND delivery_area_id = ? AND full_address = ?',
      whereArgs: [phone, details.areaId, details.fullAddress.trim()], limit: 1);
    final now = DateTime.now().toIso8601String();
    final values = <String, Object?>{'customer_phone': phone, 'customer_name': details.customerName.trim(),
      'delivery_area_id': details.areaId, 'full_address': details.fullAddress.trim(), 'landmark': details.landmark.trim(), 'notes': details.notes.trim(), 'updated_at': now};
    if (rows.isEmpty) {
      await txn.insert('customer_addresses', {...values, 'created_at': now});
    } else {
      await txn.update('customer_addresses', values, where: 'id = ?', whereArgs: [rows.single['id']]);
    }
  }

  Future<void> _requireManager(DatabaseExecutor db, int staffId) async {
    final rows = await db.query('staff', where: 'id = ? AND is_active = 1 AND login_enabled = 1', whereArgs: [staffId]);
    if (rows.isEmpty || StaffRole.fromCode(rows.single['role'] as String) != StaffRole.manager) {
      throw StateError('Only an active Manager can configure delivery areas and fees.');
    }
  }

  Future<List<DeliveryArea>> getAreas({bool activeOnly = false, bool includeArchived = false}) async {
    final conditions = [if (!includeArchived || activeOnly) 'archived_at IS NULL', if (activeOnly) 'is_active = 1'];
    final rows = await database.query('delivery_areas',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      orderBy: 'name COLLATE NOCASE, id');
    return rows.map(DeliveryArea.fromMap).toList();
  }

  Future<DeliveryArea> saveArea({required int staffId, int? id, required String name, required String code,
    String coverageDescription = '', required int deliveryFeePaisa, int minOrderPaisa = 0, bool isActive = true}) async {
    return database.transaction((txn) async {
      await _requireManager(txn, staffId);
      if (name.trim().isEmpty || code.trim().isEmpty || deliveryFeePaisa < 0 || minOrderPaisa < 0) {
        throw ArgumentError('Enter a name, code and non-negative integer paisa amounts.');
      }
      final now = DateTime.now().toIso8601String();
      final values = <String, Object?>{'name': name.trim(), 'code': code.trim().toUpperCase(),
        'coverage_description': coverageDescription.trim(), 'delivery_fee_paisa': deliveryFeePaisa,
        'min_order_paisa': minOrderPaisa, 'is_active': isActive ? 1 : 0, 'updated_at': now};
      final int savedId;
      if (id == null) {
        savedId = await txn.insert('delivery_areas', {...values, 'created_at': now});
      } else {
        if (await txn.update('delivery_areas', values, where: 'id = ? AND archived_at IS NULL', whereArgs: [id]) != 1) {
          throw StateError('Delivery area is archived or no longer exists.');
        }
        savedId = id;
      }
      return DeliveryArea.fromMap((await txn.query('delivery_areas', where: 'id = ?', whereArgs: [savedId])).single);
    });
  }

  Future<void> archiveArea({required int staffId, required int id}) async {
    await database.transaction((txn) async {
      await _requireManager(txn, staffId);
      final now = DateTime.now().toIso8601String();
      if (await txn.update('delivery_areas', {'archived_at': now, 'updated_at': now, 'is_active': 0},
          where: 'id = ? AND archived_at IS NULL', whereArgs: [id]) != 1) {
        throw StateError('Delivery area is archived or no longer exists.');
      }
    });
  }
}

/// User-entered delivery details plus the fee shown before tender collection.
/// The quote is checked, never used as an authoritative price.
class DeliveryDetails {
  const DeliveryDetails({required this.areaId, required this.quotedFeePaisa, required this.phone,
    this.customerName = '', required this.fullAddress, this.landmark = '', this.notes = ''});
  final int areaId, quotedFeePaisa;
  final String phone, customerName, fullAddress, landmark, notes;
  String get addressSnapshot => [fullAddress.trim(), landmark.trim(), notes.trim()].where((v) => v.isNotEmpty).join('\n');
}

class CustomerAddress {
  CustomerAddress.fromMap(Map<String, Object?> row)
      : id = row['id'] as int, phone = row['customer_phone'] as String,
        customerName = row['customer_name'] as String? ?? '', areaId = row['delivery_area_id'] as int?,
        fullAddress = row['full_address'] as String, landmark = row['landmark'] as String? ?? '', notes = row['notes'] as String? ?? '';
  final int id;
  final int? areaId;
  final String phone, customerName, fullAddress, landmark, notes;
}

class DeliveryCheckoutException implements Exception {
  const DeliveryCheckoutException(this.message);
  final String message;
  @override
  String toString() => message;
}


