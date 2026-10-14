import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/khata/vendor.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/khata/vendor_statement.dart';
import 'package:resturant_sys/core/khata/vendor_transaction.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'credit_delivery_dialog.dart';
import 'settlement_payment_dialog.dart';
import 'vendor_form_dialog.dart';

/// Supervisor & Owner portal workspace managing the supplier credit ledger (Vendor Khata),
/// credit stock intakes, multi-source payment settlements, and chronological statements of accounts.
class VendorKhataWorkspace extends StatefulWidget {
  const VendorKhataWorkspace({
    super.key,
    required this.controller,
    this.shiftController,
    this.catalogController,
    this.currentStaff,
  });

  final VendorKhataController controller;
  final ShiftAndCashController? shiftController;
  final CatalogAndRecipeController? catalogController;
  final Staff? currentStaff;

  @override
  State<VendorKhataWorkspace> createState() => _VendorKhataWorkspaceState();
}

class _VendorKhataWorkspaceState extends State<VendorKhataWorkspace> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00');

  List<Vendor> _vendors = [];
  Vendor? _selectedVendor;
  VendorStatement? _statement;
  Shift? _activeShift;
  List<RawIngredient> _rawIngredients = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final vendors = await widget.controller.getVendors(
        searchQuery: _searchController.text,
      );

      Shift? activeShift;
      if (widget.shiftController != null) {
        activeShift = await widget.shiftController!.getActiveShift();
      }

      List<RawIngredient> rawIngredients = [];
      if (widget.catalogController != null) {
        rawIngredients = await widget.catalogController!.getRawIngredients();
      }

      Vendor? selected = _selectedVendor;
      if (selected != null) {
        final matches = vendors.where((v) => v.id == selected!.id);
        selected = matches.isNotEmpty ? matches.first : (vendors.isNotEmpty ? vendors.first : null);
      } else if (vendors.isNotEmpty) {
        selected = vendors.first;
      }

      VendorStatement? statement;
      if (selected != null) {
        statement = await widget.controller.getVendorStatement(selected.id);
      }

      setState(() {
        _vendors = vendors;
        _selectedVendor = selected;
        _statement = statement;
        _activeShift = activeShift;
        _rawIngredients = rawIngredients;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectVendor(Vendor vendor) async {
    setState(() {
      _selectedVendor = vendor;
      _isLoading = true;
    });

    try {
      final statement = await widget.controller.getVendorStatement(vendor.id);
      setState(() {
        _statement = statement;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createVendor() async {
    final result = await VendorFormDialog.show(context);
    if (result == null) return;

    try {
      final newVendor = await widget.controller.createVendor(
        name: result['name'] as String,
        phone: result['phone'] as String,
        suppliedIngredients: result['supplied_ingredients'] as String?,
        openingBalance: result['opening_balance'] as double? ?? 0.0,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Supplier "${newVendor.name}" added successfully.'),
          backgroundColor: WarmCounterColors.lightPrimaryAction,
        ),
      );

      _selectedVendor = newVendor;
      await _loadInitialData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding supplier: $e'),
          backgroundColor: WarmCounterColors.lightRed,
        ),
      );
    }
  }

  Future<void> _editVendor(Vendor vendor) async {
    final result = await VendorFormDialog.show(context, vendor: vendor);
    if (result == null) return;

    try {
      final updated = await widget.controller.updateVendor(
        id: vendor.id,
        name: result['name'] as String,
        phone: result['phone'] as String,
        suppliedIngredients: result['supplied_ingredients'] as String?,
        openingBalance: result['opening_balance'] as double?,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Supplier "${updated.name}" updated.'),
          backgroundColor: WarmCounterColors.lightPrimaryAction,
        ),
      );

      _selectedVendor = updated;
      await _loadInitialData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating supplier: $e'),
          backgroundColor: WarmCounterColors.lightRed,
        ),
      );
    }
  }

  Future<void> _deleteVendor(Vendor vendor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Supplier?'),
        content: Text(
          'Are you sure you want to delete "${vendor.name}" and all historical Khata ledger transactions? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: WarmCounterColors.lightRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.controller.deleteVendor(vendor.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Supplier "${vendor.name}" removed.'),
        ),
      );
      _selectedVendor = null;
      await _loadInitialData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting supplier: $e'),
          backgroundColor: WarmCounterColors.lightRed,
        ),
      );
    }
  }

  Future<void> _recordCreditDelivery() async {
    if (_selectedVendor == null) return;

    final result = await CreditDeliveryDialog.show(
      context,
      vendor: _selectedVendor!,
      rawIngredients: _rawIngredients,
    );
    if (result == null) return;

    try {
      await widget.controller.recordCreditDelivery(
        vendorId: _selectedVendor!.id,
        amount: result['amount'] as double,
        referenceSlip: result['reference_slip'] as String?,
        rawIngredientId: result['raw_ingredient_id'] as int?,
        quantity: result['quantity'] as double?,
        notes: result['notes'] as String?,
        staffId: widget.currentStaff?.id,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credit delivery recorded and ledger updated.'),
          backgroundColor: WarmCounterColors.lightPrimaryAction,
        ),
      );

      await _loadInitialData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging delivery: $e'),
          backgroundColor: WarmCounterColors.lightRed,
        ),
      );
    }
  }

  Future<void> _recordSettlementPayment() async {
    if (_selectedVendor == null) return;

    final result = await SettlementPaymentDialog.show(
      context,
      vendor: _selectedVendor!,
      activeShiftId: _activeShift?.id,
      activeStaffName: widget.currentStaff?.name,
    );
    if (result == null) return;

    try {
      await widget.controller.recordSettlementPayment(
        vendorId: _selectedVendor!.id,
        amount: result['amount'] as double,
        paymentSource: result['payment_source'] as VendorPaymentSource,
        shiftId: _activeShift?.id,
        staffId: widget.currentStaff?.id,
        referenceSlip: result['reference_slip'] as String?,
        notes: result['notes'] as String?,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settlement payment recorded successfully.'),
          backgroundColor: WarmCounterColors.lightPrimaryAction,
        ),
      );

      await _loadInitialData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error recording payment: $e'),
          backgroundColor: WarmCounterColors.lightRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: WarmCounterColors.lightPageBackground,
      child: Column(
        children: [
          // Top Control Bar
          _buildTopBar(context),

          // Main Content Master-Detail
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Directory (Vendors List)
                SizedBox(
                  width: 360,
                  child: _buildSupplierDirectory(context),
                ),

                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: WarmCounterColors.lightBorder,
                ),

                // Right Statement & Detail View
                Expanded(
                  child: _buildStatementView(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WarmCounterSpacing.space24,
        vertical: WarmCounterSpacing.space12,
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
        children: [
          const Icon(
            Icons.menu_book_rounded,
            color: WarmCounterColors.lightPrimaryAction,
            size: 26,
          ),
          const SizedBox(width: WarmCounterSpacing.space12),
          Text(
            'Vendor Khata (Supplier Credit Ledger)',
            style: WarmCounterTypography.sectionHeading.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            key: const Key('add_supplier_button'),
            icon: const Icon(Icons.person_add_rounded, size: 20),
            label: const Text('New Supplier'),
            style: ElevatedButton.styleFrom(
              backgroundColor: WarmCounterColors.lightPrimaryAction,
              foregroundColor: WarmCounterColors.lightTextOnPrimary,
              minimumSize: const Size(140, 48),
            ),
            onPressed: _createVendor,
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierDirectory(BuildContext context) {
    return Container(
      color: WarmCounterColors.lightCardBackground,
      child: Column(
        children: [
          // Search Field
          Padding(
            padding: const EdgeInsets.all(WarmCounterSpacing.space12),
            child: TextField(
              key: const Key('vendor_search_field'),
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadInitialData();
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: WarmCounterSpacing.space12,
                  vertical: WarmCounterSpacing.space8,
                ),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _loadInitialData(),
            ),
          ),

          // Supplier List
          Expanded(
            child: _isLoading && _vendors.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _vendors.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(WarmCounterSpacing.space24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.people_outline_rounded,
                                size: 48,
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                              const SizedBox(height: WarmCounterSpacing.space12),
                              Text(
                                'No suppliers found',
                                style: WarmCounterTypography.bodyMedium.copyWith(
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        key: const Key('vendor_list_view'),
                        itemCount: _vendors.length,
                        separatorBuilder: (ctx, i) => const Divider(
                          height: 1,
                          thickness: 1,
                          color: WarmCounterColors.lightBorder,
                        ),
                        itemBuilder: (ctx, index) {
                          final vendor = _vendors[index];
                          final isSelected = _selectedVendor?.id == vendor.id;

                          return InkWell(
                            key: Key('vendor_tile_${vendor.id}'),
                            onTap: () => _selectVendor(vendor),
                            child: Container(
                              color: isSelected
                                  ? WarmCounterColors.lightPrimaryAction.withAlpha(20)
                                  : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: WarmCounterSpacing.space16,
                                vertical: WarmCounterSpacing.space12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          vendor.name,
                                          style: WarmCounterTypography.bodyLarge.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: isSelected
                                                ? WarmCounterColors.lightPrimaryAction
                                                : WarmCounterColors.lightPrimaryText,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          vendor.phone,
                                          style: WarmCounterTypography.captionText.copyWith(
                                            color: WarmCounterColors.lightSecondaryText,
                                          ),
                                        ),
                                        if (vendor.suppliedIngredients != null &&
                                            vendor.suppliedIngredients!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            vendor.suppliedIngredients!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: WarmCounterTypography.captionText.copyWith(
                                              color: WarmCounterColors.lightSecondaryText,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: WarmCounterSpacing.space8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Rs. ${_currencyFormat.format(vendor.currentBalance)}',
                                        style: WarmCounterTypography.tabularNumbers.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: vendor.hasOutstandingPayable
                                              ? WarmCounterColors.lightAmber
                                              : WarmCounterColors.lightPrimaryText,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: vendor.hasOutstandingPayable
                                              ? WarmCounterColors.lightAmber.withAlpha(30)
                                              : WarmCounterColors.lightSurface,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          vendor.hasOutstandingPayable ? 'Payable' : 'Clear',
                                          style: WarmCounterTypography.captionText.copyWith(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: vendor.hasOutstandingPayable
                                                ? WarmCounterColors.lightAmber
                                                : WarmCounterColors.lightSecondaryText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert_rounded,
                                      size: 18,
                                      color: WarmCounterColors.lightSecondaryText,
                                    ),
                                    padding: EdgeInsets.zero,
                                    onSelected: (val) {
                                      if (val == 'edit') {
                                        _editVendor(vendor);
                                      } else if (val == 'delete') {
                                        _deleteVendor(vendor);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 16),
                                            SizedBox(width: 8),
                                            Text('Edit'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                size: 16, color: WarmCounterColors.lightRed),
                                            SizedBox(width: 8),
                                            Text('Delete',
                                                style: TextStyle(
                                                    color: WarmCounterColors.lightRed)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
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

  Widget _buildStatementView(BuildContext context) {
    if (_selectedVendor == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(WarmCounterSpacing.space32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 64,
                color: WarmCounterColors.lightSecondaryText,
              ),
              const SizedBox(height: WarmCounterSpacing.space16),
              Text(
                'Select a Supplier',
                style: WarmCounterTypography.sectionHeading.copyWith(
                  fontWeight: FontWeight.w700,
                  color: WarmCounterColors.lightSecondaryText,
                ),
              ),
              const SizedBox(height: WarmCounterSpacing.space8),
              Text(
                'Choose a vendor from the left directory to inspect delivery receipts, '
                'settlement payments, and current net payable due.',
                textAlign: TextAlign.center,
                style: WarmCounterTypography.bodyMedium.copyWith(
                  color: WarmCounterColors.lightSecondaryText,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final vendor = _selectedVendor!;
    final statement = _statement;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vendor Details & Balance Banner
          _buildVendorHeaderBanner(context, vendor),
          const SizedBox(height: WarmCounterSpacing.space24),

          // Statement Entries Table
          _buildStatementTable(context, vendor, statement),
        ],
      ),
    );
  }

  Widget _buildVendorHeaderBanner(BuildContext context, Vendor vendor) {
    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space20),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Vendor Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendor.name,
                  style: WarmCounterTypography.sectionHeading.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space4),
                Row(
                  children: [
                    const Icon(Icons.phone_rounded, size: 16, color: WarmCounterColors.lightSecondaryText),
                    const SizedBox(width: WarmCounterSpacing.space4),
                    Text(
                      vendor.phone,
                      style: WarmCounterTypography.bodyMedium.copyWith(
                        color: WarmCounterColors.lightSecondaryText,
                      ),
                    ),
                    if (vendor.suppliedIngredients != null && vendor.suppliedIngredients!.isNotEmpty) ...[
                      const SizedBox(width: WarmCounterSpacing.space16),
                      const Icon(Icons.inventory_2_outlined, size: 16, color: WarmCounterColors.lightSecondaryText),
                      const SizedBox(width: WarmCounterSpacing.space4),
                      Text(
                        vendor.suppliedIngredients!,
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          color: WarmCounterColors.lightSecondaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Net Payable Due
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WarmCounterSpacing.space20,
              vertical: WarmCounterSpacing.space12,
            ),
            decoration: BoxDecoration(
              color: vendor.hasOutstandingPayable
                  ? WarmCounterColors.lightAmber.withAlpha(25)
                  : WarmCounterColors.lightSurface,
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              border: Border.all(
                color: vendor.hasOutstandingPayable
                    ? WarmCounterColors.lightAmber
                    : WarmCounterColors.lightBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'NET PAYABLE DUE',
                  style: WarmCounterTypography.captionText.copyWith(
                    fontWeight: FontWeight.w700,
                    color: vendor.hasOutstandingPayable
                        ? WarmCounterColors.lightAmber
                        : WarmCounterColors.lightSecondaryText,
                  ),
                ),
                Text(
                  'Rs. ${_currencyFormat.format(vendor.currentBalance)}',
                  key: const Key('vendor_net_payable_text'),
                  style: WarmCounterTypography.currencyLarge.copyWith(
                    color: vendor.hasOutstandingPayable
                        ? WarmCounterColors.lightAmber
                        : WarmCounterColors.lightPrimaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: WarmCounterSpacing.space20),

          // Action Buttons
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                key: const Key('log_credit_delivery_button'),
                icon: const Icon(Icons.local_shipping_rounded, size: 18),
                label: const Text('Log Credit Delivery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: WarmCounterColors.lightTextOnPrimary,
                  minimumSize: const Size(180, 48),
                ),
                onPressed: _recordCreditDelivery,
              ),
              const SizedBox(height: WarmCounterSpacing.space8),
              OutlinedButton.icon(
                key: const Key('settle_payment_button'),
                icon: const Icon(Icons.payments_rounded, size: 18),
                label: const Text('Record Payment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WarmCounterColors.lightPrimaryAction,
                  side: const BorderSide(color: WarmCounterColors.lightPrimaryAction),
                  minimumSize: const Size(180, 48),
                ),
                onPressed: _recordSettlementPayment,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatementTable(
    BuildContext context,
    Vendor vendor,
    VendorStatement? statement,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: WarmCounterColors.lightCardBackground,
        borderRadius: WarmCounterSpacing.panelBorderRadius,
        border: Border.all(color: WarmCounterColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Statement Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WarmCounterSpacing.space20,
              vertical: WarmCounterSpacing.space16,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: WarmCounterColors.lightBorder),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  color: WarmCounterColors.lightPrimaryAction,
                  size: 22,
                ),
                const SizedBox(width: WarmCounterSpacing.space8),
                Text(
                  'Statement of Accounts',
                  style: WarmCounterTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Opening Balance: Rs. ${_currencyFormat.format(vendor.openingBalance)}',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    color: WarmCounterColors.lightSecondaryText,
                  ),
                ),
              ],
            ),
          ),

          // Table Header
          Container(
            color: WarmCounterColors.lightSurface,
            padding: const EdgeInsets.symmetric(
              horizontal: WarmCounterSpacing.space20,
              vertical: WarmCounterSpacing.space12,
            ),
            child: Row(
              children: [
                const Expanded(flex: 2, child: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Text('Slip / Ref', style: TextStyle(fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Text('Type', style: TextStyle(fontWeight: FontWeight.w700))),
                const Expanded(flex: 3, child: Text('Particulars / Notes', style: TextStyle(fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Text('Added (+)', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Text('Paid (-)', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700))),
                const Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w700))),
              ],
            ),
          ),

          // Entries or Empty
          if (statement == null || statement.entries.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(WarmCounterSpacing.space32),
              child: Center(
                child: Text(
                  'No transactions recorded yet. Deliveries and settlements will appear here chronologically.',
                  style: WarmCounterTypography.bodyMedium.copyWith(
                    color: WarmCounterColors.lightSecondaryText,
                  ),
                ),
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: statement.entries.length,
              separatorBuilder: (ctx, i) => const Divider(
                height: 1,
                thickness: 1,
                color: WarmCounterColors.lightBorder,
              ),
              itemBuilder: (ctx, index) {
                final entry = statement.entries[index];
                final txn = entry.transaction;

                final typeBadgeText = txn.type.displayName;
                Color typeBadgeColor = WarmCounterColors.lightAmber;

                if (txn.type == VendorTransactionType.paymentDrawer) {
                  typeBadgeColor = WarmCounterColors.lightPrimaryAction;
                } else if (txn.type == VendorTransactionType.paymentExternal) {
                  typeBadgeColor = Colors.blueGrey;
                }

                String particulars = txn.notes ?? '-';
                if (txn.rawIngredientName != null && txn.quantity != null) {
                  particulars = '${txn.rawIngredientName} (${txn.quantity}) - $particulars';
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WarmCounterSpacing.space20,
                    vertical: WarmCounterSpacing.space12,
                  ),
                  child: Row(
                    children: [
                      // Date
                      Expanded(
                        flex: 2,
                        child: Text(
                          DateFormat('yyyy-MM-dd HH:mm').format(txn.createdAt),
                          style: WarmCounterTypography.captionText,
                        ),
                      ),
                      // Slip
                      Expanded(
                        flex: 2,
                        child: Text(
                          txn.referenceSlip ?? '-',
                          style: WarmCounterTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Type Badge
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: typeBadgeColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: typeBadgeColor.withAlpha(80)),
                            ),
                            child: Text(
                              typeBadgeText,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: typeBadgeColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Particulars
                      Expanded(
                        flex: 3,
                        child: Text(
                          particulars,
                          style: WarmCounterTypography.captionText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Added (+)
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.creditAmount > 0
                              ? '+ ${_currencyFormat.format(entry.creditAmount)}'
                              : '-',
                          textAlign: TextAlign.right,
                          style: WarmCounterTypography.tabularNumbers.copyWith(
                            fontWeight: FontWeight.w600,
                            color: entry.creditAmount > 0 ? WarmCounterColors.lightAmber : null,
                          ),
                        ),
                      ),
                      // Paid (-)
                      Expanded(
                        flex: 2,
                        child: Text(
                          entry.debitAmount > 0
                              ? '- ${_currencyFormat.format(entry.debitAmount)}'
                              : '-',
                          textAlign: TextAlign.right,
                          style: WarmCounterTypography.tabularNumbers.copyWith(
                            fontWeight: FontWeight.w600,
                            color: entry.debitAmount > 0 ? WarmCounterColors.lightPrimaryAction : null,
                          ),
                        ),
                      ),
                      // Running Balance
                      Expanded(
                        flex: 2,
                        child: Text(
                          'Rs. ${_currencyFormat.format(entry.runningBalance)}',
                          textAlign: TextAlign.right,
                          style: WarmCounterTypography.tabularNumbers.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
