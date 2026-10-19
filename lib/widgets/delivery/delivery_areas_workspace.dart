import '../../core/theme/warm_counter_typography.dart';
import 'package:flutter/material.dart';
import '../../core/delivery/delivery_controller.dart';

class DeliveryAreasWorkspace extends StatefulWidget {
  const DeliveryAreasWorkspace({super.key, required this.controller, required this.staffId});
  final DeliveryController controller;
  final int staffId;
  @override
  State<DeliveryAreasWorkspace> createState() => _DeliveryAreasWorkspaceState();
}

class _DeliveryAreasWorkspaceState extends State<DeliveryAreasWorkspace> {
  List<DeliveryArea> _areas = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final areas = await widget.controller.getAreas();
      if (mounted) setState(() { _areas = areas; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }
  Future<void> _edit([DeliveryArea? area]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _AreaDialog(controller: widget.controller, staffId: widget.staffId, area: area));
    if (saved == true) await _load();
  }
  Future<void> _archive(DeliveryArea area) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Archive ${area.name}?'), content: const Text('This area will no longer be selectable. Existing orders and saved addresses will be retained.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive'))]));
    if (confirmed != true) return;
    try { await widget.controller.archiveArea(staffId: widget.staffId, id: area.id); await _load(); }
    catch (e) { if (mounted) setState(() => _error = '$e'); }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Expanded(child: Text('Delivery service areas', style: TextStyle(fontSize: 22))),
      FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add area'))])),
    if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _areas.isEmpty ? const Center(child: Text('Add an area to enable delivery checkout.')) : ListView.builder(
      itemCount: _areas.length, itemBuilder: (context, index) { final area = _areas[index]; return ListTile(
        title: Text('${area.name} (${area.code}) • ${area.isActive ? "Active" : "Inactive"}'),
        subtitle: Text('${area.coverageDescription}\nFee Rs ${(area.deliveryFeePaisa / 100).toStringAsFixed(2)} • Minimum Rs ${(area.minOrderPaisa / 100).toStringAsFixed(2)}'),
        isThreeLine: true,
        subtitleTextStyle: WarmCounterTypography.tabularNumbers.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: 'Edit area', onPressed: () => _edit(area), icon: const Icon(Icons.edit)),
          IconButton(tooltip: 'Archive area', onPressed: () => _archive(area), icon: const Icon(Icons.archive_outlined))]));
      })),
  ]);
}

class _AreaDialog extends StatefulWidget {
  const _AreaDialog({required this.controller, required this.staffId, this.area});
  final DeliveryController controller;
  final int staffId;
  final DeliveryArea? area;
  @override
  State<_AreaDialog> createState() => _AreaDialogState();
}
class _AreaDialogState extends State<_AreaDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _code, _coverage, _fee, _minimum;
  late bool _active;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState(); final area = widget.area;
    _name = TextEditingController(text: area?.name); _code = TextEditingController(text: area?.code);
    _coverage = TextEditingController(text: area?.coverageDescription);
    _fee = TextEditingController(text: '${area?.deliveryFeePaisa ?? 0}');
    _minimum = TextEditingController(text: '${area?.minOrderPaisa ?? 0}'); _active = area?.isActive ?? true;
  }
  @override
  void dispose() { for (final c in [_name, _code, _coverage, _fee, _minimum]) { c.dispose(); } super.dispose(); }
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.controller.saveArea(staffId: widget.staffId, id: widget.area?.id, name: _name.text, code: _code.text,
        coverageDescription: _coverage.text, deliveryFeePaisa: int.parse(_fee.text), minOrderPaisa: int.parse(_minimum.text), isActive: _active);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() { _saving = false; _error = '$e'; }); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: Text(widget.area == null ? 'Add delivery area' : 'Edit delivery area'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Area name'), validator: (v) => v!.trim().isEmpty ? 'Enter a name' : null),
      TextFormField(controller: _code, decoration: const InputDecoration(labelText: 'Area code'), validator: (v) => v!.trim().isEmpty ? 'Enter a code' : null),
      TextFormField(controller: _coverage, decoration: const InputDecoration(labelText: 'Coverage description'), maxLines: 2),
      for (final field in [(_fee, 'Delivery fee (paisa)'), (_minimum, 'Minimum food order (paisa)')])
        TextFormField(controller: field.$1, style: WarmCounterTypography.tabularNumbers, textAlign: TextAlign.right, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: field.$2, helperText: '100 paisa = Rs 1.00'),
          validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0 ? 'Enter non-negative whole paisa' : null),
      SwitchListTile(title: const Text('Active for delivery checkout'), value: _active, onChanged: _saving ? null : (v) => setState(() => _active = v)),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])))), actions: [TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save area'))]);
}

