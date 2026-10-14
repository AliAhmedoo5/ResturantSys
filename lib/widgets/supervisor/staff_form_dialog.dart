import 'package:flutter/material.dart';
import '../../core/auth/department.dart';
import '../../core/auth/staff.dart';
import '../../core/auth/staff_role.dart';
import '../../core/theme/theme.dart';

/// Modal dialog for registering a new staff member or editing staff details.
class StaffFormDialog extends StatefulWidget {
  const StaffFormDialog({
    super.key,
    required this.departments,
    this.initialStaff,
    required this.onSave,
  });

  final List<Department> departments;
  final Staff? initialStaff;
  final Future<void> Function({
    required String name,
    required int departmentId,
    required StaffRole role,
    required String pin,
    bool? isActive,
  }) onSave;

  @override
  State<StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _pinController;
  late int _selectedDepartmentId;
  late StaffRole _selectedRole;
  late bool _isActive;
  bool _obscurePin = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final staff = widget.initialStaff;
    _nameController = TextEditingController(text: staff?.name ?? '');
    _pinController = TextEditingController();
    _selectedDepartmentId = staff?.departmentId ??
        (widget.departments.isNotEmpty ? widget.departments.first.id : 1);
    _selectedRole = staff?.role ?? StaffRole.cashier;
    _isActive = staff?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onSave(
        name: _nameController.text.trim(),
        departmentId: _selectedDepartmentId,
        role: _selectedRole,
        pin: _pinController.text.trim(),
        isActive: _isActive,
      );
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
    final isEditing = widget.initialStaff != null;

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      backgroundColor: WarmCounterColors.lightCardBackground,
      child: Container(
        width: 520,
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
                      Icons.person_add_rounded,
                      color: WarmCounterColors.lightPrimaryAction,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Text(
                    isEditing ? 'Edit Staff Profile' : 'Register New Staff Member',
                    style: WarmCounterTypography.pageHeading.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WarmCounterSpacing.space20),
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
                key: const ValueKey('staff_name_input'),
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'e.g. Usman Ali',
                  border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter the staff member name.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              Row(
                children: [
                  // Department Dropdown
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('staff_department_dropdown'),
                      value: _selectedDepartmentId,
                      decoration: InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      items: widget.departments.map((dept) {
                        return DropdownMenuItem<int>(
                          value: dept.id,
                          child: Text(dept.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedDepartmentId = val);
                      },
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  // Role Dropdown
                  Expanded(
                    child: DropdownButtonFormField<StaffRole>(
                      key: const ValueKey('staff_role_dropdown'),
                      value: _selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Role',
                        border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      items: StaffRole.values.map((role) {
                        return DropdownMenuItem<StaffRole>(
                          value: role,
                          child: Text(role.displayName),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedRole = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              TextFormField(
                key: const ValueKey('staff_pin_input'),
                controller: _pinController,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: isEditing ? 'New 4-Digit PIN (Leave blank to keep existing)' : '4-Digit Numeric PIN',
                  hintText: '4 digits (e.g. 5678)',
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  ),
                  border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (isEditing && (val == null || val.trim().isEmpty)) {
                    return null; // Keep existing PIN
                  }
                  if (val == null || val.trim().length != 4 || int.tryParse(val.trim()) == null) {
                    return 'PIN must be exactly 4 numeric digits.';
                  }
                  return null;
                },
              ),
              if (isEditing) ...[
                const SizedBox(height: WarmCounterSpacing.space12),
                SwitchListTile(
                  key: const ValueKey('staff_active_switch'),
                  title: const Text('Account Active'),
                  subtitle: const Text('Inactive staff cannot log into terminal or stations.'),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                  activeColor: WarmCounterColors.lightPrimaryAction,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
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
                    key: const ValueKey('staff_save_button'),
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
                        : Text(isEditing ? 'Save Changes' : 'Register Staff'),
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
