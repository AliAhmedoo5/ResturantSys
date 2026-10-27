import '../../core/settings/keyboard_shortcut_controller.dart';
import 'dart:convert';
import 'customer_directory.dart';
import '../../core/orders/customer_controller.dart';
import '../../core/delivery/delivery_controller.dart';
import '../../core/orders/paisa_engine.dart';
import '../delivery/delivery_details_dialog.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/staff.dart';
import '../../core/catalog/catalog_and_recipe_controller.dart';
import '../../core/catalog/catalog_media_service.dart';
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
import '../../core/theme/theme.dart';
import 'cashier_order_revision_dialog.dart';
import 'cashier_orders_panel.dart';
import 'deal_selection_dialog.dart';
import 'modifier_selection_dialog.dart';
import 'supervisor_void_dialog.dart';
import 'tender_checkout_dialog.dart';

/// High-speed touch grid billing and checkout interface for counter cashiers.
class CounterBillingWorkspace extends StatefulWidget {
  const CounterBillingWorkspace({
    super.key,
    this.orderController,
    this.shortcutController,
    this.catalogController,
    this.mediaService,
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
    this.initialMenuItemImages,
    this.initialDealImages,
    this.imageBuilder,
  });

  final OrderAndCheckoutController? orderController;
  final KeyboardShortcutController? shortcutController;
  final CatalogAndRecipeController? catalogController;
  final CatalogMediaService? mediaService;
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
  final Map<int, String>? initialMenuItemImages;
  final Map<int, String>? initialDealImages;
  final Widget Function(BuildContext context, File file)? imageBuilder;

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
  Map<int, String> _menuItemImages = {};
  Map<int, String> _dealImages = {};
  bool _isLoading = true;
  Map<String, String> _shortcutKeys = Map.of(KeyboardShortcutController.defaults);
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _searchQuery = '';

  // Active View State
  int? _selectedCategoryId; // null = Deals Tab
  DiningType _selectedDiningType = DiningType.dineIn;
  DiscountPreset? _selectedDiscount;

  // Cart State
  final List<CartItem> _cartItems = [];
  int _nextTokenNumber = 1;
  DeliveryDetails? _deliveryDetails;
  bool _checkoutOpen = false;
  bool _ordersOpen = false;
  Customer? _customer;
  int? _recalledHoldId;
  bool _draftBusy = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    final db = widget.orderController?.database ?? widget.catalogController?.database;
    final shortcuts = widget.shortcutController ?? (db == null ? null : KeyboardShortcutController(db));
    if (shortcuts != null) {
      shortcuts.load().then((keys) {
        if (mounted) setState(() => _shortcutKeys = keys);
      }).catchError((Object error) {
        if (mounted) {
          setState(() => _shortcutKeys = {});
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Keyboard shortcuts unavailable: $error')));
        }
      });
    }
    _searchFocus.addListener(() { if (mounted) setState(() {}); });
    if (widget.initialMenuItemImages != null) {
      _menuItemImages = Map.from(widget.initialMenuItemImages!);
    }
    if (widget.initialDealImages != null) {
      _dealImages = Map.from(widget.initialDealImages!);
    }

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

    final service = widget.mediaService ??
        (widget.catalogController != null
            ? widget.catalogController!.mediaService
            : null);
    Map<int, String> itemImages = {};
    Map<int, String> dealImages = {};
    if (service != null) {
      try {
        final rawItemImages = await service.getPrimaryImagesForEntities('menu_item');
        final rawDealImages = await service.getPrimaryImagesForEntities('deal');
        itemImages = rawItemImages.map((k, v) => MapEntry(k, v.relativeFilePath));
        dealImages = rawDealImages.map((k, v) => MapEntry(k, v.relativeFilePath));
      } catch (_) {
        // Suppress image lookup errors
      }
    }

