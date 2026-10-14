import 'package:flutter/material.dart';
import '../../core/auth/department.dart';
import '../../core/theme/theme.dart';

/// Modal dialog for adding a new custom restaurant department.
class DepartmentFormDialog extends StatefulWidget {
  const DepartmentFormDialog({
    super.key,
    required this.onSave,
  });

  final Future<Department> Function(String name) onSave;

  @override
  State<DepartmentFormDialog> createState() => _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends State<DepartmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final dept = await widget.onSave(_nameController.text.trim());
      if (mounted) {
        Navigator.of(context).pop(dept);
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
                      Icons.corporate_fare_rounded,
                      color: WarmCounterColors.lightPrimaryAction,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Text(
                      'Add Custom Department',
                      style: WarmCounterTypography.pageHeading.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
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
                key: const ValueKey('department_name_input'),
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Department Name',
                  hintText: 'e.g. Riders, Catering, Front Counter',
                  border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a department name.';
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
                    key: const ValueKey('department_save_button'),
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
                        : const Text('Create Department'),
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
