import '../../core/delivery/delivery_controller.dart';
import '../delivery/delivery_areas_workspace.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/department.dart';
import '../../core/auth/job_role.dart';
import 'job_roles_dialog.dart';
import '../../core/auth/staff.dart';
import '../../core/auth/staff_role.dart';
import '../../core/hardware/reprint_tray_controller.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/shifts/shift.dart';
import '../../core/shifts/shift_and_cash_controller.dart';
import '../../core/theme/theme.dart';
import 'department_form_dialog.dart';
import 'staff_form_dialog.dart';
import 'staff_pin_dialog.dart';
import '../shifts/z_report_dialog.dart';
import '../../core/shifts/z_report.dart';
import '../../core/shifts/excel_reporting_engine.dart';
import '../../core/shifts/report_delivery_service.dart';
import '../shifts/report_delivery_dialog.dart';
import '../../core/database/database_backup_service.dart';
import '../../core/database/pos_database_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/analytics/analytics_service.dart';
import 'manager_analytics_workspace.dart';

enum SupervisorPortalTab {
  dashboard('Dashboard', Icons.insights_rounded),
  deliveryAreas('Delivery Areas', Icons.delivery_dining),
  staff('Staff & Departments', Icons.badge_rounded),
  toggles('Feature Toggles', Icons.toggle_on_rounded),
  discrepancies('Discrepancy Review', Icons.assignment_late_rounded),
  reports('Z-Reports & Backups', Icons.assessment_rounded);

  const SupervisorPortalTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// The back-office administrative hub protected by Supervisor/Owner PIN.
/// Features custom Department management, universal Staff PIN configuration,
/// operational settings, discrepancy review, and business-day reports.
class SupervisorPortalWorkspace extends StatefulWidget {
  const SupervisorPortalWorkspace({
    super.key,
    this.authService,
    this.shiftController,
    this.orderController,
    this.reprintTrayController,
    this.currentStaff,
    this.initialDepartments,
    this.initialStaff,
    this.initialCashierVoidEnabled,
    this.initialDiscrepancies,
    this.initialZReport,
    this.onFinalizeBusinessDay,
    this.initialDiscrepancyThreshold,
  });

  final AuthService? authService;
  final ShiftAndCashController? shiftController;
  final OrderAndCheckoutController? orderController;
  final ReprintTrayController? reprintTrayController;
  final Staff? currentStaff;
  final List<Department>? initialDepartments;
  final List<Staff>? initialStaff;
  final bool? initialCashierVoidEnabled;
  final List<Shift>? initialDiscrepancies;
  final ZReport? initialZReport;
  final Future<void> Function()? onFinalizeBusinessDay;
  final double? initialDiscrepancyThreshold;

  @override
  State<SupervisorPortalWorkspace> createState() => _SupervisorPortalWorkspaceState();
}

class _SupervisorPortalWorkspaceState extends State<SupervisorPortalWorkspace> {
  SupervisorPortalTab _activeTab = SupervisorPortalTab.staff;
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00');
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  // Staff & Departments State
  List<Department> _departments = [];
  List<JobRole> _jobRoles = [];
  List<Staff> _staffMembers = [];
  bool _isLoadingStaff = true;

  // Feature Toggles State
  bool _cashierVoidEnabled = true;
  bool _isLoadingToggles = true;
  double _discrepancyThreshold = 100.0;
  final TextEditingController _thresholdController = TextEditingController();
  bool _isSavingThreshold = false;

  // Discrepancy Review State
  List<Shift> _discrepancyShifts = [];
  bool _isLoadingDiscrepancies = true;

  // Z-Reports & Backups State
  ZReport? _activeZReport;
  bool _isLoadingZReport = true;
  String _secondaryBackupPath = '';
  final TextEditingController _usbPathController = TextEditingController();
  final TextEditingController _localPathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialDepartments != null) {
      _departments = List.of(widget.initialDepartments!);
      _isLoadingStaff = false;
    }
    if (widget.initialStaff != null) {
      _staffMembers = List.of(widget.initialStaff!);
      _isLoadingStaff = false;
    }
    if (widget.initialCashierVoidEnabled != null) {
      _cashierVoidEnabled = widget.initialCashierVoidEnabled!;
      _isLoadingToggles = false;
    }
    if (widget.initialDiscrepancies != null) {
      _discrepancyShifts = List.of(widget.initialDiscrepancies!);
      _isLoadingDiscrepancies = false;
    }
    if (widget.initialZReport != null) {
      _activeZReport = widget.initialZReport;
      _isLoadingZReport = false;
    }
    if (widget.initialDiscrepancyThreshold != null) {
      _discrepancyThreshold = widget.initialDiscrepancyThreshold!;
    }
    _thresholdController.text = _discrepancyThreshold.toStringAsFixed(2);

