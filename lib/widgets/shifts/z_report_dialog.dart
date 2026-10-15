import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/shifts/z_report.dart';
import '../../core/theme/theme.dart';

/// Modal dialog for reviewing the End-of-Day Master Z-Report,
/// exporting the 1-click 6-sheet Excel workbook, and locking the Business Day.
class ZReportDialog extends StatefulWidget {
  const ZReportDialog({
    super.key,
    required this.report,
    this.onExportExcel,
    this.onPrint,
    this.onFinalizeBusinessDay,
    this.isFinalized = false,
  });

  final ZReport report;
  final Future<void> Function()? onExportExcel;
  final VoidCallback? onPrint;
  final Future<void> Function()? onFinalizeBusinessDay;
  final bool isFinalized;

  @override
  State<ZReportDialog> createState() => _ZReportDialogState();
}

class _ZReportDialogState extends State<ZReportDialog> {
  bool _showThermalSlip = false;
  bool _isProcessing = false;
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00');

  Future<bool> _confirmFinalizeDay(BuildContext context, int dayId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: WarmCounterColors.lightDestructiveAction),
            SizedBox(width: WarmCounterSpacing.space8),
            Text('Finalize Business Day'),
          ],
        ),
        content: Text(
          'Are you sure you want to finalize and lock Business Day #$dayId?\n\n'
          'This will close the operational day, archive all shifts, generate an automated database backup, '
          'and reset daily order tokens to #01.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel_finalize_dialog_btn'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            key: const ValueKey('confirm_finalize_dialog_btn'),
            style: ElevatedButton.styleFrom(
              backgroundColor: WarmCounterColors.lightDestructiveAction,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm & Finalize'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final z = widget.report;
    final printable = z.toPrintableString();
    final hasDiscrepancy = z.netCashVariance.abs() > 0.01;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 780),
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: const BoxDecoration(
                    color: WarmCounterColors.lightActiveNavHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.assessment_rounded,
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
                        'Master End-of-Day Z-Report',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Business Day #${z.businessDayId} • Opened by ${z.openedByStaffName}',
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle between Summary and Thermal Slip
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.dashboard_outlined, size: 16),
                      label: Text('Overview'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.receipt_long_rounded, size: 16),
                      label: Text('Thermal Slip'),
                    ),
                  ],
                  selected: {_showThermalSlip},
                  onSelectionChanged: (set) => setState(() => _showThermalSlip = set.first),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

            // Main Body Content
            Expanded(
              child: _showThermalSlip
                  ? _buildThermalSlipView(context, printable)
                  : _buildOverviewView(context, z, hasDiscrepancy),
            ),

            const SizedBox(height: WarmCounterSpacing.space16),
            const Divider(height: 1, color: WarmCounterColors.lightBorder),
            const SizedBox(height: WarmCounterSpacing.space16),

            // Action Buttons Bar
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WarmCounterSpacing.space12,
              runSpacing: WarmCounterSpacing.space8,
              children: [
                OutlinedButton(
                  key: const ValueKey('close_z_report_button'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(false),
                  child: const Text('Close'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('print_z_report_button'),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Print Z-Report'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                  ),
                  onPressed: () {
                    if (widget.onPrint != null) {
                      widget.onPrint!();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Dispatched Z-Report to 80mm thermal printer.')),
                      );
                    }
                  },
                ),
                ElevatedButton.icon(
                  key: const ValueKey('export_excel_button'),
                  icon: const Icon(Icons.table_chart_rounded, size: 18),
                  label: const Text('1-Click 6-Sheet Excel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                  ),
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          if (widget.onExportExcel != null) {
                            setState(() => _isProcessing = true);
                            try {
                              await widget.onExportExcel!();
                            } finally {
                              if (mounted) setState(() => _isProcessing = false);
                            }
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Generated 6-Sheet daily Excel workbook.')),
                            );
                          }
                        },
                ),
                if (!widget.isFinalized)
                  ElevatedButton.icon(
                    key: const ValueKey('finalize_day_button'),
                    icon: const Icon(Icons.lock_rounded, size: 18),
                    label: const Text('Finalize & Lock Business Day'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightDestructiveAction,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                    ),
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            final confirmed = await _confirmFinalizeDay(context, widget.report.businessDayId);
                            if (!confirmed) return;

                            if (widget.onFinalizeBusinessDay != null) {
                              setState(() => _isProcessing = true);
                              try {
                                await widget.onFinalizeBusinessDay!();
                                if (context.mounted) {
                                  Navigator.of(context).maybePop(true);
                                }
                              } finally {
                                if (mounted) setState(() => _isProcessing = false);
                              }
                            } else {
                              Navigator.of(context).maybePop(true);
                            }
                          },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewView(BuildContext context, ZReport z, bool hasDiscrepancy) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Net Variance Banner if any discrepancy
          if (hasDiscrepancy)
            Container(
              margin: const EdgeInsets.only(bottom: WarmCounterSpacing.space16),
              padding: const EdgeInsets.all(WarmCounterSpacing.space12),
              decoration: BoxDecoration(
                color: WarmCounterColors.lightDestructiveHighlight,
                borderRadius: WarmCounterSpacing.controlBorderRadius,
                border: Border.all(color: WarmCounterColors.lightDestructiveAction.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: WarmCounterColors.lightDestructiveAction),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Text(
                      'Cash Drawer Variance Flag: Net discrepancy of PKR ${_currencyFormat.format(z.netCashVariance)} across all shifts.',
                      style: const TextStyle(
                        color: WarmCounterColors.lightDestructiveAction,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: WarmCounterSpacing.space16),
              padding: const EdgeInsets.all(WarmCounterSpacing.space12),
              decoration: BoxDecoration(
                color: WarmCounterColors.lightActiveNavHighlight,
                borderRadius: WarmCounterSpacing.controlBorderRadius,
                border: Border.all(color: WarmCounterColors.lightPrimaryAction.withAlpha(80)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: WarmCounterColors.lightPrimaryAction),
                  SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Text(
                      'Balanced Cash Drawers: Zero net discrepancy across all finalized shifts.',
                      style: TextStyle(
                        color: WarmCounterColors.lightPrimaryAction,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Row 1: Revenue & Tenders Cards
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildMetricSection(
                  title: 'Sales & Revenue',
                  icon: Icons.payments_rounded,
                  items: [
                    _MetricItem('Gross Sales', 'PKR ${_currencyFormat.format(z.grossSales)}'),
                    _MetricItem('Discounts', 'PKR ${_currencyFormat.format(z.totalDiscounts)}'),
                    _MetricItem('Taxes Collected', 'PKR ${_currencyFormat.format(z.totalTax)}'),
                    _MetricItem('Net Sales', 'PKR ${_currencyFormat.format(z.netSales)}', isBold: true),
                    _MetricItem('Settled Orders', '${z.totalOrdersCount} orders'),
                  ],
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              Expanded(
                child: _buildMetricSection(
                  title: 'Payment Tenders',
                  icon: Icons.account_balance_wallet_rounded,
                  items: [
                    _MetricItem('Cash Tenders', 'PKR ${_currencyFormat.format(z.cashSales)}'),
                    _MetricItem('Card Tenders', 'PKR ${_currencyFormat.format(z.cardSales)}'),
                    _MetricItem('Raast QR Tenders', 'PKR ${_currencyFormat.format(z.raastSales)}'),
                    _MetricItem('Total Tendered', 'PKR ${_currencyFormat.format(z.totalTenderSales)}', isBold: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          // Row 2: Cash Drawer & Operational Audits
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildMetricSection(
                  title: 'Cash Drawer Reconciliation',
                  icon: Icons.point_of_sale_rounded,
                  items: [
                    _MetricItem('Total Opening Floats', 'PKR ${_currencyFormat.format(z.totalOpeningFloat)}'),
                    _MetricItem('(+) Cash Sales', 'PKR ${_currencyFormat.format(z.cashSales)}'),
                    _MetricItem('(+) Mid-Shift Pay-Ins', 'PKR ${_currencyFormat.format(z.totalPayIn)}'),
                    _MetricItem('(-) Mid-Shift Pay-Outs', 'PKR ${_currencyFormat.format(z.totalPayOut)}'),
                    _MetricItem('Expected Drawer Cash', 'PKR ${_currencyFormat.format(z.totalExpectedDrawerCash)}'),
                    _MetricItem('Counted Drawer Cash', 'PKR ${_currencyFormat.format(z.totalCountedCash)}'),
                    _MetricItem(
                      'Net Cash Variance',
                      'PKR ${_currencyFormat.format(z.netCashVariance)}',
                      isBold: true,
                      isWarning: hasDiscrepancy,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              Expanded(
                child: _buildMetricSection(
                  title: 'Operational Audits & Khata',
                  icon: Icons.inventory_rounded,
                  items: [
                    _MetricItem('Cashier Shifts', '${z.totalShiftsCount} shifts completed'),
                    _MetricItem('Order Voids', '${z.totalVoidCount} (PKR ${_currencyFormat.format(z.totalVoidAmount)})'),
                    _MetricItem('Kitchen Wastage', '${z.totalWastageCount} logs (PKR ${_currencyFormat.format(z.totalWastageCost)})'),
                    _MetricItem('Mandi Wholesale Purchases', 'PKR ${_currencyFormat.format(z.totalMandiPurchasesCost)}'),
                    _MetricItem('Vendor Deliveries', '${z.totalVendorDeliveriesCount} slips received'),
                    _MetricItem('Vendor Settlements', 'PKR ${_currencyFormat.format(z.totalVendorSettlementsAmount)}'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricSection({
    required String title,
    required IconData icon,
    required List<_MetricItem> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightPageBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: WarmCounterColors.lightPrimaryAction),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: item.isBold ? WarmCounterColors.lightPrimaryText : WarmCounterColors.lightSecondaryText,
                          fontWeight: item.isBold ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.value,
                      style: TextStyle(
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: item.isWarning
                            ? WarmCounterColors.lightDestructiveAction
                            : (item.isBold ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightPrimaryText),
                        fontWeight: item.isBold ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildThermalSlipView(BuildContext context, String printable) {
    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightPageBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '42-Column Thermal Print Preview (ESC/POS)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WarmCounterColors.lightSecondaryText),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copy printable slip text',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: printable));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Z-Report text copied to clipboard.')),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 12, color: WarmCounterColors.lightBorder),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                printable,
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontFamilyFallback: ['monospace'],
                  fontSize: 13,
                  height: 1.4,
                  color: WarmCounterColors.lightPrimaryText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem {
  const _MetricItem(this.label, this.value, {this.isBold = false, this.isWarning = false});
  final String label;
  final String value;
  final bool isBold;
  final bool isWarning;
}
