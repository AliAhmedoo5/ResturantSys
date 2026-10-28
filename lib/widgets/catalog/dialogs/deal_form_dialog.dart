import 'package:flutter/material.dart';
import '../../../core/catalog/menu_item.dart';
import '../../../core/orders/deal.dart';
import '../../../core/orders/deal_item.dart';
import '../../../core/catalog/catalog_and_recipe_controller.dart';

class DealFormDialog extends StatefulWidget {
  const DealFormDialog({super.key, required this.controller, required this.managerId,
    required this.menuItems, this.deal});
  final CatalogAndRecipeController controller;
  final int managerId;
  final List<MenuItem> menuItems;
  final Deal? deal;
  @override
  State<DealFormDialog> createState() => _DealFormDialogState();
}

class _Slot {
  _Slot(String name, {this.id}) : name = TextEditingController(text: name);
  final int? id;
  final TextEditingController name;
  final Map<int, TextEditingController> choices = {};
  int? defaultId;
  void dispose() { name.dispose(); for (final field in choices.values) { field.dispose(); } }
}

class _DealFormDialogState extends State<DealFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.deal?.name ?? '');
  late final _price = TextEditingController(text: widget.deal?.basePrice.toStringAsFixed(2) ?? '0.00');
  late bool _active = widget.deal?.isActive ?? false;
  final _slots = <_Slot>[];
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final item in widget.deal?.items ?? <DealItem>[]) {
      final slot = _Slot(item.groupName, id: item.id);
      for (final option in item.options) {
        slot.choices[option.menuItemId] = TextEditingController(text: option.upgradePrice.toStringAsFixed(2));
        if (option.isDefault) slot.defaultId = option.menuItemId;
      }
      final defaultId = item.defaultMenuItemId;
      if (defaultId != null) {
        slot.choices.putIfAbsent(defaultId, () => TextEditingController(text: '0.00'));
        slot.defaultId ??= defaultId;
      }
      // Expand older category-based slots into explicit selectable components.
      if (item.options.isEmpty && item.categoryId != null) {
        for (final menu in widget.menuItems.where((m) => m.categoryId == item.categoryId && m.isActive)) {
          slot.choices.putIfAbsent(menu.id, () => TextEditingController(text:
            (item.isUpgradeable && menu.id != defaultId ? item.upgradePrice : 0.0).toStringAsFixed(2)));
        }
      }
      _slots.add(slot);
    }
  }
  @override
  void dispose() { _name.dispose(); _price.dispose(); for (final slot in _slots) { slot.dispose(); } super.dispose(); }
  String? _money(String? text) {
    final value = double.tryParse(text ?? '');
    return value == null || !value.isFinite || value < 0 ||
      (value * 100 - (value * 100).round()).abs() > 0.000001 ? 'Enter a non-negative price, at most 2 decimals' : null;
  }
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.controller.saveDeal(managerId: widget.managerId, id: widget.deal?.id,
        name: _name.text, basePrice: double.parse(_price.text), isActive: _active,
        items: _slots.map((s) => DealItemDraft(id: s.id, groupName: s.name.text, options: s.choices.entries.map((e) =>
          DealOptionDraft(menuItemId: e.key, isDefault: e.key == s.defaultId,
            upgradePrice: double.parse(e.value.text))).toList())).toList());
      if (mounted) Navigator.pop(context, true);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.deal == null ? 'Create Deal' : 'Edit Deal'),
    content: SizedBox(width: 680, height: 540, child: Form(key: _form, child: ListView(children: [
      TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Deal name'),
        validator: (v) => v == null || v.trim().isEmpty ? 'Enter a name' : null),
      TextFormField(controller: _price, decoration: const InputDecoration(labelText: 'Base price (Rs)'), validator: _money),
      SwitchListTile(title: const Text('Active — all choices require verified recipes'), value: _active,
        onChanged: _saving ? null : (v) => setState(() => _active = v)),
      const Text('Add one component per serving. Select allowed items, a default and any extra price.'),
      for (final slot in _slots) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [Expanded(child: TextFormField(controller: slot.name,
          decoration: const InputDecoration(labelText: 'Component name'),
          validator: (v) => v == null || v.trim().isEmpty ? 'Enter a component name' : null)),
          IconButton(tooltip: 'Remove component', onPressed: _saving ? null : () => setState(() { _slots.remove(slot); slot.dispose(); }), icon: const Icon(Icons.delete_outline))]),
        for (final item in widget.menuItems) Row(children: [
          Checkbox(value: slot.choices.containsKey(item.id), onChanged: _saving ? null : (value) => setState(() {
            if (value == true) { slot.choices[item.id] = TextEditingController(text: '0.00'); slot.defaultId ??= item.id; }
            else { slot.choices.remove(item.id)?.dispose(); if (slot.defaultId == item.id) slot.defaultId = null; }
          })),
          Expanded(child: Text('${item.name}${item.isActive ? '' : ' (inactive)'}')),
          if (slot.choices.containsKey(item.id)) ...[
            TextButton(onPressed: _saving ? null : () => setState(() => slot.defaultId = item.id),
              child: Text(slot.defaultId == item.id ? 'Default ✓' : 'Set default')),
            SizedBox(width: 120, child: TextFormField(controller: slot.choices[item.id],
              decoration: const InputDecoration(labelText: 'Extra Rs'), validator: _money)),
          ],
        ]),
      ]))),
      TextButton.icon(onPressed: _saving ? null : () => setState(() => _slots.add(_Slot(''))),
        icon: const Icon(Icons.add), label: const Text('Add component')),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]))),
    actions: [TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save Deal'))]);
}
