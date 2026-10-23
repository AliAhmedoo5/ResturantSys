import 'package:flutter/material.dart';
import '../core/auth/auth_service.dart';
import '../core/auth/staff.dart';
import '../core/hardware/reprint_tray_controller.dart';
import '../core/orders/order_and_checkout_controller.dart';
import '../core/theme/theme.dart';
import 'orders/reprint_tray_dialog.dart';

enum AppWorkspaceTab {
  register('Register', Icons.point_of_sale_outlined),
  riderTrips('Riders', Icons.two_wheeler_outlined),
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

/// Compact workspace heading; navigation is provided by the desktop sidebar.
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
    this.showBrand = true,
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
  final bool showBrand;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StreetFoodMafiaColors.darkNavy,
      child: Container(
        height: preferredSize.height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: StreetFoodMafiaColors.border)),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final staff = activeStaff;
          return Row(children: [
            if (showBrand) ...[
              const Icon(Icons.storefront_outlined, color: StreetFoodMafiaColors.cartelYellow, size: 24),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                showBrand ? title : selectedWorkspace?.label ?? 'Register',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
              ),
            ),
            if (staff == null)
              const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: StreetFoodMafiaColors.secondaryText),
                SizedBox(width: 8),
                Text('Register Locked', style: TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 12)),
              ])
            else ...[
              if (!compact)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(staff.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                      Text('${staff.departmentName ?? 'General'} • ${staff.role.displayName}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: WarmCounterTypography.caption.copyWith(color: StreetFoodMafiaColors.secondaryText)),
                    ],
                  ),
                ),
              const SizedBox(width: 12),
              if (reprintTrayController != null)
                ListenableBuilder(
                  listenable: reprintTrayController!,
                  builder: (context, _) {
                    final failures = reprintTrayController!.failedCount;
                    final label = failures > 0 ? 'Reprint Tray ($failures)' : 'Reprint Tray';
                    return Tooltip(
                      message: label,
                      child: TextButton.icon(
                        key: const ValueKey('header_reprint_tray_button'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ReprintTrayDialog(
                            controller: reprintTrayController!, currentStaff: staff,
                            orderController: orderController, authService: authService,
                          ),
                        ),
                        icon: Icon(Icons.print_outlined, size: 18,
                            color: failures > 0 ? StreetFoodMafiaColors.statusCanceled : StreetFoodMafiaColors.secondaryText),
                        label: Text(compact ? (failures > 0 ? '$failures' : '') : label),
                      ),
                    );
                  },
                ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Lock Register',
                child: OutlinedButton.icon(
                  key: const ValueKey('lock_register_button'),
                  onPressed: onLock,
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: Text(compact ? 'Lock' : 'Lock Register'),
                ),
              ),
            ],
          ]);
        }),
      ),
    );
  }
}