    _loadAllData();
  }

  @override
  void dispose() {
    _usbPathController.dispose();
    _localPathController.dispose();
    _thresholdController.dispose();
    _featureSettingsScroll.dispose();
    super.dispose();
  }

  List<LowStockWarning> _stockAlerts = [];
  bool _isRefreshingStock = false;
  String? _stockRefreshError;
  final ScrollController _featureSettingsScroll = ScrollController();

  Future<void> _loadStockAlerts({bool showFeedback = false}) async {
    if (_isRefreshingStock) return;
    setState(() => _isRefreshingStock = true);
    try {
      final alerts = await widget.orderController?.getManagerStockAlerts() ?? <LowStockWarning>[];
      if (!mounted) return;
      setState(() {
        _stockAlerts = alerts;
        _stockRefreshError = null;
      });
      if (showFeedback) {
        final message = alerts.isEmpty
            ? 'Stock refreshed. No low-stock alerts remain.'
            : 'Stock refreshed. ${alerts.length} ingredient(s) still low. Record a purchase to replenish stock.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted) setState(() {
        _stockRefreshError = 'Could not refresh stock alerts. Try again.';
      });
    } finally {
      if (mounted) setState(() => _isRefreshingStock = false);
    }
  }

  Future<void> _loadAllData() async {
    await _loadStockAlerts();
    if (widget.initialDepartments == null || widget.initialStaff == null) {
      await _loadStaffAndDepartments();
    }
    if (widget.initialCashierVoidEnabled == null) {
      await _loadFeatureToggles();
    }
    if (widget.initialDiscrepancies == null) {
      await _loadDiscrepancies();
    }
    if (widget.initialZReport == null) {
      await _loadReportsAndBackupSettings();
    }
  }

  Future<void> _loadStaffAndDepartments() async {
    if (widget.authService == null) {
      setState(() => _isLoadingStaff = false);
      return;
    }
    if (_departments.isEmpty && _staffMembers.isEmpty) {
      setState(() => _isLoadingStaff = true);
    }
    try {
      final depts = await widget.authService!.getDepartments();
      final staff = await widget.authService!.getAllStaff();
      final jobRoles = await widget.authService!.getJobRoles();
      if (mounted) {
        setState(() {
          _departments = depts;
          _jobRoles = jobRoles;
          _staffMembers = staff;
          _isLoadingStaff = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStaff = false);
    }
  }

  Future<void> _loadFeatureToggles() async {
    if (widget.orderController == null) {
      setState(() => _isLoadingToggles = false);
      return;
    }
    setState(() => _isLoadingToggles = true);
    try {
      final cashierVoid = await widget.orderController!.isCashierVoidEnabled();
      if (widget.shiftController != null) {
        try {
          final threshold = await widget.shiftController!.getDiscrepancyThreshold();
          _discrepancyThreshold = threshold;
          _thresholdController.text = threshold.toStringAsFixed(2);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _cashierVoidEnabled = cashierVoid;
          _isLoadingToggles = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingToggles = false);
    }
  }

  Future<void> _loadDiscrepancies() async {
    if (widget.shiftController == null) {
      setState(() => _isLoadingDiscrepancies = false);
      return;
    }
    setState(() => _isLoadingDiscrepancies = true);
    try {
      final shifts = await widget.shiftController!.getHistoricalDiscrepancyShifts();
      if (mounted) {
        setState(() {
          _discrepancyShifts = shifts;
          _isLoadingDiscrepancies = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDiscrepancies = false);
    }
  }

  Future<void> _loadReportsAndBackupSettings() async {
    if (widget.shiftController == null) {
      setState(() => _isLoadingZReport = false);
      return;
    }
    setState(() => _isLoadingZReport = true);
    try {
      final activeDay = await widget.shiftController!.getActiveBusinessDay();
      if (activeDay != null) {
        final z = await widget.shiftController!.generateZReport(activeDay.id);
        _activeZReport = z;
      } else {
        _activeZReport = null;
      }

      final settingRows = await widget.shiftController!.database.query(
        PosDatabaseConstants.tableSystemSettings,
        where: 'key IN (?, ?)',
        whereArgs: [PosDatabaseConstants.settingLocalBackupPath, PosDatabaseConstants.settingSecondaryBackupPath],
      );
      for (final row in settingRows) {
        if (row['key'] == PosDatabaseConstants.settingLocalBackupPath) {
          _localPathController.text = row['value'] as String? ?? '';
        } else {
          _secondaryBackupPath = row['value'] as String? ?? '';
          _usbPathController.text = _secondaryBackupPath;
        }
      }
      if (mounted) setState(() => _isLoadingZReport = false);
    } catch (_) {
      if (mounted) setState(() => _isLoadingZReport = false);
    }
  }

  Future<void> _saveBackupPath(String key, String value) async {
    await widget.shiftController!.database.insert(
      PosDatabaseConstants.tableSystemSettings,
      {
        'key': key,
        'value': value,
        'updated_at': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _saveLocalBackupPath() async {
    if (widget.shiftController == null) return;
    await _saveBackupPath(
      PosDatabaseConstants.settingLocalBackupPath, _localPathController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Primary local backup directory updated.')),
    );
  }

  Future<void> _saveSecondaryBackupPath() async {
    if (widget.shiftController == null) return;
    final path = _usbPathController.text.trim();
    await _saveBackupPath(PosDatabaseConstants.settingSecondaryBackupPath, path);
    if (!mounted) return;
    setState(() => _secondaryBackupPath = path);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Secondary / USB backup drive path updated.')),
    );
  }

  Future<void> _triggerInstantBackup() async {
    if (widget.shiftController == null) return;
    try {
      final backupService = DatabaseBackupService(database: widget.shiftController!.database);
      final dbPath = widget.shiftController!.database.path;
      final result = await backupService.executeBackup(
        sourceDbPath: dbPath,
        secondaryBackupDir: _secondaryBackupPath.isNotEmpty ? _secondaryBackupPath : null,
      );
      if (mounted) {
        if (result.success) {
          final msg = result.warningMessage != null
              ? 'Local backup created: ${result.localBackupPath}.\nWarning: ${result.warningMessage}'
              : result.secondaryBackupPath == null
                  ? 'Backup archive created: ${result.localBackupPath}'
                  : 'Backup archive created in primary and secondary destinations.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: result.warningMessage != null ? Colors.orange : const Color(0xFF047857),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.warningMessage ?? 'Failed to create backup.'),
              backgroundColor: WarmCounterColors.lightDestructiveAction,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup error: $e'),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Action Handlers
  // ---------------------------------------------------------------------------

  Future<void> _openAddDepartmentDialog() async {
    final created = await showDialog<Department>(
      context: context,
      builder: (ctx) => DepartmentFormDialog(
        onSave: (name) async {
          if (widget.authService != null) {
            return await widget.authService!.createDepartment(name);
          }
          final dept = Department(
            id: _departments.length + 1,
            name: name,
            createdAt: DateTime.now(),
          );
          return dept;
        },
      ),
    );
    if (created != null) {
      if (widget.authService != null) {
        await _loadStaffAndDepartments();
      } else {
        setState(() => _departments.add(created));
      }
    }
  }

  Future<void> _openRegisterStaffDialog() async {
    final registered = await showDialog<bool>(
      context: context,
      builder: (ctx) => StaffFormDialog(
        departments: _departments,
        jobRoles: _jobRoles,
        onSave: ({
          required String name,
          required int departmentId,
          required StaffRole role,
          required String pin,
          required bool loginEnabled,
          required int? jobRoleId,
          bool? isActive,
        }) async {
          if (widget.authService != null) {
            await widget.authService!.registerStaff(
              name: name,
              departmentId: departmentId,
              role: role,
              loginEnabled: loginEnabled,
              jobRoleId: jobRoleId,
              pin: pin,
            );
          } else {
            final dept = _departments.firstWhere(
              (d) => d.id == departmentId,
              orElse: () => Department(id: departmentId, name: 'General', createdAt: DateTime.now()),
            );
            final newStaff = Staff(
              id: _staffMembers.length + 1,
              name: name,
              departmentId: departmentId,
              departmentName: dept.name,
              pinHash: pin,
              jobRoleName: _jobRoles.where((r) => r.id == jobRoleId).firstOrNull?.name,
              role: role,
              loginEnabled: loginEnabled,
              jobRoleId: jobRoleId,
              isActive: isActive ?? true,
            );
            setState(() => _staffMembers.add(newStaff));
          }
        },
      ),
    );
    if (registered == true && widget.authService != null) {
      await _loadStaffAndDepartments();
    }
  }

  Future<void> _openEditStaffDialog(Staff staff) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StaffFormDialog(
        departments: _departments,
        jobRoles: _jobRoles,
        initialStaff: staff,
        onSave: ({
          required String name,
          required int departmentId,
          required StaffRole role,
          required String pin,
          required bool loginEnabled,
          required int? jobRoleId,
          bool? isActive,
        }) async {
          if (widget.authService != null) {
            await widget.authService!.updateStaff(
              staffId: staff.id,
              name: name,
              departmentId: departmentId,
              role: role,
              loginEnabled: loginEnabled,
              jobRoleId: jobRoleId,
              newPin: pin.isNotEmpty ? pin : null,
              isActive: isActive,
            );
          } else {
            final dept = _departments.firstWhere(
              (d) => d.id == departmentId,
              orElse: () => Department(id: departmentId, name: 'General', createdAt: DateTime.now()),
            );
            setState(() {
              final idx = _staffMembers.indexWhere((s) => s.id == staff.id);
              if (idx != -1) {
                _staffMembers[idx] = Staff(
                  id: staff.id,
                  name: name,
                  departmentId: departmentId,
                  departmentName: dept.name,
                  pinHash: pin.isNotEmpty ? pin : staff.pinHash,
                  jobRoleName: _jobRoles.where((r) => r.id == jobRoleId).firstOrNull?.name,
                  role: role,
              loginEnabled: loginEnabled,
              jobRoleId: jobRoleId,
                  isActive: isActive ?? staff.isActive,
                );
              }
            });
          }
        },
      ),
    );
    if (updated == true && widget.authService != null) {
      await _loadStaffAndDepartments();
    }
  }

  Future<void> _openUpdatePinDialog(Staff staff) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StaffPinDialog(
        staff: staff,
        onUpdatePin: (staffId, newPin) async {
          if (widget.authService != null) {
            await widget.authService!.updateStaffPin(
              staffId: staffId,
              newPin: newPin,
            );
          }
        },
      ),
    );
    if (updated == true && widget.authService != null) {
      await _loadStaffAndDepartments();
    }
  }

  Future<void> _toggleStaffActive(Staff staff, bool active) async {
    if (widget.authService != null) {
      await widget.authService!.updateStaffActiveStatus(staffId: staff.id, isActive: active);
      await _loadStaffAndDepartments();
    } else {
      setState(() {
        final index = _staffMembers.indexWhere((s) => s.id == staff.id);
        if (index != -1) {
          _staffMembers[index] = staff.copyWith(isActive: active);
        }
      });
    }
  }

  Future<void> _handleToggleCashierVoid(bool enabled) async {
    setState(() => _cashierVoidEnabled = enabled);
    if (widget.orderController != null) {
      await widget.orderController!.setCashierVoidEnabled(enabled);
    }
  }

  Future<void> _handleSaveDiscrepancyThreshold() async {
    final text = _thresholdController.text.trim();
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid non-negative threshold amount.')),
      );
      return;
    }

    setState(() => _isSavingThreshold = true);
    try {
      if (widget.shiftController != null) {
        final managerId = widget.currentStaff?.id ?? 1;
        await widget.shiftController!.setDiscrepancyThreshold(
          parsed,
          managerStaffId: managerId,
        );
      }
      if (mounted) {
        setState(() {
          _discrepancyThreshold = parsed;
          _isSavingThreshold = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Discrepancy threshold updated to PKR ' + _currencyFormat.format(parsed))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingThreshold = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', ''))),
        );
      }
    }
  }

  Future<void> _openResolveDiscrepancyDialog(Shift shift) async {
    final notesController = TextEditingController();
    String? dialogError;

    final resolved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
              backgroundColor: WarmCounterColors.lightCardBackground,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                            decoration: const BoxDecoration(
                              color: WarmCounterColors.lightDestructiveHighlight,
                              borderRadius: WarmCounterSpacing.controlBorderRadius,
                            ),
                            child: const Icon(
                              Icons.assignment_turned_in_rounded,
                              color: WarmCounterColors.lightDestructiveAction,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: WarmCounterSpacing.space12),
                          Expanded(
                            child: Text(
                              'Resolve Shift #${shift.id} Discrepancy',
                              style: WarmCounterTypography.pageHeading.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: WarmCounterSpacing.space16),
                      Text(
                        'Cashier: ${shift.staffName ?? 'Staff #${shift.staffId}'} • Variance: PKR ${_currencyFormat.format(shift.discrepancy ?? 0.0)}',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: WarmCounterSpacing.space16),
                      if (dialogError != null) ...[
                        Text(
                          dialogError!,
                          style: const TextStyle(color: WarmCounterColors.lightDestructiveAction, fontSize: 13),
                        ),
                        const SizedBox(height: WarmCounterSpacing.space12),
                      ],
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Supervisor Resolution Audit Notes *',
                          hintText: 'Describe root cause or resolution reason...',
                          border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                        ),
                      ),
                      const SizedBox(height: WarmCounterSpacing.space24),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: WarmCounterSpacing.space12,
                        runSpacing: WarmCounterSpacing.space8,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                          key: const ValueKey('submit_resolution_button'),
                          onPressed: () async {
                            final notes = notesController.text.trim();
                            if (notes.isEmpty) {
                              setDialogState(() => dialogError = 'Resolution notes are mandatory.');
                              return;
                            }
                            if (widget.shiftController != null) {
                              try {
                                final supId = widget.currentStaff?.id ?? 1;
                                await widget.shiftController!.resolveDiscrepancy(
                                  shiftId: shift.id,
                                  supervisorStaffId: supId,
                                  resolutionNotes: notes,
                                );
                                if (ctx.mounted) Navigator.of(ctx).pop(true);
                              } catch (e) {
                                setDialogState(() => dialogError = e.toString());
                              }
                            } else {
                              final index = _discrepancyShifts.indexWhere((s) => s.id == shift.id);
                              if (index != -1) {
                                setState(() {
                                  _discrepancyShifts[index] = Shift(
                                    id: shift.id,
                                    businessDayId: shift.businessDayId,
                                    staffId: shift.staffId,
                                    openedAt: shift.openedAt,
                                    closedAt: shift.closedAt,
                                    openingFloat: shift.openingFloat,
                                    countedCash: shift.countedCash,
                                    expectedCash: shift.expectedCash,
                                    discrepancy: shift.discrepancy,
                                    discrepancyStatus: DiscrepancyStatus.resolved,
                                    status: shift.status,
                                    staffName: shift.staffName,
                                    resolvedByStaffId: widget.currentStaff?.id ?? 1,
                                    resolutionNotes: notes,
                                    resolvedAt: DateTime.now(),
                                  );
                                });
                              }
                              if (ctx.mounted) Navigator.of(ctx).pop(true);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightPrimaryAction,
                            foregroundColor: WarmCounterColors.lightTextOnPrimary,
                          ),
                          child: const Text('Resolve Discrepancy'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
          },
        );
      },
    );

    if (resolved == true && widget.shiftController != null) {
      await _loadDiscrepancies();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCashier = _staffMembers.any((s) => s.role == StaffRole.cashier && s.isActive && s.loginEnabled);

    return Container(
      color: WarmCounterColors.lightPageBackground,
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_stockAlerts.isNotEmpty || _stockRefreshError != null) ...[
            MaterialBanner(
              key: const ValueKey('manager_stock_alert'),
              backgroundColor: WarmCounterColors.lightDestructiveHighlight,
              leading: const Icon(Icons.warning_amber_rounded, color: WarmCounterColors.lightDestructiveAction),
              content: Text(_stockRefreshError ?? 'Low stock  -  replenish now: ${_stockAlerts.map((a) => '${a.ingredientName}: ${a.currentStock} ${a.storageUnit}').join('; ')}', maxLines: 3, overflow: TextOverflow.ellipsis),
              actions: [TextButton(
                key: const ValueKey('refresh_manager_stock'),
                onPressed: _isRefreshingStock ? null : () => _loadStockAlerts(showFeedback: true),
                child: Text(_isRefreshingStock ? 'Refreshing...' : 'Refresh stock'),
              )],
            ),
            const SizedBox(height: 8),
          ],
          // Top Navigation Bar
          _buildTopTabBar(context),
          const SizedBox(height: WarmCounterSpacing.space16),

          // Prominent Alert: No active cashier
          if (!hasActiveCashier && _staffMembers.isNotEmpty) ...[
            Container(
              key: const ValueKey('no_active_cashier_warning'),
              padding: const EdgeInsets.symmetric(
                horizontal: WarmCounterSpacing.space16,
                vertical: WarmCounterSpacing.space12,
              ),
              decoration: BoxDecoration(
                color: WarmCounterColors.lightDestructiveHighlight,
                borderRadius: WarmCounterSpacing.panelBorderRadius,
                border: Border.all(color: WarmCounterColors.lightDestructiveAction),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: WarmCounterColors.lightDestructiveAction, size: 28),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No active cashier — create one',
                          style: WarmCounterTypography.pageHeading.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: WarmCounterColors.lightDestructiveAction,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Front counter register billing is locked because all cashier profiles are deactivated or missing. Create or activate a cashier profile to resume register operations.',
                          style: WarmCounterTypography.bodySmall.copyWith(
                            color: WarmCounterColors.lightDestructiveAction,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  ElevatedButton.icon(
                    key: const ValueKey('warning_create_cashier_button'),
                    icon: const Icon(Icons.person_add_rounded, size: 16),
                    label: const Text('Create Cashier'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightDestructiveAction,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    onPressed: () {
                      setState(() => _activeTab = SupervisorPortalTab.staff);
                      _openRegisterStaffDialog();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space16),
          ],

          // Main Workspace Tab Content
          Expanded(
            child: _buildTabContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: SupervisorPortalTab.values.map((tab) {
          final isSelected = _activeTab == tab;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Semantics(
              selected: isSelected,
              child: TextButton(
                key: ValueKey('portal_tab_${tab.name}'),
                onPressed: () => setState(() => _activeTab = tab),
                style: TextButton.styleFrom(
                  backgroundColor: isSelected ? WarmCounterColors.lightActiveNavHighlight : null,
                  foregroundColor: isSelected ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightSecondaryText,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: TextStyle(fontFamily: WarmCounterTypography.fontFamily, fontFamilyFallback: WarmCounterTypography.fontFallbacks, fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                  shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                ),
                child: Text(tab.label),
              ),
            ),
          );
        }).toList()),
      ),
    );
  }
  Widget _buildTabContent(BuildContext context) {
    switch (_activeTab) {
      case SupervisorPortalTab.dashboard:
        final auth = widget.authService;
        if (auth == null) {
          return const Center(child: Text('Analytics unavailable. A Manager session and database are required.'));
        }
        return ManagerAnalyticsWorkspace(
          service: AnalyticsService(database: auth.database, authService: auth),
          session: auth.session,
        );
      case SupervisorPortalTab.deliveryAreas:
        if (widget.orderController == null || widget.currentStaff == null) return const Center(child: Text('Delivery areas unavailable.'));
        return DeliveryAreasWorkspace(controller: DeliveryController(database: widget.orderController!.database), staffId: widget.currentStaff!.id);
      case SupervisorPortalTab.staff:
        return _buildStaffAndDepartmentsView(context);
      case SupervisorPortalTab.toggles:
        return _buildFeatureTogglesView(context);
      case SupervisorPortalTab.discrepancies:
        return _buildDiscrepanciesView(context);
      case SupervisorPortalTab.reports:
        return _buildReportsAndBackupsView(context);

    }
  }

  // ===========================================================================
  // TAB 1: UNIVERSAL STAFF & DEPARTMENT DIRECTORY
  // ===========================================================================

  Widget _buildStaffAndDepartmentsView(BuildContext context) {
    if (_isLoadingStaff) {
      return const Center(child: CircularProgressIndicator());
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Departments Directory
        SizedBox(
          width: 230,
          child: Material(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            child: Container(
              padding: const EdgeInsets.all(WarmCounterSpacing.space16),
              decoration: BoxDecoration(
                borderRadius: WarmCounterSpacing.panelBorderRadius,
                border: Border.all(color: WarmCounterColors.lightBorder),
              ),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(
                      'Departments (${_departments.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WarmCounterTypography.pageHeading.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    )),
                    IconButton(
                      key: const ValueKey('add_department_button'),
                      icon: const Icon(Icons.add_circle_outline_rounded, color: WarmCounterColors.lightPrimaryAction),
                      tooltip: 'Add Custom Department',
                      onPressed: _openAddDepartmentDialog,
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space12),
                Expanded(
                  child: ListView.separated(
                    itemCount: _departments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: WarmCounterColors.lightBorder),
                    itemBuilder: (context, index) {
                      final dept = _departments[index];
                      final staffInDept = _staffMembers.where((s) => s.departmentId == dept.id).length;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: WarmCounterColors.lightPageBackground,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.apartment_rounded, size: 18, color: WarmCounterColors.lightSecondaryText),
                        ),
                        title: Text(
                          dept.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        subtitle: Text(
                          '$staffInDept staff registered',
                          style: const TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(width: WarmCounterSpacing.space16),

      // Right Column: Staff Members Directory
      Expanded(
        child: Material(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          child: Container(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            decoration: BoxDecoration(
              borderRadius: WarmCounterSpacing.panelBorderRadius,
              border: Border.all(color: WarmCounterColors.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Staff Directory (${_staffMembers.length})',
                          style: WarmCounterTypography.pageHeading.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Manage job roles, departments, and Cashier/Manager system access.',
                          style: WarmCounterTypography.secondaryLabel.copyWith(
                            color: WarmCounterColors.lightSecondaryText,
                          ),
                        ),
                      ],
                    )),
                    const SizedBox(width: 12),
                    if (widget.authService != null) TextButton.icon(
                      key: const ValueKey('manage_job_roles'),
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Job Roles'),
                      onPressed: () async {
                        await showDialog<void>(context: context, builder: (_) => JobRolesDialog(authService: widget.authService!));
                        if (mounted) await _loadStaffAndDepartments();
                      },
                    ),
                    ElevatedButton.icon(
                      key: const ValueKey('register_staff_button'),
                      onPressed: _openRegisterStaffDialog,
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Register Staff'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                        foregroundColor: WarmCounterColors.lightTextOnPrimary,
                        shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Staff Table
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(WarmCounterColors.lightPageBackground),
                      columns: const [
                        DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Department', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('System access', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: _staffMembers.map((staff) {
                        return DataRow(
                          cells: [
                            DataCell(Text(staff.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                            DataCell(Text(staff.departmentName ?? 'General')),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: const BoxDecoration(
                                  color: WarmCounterColors.lightActiveNavHighlight,
                                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                                ),
                                child: Text(
                                  staff.jobRoleName ?? (staff.loginEnabled ? staff.role.displayName : 'Unassigned'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: WarmCounterColors.lightPrimaryAction,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(staff.loginEnabled ? staff.role.displayName : 'No login')),
                            DataCell(
                              Row(
                                children: [
                                  Switch(
                                    value: staff.isActive,
                                    onChanged: (val) => _toggleStaffActive(staff, val),
                                    activeThumbColor: WarmCounterColors.lightPrimaryAction,
                                  ),
                                  Text(
                                    staff.isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      color: staff.isActive
                                          ? const Color(0xFF047857)
                                          : WarmCounterColors.lightSecondaryText,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('update_pin_${staff.id}'),
                                    icon: const Icon(Icons.pin_rounded, size: 20),
                                    tooltip: 'Update 4-Digit PIN',
                                    onPressed: staff.loginEnabled ? () => _openUpdatePinDialog(staff) : null,
                                  ),
                                  IconButton(
                                    key: ValueKey('edit_staff_${staff.id}'),
                                    icon: const Icon(Icons.edit_rounded, size: 20),
                                    tooltip: 'Edit Profile',
                                    onPressed: () => _openEditStaffDialog(staff),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  }

  // ===========================================================================
  // TAB 2: OPERATIONAL FEATURE TOGGLES
  // ===========================================================================

  Widget _buildFeatureTogglesView(BuildContext context) {
    if (_isLoadingToggles) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scrollbar(
      controller: _featureSettingsScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        key: const ValueKey('feature_settings_scroll'),
        controller: _featureSettingsScroll,
        child: Center(
      child: Material(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          padding: const EdgeInsets.all(WarmCounterSpacing.space32),
          decoration: BoxDecoration(
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: const BoxDecoration(
                    color: WarmCounterColors.lightActiveNavHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    color: WarmCounterColors.lightPrimaryAction,
                    size: 28,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Operational Feature Toggles',
                        style: WarmCounterTypography.pageHeading.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Enable or disable key POS modules to adapt to your restaurant workflow.',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space32, color: WarmCounterColors.lightBorder),

            // Toggle 2: Cashier Void Requests
            SwitchListTile(
              key: const ValueKey('toggle_cashier_void_switch'),
              value: _cashierVoidEnabled,
              onChanged: _handleToggleCashierVoid,
              activeTrackColor: WarmCounterColors.lightPrimaryAction,
              title: const Text(
                'Cashier Void Requests',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              subtitle: const Text(
                'Allows front counter cashiers to request post-print order voids with mandatory cancellation reasons requiring supervisor PIN authorization.',
              ),
              secondary: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: WarmCounterColors.lightPageBackground,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.cancel_rounded, color: WarmCounterColors.lightDestructiveAction),
              ),
            ),
            const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

            // Discrepancy Threshold Setting
            Container(
              padding: const EdgeInsets.all(WarmCounterSpacing.space16),
              decoration: BoxDecoration(
                color: WarmCounterColors.lightPageBackground,
                borderRadius: WarmCounterSpacing.controlBorderRadius,
                border: Border.all(color: WarmCounterColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: WarmCounterColors.lightCardBackground,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.price_change_rounded, color: WarmCounterColors.lightPrimaryAction),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Shift Cash Discrepancy Threshold (PKR)',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            Text(
                              'Variance exceeding this threshold triggers an immutable Discrepancy Flag upon blind shift close.',
                              style: WarmCounterTypography.caption.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('discrepancy_threshold_input'),
                          controller: _thresholdController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            prefixText: 'PKR ',
                            hintText: '100.00',
                            filled: true,
                            fillColor: WarmCounterColors.lightCardBackground,
                            border: OutlineInputBorder(
                              borderRadius: WarmCounterSpacing.controlBorderRadius,
                            ),
                            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space12),
                      ElevatedButton(
                        key: const ValueKey('save_discrepancy_threshold_button'),
                        onPressed: _isSavingThreshold ? null : _handleSaveDiscrepancyThreshold,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WarmCounterColors.lightPrimaryAction,
                          foregroundColor: WarmCounterColors.lightTextOnPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: const RoundedRectangleBorder(
                            borderRadius: WarmCounterSpacing.controlBorderRadius,
                          ),
                        ),
                        child: Text(_isSavingThreshold ? 'Saving...' : 'Update Threshold'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
        ),
      ),
  );
  }

  // ===========================================================================
  // TAB 3: DISCREPANCY AUDIT REVIEW TABLE
  // ===========================================================================

  Widget _buildDiscrepanciesView(BuildContext context) {
    if (_isLoadingDiscrepancies) {
      return const Center(child: CircularProgressIndicator());
    }

    return Material(
      color: WarmCounterColors.lightCardBackground,
      borderRadius: WarmCounterSpacing.panelBorderRadius,
      child: Container(
        padding: const EdgeInsets.all(WarmCounterSpacing.space16),
        decoration: BoxDecoration(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: WarmCounterColors.lightBorder),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Discrepancy Audit Review (${_discrepancyShifts.length})',
                    style: WarmCounterTypography.pageHeading.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Historical shift log of counted cash discrepancies with resolution audit notes. Active Threshold: PKR ' + _currencyFormat.format(_discrepancyThreshold),
                    style: WarmCounterTypography.secondaryLabel.copyWith(
                      color: WarmCounterColors.lightSecondaryText,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh Discrepancies',
                onPressed: _loadDiscrepancies,
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          Expanded(
            child: _discrepancyShifts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 48,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(height: WarmCounterSpacing.space12),
                        Text(
                          'No historical cash discrepancies flagged.',
                          style: WarmCounterTypography.bodyMedium.copyWith(
                            color: const Color(0xFF047857),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                      headingRowColor: WidgetStateProperty.all(WarmCounterColors.lightPageBackground),
                      columns: const [
                        DataColumn(label: Text('Shift / Cashier', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Opened & Closed', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Variance Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Resolution Notes', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: _discrepancyShifts.map((shift) {
                        final isFlagged = shift.discrepancyStatus == DiscrepancyStatus.flagged;
                        final discrepancy = shift.discrepancy ?? 0.0;
                        final isNegative = discrepancy < 0;

                        return DataRow(
                          cells: [
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Shift #${shift.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(
                                    shift.staffName ?? 'Staff #${shift.staffId}',
                                    style: const TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_dateFormat.format(shift.openedAt), style: const TextStyle(fontSize: 12)),
                                  if (shift.closedAt != null)
                                    Text(_dateFormat.format(shift.closedAt!), style: const TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 11)),
                                ],
                              ),
                            ),
                            DataCell(
                              Text(
                                '${isNegative ? '-' : '+'}PKR ${_currencyFormat.format(discrepancy.abs())}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: isNegative
                                      ? WarmCounterColors.lightDestructiveAction
                                      : const Color(0xFF047857),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isFlagged
                                      ? WarmCounterColors.lightDestructiveHighlight
                                      : const Color(0xFFECFDF5),
                                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                                ),
                                child: Text(
                                  isFlagged ? 'FLAGGED' : 'RESOLVED',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isFlagged
                                        ? WarmCounterColors.lightDestructiveAction
                                        : const Color(0xFF047857),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                shift.resolutionNotes ?? '—',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontStyle: shift.resolutionNotes == null ? FontStyle.italic : FontStyle.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataCell(
                              isFlagged
                                  ? ElevatedButton(
                                      key: ValueKey('resolve_discrepancy_${shift.id}'),
                                      onPressed: () => _openResolveDiscrepancyDialog(shift),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                                        foregroundColor: WarmCounterColors.lightTextOnPrimary,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      child: const Text('Resolve', style: TextStyle(fontSize: 12)),
                                    )
                                  : const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 20),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
        ),
      ],
    ),
  ),
);
  }

  // ===========================================================================
  // TAB 4: END-OF-DAY Z-REPORTS & DUAL-TARGET BACKUPS
  // ===========================================================================

  Widget _buildReportsAndBackupsView(BuildContext context) {
    if (_isLoadingZReport) {
      return const Center(child: CircularProgressIndicator());
    }

    final localDir = DatabaseBackupService.resolveDefaultLocalBackupDir();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Z-Report & 1-Click Excel Export
        Expanded(
          flex: 3,
          child: Material(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            child: Container(
              padding: const EdgeInsets.all(WarmCounterSpacing.space16),
              decoration: BoxDecoration(
                borderRadius: WarmCounterSpacing.panelBorderRadius,
                border: Border.all(color: WarmCounterColors.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.shiftController != null && widget.currentStaff != null)
                    Align(alignment:Alignment.centerRight,child:TextButton.icon(
                      icon:const Icon(Icons.outgoing_mail),label:const Text('Report delivery & archive'),
                      onPressed:()=>showDialog<void>(context:context,builder:(_)=>ReportDeliveryDialog(
                        service:ReportDeliveryService(database:widget.shiftController!.database),managerStaffId:widget.currentStaff!.id)),
                    )),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End-of-Day Z-Reports & Daily Close',
                              style: WarmCounterTypography.pageHeading.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Review daily revenue, tender breakdowns, net variance, and generate 1-click multi-sheet Excel workbooks.',
                              style: WarmCounterTypography.secondaryLabel.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space16),
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, color: WarmCounterColors.lightPrimaryAction),
                        tooltip: 'Refresh Report Data',
                        onPressed: _loadReportsAndBackupSettings,
                      ),
                    ],
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  if (_activeZReport != null) ...[
                    // Z-Report Summary Box
                    Container(
                      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                      decoration: BoxDecoration(
                        color: WarmCounterColors.lightPageBackground,
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                        border: Border.all(color: WarmCounterColors.lightBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Active Business Day #${_activeZReport!.businessDayId}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: const BoxDecoration(
                                  color: WarmCounterColors.lightActiveNavHighlight,
                                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                                ),
                                child: Text(
                                  '${_activeZReport!.totalShiftsCount} Shifts Finalized',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: WarmCounterColors.lightPrimaryAction,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Net Sales Revenue', style: TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'PKR ${_currencyFormat.format(_activeZReport!.netSales)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Cash Tenders', style: TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'PKR ${_currencyFormat.format(_activeZReport!.cashSales)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Net Drawer Discrepancy', style: TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _activeZReport!.hasUncountedShifts?'Missing blind count':'PKR ${_currencyFormat.format(_activeZReport!.netCashVariance)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                        color: _activeZReport!.netCashVariance.abs() > 0.01
                                            ? WarmCounterColors.lightDestructiveAction
                                            : WarmCounterColors.lightPrimaryAction,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: WarmCounterSpacing.space16),

                    Wrap(
                      spacing: WarmCounterSpacing.space12,
                      runSpacing: WarmCounterSpacing.space8,
                      children: [
                        ElevatedButton.icon(
                          key: const ValueKey('portal_view_z_report_btn'),
                          icon: const Icon(Icons.receipt_long_rounded, size: 18),
                          label: const Text('View Full Z-Report & Summary'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightPrimaryAction,
                            foregroundColor: WarmCounterColors.lightTextOnPrimary,
                            minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                          ),
                          onPressed: () async {
                            final finalized = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => ZReportDialog(
                                report: _activeZReport!,
                                onExportExcel: () async {
                                  if (widget.shiftController != null) {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final engine = ExcelReportingEngine(database: widget.shiftController!.database);
                                    final file = await engine.exportDailyReportToFile(
                                      businessDayId: _activeZReport!.businessDayId,
                                      zReport: _activeZReport!,
                                    );
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('Saved: ${file.path}')),
                                      );
                                    }
                                  }
                                },
                                onFinalizeBusinessDay: () async {
                                  if (widget.onFinalizeBusinessDay != null) {
                                    await widget.onFinalizeBusinessDay!();
                                  } else if (widget.shiftController != null) {
                                    final messenger = ScaffoldMessenger.of(context);
                                    final staffId = widget.currentStaff?.id ?? 1;
                                    final dayId = _activeZReport?.businessDayId;
                                    await widget.shiftController!.finalizeBusinessDayWithZReport(
                                      closedByStaffId: staffId,
                                    );
                                    if (mounted) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Business Day #${dayId ?? ""} closed. PDF/Excel export and delivery status are available in Report delivery & archive. Next day tokens start at #01.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            );
                            if (finalized == true && mounted) {
                              if (widget.shiftController != null) {
                                await _loadReportsAndBackupSettings();
                              } else {
                                setState(() => _activeZReport = null);
                              }
                            }
                          },
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('portal_export_excel_btn'),
                          icon: const Icon(Icons.table_chart_rounded, size: 18),
                          label: const Text('1-Click 6-Sheet Daily Excel (.xlsx)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: WarmCounterColors.lightPrimaryAction,
                            side: const BorderSide(color: WarmCounterColors.lightBorder),
                            minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                          ),
                          onPressed: () async {
                            if (widget.shiftController != null) {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                final engine = ExcelReportingEngine(database: widget.shiftController!.database);
                                final file = await engine.exportDailyReportToFile(
                                  businessDayId: _activeZReport!.businessDayId,
                                  zReport: _activeZReport!,
                                );
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('6-Sheet Daily Excel Report created at: ${file.path}')),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(content: Text('Excel export error: $e'), backgroundColor: WarmCounterColors.lightDestructiveAction),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No active Business Day is currently open.',
                          style: TextStyle(color: WarmCounterColors.lightSecondaryText),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: WarmCounterSpacing.space16),

        // Right Column: Automated & Secondary Backups
        Expanded(
          flex: 2,
          child: Material(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            child: Container(
              padding: const EdgeInsets.all(WarmCounterSpacing.space16),
              decoration: BoxDecoration(
                borderRadius: WarmCounterSpacing.panelBorderRadius,
                border: Border.all(color: WarmCounterColors.lightBorder),
              ),
              child: SingleChildScrollView(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Automated & Secondary Backups',
                    style: WarmCounterTypography.pageHeading.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Timestamped ZIP archives protect the database and catalog photos after every Z-Report closure.',
                    style: WarmCounterTypography.secondaryLabel.copyWith(
                      color: WarmCounterColors.lightSecondaryText,
                    ),
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  const Text('Primary Local Backup Directory:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('local_backup_path_input'),
                          controller: _localPathController,
                          decoration: InputDecoration(
                            hintText: localDir,
                            border: const OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        key: const ValueKey('save_local_backup_path_btn'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                        ),
                        onPressed: _saveLocalBackupPath,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Leave blank to use the default directory.', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  // Secondary / External USB Drive Path
                  const Text('Secondary / USB Drive Target Path:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('usb_path_input'),
                          controller: _usbPathController,
                          decoration: const InputDecoration(
                            hintText: r'e.g. E:\Backups or D:\POS_Backup',
                            border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        key: const ValueKey('save_usb_path_btn'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                        ),
                        onPressed: _saveSecondaryBackupPath,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                  const SizedBox(height: WarmCounterSpacing.space24),

                  // Instant Backup Button
                  OutlinedButton.icon(
                    key: const ValueKey('trigger_backup_btn'),
                    icon: const Icon(Icons.backup_rounded, size: 18),
                    label: const Text('Trigger Instant Database Backup Now'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WarmCounterColors.lightPrimaryAction,
                      side: const BorderSide(color: WarmCounterColors.lightBorder),
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                    ),
                    onPressed: _triggerInstantBackup,
                  ),
                ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
