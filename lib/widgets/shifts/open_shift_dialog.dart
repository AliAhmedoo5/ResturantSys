import 'package:flutter/material.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog allowing a cashier to record the opening cash float and open a shift.
class OpenShiftDialog extends StatefulWidget {
  const OpenShiftDialog({
    super.key,
    required this.onOpenShift,
    this.initialFloat = 5000.0,
  });

  final Future<void> Function(double openingFloat) onOpenShift;
  final double initialFloat;

  @override
  State<OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<OpenShiftDialog> {
  late final TextEditingController _floatController;
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _floatController = TextEditingController(
      text: widget.initialFloat > 0 ? widget.initialFloat.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _floatController.text.trim();
    final parsed = double.tryParse(text);

    if (parsed == null || parsed < 0) {
      setState(() {
        _errorMessage = 'Please enter a valid non-negative opening float amount.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    try {
      await widget.onOpenShift(parsed);
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

  void _setPreset(double value) {
    setState(() {
      _floatController.text = value.toStringAsFixed(0);
      _errorMessage = null;
    });
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
                    Icons.point_of_sale_rounded,
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
                        'Open Cashier Shift',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                      ),
                      Text(
                        'Record drawer opening float before taking orders',
                        style: WarmCounterTypography.caption.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: WarmCounterSpacing.space32, color: WarmCounterColors.lightBorder),
            Text(
              'Opening Cash Float (Rs)',
              style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: WarmCounterSpacing.space8),
            TextField(
              key: const ValueKey('opening_float_input'),
              controller: _floatController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: WarmCounterTypography.tabularNumbers.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'Rs ',
                hintText: '0.00',
                errorText: _errorMessage,
                filled: true,
                fillColor: WarmCounterColors.lightPageBackground,
                border: const OutlineInputBorder(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  borderSide: BorderSide(color: WarmCounterColors.lightBorder),
                ),
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space12),
            Text(
              'Quick Presets:',
              style: WarmCounterTypography.caption.copyWith(
                color: WarmCounterColors.lightSecondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space8),
            Wrap(
              spacing: WarmCounterSpacing.space8,
              runSpacing: WarmCounterSpacing.space8,
              children: [
                _buildPresetChip(2000),
                _buildPresetChip(3000),
                _buildPresetChip(5000),
                _buildPresetChip(10000),
              ],
            ),
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
                    key: const ValueKey('confirm_open_shift_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: WarmCounterColors.lightTextOnPrimary,
                      minimumSize: const Size(0, WarmCounterSpacing.touchTargetMin),
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: Text(_isSubmitting ? 'Opening Shift...' : 'Open Shift'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(double amount) {
    return ActionChip(
      label: Text('Rs ${amount.toStringAsFixed(0)}'),
      onPressed: () => _setPreset(amount),
      backgroundColor: WarmCounterColors.lightSurfaceMuted,
      labelStyle: WarmCounterTypography.tabularNumbers.copyWith(
        color: WarmCounterColors.lightPrimaryText,
        fontWeight: FontWeight.w500,
      ),
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
    );
  }
}
