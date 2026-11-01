import 'package:flutter/material.dart';
import '../../../core/settings/keyboard_shortcut_controller.dart';

class KeyboardShortcutsDialog extends StatefulWidget {
  const KeyboardShortcutsDialog({super.key, required this.controller, required this.managerId});
  final KeyboardShortcutController controller;
  final int managerId;
  @override
  State<KeyboardShortcutsDialog> createState() => _KeyboardShortcutsDialogState();
}

class _KeyboardShortcutsDialogState extends State<KeyboardShortcutsDialog> {
  Map<String, String>? _bindings;
  Map<String, String> _original = {};
  String? _message;
  bool _busy = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final bindings = await widget.controller.load();
      if (mounted) setState(() { _original = Map.of(bindings); _bindings = bindings; });
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
  }
  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.controller.save(managerId: widget.managerId, bindings: _bindings!, expected: _original);
      if (mounted) Navigator.pop(context);
    } catch (e) { if (mounted) setState(() => _message = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Cashier keyboard shortcuts'),
    content: SizedBox(width: 540, height: 450, child: _bindings == null
      ? Center(child: Text(_message ?? 'Loading shortcuts…'))
      : ListView(children: [
        const Text('Applies to the cashier register. Shortcuts pause in text fields and dialogs. Blank means unassigned. Category numbers follow display order.'),
        if (_message != null) Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (final action in _bindings!.keys) ListTile(
          title: Text(KeyboardShortcutController.actionLabels[action] ?? action),
          trailing: DropdownButton<String>(mouseCursor: WidgetStateMouseCursor.clickable, value: _bindings![action],
            items: KeyboardShortcutController.allowedKeys.map((key) => DropdownMenuItem(value: key, child: Text(key.isEmpty ? 'Unassigned' : key))).toList(),
            onChanged: _busy ? null : (value) => setState(() => _bindings![action] = value!))),
      ])),
    actions: [
      TextButton(onPressed: _busy || _bindings == null ? null : () => setState(() => _bindings = Map.of(KeyboardShortcutController.defaults)), child: const Text('Reset default')),
      TextButton(onPressed: _busy || _bindings == null ? null : () async {
        setState(() => _busy = true);
        try {
          final prior = await widget.controller.prior(widget.managerId);
          if (mounted) setState(() => _bindings = prior);
        } catch (e) { if (mounted) setState(() => _message = '$e'); }
        finally { if (mounted) setState(() => _busy = false); }
      }, child: const Text('Restore prior version')),
      TextButton(onPressed: _busy || _bindings == null ? null : () {
        try {
          KeyboardShortcutController.validate(_bindings!);
          setState(() => _message = 'Mapping valid. Preview: ${_bindings!.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.value} → ${e.key}').join(', ')}');
        } catch (e) { setState(() => _message = '$e'); }
      }, child: const Text('Test mapping')),
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _busy || _bindings == null ? null : _save, child: const Text('Save shortcuts')),
    ],
  );
}
