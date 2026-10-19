import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/staff.dart';
import '../../core/catalog/catalog_and_recipe_controller.dart';
import '../../core/catalog/discount_preset.dart';
import '../../core/catalog/menu_category.dart';
import '../../core/catalog/menu_item.dart';
import '../../core/catalog/modifier.dart';
import '../../core/catalog/modifier_group.dart';
import '../../core/orders/cart_item.dart';
import '../../core/orders/deal.dart';
import '../../core/orders/dining_type.dart';
import '../../core/orders/order.dart';
import '../../core/orders/order_and_checkout_controller.dart';
import '../../core/orders/payment_method.dart';
import '../../core/hardware/in_memory_hardware_adapter.dart';
import '../../core/hardware/reprint_tray_controller.dart';
import '../../core/theme/theme.dart';
import 'deal_selection_dialog.dart';
import 'modifier_selection_dialog.dart';
import 'reprint_tray_dialog.dart';
import 'supervisor_void_dialog.dart';
import 'tender_checkout_dialog.dart';

/// High-speed touch grid billing and checkout interface for counter cashiers.
class CounterBillingWorkspace extends StatefulWidget {
  const CounterBillingWorkspace({
    super.key,
    this.orderController,
    this.catalogController,
    this.reprintTrayController,
    this.authService,
    required this.currentStaff,
    required this.businessDayId,
    required this.shiftId,
    this.onOrderCompleted,
    this.initialCategories,
    this.initialMenuItems,
    this.initialDeals,
    this.initialDiscounts,
    this.initialModifiers,
    this.initialNextTokenNumber,
  });

  final OrderAndCheckoutController? orderController;
  final CatalogAndRecipeController? catalogController;
  final ReprintTrayController? reprintTrayController;
  final AuthService? authService;
  final Staff currentStaff;
  final int businessDayId;
  final int shiftId;
  final VoidCallback? onOrderCompleted;

  final List<MenuCategory>? initialCategories;
  final List<MenuItem>? initialMenuItems;
  final List<Deal>? initialDeals;
  final List<DiscountPreset>? initialDiscounts;
  final List<Modifier>? initialModifiers;
  final int? initialNextTokenNumber;

  @override
  State<CounterBillingWorkspace> createState() => _CounterBillingWorkspaceState();
}

class _CounterBillingWorkspaceState extends State<CounterBillingWorkspace> {
  // Catalog State
  List<MenuCategory> _categories = [];
  List<MenuItem> _menuItems = [];
  List<Deal> _deals = [];
  List<DiscountPreset> _discounts = [];
  List<Modifier> _allModifiers = [];
  bool _isLoading = true;

  // Active View State
  int? _selectedCategoryId; // null = Deals Tab
  DiningType _selectedDiningType = DiningType.dineIn;
  DiscountPreset? _selectedDiscount;

