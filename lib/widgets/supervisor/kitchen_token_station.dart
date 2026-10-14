import 'package:flutter/material.dart';
import '../../core/auth/staff.dart';
import '../../core/orders/order.dart';
import '../../core/orders/token_queue_controller.dart';
import '../../core/theme/theme.dart';
import '../pin_numpad.dart';

/// Kitchen Token Station: Kitchen staff can authenticate with Kitchen PIN and mark tokens as Ready when plated on the pass.
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
  Staff? _authenticatedCook;
  String _enteredPin = '';
  String? _pinError;

  @override
  void initState() {
    super.initState();
    if (widget.currentStaff != null && widget.currentStaff!.canAccessKitchen) {
      _authenticatedCook = widget.currentStaff;
    }
  }

  Future<void> _handlePinDigit(String digit) async {
    if (_enteredPin.length < 4) {
      final updatedPin = _enteredPin + digit;
      setState(() {
        _enteredPin = updatedPin;
        _pinError = null;
      });

      if (updatedPin.length == 4) {
        final staff = await widget.controller.authenticateKitchenPin(updatedPin);
        if (mounted) {
          if (staff != null) {
            setState(() {
              _authenticatedCook = staff;
              _enteredPin = '';
              _pinError = null;
            });
          } else {
            setState(() {
              _enteredPin = '';
              _pinError = 'Invalid Kitchen PIN or unauthorized role.';
            });
          }
        }
      }
    }
  }

  void _handlePinBackspace() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _pinError = null;
      });
    }
  }

  void _handlePinClear() {
    setState(() {
      _enteredPin = '';
      _pinError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_authenticatedCook == null) {
      return _buildPinLockScreen(context);
    }

    return _buildKitchenStationBoard(context, _authenticatedCook!);
  }

  Widget _buildPinLockScreen(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(WarmCounterSpacing.space32),
        decoration: BoxDecoration(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: WarmCounterColors.lightBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(WarmCounterSpacing.space12),
              decoration: const BoxDecoration(
                color: Color(0xFFFFF7ED), // Amber highlight
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.soup_kitchen_rounded,
                size: 36,
                color: Color(0xFFEA580C),
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space16),
            Text(
              'Kitchen Token Station',
              style: WarmCounterTypography.pageHeading.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space4),
            Text(
              'Enter Kitchen Cook 4-Digit PIN to unlock station',
              textAlign: TextAlign.center,
              style: WarmCounterTypography.bodyMedium.copyWith(
                color: WarmCounterColors.lightSecondaryText,
              ),
            ),
            const SizedBox(height: WarmCounterSpacing.space24),

            // PIN Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final isFilled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled
                        ? const Color(0xFFEA580C)
                        : WarmCounterColors.lightBorder,
                  ),
                );
              }),
            ),
            const SizedBox(height: WarmCounterSpacing.space12),

            if (_pinError != null) ...[
              Text(
                _pinError!,
                style: const TextStyle(
                  color: WarmCounterColors.lightDestructiveAction,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space12),
            ],

            PinNumpad(
              onDigitPressed: _handlePinDigit,
              onBackspacePressed: _handlePinBackspace,
              onClearPressed: _handlePinClear,
            ),
          ],
        ),
      ),
    );
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
                        const SizedBox(width: WarmCounterSpacing.space12),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _authenticatedCook = null),
                          icon: const Icon(Icons.lock_rounded, size: 16),
                          label: const Text('Lock Station'),
                          style: OutlinedButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                              borderRadius: WarmCounterSpacing.controlBorderRadius,
                            ),
                          ),
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
            icon: const Icon(Icons.check_circle_rounded, size: 24),
            label: const Text(
              'PLATED ON PASS (MARK READY)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF047857), // Emerald Green
              foregroundColor: Colors.white,
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
