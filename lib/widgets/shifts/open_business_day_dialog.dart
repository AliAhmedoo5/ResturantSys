import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for opening an overarching Business Day.
class OpenBusinessDayDialog extends StatefulWidget {
  const OpenBusinessDayDialog({
    super.key,
    required this.supervisorName,
    required this.onOpenBusinessDay,
  });

  final String supervisorName;
  final Future<void> Function() onOpenBusinessDay;

  @override
  State<OpenBusinessDayDialog> createState() => _OpenBusinessDayDialogState();
}

class _OpenBusinessDayDialogState extends State<OpenBusinessDayDialog> {
  bool _isSubmitting = false;
  String? _errorMessage;

  final DateFormat _dateFormat = DateFormat('EEEE, MMMM d, yyyy - HH:mm');

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onOpenBusinessDay();
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: Container(
        width: 480,
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
                    Icons.calendar_today_rounded,
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
                        'Open Business Day',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Supervisor: ${widget.supervisorName}',
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space24, color: WarmCounterColors.lightBorder),
            Text(
              'Operating Timestamp:',
              style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _dateFormat.format(DateTime.now()),
              style: WarmCounterTypography.bodyLarge.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Opening the overarching Business Day initializes sequential cashier shifts and starts operational daily accounting. The business day supports cross-midnight operations until concluded by an end-of-day Z-Report.',
              style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFC81E1E), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: WarmCounterSpacing.space24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).maybePop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('confirm_open_business_day_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: Text(_isSubmitting ? 'Opening Day...' : 'Start Operating Day'),
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
