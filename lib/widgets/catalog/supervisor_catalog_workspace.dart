import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'dialogs/category_form_dialog.dart';
import 'dialogs/discount_preset_form_dialog.dart';
import 'dialogs/menu_item_form_dialog.dart';
import 'dialogs/modifier_form_dialog.dart';
import 'dialogs/raw_ingredient_form_dialog.dart';
import 'dialogs/recipe_builder_dialog.dart';

/// Back-office catalog and recipe definition workspace for supervisors and owners.
///
/// Implements full CRUD for Menu Categories, Menu Items with tax-inclusive pricing,
/// Raw Ingredients with low-stock alerts, Bill of Materials (BOM) recipes,
/// Modifiers with price/ingredient deltas, and Pre-Approved Discounts.
class SupervisorCatalogWorkspace extends StatefulWidget {
  const SupervisorCatalogWorkspace({
    super.key,
    this.controller,
    this.initialCategories,
    this.initialMenuItems,
    this.initialRawIngredients,
    this.initialModifiers,
    this.initialDiscounts,
  });

  final CatalogAndRecipeController? controller;
  final List<MenuCategory>? initialCategories;
  final List<MenuItem>? initialMenuItems;
  final List<RawIngredient>? initialRawIngredients;
  final List<Modifier>? initialModifiers;
  final List<DiscountPreset>? initialDiscounts;

  @override
  State<SupervisorCatalogWorkspace> createState() => _SupervisorCatalogWorkspaceState();
}

class _SupervisorCatalogWorkspaceState extends State<SupervisorCatalogWorkspace> {
  bool _isLoading = true;
  List<MenuCategory> _categories = [];
  List<MenuItem> _menuItems = [];
  List<RawIngredient> _rawIngredients = [];
  List<Modifier> _modifiers = [];
  List<DiscountPreset> _discounts = [];

