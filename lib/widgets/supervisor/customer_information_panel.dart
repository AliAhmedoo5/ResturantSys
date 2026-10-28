import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_service.dart';
import '../../core/theme/theme.dart';

/// Operational contact details are transient and separate from analytics exports.
class CustomerInformationPanel extends StatefulWidget {
  const CustomerInformationPanel({super.key, required this.load, required this.snapshotToken});
  final Future<List<CustomerReportProfile>> Function() load;
  final Object snapshotToken;

  @override
  State<CustomerInformationPanel> createState() => _CustomerInformationPanelState();
}

class _CustomerInformationPanelState extends State<CustomerInformationPanel> {
  final _search = TextEditingController();
  List<CustomerReportProfile> _profiles = [];
  String? _selectedPhone;
  String? _error;
  bool _busy = true;
  int _generation = 0;
  int _historyPage = 0;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void didUpdateWidget(covariant CustomerInformationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshotToken, widget.snapshotToken)) _load();
  }

  @override
  void dispose() { _generation++; _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _busy = true; _error = null; _profiles = []; _selectedPhone = null; _historyPage = 0; });
    try {
      final profiles = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _profiles = profiles;
        _selectedPhone = profiles.firstOrNull?.phone;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Unable to load customer information. Check your Manager session and retry.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  bool _matches(CustomerReportProfile person) {
    final text = _search.text.trim().toLowerCase();
    if (text.isEmpty || person.name.toLowerCase().contains(text)) return true;
    var digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      if (digits.startsWith('0092')) digits = '0${digits.substring(4)}';
      if (digits.startsWith('92')) digits = '0${digits.substring(2)}';
    }
    return digits.isNotEmpty && (person.phone.contains(digits) || person.primaryPhone.contains(digits));
  }

  @override
  Widget build(BuildContext context) {
    final matches = _profiles.where(_matches).toList();
    final selected = matches.where((p) => p.phone == _selectedPhone).firstOrNull ?? matches.firstOrNull;
    return Padding(padding: const EdgeInsets.only(top: 18),
      child: Material(color: StreetFoodMafiaColors.darkNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: StreetFoodMafiaColors.border)),
        child: Padding(padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.people_outline, color: StreetFoodMafiaColors.cartelYellow), SizedBox(width: 10),
              Expanded(child: Text('Customer information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            const Text('Contact details and eligible order history for the selected period and filters. '
              'Phone-based records can represent shared numbers.',
              style: TextStyle(fontSize: 12, height: 1.5, color: StreetFoodMafiaColors.secondaryText)),
            if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Wrap(
              spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(_error!, style: const TextStyle(color: StreetFoodMafiaColors.statusCanceled)),
                TextButton(onPressed: _load, child: const Text('Retry customer information')),
              ])),
            if (!_busy && _error == null) ...[
              const SizedBox(height: 14),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 800;
                final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(key: const ValueKey('customer_information_search'), controller: _search,
                    onChanged: (_) => setState(() { _selectedPhone = null; _historyPage = 0; }),
                    decoration: const InputDecoration(labelText: 'Search by customer name or phone',
                      prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true)),
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('${matches.length} of ${_profiles.length} phone records',
                      style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText))),
                  Expanded(child: matches.isEmpty ? const Center(child: Text('No customers match this selection.'))
                    : ListView.builder(itemCount: matches.length, itemBuilder: (context, index) {
                      final person = matches[index];
                      return ListTile(key: ValueKey('customer_profile_${person.phone}'),
                        selected: selected?.phone == person.phone,
                        selectedTileColor: StreetFoodMafiaColors.activeNavHighlight,
                        title: Text(person.name), subtitle: Text(person.phone),
                        trailing: Text('${person.orders.length} orders', style: const TextStyle(fontSize: 11)),
                        onTap: () => setState(() { _selectedPhone = person.phone; _historyPage = 0; }));
                    })),
                ]);
                final detail = selected == null ? const Center(child: Text('Select a customer to view recorded details.'))
                  : _details(selected);
                return SizedBox(height: wide ? 480 : 740, child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 2, child: list), const VerticalDivider(width: 28),
                      Expanded(flex: 3, child: detail),
                    ])
                  : Column(children: [Expanded(flex: 2, child: list), const Divider(height: 24),
                      Expanded(flex: 3, child: detail)]));
              }),
            ],
          ]))));
  }

  Widget _details(CustomerReportProfile person) {
    final start = _historyPage * 10;
    final end = (start + 10).clamp(0, person.orders.length);
    final addresses = person.addresses;
    return SingleChildScrollView(key: ValueKey('customer_details_${person.phone}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(person.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        _field('Recorded phone', person.phone),
        if (person.primaryPhone.isNotEmpty && person.primaryPhone != person.phone)
          _field('Current profile phone', person.primaryPhone),
        _field('Saved customer notes', person.notes.isEmpty ? 'No notes recorded' : person.notes),
        _field('Recorded order value', _money(person.recordedValuePaisa)),
        _field('Orders in this selection', '${person.orders.length}'),
        const Divider(height: 24),
        const Text('Recorded delivery addresses', style: TextStyle(fontWeight: FontWeight.w700)),
        if (addresses.isEmpty) const Padding(padding: EdgeInsets.only(top: 6),
          child: Text('No delivery address recorded in this selection.')),
        for (final address in addresses.take(3)) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(address)),
        if (addresses.length > 3) Text('${addresses.length} distinct addresses; see individual orders below.'),
        const Divider(height: 24),
        const Text('Order history · selected period and filters', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final order in person.orders.skip(start).take(10)) ExpansionTile(
          key: ValueKey('customer_history_order_${order.id}'), tilePadding: EdgeInsets.zero,
          title: Text('Order #${order.id} · Token #${order.token} · ${_money(order.totalPaisa)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text('${_date(order.createdAt)} · ${order.diningType.replaceAll('_', ' ')} · ${order.paymentStatus.replaceAll('_', ' ')}',
            style: const TextStyle(fontSize: 11)),
          children: [Align(alignment: Alignment.centerLeft, child: Padding(
            padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _field('Name recorded on order', order.recordedName.isEmpty ? 'Not recorded' : order.recordedName),
              _field('Delivery area', order.area.isEmpty ? 'Not recorded' : order.area),
              _field('Delivery address', order.address.isEmpty ? 'Not recorded' : order.address),
              for (final item in order.items) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item)),
            ])))],
        ),
        if (person.orders.length > 10) Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${start + 1}–$end of ${person.orders.length} orders'),
          IconButton(tooltip: 'Previous customer orders', onPressed: _historyPage == 0 ? null : () => setState(() => _historyPage--),
            icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: 'Next customer orders', onPressed: end >= person.orders.length ? null : () => setState(() => _historyPage++),
            icon: const Icon(Icons.chevron_right)),
        ]),
      ]));
  }

  Widget _field(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText)),
      const SizedBox(height: 3), SelectableText(value, style: const TextStyle(fontSize: 13)),
    ]));

  String _money(int value) => 'PKR ${NumberFormat('#,##0.00').format(value / 100)}';
  String _date(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return 'Date not recorded';
    return DateFormat('dd MMM yyyy, HH:mm').format(date.isUtc ? date.add(const Duration(hours: 5)) : date);
  }
}
