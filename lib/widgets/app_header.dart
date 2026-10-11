import 'package:flutter/material.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Top application navigation bar displaying system branding, active staff session details,
/// and a 1-tap Lock Register button.
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    required this.activeStaff,
    required this.onLock,
    this.title = 'ResturantPOS',
  });

  final Staff? activeStaff;
  final VoidCallback? onLock;
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

          // Right: Active Session / Locked Status & Actions
          if (activeStaff != null)
            _buildActiveStaffBar(context, activeStaff!)
          else
            _buildLockedStatusBar(context),
        ],
      ),
    );
  }

  Widget _buildActiveStaffBar(BuildContext context, Staff staff) {
    final department = staff.departmentName ?? 'General';
    final roleName = staff.role.displayName;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Staff Info Pill
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WarmCounterSpacing.space16,
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
            children: [
              const Icon(
                Icons.account_circle_rounded,
                size: 22,
                color: WarmCounterColors.lightPrimaryAction,
              ),
              const SizedBox(width: WarmCounterSpacing.space8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    staff.name,
                    style: WarmCounterTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: WarmCounterColors.lightPrimaryText,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    '$department • $roleName',
                    style: WarmCounterTypography.secondaryLabel.copyWith(
                      color: WarmCounterColors.lightSecondaryText,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: WarmCounterSpacing.space16),

        // 1-Tap Lock Register Button
        ElevatedButton.icon(
          key: const ValueKey('lock_register_button'),
          onPressed: onLock,
          icon: const Icon(Icons.lock_outline_rounded, size: 18),
          label: const Text('Lock Register'),
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightDestructive.withValues(alpha: 0.1),
            foregroundColor: WarmCounterColors.lightDestructive,
            elevation: 0.0,
            minimumSize: const Size(140, WarmCounterSpacing.minTouchTargetSize),
            shape: const RoundedRectangleBorder(
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              side: BorderSide(
                color: WarmCounterColors.lightBorder,
                width: 1.0,
              ),
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
}
