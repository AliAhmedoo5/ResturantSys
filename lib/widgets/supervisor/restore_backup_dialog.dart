import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../core/database/database_restore_service.dart';

class RestoreBackupDialog extends StatefulWidget {
  const RestoreBackupDialog({super.key, required this.service});
  final DatabaseRestoreService service;
  @override
  State<RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<RestoreBackupDialog> {
  PreparedRestore? _prepared;
  bool _busy = false, _scheduled = false, _confirmed = false;
  String? _error, _safety;

  Future<void> _select() async {
    setState(() { _busy = true; _error = null; });
    try {
      final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label: 'POS backup', extensions: ['zip'])]);
      if (file == null) return;
      final result = await widget.service.prepare(file.path);
      if (!mounted) { await result.discard(); return; }
      await _prepared?.discard();
      setState(() { _prepared = result; _confirmed = false; });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _restore() async {
    setState(() { _busy = true; _error = null; });
    try {
      final safety = await widget.service.schedule(_prepared!);
      if (mounted) setState(() { _scheduled = true; _safety = safety; });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  void dispose() {
    if (!_scheduled) _prepared?.discard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_scheduled,
    child: AlertDialog(
      title: const Text('Restore a restaurant backup'),
      content: SizedBox(width: 580, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Close every shift and the Business Day before starting. Select a POS backup ZIP. We check the database, Manager access and catalog photos before replacing records.'),
        const SizedBox(height: 16),
        if (!_scheduled) OutlinedButton.icon(onPressed: _busy ? null : _select, icon: const Icon(Icons.folder_open), label: const Text('Select backup ZIP')),
        if (_prepared != null) ...[
          const SizedBox(height: 16),
          Text('Archive: ${_prepared!.archiveName}\nSchema: ${_prepared!.schemaVersion}\nOrders: ${_prepared!.orderCount}\nMedia files: ${_prepared!.mediaCount}'),
          if (!_scheduled) CheckboxListTile(contentPadding: EdgeInsets.zero, value: _confirmed,
            title: const Text('Replace all current restaurant records and photos with this backup. Changes made since the backup will be removed. I know a Manager PIN from this backup.'),
            onChanged: _busy ? null : (value) => setState(() => _confirmed = value ?? false)),
        ],
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (_scheduled) SelectableText('Restore is ready. Close the application, then reopen it to finish.\n\nSafety backup: $_safety\n\nAfter restart, sign in using the restored staff PINs. Your original Windows credential store is required.'),
      ]))),
      actions: _scheduled ? [FilledButton(onPressed: () => exit(0), child: const Text('Close application to finish restore'))] : [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: !_busy && _confirmed && _prepared != null ? _restore : null, child: const Text('Create safety backup and restore on restart')),
      ],
    ),
  );
}
