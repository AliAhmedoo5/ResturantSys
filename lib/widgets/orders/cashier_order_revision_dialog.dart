import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/catalog/menu_item.dart';
import '../../core/catalog/catalog_and_recipe_controller.dart';
import '../../core/catalog/modifier.dart';
import '../../core/catalog/modifier_group.dart';
import '../../core/orders/cart_item.dart';
import '../../core/orders/deal.dart';
import '../../core/orders/order.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/orders/payment_method.dart';
import '../../core/orders/token_status.dart';
import '../../core/theme/theme.dart';
import 'deal_selection_dialog.dart';
import 'modifier_selection_dialog.dart';

/// Modal dialog enabling Cashiers to autonomously revise line items, quantities,
/// or cancel confirmed orders without requiring a Manager PIN.
///
/// Features stage-aware inventory notices (RESTOCK_RAW vs WASTED_COOKED)
/// and decoupled explicit refund disbursement actions.
class CashierOrderRevisionDialog extends StatefulWidget {
  const CashierOrderRevisionDialog({
    super.key,
    required this.order,
    required this.cashierId,
    required this.shiftId,
    required this.orderController,
    this.catalogController,
    this.onRevisionCompleted,
  });

  final Order order;
  final int cashierId;
  final int shiftId;
  final OrderAndCheckoutController orderController;
  final CatalogAndRecipeController? catalogController;
  final VoidCallback? onRevisionCompleted;

  @override
  State<CashierOrderRevisionDialog> createState() =>
      _CashierOrderRevisionDialogState();
}

