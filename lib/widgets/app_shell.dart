import 'package:flutter/material.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/hardware/reprint_tray_controller.dart';
import '../core/auth/auth_service.dart';
import '../core/procurement/procurement_and_wastage_controller.dart';
import '../core/khata/vendor_khata_controller.dart';
import 'app_header.dart';
import 'app_sidebar.dart';
import 'catalog/supervisor_catalog_workspace.dart';
import 'khata/vendor_khata_workspace.dart';
import 'pin_lock_screen.dart';
import 'procurement/kitchen_wastage_workspace.dart';
import 'procurement/quick_mandi_purchase_workspace.dart';
import 'shifts/register_shift_workspace.dart';

import '../core/orders/token_queue_controller.dart';
import 'supervisor/supervisor_portal_workspace.dart';
import 'supervisor/token_queue_tray.dart';
import 'onboarding/onboarding_wizard.dart';
import '../core/delivery/rider_trip_controller.dart';
import 'delivery/rider_trip_dispatch_workspace.dart';

/// Top-level desktop application shell coordinating authentication gating,
/// active workspace presentation, and header state.
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.onAuthenticatePin,
    this.shiftController,
    this.catalogController,
    this.orderController,
    this.reprintTrayController,
    this.procurementController,
    this.vendorKhataController,
    this.authService,
    this.tokenQueueController,
    this.riderTripController,
    this.child,
  });

  final SessionState session;
  final Future<Staff?> Function(String pin) onAuthenticatePin;
  final ShiftAndCashController? shiftController;
  final CatalogAndRecipeController? catalogController;
  final OrderAndCheckoutController? orderController;
  final ReprintTrayController? reprintTrayController;
  final ProcurementAndWastageController? procurementController;
  final VendorKhataController? vendorKhataController;
  final AuthService? authService;
  final TokenQueueController? tokenQueueController;
  final RiderTripController? riderTripController;
  final Widget? child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppWorkspaceTab _selectedWorkspace = AppWorkspaceTab.register;
  bool _isOnboardingRequired = false;
  bool _checkingOnboarding = false;
  bool _onboardingCheckFailed = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    if (widget.authService != null) {
      setState(() {
        _checkingOnboarding = true;
        _onboardingCheckFailed = false;
      });
      try {
        final required = await widget.authService!.isOnboardingRequired();
        if (mounted) {
          setState(() {
            _isOnboardingRequired = required;
            _checkingOnboarding = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _checkingOnboarding = false;
            _onboardingCheckFailed = true;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingOnboarding || _onboardingCheckFailed) {
      return Scaffold(body: Center(
        child: _checkingOnboarding
            ? const CircularProgressIndicator()
            : ElevatedButton(onPressed: _checkOnboarding, child: const Text('Unable to check setup. Retry')),
      ));
    }
    if (_isOnboardingRequired &&
        widget.authService != null &&
        widget.shiftController != null &&
        widget.catalogController != null) {
      return Scaffold(
        backgroundColor: WarmCounterColors.lightPageBackground,
        body: OnboardingWizard(
          key: const ValueKey('onboarding_wizard'),
          authService: widget.authService!,
          shiftController: widget.shiftController!,
          catalogController: widget.catalogController!,
          onCompleted: (cashierStaff) {
            setState(() {
              _isOnboardingRequired = false;
              _selectedWorkspace = AppWorkspaceTab.register;
            });
            widget.session.lock();
          },
        ),
      );
    }

    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final staff = widget.session.currentStaff;

        if (staff == null) {
          return Scaffold(
            backgroundColor: WarmCounterColors.lightPageBackground,
            appBar: const PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: AppHeader(
                activeStaff: null,
                onLock: null,
              ),
            ),
            body: PinLockScreen(
              key: const ValueKey('pin_lock_screen'),
              maxPinLength: 8,
              subtitle: 'Enter your 4–8 digit PIN, then tap Unlock',
              onPinSubmitted: (pin) async {
                final authenticated = await widget.onAuthenticatePin(pin);
                if (authenticated != null) {
                  widget.session.login(authenticated);
                  return true;
                }
                return false;
              },
            ),
          );
        }

        return Scaffold(
          backgroundColor: WarmCounterColors.lightPageBackground,
          body: LayoutBuilder(builder: (context, constraints) {
            return Row(children: [
              AppSidebar(
                staff: staff,
                selected: _selectedWorkspace,
                compact: constraints.maxWidth < 1180,
                onSelected: (tab) => setState(() => _selectedWorkspace = tab),
              ),
              Expanded(child: Column(children: [
                AppHeader(
                  activeStaff: staff,
                  onLock: () => widget.session.lock(),
                  selectedWorkspace: _selectedWorkspace,
                  showBrand: false,
                  reprintTrayController: widget.reprintTrayController,
                  orderController: widget.orderController,
                  authService: widget.authService,
                ),
                Expanded(child: widget.child ?? _buildWorkspaceBody(context, staff)),
              ])),
            ]);
          }),
        );
      },
    );
  }

  Widget _buildWorkspaceBody(BuildContext context, Staff staff) {
    if (_selectedWorkspace == AppWorkspaceTab.catalog && widget.catalogController != null) {
      return SupervisorCatalogWorkspace(
        controller: widget.catalogController!,
        orderController: widget.orderController,
        procurementController: widget.procurementController,
      );
    }

    if (_selectedWorkspace == AppWorkspaceTab.khata && widget.vendorKhataController != null) {
      return VendorKhataWorkspace(
        controller: widget.vendorKhataController!,
        shiftController: widget.shiftController,
        catalogController: widget.catalogController,
        currentStaff: staff,
      );
    }

    if (_selectedWorkspace == AppWorkspaceTab.mandi) {
      return QuickMandiPurchaseWorkspace(
        controller: widget.procurementController,
      );
    }

    if (_selectedWorkspace == AppWorkspaceTab.wastage) {
      return KitchenWastageWorkspace(
        controller: widget.procurementController,
      );
    }

    if (_selectedWorkspace == AppWorkspaceTab.supervisor && widget.authService != null) {
      return SupervisorPortalWorkspace(
        authService: widget.authService!,
        shiftController: widget.shiftController,
        orderController: widget.orderController,
        tokenQueueController: widget.tokenQueueController,
        reprintTrayController: widget.reprintTrayController,
        currentStaff: staff,
      );
    }

    if (_selectedWorkspace == AppWorkspaceTab.riderTrips) {
      final tripCtrl = widget.riderTripController ??
          (widget.orderController != null
              ? RiderTripController(database: widget.orderController!.database)
              : null);
      if (tripCtrl != null) {
        return RiderTripDispatchWorkspace(
          controller: tripCtrl,
          currentStaff: staff,
          shiftController: widget.shiftController,
        );
      }
    }

    if (_selectedWorkspace == AppWorkspaceTab.tokenQueue && widget.tokenQueueController != null) {
      return TokenQueueTray(
        controller: widget.tokenQueueController!,
      );
    }

    if (widget.shiftController != null) {
      return RegisterShiftWorkspace(
        controller: widget.shiftController!,
        currentStaff: staff,
        orderController: widget.orderController,
        catalogController: widget.catalogController,
        reprintTrayController: widget.reprintTrayController,
        authService: widget.authService,
        onLock: () => widget.session.lock(),
      );
    }

    return _buildDefaultWorkspace(context, staff);
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
