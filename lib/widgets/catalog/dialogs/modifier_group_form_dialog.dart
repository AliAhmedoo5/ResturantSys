import 'package:flutter/material.dart';
import '../../../core/catalog/menu_item.dart';
import '../../../core/catalog/modifier_group.dart';
import '../../../core/theme/theme.dart';

/// Configures selection limits for an item's customization group.
class ModifierGroupFormDialog extends StatefulWidget {
  const ModifierGroupFormDialog({super.key, required this.menuItems, required this.onSave, this.group});

  final List<MenuItem> menuItems;
  final ModifierGroup? group;
  final Future<void> Function(ModifierGroup group) onSave;

  @override
  State<ModifierGroupFormDialog> createState() => _ModifierGroupFormDialogState();
}

class _ModifierGroupFormDialogState extends State<ModifierGroupFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  int? _itemId;
  late String _mode;
  late bool _required;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _itemId = group?.menuItemId;
    _name = TextEditingController(text: group?.name ?? '');
    _minimum = TextEditingController(text: '${group?.minSelected ?? 0}');
    _maximum = TextEditingController(text: '${group?.maxSelected ?? 1}');
    _mode = group?.selectionMode ?? 'SINGLE';
    _required = group?.isRequired ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _minimum.dispose();
    _maximum.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(ModifierGroup(
        id: widget.group?.id ?? 0,
        menuItemId: _itemId!,
        name: _name.text.trim(),
        selectionMode: _mode,
        minSelected: int.parse(_minimum.text),
        maxSelected: int.parse(_maximum.text),
        isRequired: _required,
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.group == null ? 'Add Modifier Group' : 'Edit Modifier Group'),
    shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              mouseCursor: WidgetStateMouseCursor.clickable,
              key: const ValueKey('group_item_dropdown'),
              initialValue: _itemId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Menu item'),
              items: widget.menuItems.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name))).toList(),
              onChanged: widget.group != null ? null : (value) => setState(() => _itemId = value),
              validator: (value) => value == null ? 'Choose a menu item' : null,
            ),
            TextFormField(
              key: const ValueKey('group_name_field'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Group name', hintText: 'e.g. Patty size'),
              validator: (value) => value == null || value.trim().isEmpty ? 'Enter a group name' : null,
            ),
            DropdownButtonFormField<String>(
              mouseCursor: WidgetStateMouseCursor.clickable,
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Selection mode'),
              items: const [
                DropdownMenuItem(value: 'SINGLE', child: Text('Single choice')),
                DropdownMenuItem(value: 'MULTIPLE', child: Text('Multiple choices')),
              ],
              onChanged: (value) => setState(() {
                _mode = value!;
                if (_mode == 'SINGLE') { _maximum.text = '1'; _minimum.text = _required ? '1' : '0'; }
              }),
            ),
            TextFormField(
              key: const ValueKey('group_minimum_field'),
              controller: _minimum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Minimum selections'),
              validator: (value) {
                final minimum = int.tryParse(value ?? '');
                if (minimum == null || minimum < 0) return 'Enter zero or a positive integer';
                if (_mode == 'SINGLE' && minimum > 1) return 'Single choice allows at most one';
                return null;
              },
            ),
            TextFormField(
              key: const ValueKey('group_maximum_field'),
              controller: _maximum,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Maximum selections'),
              validator: (value) {
                final maximum = int.tryParse(value ?? '');
                if (maximum == null || maximum < 1) return 'Enter a positive integer';
                if (maximum < (int.tryParse(_minimum.text) ?? 0)) return 'Maximum must be at least minimum';
                if (_mode == 'SINGLE' && maximum != 1) return 'Single choice requires maximum one';
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Required'),
              subtitle: const Text('Cashier must select at least one option'),
              value: _required,
              onChanged: (value) => setState(() => _required = value),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: WarmCounterColors.lightDestructiveAction)),
          ]),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ElevatedButton(key: const ValueKey('save_modifier_group_button'), onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Save Group')),
    ],
  );
}
