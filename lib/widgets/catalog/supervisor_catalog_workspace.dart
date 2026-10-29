import '../../core/catalog/discount_rules.dart';
import '../../core/inventory/stock_count_controller.dart';
import '../../core/settings/keyboard_shortcut_controller.dart';
import 'dialogs/stock_counts_dialog.dart';
import 'dialogs/keyboard_shortcuts_dialog.dart';
import 'dialogs/deal_form_dialog.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/discount_preset.dart';
import 'package:resturant_sys/core/catalog/menu_category.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/catalog/modifier.dart';
import 'package:resturant_sys/core/catalog/modifier_group.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'dialogs/category_form_dialog.dart';
import 'dialogs/catalog_photo_dialog.dart';
import '../../core/orders/deal.dart';
import 'dialogs/discount_preset_form_dialog.dart';
import 'dialogs/menu_item_form_dialog.dart';
import 'dialogs/modifier_form_dialog.dart';
import 'dialogs/modifier_group_form_dialog.dart';
import 'dialogs/raw_ingredient_form_dialog.dart';
import 'dialogs/recipe_builder_dialog.dart';
import '../procurement/kitchen_wastage_dialog.dart';
import '../procurement/quick_mandi_purchase_dialog.dart';
import '../../core/procurement/procurement_and_wastage_controller.dart';

/// Back-office catalog and recipe definition workspace for supervisors and owners.
///
/// Implements full CRUD for Menu Categories, Menu Items with tax-inclusive pricing,
/// Raw Ingredients with low-stock alerts, Bill of Materials (BOM) recipes,
/// Modifiers with price/ingredient deltas, and Pre-Approved Discounts.
class SupervisorCatalogWorkspace extends StatefulWidget {
  const SupervisorCatalogWorkspace({
    super.key,
    this.controller,
    this.orderController,
    this.managerId,
    this.procurementController,
    this.initialCategories,
    this.initialMenuItems,
    this.initialRawIngredients,
    this.initialModifiers,
    this.initialModifierGroups,
    this.initialDiscounts,
    this.imageBuilder,
  });

  final CatalogAndRecipeController? controller;
  final OrderAndCheckoutController? orderController;
  final int? managerId;
  final ProcurementAndWastageController? procurementController;
  final List<MenuCategory>? initialCategories;
  final List<MenuItem>? initialMenuItems;
  final List<RawIngredient>? initialRawIngredients;
  final List<Modifier>? initialModifiers;
  final List<ModifierGroup>? initialModifierGroups;
  final List<DiscountPreset>? initialDiscounts;
  final Widget Function(BuildContext context, File file)? imageBuilder;

  @override
  State<SupervisorCatalogWorkspace> createState() => _SupervisorCatalogWorkspaceState();
}

class _SupervisorCatalogWorkspaceState extends State<SupervisorCatalogWorkspace> {
  bool _isLoading = true;
  List<MenuCategory> _categories = [];
  List<MenuItem> _menuItems = [];
  List<Deal> _deals = [];
  List<MenuItem> _allMenuItems = [];
  List<RawIngredient> _rawIngredients = [];
  List<Modifier> _modifiers = [];
  List<ModifierGroup> _modifierGroups = [];
  List<DiscountPreset> _discounts = [];
  List<Map<String, Object?>> _discountCashiers = [];
  bool _cashierVoidEnabled = true;

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
    if (widget.orderController != null) {
      widget.orderController!.isCashierVoidEnabled().then((enabled) {
        if (mounted) setState(() => _cashierVoidEnabled = enabled);
      });
    }

