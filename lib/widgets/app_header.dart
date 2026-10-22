import 'package:flutter/material.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/staff.dart';
import '../core/hardware/reprint_tray_controller.dart';
import '../core/orders/order_and_checkout_controller.dart';
import '../core/theme/theme.dart';
import 'orders/reprint_tray_dialog.dart';

/// Operational workspaces selectable in the application header.
enum AppWorkspaceTab {
  register('Register', Icons.point_of_sale_outlined),
  catalog('Catalog', Icons.restaurant_menu_outlined),
  khata('Khata', Icons.menu_book_outlined),
  mandi('Mandi', Icons.shopping_basket_outlined),
  wastage('Wastage', Icons.delete_outline_rounded),
  supervisor('Supervisor', Icons.admin_panel_settings_outlined),
  tokenQueue('Tokens', Icons.confirmation_number_outlined);

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
    this.isTokenTrayEnabled = true,
    this.title = 'ResturantPOS',
  });

  final Staff? activeStaff;
  final VoidCallback? onLock;
  final AppWorkspaceTab? selectedWorkspace;
  final ValueChanged<AppWorkspaceTab>? onWorkspaceSelected;
  final ReprintTrayController? reprintTrayController;
  final OrderAndCheckoutController? orderController;
  final AuthService? authService;
  final bool isTokenTrayEnabled;
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
        color: StreetFoodMafiaColors.darkNavy,
        border: Border(
          bottom: BorderSide(
            color: StreetFoodMafiaColors.border,
            width: 1.0,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: App Brand & Logo (Street-Food / Mafia Branding)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: StreetFoodMafiaColors.darkNavy,
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  border: Border.all(
                    color: StreetFoodMafiaColors.cartelYellow,
                    width: 1.5,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.storefront_outlined,
                    color: StreetFoodMafiaColors.cartelYellow,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              // Dual-Tone Brand Formatting Protocol (Zero-Gap Container)
              if (title == 'ResturantPOS')
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Resturant',
                      style: WarmCounterTypography.pageHeading.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: StreetFoodMafiaColors.offWhite,
                      ),
                    ),
                    Text(
                      'POS',
                      style: WarmCounterTypography.pageHeading.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        color: StreetFoodMafiaColors.cartelYellow,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  title,
                  style: WarmCounterTypography.pageHeading.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: StreetFoodMafiaColors.offWhite,
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
                      if (activeStaff!.canAccessSupervisorPortal) ...[
                        const SizedBox(width: WarmCounterSpacing.space8),
                        _buildWorkspaceTabButton(
                          context,
                          tab: AppWorkspaceTab.catalog,
                          isSelected: selectedWorkspace == AppWorkspaceTab.catalog,
                        ),
                        const SizedBox(width: WarmCounterSpacing.space8),
                        _buildWorkspaceTabButton(
                          context,
                          tab: AppWorkspaceTab.khata,
                          isSelected: selectedWorkspace == AppWorkspaceTab.khata,
                        ),
                        const SizedBox(width: WarmCounterSpacing.space8),
                        _buildWorkspaceTabButton(
                          context,
                          tab: AppWorkspaceTab.supervisor,
                          isSelected: selectedWorkspace == AppWorkspaceTab.supervisor,
                        ),
                      ],
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
                      if (isTokenTrayEnabled) ...[
                        const SizedBox(width: WarmCounterSpacing.space8),
                        _buildWorkspaceTabButton(
                          context,
                          tab: AppWorkspaceTab.tokenQueue,
                          isSelected: selectedWorkspace == AppWorkspaceTab.tokenQueue,
                        ),
                      ],
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
              color: StreetFoodMafiaColors.darkNavy,
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              border: Border.all(
                color: StreetFoodMafiaColors.border,
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.account_circle_outlined,
                  size: 22,
                  color: StreetFoodMafiaColors.cartelYellow,
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
                          color: StreetFoodMafiaColors.offWhite,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        '$department • $roleName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WarmCounterTypography.secondaryLabel.copyWith(
                          color: StreetFoodMafiaColors.secondaryText,
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
                    Icons.print_outlined,
                    size: 18,
                    color: hasFailures
                        ? StreetFoodMafiaColors.statusCanceled
                        : StreetFoodMafiaColors.offWhite,
                  ),
                  label: Text(
                    hasFailures ? 'Reprint Tray ($failedCount)' : 'Reprint Tray',
                    style: TextStyle(
                      color: hasFailures
                          ? StreetFoodMafiaColors.statusCanceled
                          : StreetFoodMafiaColors.offWhite,
                      fontWeight: hasFailures ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: hasFailures ? const Color(0xFF2C1518) : null,
                    side: BorderSide(
                      color: hasFailures ? StreetFoodMafiaColors.statusCanceled : StreetFoodMafiaColors.border,
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
            foregroundColor: StreetFoodMafiaColors.offWhite,
            minimumSize: const Size(120, WarmCounterSpacing.minTouchTargetSize),
            side: const BorderSide(
              color: StreetFoodMafiaColors.border,
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
        color: StreetFoodMafiaColors.darkNavy,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(
          color: StreetFoodMafiaColors.border,
          width: 1.0,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 18,
            color: StreetFoodMafiaColors.secondaryText,
          ),
          SizedBox(width: WarmCounterSpacing.space8),
          Text(
            'Register Locked',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: StreetFoodMafiaColors.secondaryText,
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
              ? StreetFoodMafiaColors.activeNavHighlight
              : Colors.transparent,
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          border: Border.all(
            color: isSelected
                ? StreetFoodMafiaColors.cartelYellow
                : StreetFoodMafiaColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 18,
              color: isSelected
                  ? StreetFoodMafiaColors.cartelYellow
                  : StreetFoodMafiaColors.secondaryText,
            ),
            const SizedBox(width: WarmCounterSpacing.space8),
            Text(
              tab.label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? StreetFoodMafiaColors.cartelYellow
                    : StreetFoodMafiaColors.offWhite,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
