import 'package:flutter/material.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/staff.dart';
import '../core/hardware/reprint_tray_controller.dart';
import '../core/orders/order_and_checkout_controller.dart';
import '../core/theme/theme.dart';
import 'orders/reprint_tray_dialog.dart';

/// Operational workspaces selectable in the application header.
enum AppWorkspaceTab {
  register('Register', Icons.point_of_sale_rounded),
  catalog('Catalog', Icons.restaurant_menu_rounded),
  mandi('Mandi', Icons.shopping_basket_rounded),
  wastage('Wastage', Icons.delete_outline_rounded);

  const AppWorkspaceTab(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Top application navigation bar displaying system branding, active staff session details,
/// workspace switching tabs for supervisors, and a 1-tap Lock Register button.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    required this.activeStaff,
    required this.onLock,
    this.selectedWorkspace,
    this.onWorkspaceSelected,
    this.reprintTrayController,
    this.orderController,
    this.authService,
    this.title = 'ResturantPOS',
  });

  final Staff? activeStaff;
  final VoidCallback? onLock;
  final AppWorkspaceTab? selectedWorkspace;
  final ValueChanged<AppWorkspaceTab>? onWorkspaceSelected;
  final ReprintTrayController? reprintTrayController;
  final OrderAndCheckoutController? orderController;
  final AuthService? authService;
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: preferredSize.height,
      padding: const EdgeInsets.symmetric(
        horizontal: WarmCounterSpacing.space24,
      ),
      decoration: const BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        border: Border(
          bottom: BorderSide(
            color: WarmCounterColors.lightBorder,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: App Brand & Logo
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: WarmCounterColors.lightPrimaryAction,
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                ),
                child: const Center(
                  child: Icon(
                    Icons.storefront_rounded,
                    color: WarmCounterColors.lightTextOnPrimary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              Text(
                title,
                style: WarmCounterTypography.pageHeading.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: WarmCounterColors.lightPrimaryText,
                ),
              ),
            ],
          ),

          // Middle: Workspace Switcher for Supervisors/Owners/Kitchen
          if (activeStaff != null &&
              (activeStaff!.canAccessSupervisorPortal || activeStaff!.canAccessKitchen) &&
              onWorkspaceSelected != null)
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildWorkspaceTabButton(
                        context,
                        tab: AppWorkspaceTab.register,
                        isSelected: selectedWorkspace == AppWorkspaceTab.register,
                      ),
                      const SizedBox(width: WarmCounterSpacing.space8),
                      _buildWorkspaceTabButton(
                        context,
                        tab: AppWorkspaceTab.catalog,
                        isSelected: selectedWorkspace == AppWorkspaceTab.catalog,
                      ),
                      const SizedBox(width: WarmCounterSpacing.space8),
                      _buildWorkspaceTabButton(
                        context,
                        tab: AppWorkspaceTab.mandi,
                        isSelected: selectedWorkspace == AppWorkspaceTab.mandi,
                      ),
                      const SizedBox(width: WarmCounterSpacing.space8),
                      _buildWorkspaceTabButton(
                        context,
                        tab: AppWorkspaceTab.wastage,
                        isSelected: selectedWorkspace == AppWorkspaceTab.wastage,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Right: Active Session / Locked Status & Actions
          Flexible(
            child: activeStaff != null
                ? _buildActiveStaffBar(context, activeStaff!)
                : _buildLockedStatusBar(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveStaffBar(BuildContext context, Staff staff) {
    final department = staff.departmentName ?? 'General';
    final roleName = staff.role.displayName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Staff Info Pill
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WarmCounterSpacing.space12,
              vertical: WarmCounterSpacing.space8,
            ),
            decoration: BoxDecoration(
              color: WarmCounterColors.lightActiveNavHighlight,
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              border: Border.all(
                color: WarmCounterColors.lightBorder,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle_rounded,
                  size: 22,
                  color: WarmCounterColors.lightPrimaryAction,
                ),
                const SizedBox(width: WarmCounterSpacing.space8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        staff.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: WarmCounterColors.lightPrimaryText,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '$department • $roleName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WarmCounterTypography.secondaryLabel.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: WarmCounterSpacing.space12),

        // Reprint Tray Button with Failure Badge
        if (reprintTrayController != null) ...[
          ListenableBuilder(
            listenable: reprintTrayController!,
            builder: (context, _) {
              final hasFailures = reprintTrayController!.hasFailures;
              final failedCount = reprintTrayController!.failedCount;

              return Padding(
                padding: const EdgeInsets.only(right: WarmCounterSpacing.space12),
                child: OutlinedButton.icon(
                  key: const ValueKey('header_reprint_tray_button'),
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (ctx) => ReprintTrayDialog(
                        controller: reprintTrayController!,
                        currentStaff: staff,
                        orderController: orderController,
                        authService: authService,
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.print_rounded,
                    size: 18,
                    color: hasFailures
                        ? WarmCounterColors.lightDestructiveAction
                        : WarmCounterColors.lightPrimaryText,
                  ),
                  label: Text(
                    hasFailures ? 'Reprint Tray ($failedCount)' : 'Reprint Tray',
                    style: TextStyle(
                      color: hasFailures
                          ? WarmCounterColors.lightDestructiveAction
                          : WarmCounterColors.lightPrimaryText,
                      fontWeight: hasFailures ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: hasFailures ? WarmCounterColors.lightDestructiveHighlight : null,
                    side: BorderSide(
                      color: hasFailures ? WarmCounterColors.lightDestructive : WarmCounterColors.lightBorder,
                    ),
                    minimumSize: const Size(110, WarmCounterSpacing.minTouchTargetSize),
                    shape: const RoundedRectangleBorder(
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                    ),
                  ),
                ),
              );
            },
          ),
        ],

        // 1-Tap Lock Register Button
        OutlinedButton.icon(
          key: const ValueKey('lock_register_button'),
          onPressed: onLock,
          icon: const Icon(Icons.lock_outline_rounded, size: 18),
          label: const Text('Lock Register'),
          style: OutlinedButton.styleFrom(
            foregroundColor: WarmCounterColors.lightPrimaryText,
            minimumSize: const Size(120, WarmCounterSpacing.minTouchTargetSize),
            side: const BorderSide(
              color: WarmCounterColors.lightBorder,
              width: 1.0,
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: WarmCounterSpacing.controlBorderRadius,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLockedStatusBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WarmCounterSpacing.space16,
        vertical: WarmCounterSpacing.space8,
      ),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightPageBackground,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: WarmCounterColors.lightBorder,
          width: 1.0,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_rounded,
            size: 18,
            color: WarmCounterColors.lightSecondaryText,
          ),
          SizedBox(width: WarmCounterSpacing.space8),
          Text(
            'Register Locked',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WarmCounterColors.lightSecondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspaceTabButton(
    BuildContext context, {
    required AppWorkspaceTab tab,
    required bool isSelected,
  }) {
    return InkWell(
      key: ValueKey('workspace_tab_${tab.name}'),
      onTap: () => onWorkspaceSelected?.call(tab),
      borderRadius: WarmCounterSpacing.controlBorderRadius,
      child: Container(
        constraints: WarmCounterSpacing.minTouchTargetConstraints,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? WarmCounterColors.lightActiveNavHighlight
              : Colors.transparent,
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          border: Border.all(
            color: isSelected
                ? WarmCounterColors.lightPrimaryAction
                : WarmCounterColors.lightBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 18,
              color: isSelected
                  ? WarmCounterColors.lightPrimaryAction
                  : WarmCounterColors.lightSecondaryText,
            ),
            const SizedBox(width: WarmCounterSpacing.space8),
            Text(
              tab.label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? WarmCounterColors.lightPrimaryAction
                    : WarmCounterColors.lightPrimaryText,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