  // Filter states
  int? _menuItemCategoryFilter;
  bool _lowStockFilterOnly = false;

  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadAllCatalogData();
  }

  Future<void> _loadAllCatalogData() async {
    if (widget.initialCategories != null || widget.controller == null) {
      if (mounted) {
        setState(() {
          _categories = List.from(widget.initialCategories ?? []);
          _menuItems = List.from(widget.initialMenuItems ?? []);
          var ings = List<RawIngredient>.from(widget.initialRawIngredients ?? []);
          if (_lowStockFilterOnly) {
            ings = ings.where((i) => i.isLowStock).toList();
          }
          _rawIngredients = ings;
          _modifiers = List.from(widget.initialModifiers ?? []);
          _discounts = List.from(widget.initialDiscounts ?? []);
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final categories = await widget.controller!.getCategories();
    final items = await widget.controller!.getMenuItems(categoryId: _menuItemCategoryFilter);
    final ingredients = await widget.controller!.getRawIngredients(lowStockOnly: _lowStockFilterOnly ? true : null);
    final modifiers = await widget.controller!.getModifiers();
    final discounts = await widget.controller!.getDiscountPresets();

    if (mounted) {
      setState(() {
        _categories = categories;
        _menuItems = items;
        _rawIngredients = ingredients;
        _modifiers = modifiers;
        _discounts = discounts;
        _isLoading = false;
      });
    }
  }

  Color _parseHex(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return WarmCounterColors.lightPrimaryAction;
    }
  }

  // ---------------------------------------------------------------------------
  // Category Actions
  // ---------------------------------------------------------------------------

  void _showAddCategoryDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => CategoryFormDialog(
        onSave: ({required name, required displayOrder, required colorHex}) async {
          if (widget.controller != null) {
            await widget.controller!.createCategory(
              name: name,
              displayOrder: displayOrder,
              colorHex: colorHex,
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              _categories.add(MenuCategory(
                id: _categories.length + 1,
                name: name,
                displayOrder: displayOrder,
                colorHex: colorHex,
              ));
            });
          }
        },
      ),
    );
  }

  void _showEditCategoryDialog(MenuCategory category) {
    showDialog<void>(
      context: context,
      builder: (ctx) => CategoryFormDialog(
        category: category,
        onSave: ({required name, required displayOrder, required colorHex}) async {
          if (widget.controller != null) {
            await widget.controller!.updateCategory(
              category.copyWith(
                name: name,
                displayOrder: displayOrder,
                colorHex: colorHex,
              ),
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              final idx = _categories.indexWhere((c) => c.id == category.id);
              if (idx != -1) {
                _categories[idx] = category.copyWith(
                  name: name,
                  displayOrder: displayOrder,
                  colorHex: colorHex,
                );
              }
            });
          }
        },
      ),
    );
  }

  Future<void> _confirmDeleteCategory(MenuCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text('Delete "${category.name}"? All associated menu items, recipes, and modifiers will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WarmCounterColors.lightDestructiveAction, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.controller != null) {
        await widget.controller!.deleteCategory(category.id);
        await _loadAllCatalogData();
      } else {
        setState(() {
          _categories.removeWhere((c) => c.id == category.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Menu Item Actions
  // ---------------------------------------------------------------------------

  void _showAddMenuItemDialog() {
    if (_categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please create at least one category before adding menu items.')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => MenuItemFormDialog(
        categories: _categories,
        onSave: ({required categoryId, required name, required basePrice, required taxRate, required isTaxInclusive, required isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.createMenuItem(
              categoryId: categoryId,
              name: name,
              basePrice: basePrice,
              taxRate: taxRate,
              isTaxInclusive: isTaxInclusive,
              isActive: isActive,
            );
            await _loadAllCatalogData();
          } else {
            final cat = _categories.firstWhere((c) => c.id == categoryId);
            setState(() {
              _menuItems.add(MenuItem(
                id: _menuItems.length + 1,
                categoryId: categoryId,
                categoryName: cat.name,
                name: name,
                basePrice: basePrice,
                taxRate: taxRate,
                isTaxInclusive: isTaxInclusive,
                isActive: isActive,
              ));
            });
          }
        },
      ),
    );
  }

  void _showEditMenuItemDialog(MenuItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => MenuItemFormDialog(
        item: item,
        categories: _categories,
        onSave: ({required categoryId, required name, required basePrice, required taxRate, required isTaxInclusive, required isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.updateMenuItem(
              item.copyWith(
                categoryId: categoryId,
                name: name,
                basePrice: basePrice,
                taxRate: taxRate,
                isTaxInclusive: isTaxInclusive,
                isActive: isActive,
              ),
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              final idx = _menuItems.indexWhere((m) => m.id == item.id);
              if (idx != -1) {
                _menuItems[idx] = item.copyWith(
                  categoryId: categoryId,
                  name: name,
                  basePrice: basePrice,
                  taxRate: taxRate,
                  isTaxInclusive: isTaxInclusive,
                  isActive: isActive,
                );
              }
            });
          }
        },
      ),
    );
  }

  void _showRecipeBuilderDialog(MenuItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => RecipeBuilderDialog(
        menuItem: item,
        controller: widget.controller,
      ),
    );
  }

  Future<void> _confirmDeleteMenuItem(MenuItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Menu Item'),
        content: Text('Delete "${item.name}"? Linked BOM recipes and modifiers will be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WarmCounterColors.lightDestructiveAction, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.controller != null) {
        await widget.controller!.deleteMenuItem(item.id);
        await _loadAllCatalogData();
      } else {
        setState(() {
          _menuItems.removeWhere((m) => m.id == item.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Raw Ingredient Actions
  // ---------------------------------------------------------------------------

  void _showAddRawIngredientDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => RawIngredientFormDialog(
        onSave: ({required name, required storageUnit, required currentStock, required lowStockThreshold, required costPerRecipeUnit}) async {
          if (widget.controller != null) {
            await widget.controller!.createRawIngredient(
              name: name,
              storageUnit: storageUnit,
              currentStock: currentStock,
              lowStockThreshold: lowStockThreshold,
              costPerRecipeUnit: costPerRecipeUnit,
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              _rawIngredients.add(RawIngredient(
                id: _rawIngredients.length + 1,
                name: name,
                storageUnit: storageUnit,
                currentStock: currentStock,
                lowStockThreshold: lowStockThreshold,
                costPerRecipeUnit: costPerRecipeUnit,
              ));
            });
          }
        },
      ),
    );
  }

  void _showEditRawIngredientDialog(RawIngredient ingredient) {
    showDialog<void>(
      context: context,
      builder: (ctx) => RawIngredientFormDialog(
        ingredient: ingredient,
        onSave: ({required name, required storageUnit, required currentStock, required lowStockThreshold, required costPerRecipeUnit}) async {
          if (widget.controller != null) {
            await widget.controller!.updateRawIngredient(
              ingredient.copyWith(
                name: name,
                storageUnit: storageUnit,
                currentStock: currentStock,
                lowStockThreshold: lowStockThreshold,
                costPerRecipeUnit: costPerRecipeUnit,
              ),
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              final idx = _rawIngredients.indexWhere((i) => i.id == ingredient.id);
              if (idx != -1) {
                _rawIngredients[idx] = ingredient.copyWith(
                  name: name,
                  storageUnit: storageUnit,
                  currentStock: currentStock,
                  lowStockThreshold: lowStockThreshold,
                  costPerRecipeUnit: costPerRecipeUnit,
                );
              }
            });
          }
        },
      ),
    );
  }

  Future<void> _confirmDeleteRawIngredient(RawIngredient ingredient) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Raw Ingredient'),
        content: Text('Delete "${ingredient.name}" from kitchen inventory? Cannot be deleted if used in an active recipe.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WarmCounterColors.lightDestructiveAction, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.controller != null) {
        try {
          await widget.controller!.deleteRawIngredient(ingredient.id);
          await _loadAllCatalogData();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot delete ingredient: it is linked to one or more active recipes.'),
                backgroundColor: WarmCounterColors.lightDestructiveAction,
              ),
            );
          }
        }
      } else {
        setState(() {
          _rawIngredients.removeWhere((i) => i.id == ingredient.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Modifier Actions
  // ---------------------------------------------------------------------------

  void _showAddModifierDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ModifierFormDialog(
        menuItems: _menuItems,
        rawIngredients: _rawIngredients,
        onSave: ({menuItemId, required name, required priceDelta, rawIngredientId, required ingredientQtyDelta, required bool isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.createModifier(
              menuItemId: menuItemId,
              name: name,
              priceDelta: priceDelta,
              rawIngredientId: rawIngredientId,
              ingredientQtyDelta: ingredientQtyDelta,
              isActive: isActive,
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              _modifiers.add(Modifier(
                id: _modifiers.length + 1,
                menuItemId: menuItemId,
                name: name,
                priceDelta: priceDelta,
                rawIngredientId: rawIngredientId,
                ingredientQtyDelta: ingredientQtyDelta,
                isActive: isActive,
              ));
            });
          }
        },
      ),
    );
  }

  void _showEditModifierDialog(Modifier modifier) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ModifierFormDialog(
        modifier: modifier,
        menuItems: _menuItems,
        rawIngredients: _rawIngredients,
        onSave: ({menuItemId, required name, required priceDelta, rawIngredientId, required ingredientQtyDelta, required bool isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.updateModifier(
              modifier.copyWith(
                menuItemId: menuItemId,
                name: name,
                priceDelta: priceDelta,
                rawIngredientId: rawIngredientId,
                ingredientQtyDelta: ingredientQtyDelta,
                isActive: isActive,
              ),
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              final idx = _modifiers.indexWhere((m) => m.id == modifier.id);
              if (idx != -1) {
                _modifiers[idx] = modifier.copyWith(
                  menuItemId: menuItemId,
                  name: name,
                  priceDelta: priceDelta,
                  rawIngredientId: rawIngredientId,
                  ingredientQtyDelta: ingredientQtyDelta,
                  isActive: isActive,
                );
              }
            });
          }
        },
      ),
    );
  }

  Future<void> _confirmDeleteModifier(Modifier modifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Modifier'),
        content: Text('Delete modifier "${modifier.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WarmCounterColors.lightDestructiveAction, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.controller != null) {
        await widget.controller!.deleteModifier(modifier.id);
        await _loadAllCatalogData();
      } else {
        setState(() {
          _modifiers.removeWhere((m) => m.id == modifier.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Discount Preset Actions
  // ---------------------------------------------------------------------------

  void _showAddDiscountDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => DiscountPresetFormDialog(
        onSave: ({required name, required type, required value, required bool isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.createDiscountPreset(
              name: name,
              type: type,
              value: value,
              isActive: isActive,
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              _discounts.add(DiscountPreset(
                id: _discounts.length + 1,
                name: name,
                type: type,
                value: value,
                isActive: isActive,
              ));
            });
          }
        },
      ),
    );
  }

  void _showEditDiscountDialog(DiscountPreset preset) {
    showDialog<void>(
      context: context,
      builder: (ctx) => DiscountPresetFormDialog(
        preset: preset,
        onSave: ({required name, required type, required value, required bool isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.updateDiscountPreset(
              preset.copyWith(
                name: name,
                type: type,
                value: value,
                isActive: isActive,
              ),
            );
            await _loadAllCatalogData();
          } else {
            setState(() {
              final idx = _discounts.indexWhere((d) => d.id == preset.id);
              if (idx != -1) {
                _discounts[idx] = preset.copyWith(
                  name: name,
                  type: type,
                  value: value,
                  isActive: isActive,
                );
              }
            });
          }
        },
      ),
    );
  }

  Future<void> _confirmDeleteDiscount(DiscountPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Discount Preset'),
        content: Text('Delete discount preset "${preset.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: WarmCounterColors.lightDestructiveAction, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (widget.controller != null) {
        await widget.controller!.deleteDiscountPreset(preset.id);
        await _loadAllCatalogData();
      } else {
        setState(() {
          _discounts.removeWhere((d) => d.id == preset.id);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          // Sub-navigation TabBar
          Container(
            color: WarmCounterColors.lightCardBackground,
            child: const TabBar(
              key: ValueKey('catalog_tab_bar'),
              isScrollable: true,
              labelColor: WarmCounterColors.lightPrimaryAction,
              unselectedLabelColor: WarmCounterColors.lightSecondaryText,
              indicatorColor: WarmCounterColors.lightPrimaryAction,
              indicatorWeight: 3.0,
              tabs: [
                Tab(key: ValueKey('tab_categories'), icon: Icon(Icons.category_outlined), text: 'Categories'),
                Tab(key: ValueKey('tab_menu_items'), icon: Icon(Icons.restaurant_menu_outlined), text: 'Menu Items & BOM'),
                Tab(key: ValueKey('tab_raw_ingredients'), icon: Icon(Icons.inventory_2_outlined), text: 'Raw Ingredients'),
                Tab(key: ValueKey('tab_modifiers'), icon: Icon(Icons.tune_outlined), text: 'Modifiers'),
                Tab(key: ValueKey('tab_discounts'), icon: Icon(Icons.local_offer_outlined), text: 'Pre-Approved Discounts'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildCategoriesTab(),
                _buildMenuItemsTab(),
                _buildRawIngredientsTab(),
                _buildModifiersTab(),
                _buildDiscountsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Tab 1: Categories
  Widget _buildCategoriesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Menu Categories', style: WarmCounterTypography.pageHeading),
                    Text(
                      'Configure customer-facing category tabs, ordering, and display colors.',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              ElevatedButton.icon(
                key: const ValueKey('add_category_button'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Category'),
                onPressed: _showAddCategoryDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),
          if (_categories.isEmpty)
            _buildEmptyState('No categories configured yet. Tap "Add Category" to start.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final color = _parseHex(cat.colorHex);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightCardBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          cat.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: WarmCounterColors.lightSurfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Order: #${cat.displayOrder}',
                          style: WarmCounterTypography.caption.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: ValueKey('edit_category_${cat.id}'),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showEditCategoryDialog(cat),
                      ),
                      IconButton(
                        key: ValueKey('delete_category_${cat.id}'),
                        icon: const Icon(Icons.delete_outline, color: WarmCounterColors.lightDestructiveAction, size: 20),
                        onPressed: () => _confirmDeleteCategory(cat),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Tab 2: Menu Items & BOM
  Widget _buildMenuItemsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Menu Items & Recipe BOM', style: WarmCounterTypography.pageHeading),
                    Text(
                      'Manage tax-inclusive prices, sales tax rates, and component recipe formulas.',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('add_menu_item_button'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Menu Item'),
                onPressed: _showAddMenuItemDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          // Category filter chip row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All Categories'),
                  selected: _menuItemCategoryFilter == null,
                  onSelected: (_) {
                    setState(() => _menuItemCategoryFilter = null);
                    _loadAllCatalogData();
                  },
                ),
                const SizedBox(width: 8),
                ..._categories.map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(c.name),
                      selected: _menuItemCategoryFilter == c.id,
                      onSelected: (selected) {
                        setState(() => _menuItemCategoryFilter = selected ? c.id : null);
                        _loadAllCatalogData();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          if (_menuItems.isEmpty)
            _buildEmptyState('No menu items found. Tap "Add Menu Item" to create dishes.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _menuItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _menuItems[index];

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightCardBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: item.isActive
                              ? WarmCounterColors.lightActiveNavHighlight
                              : WarmCounterColors.lightSurfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.lunch_dining_rounded,
                          color: item.isActive
                              ? WarmCounterColors.lightPrimaryAction
                              : WarmCounterColors.lightSecondaryText,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: WarmCounterColors.lightSurfaceMuted,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    item.categoryName ?? 'General',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Net Base: Rs ${_currencyFormat.format(item.netPrice)} • Tax (${item.taxRate.toStringAsFixed(1)}%): Rs ${_currencyFormat.format(item.taxAmount)}',
                              style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Rs ${_currencyFormat.format(item.basePrice)}',
                            style: WarmCounterTypography.tabularNumbers.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            item.isTaxInclusive ? 'Tax-Inclusive' : 'Tax-Exclusive',
                            style: WarmCounterTypography.caption,
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // BOM recipe button
                      OutlinedButton.icon(
                        key: ValueKey('edit_bom_button_${item.id}'),
                        icon: const Icon(Icons.receipt_long_outlined, size: 16),
                        label: const Text('BOM Recipe'),
                        onPressed: () => _showRecipeBuilderDialog(item),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: WarmCounterColors.lightPrimaryAction,
                          side: const BorderSide(color: WarmCounterColors.lightPrimaryAction),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        key: ValueKey('edit_menu_item_${item.id}'),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showEditMenuItemDialog(item),
                      ),
                      IconButton(
                        key: ValueKey('delete_menu_item_${item.id}'),
                        icon: const Icon(Icons.delete_outline, color: WarmCounterColors.lightDestructiveAction, size: 20),
                        onPressed: () => _confirmDeleteMenuItem(item),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Tab 3: Raw Ingredients
  Widget _buildRawIngredientsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Raw Ingredients Inventory', style: WarmCounterTypography.pageHeading),
                    Text(
                      'Bulk kitchen stock tracked in grams (g), kilograms (kg), milliliters (ml), and piece counts.',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                key: const ValueKey('add_ingredient_button'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Raw Ingredient'),
                onPressed: _showAddRawIngredientDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          // Low-stock toggle chip
          FilterChip(
            key: const ValueKey('low_stock_filter_chip'),
            label: const Text('Show Low Stock Alert Only'),
            selected: _lowStockFilterOnly,
            onSelected: (val) {
              setState(() => _lowStockFilterOnly = val);
              _loadAllCatalogData();
            },
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          if (_rawIngredients.isEmpty)
            _buildEmptyState('No raw ingredients recorded. Tap "Add Raw Ingredient" to track kitchen inventory.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rawIngredients.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final ing = _rawIngredients[index];
                final unit = ing.storageUnit.code;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightCardBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(
                      color: ing.isLowStock
                          ? WarmCounterColors.lightDestructiveAction
                          : WarmCounterColors.lightBorder,
                      width: ing.isLowStock ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ing.isLowStock
                              ? WarmCounterColors.lightDestructiveHighlight
                              : WarmCounterColors.lightSurfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.kitchen_outlined,
                          color: ing.isLowStock
                              ? WarmCounterColors.lightDestructiveAction
                              : WarmCounterColors.lightPrimaryAction,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  ing.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                if (ing.isLowStock) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: WarmCounterColors.lightDestructiveAction,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'LOW STOCK',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Base Unit: ${ing.storageUnit.displayName} • Cost: Rs ${_currencyFormat.format(ing.costPerRecipeUnit)} / $unit',
                              style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${ing.currentStock} $unit',
                            style: WarmCounterTypography.tabularNumbers.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: ing.isLowStock ? WarmCounterColors.lightDestructiveAction : null,
                            ),
                          ),
                          Text(
                            'Alert at ≤ ${ing.lowStockThreshold} $unit',
                            style: WarmCounterTypography.caption,
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: ValueKey('edit_ingredient_${ing.id}'),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showEditRawIngredientDialog(ing),
                      ),
                      IconButton(
                        key: ValueKey('delete_ingredient_${ing.id}'),
                        icon: const Icon(Icons.delete_outline, color: WarmCounterColors.lightDestructiveAction, size: 20),
                        onPressed: () => _confirmDeleteRawIngredient(ing),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Tab 4: Modifiers
  Widget _buildModifiersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Modifiers & Add-ons', style: WarmCounterTypography.pageHeading),
                    Text(
                      'Options that adjust item retail prices and recipe raw ingredient deductions.',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              ElevatedButton.icon(
                key: const ValueKey('add_modifier_button'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Modifier'),
                onPressed: _showAddModifierDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          if (_modifiers.isEmpty)
            _buildEmptyState('No modifiers configured. Tap "Add Modifier" to configure extras or removals.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _modifiers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final mod = _modifiers[index];
                final isPositivePrice = mod.priceDelta > 0;
                final priceText = mod.priceDelta == 0
                    ? 'Rs 0.00'
                    : '${isPositivePrice ? '+' : ''}Rs ${_currencyFormat.format(mod.priceDelta)}';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightCardBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: WarmCounterColors.lightSurfaceMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.add_circle_outline_rounded, size: 22, color: WarmCounterColors.lightPrimaryAction),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mod.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Target: ${mod.menuItemName ?? 'All Items (Global)'} • BOM: ${mod.rawIngredientName ?? 'None'} (${mod.ingredientQtyDelta >= 0 ? '+' : ''}${mod.ingredientQtyDelta} ${mod.storageUnit?.code ?? ''})',
                              style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        priceText,
                        style: WarmCounterTypography.tabularNumbers.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: isPositivePrice ? WarmCounterColors.lightPrimaryAction : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: ValueKey('edit_modifier_${mod.id}'),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showEditModifierDialog(mod),
                      ),
                      IconButton(
                        key: ValueKey('delete_modifier_${mod.id}'),
                        icon: const Icon(Icons.delete_outline, color: WarmCounterColors.lightDestructiveAction, size: 20),
                        onPressed: () => _confirmDeleteModifier(mod),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Tab 5: Pre-Approved Discounts
  Widget _buildDiscountsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pre-Approved Discounts', style: WarmCounterTypography.pageHeading),
                    Text(
                      'Promotions cashiers can apply at the counter without requiring a supervisor PIN (ADR-0004).',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              ElevatedButton.icon(
                key: const ValueKey('add_discount_preset_button'),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Discount Preset'),
                onPressed: _showAddDiscountDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: WarmCounterColors.lightPrimaryAction,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          if (_discounts.isEmpty)
            _buildEmptyState('No discount presets configured yet. Tap "Add Discount Preset" to define promotions.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _discounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final d = _discounts[index];
                final valueText = d.type == DiscountType.percentage
                    ? '${d.value.toStringAsFixed(0)}% Off'
                    : 'Rs ${_currencyFormat.format(d.value)} Off';

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightCardBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: WarmCounterColors.lightActiveNavHighlight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.discount_outlined, size: 22, color: WarmCounterColors.lightPrimaryAction),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              d.name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Type: ${d.type.displayName} • Cashier 1-Tap Checkout',
                              style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: WarmCounterColors.lightSurfaceMuted,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: WarmCounterColors.lightBorder),
                        ),
                        child: Text(
                          valueText,
                          style: WarmCounterTypography.tabularNumbers.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: WarmCounterColors.lightPrimaryAction,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: ValueKey('edit_discount_${d.id}'),
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _showEditDiscountDialog(d),
                      ),
                      IconButton(
                        key: ValueKey('delete_discount_${d.id}'),
                        icon: const Icon(Icons.delete_outline, color: WarmCounterColors.lightDestructiveAction, size: 20),
                        onPressed: () => _confirmDeleteDiscount(d),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(WarmCounterSpacing.space32),
        decoration: const BoxDecoration(
          color: WarmCounterColors.lightPageBackground,
          borderRadius: WarmCounterSpacing.panelBorderRadius,
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
        ),
      ),
    );
  }
}