    if (widget.initialCategories != null || widget.controller == null) {
      if (mounted) {
        setState(() {
          _categories = List.from(widget.initialCategories ?? []);
          _menuItems = List.from(widget.initialMenuItems ?? []);
          _allMenuItems = List.from(widget.initialMenuItems ?? []);
          var ings = List<RawIngredient>.from(widget.initialRawIngredients ?? []);
          if (_lowStockFilterOnly) {
            ings = ings.where((i) => i.isLowStock).toList();
          }
          _rawIngredients = ings;
          _modifiers = List.from(widget.initialModifiers ?? []);
          _modifierGroups = List.from(widget.initialModifierGroups ?? []);
          _discounts = List.from(widget.initialDiscounts ?? []);
          _isLoading = false;
        });
      }
      return;
    }

    setState(() => _isLoading = true);
    final deals = await widget.controller!.getDeals();
    final categories = await widget.controller!.getCategories();
    final allItems = await widget.controller!.getMenuItems();
    final items = allItems.where((item) => _menuItemCategoryFilter == null || item.categoryId == _menuItemCategoryFilter).toList();
    final ingredients = await widget.controller!.getRawIngredients(lowStockOnly: _lowStockFilterOnly ? true : null);
    final modifiers = await widget.controller!.getModifiers();
    final groups = await widget.controller!.getModifierGroups();
    final discounts = await widget.controller!.getDiscountPresets();
    final cashiers = widget.managerId == null ? <Map<String, Object?>>[]
      : await widget.controller!.getDiscountCashiers(managerId: widget.managerId!);