  // Cart State
  final List<CartItem> _cartItems = [];
  int _nextTokenNumber = 1;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    if (widget.initialCategories != null ||
        widget.initialMenuItems != null ||
        widget.initialDeals != null) {
      _categories = widget.initialCategories ?? [];
      _menuItems = widget.initialMenuItems ?? [];
      _deals = widget.initialDeals ?? [];
      _discounts = widget.initialDiscounts ?? [];
      _allModifiers = widget.initialModifiers ?? [];
      _nextTokenNumber = widget.initialNextTokenNumber ?? 1;
      _selectedCategoryId = _categories.isNotEmpty ? _categories.first.id : null;
      _isLoading = false;
    } else {
      _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final categories = widget.catalogController != null
        ? await widget.catalogController!.getCategories()
        : <MenuCategory>[];
    final menuItems = widget.catalogController != null
        ? await widget.catalogController!.getMenuItems(activeOnly: true)
        : <MenuItem>[];
    final deals = widget.orderController != null
        ? await widget.orderController!.getDeals(activeOnly: true)
        : <Deal>[];
    final discounts = widget.catalogController != null
        ? await widget.catalogController!.getDiscountPresets(activeOnly: true)
        : <DiscountPreset>[];
    final modifiers = widget.catalogController != null
        ? await widget.catalogController!.getModifiers(activeOnly: true)
        : <Modifier>[];
    final token = widget.orderController != null
        ? await widget.orderController!.getNextTokenNumber(widget.businessDayId)
        : 1;

    if (mounted) {
      setState(() {
        _categories = categories;
        _menuItems = menuItems;
        _deals = deals;
        _discounts = discounts;
        _allModifiers = modifiers;
        _nextTokenNumber = token;
        _selectedCategoryId = categories.isNotEmpty ? categories.first.id : null;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshToken() async {
    if (widget.orderController == null) return;
    final token = await widget.orderController!.getNextTokenNumber(widget.businessDayId);
    if (mounted) {
      setState(() => _nextTokenNumber = token);
    }
  }

  CartTotals get _cartTotals {
    if (widget.orderController != null) {
      return widget.orderController!.calculateCartTotals(
        items: _cartItems,
        discount: _selectedDiscount,
      );
    }

    double subtotal = 0.0;
    for (final item in _cartItems) {
      subtotal += item.totalPrice;
    }
    double discountAmount = 0.0;
    if (_selectedDiscount != null) {
      discountAmount = _selectedDiscount!.calculateDiscount(subtotal);
    }
    final grandTotal = (subtotal - discountAmount) < 0.0 ? 0.0 : (subtotal - discountAmount);
    return CartTotals(
      subtotal: subtotal,
      discountAmount: discountAmount,
      taxAmount: 0.0,
      grandTotal: grandTotal,
    );
  }

  // ---------------------------------------------------------------------------
  // Cart Actions
  // ---------------------------------------------------------------------------

  void _addMenuItemToCart(MenuItem item) {
    setState(() {
      final existingIndex = _cartItems.indexWhere(
        (ci) => ci.menuItem?.id == item.id && ci.selectedModifiers.isEmpty,
      );
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity += 1;
      } else {
        _cartItems.add(CartItem(menuItem: item, quantity: 1));
      }
    });
  }

  Future<void> _openDealSelection(Deal deal) async {
    final choices = await showDialog<List<SelectedDealChoice>>(
      context: context,
      builder: (ctx) => DealSelectionDialog(
        deal: deal,
        availableMenuItems: _menuItems,
      ),
    );

    if (choices != null && mounted) {
      setState(() {
        _cartItems.add(CartItem(
          deal: deal,
          quantity: 1,
          selectedDealChoices: choices,
        ));
      });
    }
  }

  Future<void> _openModifierSelection(int index) async {
    final cartItem = _cartItems[index];
    if (cartItem.menuItem == null) return;

    final itemModifiers = _allModifiers.where(
      (m) => m.menuItemId == null || m.menuItemId == cartItem.menuItem!.id,
    ).toList();

    final groups = widget.catalogController == null ? <ModifierGroup>[] : await widget.catalogController!.getModifierGroups(menuItemId: cartItem.menuItem!.id);
    if (!mounted) return;
    final selected = await showDialog<List<Modifier>>(
      context: context,
      builder: (ctx) => ModifierSelectionDialog(
        itemName: cartItem.name,
        availableModifiers: itemModifiers,
        groups: groups,
        initialSelected: cartItem.selectedModifiers,
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _cartItems[index] = cartItem.copyWith(selectedModifiers: selected);
      });
    }
  }

  void _incrementCartItem(int index) {
    setState(() => _cartItems[index].quantity += 1);
  }

  void _decrementCartItem(int index) {
    setState(() {
      if (_cartItems[index].quantity > 1) {
        _cartItems[index].quantity -= 1;
      } else {
        _cartItems.removeAt(index);
      }
    });
  }

  void _removeCartItem(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  void _clearCart() {
    if (_cartItems.isEmpty) return;
    setState(() {
      _cartItems.clear();
      _selectedDiscount = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Checkout Execution
  // ---------------------------------------------------------------------------

  Future<void> _openTenderCheckout() async {
    if (_cartItems.isEmpty) return;

    final totals = _cartTotals;
    final completed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TenderCheckoutDialog(
        grandTotal: totals.grandTotal,
        onCompleteCheckout: (tenders) async {
            if (widget.orderController != null) {
              final result = await widget.orderController!.checkoutOrder(
                businessDayId: widget.businessDayId,
                shiftId: widget.shiftId,
                cashierId: widget.currentStaff.id,
                diningType: _selectedDiningType,
                items: List.of(_cartItems),
                discount: _selectedDiscount,
                payments: tenders,
              );

              // Decoupled hardware printing executed strictly AFTER transaction commit
              if (widget.reprintTrayController != null) {
                final isCashPaid = tenders.any((t) => t.method == PaymentMethod.cash);
                await widget.reprintTrayController!.dispatchOrderPrinting(
                  order: result.order,
                  isCashPaid: isCashPaid,
                );
              }

              if (mounted) {
                _showCheckoutSuccessBanner(result);
              }
            }
        },
      ),
    );

    if (completed == true && mounted) {
      _clearCart();
      await _refreshToken();
      widget.onOrderCompleted?.call();
    }
  }

  /// Instant checkout with exact cash on Numpad Enter
  Future<void> _handleExactCashCheckout() async {
    if (_cartItems.isEmpty) return;
    final totals = _cartTotals;

    try {
      if (widget.orderController != null) {
        final result = await widget.orderController!.checkoutOrder(
          businessDayId: widget.businessDayId,
          shiftId: widget.shiftId,
          cashierId: widget.currentStaff.id,
          diningType: _selectedDiningType,
          items: List.of(_cartItems),
          discount: _selectedDiscount,
          payments: [
            PaymentTender(
              method: PaymentMethod.cash,
              amountTendered: totals.grandTotal,
              changeReturned: 0.0,
            ),
          ],
        );

        // Decoupled hardware printing executed strictly AFTER transaction commit
        if (widget.reprintTrayController != null) {
          await widget.reprintTrayController!.dispatchOrderPrinting(
            order: result.order,
            isCashPaid: true,
          );
        }

        if (mounted) {
          _showCheckoutSuccessBanner(result);
        }
      }

      if (mounted) {
        _clearCart();
        await _refreshToken();
        widget.onOrderCompleted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed: $e')),
        );
      }
    }
  }

  void _showCheckoutSuccessBanner(CheckoutResult result) {
    final token = result.order.tokenDisplay;
    final total = _currencyFormat.format(result.order.grandTotal);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: WarmCounterColors.lightPrimaryAction,
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Order Placed! Token $token | Settled: Rs $total (${result.order.diningType.displayName})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (result.lowStockWarnings.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${result.lowStockWarnings.length} Low Stock Alert(s)',
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Keyboard Shortcuts Setup
  // ---------------------------------------------------------------------------

  Map<ShortcutActivator, VoidCallback> _buildKeyboardBindings() {
    final bindings = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () => _openTenderCheckout(),
      const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _handleExactCashCheckout(),
      const SingleActivator(LogicalKeyboardKey.escape): () => _clearCart(),
    };

    // F1 to F12 for category switching
    final fKeys = [
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.f2,
      LogicalKeyboardKey.f3,
      LogicalKeyboardKey.f4,
      LogicalKeyboardKey.f5,
      LogicalKeyboardKey.f6,
      LogicalKeyboardKey.f7,
      LogicalKeyboardKey.f8,
      LogicalKeyboardKey.f9,
      LogicalKeyboardKey.f10,
      LogicalKeyboardKey.f11,
      LogicalKeyboardKey.f12,
    ];

    for (int i = 0; i < fKeys.length && i < _categories.length; i++) {
      final catId = _categories[i].id;
      bindings[SingleActivator(fKeys[i])] = () {
        setState(() => _selectedCategoryId = catId);
      };
    }

    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: WarmCounterColors.lightPrimaryAction),
      );
    }

    return CallbackShortcuts(
      bindings: _buildKeyboardBindings(),
      child: Focus(
        autofocus: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Side: Catalog Grid & Controls (65%)
            Expanded(
              flex: 65,
              child: Padding(
                padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Dining Type Selector & Hotkey Info Row
                    _buildTopControlBar(),
                    const SizedBox(height: WarmCounterSpacing.space12),

                    // Category Tabs Bar
                    _buildCategoryTabsBar(),
                    const SizedBox(height: WarmCounterSpacing.space12),

                    // Items Grid
                    Expanded(
                      child: _buildCatalogGrid(),
                    ),
                  ],
                ),
              ),
            ),

            // Vertical Border Divider
            Container(width: 1, color: WarmCounterColors.lightBorder),

            // Right Side: Active Order Cart & Tender Panel (35%)
            Expanded(
              flex: 35,
              child: _buildCartPanel(),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Top Control Bar (Dining Type)
  // ---------------------------------------------------------------------------

  Widget _buildTopControlBar() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WarmCounterSpacing.space8,
      runSpacing: WarmCounterSpacing.space8,
      children: [
        // Dining Type Selector
        Wrap(
          spacing: WarmCounterSpacing.space8,
          runSpacing: WarmCounterSpacing.space8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: DiningType.values.map((type) {
            final isSelected = _selectedDiningType == type;
            return ChoiceChip(
              key: ValueKey('dining_type_${type.code}'),
              label: Text(type.displayName),
              selected: isSelected,
              selectedColor: WarmCounterColors.lightActiveNavHighlight,
              onSelected: (selected) {
                if (selected) setState(() => _selectedDiningType = type);
              },
            );
          }).toList(),
        ),

        // Actions & Hotkey Tooltip Hint
        Wrap(
          spacing: WarmCounterSpacing.space8,
          runSpacing: WarmCounterSpacing.space8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.end,
          children: [
            if (widget.orderController != null) _buildVoidOrderButton(),
            if (widget.reprintTrayController != null) _buildReprintTrayButton(),
            Text(
              '[Space] Tender | [Numpad Enter] Exact | [Esc] Clear',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: WarmCounterTypography.caption.copyWith(
                color: WarmCounterColors.lightSecondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVoidOrderButton() {
    return OutlinedButton.icon(
      key: const ValueKey('open_void_order_button'),
      icon: const Icon(
        Icons.cancel_outlined,
        size: 16,
        color: WarmCounterColors.lightDestructiveAction,
      ),
      label: const Text(
        'Void Order',
        style: TextStyle(
          color: WarmCounterColors.lightDestructiveAction,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: WarmCounterColors.lightDestructive),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(100, WarmCounterSpacing.minTouchTargetSize),
      ),
      onPressed: _openVoidOrderFlow,
    );
  }

  Future<void> _openVoidOrderFlow() async {
    if (widget.orderController == null) return;

    final isSupervisor = widget.currentStaff.canVoidOrders;
    final isVoidEnabled = await widget.orderController!.isCashierVoidEnabled();

    if (!isSupervisor && !isVoidEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cashier void requests are disabled by management.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final recentOrders = await widget.orderController!.getOrders(
      businessDayId: widget.businessDayId,
      limit: 10,
    );
    final settledOrders = recentOrders.where((o) => o.isSettled).toList();

    if (settledOrders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No settled orders available to void.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    final selectedOrder = await showDialog<Order>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Order to Void'),
        shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: settledOrders.length,
            itemBuilder: (ctx, i) {
              final o = settledOrders[i];
              return ListTile(
                key: ValueKey('select_order_to_void_${o.id}'),
                title: Text(
                  'Order #${o.id} • Token ${o.tokenDisplay}',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'Rs ${_currencyFormat.format(o.grandTotal)} • ${o.diningType.displayName}',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontSize: 12,
                    color: WarmCounterColors.lightSecondaryText,
                  ),
                ),
                onTap: () => Navigator.of(ctx).pop(o),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selectedOrder != null && mounted) {
      final auth = widget.authService ?? AuthService(database: widget.orderController!.database);
      final reprintTray = widget.reprintTrayController ??
          ReprintTrayController(hardwareAdapter: InMemoryHardwareAdapter());
      await showDialog<void>(
        context: context,
        builder: (ctx) => SupervisorVoidDialog(
          order: selectedOrder,
          cashierId: widget.currentStaff.id,
          orderController: widget.orderController!,
          authService: auth,
          reprintTrayController: reprintTray,
          onVoidSuccess: () {
            _refreshToken();
            widget.onOrderCompleted?.call();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Order #${selectedOrder.id} (${selectedOrder.tokenDisplay}) voided successfully.'),
              ),
            );
          },
        ),
      );
    }
  }

  Widget _buildReprintTrayButton() {
    return ListenableBuilder(
      listenable: widget.reprintTrayController!,
      builder: (context, _) {
        final hasFailures = widget.reprintTrayController!.hasFailures;
        final failedCount = widget.reprintTrayController!.failedCount;

        return OutlinedButton.icon(
          key: const ValueKey('open_reprint_tray_button'),
          icon: Icon(
            Icons.print_rounded,
            size: 16,
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
              fontSize: 12,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: hasFailures ? WarmCounterColors.lightDestructiveHighlight : null,
            side: BorderSide(
              color: hasFailures ? WarmCounterColors.lightDestructive : WarmCounterColors.lightBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(110, WarmCounterSpacing.minTouchTargetSize),
          ),
          onPressed: _openReprintTray,
        );
      },
    );
  }

  void _openReprintTray() {
    if (widget.reprintTrayController == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => ReprintTrayDialog(
        controller: widget.reprintTrayController!,
        currentStaff: widget.currentStaff,
        orderController: widget.orderController,
        authService: widget.authService ?? (widget.orderController != null ? AuthService(database: widget.orderController!.database) : null),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Category Tabs Bar
  // ---------------------------------------------------------------------------

  Widget _buildCategoryTabsBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // Deals & Combos Tab
          if (_deals.isNotEmpty)
            _buildTabChip(
              id: null,
              label: 'Deals & Combos (${_deals.length})',
              isSelected: _selectedCategoryId == null,
            ),

          // Categories
          ..._categories.asMap().entries.map((entry) {
            final index = entry.key;
            final cat = entry.value;
            final fKey = index < 12 ? 'F${index + 1}' : '';
            final label = fKey.isNotEmpty ? '$fKey: ${cat.name}' : cat.name;

            return _buildTabChip(
              id: cat.id,
              label: label,
              isSelected: _selectedCategoryId == cat.id,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTabChip({
    required int? id,
    required String label,
    required bool isSelected,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: WarmCounterSpacing.space8),
      child: FilterChip(
        key: ValueKey('category_tab_${id ?? 'deals'}'),
        label: Text(label),
        selected: isSelected,
        selectedColor: WarmCounterColors.lightActiveNavHighlight,
        checkmarkColor: WarmCounterColors.lightPrimaryAction,
        onSelected: (_) => setState(() => _selectedCategoryId = id),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Catalog Grid (Menu Items or Deals)
  // ---------------------------------------------------------------------------

  Widget _buildCatalogGrid() {
    if (_selectedCategoryId == null) {
      // Show Deals Grid
      return GridView.builder(
        key: const ValueKey('deals_grid'),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 1.1,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _deals.length,
        itemBuilder: (context, index) {
          final deal = _deals[index];
          return _buildDealTile(deal);
        },
      );
    }

    // Show Menu Items Grid for Selected Category
    final items = _menuItems.where((i) => i.categoryId == _selectedCategoryId).toList();

    if (items.isEmpty) {
      return Center(
        child: Text(
          'No active items in this category.',
          style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
        ),
      );
    }

    return GridView.builder(
      key: ValueKey('menu_grid_$_selectedCategoryId'),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildMenuItemTile(item);
      },
    );
  }

  Widget _buildMenuItemTile(MenuItem item) {
    return InkWell(
      key: ValueKey('menu_item_tile_${item.id}'),
      onTap: () => _addMenuItemToCart(item),
      borderRadius: WarmCounterSpacing.panelBorderRadius,
      child: Container(
        padding: const EdgeInsets.all(WarmCounterSpacing.space12),
        decoration: BoxDecoration(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: WarmCounterColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Rs ${_currencyFormat.format(item.basePrice)}',
              style: WarmCounterTypography.tabularPrice.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WarmCounterColors.lightPrimaryAction,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDealTile(Deal deal) {
    return InkWell(
      key: ValueKey('deal_tile_${deal.id}'),
      onTap: () => _openDealSelection(deal),
      borderRadius: WarmCounterSpacing.panelBorderRadius,
      child: Container(
        padding: const EdgeInsets.all(WarmCounterSpacing.space12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8E9), // Light green tint for Deals
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: WarmCounterColors.lightPrimaryAction, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightPrimaryAction,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DEAL',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  deal.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              'Rs ${_currencyFormat.format(deal.basePrice)}',
              style: WarmCounterTypography.tabularPrice.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WarmCounterColors.lightPrimaryAction,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Right Cart & Checkout Panel
  // ---------------------------------------------------------------------------

  Widget _buildCartPanel() {
    final totals = _cartTotals;
    final tokenFormatted = '#${_nextTokenNumber.toString().padLeft(2, '0')}';

    return Container(
      color: WarmCounterColors.lightCardBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cart Header with Next Token & Dining Type
          Container(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: WarmCounterColors.lightBorder)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: WarmCounterColors.lightActiveNavHighlight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Token $tokenFormatted',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _selectedDiningType.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: WarmCounterTypography.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: WarmCounterColors.lightSecondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_cartItems.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_rounded, size: 22),
                    tooltip: 'Clear Cart [Esc]',
                    onPressed: _clearCart,
                  ),
              ],
            ),
          ),

          // Cart Items List
          Expanded(
            child: _cartItems.isEmpty
                ? Center(
                    child: Text(
                      'Cart is empty.\nTap items on the left to ring up an order.',
                      textAlign: TextAlign.center,
                      style: WarmCounterTypography.bodyMedium.copyWith(
                        color: WarmCounterColors.lightSecondaryText,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                    itemCount: _cartItems.length,
                    separatorBuilder: (context, _) => const Divider(height: 12),
                    itemBuilder: (context, index) {
                      final item = _cartItems[index];
                      return _buildCartItemRow(item, index);
                    },
                  ),
          ),

          // Pre-Approved Discounts Row (No PIN friction)
          if (_discounts.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: WarmCounterColors.lightPageBackground,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'Discount: ',
                      style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.bold),
                    ),
                    ..._discounts.map((d) {
                      final isSelected = _selectedDiscount?.id == d.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: ValueKey('discount_chip_${d.id}'),
                          label: Text(d.name, style: const TextStyle(fontSize: 11)),
                          selected: isSelected,
                          onSelected: (chosen) {
                            setState(() => _selectedDiscount = chosen ? d : null);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],

          // Summary & Tender Action Bar
          Container(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            decoration: const BoxDecoration(
              color: WarmCounterColors.lightPageBackground,
              border: Border(top: BorderSide(color: WarmCounterColors.lightBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSummaryLine('Subtotal', 'Rs ${_currencyFormat.format(totals.subtotal)}'),
                if (totals.discountAmount > 0)
                  _buildSummaryLine(
                    'Discount (${_selectedDiscount?.name})',
                    '-Rs ${_currencyFormat.format(totals.discountAmount)}',
                    isDiscount: true,
                  ),
                if (totals.taxAmount > 0)
                  _buildSummaryLine(
                    'Tax (Inclusive)',
                    'Rs ${_currencyFormat.format(totals.taxAmount)}',
                    isTax: true,
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Grand Total:',
                        style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
                      ),
                    ),
                    Text(
                      'Rs ${_currencyFormat.format(totals.grandTotal)}',
                      style: WarmCounterTypography.orderTotal.copyWith(
                        color: WarmCounterColors.lightPrimaryAction,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space12),

                // Big Green Checkout Button
                ElevatedButton.icon(
                  key: const ValueKey('proceed_to_tender_button'),
                  icon: const Icon(Icons.point_of_sale_rounded, size: 24),
                  label: const Text(
                    'Charge [Space]',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _cartItems.isEmpty ? null : _openTenderCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 54),
                    shape: const RoundedRectangleBorder(
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemRow(CartItem item, int index) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quantity Controls
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _decrementCartItem(index),
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              child: const SizedBox(
                width: WarmCounterSpacing.touchTargetMin,
                height: WarmCounterSpacing.touchTargetMin,
                child: Center(
                  child: Icon(Icons.remove_circle_outline, size: 22),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.0),
              child: Text(
                '${item.quantity}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            InkWell(
              onTap: () => _incrementCartItem(index),
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              child: const SizedBox(
                width: WarmCounterSpacing.touchTargetMin,
                height: WarmCounterSpacing.touchTargetMin,
                child: Center(
                  child: Icon(Icons.add_circle_outline, size: 22),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),

        // Item Details & Modifiers
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),

              // Deal choices preview
              if (item.selectedDealChoices.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: item.selectedDealChoices.map((c) {
                    return Text(
                      '• ${c.menuItemName}${c.upgradePrice > 0 ? " (+Rs ${c.upgradePrice.toStringAsFixed(0)})" : ""}',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    );
                  }).toList(),
                ),

              // Modifiers preview
              if (item.selectedModifiers.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: item.selectedModifiers.map((m) {
                    return Text(
                      '• ${m.name}',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightPrimaryAction),
                    );
                  }).toList(),
                ),

              // Customize button for Menu Items
              if (item.menuItem != null)
                InkWell(
                  key: ValueKey('customize_item_$index'),
                  onTap: () => _openModifierSelection(index),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      'Customize Modifiers',
                      style: WarmCounterTypography.caption.copyWith(
                        color: WarmCounterColors.lightPrimaryAction,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Price
        Text(
          'Rs ${_currencyFormat.format(item.totalPrice)}',
          style: WarmCounterTypography.tabularPrice.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(width: 4),

        // Delete button
        InkWell(
          onTap: () => _removeCartItem(index),
          borderRadius: WarmCounterSpacing.controlBorderRadius,
          child: const SizedBox(
            width: WarmCounterSpacing.touchTargetMin,
            height: WarmCounterSpacing.touchTargetMin,
            child: Center(
              child: Icon(Icons.close, size: 18, color: WarmCounterColors.lightSecondaryText),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryLine(String title, String value, {bool isDiscount = false, bool isTax = false}) {
    Color color = WarmCounterColors.lightPrimaryText;
    if (isDiscount) color = WarmCounterColors.lightDestructiveAction;
    if (isTax) color = WarmCounterColors.lightSecondaryText;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: WarmCounterTypography.bodyMedium.copyWith(color: color))),
          Text(value, style: WarmCounterTypography.tabularPrice.copyWith(color: color)),
        ],
      ),
    );
  }
}
