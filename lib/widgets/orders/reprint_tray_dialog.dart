import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/auth/staff.dart';
import '../../core/hardware/print_job.dart';
import '../../core/hardware/reprint_tray_controller.dart';
import '../../core/theme/theme.dart';

/// Modal dialog displaying failed and recent thermal print jobs with 1-tap retry
/// and supervisor manual cash drawer override.
class ReprintTrayDialog extends StatefulWidget {
  const ReprintTrayDialog({
    super.key,
    required this.controller,
    this.currentStaff,
  });

  final ReprintTrayController controller;
  final Staff? currentStaff;

  @override
  State<ReprintTrayDialog> createState() => _ReprintTrayDialogState();
}

class _ReprintTrayDialogState extends State<ReprintTrayDialog> {
  final DateFormat _timeFormat = DateFormat('HH:mm:ss');
  bool _isRetrying = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final failedJobs = widget.controller.failedJobs;
        final recentJobs = widget.controller.recentJobs;

        return Dialog(
          backgroundColor: WarmCounterColors.lightCardBackground,
          shape: const RoundedRectangleBorder(
            borderRadius: WarmCounterSpacing.panelBorderRadius,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680, maxHeight: 650),
            child: Padding(
              padding: const EdgeInsets.all(WarmCounterSpacing.space24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                            decoration: BoxDecoration(
                              color: failedJobs.isNotEmpty
                                  ? Colors.red.shade50
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hardware & Reprint Tray',
                                style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
                              ),
                              Text(
                                '${widget.controller.topology.label} • ${widget.controller.paperWidth.label}',
                                style: WarmCounterTypography.caption.copyWith(
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        key: const ValueKey('close_reprint_tray_button'),
                        icon: const Icon(Icons.close_rounded),
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
                        Row(
                          children: [
                            Icon(
                              widget.controller.cashDrawerEnabled
                                  ? Icons.savings_outlined
                                  : Icons.lock_clock_outlined,
                              size: 20,
                              color: WarmCounterColors.lightPrimaryText,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.controller.cashDrawerEnabled
                                  ? 'RJ11 Cash Drawer: Enabled'
                                  : 'RJ11 Cash Drawer: Manual Unplugged',
                              style: WarmCounterTypography.bodyMedium.copyWith(fontSize: 13),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          key: const ValueKey('kick_drawer_button'),
                          icon: const Icon(Icons.sensor_door_outlined, size: 16),
                          label: const Text('Kick Drawer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightActiveNavHighlight,
                            foregroundColor: WarmCounterColors.lightPrimaryAction,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onPressed: () async {
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
                              'Recent Printed Tickets',
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
                                'No tickets printed in this session.',
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
        color: isFailed ? Colors.red.shade50 : WarmCounterColors.lightPageBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: isFailed ? Colors.red.shade200 : WarmCounterColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
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
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.type.label,
                    style: WarmCounterTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '${job.target.label} • ${_timeFormat.format(job.createdAt)}'
                    '${job.attempts > 1 ? ' • Attempt ${job.attempts}' : ''}',
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
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Actions
          if (isFailed)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Dismiss',
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
                    minimumSize: const Size(80, 36),
                  ),
                  onPressed: () async {
                    await widget.controller.retryJob(job.id);
                  },
                ),
              ],
            )
          else
            OutlinedButton.icon(
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text('Reprint'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(80, 34),
              ),
              onPressed: () async {
                // Re-send bytes for recent job
                await widget.controller.hardwareAdapter.sendBytes(job.target, job.bytes);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Reprint sent to printer.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}
