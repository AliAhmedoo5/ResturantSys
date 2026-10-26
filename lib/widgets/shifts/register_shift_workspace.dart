import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/shifts/business_day.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'blind_shift_close_dialog.dart';
import 'business_day_bar.dart';
import 'cash_movement_dialog.dart';
import 'discrepancy_review_dialog.dart';
import 'open_business_day_dialog.dart';
import 'open_shift_dialog.dart';
import 'x_report_dialog.dart';
import 'z_report_dialog.dart';
import '../../core/shifts/excel_reporting_engine.dart';
import '../../core/auth/auth_service.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/catalog/catalog_and_recipe_controller.dart';
import '../orders/counter_billing_workspace.dart';

/// Counter register operational workspace coordinating Business Day and Shift lifecycles.
class RegisterShiftWorkspace extends StatefulWidget {
  const RegisterShiftWorkspace({
    super.key,
    required this.controller,
    required this.currentStaff,
    this.orderController,
    this.catalogController,
    this.authService,
    this.onLock,
  });

  final ShiftAndCashController controller;
  final Staff currentStaff;
  final OrderAndCheckoutController? orderController;
  final CatalogAndRecipeController? catalogController;
  final AuthService? authService;
  final VoidCallback? onLock;

  @override
  State<RegisterShiftWorkspace> createState() => _RegisterShiftWorkspaceState();
}

class _RegisterShiftWorkspaceState extends State<RegisterShiftWorkspace> {
  BusinessDay? _activeBusinessDay;
  Shift? _activeShift;
  List<CashMovement> _activeMovements = [];
  int _flaggedCount = 0;
  bool _isLoading = true;
  bool _showShiftDetails = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    setState(() => _isLoading = true);
    final day = await widget.controller.getActiveBusinessDay();
    final shift = await widget.controller.getActiveShift();
    List<CashMovement> movements = [];
    if (shift != null) {
      movements = await widget.controller.getCashMovements(shift.id);
    }
    final flagged = await widget.controller.getFlaggedShifts();

