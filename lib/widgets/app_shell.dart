import 'package:flutter/material.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'app_header.dart';
import 'pin_lock_screen.dart';

/// Top-level desktop application shell coordinating authentication gating,
/// active workspace presentation, and header state.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.onAuthenticatePin,
    this.child,
  });

  final SessionState session;
  final Future<Staff?> Function(String pin) onAuthenticatePin;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final staff = session.currentStaff;

        if (staff == null) {
          return Scaffold(
            backgroundColor: WarmCounterColors.lightPageBackground,
            appBar: const PreferredSize(
              preferredSize: Size.fromHeight(64),
              child: AppHeader(
                activeStaff: null,
                onLock: null,
              ),
            ),
            body: PinLockScreen(
              key: const ValueKey('pin_lock_screen'),
              onPinSubmitted: (pin) async {
                final authenticated = await onAuthenticatePin(pin);
                if (authenticated != null) {
                  session.login(authenticated);
                  return true;
                }
                return false;
              },
            ),
          );
        }

        return Scaffold(
          backgroundColor: WarmCounterColors.lightPageBackground,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: AppHeader(
              activeStaff: staff,
              onLock: () => session.lock(),
            ),
          ),
          body: child ?? _buildDefaultWorkspace(context, staff),
        );
      },
    );
  }

  Widget _buildDefaultWorkspace(BuildContext context, Staff staff) {
    final department = staff.departmentName ?? 'General Department';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(WarmCounterSpacing.space32),
        decoration: BoxDecoration(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: const BoxDecoration(
                    color: WarmCounterColors.lightActiveNavHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline_rounded,
                    color: WarmCounterColors.lightPrimaryAction,
                    size: 32,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Register Unlocked',
                        style: WarmCounterTypography.pageHeading.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Welcome back, ${staff.name}',
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(
              height: WarmCounterSpacing.space32,
              color: WarmCounterColors.lightBorder,
            ),
            Text(
              'Session Capabilities:',
              style: WarmCounterTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space12),
            _buildCapabilityRow('Department', department),
            _buildCapabilityRow('Role', staff.role.displayName),
            _buildCapabilityRow('Register Billing Access', staff.canAccessRegister ? 'Granted' : 'Restricted'),
            _buildCapabilityRow('Kitchen Slip Management', staff.canAccessKitchen ? 'Granted' : 'Restricted'),
            _buildCapabilityRow('Supervisor Portal & Voids', staff.canAccessSupervisorPortal ? 'Authorized' : 'Restricted'),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilityRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WarmCounterSpacing.space4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: WarmCounterTypography.bodyMedium.copyWith(
                color: WarmCounterColors.lightSecondaryText,
              ),
            ),
          ),
          const SizedBox(width: WarmCounterSpacing.space8),
          Text(
            value,
            style: WarmCounterTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
