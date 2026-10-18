import 'package:flutter/material.dart';
import '../../core/auth/staff.dart';
import '../../core/theme/theme.dart';

/// Modal dialog for supervisor/owner to update or reset a staff member's 4-digit PIN.
class StaffPinDialog extends StatefulWidget {
  const StaffPinDialog({
    super.key,
    required this.staff,
    required this.onUpdatePin,
  });

  final Staff staff;
  final Future<void> Function(int staffId, String newPin) onUpdatePin;

  @override
  State<StaffPinDialog> createState() => _StaffPinDialogState();
}

class _StaffPinDialogState extends State<StaffPinDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _obscurePin = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final newPin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (newPin != confirmPin) {
      setState(() => _errorMessage = 'PINs do not match. Please re-enter.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onUpdatePin(widget.staff.id, newPin);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
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
        width: 440,
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
        child: Form(
          key: _formKey,
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
                      Icons.pin_rounded,
                      color: WarmCounterColors.lightPrimaryAction,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Staff PIN',
                          style: WarmCounterTypography.pageHeading.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.staff.name,
                          style: WarmCounterTypography.bodyMedium.copyWith(
                            color: WarmCounterColors.lightSecondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightDestructiveHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightDestructiveAction),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: WarmCounterTypography.bodyMedium.copyWith(
                      color: WarmCounterColors.lightDestructiveAction,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
              ],
              TextFormField(
                key: const ValueKey('new_pin_input'),
                controller: _pinController,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: widget.staff.role.isManager ? 8 : 4,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.staff.role.isManager ? 'New 4–8 Digit PIN' : 'New 4-Digit PIN',
                  hintText: widget.staff.role.isManager ? '4 to 8 digits' : '4 digits (e.g. 7777)',
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  ),
                  border: const OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  final trimmed = val?.trim() ?? '';
                  if (int.tryParse(trimmed) == null) {
                    return 'PIN must be numeric.';
                  }
                  if (widget.staff.role.isManager) {
                    if (trimmed.length < 4 || trimmed.length > 8) {
                      return 'Manager PIN must be between 4 and 8 digits.';
                    }
                  } else {
                    if (trimmed.length != 4) {
                      return 'Cashier PIN must be exactly 4 numeric digits.';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              TextFormField(
                key: const ValueKey('confirm_new_pin_input'),
                controller: _confirmPinController,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: widget.staff.role.isManager ? 8 : 4,
                decoration: InputDecoration(
                  labelText: widget.staff.role.isManager ? 'Confirm New 4–8 Digit PIN' : 'Confirm New PIN',
                  hintText: widget.staff.role.isManager ? 'Re-enter 4 to 8 digits' : 'Re-enter 4 digits',
                  counterText: '',
                  border: const OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  final trimmed = val?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return 'Please confirm the PIN.';
                  }
                  if (trimmed != _pinController.text.trim()) {
                    return 'PINs do not match.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  ElevatedButton(
                    key: const ValueKey('update_pin_save_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: WarmCounterColors.lightTextOnPrimary,
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Update PIN'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
