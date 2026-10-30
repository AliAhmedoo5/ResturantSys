import 'package:flutter/material.dart';
import '../../core/analytics/analytics_models.dart';

/// Controlled stable-ID selectors: options come from the authorized snapshot,
/// never from private customer information or a second database read.
class AnalyticsDomainFilters extends StatelessWidget {
  const AnalyticsDomainFilters({super.key, required this.query, required this.options, required this.onChanged});
  final AnalyticsQuery query;
  final List<AnalyticsFilterOption> options;
  final ValueChanged<AnalyticsQuery> onChanged;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Domain filters • inspect each report’s scope notes'),
    const SizedBox(height: 8),
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final dimension in AnalyticsDimension.values) _picker(dimension),
      SizedBox(width: 240, child: DropdownButtonFormField<String>(
        key: ValueKey('analytics_funding_${query.fundingStream}'), initialValue: query.fundingStream,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Funding stream (money flow only)', border: OutlineInputBorder(), isDense: true),
        items: [const DropdownMenuItem<String>(child: Text('All streams')),
          for (final source in ['DRAWER','BANK','OWNER','RIDER_HELD','EXTERNAL_UNKNOWN'])
            DropdownMenuItem(value: source, child: Text(source))],
        onChanged: (value) => onChanged(query.copyWith(fundingStream: value)),
      )),
      TextButton.icon(key: const ValueKey('analytics_reset_domains'),
        onPressed: () => onChanged(query.copyWith(domainFilters: {}, fundingStream: null)),
        icon: const Icon(Icons.filter_alt_off_outlined), label: const Text('Reset domain filters')),
    ]),
    if (query.domainFilters.isNotEmpty) Wrap(spacing: 8, children: [
      for (final entry in query.domainFilters.entries) InputChip(
        label: Text('${entry.key.label}: ${options.where((o) => o.dimension == entry.key && o.id == entry.value).firstOrNull?.label ?? 'Unknown / archived #${entry.value}'}'),
        onDeleted: () => onChanged(query.copyWith(domainFilters: {...query.domainFilters}..remove(entry.key)))),
    ]),
    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text(
      'Stock category: unavailable (no stored category evidence). Menu category and staff department use current classification. '
      'Department does not allocate historical payroll. Supplier acquisition excludes Mandi records without a supplier link. '
      'Known/guest segments describe phone identity coverage; lifetime loyalty remains unavailable. '
      'Whole drawers and unrelated current balances retain their labeled scope.',
      style: TextStyle(fontSize: 12))),
  ]);

  Widget _picker(AnalyticsDimension dimension) {
    final selected = query.domainFilters[dimension];
    final choices = <String, String>{for (final option in options.where((o) => o.dimension == dimension)) option.id: option.label};
    if (selected != null) choices.putIfAbsent(selected, () => 'Unknown / archived');
    return SizedBox(width: 240, child: DropdownButtonFormField<String>(
      key: ValueKey('analytics_domain_${dimension.name}_$selected'), initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(labelText: dimension.label, border: const OutlineInputBorder(), isDense: true),
      items: [const DropdownMenuItem<String>(child: Text('All • clear selection')),
        for (final choice in choices.entries) DropdownMenuItem(value: choice.key,
          child: Text('${choice.value} [${choice.key}]', maxLines: 1, overflow: TextOverflow.ellipsis))],
      onChanged: (value) {
        final filters = {...query.domainFilters};
        if (value == null) { filters.remove(dimension); } else { filters[dimension] = value; }
        onChanged(query.copyWith(domainFilters: filters));
      },
    ));
  }
}
