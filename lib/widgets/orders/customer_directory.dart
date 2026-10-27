import 'package:flutter/material.dart';
import '../../core/orders/customer_controller.dart';

class CustomerSelection {
  const CustomerSelection(this.customer, {this.repeatOrderId});
  final Customer customer;
  final int? repeatOrderId;
}

/// Shared directory: Manager maintains identities; Cashier explicitly selects or repeats.
class CustomerDirectory extends StatefulWidget {
  const CustomerDirectory({super.key, required this.controller, required this.staffId, this.manager = false});
  final CustomerController controller;
  final int staffId;
  final bool manager;
  @override
  State<CustomerDirectory> createState() => _CustomerDirectoryState();
}

class _CustomerDirectoryState extends State<CustomerDirectory> {
  final _search = TextEditingController();
  List<Customer> _customers = [];
  Customer? _selected;
  List<Map<String, Object?>> _history = [];
  bool _busy = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final rows = await widget.controller.search(_search.text);
      if (mounted && generation == _generation) setState(() => _customers = rows);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }
  Future<void> _select(Customer customer) async {
    setState(() { _selected = customer; _history = []; _error = null; });
    try {
      final history = await widget.controller.history(customer.id);
      if (mounted && _selected?.id == customer.id) setState(() => _history = history);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }
  Future<void> _edit([Customer? customer]) async {
    final name = TextEditingController(text: customer?.name ?? '');
    final phone = TextEditingController(text: customer?.phone ?? '');
    final notes = TextEditingController(text: customer?.notes ?? '');
    String? error;
    Customer? savedCustomer;
    bool saving = false;
    if (!mounted) return;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text(customer == null ? 'Add Customer' : 'Edit Customer'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
        TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes')),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]))), actions: [TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: saving ? null : () async {
          update(() => saving = true);
          try {
            savedCustomer = await widget.controller.save(staffId: widget.staffId, id: customer?.id,
              name: name.text, phone: phone.text, notes: notes.text);
            if (context.mounted) Navigator.pop(context);
          } catch (e) { if (context.mounted) update(() { saving = false; error = e.toString(); }); }
        }, child: const Text('Save'))])));
    name.dispose(); phone.dispose(); notes.dispose();
    await _load();
    if (savedCustomer != null && mounted) await _select(savedCustomer!);
  }
  Future<void> _merge() async {
    final source = _selected;
    if (source == null) return;
    Customer? target;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: Text('Merge ${source.name} into…'),
      content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('The selected target remains in the directory. Both order histories and phone associations are retained. This action is audited.'),
        DropdownButtonFormField<int>(decoration: const InputDecoration(labelText: 'Keep customer'),
          items: _customers.where((c) => c.id != source.id).map((c) => DropdownMenuItem(value: c.id, child: Text('${c.name} · ${c.phone}'))).toList(),
          onChanged: (id) => update(() => target = _customers.singleWhere((c) => c.id == id))),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason'), onChanged: (_) => update(() {})),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: target == null || reason.text.trim().isEmpty ? null : () => Navigator.pop(context, true), child: const Text('Confirm merge'))])));
    if (confirmed == true && target != null) {
      await _run(() async {
        await widget.controller.merge(managerId: widget.staffId, sourceId: source.id, targetId: target!.id, reason: reason.text);
        if (mounted) setState(() { _selected = null; _history = []; });
        await _load();
      });
    }
    reason.dispose();
  }
  Future<void> _run(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try { await action(); } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    Row(children: [Expanded(child: TextField(controller: _search, onChanged: (_) => _load(),
      decoration: const InputDecoration(labelText: 'Search customers by name or phone', prefixIcon: Icon(Icons.search)))),
      const SizedBox(width: 12), FilledButton.icon(onPressed: _busy ? null : () => _edit(), icon: const Icon(Icons.person_add_outlined), label: const Text('Add Customer'))]),
    if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    if (_busy) const LinearProgressIndicator(),
    const SizedBox(height: 12),
    Expanded(child: Row(children: [
      Expanded(child: _customers.isEmpty ? const Center(child: Text('No customers found. Add a customer to get started.')) : ListView(children: [
        for (final customer in _customers) ListTile(selected: _selected?.id == customer.id,
          title: Text(customer.name), subtitle: Text(customer.phone), onTap: _busy ? null : () => _select(customer)),
      ])),
      const VerticalDivider(),
      Expanded(child: _selected == null ? const Center(child: Text('Select a customer to view their order history.')) : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(_selected!.name, style: Theme.of(context).textTheme.titleLarge),
        Text('${_selected!.phone}\n${_selected!.notes}'),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: _busy ? null : () => _edit(_selected), child: const Text('Edit')),
          if (widget.manager) TextButton(onPressed: _busy ? null : _merge, child: const Text('Merge duplicate')),
          if (!widget.manager) FilledButton(onPressed: _busy ? null : () => Navigator.pop(context, CustomerSelection(_selected!)), child: const Text('Use customer')),
        ]),
        const Divider(),
        Expanded(child: _history.isEmpty ? const Center(child: Text('No previous orders.')) : ListView(children: [
          for (final order in _history) ListTile(
            title: Text('${order['created_at']} · Rs ${(order['grand_total'] as num).toStringAsFixed(2)}'),
            subtitle: Text('${order['dining_type']} · ${order['payment_status']} · ${order['token_status']}'),
            onTap: () => _showOrder(order['id'] as int),
            trailing: widget.manager ? null : TextButton(onPressed: _busy ? null : () => Navigator.pop(context,
              CustomerSelection(_selected!, repeatOrderId: order['id'] as int)), child: const Text('Repeat'))),
        ])),
      ])),
    ])),
  ]));

  Future<void> _showOrder(int id) async {
    await _run(() async {
      final lines = await widget.controller.database.query('order_items', where: 'order_id = ?', whereArgs: [id]);
      final payments = await widget.controller.database.query('order_payments', where: 'order_id = ?', whereArgs: [id]);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text('Order $id'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Text([
          ...lines.map((r) => '${r['quantity']} × ${r['name']} · Rs ${r['total_price']}'),
          'Payments', ...payments.map((r) => '${r['payment_method']}: received ${r['amount_tendered']}, change ${r['change_returned']}'),
        ].join('\n')))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
    });
  }
}