class _CashierOrderRevisionDialogState
    extends State<CashierOrderRevisionDialog> {
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final TextEditingController _reasonController = TextEditingController();

  late List<CartItem> _revisedItems;
  bool _isSubmitting = false;
  bool _isChoosingItems = false;
  String? _errorMessage;
  int? _pendingRefundPaisa;

  static const List<String> _quickReasons = [
    'Customer changed mind',
    'Item quantity adjusted',
    'Wrong item ordered',
    'Customer requested extra item',
    'Kitchen delay / cancellation',
    'Customer walkout',
  ];

  @override
  void initState() {
    super.initState();
    _reasonController.text = _quickReasons.first;

    // Clone order items to editable cart items
    _revisedItems = widget.order.items.map((oi) {
      final modifiers = oi.decodedModifiers.map(Modifier.fromMap).toList();
      final choices = oi.decodedDealChoices.map(SelectedDealChoice.fromJson).toList();
      // Stored unit prices already include modifiers and deal upgrades.
      final basePrice = oi.unitPrice -
          modifiers.fold<double>(0, (sum, m) => sum + m.priceDelta) -
          choices.fold<double>(0, (sum, c) => sum + c.upgradePrice);
      return CartItem(
        menuItem: oi.isDeal ? null : MenuItem(
          // Deleted catalog entries retain their order snapshot, but cannot be
          // submitted as another menu item with a fabricated catalog identity.
          id: oi.menuItemId ?? 0,
          categoryId: 1,
          name: oi.name,
          basePrice: basePrice,
        ),
        deal: oi.isDeal ? Deal(
          id: oi.dealId!, name: oi.name, basePrice: basePrice,
          createdAt: oi.createdAt,
        ) : null,
        quantity: oi.quantity,
        selectedModifiers: modifiers,
        selectedDealChoices: choices,
      );
    }).toList();

    _checkPendingRefund();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _checkPendingRefund() async {
    final pending =
        await widget.orderController.getOrderPendingRefundPaisa(widget.order.id);
    if (mounted) {
      setState(() => _pendingRefundPaisa = pending);
    }
  }

  double get _revisedTotal =>
      _revisedItems.fold(0.0, (sum, i) => sum + i.totalPrice);
  double get _delta => _revisedTotal - widget.order.grandTotal;

  Future<void> _addItems() async {
    setState(() {
      _isChoosingItems = true;
      _errorMessage = null;
    });
    try {
      final catalog = widget.catalogController ??
          CatalogAndRecipeController(database: widget.orderController.database);
      final menuItems = await catalog.getMenuItems(activeOnly: true);
      final deals = await widget.orderController.getDeals(activeOnly: true);
      if (!mounted) return;
      final selectedItem = await showDialog<CartItem>(
        context: context,
        builder: (_) => _RevisionCatalogPicker(menuItems: menuItems, deals: deals),
      );
      if (selectedItem == null || !mounted) return;
      var item = selectedItem;
      if (item.isDeal) {
        final choices = await showDialog<List<SelectedDealChoice>>(
          context: context,
          builder: (_) => DealSelectionDialog(
            deal: selectedItem.deal!, availableMenuItems: menuItems,
          ),
        );
        if (choices == null || !mounted) return;
        item = item.copyWith(selectedDealChoices: choices);
      }
      final configuredItem = item;
      final allModifiers = await catalog.getModifiers(activeOnly: true);
      // Match checkout: global options once, item groups once per component.
      final componentIds = item.isDeal
          ? item.selectedDealChoices.map((c) => c.menuItemId).toSet()
          : {item.menuItem!.id};
      final modifiers = <Modifier>[];
      final scopes = item.isDeal ? <int?>[null, ...componentIds] : <int?>[item.menuItem!.id];
      for (final id in scopes) {
        final options = allModifiers.where((m) => m.menuItemId == id ||
            (!configuredItem.isDeal && m.menuItemId == null)).toList();
        final groups = id == null ? <ModifierGroup>[] :
            await catalog.getModifierGroups(menuItemId: id);
        if (!mounted) return;
        if (options.isEmpty && groups.isEmpty) continue;
        final name = id == null || !item.isDeal ? item.name :
            item.selectedDealChoices.firstWhere((c) => c.menuItemId == id).menuItemName;
        final selected = await showDialog<List<Modifier>>(
          context: context,
          builder: (_) => ModifierSelectionDialog(
            itemName: name, availableModifiers: options, groups: groups,
          ),
        );
        if (selected == null || !mounted) return;
        modifiers.addAll(selected);
      }
      if (mounted) setState(() => _revisedItems.add(configuredItem.copyWith(selectedModifiers: modifiers)));
    } catch (error) {
      if (mounted) setState(() => _errorMessage = 'Could not add item: $error');
    } finally {
      if (mounted) setState(() => _isChoosingItems = false);
    }
  }

  void _incrementItem(int index) {
    setState(() {
      final item = _revisedItems[index];
      _revisedItems[index] = item.copyWith(quantity: item.quantity + 1);
    });
  }

  void _decrementItem(int index) {
    setState(() {
      final item = _revisedItems[index];
      if (item.quantity > 1) {
        _revisedItems[index] = item.copyWith(quantity: item.quantity - 1);
      } else {
        _revisedItems.removeAt(index);
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _revisedItems.removeAt(index);
    });
  }

  Future<void> _handleApplyRevision() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Revision reason is mandatory.');
      return;
    }
    if (_revisedItems.any((item) => item.menuItem?.id == 0)) {
      setState(() => _errorMessage =
          'An original item was deleted from the catalog. Remove it before applying a revision, or cancel the order.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final commandId = 'rev-${widget.order.id}-${DateTime.now().millisecondsSinceEpoch}';
      await widget.orderController.reviseOrder(
        orderId: widget.order.id,
        cashierId: widget.cashierId,
        reason: reason,
        commandId: commandId,
        newItems: _revisedItems,
      );

      await _checkPendingRefund();
      widget.onRevisionCompleted?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order ${widget.order.tokenDisplay} revised successfully.',
            ),
            backgroundColor: WarmCounterColors.lightPrimaryAction,
          ),
        );
        if ((_pendingRefundPaisa ?? 0) == 0) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleCancelOrder() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorMessage = 'Cancellation reason is mandatory.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final commandId = 'cancel-${widget.order.id}-${DateTime.now().millisecondsSinceEpoch}';
      await widget.orderController.cancelOrder(
        orderId: widget.order.id,
        cashierId: widget.cashierId,
        reason: reason,
        commandId: commandId,
      );

      await _checkPendingRefund();
      widget.onRevisionCompleted?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Order ${widget.order.tokenDisplay} canceled successfully.',
            ),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
        if ((_pendingRefundPaisa ?? 0) == 0) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _handleDisburseRefund(PaymentMethod method) async {
    if ((_pendingRefundPaisa ?? 0) <= 0) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final commandId = 'refund-${widget.order.id}-${DateTime.now().millisecondsSinceEpoch}';
      await widget.orderController.recordCashierRefund(
        orderId: widget.order.id,
        shiftId: widget.shiftId,
        cashierId: widget.cashierId,
        amountPaisa: _pendingRefundPaisa!,
        method: method,
        referenceCode: method != PaymentMethod.cash ? 'REF-${widget.order.id}' : null,
        reason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : 'Order revision refund payout',
        commandId: commandId,
      );

      await _checkPendingRefund();
      widget.onRevisionCompleted?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Refund of Rs ${_currencyFormat.format(_pendingRefundPaisa! / 100)} recorded successfully.',
            ),
            backgroundColor: WarmCounterColors.lightPrimaryAction,
          ),
        );
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUnstarted = widget.order.tokenStatus == TokenStatus.confirmed;
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      key: const ValueKey('cashier_order_revision_dialog'),
      backgroundColor: WarmCounterColors.lightCardBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: WarmCounterColors.lightWarningHighlight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.order.tokenDisplay,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: WarmCounterColors.lightPrimaryText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${widget.order.id} Revision',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: WarmCounterColors.lightPrimaryText,
                          ),
                        ),
                        Text(
                          'Stage: ${widget.order.tokenStatus.displayName} • Cashier Autonomy (No PIN)',
                          style: TextStyle(
                            fontSize: 12,
                            color: isUnstarted
                                ? WarmCounterColors.lightPrimaryAction
                                : Colors.deepOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('close_revision_dialog_button'),
                    icon: const Icon(Icons.close),
                    onPressed: _isSubmitting || _isChoosingItems
                        ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Stage-aware stock notice badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isUnstarted
                      ? WarmCounterColors.lightPrimaryAction.withAlpha(25)
                      : Colors.deepOrange.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isUnstarted
                        ? WarmCounterColors.lightPrimaryAction
                        : Colors.deepOrange,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isUnstarted ? Icons.inventory_2_outlined : Icons.delete_outline,
                      size: 18,
                      color: isUnstarted
                          ? WarmCounterColors.lightPrimaryAction
                          : Colors.deepOrange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isUnstarted
                            ? 'Unstarted Prep: Items removed now will return to bulk raw inventory (RESTOCK_RAW).'
                            : 'Active/Completed Prep: Items removed now cannot return to raw stock and post to cooked wastage (WASTED_COOKED).',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isUnstarted
                              ? WarmCounterColors.lightPrimaryAction
                              : Colors.deepOrange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Pending refund banner (if refund owed)
              if ((_pendingRefundPaisa ?? 0) > 0)
                Container(
                  key: const ValueKey('pending_refund_banner'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade800, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.money_off, color: Colors.brown),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Refund Owed / Pending',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              'Amount: Rs ${_currencyFormat.format(_pendingRefundPaisa! / 100)} (Drawer not automatically opened)',
                              style: const TextStyle(fontSize: 12, color: Colors.brown),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        key: const ValueKey('disburse_cash_refund_button'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.brown,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.point_of_sale_outlined, size: 16),
                        label: const Text('Cash Payout'),
                        onPressed: _isSubmitting
                            ? null
                            : () => _handleDisburseRefund(PaymentMethod.cash),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const ValueKey('confirm_digital_refund_button'),
                        onPressed: _isSubmitting
                            ? null
                            : () => _handleDisburseRefund(PaymentMethod.jazzCash),
                        child: const Text('Digital'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),

              // Items editor list
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Line Items & Quantities:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  TextButton.icon(
                    key: const ValueKey('add_revision_items_button'),
                    onPressed: _isSubmitting || _isChoosingItems ? null : _addItems,
                    icon: const Icon(Icons.add),
                    label: Text(_isChoosingItems ? 'Loading menu...' : 'Add Items / Deals'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: _revisedItems.isEmpty
                      ? const Center(
                          child: Text(
                            'All items removed. Click "Cancel Entire Order" below.',
                            style: TextStyle(color: WarmCounterColors.lightSecondaryText),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _revisedItems.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, index) {
                            final item = _revisedItems[index];
                            return ListTile(
                              dense: true,
                              textColor: colors.onSurface,
                              iconColor: colors.onSurface,
                              title: Text(
                                item.name,
                                style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
                              ),
                              subtitle: Text(
                                'Rs ${_currencyFormat.format(item.unitPrice)} each',
                                style: TextStyle(color: colors.onSurfaceVariant),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('decrement_item_$index'),
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    onPressed: _isSubmitting ? null : () => _decrementItem(index),
                                  ),
                                  Text(
                                    '${item.quantity}',
                                    style: TextStyle(
                                      color: colors.onSurface,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey('increment_item_$index'),
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    onPressed: _isSubmitting ? null : () => _incrementItem(index),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Rs ${_currencyFormat.format(item.totalPrice)}',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: colors.onSurface),
                                  ),
                                  IconButton(
                                    key: ValueKey('remove_item_$index'),
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                    onPressed: _isSubmitting ? null : () => _removeItem(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 10),

              // Totals row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Original: Rs ${_currencyFormat.format(widget.order.grandTotal)}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Delta: ${_delta >= 0 ? "+" : ""}Rs ${_currencyFormat.format(_delta)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _delta < 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'New Total: Rs ${_currencyFormat.format(_revisedTotal)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: WarmCounterColors.lightPrimaryText,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Mandatory Reason field & quick tags
              const Text(
                'Mandatory Reason:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _quickReasons.map((r) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: ActionChip(
                        label: Text(r, style: const TextStyle(fontSize: 11)),
                        onPressed: () => setState(() => _reasonController.text = r),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('revision_reason_input'),
                controller: _reasonController,
                decoration: const InputDecoration(
                  hintText: 'Enter mandatory reason for revision/cancellation...',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
              const SizedBox(height: 14),

              // Action buttons
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('cancel_entire_order_button'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel Entire Order'),
                    onPressed: _isSubmitting || _isChoosingItems ? null : _handleCancelOrder,
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    key: const ValueKey('apply_revision_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: WarmCounterColors.lightTextOnPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: const Text(
                      'Apply Revision',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isSubmitting || _isChoosingItems ? null : _handleApplyRevision,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevisionCatalogPicker extends StatefulWidget {
  const _RevisionCatalogPicker({required this.menuItems, required this.deals});
  final List<MenuItem> menuItems;
  final List<Deal> deals;

  @override
  State<_RevisionCatalogPicker> createState() => _RevisionCatalogPickerState();
}

class _RevisionCatalogPickerState extends State<_RevisionCatalogPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final items = <CartItem>[
      for (final item in widget.menuItems) CartItem(menuItem: item),
      for (final deal in widget.deals) CartItem(deal: deal),
    ].where((item) => item.name.toLowerCase().contains(_query)).toList();
    return AlertDialog(
      title: const Text('Add Items / Deals'),
      content: SizedBox(
        width: 560, height: 400,
        child: Column(children: [
          TextField(
            key: const ValueKey('revision_catalog_search'),
            decoration: const InputDecoration(labelText: 'Search menu items and deals', prefixIcon: Icon(Icons.search)),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          Expanded(child: items.isEmpty
            ? const Center(child: Text('No available items or deals.'))
            : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, index) {
                final item = items[index];
                return ListTile(
                  key: ValueKey('revision_catalog_${item.isDeal ? 'deal' : 'item'}_${item.menuItem?.id ?? item.deal!.id}'),
                  leading: Icon(item.isDeal ? Icons.local_offer_outlined : Icons.restaurant),
                  title: Text(item.name),
                  subtitle: Text('${item.isDeal ? 'Deal' : 'Menu item'} • Rs ${item.basePrice.toStringAsFixed(2)}'),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: () => Navigator.of(context).pop(item),
                );
              },
            )),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
