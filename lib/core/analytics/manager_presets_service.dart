import 'dart:convert';
import 'package:sqflite_common/sqlite_api.dart';
import '../auth/auth_service.dart';
import '../auth/staff_role.dart';
import '../orders/dining_type.dart';
import '../orders/payment_method.dart';
import 'analytics_models.dart';

enum PresetPeriodKind { dynamic, fixed }

class ManagerReportPreset {
  const ManagerReportPreset({
    this.id,
    required this.name,
    required this.ownerStaffId,
    required this.isShared,
    required this.family,
    required this.periodKind,
    this.dynamicPeriod,
    this.startDate,
    this.endDateExclusive,
    required this.timeBasis,
    required this.grouping,
    this.filters = const {},
    required this.createdAt,
    required this.updatedAt,
    this.ownerStaffName,
  });

  final int? id;
  final String name;
  final int ownerStaffId;
  final bool isShared;
  final AnalyticsFamily family;
  final PresetPeriodKind periodKind;
  final String? dynamicPeriod;
  final DateTime? startDate;
  final DateTime? endDateExclusive;
  final AnalyticsTimeBasis timeBasis;
  final AnalyticsGrouping grouping;
  final Map<String, dynamic> filters;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? ownerStaffName;

  ManagerReportPreset copyWith({
    int? id,
    String? name,
    int? ownerStaffId,
    bool? isShared,
    AnalyticsFamily? family,
    PresetPeriodKind? periodKind,
    String? dynamicPeriod,
    DateTime? startDate,
    DateTime? endDateExclusive,
    AnalyticsTimeBasis? timeBasis,
    AnalyticsGrouping? grouping,
    Map<String, dynamic>? filters,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ownerStaffName,
  }) =>
      ManagerReportPreset(
        id: id ?? this.id,
        name: name ?? this.name,
        ownerStaffId: ownerStaffId ?? this.ownerStaffId,
        isShared: isShared ?? this.isShared,
        family: family ?? this.family,
        periodKind: periodKind ?? this.periodKind,
        dynamicPeriod: dynamicPeriod ?? this.dynamicPeriod,
        startDate: startDate ?? this.startDate,
        endDateExclusive: endDateExclusive ?? this.endDateExclusive,
        timeBasis: timeBasis ?? this.timeBasis,
        grouping: grouping ?? this.grouping,
        filters: filters ?? this.filters,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        ownerStaffName: ownerStaffName ?? this.ownerStaffName,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'owner_staff_id': ownerStaffId,
        'is_shared': isShared ? 1 : 0,
        'family': family.name,
        'period_kind': periodKind == PresetPeriodKind.dynamic ? 'DYNAMIC' : 'FIXED',
        'dynamic_period': dynamicPeriod,
        'start_date': startDate?.toIso8601String(),
        'end_date_exclusive': endDateExclusive?.toIso8601String(),
        'time_basis': timeBasis.name,
        'grouping': grouping.name,
        'filters_json': jsonEncode(filters),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ManagerReportPreset.fromMap(Map<String, dynamic> map, {String? ownerStaffName}) {
    Map<String, dynamic> parsedFilters = const {};
    final rawFilters = map['filters_json'];
    if (rawFilters is String && rawFilters.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawFilters);
        if (decoded is Map<String, dynamic>) {
          parsedFilters = decoded;
        }
      } catch (_) {}
    }

    final familyStr = map['family'] as String? ?? 'overview';
    final family = AnalyticsFamily.values.firstWhere(
      (f) => f.name == familyStr,
      orElse: () => AnalyticsFamily.overview,
    );

    final periodKindStr = map['period_kind'] as String? ?? 'DYNAMIC';
    final periodKind = periodKindStr.toUpperCase() == 'FIXED'
        ? PresetPeriodKind.fixed
        : PresetPeriodKind.dynamic;

    final timeBasisStr = map['time_basis'] as String? ?? 'businessDay';
    final timeBasis = AnalyticsTimeBasis.values.firstWhere(
      (b) => b.name == timeBasisStr,
      orElse: () => AnalyticsTimeBasis.businessDay,
    );

    final groupingStr = map['grouping'] as String? ?? 'day';
    final grouping = AnalyticsGrouping.values.firstWhere(
      (g) => g.name == groupingStr,
      orElse: () => AnalyticsGrouping.day,
    );

