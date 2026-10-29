import '../../core/theme/warm_counter_typography.dart';
import 'package:flutter/material.dart';
import '../../core/delivery/delivery_controller.dart';

class DeliveryDetailsDialog extends StatefulWidget {
  const DeliveryDetailsDialog({super.key, required this.controller, required this.foodTotalPaisa, this.initial,
    this.customerPhone, this.customerName});
  final DeliveryController controller;
  final int foodTotalPaisa;
  final DeliveryDetails? initial;
  final String? customerPhone, customerName;
  @override
  State<DeliveryDetailsDialog> createState() => _DeliveryDetailsDialogState();
}
class _DeliveryDetailsDialogState extends State<DeliveryDetailsDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _phone, _name, _address, _landmark, _notes;
  List<DeliveryArea> _areas = [];
  List<CustomerAddress> _matches = [];
  int? _areaId;
  int _query = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState(); final initial = widget.initial;
    _phone = TextEditingController(text: initial?.phone ?? widget.customerPhone); _name = TextEditingController(text: initial?.customerName ?? widget.customerName);
    _address = TextEditingController(text: initial?.fullAddress); _landmark = TextEditingController(text: initial?.landmark);
    _notes = TextEditingController(text: initial?.notes); _areaId = initial?.areaId;
    _load();
  }
  @override
  void dispose() { for (final c in [_phone, _name, _address, _landmark, _notes]) { c.dispose(); } super.dispose(); }
  Future<void> _load() async {
    try {
      final areas = await widget.controller.getAreas(activeOnly: true);
      final matches = _phone.text.isEmpty ? <CustomerAddress>[] : await widget.controller.lookupAddresses(_phone.text);
      if (!mounted) return;
      setState(() { _areas = areas; _matches = matches; _loading = false; if (!areas.any((a) => a.id == _areaId)) _areaId = null; });
    } catch (e) { if (mounted) setState(() { _error = '$e'; _loading = false; }); }
  }
  Future<void> _lookup(String phone) async {
    final query = ++_query;
    setState(() { _matches = []; _name.clear(); _address.clear(); _landmark.clear(); _notes.clear(); _areaId = null; _error = null; });
    try {
      final matches = await widget.controller.lookupAddresses(phone);
      if (!mounted || query != _query) return;
      setState(() {
        _matches = matches;
        final exact = matches.where((a) => a.phone == DeliveryController.normalizePhone(phone)).toList();
        if (exact.isNotEmpty) _fill(exact.first, updatePhone: false);
      });
    } catch (e) { if (mounted && query == _query) setState(() => _error = 'Customer lookup failed: $e'); }
  }
  void _fill(CustomerAddress address, {bool updatePhone = true}) {
    if (updatePhone) { _query++; _phone.text = address.phone; }
    _name.text = address.customerName; _address.text = address.fullAddress;
    _landmark.text = address.landmark; _notes.text = address.notes;
    _areaId = _areas.any((a) => a.id == address.areaId) ? address.areaId : null;
  }
  void _continue() {
    if (!_form.currentState!.validate() || _areaId == null) return;
    final area = _areas.firstWhere((a) => a.id == _areaId);
    if (widget.foodTotalPaisa < area.minOrderPaisa) {
      setState(() => _error = 'Minimum food order after discounts: Rs ${(area.minOrderPaisa / 100).toStringAsFixed(2)}'); return;
    }
    Navigator.pop(context, DeliveryDetails(areaId: area.id, quotedFeePaisa: area.deliveryFeePaisa, phone: _phone.text,
      customerName: _name.text, fullAddress: _address.text, landmark: _landmark.text, notes: _notes.text));
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: const Text('Delivery customer details'),
    content: SizedBox(width: 520, child: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(key: const ValueKey('delivery_phone'), controller: _phone, autofocus: true, keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Customer phone', helperText: 'Type to search saved addresses'), onChanged: _lookup,
        validator: (v) => DeliveryController.normalizePhone(v ?? '').length < 7 ? 'Enter a phone number' : null),
      if (_matches.isNotEmpty) SizedBox(height: 100, child: ListView(children: _matches.map((a) => ListTile(dense: true,
        title: Text('${a.customerName} • ${a.phone}'), subtitle: Text(a.fullAddress), onTap: () => setState(() => _fill(a)))).toList())),
      TextFormField(key: const ValueKey('delivery_name'), controller: _name, decoration: const InputDecoration(labelText: 'Customer name')),
      DropdownButtonFormField<int>(mouseCursor: WidgetStateMouseCursor.clickable, key: ValueKey('delivery_area_$_areaId'), initialValue: _areaId, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Active delivery area'), items: _areas.map((a) => DropdownMenuItem(value: a.id,
          child: Text('${a.name} • Rs ${(a.deliveryFeePaisa / 100).toStringAsFixed(2)}', overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: WarmCounterTypography.tabularNumbers))).toList(),
        onChanged: (id) => setState(() => _areaId = id), validator: (v) => v == null ? 'Select an active area' : null),
      if (_areas.isEmpty) const Text('No active delivery areas. Ask a Manager to enable an area, or choose Takeaway / Dine-In.'),
      TextFormField(key: const ValueKey('delivery_address'), controller: _address, decoration: const InputDecoration(labelText: 'Full address'), maxLines: 2,
        validator: (v) => v!.trim().isEmpty ? 'Enter an address' : null),
      TextFormField(controller: _landmark, decoration: const InputDecoration(labelText: 'Landmark')),
      TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Delivery notes')),
      if (_areaId != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Fixed delivery fee: Rs ${(_areas.firstWhere((a) => a.id == _areaId).deliveryFeePaisa / 100).toStringAsFixed(2)} • Food discounts do not apply to delivery.', textAlign: TextAlign.right, style: WarmCounterTypography.tabularNumbers)),
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ])))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to cart')),
      FilledButton(onPressed: _loading || _areas.isEmpty ? null : _continue, child: const Text('Continue to payment'))]);
}

