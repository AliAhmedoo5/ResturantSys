import 'package:flutter/material.dart';
import '../../core/auth/staff.dart';
import '../../core/delivery/rider_trip.dart';
import '../../core/delivery/rider_trip_controller.dart';
import '../../core/orders/order.dart';
import '../../core/orders/paisa_engine.dart';
import '../../core/shifts/shift.dart';
import '../../core/theme/theme.dart';
import 'rider_trip_settlement_dialog.dart';

/// Counter & dispatch workstation for batching delivery orders into named Rider Trips,
/// managing live trips, monitoring dispatch alerts, and performing cash settlement.
class RiderTripDispatchWorkspace extends StatefulWidget {
  const RiderTripDispatchWorkspace({
    super.key,
    required this.controller,
    required this.currentStaff,
    this.currentShift,
    this.businessDayId,
  });

  final RiderTripController controller;
  final Staff currentStaff;
  final Shift? currentShift;
  final int? businessDayId;

  @override
  State<RiderTripDispatchWorkspace> createState() => _RiderTripDispatchWorkspaceState();
}

class _RiderTripDispatchWorkspaceState extends State<RiderTripDispatchWorkspace> {
  bool _isLoading = true;
  List<Order> _pendingOrders = [];
  List<RiderTrip> _activeTrips = [];
  List<RiderDispatchAlert> _activeAlerts = [];
  List<Staff> _availableRiders = [];

  final Set<int> _selectedOrderIds = {};
  Staff? _selectedRider;
  final _tripNameController = TextEditingController();
  bool _isDispatching = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tripNameController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final pending = await widget.controller.getPendingDeliveryOrders(
        shiftId: widget.currentShift?.id,
        businessDayId: widget.businessDayId,
      );
      final active = await widget.controller.getActiveTrips(
        shiftId: widget.currentShift?.id,
        businessDayId: widget.businessDayId,
      );
      final alerts = await widget.controller.getActiveAlerts();
      final riders = await widget.controller.getAvailableRiders();

      if (mounted) {
        setState(() {
          _pendingOrders = pending;
          _activeTrips = active;
          _activeAlerts = alerts;
          _availableRiders = riders;
          if (_selectedRider == null && riders.isNotEmpty) {
            _selectedRider = riders.first;
            _tripNameController.text = 'Trip #${active.length + 1} - ${_selectedRider!.name}';
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDispatch() async {
    if (_selectedOrderIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one delivery order to dispatch.')),
      );
      return;
    }
    if (_selectedRider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a rider for this trip.')),
      );
      return;
    }

    setState(() => _isDispatching = true);
    try {
      final tripName = _tripNameController.text.trim().isNotEmpty
          ? _tripNameController.text.trim()
          : 'Trip #${_activeTrips.length + 1} - ${_selectedRider!.name}';

      await widget.controller.createRiderTrip(
        riderStaffId: _selectedRider!.id,
        shiftId: widget.currentShift?.id ?? 1,
        businessDayId: widget.businessDayId ?? 1,
        tripName: tripName,
        orderIds: _selectedOrderIds.toList(),
      );

      _selectedOrderIds.clear();
      _tripNameController.clear();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: StreetFoodMafiaColors.crimsonRed,
            content: Text(e.toString().replaceAll('StateError: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDispatching = false);
    }
  }

  Future<void> _handleMarkDelivered(int tripId, int orderId) async {
    try {
      await widget.controller.markOrderDelivered(tripId: tripId, orderId: orderId);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: StreetFoodMafiaColors.crimsonRed, content: Text('$e')),
        );
      }
    }
  }

  Future<void> _handleMarkReturned(int tripId, int orderId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StreetFoodMafiaColors.darkNavy,
        title: const Text('Return Undelivered Order', style: TextStyle(color: StreetFoodMafiaColors.offWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter mandatory reason for returned delivery (e.g. customer unreachable, wrong address):',
              style: TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('return_reason_input'),
              controller: reasonController,
              style: const TextStyle(color: StreetFoodMafiaColors.offWhite),
              decoration: const InputDecoration(
                hintText: 'Return reason...',
                filled: true,
                fillColor: StreetFoodMafiaColors.obsidianBlack,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            key: const ValueKey('confirm_return_btn'),
            style: ElevatedButton.styleFrom(backgroundColor: StreetFoodMafiaColors.crimsonRed),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Return', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonController.text.trim().isNotEmpty) {
      try {
        await widget.controller.markOrderReturned(
          tripId: tripId,
          orderId: orderId,
          reason: reasonController.text.trim(),
        );
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: StreetFoodMafiaColors.crimsonRed, content: Text('$e')),
          );
        }
      }
    }
  }