    return ManagerReportPreset(
      id: map['id'] as int?,
      name: map['name'] as String,
      ownerStaffId: map['owner_staff_id'] as int,
      isShared: (map['is_shared'] as int? ?? 0) == 1,
      family: family,
      periodKind: periodKind,
      dynamicPeriod: map['dynamic_period'] as String?,
      startDate: map['start_date'] != null ? DateTime.tryParse(map['start_date'] as String) : null,
      endDateExclusive: map['end_date_exclusive'] != null
          ? DateTime.tryParse(map['end_date_exclusive'] as String)
          : null,
      timeBasis: timeBasis,
      grouping: grouping,
      filters: parsedFilters,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      ownerStaffName: ownerStaffName ?? map['owner_staff_name'] as String?,
    );
  }
}

class ManagerPresetsService {
  ManagerPresetsService({
    required this.database,
    required this.authService,
  });

  final DatabaseExecutor database;
  final AuthService authService;

  void _assertManager() {
    final staff = authService.session.currentStaff;
    if (staff == null ||
        staff.role != StaffRole.manager ||
        !staff.isActive ||
        !staff.loginEnabled) {
      throw StateError('Manager session required.');
    }
  }

  Future<ManagerReportPreset> createPreset({
    required String name,
    required int ownerStaffId,
    required bool isShared,
    required AnalyticsFamily family,
    required PresetPeriodKind periodKind,
    String? dynamicPeriod,
    DateTime? startDate,
    DateTime? endDateExclusive,
    required AnalyticsTimeBasis timeBasis,
    required AnalyticsGrouping grouping,
    Map<String, dynamic> filters = const {},
  }) async {
    _assertManager();
    final now = DateTime.now().toUtc();
    final preset = ManagerReportPreset(
      name: name.trim(),
      ownerStaffId: ownerStaffId,
      isShared: isShared,
      family: family,
      periodKind: periodKind,
      dynamicPeriod: dynamicPeriod,
      startDate: startDate,
      endDateExclusive: endDateExclusive,
      timeBasis: timeBasis,
      grouping: grouping,
      filters: filters,
      createdAt: now,
      updatedAt: now,
    );

    final id = await database.insert('manager_report_presets', preset.toMap());
    return preset.copyWith(id: id);
  }

  Future<List<ManagerReportPreset>> listPresets({required int staffId}) async {
    _assertManager();
    final rows = await database.rawQuery('''
      SELECT p.*, s.name as owner_staff_name
      FROM manager_report_presets p
      LEFT JOIN staff s ON s.id = p.owner_staff_id
      WHERE p.owner_staff_id = ? OR p.is_shared = 1
      ORDER BY p.is_shared ASC, p.name COLLATE NOCASE ASC
    ''', [staffId]);

    return rows.map((r) => ManagerReportPreset.fromMap(r)).toList();
  }

  Future<ManagerReportPreset?> getPreset(int presetId) async {
    _assertManager();
    final rows = await database.rawQuery('''
      SELECT p.*, s.name as owner_staff_name
      FROM manager_report_presets p
      LEFT JOIN staff s ON s.id = p.owner_staff_id
      WHERE p.id = ?
    ''', [presetId]);

    if (rows.isEmpty) return null;
    return ManagerReportPreset.fromMap(rows.first);
  }

  Future<ManagerReportPreset> updatePreset(
    ManagerReportPreset preset, {
    required int staffId,
  }) async {
    _assertManager();
    final existing = await getPreset(preset.id!);
    if (existing == null) {
      throw StateError('Preset #${preset.id} not found.');
    }
    if (existing.ownerStaffId != staffId) {
      throw StateError('Only the owning Manager can edit this preset.');
    }

    final now = DateTime.now().toUtc();
    final updated = preset.copyWith(updatedAt: now);
    await database.update(
      'manager_report_presets',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [preset.id],
    );
    return updated;
  }

  Future<void> deletePreset({
    required int presetId,
    required int staffId,
  }) async {
    _assertManager();
    final existing = await getPreset(presetId);
    if (existing == null) {
      throw StateError('Preset #$presetId not found.');
    }
    if (existing.ownerStaffId != staffId) {
      throw StateError('Only the owning Manager can delete this preset.');
    }

    await database.delete(
      'manager_report_presets',
      where: 'id = ?',
      whereArgs: [presetId],
    );
  }

