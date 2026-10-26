import 'package:flutter/material.dart';

import '../../core/analytics/analytics_service.dart';
import '../../core/auth/auth_service.dart';
import '../../core/theme/theme.dart';
import 'analytics_export_actions.dart';
import 'manager_analytics_workspace.dart';

/// Shared entry point for the sidebar and the Manager portal.
/// Keeps the service identity stable while the parent shell rebuilds.
class ManagerDashboardWorkspace extends StatefulWidget {
  const ManagerDashboardWorkspace({super.key, this.authService});

  final AuthService? authService;

  @override
  State<ManagerDashboardWorkspace> createState() => _ManagerDashboardWorkspaceState();
}

class _ManagerDashboardWorkspaceState extends State<ManagerDashboardWorkspace> {
  AnalyticsService? _service;

  @override
  Widget build(BuildContext context) {
    final auth = widget.authService;
    if (auth == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.insights_rounded, size: 40, color: StreetFoodMafiaColors.secondaryText),
          SizedBox(height: 16),
          Text('Analytics unavailable', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('Analytics unavailable. A Manager session and database are required.',
            textAlign: TextAlign.center, style: TextStyle(color: StreetFoodMafiaColors.secondaryText)),
        ])));
    }
    if (_service?.authService != auth || _service?.database != auth.database) {
      _service = AnalyticsService(database: auth.database, authService: auth);
    }
    return ManagerAnalyticsWorkspace(
      service: _service!,
      session: auth.session,
      exportActionsBuilder: (context, snapshot, family) => AnalyticsExportActions(
        snapshot: snapshot, family: family,
        canExport: () {
          final actor = auth.session.currentStaff;
          return actor != null && actor.isActive && actor.canAccessSupervisorPortal &&
            actor.id == snapshot.generatedByStaffId;
        },
      ),
    );
  }
}