  Future<void> _openSettlementDialog(RiderTrip trip) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RiderTripSettlementDialog(
        trip: trip,
        cashierStaffId: widget.currentStaff.id,
        shiftId: widget.currentShift?.id ?? 1,
        controller: widget.controller,
        onSettled: _loadData,
      ),
    );
    await _loadData();
  }

  Future<void> _handleAcknowledgeAlert(int alertId) async {
    await widget.controller.acknowledgeDispatchAlert(
      alertId: alertId,
      staffId: widget.currentStaff.id,
    );
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: StreetFoodMafiaColors.cartelYellow));
    }

    return Container(
      color: StreetFoodMafiaColors.obsidianBlack,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Dispatch Alerts Banner
          if (_activeAlerts.isNotEmpty) ...[
            _buildAlertsBanner(),
            const SizedBox(height: 14),
          ],

          // 2. Main Workstation Grid
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Pane: Pending Delivery Orders & Dispatch Formulation
                Expanded(
                  flex: 5,
                  child: _buildPendingDispatchPane(),
                ),
                const SizedBox(width: 16),
                // Right Pane: Active Rider Trips
                Expanded(
                  flex: 7,
                  child: _buildActiveTripsPane(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: StreetFoodMafiaColors.crimsonRed.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StreetFoodMafiaColors.crimsonRed, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: StreetFoodMafiaColors.crimsonRed, size: 24),
              const SizedBox(width: 10),
              Text(
                'RIDER DISPATCH ALERTS (${_activeAlerts.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: StreetFoodMafiaColors.crimsonRed,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._activeAlerts.map((alert) {
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '• ${alert.message}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: StreetFoodMafiaColors.offWhite,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    key: ValueKey('ack_alert_${alert.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StreetFoodMafiaColors.crimsonRed,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () => _handleAcknowledgeAlert(alert.id),
                    child: const Text('Acknowledge', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPendingDispatchPane() {
    return Container(
      decoration: BoxDecoration(
        color: StreetFoodMafiaColors.darkNavy,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StreetFoodMafiaColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pending Deliveries',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StreetFoodMafiaColors.offWhite),
              ),
              Text(
                '${_pendingOrders.length} ready',
                style: const TextStyle(fontSize: 13, color: StreetFoodMafiaColors.cartelYellow, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const Divider(height: 20),
          Expanded(
            child: _pendingOrders.isEmpty
                ? const Center(
                    child: Text(
                      'No delivery orders awaiting dispatch.',
                      style: TextStyle(color: StreetFoodMafiaColors.secondaryText),
                    ),
                  )
                : ListView.builder(
                    itemCount: _pendingOrders.length,
                    itemBuilder: (context, index) {
                      final order = _pendingOrders[index];
                      final isSelected = _selectedOrderIds.contains(order.id);
                      final isCod = order.paymentStatus == 'COLLECTION_DUE';

                      return Card(
                        color: isSelected ? StreetFoodMafiaColors.activeNavHighlight : StreetFoodMafiaColors.obsidianBlack,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? StreetFoodMafiaColors.cartelYellow : StreetFoodMafiaColors.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedOrderIds.remove(order.id);
                              } else {
                                _selectedOrderIds.add(order.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: StreetFoodMafiaColors.cartelYellow,
                                  checkColor: StreetFoodMafiaColors.obsidianBlack,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedOrderIds.add(order.id);
                                      } else {
                                        _selectedOrderIds.remove(order.id);
                                      }
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            order.tokenDisplay,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w900,
                                              color: StreetFoodMafiaColors.cartelYellow,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isCod ? StreetFoodMafiaColors.cartelYellow.withValues(alpha: 0.2) : StreetFoodMafiaColors.successGreen.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              isCod ? 'COD (Rs. ${order.grandTotal.toStringAsFixed(0)})' : 'PREPAID',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: isCod ? StreetFoodMafiaColors.cartelYellow : StreetFoodMafiaColors.successGreen,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${order.customerName ?? "Customer"} • ${order.customerPhone ?? ""}',
                                        style: const TextStyle(fontSize: 13, color: StreetFoodMafiaColors.offWhite, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        order.deliveryAddress ?? 'No address recorded',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 20),
          // Batch Controls
          DropdownButtonFormField<Staff>(
            key: const ValueKey('rider_select_dropdown'),
            initialValue: _selectedRider,
            dropdownColor: StreetFoodMafiaColors.darkNavy,
            style: const TextStyle(color: StreetFoodMafiaColors.offWhite, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Assign to Rider',
              labelStyle: TextStyle(color: StreetFoodMafiaColors.secondaryText),
              filled: true,
              fillColor: StreetFoodMafiaColors.obsidianBlack,
              border: OutlineInputBorder(),
            ),
            items: _availableRiders.map((r) => DropdownMenuItem(value: r, child: Text(r.name))).toList(),
            onChanged: (rider) {
              setState(() {
                _selectedRider = rider;
                if (rider != null) {
                  _tripNameController.text = 'Trip #${_activeTrips.length + 1} - ${rider.name}';
                }
              });
            },
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('trip_name_input'),
            controller: _tripNameController,
            style: const TextStyle(color: StreetFoodMafiaColors.offWhite, fontSize: 14),
            decoration: const InputDecoration(
              labelText: 'Trip Name / Memo',
              labelStyle: TextStyle(color: StreetFoodMafiaColors.secondaryText),
              filled: true,
              fillColor: StreetFoodMafiaColors.obsidianBlack,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const ValueKey('dispatch_trip_btn'),
            icon: _isDispatching
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: StreetFoodMafiaColors.obsidianBlack))
                : const Icon(Icons.send_rounded, color: StreetFoodMafiaColors.obsidianBlack),
            label: Text(
              'Dispatch Rider Trip (${_selectedOrderIds.length})',
              style: const TextStyle(fontWeight: FontWeight.w900, color: StreetFoodMafiaColors.obsidianBlack, fontSize: 14),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: StreetFoodMafiaColors.cartelYellow,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _isDispatching ? null : _handleDispatch,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTripsPane() {
    return Container(
      decoration: BoxDecoration(
        color: StreetFoodMafiaColors.darkNavy,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: StreetFoodMafiaColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Active Rider Trips',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: StreetFoodMafiaColors.offWhite),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: StreetFoodMafiaColors.cartelYellow),
                onPressed: _loadData,
              ),
            ],
          ),
          const Divider(height: 20),
          Expanded(
            child: _activeTrips.isEmpty
                ? const Center(
                    child: Text(
                      'No active trips currently dispatched.',
                      style: TextStyle(color: StreetFoodMafiaColors.secondaryText),
                    ),
                  )
                : ListView.builder(
                    itemCount: _activeTrips.length,
                    itemBuilder: (context, index) {
                      final trip = _activeTrips[index];
                      final expectedRupees = PaisaEngine.paisaToRupees(trip.cashExpectedPaisa);

                      return Card(
                        color: StreetFoodMafiaColors.obsidianBlack,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: trip.hasActiveAlerts ? StreetFoodMafiaColors.crimsonRed : StreetFoodMafiaColors.border,
                            width: trip.hasActiveAlerts ? 2 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Trip Header
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          trip.tripName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: StreetFoodMafiaColors.offWhite,
                                          ),
                                        ),
                                        Text(
                                          'Rider: ${trip.riderName ?? "ID #${trip.riderStaffId}"} • ${trip.orders.length} orders',
                                          style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: StreetFoodMafiaColors.darkNavy,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: StreetFoodMafiaColors.cartelYellow),
                                    ),
                                    child: Text(
                                      'COD: Rs. ${expectedRupees.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: StreetFoodMafiaColors.cartelYellow,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    key: ValueKey('settle_trip_btn_${trip.id}'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: StreetFoodMafiaColors.successGreen,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                    ),
                                    onPressed: () => _openSettlementDialog(trip),
                                    child: const Text('Settle Trip', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 13)),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              // Contained Orders List
                              ...trip.orders.map((tripOrder) {
                                final order = tripOrder.order;
                                final isCod = order?.paymentStatus == 'COLLECTION_DUE';

                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: StreetFoodMafiaColors.darkNavy,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        order?.tokenDisplay ?? '#${tripOrder.orderId}',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: StreetFoodMafiaColors.cartelYellow),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${order?.customerName ?? ""} (${order?.deliveryAddress ?? ""})',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.offWhite),
                                        ),
                                      ),
                                      if (tripOrder.isDelivered)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: StreetFoodMafiaColors.successGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                          child: const Text('Delivered', style: TextStyle(color: StreetFoodMafiaColors.successGreen, fontSize: 11, fontWeight: FontWeight.w700)),
                                        )
                                      else if (tripOrder.isReturned)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: StreetFoodMafiaColors.crimsonRed.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                          child: Text('Returned: ${tripOrder.notes ?? ""}', style: const TextStyle(color: StreetFoodMafiaColors.crimsonRed, fontSize: 11, fontWeight: FontWeight.w700)),
                                        )
                                      else ...[
                                        IconButton(
                                          key: ValueKey('mark_delivered_${tripOrder.orderId}'),
                                          icon: const Icon(Icons.check_circle_outline, color: StreetFoodMafiaColors.successGreen, size: 20),
                                          tooltip: 'Mark Delivered',
                                          onPressed: () => _handleMarkDelivered(trip.id, tripOrder.orderId),
                                        ),
                                        IconButton(
                                          key: ValueKey('mark_returned_${tripOrder.orderId}'),
                                          icon: const Icon(Icons.replay, color: StreetFoodMafiaColors.crimsonRed, size: 20),
                                          tooltip: 'Mark Returned',
                                          onPressed: () => _handleMarkReturned(trip.id, tripOrder.orderId),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