    if (mounted) {
      setState(() {
        _categories = categories;
        _deals = deals;
        _menuItems = items;
        _allMenuItems = allItems;
        _rawIngredients = ingredients;
        _modifiers = modifiers;
        _modifierGroups = groups;
        _discounts = discounts;
        _discountCashiers = cashiers;
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Category Actions
  // ---------------------------------------------------------------------------

  Future<void> _deleteCatalogRecord(Future<void> Function() delete, String label) async {
    try {
      await delete();
      if (mounted) await _loadAllCatalogData();
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError ? error.message
          : 'Could not delete $label. It may be linked to protected records. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: WarmCounterColors.lightDestructiveAction,
      ));
    }
  }

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

    if (confirmed == true && mounted) {
      if (widget.controller != null) {
        await _deleteCatalogRecord(() async {
          await widget.controller!.deleteCategory(category.id);
          if (_menuItemCategoryFilter == category.id) _menuItemCategoryFilter = null;
        }, 'category');
      } else {
        setState(() {
          _categories.removeWhere((c) => c.id == category.id);
          final itemIds = _allMenuItems.where((item) => item.categoryId == category.id).map((item) => item.id).toSet();
          _removePreviewMenuItems(itemIds);
          if (_menuItemCategoryFilter == category.id) _menuItemCategoryFilter = null;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Menu Item Actions
  // ---------------------------------------------------------------------------

  void _removePreviewMenuItems(Set<int> ids) {
    _allMenuItems.removeWhere((item) => ids.contains(item.id));
    _menuItems.removeWhere((item) => ids.contains(item.id));
    _modifiers.removeWhere((modifier) => ids.contains(modifier.menuItemId));
    _modifierGroups.removeWhere((group) => ids.contains(group.menuItemId));
  }

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
        mediaService: widget.controller?.mediaService,
        onSave: ({required categoryId, required name, required basePrice, required taxRate, required isTaxInclusive, required isActive, required photoChange}) async {
          if (widget.controller != null) {
            await widget.controller!.createMenuItem(
              categoryId: categoryId,
              name: name,
              basePrice: basePrice,
              taxRate: taxRate,
              isTaxInclusive: isTaxInclusive,
              isActive: isActive,
              photoChange: photoChange,
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
        mediaService: widget.controller?.mediaService,
        onSave: ({required categoryId, required name, required basePrice, required taxRate, required isTaxInclusive, required isActive, required photoChange}) async {
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
              photoChange: photoChange,
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

  void _showPhotoGalleryDialog({
    required String entityType,
    required int entityId,
    required String entityName,
  }) {
    if (widget.controller == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => CatalogPhotoDialog(
        mediaService: widget.controller!.mediaService,
        entityType: entityType,
        entityId: entityId,
        entityName: entityName,
        imageBuilder: widget.imageBuilder,
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

    if (confirmed == true && mounted) {
      if (widget.controller != null) {
        await _deleteCatalogRecord(() => widget.controller!.deleteMenuItem(item.id), 'menu item');
      } else {
        setState(() {
          _removePreviewMenuItems({item.id});
        });
      }
    }
  }

  Future<void> _toggleMenuItemActive(MenuItem item, bool active) async {
    if (widget.controller != null) {
      try {
        await widget.controller!.toggleMenuItemActive(item.id, active);
        await _loadAllCatalogData();
      } on StateError catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } else {
      setState(() {
        final idx = _menuItems.indexWhere((m) => m.id == item.id);
        if (idx != -1) {
          _menuItems[idx] = item.copyWith(isActive: active);
        }
      });
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
        content: Text('Delete "${ingredient.name}" from kitchen inventory? Ingredients linked to recipes or inventory and cost history must be retained.'),
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

    if (confirmed == true && mounted) {
      if (widget.controller != null) {
        try {
          await widget.controller!.deleteRawIngredient(ingredient.id);
          await _loadAllCatalogData();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot delete ingredient: it may be linked to recipes or protected inventory and cost history.'),
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

  void _showQuickMandiDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => QuickMandiPurchaseDialog(
        controller: widget.procurementController,
        initialIngredients: _rawIngredients,
        onProcurementCompleted: (_) => _loadAllCatalogData(),
      ),
    ).then((_) => _loadAllCatalogData());
  }

  void _showKitchenWastageDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => KitchenWastageDialog(
        controller: widget.procurementController,
        initialIngredients: _rawIngredients,
        onWastageLogged: (_) => _loadAllCatalogData(),
      ),
    ).then((_) => _loadAllCatalogData());
  }

  // ---------------------------------------------------------------------------
  // Modifier Actions
  // ---------------------------------------------------------------------------

  void _showModifierGroupDialog([ModifierGroup? group]) {
    showDialog<void>(
      context: context,
      builder: (context) => ModifierGroupFormDialog(
        group: group,
        menuItems: _allMenuItems,
        onSave: (updated) async {
          if (widget.controller != null) {
            if (group == null) {
              await widget.controller!.createModifierGroup(
                menuItemId: updated.menuItemId,
                name: updated.name,
                selectionMode: updated.selectionMode,
                minSelected: updated.minSelected,
                maxSelected: updated.maxSelected,
                isRequired: updated.isRequired,
              );
            } else {
              await widget.controller!.updateModifierGroup(updated);
            }
            await _loadAllCatalogData();
          } else {
            setState(() {
              if (group == null) {
                _modifierGroups.add(ModifierGroup(
                  id: _modifierGroups.fold<int>(0, (max, group) => group.id > max ? group.id : max) + 1,
                  menuItemId: updated.menuItemId,
                  name: updated.name,
                  selectionMode: updated.selectionMode,
                  minSelected: updated.minSelected,
                  maxSelected: updated.maxSelected,
                  isRequired: updated.isRequired,
                ));
              } else {
                final index = _modifierGroups.indexWhere((g) => g.id == group.id);
                _modifierGroups[index] = updated;
              }
            });
          }
        },
      ),
    );
  }

  void _showAddModifierDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ModifierFormDialog(
        menuItems: _allMenuItems,
        rawIngredients: _rawIngredients,
        groups: _modifierGroups,
        onSave: ({menuItemId, groupId, required name, required priceDelta, rawIngredientId, required ingredientQtyDelta, required bool isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.createModifier(
              menuItemId: menuItemId,
              groupId: groupId,
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
              groupId: groupId,
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
        menuItems: _allMenuItems,
        rawIngredients: _rawIngredients,
        groups: _modifierGroups,
        onSave: ({menuItemId, groupId, required name, required priceDelta, rawIngredientId, required ingredientQtyDelta, required bool isActive}) async {
          if (widget.controller != null) {
            await widget.controller!.updateModifier(
              modifier.copyWith(
                clearGroup: groupId == null,
                clearMenuItem: menuItemId == null,
                menuItemId: menuItemId,
              groupId: groupId,
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
                clearGroup: groupId == null,
                clearMenuItem: menuItemId == null,
                  menuItemId: menuItemId,
              groupId: groupId,
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

    if (confirmed == true && mounted) {
      if (widget.controller != null) {
        await _deleteCatalogRecord(() => widget.controller!.deleteModifier(modifier.id), 'modifier');
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
        categories: _categories, deals: _deals, cashiers: _discountCashiers,
        onSave: ({required name, required type, required value, required bool isActive, required DiscountRules rules}) async {
          if (widget.controller != null) {
            if (widget.managerId == null) throw StateError('Manager session required.');
            await widget.controller!.saveManagedDiscount(managerId: widget.managerId!, create: true,
              preset: DiscountPreset(id: 0, name: name, type: type, value: value, isActive: isActive, rules: rules));
            await _loadAllCatalogData();
          } else {
            setState(() {
              _discounts.add(DiscountPreset(
                id: _discounts.length + 1,
                name: name,
                type: type,
                value: value,
                isActive: isActive,
                rules: rules,
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
        categories: _categories, deals: _deals, cashiers: _discountCashiers,
        preset: preset,
        onSave: ({required name, required type, required value, required bool isActive, required DiscountRules rules}) async {
          if (widget.controller != null) {
            if (widget.managerId == null) throw StateError('Manager session required.');
            await widget.controller!.saveManagedDiscount(managerId: widget.managerId!, preset:
              preset.copyWith(
                name: name,
                type: type,
                value: value,
                isActive: isActive,
                rules: rules,
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
                rules: rules,
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

    if (confirmed == true && mounted) {
      if (widget.controller != null) {
        await _deleteCatalogRecord(() async {
          if (widget.managerId == null) throw StateError('Manager session required.');
          await widget.controller!.deleteManagedDiscount(managerId: widget.managerId!, id: preset.id);
        }, 'discount preset');
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
    // Keep the controller mounted while persisted catalog changes reload.
    // Removing it for the loading indicator resets the selected tab to zero.
    return DefaultTabController(
      length: 7,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                Tab(key: ValueKey('tab_categories'), text: 'Categories'),
                Tab(key: ValueKey('tab_menu_items'), text: 'Menu Items & BOM'),
                Tab(key: ValueKey('tab_raw_ingredients'), text: 'Raw Ingredients'),
                Tab(key: ValueKey('tab_modifiers'), text: 'Modifiers'),
                Tab(key: ValueKey('tab_discounts'), text: 'Pre-Approved Discounts'),
                Tab(key: ValueKey('tab_settings'), text: 'Settings & Toggles'),
                Tab(key: ValueKey('tab_deal_photos'), text: 'Deals'),
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
                _buildSettingsTab(),
                _buildDealPhotosTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealPhotosTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Row(children: [
        Expanded(child: Text('Deals & selectable components', style: Theme.of(context).textTheme.titleLarge)),
        FilledButton.icon(onPressed: widget.managerId == null ? null : () => _editDeal(),
          icon: const Icon(Icons.add), label: const Text('Create Deal')),
      ])),
      if (_deals.isEmpty) const Expanded(child: Center(child: Text('No deals available. Create your first deal.')))
      else Expanded(child: ListView.builder(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      itemCount: _deals.length,
      itemBuilder: (context, index) {
        final deal = _deals[index];
        return ListTile(
          title: Text(deal.name),
          subtitle: Text('Rs ${deal.basePrice.toStringAsFixed(2)} | ${deal.items.length} components | ${deal.isActive ? 'Active' : 'Draft'}'),
          onTap: widget.managerId == null ? null : () => _editDeal(deal),
          trailing: IconButton(
            key: ValueKey('deal_photo_${deal.id}'),
            tooltip: 'Change picture',
            icon: const Icon(Icons.image_outlined),
            onPressed: () => _showPhotoGalleryDialog(
              entityType: 'deal', entityId: deal.id, entityName: deal.name,
            ),
          ),
        );
      },
    )),
    ]);
  }

  Future<void> _editDeal([Deal? deal]) async {
    final controller = widget.controller;
    if (controller == null || widget.managerId == null) return;
    final saved = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => DealFormDialog(
      controller: controller, managerId: widget.managerId!, menuItems: _allMenuItems, deal: deal));
    if (saved == true && mounted) await _loadAllCatalogData();
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operational Feature Toggles & Settings',
            style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
          ),
          ListTile(leading: const Icon(Icons.keyboard), title: const Text('Configure keyboard shortcuts'),
            subtitle: const Text('Cashier register · conflicts, preview and restore defaults'),
            onTap: widget.controller == null || widget.managerId == null ? null : () => showDialog<void>(context: context,
              builder: (_) => KeyboardShortcutsDialog(controller: KeyboardShortcutController(widget.controller!.database), managerId: widget.managerId!))),
          const SizedBox(height: WarmCounterSpacing.space16),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cashier-Initiated Void Requests',
                              style: WarmCounterTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'When enabled, cashiers can tap Void Order and request supervisor authorization. When disabled, cashiers cannot initiate void requests from the billing register.',
                              style: WarmCounterTypography.caption.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Switch(
                        key: const ValueKey('supervisor_cashier_void_toggle'),
                        value: _cashierVoidEnabled,
                        activeThumbColor: WarmCounterColors.lightPrimaryAction,
                        onChanged: (val) async {
                          if (widget.orderController != null) {
                            await widget.orderController!.setCashierVoidEnabled(val);
                          }
                          setState(() => _cashierVoidEnabled = val);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _filterMenuItems(int? categoryId) {
    setState(() {
      _menuItemCategoryFilter = categoryId;
      _menuItems = _allMenuItems.where((item) => categoryId == null || item.categoryId == categoryId).toList();
    });
  }

  // Tab 1: Categories
  Widget _buildCategoriesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
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
                    const Text('Menu Categories', style: WarmCounterTypography.brandHeading),
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
                  foregroundColor: WarmCounterColors.lightTextOnPrimary,
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
                final color = WarmCounterColors.parseHex(cat.colorHex);

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightCardBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    key: ValueKey('open_category_${cat.id}'),
                    onTap: () {
                      _filterMenuItems(cat.id);
                      DefaultTabController.of(context).animateTo(1);
                    },
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
    final menuItems = _menuItems;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
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
                    const Text('Menu Items & Recipe BOM', style: WarmCounterTypography.brandHeading),
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
                  foregroundColor: WarmCounterColors.lightTextOnPrimary,
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
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  label: const Text('All Categories'),
                  selected: _menuItemCategoryFilter == null,
                  onSelected: (_) {
                    _filterMenuItems(null);
                  },
                ),
                const SizedBox(width: 8),
                ..._categories.map((c) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      label: Text(c.name),
                      selected: _menuItemCategoryFilter == c.id,
                      onSelected: (selected) {
                        _filterMenuItems(selected ? c.id : null);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          if (menuItems.isEmpty)
            _buildEmptyState('No menu items found. Tap "Add Menu Item" to create dishes.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: menuItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = menuItems[index];

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
                              style: WarmCounterTypography.tabularNumbers.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Rs ${_currencyFormat.format(item.grossPrice)}',
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
                      // Inline active toggle switch
                      Tooltip(
                        message: item.isActive ? 'Active on counter register' : 'Inactive (hidden from cashiers)',
                        child: Switch(
                          key: ValueKey('toggle_menu_item_active_${item.id}'),
                          value: item.isActive,
                          onChanged: (val) => _toggleMenuItemActive(item, val),
                        ),
                      ),
                      const SizedBox(width: 8),
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
                        key: ValueKey('manage_photos_button_${item.id}'),
                        icon: const Icon(Icons.image_outlined, size: 20),
                        tooltip: 'Change picture',
                        onPressed: () => _showPhotoGalleryDialog(
                          entityType: 'menu_item',
                          entityId: item.id,
                          entityName: item.name,
                        ),
                      ),
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
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
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
                    const Text('Raw Ingredients Inventory', style: WarmCounterTypography.brandHeading),
                    Text(
                      'Bulk kitchen stock tracked in grams (g), kilograms (kg), milliliters (ml), and piece counts.',
                      style: WarmCounterTypography.caption.copyWith(color: WarmCounterColors.lightSecondaryText),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('raw_ingredients_quick_mandi_button'),
                    icon: const Icon(Icons.shopping_basket_rounded, size: 18),
                    label: const Text('Quick Mandi Purchase'),
                    onPressed: _showQuickMandiDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WarmCounterColors.lightPrimaryAction,
                      side: const BorderSide(color: WarmCounterColors.lightPrimaryAction),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('raw_ingredients_record_wastage_button'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Record Wastage'),
                    onPressed: _showKitchenWastageDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WarmCounterColors.lightDestructiveAction,
                      side: const BorderSide(color: WarmCounterColors.lightDestructiveAction),
                    ),
                  ),
                  ElevatedButton.icon(
                    key: const ValueKey('add_ingredient_button'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Raw Ingredient'),
                    onPressed: _showAddRawIngredientDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WarmCounterColors.lightPrimaryAction,
                      foregroundColor: WarmCounterColors.lightTextOnPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          OutlinedButton.icon(icon: const Icon(Icons.fact_check_outlined), label: const Text('Physical stock counts'),
            onPressed: widget.controller == null || widget.managerId == null ? null : () async {
              await showDialog<void>(context: context, builder: (_) => StockCountsDialog(
                controller: StockCountController(widget.controller!.database), managerId: widget.managerId!));
              if (mounted) await _loadAllCatalogData();
            }),
          // Low-stock toggle chip
          FilterChip(
            mouseCursor: WidgetStateMouseCursor.clickable,
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
                              style: WarmCounterTypography.tabularNumbers.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                                fontSize: 12,
                              ),
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
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
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
                    const Text('Modifiers & Add-ons', style: WarmCounterTypography.brandHeading),
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
                  foregroundColor: WarmCounterColors.lightTextOnPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          OutlinedButton.icon(
            key: const ValueKey('add_modifier_group_button'),
            onPressed: () => _showModifierGroupDialog(),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Add Modifier Group'),
          ),
          for (final group in _modifierGroups)
            ListTile(
              title: Text(group.name),
              subtitle: Text('${_allMenuItems.where((item) => item.id == group.menuItemId).firstOrNull?.name ?? 'Menu item'} · ${group.selectionMode} · ${group.minSelected}–${group.maxSelected}${group.isRequired ? ' · Required' : ''}'),
              trailing: IconButton(
                key: ValueKey('edit_modifier_group_${group.id}'),
                tooltip: 'Edit modifier group',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showModifierGroupDialog(group),
              ),
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
                              style: WarmCounterTypography.tabularNumbers.copyWith(
                                color: WarmCounterColors.lightSecondaryText,
                                fontSize: 12,
                              ),
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
      padding: const EdgeInsets.all(WarmCounterSpacing.space16),
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
                    const Text('Pre-Approved Discounts', style: WarmCounterTypography.brandHeading),
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
                  foregroundColor: WarmCounterColors.lightTextOnPrimary,
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
