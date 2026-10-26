import 'package:flutter/material.dart';
import '../core/auth/staff.dart';
import '../core/theme/theme.dart';
import 'app_header.dart';

/// Persistent navigation retaining the workspaces' existing capability gates.
class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.staff, required this.selected,
    required this.onSelected, this.compact = false});

  final Staff staff;
  final AppWorkspaceTab selected;
  final ValueChanged<AppWorkspaceTab> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final manager = staff.canAccessSupervisorPortal;
    final tabs = [
      AppWorkspaceTab.register,
      if (manager) AppWorkspaceTab.riderTrips,
      if (manager) ...[AppWorkspaceTab.catalog, AppWorkspaceTab.khata, AppWorkspaceTab.supervisor],
      if (manager) ...[
        AppWorkspaceTab.mandi, AppWorkspaceTab.wastage,
      ],
    ];
    return Material(
      key: const ValueKey('app_sidebar'),
      color: StreetFoodMafiaColors.darkNavy,
      child: Container(
        width: compact ? 72 : 176,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: StreetFoodMafiaColors.border)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: 72,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.storefront_outlined, color: StreetFoodMafiaColors.cartelYellow, size: 28),
              if (!compact) ...[
                const SizedBox(width: 10),
                const Flexible(child: Text('RESTAURANT\nPOS', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13,
                    height: 1.2, fontWeight: FontWeight.w800, letterSpacing: 1,
                    color: StreetFoodMafiaColors.offWhite))),
              ],
            ]),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              children: tabs.map((tab) {
                final active = tab == selected;
                final color = active ? StreetFoodMafiaColors.cartelYellow : StreetFoodMafiaColors.secondaryText;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Tooltip(
                    message: tab.label,
                    child: Semantics(
                      selected: active,
                      child: Ink(
                        decoration: BoxDecoration(
                          color: active ? StreetFoodMafiaColors.activeNavHighlight : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: active ? StreetFoodMafiaColors.border : Colors.transparent),
                        ),
                        child: InkWell(
                          key: ValueKey('workspace_tab_${tab.name}'),
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => onSelected(tab),
                          child: SizedBox(
                            height: 48,
                            child: Row(mainAxisAlignment: compact ? MainAxisAlignment.center : MainAxisAlignment.start,
                              children: [
                                if (!compact) const SizedBox(width: 12),
                                Icon(tab.icon, size: 19, color: color),
                                if (!compact) ...[
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(tab.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: color,
                                      fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.offline_bolt_outlined, size: 16, color: StreetFoodMafiaColors.cartelYellow),
              if (!compact) ...[
                const SizedBox(width: 8),
                Flexible(child: Text('OFFLINE POS', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: WarmCounterTypography.caption.copyWith(letterSpacing: 1))),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
