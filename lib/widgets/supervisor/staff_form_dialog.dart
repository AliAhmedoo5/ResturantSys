import 'package:flutter/material.dart';
import '../../core/auth/department.dart';
import '../../core/auth/job_role.dart';
import '../../core/auth/staff.dart';
import '../../core/auth/staff_role.dart';
import '../../core/theme/theme.dart';

/// Modal dialog for registering a new staff member or editing staff details.
class StaffFormDialog extends StatefulWidget {
  const StaffFormDialog({
    super.key,
    required this.departments,
    this.jobRoles = const [],
    this.initialStaff,
    required this.onSave,
  });

  final List<Department> departments;
  final List<JobRole> jobRoles;
  final Staff? initialStaff;
  final Future<void> Function({
    required String name,
    required int departmentId,
    required StaffRole role,
    required String pin,
    required bool loginEnabled,
    required int? jobRoleId,
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
  bool _loginEnabled = false;
  int? _jobRoleId;
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
    _loginEnabled = staff?.loginEnabled ?? false;
    _jobRoleId = staff?.jobRoleId;
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
        loginEnabled: _loginEnabled,
        jobRoleId: _jobRoleId,
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
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit Staff Profile' : 'Register New Staff Member',
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
                key: const ValueKey('staff_name_input'),
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  hintText: 'e.g. Usman Ali',
                  border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                      isExpanded: true,
                      initialValue: _selectedDepartmentId,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      items: widget.departments.map((dept) {
                        return DropdownMenuItem<int>(
                          value: dept.id,
                          child: Text(dept.name, overflow: TextOverflow.ellipsis),
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
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('staff_role_dropdown'),
                      isExpanded: true,
                      initialValue: _loginEnabled ? _selectedRole.code : 'NONE',
                      decoration: const InputDecoration(
                        labelText: 'System access',
                        border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'NONE', child: Text('No login')),
                        ...StaffRole.values.map((role) => DropdownMenuItem(
                          value: role.code, child: Text(role.displayName, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() {
                          _loginEnabled = val != 'NONE';
                          if (_loginEnabled) _selectedRole = StaffRole.fromCode(val);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              DropdownButtonFormField<int>(
                key: ValueKey('staff_job_role_${_jobRoleId ?? 0}'),
                initialValue: _jobRoleId ?? 0,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Job role', helperText: 'Job titles do not grant system access.'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('No job role assigned')),
                  ...widget.jobRoles.map((role) => DropdownMenuItem(value: role.id, child: Text(role.name))),
                ],
                onChanged: (id) => setState(() => _jobRoleId = id == 0 ? null : id),
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              if (_loginEnabled) TextFormField(
                key: const ValueKey('staff_pin_input'),
                controller: _pinController,
                obscureText: _obscurePin,
                keyboardType: TextInputType.number,
                maxLength: _selectedRole == StaffRole.manager ? 8 : 4,
                decoration: InputDecoration(
                  labelText: isEditing
                      ? (_selectedRole == StaffRole.manager
                          ? 'New 4–8 Digit PIN (Leave blank to keep existing)'
                          : 'New 4-Digit PIN (Leave blank to keep existing)')
                      : (_selectedRole == StaffRole.manager ? '4–8 Digit Numeric PIN' : '4-Digit Numeric PIN'),
                  hintText: _selectedRole == StaffRole.manager ? '4 to 8 digits' : '4 digits (e.g. 5678)',
                  counterText: '',
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  ),
                  border: const OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: (val) {
                  if (isEditing && widget.initialStaff!.loginEnabled && (val == null || val.trim().isEmpty)) {
                    return null; // Keep existing PIN
                  }
                  final trimmed = val?.trim() ?? '';
                  if (int.tryParse(trimmed) == null) {
                    return 'PIN must be numeric.';
                  }
                  if (_selectedRole == StaffRole.manager) {
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
              if (isEditing) ...[
                const SizedBox(height: WarmCounterSpacing.space12),
                SwitchListTile(
                  key: const ValueKey('staff_active_switch'),
                  title: const Text('Account Active'),
                  subtitle: const Text('Inactive staff cannot log into terminal or stations.'),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                  activeThumbColor: WarmCounterColors.lightPrimaryAction,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
              const SizedBox(height: WarmCounterSpacing.space24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: WarmCounterSpacing.space12,
                runSpacing: WarmCounterSpacing.space8,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    child: const Text('Cancel'),
                  ),
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
