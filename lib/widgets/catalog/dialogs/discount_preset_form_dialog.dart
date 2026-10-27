import '../../../core/catalog/discount_rules.dart';
import '../../../core/catalog/menu_category.dart';
import '../../../core/orders/deal.dart';
import '../../../core/orders/dining_type.dart';
import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Modal dialog for creating or updating a Pre-Approved Discount Preset.
class DiscountPresetFormDialog extends StatefulWidget {
  const DiscountPresetFormDialog({
    super.key,
    this.preset,
    this.categories = const [], this.deals = const [], this.cashiers = const [],
    required this.onSave,
  });

  final DiscountPreset? preset;
  final List<MenuCategory> categories;
  final List<Deal> deals;
  final List<Map<String, Object?>> cashiers;
  final Future<void> Function({
    required String name,
    required DiscountType type,
    required double value,
    required bool isActive,
    required DiscountRules rules,
  }) onSave;

  @override
  State<DiscountPresetFormDialog> createState() => _DiscountPresetFormDialogState();
}

class _DiscountPresetFormDialogState extends State<DiscountPresetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late DiscountType _selectedType;
  late bool _isActive;
  bool _isSaving = false;
  final _advanced = <String, TextEditingController>{};
  late Set<String> _modes;
  late Set<int> _categories, _deals, _cashiers;
  String? _rulesError;


  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset?.name ?? '');
    _valueController = TextEditingController(
      text: widget.preset != null ? widget.preset!.value.toString() : '10.0',
    );
    _selectedType = widget.preset?.type ?? DiscountType.percentage;
    _isActive = widget.preset?.isActive ?? true;
    final rules = widget.preset?.rules ?? const DiscountRules();
    final values = <String, String>{
      'Minimum spend (Rs)': (rules.minimumSpendPaisa / 100).toStringAsFixed(2),
      'Maximum discount (Rs)': rules.maximumDiscountPaisa == null ? '' : (rules.maximumDiscountPaisa! / 100).toStringAsFixed(2),
      'Effective from': rules.startsAt?.toIso8601String() ?? '', 'Effective until': rules.endsAt?.toIso8601String() ?? '',
      'Daily start time': _time(rules.startMinute), 'Daily end time': _time(rules.endMinute),
      'Uses per Business Day': rules.dailyLimit?.toString() ?? '',
    };
    for (final entry in values.entries) { _advanced[entry.key] = TextEditingController(text: entry.value); }
    _modes = rules.diningModes.toSet(); _categories = rules.categoryIds.toSet();
    _deals = rules.dealIds.toSet(); _cashiers = rules.cashierIds.toSet();
  }

  @override
  void dispose() {
    for (final field in _advanced.values) { field.dispose(); }
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isSaving = true; _rulesError = null; });
    try {
      final name = _nameController.text.trim();
      final value = double.tryParse(_valueController.text.trim()) ?? 0.0;

      await widget.onSave(
        name: name,
        type: _selectedType,
        value: value,
        isActive: _isActive,
        rules: _readRules(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _rulesError = '$e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _time(int? minute) => minute == null ? '' : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  DiscountRules _readRules() {
    String read(String key) => _advanced[key]!.text.trim();
    int? money(String key) {
      if (read(key).isEmpty) return null;
      final value = double.tryParse(read(key));
      if (value == null || !value.isFinite || value < 0 || (value * 100 - (value * 100).round()).abs() > 0.000001) throw ArgumentError('$key requires a valid amount with at most two decimals.');
      return (value * 100).round();
    }
    DateTime? date(String key) {
      if (read(key).isEmpty) return null;
      final result = DateTime.tryParse(read(key));
      if (result == null) throw ArgumentError('Enter a valid $key date and time.');
      return result;
    }
    int? minute(String key) {
      if (read(key).isEmpty) return null;
      final parts = read(key).split(':');
      if (parts.length != 2) throw ArgumentError('Use HH:MM for $key.');
      final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) throw ArgumentError('Use a valid 24-hour time.');
      return h * 60 + m;
    }
    final limit = read('Uses per Business Day');
    if (limit.isNotEmpty && int.tryParse(limit) == null) throw ArgumentError('Usage limit must be a whole number.');
    final rules = DiscountRules(minimumSpendPaisa: money('Minimum spend (Rs)') ?? 0,
      maximumDiscountPaisa: money('Maximum discount (Rs)'), startsAt: date('Effective from'), endsAt: date('Effective until'),
      startMinute: minute('Daily start time'), endMinute: minute('Daily end time'), dailyLimit: limit.isEmpty ? null : int.parse(limit),
      diningModes: _modes.toList(), categoryIds: _categories.toList(), dealIds: _deals.toList(), cashierIds: _cashiers.toList());
    rules.validate();
    return rules;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.preset != null;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Text(isEditing ? 'Edit Discount Preset' : 'Add Discount Preset', style: WarmCounterTypography.pageHeading),
      content: SizedBox(
        width: 600,
        height: 470,
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                key: const ValueKey('discount_name_field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Discount Name',
                  hintText: 'e.g. Staff Meal 20%, Owner Courtesy 100%, Promo Rs 100',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter discount name';
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              DropdownButtonFormField<DiscountType>(
                key: const ValueKey('discount_type_dropdown'),
                initialValue: _selectedType,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Discount Calculation Type'),
                items: DiscountType.values.map((t) {
                  return DropdownMenuItem<DiscountType>(
                    value: t,
                    child: Text(t.displayName),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedType = val);
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              TextFormField(
                key: const ValueKey('discount_value_field'),
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _selectedType == DiscountType.percentage ? 'Percentage Value (%)' : 'Flat Amount (Rs)',
                  suffixText: _selectedType == DiscountType.percentage ? '%' : 'Rs',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter discount value';
                  final num = double.tryParse(val.trim());
                  if (num == null || !num.isFinite || num <= 0) return 'Must be a positive value';
                  if (_selectedType == DiscountType.percentage && num > 100) {
                    return 'Percentage cannot exceed 100%';
                  }
                  return null;
                },
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              const Text('Advanced eligibility · one preset per order'),
              if (_rulesError != null) Text(_rulesError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              for (final entry in _advanced.entries) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: TextFormField(
                controller: entry.value, decoration: InputDecoration(labelText: entry.key,
                  hintText: entry.key.startsWith('Effective') ? 'YYYY-MM-DD HH:MM (optional)'
                    : entry.key.startsWith('Daily') ? 'HH:MM (optional)' : 'Optional'),
              )),
              const Text('Allowed dining modes (empty = all)'),
              Wrap(spacing: 6, children: DiningType.values.map((mode) => FilterChip(label: Text(mode.displayName),
                selected: _modes.contains(mode.code), onSelected: (selected) => setState(() { selected ? _modes.add(mode.code) : _modes.remove(mode.code); }))).toList()),
              const Text('Eligible categories and deals (empty = all lines)'),
              Wrap(spacing: 6, children: [
                for (final category in widget.categories) FilterChip(label: Text(category.name), selected: _categories.contains(category.id),
                  onSelected: (selected) => setState(() { selected ? _categories.add(category.id) : _categories.remove(category.id); })),
                for (final deal in widget.deals) FilterChip(label: Text('Deal: ${deal.name}'), selected: _deals.contains(deal.id),
                  onSelected: (selected) => setState(() { selected ? _deals.add(deal.id) : _deals.remove(deal.id); })),
              ]),
              const Text('Eligible cashiers (empty = all cashiers)'),
              Wrap(spacing: 6, children: [for (final cashier in widget.cashiers) FilterChip(label: Text(cashier['name'] as String),
                selected: _cashiers.contains(cashier['id']), onSelected: (selected) => setState(() {
                  selected ? _cashiers.add(cashier['id'] as int) : _cashiers.remove(cashier['id']);
                }))]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active for Cashiers'),
                subtitle: const Text('Enables 1-tap selection on counter register without supervisor PIN'),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const ValueKey('save_discount_button'),
          onPressed: _isSaving ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightPrimaryAction,
            foregroundColor: WarmCounterColors.lightTextOnPrimary,
          ),
          child: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(isEditing ? 'Save Changes' : 'Create Preset'),
        ),
      ],
    );
  }
}
