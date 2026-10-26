import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:resturant_sys/core/shifts/x_report.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for reviewing and copying interim and closing X-Reports.
class XReportDialog extends StatelessWidget {
  const XReportDialog({
    super.key,
    required this.report,
  });

  final XReport report;

  @override
  Widget build(BuildContext context) {
    final printable = report.toPrintableString();

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 740),
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                  decoration: const BoxDecoration(
                    color: WarmCounterColors.lightActiveNavHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: WarmCounterColors.lightPrimaryAction,
                    size: 28,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.isInterim ? 'Interim X-Report Preview' : 'Shift Closing X-Report',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Shift #${report.shiftId} • ${report.cashierName}',
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Copy report text',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: printable));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('X-Report text copied to clipboard.')),
                    );
                  },
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),

            // Monospace report text preview
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBFBFB),
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  border: Border.all(color: WarmCounterColors.lightBorder),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    printable,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontFamilyFallback: ['monospace'],
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: WarmCounterSpacing.space16),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
