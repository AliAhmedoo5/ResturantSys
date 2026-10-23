import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/procurement/desi_unit.dart';
import 'package:resturant_sys/core/procurement/mandi_procurement.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Touch-optimized back-office workspace for wholesale Pakistani market procurement,
/// supporting traditional Desi units (Mann, Darjan, Peti, Bori, Dharri, Pao)
/// with live auto-calculation of recipe unit costs and instant inventory balance updates.
class QuickMandiPurchaseWorkspace extends StatefulWidget {
  const QuickMandiPurchaseWorkspace({
    super.key,
    this.controller,
    this.initialIngredients,
    this.initialProcurements,
    this.onProcurementCompleted,
  });

  final ProcurementAndWastageController? controller;
  final List<RawIngredient>? initialIngredients;
  final List<MandiProcurement>? initialProcurements;
  final ValueChanged<MandiProcurement>? onProcurementCompleted;

  @override
  State<QuickMandiPurchaseWorkspace> createState() => _QuickMandiPurchaseWorkspaceState();
}

class _QuickMandiPurchaseWorkspaceState extends State<QuickMandiPurchaseWorkspace> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _totalCostController = TextEditingController();
  final _notesController = TextEditingController();

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final NumberFormat _qtyFormat = NumberFormat('#,##0.###', 'en_US');

  bool _isLoading = true;
  List<RawIngredient> _ingredients = [];
  List<MandiProcurement> _recentProcurements = [];

  RawIngredient? _selectedIngredient;
  DesiUnit _selectedUnit = DesiUnit.mann;

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(_onFormValuesChanged);
    _totalCostController.addListener(_onFormValuesChanged);
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.removeListener(_onFormValuesChanged);
    _totalCostController.removeListener(_onFormValuesChanged);
    _quantityController.dispose();
    _totalCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onFormValuesChanged() {
    setState(() {});
  }

  Future<void> _loadData() async {
    if (widget.initialIngredients != null || widget.controller == null) {
      if (mounted) {
        setState(() {
          _ingredients = List.from(widget.initialIngredients ?? []);
          _recentProcurements = List.from(widget.initialProcurements ?? []);
          if (_ingredients.isNotEmpty) {
            _selectedIngredient = _ingredients.first;
          }
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final ingredients = await widget.controller!.getRawIngredients();
    final procurements = await widget.controller!.getProcurements(limit: 50);

    if (mounted) {
      setState(() {
        _ingredients = ingredients;
        _recentProcurements = procurements;
        if (_ingredients.isNotEmpty && _selectedIngredient == null) {
          _selectedIngredient = _ingredients.first;
        } else if (_selectedIngredient != null) {
          final matched = _ingredients.where((i) => i.id == _selectedIngredient!.id);
          if (matched.isNotEmpty) {
            _selectedIngredient = matched.first;
          }
        }
        _isLoading = false;
      });
    }
  }

  double get _enteredQuantity {
    final text = _quantityController.text.trim();
    return double.tryParse(text) ?? 0.0;
  }

  double get _enteredTotalCost {
    final text = _totalCostController.text.trim();
    return double.tryParse(text) ?? 0.0;
  }

  double get _convertedRecipeUnits {
    if (_selectedIngredient == null || _enteredQuantity <= 0) return 0.0;
    return _selectedUnit.toRecipeUnits(_enteredQuantity, _selectedIngredient!.storageUnit);
  }

  double get _computedUnitCost {
    if (_convertedRecipeUnits <= 0 || _enteredTotalCost <= 0) return 0.0;
    return _enteredTotalCost / _convertedRecipeUnits;
  }

  Future<void> _submitProcurement() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedIngredient == null) return;

    final qty = _enteredQuantity;
    final totalCost = _enteredTotalCost;
    final notes = _notesController.text.trim();

    if (widget.controller != null) {
      try {
        final procurement = await widget.controller!.recordMandiPurchase(
          rawIngredientId: _selectedIngredient!.id,
          unit: _selectedUnit,
          quantity: qty,
          totalCost: totalCost,
          notes: notes.isNotEmpty ? notes : null,
        );

        widget.onProcurementCompleted?.call(procurement);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Purchased ${qty.toStringAsFixed(1)} ${_selectedUnit.displayName} of ${_selectedIngredient!.name} '
                '(${_qtyFormat.format(_convertedRecipeUnits)} ${_selectedIngredient!.storageUnit.code}) for Rs. ${_currencyFormat.format(totalCost)}',
              ),
              backgroundColor: WarmCounterColors.lightPrimaryAction,
            ),
          );
          _totalCostController.clear();
          _notesController.clear();
          await _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error recording procurement: $e'),
              backgroundColor: WarmCounterColors.lightDestructiveAction,
            ),
          );
        }
      }
    } else {
      // Standalone / preview mode
      final converted = _convertedRecipeUnits;
      final costPerUnit = _computedUnitCost;
      final created = MandiProcurement(
        id: _recentProcurements.length + 1,
        rawIngredientId: _selectedIngredient!.id,
        rawIngredientName: _selectedIngredient!.name,
        traditionalUnit: _selectedUnit,
        quantity: qty,
        totalCost: totalCost,
        convertedQuantity: converted,
        costPerRecipeUnit: costPerUnit,
        storageUnit: _selectedIngredient!.storageUnit,
        notes: notes.isNotEmpty ? notes : null,
        createdAt: DateTime.now(),
      );

      setState(() {
        _recentProcurements.insert(0, created);
        final idx = _ingredients.indexWhere((i) => i.id == _selectedIngredient!.id);
        if (idx != -1) {
          _ingredients[idx] = _selectedIngredient!.copyWith(
            currentStock: _selectedIngredient!.currentStock + converted,
            costPerRecipeUnit: costPerUnit,
          );
          _selectedIngredient = _ingredients[idx];
        }
      });

      widget.onProcurementCompleted?.call(created);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Recorded ${qty.toStringAsFixed(1)} ${_selectedUnit.displayName} of ${_selectedIngredient!.name} for Rs. ${_currencyFormat.format(totalCost)}',
          ),
          backgroundColor: WarmCounterColors.lightPrimaryAction,
        ),
      );
      _totalCostController.clear();
      _notesController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: WarmCounterColors.lightPageBackground,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Purchase Form
                      Expanded(
                        flex: 5,
                        child: _buildPurchaseFormCard(),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space24),
                      // Right: Procurement History & Stock Overview
                      Expanded(
                        flex: 6,
                        child: _buildHistoryAndStockCard(),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPurchaseFormCard(),
                      const SizedBox(height: WarmCounterSpacing.space24),
                      _buildHistoryAndStockCard(),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildPurchaseFormCard() {
    return Card(
      color: WarmCounterColors.lightCardBackground,
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(WarmCounterSpacing.space16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(WarmCounterSpacing.space8),
                    decoration: const BoxDecoration(
                      color: WarmCounterColors.lightActiveNavHighlight,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                    ),
                    child: const Icon(
                      Icons.shopping_cart_checkout_rounded,
                      color: WarmCounterColors.lightPrimaryAction,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Desi Mandi Purchase',
                          style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                        ),
                        const Text(
                          'Bulk stock intake with traditional Pakistani wholesale units',
                          style: WarmCounterTypography.secondaryLabel,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32, color: WarmCounterColors.lightBorder),

              if (_ingredients.isEmpty)
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightWarningHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightWarning),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: WarmCounterColors.lightWarning),
                      SizedBox(width: WarmCounterSpacing.space12),
                      Expanded(
                        child: Text(
                          'No raw ingredients registered yet. Add ingredients in the Catalog & BOM workspace first.',
                          style: WarmCounterTypography.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Raw Ingredient Dropdown
                Text(
                  'Raw Ingredient *',
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                DropdownButtonFormField<int>(
                  key: const ValueKey('mandi_ingredient_dropdown'),
                  value: _selectedIngredient?.id,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _ingredients.map((ing) {
                    return DropdownMenuItem<int>(
                      value: ing.id,
                      child: Text(
                        '${ing.name} (Unit: ${ing.storageUnit.displayName})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    if (id != null) {
                      setState(() {
                        _selectedIngredient = _ingredients.firstWhere((i) => i.id == id);
                      });
                    }
                  },
                  validator: (value) => value == null ? 'Please select an ingredient' : null,
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Traditional Unit & Purchased Quantity Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Traditional Unit Dropdown
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Traditional Unit *',
                            style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: WarmCounterSpacing.space8),
                          DropdownButtonFormField<DesiUnit>(
                            key: const ValueKey('mandi_unit_dropdown'),
                            value: _selectedUnit,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.scale_rounded),
                              border: OutlineInputBorder(),
                            ),
                            items: DesiUnit.values.map((u) {
                              return DropdownMenuItem<DesiUnit>(
                                value: u,
                                child: Text(
                                  '${u.displayName} [${u.metricEquivalence}]',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (u) {
                              if (u != null) {
                                setState(() => _selectedUnit = u);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: WarmCounterSpacing.space16),

                    // Quantity Input
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quantity *',
                            style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: WarmCounterSpacing.space8),
                          TextFormField(
                            key: const ValueKey('mandi_quantity_input'),
                            controller: _quantityController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              hintText: 'e.g. 2.5',
                              border: OutlineInputBorder(),
                            ),
                            validator: (val) {
                              final parsed = double.tryParse(val?.trim() ?? '');
                              if (parsed == null || parsed <= 0) {
                                return 'Enter valid quantity > 0';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Total Amount Paid (PKR)
                Text(
                  'Total Amount Paid (PKR) *',
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                TextFormField(
                  key: const ValueKey('mandi_total_cost_input'),
                  controller: _totalCostController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    prefixText: 'Rs. ',
                    hintText: 'e.g. 4500.00',
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    final parsed = double.tryParse(val?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter total purchase cost > 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Notes (Optional)
                Text(
                  'Notes / Wholesale Vendor (Optional)',
                  style: WarmCounterTypography.secondaryLabel,
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                TextFormField(
                  key: const ValueKey('mandi_notes_input'),
                  controller: _notesController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Sabzi Mandi Gate 2 / Haji Bashir Arhat',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space24),

                // Live Auto-Calculated Conversion Summary Banner
                _buildLiveCalculationBanner(),
                const SizedBox(height: WarmCounterSpacing.space24),

                // Confirm Procurement Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const ValueKey('confirm_mandi_purchase_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: WarmCounterColors.lightTextOnPrimary,
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    onPressed: _submitProcurement,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_shopping_cart_rounded, size: 20),
                        const SizedBox(width: WarmCounterSpacing.space8),
                        Flexible(
                          child: Text(
                            'Confirm Mandi Purchase',
                            overflow: TextOverflow.ellipsis,
                            style: WarmCounterTypography.bodyMedium.copyWith(
                              color: WarmCounterColors.lightTextOnPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveCalculationBanner() {
    final qty = _enteredQuantity;
    final totalCost = _enteredTotalCost;
    final convertedQty = _convertedRecipeUnits;
    final unitCost = _computedUnitCost;
    final storageUnitStr = _selectedIngredient?.storageUnit.code ?? '';

    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightActiveNavHighlight,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(color: WarmCounterColors.lightPrimaryAction.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate_outlined, color: WarmCounterColors.lightPrimaryAction, size: 20),
              const SizedBox(width: WarmCounterSpacing.space8),
              Expanded(
                child: Text(
                  'Automatic Recipe Unit Calculation',
                  overflow: TextOverflow.ellipsis,
                  style: WarmCounterTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: WarmCounterColors.lightPrimaryAction,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                flex: 5,
                child: Text('Purchase Intake:', style: WarmCounterTypography.secondaryLabel),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  '${qty.toStringAsFixed(1)} ${_selectedUnit.displayName} (${_selectedUnit.metricEquivalence})',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                flex: 5,
                child: Text('Converted Recipe Stock:', style: WarmCounterTypography.secondaryLabel),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  '+${_qtyFormat.format(convertedQty)} $storageUnitStr',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  key: const ValueKey('mandi_converted_stock_display'),
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontWeight: FontWeight.w700,
                    color: WarmCounterColors.lightPrimaryAction,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                flex: 5,
                child: Text('Unit Cost per Recipe Unit:', style: WarmCounterTypography.secondaryLabel),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  totalCost > 0 && convertedQty > 0
                      ? 'Rs. ${_currencyFormat.format(unitCost)} / $storageUnitStr'
                      : 'Rs. 0.00 / $storageUnitStr',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  key: const ValueKey('mandi_unit_cost_display'),
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontWeight: FontWeight.w700,
                    color: WarmCounterColors.lightPrimaryAction,
                  ),
                ),
              ),
            ],
          ),
          if (_selectedIngredient != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  flex: 5,
                  child: Text('Current Stock:', style: WarmCounterTypography.caption),
                ),
                Expanded(
                  flex: 6,
                  child: Text(
                    '${_qtyFormat.format(_selectedIngredient!.currentStock)} $storageUnitStr',
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: WarmCounterTypography.tabularNumbers.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryAndStockCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Current Stock Balances Table Card
        Card(
          color: WarmCounterColors.lightCardBackground,
          shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Live Raw Ingredient Balances',
                        overflow: TextOverflow.ellipsis,
                        style: WarmCounterTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      tooltip: 'Refresh Balances',
                      onPressed: _loadData,
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                if (_ingredients.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(WarmCounterSpacing.space16),
                    child: Center(
                      child: Text('No raw ingredients recorded.', style: WarmCounterTypography.caption),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _ingredients.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: WarmCounterColors.lightBorder),
                      itemBuilder: (context, idx) {
                        final ing = _ingredients[idx];
                        final isSelected = ing.id == _selectedIngredient?.id;
                        final isLow = ing.isLowStock;

                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor: WarmCounterColors.lightActiveNavHighlight,
                          leading: Icon(
                            isLow ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                            color: isLow ? WarmCounterColors.lightWarning : WarmCounterColors.lightPrimaryAction,
                            size: 20,
                          ),
                          title: Text(
                            ing.name,
                            style: WarmCounterTypography.bodyMedium.copyWith(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            'Unit cost: Rs. ${_currencyFormat.format(ing.costPerRecipeUnit)} / ${ing.storageUnit.code}',
                            style: WarmCounterTypography.caption,
                          ),
                          trailing: Text(
                            '${_qtyFormat.format(ing.currentStock)} ${ing.storageUnit.code}',
                            style: WarmCounterTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isLow ? WarmCounterColors.lightWarning : WarmCounterColors.lightPrimaryText,
                            ),
                          ),
                          onTap: () {
                            setState(() => _selectedIngredient = ing);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WarmCounterSpacing.space16),

        // Recent Mandi Procurements Ledger Card
        Card(
          color: WarmCounterColors.lightCardBackground,
          shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent Mandi Purchases Log',
                  style: WarmCounterTypography.bodyMedium,
                ),
                const SizedBox(height: WarmCounterSpacing.space12),
                if (_recentProcurements.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(WarmCounterSpacing.space16),
                    child: Center(
                      child: Text(
                        'No wholesale purchases recorded yet.',
                        style: WarmCounterTypography.secondaryLabel,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _recentProcurements.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: WarmCounterColors.lightBorder),
                      itemBuilder: (context, idx) {
                        final p = _recentProcurements[idx];
                        final formattedDate = DateFormat('dd MMM, hh:mm a').format(p.createdAt);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.rawIngredientName ?? 'Ingredient #${p.rawIngredientId}',
                                      style: WarmCounterTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${p.quantity.toStringAsFixed(1)} ${p.traditionalUnit.displayName} '
                                      '(+${_qtyFormat.format(p.convertedQuantity)} ${p.storageUnit.code})',
                                      style: WarmCounterTypography.secondaryLabel,
                                    ),
                                    if (p.notes != null && p.notes!.isNotEmpty)
                                      Text(
                                        p.notes!,
                                        style: WarmCounterTypography.caption.copyWith(fontStyle: FontStyle.italic),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'Rs. ${_currencyFormat.format(p.totalCost)}',
                                      style: WarmCounterTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: WarmCounterColors.lightPrimaryText,
                                      ),
                                    ),
                                    Text(
                                      'Rs. ${_currencyFormat.format(p.costPerRecipeUnit)}/${p.storageUnit.code}',
                                      style: WarmCounterTypography.caption.copyWith(
                                        color: WarmCounterColors.lightPrimaryAction,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      formattedDate,
                                      style: WarmCounterTypography.caption.copyWith(fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
