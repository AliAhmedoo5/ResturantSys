import 'package:flutter/material.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/shifts/business_day.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Operational status bar presenting Business Day status, Active Shift status,
/// and fast-access trigger actions (Cash Movements, Interim X-Report, Blind Shift Handover).
class BusinessDayBar extends StatelessWidget {
  const BusinessDayBar({
    super.key,
    required this.currentStaff,
    required this.activeBusinessDay,
    required this.activeShift,
    required this.flaggedShiftsCount,
    required this.onOpenBusinessDayTap,
    required this.onCloseBusinessDayTap,
    required this.onOpenShiftTap,
    required this.onCashMovementTap,
    required this.onInterimXReportTap,
    required this.onCloseShiftTap,
    required this.onDiscrepancyQueueTap,
  });

  final Staff currentStaff;
  final BusinessDay? activeBusinessDay;
  final Shift? activeShift;
  final int flaggedShiftsCount;
  final VoidCallback onOpenBusinessDayTap;
  final VoidCallback onCloseBusinessDayTap;
  final VoidCallback onOpenShiftTap;
  final VoidCallback onCashMovementTap;
  final VoidCallback onInterimXReportTap;
  final VoidCallback onCloseShiftTap;
  final VoidCallback onDiscrepancyQueueTap;

  @override
  Widget build(BuildContext context) {
    final isDayOpen = activeBusinessDay != null && activeBusinessDay!.isOpen;
    final isShiftOpen = activeShift != null && activeShift!.isOpen;
    final isSupervisor = currentStaff.canAccessSupervisorPortal || currentStaff.canAuthorizeOverrides;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WarmCounterSpacing.space16,
        vertical: WarmCounterSpacing.space8,
      ),
      decoration: const BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        border: Border(
          bottom: BorderSide(color: WarmCounterColors.lightBorder, width: 1.0),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Business Day Status Chip
                      _buildStatusChip(
                        icon: Icons.calendar_today_rounded,
                        label: isDayOpen
                            ? 'Day #${activeBusinessDay!.id}'
                            : 'Business Day Closed',
                        isActive: isDayOpen,
                      ),
                      const SizedBox(width: WarmCounterSpacing.space12),

                      // Shift Status Chip
                      _buildStatusChip(
                        icon: Icons.point_of_sale_rounded,
                        label: isShiftOpen
                            ? 'Shift #${activeShift!.id}: ${activeShift!.staffName ?? currentStaff.name}'
                            : 'No Active Shift',
                        isActive: isShiftOpen,
                      ),
                    ],
                  ),
                  const SizedBox(width: WarmCounterSpacing.space16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Actions
                      if (!isDayOpen) ...[
                        if (isSupervisor)
                          ElevatedButton.icon(
                            key: const ValueKey('btn_open_business_day'),
                            icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                            label: const Text('Open Business Day'),
                            onPressed: onOpenBusinessDayTap,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: WarmCounterColors.lightPrimaryAction,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                            ),
                          ),
                      ] else if (!isShiftOpen) ...[
                        ElevatedButton.icon(
                          key: const ValueKey('btn_open_shift'),
                          icon: const Icon(Icons.lock_open_rounded, size: 18),
                          label: const Text('Open Cashier Shift'),
                          onPressed: onOpenShiftTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightPrimaryAction,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                          ),
                        ),
                        if (isSupervisor) ...[
                          const SizedBox(width: WarmCounterSpacing.space8),
                          OutlinedButton.icon(
                            key: const ValueKey('btn_close_business_day'),
                            icon: const Icon(Icons.nightlight_round, size: 18),
                            label: const Text('Close Business Day'),
                            onPressed: onCloseBusinessDayTap,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                            ),
                          ),
                        ],
                      ] else ...[
                        // Shift is Active
                        OutlinedButton.icon(
                          key: const ValueKey('btn_cash_movement'),
                          icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                          label: const Text('Cash Movement'),
                          onPressed: onCashMovementTap,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                          ),
                        ),
                        if (isSupervisor) ...[
                          const SizedBox(width: WarmCounterSpacing.space8),
                          OutlinedButton.icon(
                            key: const ValueKey('btn_interim_xreport'),
                            icon: const Icon(Icons.receipt_long_rounded, size: 18),
                            label: const Text('Interim X-Report'),
                            onPressed: onInterimXReportTap,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                            ),
                          ),
                        ],
                        const SizedBox(width: WarmCounterSpacing.space8),
                        ElevatedButton.icon(
                          key: const ValueKey('btn_close_shift'),
                          icon: const Icon(Icons.inventory_2_outlined, size: 18),
                          label: const Text('Handover / Close Shift'),
                          onPressed: onCloseShiftTap,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightDestructiveAction,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                          ),
                        ),
                      ],

                      if (isSupervisor) ...[
                        const SizedBox(width: WarmCounterSpacing.space12),
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              key: const ValueKey('btn_discrepancy_queue'),
                              icon: const Icon(Icons.notification_important_outlined),
                              tooltip: 'Discrepancy Review Queue',
                              onPressed: onDiscrepancyQueueTap,
                            ),
                            if (flaggedShiftsCount > 0)
                              Positioned(
                                right: 4,
                                top: 4,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: WarmCounterColors.lightDestructiveAction,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                  child: Text(
                                    '$flaggedShiftsCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required bool isActive,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? WarmCounterColors.lightActiveNavHighlight : WarmCounterColors.lightSurfaceMuted,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: isActive ? WarmCounterColors.lightPrimaryAction.withAlpha(76) : WarmCounterColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isActive ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightSecondaryText,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: WarmCounterTypography.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: isActive ? WarmCounterColors.lightPrimaryText : WarmCounterColors.lightSecondaryText,
            ),
          ),
        ],
      ),
    );
  }
}