    if (mounted) {
      setState(() {
        _categories = categories;
        _menuItems = menuItems;
        _deals = deals;
        _discounts = discounts;
        _allModifiers = modifiers;
        _menuItemImages = itemImages;
        _dealImages = dealImages;
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
        diningType: _selectedDiningType, cashierId: widget.currentStaff.id,
      );
    }

    double subtotal = 0.0;
    for (final item in _cartItems) {
      subtotal += item.totalPrice;
    }
    double discountAmount = 0.0;
    if (_selectedDiscount != null) {
      discountAmount = _selectedDiscount!.calculateDiscount(subtotal, items: _cartItems, diningMode: _selectedDiningType.code, cashierId: widget.currentStaff.id);
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
      final draft = CartItem(deal: deal, quantity: 1, selectedDealChoices: choices);
      final modifiers = await _chooseDealModifiers(draft);
      if (modifiers == null || !mounted) return;
      setState(() => _cartItems.add(draft.copyWith(selectedModifiers: modifiers)));
    }
  }

  Future<List<Modifier>?> _chooseDealModifiers(CartItem item) async {
    final result = <Modifier>[];
    // Global options apply to the whole deal. Item-specific groups are chosen
    // once per component menu item, including repeated portions of that item.
    final globals = _allModifiers.where((m) => m.menuItemId == null).toList();
    if (globals.isNotEmpty) {
      final selected = await showDialog<List<Modifier>>(context: context, builder: (_) => ModifierSelectionDialog(
        itemName: item.name, availableModifiers: globals,
        initialSelected: item.selectedModifiers.where((m) => m.menuItemId == null).toList(),
      ));
      if (selected == null || !mounted) return null;
      result.addAll(selected);
    }
    for (final id in item.selectedDealChoices.map((c) => c.menuItemId).toSet()) {
      final options = _allModifiers.where((m) => m.menuItemId == id).toList();
      final groups = widget.catalogController == null
          ? <ModifierGroup>[for (final option in options) if (option.group != null) option.group!]
          : await widget.catalogController!.getModifierGroups(menuItemId: id);
      if (!mounted) return null;
      if (options.isEmpty && groups.isEmpty) continue;
      final name = item.selectedDealChoices.firstWhere((c) => c.menuItemId == id).menuItemName;
      final selected = await showDialog<List<Modifier>>(context: context, builder: (_) => ModifierSelectionDialog(
        itemName: name, availableModifiers: options, groups: groups,
        initialSelected: item.selectedModifiers.where((m) => m.menuItemId == id).toList(),
      ));
      if (selected == null || !mounted) return null;
      result.addAll(selected);
    }
    return result;
  }

