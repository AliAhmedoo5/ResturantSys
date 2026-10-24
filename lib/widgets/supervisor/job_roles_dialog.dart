import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/job_role.dart';

/// Job titles are managed independently of the two system login roles.
class JobRolesDialog extends StatefulWidget {
  const JobRolesDialog({super.key, required this.authService});
  final AuthService authService;

  @override
  State<JobRolesDialog> createState() => _JobRolesDialogState();
}

class _JobRolesDialogState extends State<JobRolesDialog> {
  final _name = TextEditingController();
  List<JobRole> _roles = [];
  JobRole? _editing;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _run(() async {});
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      final roles = await widget.authService.getJobRoles();
      if (mounted) setState(() => _roles = roles);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Manage Job Roles'),
    content: SizedBox(width: 480, height: 400, child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Job titles do not grant system access. Only Cashier and Manager can log in.'),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('job_role_name'), controller: _name,
          enabled: !_busy, decoration: InputDecoration(labelText: _editing == null ? 'New job role' : 'Rename job role')),
        Row(children: [
          FilledButton(key: const ValueKey('save_job_role'), onPressed: _busy ? null : () => _run(() async {
            if (_editing == null) {
              await widget.authService.createJobRole(_name.text);
            } else {
              await widget.authService.updateJobRole(_editing!.id, _name.text);
            }
            _name.clear();
            _editing = null;
          }), child: Text(_editing == null ? 'Add Role' : 'Save Role')),
          if (_editing != null) TextButton(onPressed: _busy ? null : () => setState(() {
            _editing = null; _name.clear();
          }), child: const Text('Cancel Edit')),
        ]),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        Expanded(child: _busy ? const Center(child: CircularProgressIndicator()) : ListView(
          children: _roles.map((role) => ListTile(title: Text(role.name), trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(tooltip: 'Rename ${role.name}', icon: const Icon(Icons.edit_outlined), onPressed: () => setState(() {
                _editing = role; _name.text = role.name;
              })),
              IconButton(tooltip: 'Delete ${role.name}', icon: const Icon(Icons.delete_outline), onPressed: () async {
                final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                  title: Text('Delete ${role.name}?'),
                  content: const Text('Assigned roles must be reassigned before deletion.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                  ],
                ));
                if (confirmed == true && mounted) await _run(() async {
                  await widget.authService.deleteJobRole(role.id);
                  if (_editing?.id == role.id) { _editing = null; _name.clear(); }
                });
              }),
            ],
          ))).toList(),
        )),
      ],
    )),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Done'))],
  );
}
