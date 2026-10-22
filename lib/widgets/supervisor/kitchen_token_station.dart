import 'package:flutter/material.dart';
import '../../core/auth/staff.dart';
import '../../core/orders/order.dart';
import '../../core/orders/token_queue_controller.dart';
import '../../core/theme/theme.dart';


/// Kitchen Token Station: Managers mark tokens as Ready using their existing session.
class KitchenTokenStation extends StatefulWidget {
  const KitchenTokenStation({
    super.key,
    required this.controller,
    this.currentStaff,
  });

  final TokenQueueController controller;
  final Staff? currentStaff;

  @override
  State<KitchenTokenStation> createState() => _KitchenTokenStationState();
}

class _KitchenTokenStationState extends State<KitchenTokenStation> {
  @override
  Widget build(BuildContext context) {
    final staff = widget.currentStaff;
    if (staff == null || !staff.isActive || !staff.role.isManager) {
      return const Center(child: Text('Sign in as Manager to view the kitchen station.'));
    }
    return _buildKitchenStationBoard(context, staff);
  }
  Widget _buildKitchenStationBoard(BuildContext context, Staff cook) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final preparingOrders = widget.controller.preparingTokens;

        return Container(
          decoration: BoxDecoration(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WarmCounterSpacing.space24,
                  vertical: WarmCounterSpacing.space16,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: WarmCounterColors.lightBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFF7ED),
                            borderRadius: WarmCounterSpacing.controlBorderRadius,
                          ),
                          child: const Icon(
                            Icons.soup_kitchen_rounded,
                            color: Color(0xFFEA580C),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: WarmCounterSpacing.space12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Kitchen Token Station (The Pass)',
                              style: WarmCounterTypography.pageHeading.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Unlocked by ${cook.name} (${cook.role.displayName}) • ${preparingOrders.length} orders cooking',
                              style: WarmCounterTypography.secondaryLabel.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: 'Refresh',
                          onPressed: () => widget.controller.loadTokens(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Orders Grid
              Expanded(
                child: preparingOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.restaurant_rounded,
                              size: 56,
                              color: Color(0xFF10B981),
                            ),
                            const SizedBox(height: WarmCounterSpacing.space16),
                            Text(
                              'All orders plated! The pass is clear.',
                              style: WarmCounterTypography.pageHeading.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF047857),
                              ),
                            ),
                            const SizedBox(height: WarmCounterSpacing.space4),
                            Text(
                              'New incoming counter chits will appear here automatically.',
                              style: WarmCounterTypography.bodyMedium.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 420,
                          mainAxisExtent: 260,
                          crossAxisSpacing: WarmCounterSpacing.space16,
                          mainAxisSpacing: WarmCounterSpacing.space16,
                        ),
                        itemCount: preparingOrders.length,
                        itemBuilder: (context, index) {
                          final order = preparingOrders[index];
                          return _buildKitchenOrderCard(context, order);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKitchenOrderCard(BuildContext context, Order order) {
    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        border: Border.all(
          color: const Color(0xFFEA580C), // Orange kitchen border
          width: 2.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header: Token Number & Dining Type
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFFEA580C),
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                ),
                child: Text(
                  order.tokenDisplay,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: WarmCounterColors.lightPageBackground,
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                  border: Border.all(color: WarmCounterColors.lightBorder),
                ),
                child: Text(
                  order.diningType.displayName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: WarmCounterColors.lightPrimaryText,
                  ),
                ),
              ),
            ],
          ),

          // Items List
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WarmCounterSpacing.space12),
              child: ListView(
                children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.quantity}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Big 1-Tap "Mark Ready" Button
          ElevatedButton.icon(
            key: ValueKey('kitchen_mark_ready_${order.id}'),
            onPressed: () => widget.controller.markTokenReady(order.id),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 24),
            label: const Text(
              'PLATED ON PASS (MARK READY)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetFoodMafiaColors.statusReady,
              foregroundColor: StreetFoodMafiaColors.textOnPrimary,
              shape: const RoundedRectangleBorder(
                borderRadius: WarmCounterSpacing.controlBorderRadius,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