  Future<void> _openModifierSelection(int index) async {
    final cartItem = _cartItems[index];
    if (cartItem.isDeal) {
      final selected = await _chooseDealModifiers(cartItem);
      if (selected != null && mounted) setState(() => _cartItems[index] = cartItem.copyWith(selectedModifiers: selected));
      return;
    }

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
      _deliveryDetails = null;
      _customer = null;
      _recalledHoldId = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Checkout Execution
  // ---------------------------------------------------------------------------

  Future<void> _draftAction(Future<void> Function() action) async {
    if (_draftBusy || _checkoutOpen) return;
    setState(() => _draftBusy = true);
    try { await action(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
    finally { if (mounted) setState(() => _draftBusy = false); }
  }

  Future<void> _hold() => _draftAction(() async {
    final controller = widget.orderController;
    if (controller == null || _cartItems.isEmpty) return;
    final label = TextEditingController(text: _customer?.name ?? 'Cart ${DateFormat('HH:mm').format(DateTime.now())}');
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Hold cart'), content: TextField(controller: label, decoration: const InputDecoration(labelText: 'Label')),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save hold'))]));
    final text = label.text;
    label.dispose();
    if (confirmed != true || !mounted) return;
    await controller.holdCart(cashierId: widget.currentStaff.id, label: text, items: _cartItems,
      diningType: _selectedDiningType, delivery: _deliveryDetails, customerId: _customer?.id, discountId: _selectedDiscount?.id, previousHoldId: _recalledHoldId);
    if (mounted) _clearCart();
  });

  Future<void> _recall() => _draftAction(() async {
    final controller = widget.orderController;
    if (controller == null) return;
    if (_cartItems.isNotEmpty) throw StateError('Hold or clear the current cart before recalling another.');
    final holds = List<Map<String, Object?>>.of(await controller.getHolds(widget.currentStaff.id));
    if (!mounted) return;
    final selected = await showDialog<Map<String, Object?>>(context: context, builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
      title: const Text('Recall held cart'), content: SizedBox(width: 460, height: 360,
        child: holds.isEmpty ? const Center(child: Text('No held carts.')) : ListView(children: [
          for (final hold in holds) ListTile(title: Text(hold['label'] as String), subtitle: Text(hold['created_at'] as String),
            onTap: () => Navigator.pop(context, hold), trailing: IconButton(tooltip: 'Discard hold', icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
                  title: const Text('Discard held cart?'), content: Text(hold['label'] as String),
                  actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard'))]));
                if (confirmed != true) return;
                try {
                  await controller.removeHold(widget.currentStaff.id, hold['id'] as int);
                  if (context.mounted) update(() => holds.remove(hold));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              })),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))])));
    if (selected == null || !mounted) return;
    final payload = jsonDecode(selected['payload'] as String) as Map<String, dynamic>;
    final lines = await controller.restoreDraftLines(payload['items'] as List<dynamic>);
    Customer? customer;
    final customerId = payload['customer_id'] as int?;
    if (customerId != null) {
      final rows = await controller.database.rawQuery('SELECT c.* FROM customers c WHERE c.id = (SELECT COALESCE(merged_into, id) FROM customers WHERE id = ?)', [customerId]);
      if (rows.isNotEmpty) customer = Customer.fromMap(rows.single);
    }
    DiscountPreset? discount;
    final discounts = await CatalogAndRecipeController(database: controller.database).getDiscountPresets(activeOnly: true);
    for (final current in discounts) { if (current.id == payload['discount_id']) discount = current; }
    final raw = payload['delivery'] as Map<String, dynamic>?;
    final delivery = raw == null ? null : DeliveryDetails(areaId: raw['area_id'] as int, quotedFeePaisa: raw['fee'] as int,
      phone: raw['phone'] as String, customerName: raw['name'] as String, fullAddress: raw['address'] as String,
      landmark: raw['landmark'] as String, notes: raw['notes'] as String);
    if (!mounted) return;
    setState(() { _cartItems.addAll(lines); _selectedDiningType = DiningType.fromCode(payload['dining_type'] as String);
      _deliveryDetails = delivery; _selectedDiscount = discount; _customer = customer; _recalledHoldId = selected['id'] as int; });
  });

  Future<void> _customers() => _draftAction(() async {
    final controller = widget.orderController;
    if (controller == null) return;
    final selection = await showDialog<CustomerSelection>(context: context, builder: (context) => Dialog(
      child: SizedBox(width: 900, height: 620, child: Column(children: [
        Row(children: [const Expanded(child: Padding(padding: EdgeInsets.all(16), child: Text('Customer Directory'))),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
        Expanded(child: CustomerDirectory(controller: CustomerController(controller.database), staffId: widget.currentStaff.id)),
      ]))));
    if (selection == null || !mounted) return;
    List<CartItem>? lines;
    DiningType? diningType;
    if (selection.repeatOrderId != null) {
      if (_cartItems.isNotEmpty) throw StateError('Hold or clear the current cart before repeating an order.');
      lines = await controller.repeatOrder(cashierId: widget.currentStaff.id, orderId: selection.repeatOrderId!);
      diningType = (await controller.getOrder(selection.repeatOrderId!)).diningType;
    }
    if (!mounted) return;
    setState(() {
      _customer = selection.customer;
      if (lines != null) { _cartItems.addAll(lines); _selectedDiningType = diningType!; _selectedDiscount = null; _deliveryDetails = null; }
    });
  });

  Future<void> _openTenderCheckout() async {
    if (_cartItems.isEmpty || _checkoutOpen || _draftBusy) return;
    _checkoutOpen = true;
    try {
    if (widget.catalogController != null) {
      final fresh = await widget.catalogController!.getDiscountPresets(activeOnly: true);
      if (!mounted) return;
      final selected = _selectedDiscount;
      final matching = selected == null ? <DiscountPreset>[] : fresh.where((d) => d.id == selected.id).toList();
      final changed = selected != null && (matching.isEmpty || jsonEncode(matching.single.toMap()) != jsonEncode(selected.toMap()));
      setState(() { _discounts = fresh; if (changed) _selectedDiscount = null; });
      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Discount terms changed. Review the refreshed discounts and total before payment.')));
        return;
      }
    }
    if (_selectedDiningType == DiningType.delivery) {
      if (widget.orderController == null) return;
      final details = await showDialog<DeliveryDetails>(context: context, builder: (_) => DeliveryDetailsDialog(
        controller: DeliveryController(database: widget.orderController!.database),
        foodTotalPaisa: PaisaEngine.rupeesToPaisa(_cartTotals.grandTotal), initial: _deliveryDetails,
        customerPhone: _customer?.phone, customerName: _customer?.name));
      if (details == null || !mounted) return;
      _deliveryDetails = details;
      if (_customer != null && DeliveryController.normalizePhone(details.phone) != _customer!.phone) _customer = null;
    } else {
      _deliveryDetails = null;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Customer Details'),
          content: const Text('No delivery details are required for this walk-in order.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back to cart')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Skip delivery details')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final totals = _cartTotals;
    final completed = await showDialog<bool>(
      context: context,
      builder: (ctx) => TenderCheckoutDialog(
        roundPhysicalCash: true,
        allowCod: _selectedDiningType == DiningType.delivery,
        grandTotal: totals.grandTotal + (_deliveryDetails?.quotedFeePaisa ?? 0) / 100,
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
                delivery: _deliveryDetails,
                customerId: _customer?.id,
                heldCartId: _recalledHoldId,
              );

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
    } finally { _checkoutOpen = false; }
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
                'Order Placed! Token $token | ${result.order.paymentStatus == 'COLLECTION_DUE' ? 'Collection Due' : 'Settled'}: Rs $total (${result.order.diningType.displayName})',
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
    final callbacks = <String, VoidCallback>{
      'checkout': () => _openTenderCheckout(), 'checkoutAlternate': () => _openTenderCheckout(),
      'clear': _clearCart, 'hold': () => _hold(), 'recall': () => _recall(),
      'customers': () => _customers(), 'search': () => _searchFocus.requestFocus(),
      for (var i = 0; i < _categories.length && i < 12; i++)
        'category${i + 1}': () => setState(() => _selectedCategoryId = _categories[i].id),
    };
    final bindings = <ShortcutActivator, VoidCallback>{};
    for (final entry in _shortcutKeys.entries) {
      if (entry.value.isEmpty || !callbacks.containsKey(entry.key)) continue;
      final label = entry.value.replaceFirst('Shift+', '');
      final key = label == 'Space' ? LogicalKeyboardKey.space
        : label == 'Escape' ? LogicalKeyboardKey.escape
        : label == 'Numpad Enter' ? LogicalKeyboardKey.numpadEnter
        : LogicalKeyboardKey.findKeyByKeyId(LogicalKeyboardKey.f1.keyId + int.parse(label.substring(1)) - 1)!;
      bindings[SingleActivator(key, shift: entry.value.startsWith('Shift+'), includeRepeats: false)] = () {
        final focusedContext = FocusManager.instance.primaryFocus?.context;
        final typing = focusedContext?.widget is EditableText || focusedContext?.findAncestorWidgetOfExactType<EditableText>() != null;
        if (_draftBusy || typing || ModalRoute.of(context)?.isCurrent != true || !widget.currentStaff.role.isCashier || !widget.currentStaff.isActive || !widget.currentStaff.loginEnabled) return;
        callbacks[entry.key]!();
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
      bindings: _draftBusy ? const <ShortcutActivator, VoidCallback>{} : _buildKeyboardBindings(),
      child: AbsorbPointer(absorbing: _draftBusy, child: Focus(
        autofocus: true,
        child: LayoutBuilder(builder: (context, constraints) {
          final cartWidth = (constraints.maxWidth * 0.32).clamp(300.0, 360.0);
          return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The catalog fills the space left by the bounded cart panel.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const ValueKey('catalog_search'),
                      controller: _searchController,
                      focusNode: _searchFocus,
                      onEditingComplete: _searchFocus.unfocus,
                      onTapOutside: (_) => _searchFocus.unfocus(),
                      onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search menu items…',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isEmpty ? null : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Dining Type Selector & Hotkey Info Row
                    _buildTopControlBar(),
                    const SizedBox(height: WarmCounterSpacing.space12),

                    // Category Tabs Bar
                    _buildCategoryTabsBar(),
                    const SizedBox(height: WarmCounterSpacing.space12),

                    // Items Grid
                    Expanded(
                      child: _ordersOpen && widget.orderController != null
                          ? CashierOrdersPanel(controller: widget.orderController!,
                              key: ValueKey('orders_${widget.currentStaff.id}_${widget.businessDayId}'),
                              cashierId: widget.currentStaff.id, businessDayId: widget.businessDayId)
                          : _buildCatalogGrid(),
                    ),
                  ],
                ),
              ),
            ),

            // Vertical Border Divider
            Container(width: 1, color: WarmCounterColors.lightBorder),

            // Keep totals and checkout pinned without stretching on wide displays.
            SizedBox(
              width: cartWidth,
              child: _buildCartPanel(),
            ),
          ],
          );
        }),
      )),
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
              selectedColor: StreetFoodMafiaColors.cartelYellow,
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
            if (widget.orderController != null && widget.currentStaff.isActive && widget.currentStaff.canAccessRegister)
              ElevatedButton.icon(key: const ValueKey('open_order_status_button'),
                onPressed: () => setState(() => _ordersOpen = !_ordersOpen),
                icon: const Icon(Icons.receipt_long), label: Text(_ordersOpen ? 'Back to Menu' : 'Orders')),
            if (widget.orderController != null) _buildReviseOrderButton(),
            if (widget.orderController != null) _buildVoidOrderButton(),
            Text(
              'Checkout: ${_shortcutKeys['checkout'] ?? ''} | Clear: ${_shortcutKeys['clear'] ?? ''}',
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

  Widget _buildReviseOrderButton() {
    return ElevatedButton.icon(
      key: const ValueKey('open_revise_order_button'),
      icon: const Icon(
        Icons.edit_note,
        size: 16,
      ),
      label: const Text(
        'Revise / Cancel',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: WarmCounterColors.lightWarningHighlight,
        foregroundColor: WarmCounterColors.lightPrimaryText,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(110, WarmCounterSpacing.minTouchTargetSize),
      ),
      onPressed: _openReviseOrderFlow,
    );
  }

  Future<void> _openReviseOrderFlow() async {
    if (widget.orderController == null) return;

    final recentOrders = await widget.orderController!.getOrders(
      businessDayId: widget.businessDayId,
      limit: 15,
    );
    final eligibleOrders = recentOrders
        .where((o) => !o.isVoided && (!o.isCancelled || o.isRefundPending))
        .toList();

    if (eligibleOrders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active orders available to revise or cancel.'),
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
        title: const Text('Select Order to Revise / Cancel'),
        shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
        content: SizedBox(
          width: 440,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: eligibleOrders.length,
            itemBuilder: (ctx, i) {
              final o = eligibleOrders[i];
              return ListTile(
                key: ValueKey('select_order_to_revise_${o.id}'),
                title: Text(
                  'Order #${o.id} • Token ${o.tokenDisplay}',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  'Rs ${_currencyFormat.format(o.grandTotal)} • Stage: ${o.tokenStatus.displayName} • ${o.diningType.displayName}',
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
      await showDialog<void>(
        context: context,
        builder: (ctx) => CashierOrderRevisionDialog(
          order: selectedOrder,
          cashierId: widget.currentStaff.id,
          shiftId: widget.shiftId,
          orderController: widget.orderController!,
          catalogController: widget.catalogController,
          onRevisionCompleted: () {
            _refreshToken();
            widget.onOrderCompleted?.call();
          },
        ),
      );
    }
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
      await showDialog<void>(
        context: context,
        builder: (ctx) => SupervisorVoidDialog(
          order: selectedOrder,
          cashierId: widget.currentStaff.id,
          orderController: widget.orderController!,
          authService: auth,
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

  // ---------------------------------------------------------------------------
  // Category Tabs Bar
  // ---------------------------------------------------------------------------

  Widget _buildCategoryTabsBar() {
    return SizedBox(
      height: 48,
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
            final fKey = _shortcutKeys['category${index + 1}'] ?? '';
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
        label: Text(label, style: TextStyle(color: isSelected
            ? StreetFoodMafiaColors.textOnPrimary : StreetFoodMafiaColors.offWhite)),
        selected: isSelected,
        selectedColor: StreetFoodMafiaColors.cartelYellow,
        checkmarkColor: StreetFoodMafiaColors.textOnPrimary,
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
      final deals = _deals.where((deal) => deal.name.toLowerCase().contains(_searchQuery)).toList();
      return GridView.builder(
        key: const ValueKey('deals_grid'),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 260,
          mainAxisExtent: 240,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: deals.length,
        itemBuilder: (context, index) {
          final deal = deals[index];
          return _buildDealTile(deal);
        },
      );
    }

    // Show Menu Items Grid for Selected Category
    final items = _menuItems.where((i) => i.categoryId == _selectedCategoryId &&
        i.name.toLowerCase().contains(_searchQuery)).toList();

    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'No active items in this category.' : 'No items match your search.',
          style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
        ),
      );
    }

    return GridView.builder(
      key: ValueKey('menu_grid_$_selectedCategoryId'),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 240,
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

  File? _resolveImageFile(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    File file;
    if (widget.mediaService != null) {
      file = widget.mediaService!.resolveFile(relativePath);
    } else if (widget.catalogController != null) {
      file = widget.catalogController!.mediaService.resolveFile(relativePath);
    } else {
      file = File(relativePath);
    }
    if (!file.existsSync()) return null;
    return file;
  }

  Widget _buildItemPlaceholder(MenuItem item) {
    return Container(
      color: WarmCounterColors.lightSurfaceMuted,
      child: Center(
        child: Icon(
          Icons.restaurant_outlined,
          color: WarmCounterColors.lightSecondaryText.withValues(alpha: 0.5),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildDealPlaceholder(Deal deal) {
    return Container(
      color: StreetFoodMafiaColors.darkNavy,
      child: Center(
        child: Icon(
          Icons.local_offer_outlined,
          color: StreetFoodMafiaColors.burntGold.withValues(alpha: 0.7),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildSafeImage(File file, {required Widget Function() placeholder}) {
    if (!file.existsSync()) return placeholder();
    if (widget.imageBuilder != null) {
      return widget.imageBuilder!(context, file);
    }
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => placeholder(),
    );
  }

  Widget _buildMenuItemTile(MenuItem item) {
    final imageFile = _resolveImageFile(_menuItemImages[item.id]);

    return InkWell(
      key: ValueKey('menu_item_tile_${item.id}'),
      onTap: () => _addMenuItemToCart(item),
      borderRadius: WarmCounterSpacing.panelBorderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: WarmCounterColors.lightCardBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: WarmCounterColors.lightBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imageFile != null
                  ? _buildSafeImage(imageFile, placeholder: () => _buildItemPlaceholder(item))
                  : _buildItemPlaceholder(item),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WarmCounterSpacing.space8,
                vertical: WarmCounterSpacing.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs ${_currencyFormat.format(item.basePrice)}',
                    style: WarmCounterTypography.tabularPrice.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WarmCounterColors.lightPrimaryAction,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDealTile(Deal deal) {
    final imageFile = _resolveImageFile(_dealImages[deal.id]);

    return InkWell(
      key: ValueKey('deal_tile_${deal.id}'),
      onTap: () => _openDealSelection(deal),
      borderRadius: WarmCounterSpacing.panelBorderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: StreetFoodMafiaColors.cardSurface,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          border: Border.all(color: StreetFoodMafiaColors.burntGold, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageFile != null
                      ? _buildSafeImage(imageFile, placeholder: () => _buildDealPlaceholder(deal))
                      : _buildDealPlaceholder(deal),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: WarmCounterColors.lightPrimaryAction,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'DEAL',
                        style: TextStyle(color: StreetFoodMafiaColors.textOnPrimary, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WarmCounterSpacing.space8,
                vertical: WarmCounterSpacing.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    deal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs ${_currencyFormat.format(deal.basePrice)}',
                    style: WarmCounterTypography.tabularPrice.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WarmCounterColors.lightPrimaryAction,
                    ),
                  ),
                ],
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
                    icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                    tooltip: 'Clear Cart [${_shortcutKeys['clear'] ?? ''}]',
                    onPressed: _clearCart,
                  ),
              ],
            ),
          ),

          if (widget.orderController != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Wrap(spacing: 4, children: [
            TextButton.icon(onPressed: _draftBusy || _cartItems.isEmpty ? null : _hold,
              icon: const Icon(Icons.pause_circle_outline), label: const Text('Hold')),
            TextButton.icon(onPressed: _draftBusy ? null : _recall,
              icon: const Icon(Icons.restore), label: const Text('Recall')),
            TextButton.icon(onPressed: _draftBusy ? null : _customers,
              icon: const Icon(Icons.people_outline), label: Text(_customer?.name ?? 'Customers')),
          ])),
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
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 112),
                child: SingleChildScrollView(child: Wrap(
                spacing: 6,
                runSpacing: 4,
                  children: [
                    Text(
                      'Discount: ',
                      style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.bold),
                    ),
                    ..._discounts.where((d) => d.id == _selectedDiscount?.id || d.calculateDiscount(
                      _cartItems.fold<double>(0, (sum, item) => sum + item.totalPrice), items: _cartItems,
                      diningMode: _selectedDiningType.code, cashierId: widget.currentStaff.id) > 0).map((d) {
                      final isSelected = _selectedDiscount?.id == d.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: ValueKey('discount_chip_${d.id}'),
                          label: Text(d.name, style: TextStyle(fontSize: 11, color: isSelected
                              ? StreetFoodMafiaColors.textOnPrimary : StreetFoodMafiaColors.offWhite)),
                          selected: isSelected,
                          onSelected: (chosen) {
                            setState(() => _selectedDiscount = chosen ? d : null);
                          },
                        ),
                      );
                    }),
                  ],
                )),
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
                        fontSize: 26,
                        color: WarmCounterColors.lightPrimaryAction,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space12),

                // Big Green Checkout Button
                ElevatedButton.icon(
                  key: const ValueKey('proceed_to_tender_button'),
                  icon: const Icon(Icons.point_of_sale_outlined, size: 24),
                  label: const Text(
                    'Charge [${_shortcutKeys['checkout'] ?? ''}]',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _cartItems.isEmpty ? null : _openTenderCheckout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: StreetFoodMafiaColors.cartelYellow,
                    foregroundColor: StreetFoodMafiaColors.textOnPrimary,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text(
            item.name,
            key: ValueKey('cart_item_name_$index'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          )),
          if (item.menuItem != null || item.deal != null)
            IconButton(
              key: ValueKey('customize_item_$index'),
              tooltip: 'Customize Modifiers',
              onPressed: () => _openModifierSelection(index),
              icon: const Icon(Icons.tune_outlined, size: 18, color: WarmCounterColors.lightPrimaryAction),
            ),
          IconButton(
            tooltip: 'Remove ${item.name}',
            onPressed: () => _removeCartItem(index),
            icon: const Icon(Icons.close, size: 18, color: WarmCounterColors.lightSecondaryText),
          ),
        ]),
        if (item.selectedDealChoices.isNotEmpty)
          Wrap(spacing: 4, children: item.selectedDealChoices.map((choice) => Text(
            '• ${choice.menuItemName}${choice.upgradePrice > 0 ? " (+Rs ${choice.upgradePrice.toStringAsFixed(0)})" : ""}',
            style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
          )).toList()),
        if (item.selectedModifiers.isNotEmpty)
          Wrap(spacing: 4, children: item.selectedModifiers.map((modifier) => Text(
            '• ${modifier.name}',
            style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightPrimaryAction),
          )).toList()),
        Row(children: [
          IconButton(
            tooltip: 'Decrease quantity',
            onPressed: () => _decrementCartItem(index),
            icon: const Icon(Icons.remove_circle_outline, size: 22),
          ),
          Text('${item.quantity}', style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
          IconButton(
            tooltip: 'Increase quantity',
            onPressed: () => _incrementCartItem(index),
            icon: const Icon(Icons.add_circle_outline, size: 22),
          ),
          const SizedBox(width: 8),
          Expanded(child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(fit: BoxFit.scaleDown, child: Text(
              'Rs ${_currencyFormat.format(item.totalPrice)}',
              style: WarmCounterTypography.tabularPrice.copyWith(fontWeight: FontWeight.w600),
            )),
          )),
        ]),
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




