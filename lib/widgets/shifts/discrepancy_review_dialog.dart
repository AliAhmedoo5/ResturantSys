import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Supervisor modal dialog for inspecting and resolving flagged cash discrepancies asynchronously.
class DiscrepancyReviewDialog extends StatefulWidget {
  const DiscrepancyReviewDialog({
    super.key,
    required this.flaggedShifts,
    required this.onResolveDiscrepancy,
  });

  final List<Shift> flaggedShifts;
  final Future<void> Function(int shiftId, String resolutionNotes) onResolveDiscrepancy;

  @override
  State<DiscrepancyReviewDialog> createState() => _DiscrepancyReviewDialogState();
}

class _DiscrepancyReviewDialogState extends State<DiscrepancyReviewDialog> {
  int? _activeResolvingShiftId;
  final TextEditingController _notesController = TextEditingController();
  String? _notesError;
  bool _isSubmitting = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submitResolution(int shiftId) async {
    final notes = _notesController.text.trim();
    if (notes.isEmpty) {
      setState(() {
        _notesError = 'Resolution audit notes are mandatory.';
      });
      return;
    }

    setState(() {
      _notesError = null;
      _isSubmitting = true;
    });

    try {
      await widget.onResolveDiscrepancy(shiftId, notes);
      if (mounted) {
        setState(() {
          _activeResolvingShiftId = null;
          _notesController.clear();
          _isSubmitting = false;
        });
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _notesError = e.toString().replaceFirst('StateError: ', '').replaceFirst('ArgumentError: ', '');
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
        width: 680,
        constraints: const BoxConstraints(maxHeight: 760),
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
                    color: Color(0xFFFDE8E8),
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFF9B1C1C),
                    size: 28,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discrepancy Review Queue',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Asynchronous supervisor audit for flagged cashier drawer variances',
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

            // Content
            Expanded(
              child: widget.flaggedShifts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline, color: WarmCounterColors.lightPrimaryAction, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'All Shifts Clean',
                            style: WarmCounterTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'No shifts currently require supervisor variance review.',
                            style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: widget.flaggedShifts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final shift = widget.flaggedShifts[index];
                        final isResolvingThis = _activeResolvingShiftId == shift.id;
                        final variance = shift.discrepancy ?? 0.0;
                        final isShortage = variance < 0;

                        return Container(
                          padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                          decoration: BoxDecoration(
                            color: WarmCounterColors.lightPageBackground,
                            borderRadius: WarmCounterSpacing.controlBorderRadius,
                            border: Border.all(
                              color: isShortage ? const Color(0xFFF98080) : const Color(0xFFFACA15),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    shift.staffName ?? 'Cashier #${shift.staffId}',
                                    style: WarmCounterTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isShortage ? const Color(0xFFFDE8E8) : const Color(0xFFFEF08A),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${isShortage ? "Shortage: " : "Overage: "}Rs ${_currencyFormat.format(variance)}',
                                      style: TextStyle(
                                        color: isShortage ? const Color(0xFF9B1C1C) : const Color(0xFF723B10),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Shift #${shift.id} • Day #${shift.businessDayId} • Opened: ${_dateFormat.format(shift.openedAt)}${shift.closedAt != null ? " • Closed: ${_dateFormat.format(shift.closedAt!)}" : ""}',
                                style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('Opening Float: Rs ${_currencyFormat.format(shift.openingFloat)}',
                                      style: WarmCounterTypography.caption),
                                  const SizedBox(width: 16),
                                  Text('Expected: Rs ${_currencyFormat.format(shift.expectedCash ?? 0.0)}',
                                      style: WarmCounterTypography.caption),
                                  const SizedBox(width: 16),
                                  Text('Counted: Rs ${_currencyFormat.format(shift.countedCash ?? 0.0)}',
                                      style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.bold)),
                                ],
                              ),

                              if (isResolvingThis) ...[
                                const Divider(height: 20, color: WarmCounterColors.lightBorder),
                                Text(
                                  'Supervisor Investigation Notes (Mandatory):',
                                  style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  key: const ValueKey('resolution_notes_input'),
                                  controller: _notesController,
                                  maxLines: 2,
                                  decoration: InputDecoration(
                                    hintText: 'Enter root-cause explanation (e.g. accepted bad note, drawer recount)',
                                    errorText: _notesError,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => setState(() => _activeResolvingShiftId = null),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      key: const ValueKey('confirm_resolve_button'),
                                      onPressed: _isSubmitting ? null : () => _submitResolution(shift.id),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: WarmCounterColors.lightPrimaryAction,
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSubmitting
                                          ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Text('Confirm Resolution'),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton(
                                    key: ValueKey('resolve_shift_btn_${shift.id}'),
                                    onPressed: () {
                                      setState(() {
                                        _activeResolvingShiftId = shift.id;
                                        _notesController.clear();
                                        _notesError = null;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: WarmCounterColors.lightSurfaceMuted,
                                      foregroundColor: WarmCounterColors.lightPrimaryText,
                                    ),
                                    child: const Text('Audit & Resolve'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: WarmCounterSpacing.space16),

            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, WarmCounterSpacing.touchTargetMin),
                  shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
