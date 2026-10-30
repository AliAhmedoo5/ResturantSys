import 'package:flutter/material.dart';
import '../../../core/inventory/stock_count_controller.dart';

class StockCountsDialog extends StatefulWidget {
  const StockCountsDialog({super.key, required this.controller, required this.managerId});
  final StockCountController controller;
  final int managerId;
  @override
  State<StockCountsDialog> createState() => _StockCountsDialogState();
}

class _StockCountsDialogState extends State<StockCountsDialog> {
  List<Map<String, Object?>> _sessions = [];
  List<Map<String, Object?>> _ingredients = [];
  final Set<int> _selection = {};
  final _reason = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void initState() { super.initState(); _run(_reload); }
  @override
  void dispose() { _reason.dispose(); super.dispose(); }
  Future<void> _reload() async {
    final sessions = await widget.controller.sessions(widget.managerId);
    final ingredients = await widget.controller.ingredients(widget.managerId);
    if (mounted) setState(() { _sessions = sessions; _ingredients = ingredients; });
  }
  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try { await action(); await _reload(); }
    catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(Map<String, Object?> session) async {
    final id = session['id'] as int;
    final lines = await widget.controller.lines(widget.managerId, id);
    final fields = {for (final line in lines) line['ingredient_id'] as int:
      TextEditingController(text: line['counted']?.toString() ?? '')};
    String? error;
    bool saving = false;
    if (!mounted) { for (final f in fields.values) { f.dispose(); } return; }
    await showDialog<void>(context: context, barrierDismissible: false, builder: (context) => StatefulBuilder(builder: (context, setLocal) {
      Future<void> perform(Future<void> Function() action) async {
        setLocal(() { saving = true; error = null; });
        try { await action(); if (context.mounted) Navigator.pop(context); }
        catch (e) { if (context.mounted) setLocal(() => error = '$e'); }
        finally { if (context.mounted) setLocal(() => saving = false); }
      }
      return AlertDialog(title: Text('Count #$id · ${session['status']}'),
        content: SizedBox(width: 600, height: 380, child: ListView(children: [
          Text('Reason: ${session['reason']}\nCount taker: ${session['creator_name'] ?? session['created_by']} · Snapshot: ${session['created_at']}\nApprover: ${session['approver_name'] ?? session['approved_by'] ?? 'Pending'}'),
          const Text('Quantities use the displayed storage unit. Any movement since the snapshot requires a new count.'),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          for (final line in lines) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: TextField(
            controller: fields[line['ingredient_id']], enabled: !saving && session['status'] == 'DRAFT',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: '${line['name']} (${line['unit']})',
              helperText: 'Expected ${line['expected']} · Variance ${line['variance'] ?? 'Pending'} · Estimated value ${line['estimated_cost_paisa'] == null ? 'Unknown cost' : 'Rs ${(line['estimated_cost_paisa'] as int) / 100}'}',
              border: const OutlineInputBorder()))),
        ])),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Close')),
          if (session['status'] == 'DRAFT') FilledButton(onPressed: saving ? null : () => perform(() async {
            final quantities = <int, double>{};
            for (final entry in fields.entries) {
              final value = double.tryParse(entry.value.text.trim());
              if (value == null || !value.isFinite || value < 0) throw ArgumentError('Enter every non-negative physical quantity.');
              quantities[entry.key] = value;
            }
            await widget.controller.submit(managerId: widget.managerId, id: id, quantities: quantities);
          }), child: const Text('Submit count')),
          if (session['status'] == 'SUBMITTED') ...[
            TextButton(onPressed: saving ? null : () => perform(() => widget.controller.review(managerId: widget.managerId, id: id, approve: false)), child: const Text('Reject')),
            FilledButton(onPressed: saving ? null : () => perform(() => widget.controller.review(managerId: widget.managerId, id: id, approve: true)), child: const Text('Approve')),
          ],
          if (session['status'] == 'APPROVED') FilledButton(onPressed: saving ? null : () => perform(() => widget.controller.post(managerId: widget.managerId, id: id)), child: const Text('Post adjustment')),
        ]);
    }));
    // Controllers remain alive through the dialog's exit transition.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    for (final field in fields.values) { field.dispose(); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Physical stock counts'),
    content: SizedBox(width: 700, height: 480, child: ListView(children: [
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      TextField(controller: _reason, enabled: !_busy, decoration: const InputDecoration(labelText: 'Reason / storage area')),
      Wrap(children: [for (final ingredient in _ingredients) Padding(padding: const EdgeInsets.all(4), child: FilterChip(
        mouseCursor: WidgetStateMouseCursor.clickable,
        label: Text('${ingredient['name']} (${ingredient['storage_unit']})'), selected: _selection.contains(ingredient['id']),
        onSelected: _busy ? null : (selected) => setState(() { if (selected) { _selection.add(ingredient['id'] as int); } else { _selection.remove(ingredient['id']); } }))) ]),
      FilledButton(onPressed: _busy ? null : () => _run(() async {
        await widget.controller.start(managerId: widget.managerId, ingredientIds: _selection.toList(), reason: _reason.text);
        _reason.clear(); _selection.clear();
      }), child: const Text('Start count snapshot')),
      const Divider(),
      for (final session in _sessions) ListTile(title: Text('Count #${session['id']} · ${session['status']}'),
        subtitle: Text('${session['reason']} · ${session['created_at']}'), trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : () => _run(() => _open(session))),
    ])),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Close'))],
  );
}
