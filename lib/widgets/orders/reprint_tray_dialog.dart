import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/staff.dart';
import '../../core/hardware/print_job.dart';
import '../../core/hardware/reprint_tray_controller.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/theme/theme.dart';
import 'supervisor_void_dialog.dart';

/// Modal dialog displaying failed and recent thermal print jobs with 1-tap retry,
/// supervisor order voiding, and manual cash drawer override.
class ReprintTrayDialog extends StatefulWidget {
  const ReprintTrayDialog({
    super.key,
    required this.controller,
    this.currentStaff,
    this.orderController,
    this.authService,
  });

  final ReprintTrayController controller;
  final Staff? currentStaff;
  final OrderAndCheckoutController? orderController;
  final AuthService? authService;

  @override
  State<ReprintTrayDialog> createState() => _ReprintTrayDialogState();
}

class _ReprintTrayDialogState extends State<ReprintTrayDialog> {
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');
  bool _isRetrying = false;
  bool _cashierVoidEnabled = true;

  @override
  void initState() {
    super.initState();
    if (widget.orderController != null) {
      widget.orderController!.isCashierVoidEnabled().then((enabled) {
        if (mounted) setState(() => _cashierVoidEnabled = enabled);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (_, __) {
        final failedJobs = widget.controller.failedJobs;
        final recentJobs = widget.controller.recentJobs;

        return Dialog(
          backgroundColor: WarmCounterColors.lightCardBackground,
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.panelBorderRadius,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.all(WarmCounterSpacing.space24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                              decoration: BoxDecoration(
                                color: failedJobs.isNotEmpty
                                    ? WarmCounterColors.lightDestructiveHighlight
                                    : WarmCounterColors.lightActiveNavHighlight,
                                borderRadius: WarmCounterSpacing.controlBorderRadius,
                              ),
                              child: Icon(
                                Icons.print_rounded,
                                size: 26,
                                color: failedJobs.isNotEmpty
                                    ? WarmCounterColors.lightDestructiveAction
                                    : WarmCounterColors.lightPrimaryAction,
                              ),
                            ),
                            const SizedBox(width: WarmCounterSpacing.space12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hardware & Reprint Tray',
                                    style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
                                  ),
                                  Text(
                                    '${widget.controller.topology.label} • ${widget.controller.paperWidth.label}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: WarmCounterTypography.caption.copyWith(
                                      color: WarmCounterColors.lightSecondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('close_reprint_tray_button'),
                        icon: const Icon(Icons.close_rounded),
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  // Cash Drawer Override & Topology Action Row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: WarmCounterColors.lightPageBackground,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                      border: Border.all(color: WarmCounterColors.lightBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                widget.controller.cashDrawerEnabled
                                    ? Icons.savings_outlined
                                    : Icons.lock_clock_outlined,
                                size: 20,
                                color: WarmCounterColors.lightPrimaryText,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.controller.cashDrawerEnabled
                                      ? 'RJ11 Cash Drawer: Enabled'
                                      : 'RJ11 Cash Drawer: Manual Unplugged',
                                  overflow: TextOverflow.ellipsis,
                                  style: WarmCounterTypography.bodyMedium.copyWith(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          key: const ValueKey('kick_drawer_button'),
                          icon: const Icon(Icons.sensor_door_outlined, size: 16),
                          label: const Text('Kick Drawer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightActiveNavHighlight,
                            foregroundColor: WarmCounterColors.lightPrimaryAction,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            minimumSize: const Size(120, 48),
                          ),
                          onPressed: () async {
                            final staff = widget.currentStaff;
                            if (staff != null &&
                                !(staff.canAuthorizeOverrides || staff.canAccessSupervisorPortal)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Supervisor authorization required for manual drawer kick.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }
                            final success = await widget.controller.triggerSupervisorDrawerOverride();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'Cash drawer pulse emitted.'
                                        : 'Drawer override failed.',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  if (widget.orderController != null &&
                      (widget.currentStaff?.canAccessSupervisorPortal == true ||
                          widget.currentStaff?.canAuthorizeOverrides == true)) ...[
                    const SizedBox(height: WarmCounterSpacing.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: WarmCounterColors.lightPageBackground,
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                        border: Border.all(color: WarmCounterColors.lightBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.toggle_on_outlined,
                                size: 20,
                                color: WarmCounterColors.lightPrimaryText,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Cashier Void Requests: ${_cashierVoidEnabled ? "Enabled" : "Disabled"}',
                                style: WarmCounterTypography.bodyMedium.copyWith(fontSize: 13),
                              ),
                            ],
                          ),
                          Switch(
                            key: const ValueKey('toggle_cashier_void_switch'),
                            value: _cashierVoidEnabled,
                            activeThumbColor: WarmCounterColors.lightPrimaryAction,
                            onChanged: (val) async {
                              await widget.orderController!.setCashierVoidEnabled(val);
                              setState(() => _cashierVoidEnabled = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: WarmCounterSpacing.space16),

                  // Main Content: Failed Jobs and Recent Jobs
                  Expanded(
                    child: ListView(
                      children: [
                        // Failed Jobs Alert Section
                        if (failedJobs.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: WarmCounterColors.lightDestructiveAction,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Failed Print Jobs (${failedJobs.length})',
                                    style: WarmCounterTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: WarmCounterColors.lightDestructiveAction,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton.icon(
                                key: const ValueKey('retry_all_failed_button'),
                                icon: _isRetrying
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh_rounded, size: 16),
                                label: const Text('Retry All'),
                                style: TextButton.styleFrom(
                                  foregroundColor: WarmCounterColors.lightPrimaryAction,
                                  minimumSize: const Size(80, 48),
                                ),
                                onPressed: _isRetrying
                                    ? null
                                    : () async {
                                        setState(() => _isRetrying = true);
                                        await widget.controller.retryAllFailed();
                                        if (mounted) setState(() => _isRetrying = false);
                                      },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...failedJobs.map((job) => _buildJobCard(job, isFailed: true)),
                          const Divider(height: 24),
                        ],

                        // Recent Completed Jobs Section
                        Row(
                          children: [
                            const Icon(
                              Icons.history_rounded,
                              size: 18,
                              color: WarmCounterColors.lightSecondaryText,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Recent Receipts & KOTs',
                              style: WarmCounterTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: WarmCounterColors.lightPrimaryText,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (recentJobs.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'No receipts or KOTs printed in this session.',
                                style: WarmCounterTypography.caption.copyWith(
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                              ),
                            ),
                          )
                        else
                          ...recentJobs.map((job) => _buildJobCard(job, isFailed: false)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildJobCard(PrintJob job, {required bool isFailed}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(WarmCounterSpacing.space12),
      decoration: BoxDecoration(
        color: isFailed
            ? WarmCounterColors.lightDestructiveHighlight
            : WarmCounterColors.lightPageBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: isFailed
              ? WarmCounterColors.lightDestructive
              : WarmCounterColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFailed
                        ? WarmCounterColors.lightDestructiveAction
                        : WarmCounterColors.lightPrimaryAction,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    job.tokenDisplay,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFeatures: WarmCounterTypography.tabularFigures,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.type.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${job.target.label} • ${_timeFormat.format(job.createdAt)}'
                        '${job.attempts > 1 ? ' • Attempt ${job.attempts}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                          fontSize: 11,
                        ),
                      ),
                      if (job.errorMessage != null && isFailed)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            job.errorMessage!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: WarmCounterColors.lightDestructive,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Actions
          if (isFailed)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Dismiss',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => widget.controller.dismissFailedJob(job.id),
                ),
                ElevatedButton.icon(
                  key: ValueKey('retry_job_${job.id}'),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: const Size(80, 48),
                  ),
                  onPressed: () async {
                    await widget.controller.retryJob(job.id);
                  },
                ),
              ],
            )
          else
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: const Text('Reprint'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(80, 48),
                  ),
                  onPressed: () async {
                    final success = await widget.controller.reprintJob(job);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            success
                                ? 'Reprint sent to printer.'
                                : 'Reprint failed. Added to failed jobs queue.',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                if (widget.orderController != null &&
                    widget.authService != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: ValueKey('void_job_${job.id}'),
                    icon: const Icon(Icons.cancel_outlined, size: 16, color: WarmCounterColors.lightDestructiveAction),
                    label: const Text('Void', style: TextStyle(color: WarmCounterColors.lightDestructiveAction)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: WarmCounterColors.lightDestructive),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: const Size(70, 48),
                    ),
                    onPressed: () async {
                      final isSupervisor = widget.currentStaff?.canVoidOrders ?? false;
                      if (!isSupervisor && !_cashierVoidEnabled) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cashier void requests are disabled by management.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        return;
                      }

                      try {
                        final order = await widget.orderController!.getOrder(job.orderId);
                        if (order.isVoided) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Order is already voided.')),
                            );
                          }
                          return;
                        }
                        if (!mounted) return;
                        await showDialog<void>(
                          context: context,
                          builder: (ctx) => SupervisorVoidDialog(
                            order: order,
                            cashierId: widget.currentStaff?.id ?? 1,
                            orderController: widget.orderController!,
                            authService: widget.authService!,
                            reprintTrayController: widget.controller,
                            onVoidSuccess: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Order #${order.id} (${order.tokenDisplay}) voided successfully. Kitchen Void Slip emitted.'),
                                ),
                              );
                            },
                          ),
                        );
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to load order: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
