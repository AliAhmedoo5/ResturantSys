import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/procurement/kitchen_wastage.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/procurement/wastage_reason.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Touch-friendly kitchen wastage logging workspace allowing culinary staff
/// to authenticate with their 4-digit Staff PIN, record spoiled or burned ingredients
/// with mandatory categorized reasons, immediately deduct inventory stock,
/// and compute total financial cost loss.
class KitchenWastageWorkspace extends StatefulWidget {
  const KitchenWastageWorkspace({
    super.key,
    this.controller,
    this.initialIngredients,
    this.initialWastageLogs,
    this.onWastageLogged,
  });

  final ProcurementAndWastageController? controller;
  final List<RawIngredient>? initialIngredients;
  final List<KitchenWastage>? initialWastageLogs;
  final ValueChanged<KitchenWastage>? onWastageLogged;

  @override
  State<KitchenWastageWorkspace> createState() => _KitchenWastageWorkspaceState();
}

class _KitchenWastageWorkspaceState extends State<KitchenWastageWorkspace> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _pinController = TextEditingController();
  final _notesController = TextEditingController();

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  final NumberFormat _qtyFormat = NumberFormat('#,##0.###', 'en_US');

  bool _isLoading = true;
  List<RawIngredient> _ingredients = [];
  List<KitchenWastage> _recentLogs = [];
  double _totalLoss = 0.0;

  RawIngredient? _selectedIngredient;
  WastageReason _selectedReason = WastageReason.burned;

  @override
  void initState() {
    super.initState();
    _quantityController.addListener(_onQuantityChanged);
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.removeListener(_onQuantityChanged);
    _quantityController.dispose();
    _pinController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onQuantityChanged() {
    setState(() {});
  }

  Future<void> _loadData() async {
    if (widget.initialIngredients != null || widget.controller == null) {
      if (mounted) {
        setState(() {
          _ingredients = List.from(widget.initialIngredients ?? []);
          _recentLogs = List.from(widget.initialWastageLogs ?? []);
          _totalLoss = _recentLogs.fold<double>(0.0, (sum, log) => sum + log.costLoss);
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
    final logs = await widget.controller!.getWastageLogs(limit: 50);
    final totalLoss = await widget.controller!.getTotalWastageLoss();

    if (mounted) {
      setState(() {
        _ingredients = ingredients;
        _recentLogs = logs;
        _totalLoss = totalLoss;
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

  double get _computedCostLoss {
    if (_selectedIngredient == null || _enteredQuantity <= 0) return 0.0;
    return _enteredQuantity * _selectedIngredient!.costPerRecipeUnit;
  }

  Future<void> _submitWastage() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedIngredient == null) return;

    final qty = _enteredQuantity;
    final pin = _pinController.text.trim();
    final notes = _notesController.text.trim();

    if (widget.controller != null) {
      try {
        final wastage = await widget.controller!.recordKitchenWastage(
          staffPin: pin,
          rawIngredientId: _selectedIngredient!.id,
          quantity: qty,
          reason: _selectedReason,
          notes: notes.isNotEmpty ? notes : null,
        );

        widget.onWastageLogged?.call(wastage);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Logged ${_qtyFormat.format(qty)} ${_selectedIngredient!.storageUnit.code} wastage '
                '(${_selectedReason.displayName}) — Cost Loss: Rs. ${_currencyFormat.format(wastage.costLoss)}',
              ),
              backgroundColor: WarmCounterColors.lightPrimaryAction,
            ),
          );
          _quantityController.clear();
          _pinController.clear();
          _notesController.clear();
          await _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to log wastage: $e'),
              backgroundColor: WarmCounterColors.lightDestructiveAction,
            ),
          );
        }
      }
    } else {
      // Standalone / preview mode
      if (pin != '1234' && pin != '2222' && pin != '1111') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid staff PIN. Please enter a valid 4-digit PIN.'),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
        return;
      }

      final costLoss = _computedCostLoss;
      final created = KitchenWastage(
        id: _recentLogs.length + 1,
        staffId: 1,
        staffName: 'Staff Member',
        rawIngredientId: _selectedIngredient!.id,
        rawIngredientName: _selectedIngredient!.name,
        quantity: qty,
        storageUnit: _selectedIngredient!.storageUnit,
        costLoss: costLoss,
        reason: _selectedReason,
        notes: notes.isNotEmpty ? notes : null,
        createdAt: DateTime.now(),
      );

      setState(() {
        _recentLogs.insert(0, created);
        _totalLoss += costLoss;
        final idx = _ingredients.indexWhere((i) => i.id == _selectedIngredient!.id);
        if (idx != -1) {
          _ingredients[idx] = _selectedIngredient!.copyWith(
            currentStock: _selectedIngredient!.currentStock - qty,
          );
          _selectedIngredient = _ingredients[idx];
        }
      });

      widget.onWastageLogged?.call(created);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Logged ${_qtyFormat.format(qty)} ${_selectedIngredient!.storageUnit.code} wastage '
            '(${_selectedReason.displayName}) — Cost Loss: Rs. ${_currencyFormat.format(costLoss)}',
          ),
          backgroundColor: WarmCounterColors.lightPrimaryAction,
        ),
      );
      _quantityController.clear();
      _pinController.clear();
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
            padding: const EdgeInsets.all(WarmCounterSpacing.space24),
            child: isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Wastage Entry Form
                      Expanded(
                        flex: 5,
                        child: _buildWastageFormCard(),
                      ),
                      const SizedBox(width: WarmCounterSpacing.space24),
                      // Right: Loss Summary & Wastage Logs
                      Expanded(
                        flex: 6,
                        child: _buildHistoryAndSummaryCard(),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWastageFormCard(),
                      const SizedBox(height: WarmCounterSpacing.space24),
                      _buildHistoryAndSummaryCard(),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildWastageFormCard() {
    return Card(
      color: WarmCounterColors.lightCardBackground,
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(WarmCounterSpacing.space24),
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
                      color: WarmCounterColors.lightDestructiveHighlight,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                    ),
                    child: const Icon(
                      Icons.delete_sweep_rounded,
                      color: WarmCounterColors.lightDestructiveAction,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: WarmCounterSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Kitchen Wastage Log',
                          style: WarmCounterTypography.brandHeading.copyWith(fontSize: 20),
                        ),
                        const Text(
                          'Immediate stock deduction and financial food-cost loss audit',
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
                  key: const ValueKey('wastage_ingredient_dropdown'),
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
                        '${ing.name} (Unit: ${ing.storageUnit.displayName} • Rs. ${_currencyFormat.format(ing.costPerRecipeUnit)}/${ing.storageUnit.code})',
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

                // Wasted Quantity Input
                Text(
                  'Wasted Quantity (${_selectedIngredient?.storageUnit.displayName ?? 'units'}) *',
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                TextFormField(
                  key: const ValueKey('wastage_quantity_input'),
                  controller: _quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    suffixText: _selectedIngredient?.storageUnit.code ?? '',
                    hintText: 'e.g. 250 or 1.5',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (val) {
                    final parsed = double.tryParse(val?.trim() ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter wasted quantity > 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Mandatory Wastage Reason Dropdown
                Text(
                  'Wastage Reason (Mandatory) *',
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                DropdownButtonFormField<WastageReason>(
                  key: const ValueKey('wastage_reason_dropdown'),
                  value: _selectedReason,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.report_problem_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: WastageReason.values.map((r) {
                    return DropdownMenuItem<WastageReason>(
                      value: r,
                      child: Text(
                        r.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (r) {
                    if (r != null) {
                      setState(() => _selectedReason = r);
                    }
                  },
                  validator: (value) => value == null ? 'Reason is mandatory' : null,
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Staff PIN (Masked)
                Text(
                  'Staff PIN (Mandatory Audit Verification) *',
                  style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                TextFormField(
                  key: const ValueKey('wastage_pin_input'),
                  controller: _pinController,
                  obscureText: true,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                    hintText: 'Enter 4-digit Staff PIN',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  validator: (val) {
                    if (val == null || val.trim().length != 4) {
                      return '4-digit Staff PIN required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: WarmCounterSpacing.space16),

                // Notes (Optional)
                const Text(
                  'Notes / Chef Comments (Optional)',
                  style: WarmCounterTypography.secondaryLabel,
                ),
                const SizedBox(height: WarmCounterSpacing.space8),
                TextFormField(
                  key: const ValueKey('wastage_notes_input'),
                  controller: _notesController,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Overcooked batch during lunch rush fry station',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: WarmCounterSpacing.space24),

                // Financial Loss Preview Banner
                _buildLossPreviewBanner(),
                const SizedBox(height: WarmCounterSpacing.space24),

                // Submit Wastage Chit Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    key: const ValueKey('confirm_kitchen_wastage_button'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightDestructiveAction,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    ),
                    onPressed: _submitWastage,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 20),
                        const SizedBox(width: WarmCounterSpacing.space8),
                        Flexible(
                          child: Text(
                            'Log Wastage Chit & Deduct Stock',
                            overflow: TextOverflow.ellipsis,
                            style: WarmCounterTypography.bodyMedium.copyWith(
                              color: Colors.white,
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

  Widget _buildLossPreviewBanner() {
    final qty = _enteredQuantity;
    final costLoss = _computedCostLoss;
    final unitCost = _selectedIngredient?.costPerRecipeUnit ?? 0.0;
    final storageUnitStr = _selectedIngredient?.storageUnit.code ?? '';

    return Container(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      decoration: BoxDecoration(
        color: WarmCounterColors.lightDestructiveHighlight,
        borderRadius: WarmCounterSpacing.controlBorderRadius,
        border: Border.all(color: WarmCounterColors.lightDestructiveAction.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_down_rounded, color: WarmCounterColors.lightDestructiveAction, size: 20),
              const SizedBox(width: WarmCounterSpacing.space8),
              Expanded(
                child: Text(
                  'Financial Food-Cost Loss',
                  overflow: TextOverflow.ellipsis,
                  style: WarmCounterTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: WarmCounterColors.lightDestructiveAction,
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
                child: Text('Wasted Stock Deduction:', style: WarmCounterTypography.secondaryLabel),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  '-${_qtyFormat.format(qty)} $storageUnitStr',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  key: const ValueKey('wastage_deducted_stock_display'),
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontWeight: FontWeight.w700,
                    color: WarmCounterColors.lightDestructiveAction,
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
                child: Text('Ingredient Unit Cost:', style: WarmCounterTypography.secondaryLabel),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  'Rs. ${_currencyFormat.format(unitCost)} / $storageUnitStr',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: WarmCounterTypography.tabularNumbers,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 5,
                child: Text('Total Financial Loss:', style: WarmCounterTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
              ),
              Expanded(
                flex: 6,
                child: Text(
                  'Rs. ${_currencyFormat.format(costLoss)}',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  key: const ValueKey('wastage_cost_loss_display'),
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: WarmCounterColors.lightDestructiveAction,
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

  Widget _buildHistoryAndSummaryCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total Wastage Cost Loss Summary Card
        Card(
          color: WarmCounterColors.lightCardBackground,
          shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                  decoration: const BoxDecoration(
                    color: WarmCounterColors.lightDestructiveHighlight,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                  ),
                  child: const Icon(
                    Icons.monetization_on_outlined,
                    color: WarmCounterColors.lightDestructiveAction,
                    size: 32,
                  ),
                ),
                const SizedBox(width: WarmCounterSpacing.space16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Recorded Wastage Loss',
                        style: WarmCounterTypography.secondaryLabel,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rs. ${_currencyFormat.format(_totalLoss)}',
                        key: const ValueKey('total_wastage_loss_summary'),
                        style: WarmCounterTypography.pageHeading.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: WarmCounterColors.lightDestructiveAction,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh Logs',
                  onPressed: _loadData,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WarmCounterSpacing.space16),

        // Recent Wastage Logs Ledger Card
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
                  'Recent Kitchen Wastage Audit Log',
                  style: WarmCounterTypography.bodyMedium,
                ),
                const SizedBox(height: WarmCounterSpacing.space12),
                if (_recentLogs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(WarmCounterSpacing.space24),
                    child: Center(
                      child: Text(
                        'No kitchen wastage incidents logged yet.',
                        style: WarmCounterTypography.secondaryLabel,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _recentLogs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: WarmCounterColors.lightBorder),
                      itemBuilder: (context, idx) {
                        final log = _recentLogs[idx];
                        final formattedDate = DateFormat('dd MMM, hh:mm a').format(log.createdAt);

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
                                      log.rawIngredientName ?? 'Ingredient #${log.rawIngredientId}',
                                      style: WarmCounterTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '-${_qtyFormat.format(log.quantity)} ${log.storageUnit.code} • ${log.reason.displayName}',
                                      style: WarmCounterTypography.secondaryLabel.copyWith(
                                        color: WarmCounterColors.lightDestructiveAction,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Logged by: ${log.staffName ?? 'Staff #${log.staffId}'}',
                                      style: WarmCounterTypography.caption,
                                    ),
                                    if (log.notes != null && log.notes!.isNotEmpty)
                                      Text(
                                        log.notes!,
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
                                      '-Rs. ${_currencyFormat.format(log.costLoss)}',
                                      style: WarmCounterTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: WarmCounterColors.lightDestructiveAction,
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
