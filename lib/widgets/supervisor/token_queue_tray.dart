import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/orders/order.dart';
import '../../core/orders/token_queue_controller.dart';
import '../../core/orders/token_status.dart';
import '../../core/theme/theme.dart';

/// Interactive on-screen tray showing active tokens with 1-tap progression:
/// Preparing -> Ready -> Delivered.
class TokenQueueTray extends StatefulWidget {
  const TokenQueueTray({
    super.key,
    required this.controller,
  });

  final TokenQueueController controller;

  @override
  State<TokenQueueTray> createState() => _TokenQueueTrayState();
}

class _TokenQueueTrayState extends State<TokenQueueTray> {
  String _selectedFilter = 'ACTIVE'; // 'ACTIVE', 'PREPARING', 'READY', 'DELIVERED'
  final DateFormat _timeFormat = DateFormat('hh:mm a');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;

        List<Order> displayedTokens;
        switch (_selectedFilter) {
          case 'PREPARING':
            displayedTokens = controller.preparingTokens;
            break;
          case 'READY':
            displayedTokens = controller.readyTokens;
            break;
          case 'DELIVERED':
            displayedTokens = controller.deliveredTokens;
            break;
          case 'ACTIVE':
          default:
            displayedTokens = controller.activeTokens;
            break;
        }

        return Container(
          decoration: BoxDecoration(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Filter Chips
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WarmCounterSpacing.space24,
                  vertical: WarmCounterSpacing.space16,
                ),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: WarmCounterColors.lightBorder)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                      decoration: const BoxDecoration(
                        color: WarmCounterColors.lightActiveNavHighlight,
                        borderRadius: WarmCounterSpacing.controlBorderRadius,
                      ),
                      child: const Icon(
                        Icons.confirmation_number_rounded,
                        color: WarmCounterColors.lightPrimaryAction,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Token Queue Tray',
                            style: WarmCounterTypography.pageHeading.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${controller.activeTokens.length} active • ${controller.preparingTokens.length} preparing • ${controller.readyTokens.length} ready on pass',
                            style: WarmCounterTypography.secondaryLabel.copyWith(
                              color: WarmCounterColors.lightSecondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh Tokens',
                      onPressed: () => widget.controller.loadTokens(),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space8),
                    // Filter Chips
                    _buildFilterChip('Active (${controller.activeTokens.length})', 'ACTIVE'),
                    const SizedBox(width: WarmCounterSpacing.space8),
                    _buildFilterChip('Preparing (${controller.preparingTokens.length})', 'PREPARING'),
                    const SizedBox(width: WarmCounterSpacing.space8),
                    _buildFilterChip('Ready (${controller.readyTokens.length})', 'READY'),
                    const SizedBox(width: WarmCounterSpacing.space8),
                    _buildFilterChip('Delivered (${controller.deliveredTokens.length})', 'DELIVERED'),
                  ],
                ),
              ),

              // Content Area
              Expanded(
                child: controller.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : displayedTokens.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 48,
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                                const SizedBox(height: WarmCounterSpacing.space12),
                                Text(
                                  'No tokens in this status.',
                                  style: WarmCounterTypography.bodyMedium.copyWith(
                                    color: WarmCounterColors.lightSecondaryText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 380,
                              mainAxisExtent: 220,
                              crossAxisSpacing: WarmCounterSpacing.space16,
                              mainAxisSpacing: WarmCounterSpacing.space16,
                            ),
                            itemCount: displayedTokens.length,
                            itemBuilder: (context, index) {
                              final order = displayedTokens[index];
                              return _buildTokenCard(context, order);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, String code) {
    final isSelected = _selectedFilter == code;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = code),
      selectedColor: WarmCounterColors.lightActiveNavHighlight,
      backgroundColor: Colors.transparent,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        color: isSelected ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightPrimaryText,
      ),
      side: BorderSide(
        color: isSelected ? WarmCounterColors.lightPrimaryAction : WarmCounterColors.lightBorder,
      ),
    );
  }

  Widget _buildTokenCard(BuildContext context, Order order) {
    final isPreparing = order.tokenStatus == TokenStatus.preparing;
    final isReady = order.tokenStatus == TokenStatus.ready;

    final itemsSummary = order.items.isNotEmpty
        ? order.items.map((it) => '${it.quantity}x ${it.name}').join(', ')
        : 'Order Items';

    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        border: Border.all(
          color: isReady
              ? StreetFoodMafiaColors.statusReady
              : isPreparing
                  ? StreetFoodMafiaColors.statusPreparing
                  : StreetFoodMafiaColors.border,
          width: isReady ? 2.0 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header: Token Number & Dining Type & Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: const BoxDecoration(
                      color: WarmCounterColors.lightPrimaryAction,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                    ),
                    child: Text(
                      order.tokenDisplay,
                      style: const TextStyle(
                        color: StreetFoodMafiaColors.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: WarmCounterColors.lightPageBackground,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                      border: Border.all(color: WarmCounterColors.lightBorder),
                    ),
                    child: Text(
                      order.diningType.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WarmCounterColors.lightPrimaryText,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                _timeFormat.format(order.createdAt),
                style: WarmCounterTypography.secondaryLabel.copyWith(
                  color: WarmCounterColors.lightSecondaryText,
                ),
              ),
            ],
          ),

          // Middle: Items Summary & Status Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                itemsSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: WarmCounterTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space8),
              Row(
                children: [
                  if (isPreparing)
                    const SemanticStatusBadge.preparing(label: 'PREPARING')
                  else if (isReady)
                    const SemanticStatusBadge.ready(label: 'READY ON PASS')
                  else
                    const SemanticStatusBadge.ready(label: 'DELIVERED'),
                ],
              ),
            ],
          ),

          // Bottom: 1-Tap Progression Action
          if (isPreparing) ...[
            ElevatedButton.icon(
              key: ValueKey('advance_token_${order.id}'),
              onPressed: () => widget.controller.advanceToken(order.id),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Mark Ready (Plated on Pass)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: StreetFoodMafiaColors.statusReady,
                foregroundColor: StreetFoodMafiaColors.textOnPrimary,
                shape: const RoundedRectangleBorder(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ] else if (isReady) ...[
            ElevatedButton.icon(
              key: ValueKey('advance_token_${order.id}'),
              onPressed: () => widget.controller.advanceToken(order.id),
              icon: const Icon(Icons.delivery_dining_outlined, size: 18),
              label: const Text('Mark Delivered'),
              style: ElevatedButton.styleFrom(
                backgroundColor: StreetFoodMafiaColors.cartelYellow,
                foregroundColor: StreetFoodMafiaColors.textOnPrimary,
                shape: const RoundedRectangleBorder(
                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: WarmCounterColors.lightPageBackground,
                borderRadius: WarmCounterSpacing.controlBorderRadius,
              ),
              child: const Text(
                'Fulfilled & Delivered',
                style: TextStyle(
                  color: WarmCounterColors.lightSecondaryText,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