    if (mounted) {
      setState(() {
        _activeBusinessDay = day;
        _activeShift = shift;
        _activeMovements = movements;
        _flaggedCount = flagged.length;
        _isLoading = false;
      });
    }
  }

  void _showOpenBusinessDayDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => OpenBusinessDayDialog(
        supervisorName: widget.currentStaff.name,
        onOpenBusinessDay: () async {
          await widget.controller.openBusinessDay(openedByStaffId: widget.currentStaff.id);
          await _refreshState();
          if (mounted && !widget.currentStaff.canAccessRegister) {
            _showSwitchToCashierPrompt();
          }
        },
      ),
    );
  }

  void _showSwitchToCashierPrompt() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: WarmCounterColors.lightPrimaryAction),
            SizedBox(width: 8),
            Text('Business Day Opened'),
          ],
        ),
        content: const Text(
          'Business Day is now active. Manager accounts cannot operate cashier shifts or process register orders. Please switch to a Cashier account to open the shift and begin billing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Stay on Manager Workspace'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Switch to Cashier Login'),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onLock?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: WarmCounterColors.lightPrimaryAction,
              foregroundColor: WarmCounterColors.lightTextOnPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleCloseBusinessDay() async {
    final activeDay = _activeBusinessDay;
    if (activeDay == null) return;

    final activeShift = _activeShift;
    if (activeShift != null && activeShift.isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot close Business Day while Shift #${activeShift.id} is still open. Complete shift handover first.',
          ),
          backgroundColor: WarmCounterColors.lightDestructiveAction,
        ),
      );
      return;
    }

    try {
      final zReport = await widget.controller.generateZReport(activeDay.id);
      if (!mounted) return;

      final finalized = await showDialog<bool>(
        context: context,
        builder: (ctx) => ZReportDialog(
          report: zReport,
          onExportExcel: () async {
            final engine = ExcelReportingEngine(database: widget.controller.database);
            final file = await engine.exportDailyReportToFile(
              businessDayId: activeDay.id,
              zReport: zReport,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('6-Sheet Daily Excel Report saved: ${file.path}'),
                ),
              );
            }
          },
          onFinalizeBusinessDay: () async {
            await widget.controller.finalizeBusinessDayWithZReport(
              closedByStaffId: widget.currentStaff.id,
            );

            await _refreshState();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Business Day #${activeDay.id} finalized with Z-Report. Backup archived and tokens reset to #01.',
                  ),
                ),
              );
            }
          },
        ),
      );

      if (finalized == true) {
        await _refreshState();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('StateError: ', '')),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
      }
    }
  }

  void _showOpenShiftDialog() {
    if (!widget.currentStaff.canAccessRegister) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Authorization error: Manager credentials cannot open or operate cashier shifts.'),
          backgroundColor: WarmCounterColors.lightDestructiveAction,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => OpenShiftDialog(
        onOpenShift: (float) async {
          await widget.controller.openShift(
            staffId: widget.currentStaff.id,
            openingFloat: float,
          );
          await _refreshState();
        },
      ),
    );
  }

  void _showCashMovementDialog() {
    final shift = _activeShift;
    if (shift == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => CashMovementDialog(
        onRecordMovement: (type, amount, category, notes) async {
          await widget.controller.recordCashMovement(
            shiftId: shift.id,
            staffId: widget.currentStaff.id,
            type: type,
            amount: amount,
            category: category,
            notes: notes,
          );
          await _refreshState();
        },
      ),
    );
  }

  Future<void> _showInterimXReportDialog() async {
    final shift = _activeShift;
    if (shift == null) return;

    final report = await widget.controller.generateXReport(shift.id);
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => XReportDialog(report: report),
    );
  }

  void _showBlindShiftCloseDialog() {
    final shift = _activeShift;
    if (shift == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => BlindShiftCloseDialog(
        shiftId: shift.id,
        cashierName: shift.staffName ?? widget.currentStaff.name,
        onSubmitBlindCount: (countedCash) async {
          final closedShift = await widget.controller.closeShift(
            shiftId: shift.id,
            staffId: widget.currentStaff.id,
            countedCash: countedCash,
          );
          await _refreshState();

          if (mounted) {
            final report = await widget.controller.generateXReport(closedShift.id);
            if (mounted) {
              showDialog<void>(
                context: context,
                builder: (ctx) => XReportDialog(report: report),
              );
            }
          }
        },
      ),
    );
  }

  Future<void> _showDiscrepancyReviewDialog() async {
    final flagged = await widget.controller.getFlaggedShifts();
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => DiscrepancyReviewDialog(
        flaggedShifts: flagged,
        onResolveDiscrepancy: (shiftId, notes) async {
          await widget.controller.resolveDiscrepancy(
            shiftId: shiftId,
            supervisorStaffId: widget.currentStaff.id,
            resolutionNotes: notes,
          );
          await _refreshState();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Text(
          'Loading POS Workspace...',
          style: TextStyle(color: WarmCounterColors.lightSecondaryText),
        ),
      );
    }

    final isDayOpen = _activeBusinessDay != null && _activeBusinessDay!.isOpen;
    final isShiftOpen = _activeShift != null && _activeShift!.isOpen;
    final showBilling = isDayOpen &&
        isShiftOpen &&
        widget.orderController != null &&
        widget.catalogController != null &&
        widget.currentStaff.canAccessRegister &&
        !_showShiftDetails;

    return Column(
      children: [
        BusinessDayBar(
          currentStaff: widget.currentStaff,
          activeBusinessDay: _activeBusinessDay,
          activeShift: _activeShift,
          flaggedShiftsCount: _flaggedCount,
          onOpenBusinessDayTap: _showOpenBusinessDayDialog,
          onCloseBusinessDayTap: _handleCloseBusinessDay,
          onOpenShiftTap: _showOpenShiftDialog,
          onCashMovementTap: _showCashMovementDialog,
          onInterimXReportTap: _showInterimXReportDialog,
          onCloseShiftTap: _showBlindShiftCloseDialog,
          onDiscrepancyQueueTap: _showDiscrepancyReviewDialog,
        ),
        if (isShiftOpen && widget.orderController != null && widget.catalogController != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: WarmCounterColors.lightPageBackground,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: Icon(_showShiftDetails ? Icons.point_of_sale_rounded : Icons.info_outline_rounded, size: 16),
                  label: Text(_showShiftDetails ? 'Switch to Counter Billing Grid' : 'View Shift Details & Drawer Movements'),
                  onPressed: () => setState(() => _showShiftDetails = !_showShiftDetails),
                ),
              ],
            ),
          ),
        Expanded(
          child: showBilling
              ? CounterBillingWorkspace(
                  orderController: widget.orderController!,
                  catalogController: widget.catalogController!,
                  authService: widget.authService,
                  currentStaff: widget.currentStaff,
                  businessDayId: _activeBusinessDay!.id,
                  shiftId: _activeShift!.id,
                  onOrderCompleted: _refreshState,
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space24),
                  child: _buildWorkspaceBody(),
                ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceBody() {
    final isDayOpen = _activeBusinessDay != null && _activeBusinessDay!.isOpen;
    final isShiftOpen = _activeShift != null && _activeShift!.isOpen;

    if (!isDayOpen) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          padding: const EdgeInsets.all(WarmCounterSpacing.space32),
          decoration: BoxDecoration(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.nightlight_round, size: 48, color: WarmCounterColors.lightSecondaryText),
              const SizedBox(height: WarmCounterSpacing.space16),
              Text(
                'Business Day is Closed',
                style: WarmCounterTypography.pageHeading.copyWith(fontSize: 22),
              ),
              const SizedBox(height: WarmCounterSpacing.space8),
              Text(
                'Open a Business Day to initialize sequential cashier shifts and counter billing operations.',
                style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WarmCounterSpacing.space24),
              if (widget.currentStaff.canAccessSupervisorPortal || widget.currentStaff.canAuthorizeOverrides)
                ElevatedButton.icon(
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: const Text('Open Business Day'),
                  onPressed: _showOpenBusinessDayDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: WarmCounterColors.lightTextOnPrimary,
                    minimumSize: const Size(200, WarmCounterSpacing.touchTargetMin),
                  ),
                )
              else
                Text(
                  'Supervisor authorization is required to open the Business Day.',
                  style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightDestructiveAction),
                ),
            ],
          ),
        ),
      );
    }

    if (!isShiftOpen) {
      return Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          padding: const EdgeInsets.all(WarmCounterSpacing.space32),
          decoration: BoxDecoration(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.point_of_sale_rounded, size: 48, color: WarmCounterColors.lightPrimaryAction),
              const SizedBox(height: WarmCounterSpacing.space16),
              Text(
                'No Active Cashier Shift',
                style: WarmCounterTypography.pageHeading.copyWith(fontSize: 22),
              ),
              const SizedBox(height: WarmCounterSpacing.space8),
              Text(
                'Business Day #${_activeBusinessDay!.id} is running. Record your physical opening float to open a shift.',
                style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: WarmCounterSpacing.space24),
              if (widget.currentStaff.canAccessRegister)
                ElevatedButton.icon(
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Open Cashier Shift'),
                  onPressed: _showOpenShiftDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: WarmCounterColors.lightTextOnPrimary,
                    minimumSize: const Size(200, WarmCounterSpacing.touchTargetMin),
                  ),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxWidth: 440),
                  padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightActiveNavHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.badge_outlined, size: 36, color: WarmCounterColors.lightPrimaryAction),
                      const SizedBox(height: 8),
                      Text(
                        'Cashier Credentials Required',
                        style: WarmCounterTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Business Day #${_activeBusinessDay!.id} is open. Manager credentials cannot operate cashier shifts or process register orders. Please switch to a Cashier account.',
                        style: WarmCounterTypography.bodySmall.copyWith(color: WarmCounterColors.lightSecondaryText),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.onLock != null) ...[
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          key: const ValueKey('switch_to_cashier_button'),
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Switch to Cashier Login'),
                          onPressed: widget.onLock,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightPrimaryAction,
                            foregroundColor: WarmCounterColors.lightTextOnPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Shift is active
    final shift = _activeShift!;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
        decoration: BoxDecoration(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: WarmCounterColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    Icons.storefront_rounded,
                    color: WarmCounterColors.lightPrimaryAction,
                    size: 32,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shift #${shift.id} Active',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 22),
                      ),
                      Text(
                        'Cashier: ${shift.staffName ?? widget.currentStaff.name} • Opened ${_timeFormat.format(shift.openedAt)}',
                        style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightSurfaceMuted,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Opening Float', style: WarmCounterTypography.caption),
                      Text(
                        'Rs ${_currencyFormat.format(shift.openingFloat)}',
                        style: WarmCounterTypography.tabularNumbers.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space32, color: WarmCounterColors.lightBorder),

            // Mid-Shift Movements Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Drawer Cash Movements',
                  style: WarmCounterTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Movement'),
                  onPressed: _showCashMovementDialog,
                ),
              ],
            ),
            const SizedBox(height: WarmCounterSpacing.space8),
            if (_activeMovements.isEmpty)
              Container(
                padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                decoration: const BoxDecoration(
                  color: WarmCounterColors.lightPageBackground,
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                ),
                alignment: Alignment.center,
                child: Text(
                  'No mid-shift cash movements recorded yet.',
                  style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _activeMovements.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final m = _activeMovements[index];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: WarmCounterColors.lightPageBackground,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: m.isPayIn ? WarmCounterColors.lightActiveNavHighlight : WarmCounterColors.lightDestructiveHighlight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            m.isPayIn ? '+ PAY-IN' : '- PAY-OUT',
                            style: TextStyle(
                              color: m.isPayIn ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightDestructiveAction,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.category, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text(m.notes, style: WarmCounterTypography.caption),
                            ],
                          ),
                        ),
                        Text(
                          'Rs ${_currencyFormat.format(m.amount)}',
                          style: WarmCounterTypography.tabularNumbers.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

            const SizedBox(height: WarmCounterSpacing.space24),
            Builder(
              builder: (context) {
                final isSupervisor = widget.currentStaff.canAccessSupervisorPortal || widget.currentStaff.canAuthorizeOverrides;
                return Row(
                  children: [
                    if (isSupervisor) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text('Generate Interim X-Report'),
                          onPressed: _showInterimXReportDialog,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                          ),
                        ),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space12),
                    ],
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Blind Shift Handover'),
                        onPressed: _showBlindShiftCloseDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WarmCounterColors.lightDestructiveAction,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