  AnalyticsQuery resolvePresetQuery(
    ManagerReportPreset preset, {
    DateTime Function()? clock,
    List<AnalyticsFilterOption>? availableFilters,
  }) {
    final now = clock?.call() ?? DateTime.now().toUtc().add(const Duration(hours: 5));
    final today = DateTime(now.year, now.month, now.day);

    DateTime start;
    DateTime end;
    bool live;

    if (preset.periodKind == PresetPeriodKind.dynamic) {
      final period = preset.dynamicPeriod ?? 'live';
      switch (period) {
        case 'month_to_date':
          start = DateTime(now.year, now.month, 1);
          end = today.add(const Duration(days: 1));
          live = true;
          break;
        case 'today':
          start = today;
          end = today.add(const Duration(days: 1));
          live = false;
          break;
        case 'yesterday':
          start = today.subtract(const Duration(days: 1));
          end = today;
          live = false;
          break;
        case 'week':
          start = today.subtract(const Duration(days: 6));
          end = today.add(const Duration(days: 1));
          live = false;
          break;
        case 'month':
          start = today.subtract(const Duration(days: 29));
          end = today.add(const Duration(days: 1));
          live = false;
          break;
        case 'live':
        default:
          start = today;
          end = today.add(const Duration(days: 1));
          live = true;
          break;
      }
    } else {
      start = preset.startDate ?? DateTime(today.year, today.month, 1);
      end = preset.endDateExclusive ?? today.add(const Duration(days: 1));
      if (!start.isBefore(end)) {
        end = start.add(const Duration(days: 1));
      }
      live = false;
    }

    // Sanitize filters
    final rawFilters = preset.filters;
    int? cashierId;
    if (rawFilters['cashierId'] is int && (rawFilters['cashierId'] as int) > 0) {
      cashierId = rawFilters['cashierId'] as int;
    }

    int? shiftId;
    if (rawFilters['shiftId'] is int && (rawFilters['shiftId'] as int) > 0) {
      shiftId = rawFilters['shiftId'] as int;
    }

    String? diningType;
    final dt = rawFilters['diningType']?.toString();
    if (dt != null && DiningType.values.any((d) => d.code == dt)) {
      diningType = dt;
    }

    String? paymentMethod;
    final pm = rawFilters['paymentMethod']?.toString();
    if (pm != null && PaymentMethod.values.any((p) => p.code == pm)) {
      paymentMethod = pm;
    }

    String? fundingStream;
    final fs = rawFilters['fundingStream']?.toString();
    if (fs != null && ['DRAWER', 'BANK', 'OWNER', 'RIDER_HELD', 'EXTERNAL_UNKNOWN'].contains(fs)) {
      fundingStream = fs;
    }

    int holdStaleMinutes = 30;
    if (rawFilters['holdStaleMinutes'] is int && (rawFilters['holdStaleMinutes'] as int) > 0) {
      holdStaleMinutes = rawFilters['holdStaleMinutes'] as int;
    }

    final domainFilters = <AnalyticsDimension, String>{};
    final rawDomain = rawFilters['domainFilters'];
    if (rawDomain is Map) {
      for (final entry in rawDomain.entries) {
        final keyStr = entry.key.toString();
        final valStr = entry.value.toString();
        final dim = AnalyticsDimension.values.where((d) => d.name == keyStr).firstOrNull;
        if (dim != null) {
          if (availableFilters != null) {
            final exists = availableFilters.any((opt) => opt.dimension == dim && opt.id == valStr);
            if (!exists) continue;
          }
          if (dim == AnalyticsDimension.customerSegment) {
            if (['known', 'guest'].contains(valStr)) {
              domainFilters[dim] = valStr;
            }
          } else if (dim == AnalyticsDimension.acquisition) {
            if (['mandi', 'supplier'].contains(valStr)) {
              domainFilters[dim] = valStr;
            }
          } else if ((int.tryParse(valStr) ?? 0) > 0) {
            domainFilters[dim] = valStr;
          }
        }
      }
    }

    return AnalyticsQuery(
      startDate: start,
      endDateExclusive: end,
      live: live,
      timeBasis: preset.timeBasis,
      grouping: preset.grouping,
      holdStaleMinutes: holdStaleMinutes,
      cashierId: cashierId,
      shiftId: shiftId,
      diningType: diningType,
      paymentMethod: paymentMethod,
      fundingStream: fundingStream,
      domainFilters: domainFilters,
    );
  }
}
