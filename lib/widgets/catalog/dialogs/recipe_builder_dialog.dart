import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/catalog/recipe_item.dart';
import 'package:resturant_sys/core/theme/theme.dart';

/// Interactive modal dialog for building and editing the Bill of Materials (BOM)
/// recipe linking a Menu Item to its raw ingredient components.
class RecipeBuilderDialog extends StatefulWidget {
  const RecipeBuilderDialog({
    super.key,
    required this.menuItem,
    this.controller,
    this.initialRecipeItems,
    this.initialAllIngredients,
    this.onAddOrUpdateItem,
    this.onRemoveItem,
  });

  final MenuItem menuItem;
  final CatalogAndRecipeController? controller;
  final List<RecipeItem>? initialRecipeItems;
  final List<RawIngredient>? initialAllIngredients;
  final Future<void> Function(int rawIngredientId, double quantity)? onAddOrUpdateItem;
  final Future<void> Function(int rawIngredientId)? onRemoveItem;

  @override
  State<RecipeBuilderDialog> createState() => _RecipeBuilderDialogState();
}

class _RecipeBuilderDialogState extends State<RecipeBuilderDialog> {
  final _qtyController = TextEditingController();
  List<RecipeItem> _recipeItems = [];
  List<RawIngredient> _allIngredients = [];
  int? _selectedIngredientId;
  bool _isLoading = true;
  bool _isAdding = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.initialRecipeItems != null || widget.controller == null) {
      final items = widget.initialRecipeItems ?? [];
      final ingredients = widget.initialAllIngredients ?? [];
      if (mounted) {
        setState(() {
          _recipeItems = List.from(items);
          _allIngredients = List.from(ingredients);
          if (_selectedIngredientId == null && ingredients.isNotEmpty) {
            _selectedIngredientId = ingredients.first.id;
          }
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final items = await widget.controller!.getRecipeForMenuItem(widget.menuItem.id);
    final ingredients = await widget.controller!.getRawIngredients();

    if (mounted) {
      setState(() {
        _recipeItems = items;
        _allIngredients = ingredients;
        if (_selectedIngredientId == null && ingredients.isNotEmpty) {
          _selectedIngredientId = ingredients.first.id;
        }
        _isLoading = false;
      });
    }
  }

  double get _totalFoodCost =>
      _recipeItems.fold(0.0, (sum, item) => sum + item.totalIngredientCost);

  RawIngredient? get _selectedIngredient {
    if (_selectedIngredientId == null) return null;
    try {
      return _allIngredients.firstWhere((i) => i.id == _selectedIngredientId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleAddOrUpdate() async {
    final ingId = _selectedIngredientId;
    if (ingId == null) return;

    final qty = double.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid positive quantity')),
      );
      return;
    }

    setState(() => _isAdding = true);
    try {
      if (widget.onAddOrUpdateItem != null) {
        await widget.onAddOrUpdateItem!(ingId, qty);
      } else if (widget.controller != null) {
        await widget.controller!.addOrUpdateRecipeItem(
          menuItemId: widget.menuItem.id,
          rawIngredientId: ingId,
          quantity: qty,
        );
      }
      _qtyController.clear();
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  Future<void> _handleRemoveItem(int rawIngredientId) async {
    try {
      if (widget.onRemoveItem != null) {
        await widget.onRemoveItem!(rawIngredientId);
      } else if (widget.controller != null) {
        await widget.controller!.removeRecipeItem(
          menuItemId: widget.menuItem.id,
          rawIngredientId: rawIngredientId,
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: WarmCounterColors.lightDestructiveAction,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final foodCost = _totalFoodCost;
    final retail = widget.menuItem.basePrice;
    final marginPct = retail > 0 ? ((retail - foodCost) / retail) * 100.0 : 0.0;

    return AlertDialog(
      shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.panelBorderRadius),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recipe BOM: ${widget.menuItem.name}',
                  style: WarmCounterTypography.pageHeading.copyWith(fontSize: 20),
                ),
                Text(
                  'Category: ${widget.menuItem.categoryName ?? 'General'} • Retail Price: Rs ${_currencyFormat.format(retail)}',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    color: WarmCounterColors.lightSecondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: WarmCounterColors.lightSurfaceMuted,
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              border: Border.all(color: WarmCounterColors.lightBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('Total Food Cost', style: WarmCounterTypography.caption),
                Text(
                  'Rs ${_currencyFormat.format(foodCost)} (${marginPct.toStringAsFixed(1)}% margin)',
                  style: WarmCounterTypography.tabularNumbers.copyWith(
                    fontWeight: FontWeight.bold,
                    color: WarmCounterColors.lightPrimaryAction,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        height: 480,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Add ingredient row
                  Container(
                    padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                    decoration: BoxDecoration(
                      color: WarmCounterColors.lightPageBackground,
                      borderRadius: WarmCounterSpacing.controlBorderRadius,
                      border: Border.all(color: WarmCounterColors.lightBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
                            key: const ValueKey('recipe_ingredient_dropdown'),
                            initialValue: _selectedIngredientId,
                            decoration: const InputDecoration(labelText: 'Select Ingredient'),
                            isExpanded: true,
                            items: _allIngredients.map((i) {
                              return DropdownMenuItem<int>(
                                value: i.id,
                                child: Text('${i.name} (${i.storageUnit.code})'),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _selectedIngredientId = val),
                          ),
                        ),
                        const SizedBox(width: WarmCounterSpacing.space12),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            key: const ValueKey('recipe_qty_field'),
                            controller: _qtyController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              hintText: 'e.g. 150, 1.5, 20',
                              suffixText: _selectedIngredient?.storageUnit.code ?? '',
                            ),
                          ),
                        ),
                        const SizedBox(width: WarmCounterSpacing.space12),
                        ElevatedButton.icon(
                          key: const ValueKey('add_recipe_item_button'),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add / Update'),
                          onPressed: _isAdding ? null : _handleAddOrUpdate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WarmCounterColors.lightPrimaryAction,
                            foregroundColor: WarmCounterColors.lightTextOnPrimary,
                            minimumSize: const Size(120, WarmCounterSpacing.touchTargetMin),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: WarmCounterSpacing.space16),

                  // Recipe items list / table
                  const Text('Recipe Ingredients Breakdown:', style: WarmCounterTypography.bodyLarge),
                  const SizedBox(height: WarmCounterSpacing.space8),
                  Expanded(
                    child: _recipeItems.isEmpty
                        ? Center(
                            child: Container(
                              padding: const EdgeInsets.all(WarmCounterSpacing.space24),
                              decoration: const BoxDecoration(
                                color: WarmCounterColors.lightPageBackground,
                                borderRadius: WarmCounterSpacing.controlBorderRadius,
                              ),
                              child: Text(
                                'No ingredients linked to this recipe yet.\nSelect ingredients above to configure BOM deductions.',
                                textAlign: TextAlign.center,
                                style: WarmCounterTypography.caption.copyWith(
                                  color: WarmCounterColors.lightSecondaryText,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _recipeItems.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = _recipeItems[index];
                              final unit = item.storageUnit?.code ?? '';
                              final lineCost = item.totalIngredientCost;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: WarmCounterColors.lightCardBackground,
                                  borderRadius: WarmCounterSpacing.controlBorderRadius,
                                  border: Border.all(color: WarmCounterColors.lightBorder),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.fastfood_outlined,
                                      size: 20,
                                      color: WarmCounterColors.lightPrimaryAction,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.rawIngredientName ?? 'Ingredient #${item.rawIngredientId}',
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                          ),
                                          Text(
                                            '${item.quantityPerRecipeUnit} $unit • Rs ${_currencyFormat.format(item.costPerRecipeUnit)} per $unit',
                                            style: WarmCounterTypography.tabularNumbers.copyWith(
                                              color: WarmCounterColors.lightSecondaryText,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'Rs ${_currencyFormat.format(lineCost)}',
                                      style: WarmCounterTypography.tabularNumbers.copyWith(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    IconButton(
                                      key: ValueKey('remove_recipe_item_${item.rawIngredientId}'),
                                      icon: const Icon(Icons.delete_outline, color: WarmCounterColors.lightDestructiveAction, size: 20),
                                      onPressed: () => _handleRemoveItem(item.rawIngredientId),
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
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: WarmCounterColors.lightPrimaryAction,
            foregroundColor: WarmCounterColors.lightTextOnPrimary,
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
