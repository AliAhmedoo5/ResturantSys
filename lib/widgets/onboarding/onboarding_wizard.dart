import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/department.dart';
import '../../core/auth/staff.dart';
import '../../core/auth/staff_role.dart';
import '../../core/catalog/catalog_and_recipe_controller.dart';
import '../../core/catalog/storage_unit.dart';
import '../../core/database/pos_database_constants.dart';
import '../../core/shifts/business_day.dart';
import '../../core/shifts/shift_and_cash_controller.dart';
import '../../core/theme/theme.dart';

/// Compulsory 5-Step First-Run Onboarding Wizard.
///
/// Guarantees clean installations never launch in an un-runnable headless state.
/// Enforces creation of both a Manager (4-8 digit PIN) and a distinct primary Cashier (4-digit PIN),
/// guides creation of the first sellable recipe, and opens the first Business Day.
class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({
    super.key,
    required this.authService,
    required this.shiftController,
    required this.catalogController,
    required this.onCompleted,
  });

  final AuthService authService;
  final ShiftAndCashController shiftController;
  final CatalogAndRecipeController catalogController;
  final void Function(Staff cashierStaff) onCompleted;

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int _currentStep = 0;
  bool _isLoading = false;
  String? _stepError;

  // Step 1: Restaurant Identity State
  final _step1FormKey = GlobalKey<FormState>();
  final _restaurantNameController = TextEditingController(text: 'ResturantPOS');
  final _localPathController = TextEditingController(text: r'C:\ProgramData\ResturantPOS\data');

  // Step 2: Manager Account State
  final _step2FormKey = GlobalKey<FormState>();
  final _managerNameController = TextEditingController(text: 'Restaurant Manager');
  final _managerPinController = TextEditingController();
  final _managerConfirmPinController = TextEditingController();
  bool _obscureManagerPin = true;
  Staff? _createdManager;

  // Step 3: Cashier Account State
  final _step3FormKey = GlobalKey<FormState>();
  final _cashierNameController = TextEditingController(text: 'Primary Cashier');
  final _cashierPinController = TextEditingController();
  final _cashierConfirmPinController = TextEditingController();
  bool _obscureCashierPin = true;
  Staff? _createdCashier;

  // Step 4: Recipe Creation State
  final _step4FormKey = GlobalKey<FormState>();
  final _menuItemNameController = TextEditingController(text: 'Classic Smash Burger');
  final _categoryNameController = TextEditingController(text: 'Burgers');
  final _menuItemPriceController = TextEditingController(text: '450.00');
  final _ingredientNameController = TextEditingController(text: 'Beef Patty');
  final _ingredientStockController = TextEditingController(text: '10000');
  final _ingredientCostController = TextEditingController(text: '1.20');
  final _recipeQtyController = TextEditingController(text: '150');
  StorageUnit _selectedStorageUnit = StorageUnit.g;

  // Step 5: Business Day & Handover State
  BusinessDay? _openedBusinessDay;

  @override
  void dispose() {
    _restaurantNameController.dispose();
    _localPathController.dispose();
    _managerNameController.dispose();
    _managerPinController.dispose();
    _managerConfirmPinController.dispose();
    _cashierNameController.dispose();
    _cashierPinController.dispose();
    _cashierConfirmPinController.dispose();
    _menuItemNameController.dispose();
    _categoryNameController.dispose();
    _menuItemPriceController.dispose();
    _ingredientNameController.dispose();
    _ingredientStockController.dispose();
    _ingredientCostController.dispose();
    _recipeQtyController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // STEP ACTIONS
  // ===========================================================================

  Future<void> _handleStep1Submit() async {
    if (!_step1FormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _stepError = null;
    });

    try {
      final now = DateTime.now().toIso8601String();
      await widget.authService.database.insert(
        PosDatabaseConstants.tableSystemSettings,
        {
          'key': PosDatabaseConstants.settingRestaurantName,
          'value': _restaurantNameController.text.trim(),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await widget.authService.database.insert(
        PosDatabaseConstants.tableSystemSettings,
        {
          'key': PosDatabaseConstants.settingCurrencyCode,
          'value': PosDatabaseConstants.defaultCurrencyCode,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await widget.authService.database.insert(
        PosDatabaseConstants.tableSystemSettings,
        {
          'key': PosDatabaseConstants.settingDefaultTaxRate,
          'value': '0.0',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await widget.authService.database.insert(
        PosDatabaseConstants.tableSystemSettings,
        {
          'key': PosDatabaseConstants.settingTaxInclusive,
          'value': 'true',
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await widget.authService.database.insert(
        PosDatabaseConstants.tableSystemSettings,
        {
          'key': PosDatabaseConstants.settingLocalBackupPath,
          'value': _localPathController.text.trim(),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      setState(() {
        _isLoading = false;
        _currentStep = 1;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _stepError = 'Failed to save settings: $e';
      });
    }
  }

  Future<void> _handleStep2Submit() async {
    if (!_step2FormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _stepError = null;
    });

    try {
      // Find or create Management department
      final depts = await widget.authService.getDepartments();
      Department mgmtDept = depts.firstWhere(
        (d) => d.name.toLowerCase() == 'management',
        orElse: () => depts.first,
      );

      final manager = await widget.authService.registerStaff(
        name: _managerNameController.text.trim(),
        departmentId: mgmtDept.id,
        role: StaffRole.manager,
        pin: _managerPinController.text.trim(),
      );

      setState(() {
        _createdManager = manager;
        _isLoading = false;
        _currentStep = 2;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _stepError = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    }
  }

  Future<void> _handleStep3Submit() async {
    if (!_step3FormKey.currentState!.validate()) return;
    final cashierPin = _cashierPinController.text.trim();
    final managerPin = _managerPinController.text.trim();

    if (cashierPin == managerPin) {
      setState(() {
        _stepError = 'Cashier PIN must be different from Manager PIN.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _stepError = null;
    });

    try {
      // Find or create Front Counter department
      final depts = await widget.authService.getDepartments();
      Department counterDept = depts.firstWhere(
        (d) => d.name.toLowerCase() == 'front counter',
        orElse: () => depts.first,
      );

      final cashier = await widget.authService.registerStaff(
        name: _cashierNameController.text.trim(),
        departmentId: counterDept.id,
        role: StaffRole.cashier,
        pin: cashierPin,
      );

      setState(() {
        _createdCashier = cashier;
        _isLoading = false;
        _currentStep = 3;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _stepError = e.toString().replaceFirst('Exception: ', '').replaceFirst('ArgumentError: ', '');
      });
    }
  }

  Future<void> _handleStep4Submit() async {
    if (!_step4FormKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _stepError = null;
    });

    try {
      // 1. Create or resolve Category
      final catName = _categoryNameController.text.trim();
      final cat = await widget.catalogController.createCategory(
        name: catName,
        displayOrder: 1,
        colorHex: '#FFC400',
      );

      // 2. Create Raw Ingredient
      final ingredientName = _ingredientNameController.text.trim();
      final initialStock = double.parse(_ingredientStockController.text.trim());
      final unitCost = double.parse(_ingredientCostController.text.trim());

      final rawIngredient = await widget.catalogController.createRawIngredient(
        name: ingredientName,
        storageUnit: _selectedStorageUnit,
        currentStock: initialStock,
        lowStockThreshold: initialStock * 0.2,
        costPerRecipeUnit: unitCost,
      );

      // 3. Create Menu Item
      final itemName = _menuItemNameController.text.trim();
      final itemPrice = double.parse(_menuItemPriceController.text.trim());
      final recipeQty = double.parse(_recipeQtyController.text.trim());

      final menuItem = await widget.catalogController.createMenuItem(
        categoryId: cat.id,
        name: itemName,
        basePrice: itemPrice,
        isTaxInclusive: true,
        taxRate: 0.0,
      );

      // 4. Create Recipe Item linking menuItem to rawIngredient
      await widget.catalogController.addOrUpdateRecipeItem(
        menuItemId: menuItem.id,
        rawIngredientId: rawIngredient.id,
        quantity: recipeQty,
      );

      setState(() {
        _isLoading = false;
        _currentStep = 4;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _stepError = 'Failed to create recipe: $e';
      });
    }
  }

  Future<void> _handleOpenFirstBusinessDay() async {
    if (_createdManager == null) return;
    setState(() {
      _isLoading = true;
      _stepError = null;
    });

    try {
      final day = await widget.shiftController.openBusinessDay(
        openedByStaffId: _createdManager!.id,
      );

      setState(() {
        _openedBusinessDay = day;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _stepError = 'Failed to open Business Day: $e';
      });
    }
  }

  Future<void> _handleFinishAndSwitchToCashier() async {
    if (_createdCashier == null) return;
    setState(() => _isLoading = true);
    try {
      await widget.authService.completeOnboarding();
      widget.onCompleted(_createdCashier!);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _stepError = 'Failed to finalize onboarding: $e';
      });
    }
  }

  // ===========================================================================
  // BUILD METHOD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WarmCounterColors.lightPageBackground,
      appBar: AppBar(
        backgroundColor: WarmCounterColors.lightCardBackground,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(WarmCounterSpacing.space8),
              decoration: const BoxDecoration(
                color: WarmCounterColors.lightPrimaryAction,
                borderRadius: WarmCounterSpacing.controlBorderRadius,
              ),
              child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: WarmCounterSpacing.space12),
            Text(
              'Restaurant POS — First-Run Setup Wizard',
              style: WarmCounterTypography.pageHeading.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          margin: const EdgeInsets.all(WarmCounterSpacing.space24),
          decoration: BoxDecoration(
            color: WarmCounterColors.lightCardBackground,
            borderRadius: WarmCounterSpacing.panelBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Step Progress Indicator Bar
              _buildProgressHeader(),
              const Divider(height: 1, color: WarmCounterColors.lightBorder),

              // Active Step Form Content
              Padding(
                padding: const EdgeInsets.all(WarmCounterSpacing.space24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_stepError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(WarmCounterSpacing.space12),
                          decoration: BoxDecoration(
                            color: WarmCounterColors.lightDestructiveHighlight,
                            borderRadius: WarmCounterSpacing.controlBorderRadius,
                            border: Border.all(color: WarmCounterColors.lightDestructiveAction),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: WarmCounterColors.lightDestructiveAction, size: 20),
                              const SizedBox(width: WarmCounterSpacing.space8),
                              Expanded(
                                child: Text(
                                  _stepError!,
                                  style: const TextStyle(color: WarmCounterColors.lightDestructiveAction, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: WarmCounterSpacing.space16),
                      ],
                      if (_isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(WarmCounterSpacing.space32),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else
                        _buildCurrentStepContent(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // STEP HEADER
  // ===========================================================================

  Widget _buildProgressHeader() {
    final steps = [
      '1. Identity',
      '2. Manager',
      '3. Cashier',
      '4. Recipe',
      '5. Open Day',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WarmCounterSpacing.space24,
        vertical: WarmCounterSpacing.space16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;

          Color badgeColor;
          Color textColor;
          if (isCompleted) {
            badgeColor = const Color(0xFF047857);
            textColor = const Color(0xFF047857);
          } else if (isCurrent) {
            badgeColor = WarmCounterColors.lightPrimaryAction;
            textColor = WarmCounterColors.lightPrimaryAction;
          } else {
            badgeColor = WarmCounterColors.lightBorder;
            textColor = WarmCounterColors.lightSecondaryText;
          }

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted || isCurrent ? badgeColor : Colors.transparent,
                  border: Border.all(color: badgeColor, width: 1.5),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? Colors.white : textColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space8),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
              if (index < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: WarmCounterSpacing.space12),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: WarmCounterColors.lightBorder),
                ),
            ],
          );
        }),
      ),
    );
  }

  // ===========================================================================
  // STEP CONTENTS
  // ===========================================================================

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Identity();
      case 1:
        return _buildStep2Manager();
      case 2:
        return _buildStep3Cashier();
      case 3:
        return _buildStep4Recipe();
      case 4:
      default:
        return _buildStep5OpenDay();
    }
  }

  // --- STEP 1: IDENTITY ---
  Widget _buildStep1Identity() {
    return Form(
      key: _step1FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 1: Restaurant Identity',
            style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: WarmCounterSpacing.space4),
          Text(
            'Configure your restaurant branding, storage location, currency, and tax defaults.',
            style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          TextFormField(
            key: const ValueKey('restaurant_name_input'),
            controller: _restaurantNameController,
            decoration: const InputDecoration(
              labelText: 'Restaurant / Business Name *',
              hintText: 'e.g. Street Food Mafia',
              border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Restaurant name is required.' : null,
          ),
          const SizedBox(height: WarmCounterSpacing.space16),
          TextFormField(
            key: const ValueKey('local_path_input'),
            controller: _localPathController,
            decoration: const InputDecoration(
              labelText: 'Local Database & Storage Directory',
              border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
            ),
          ),
          const SizedBox(height: WarmCounterSpacing.space16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightPageBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Currency Standard', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      SizedBox(height: 4),
                      Text('PKR (Pakistani Rupee • 64-bit Paisa Engine)', style: TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(WarmCounterSpacing.space16),
                  decoration: BoxDecoration(
                    color: WarmCounterColors.lightPageBackground,
                    borderRadius: WarmCounterSpacing.controlBorderRadius,
                    border: Border.all(color: WarmCounterColors.lightBorder),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tax Configuration', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      SizedBox(height: 4),
                      Text('0.0% Tax-Inclusive Shelf Pricing (Internal Carve-Out)', style: TextStyle(color: WarmCounterColors.lightSecondaryText, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const ValueKey('step_1_next_button'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Next: Create Manager Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WarmCounterColors.lightPrimaryAction,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, WarmCounterSpacing.touchTargetMin),
              ),
              onPressed: _handleStep1Submit,
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2: MANAGER ACCOUNT ---
  Widget _buildStep2Manager() {
    return Form(
      key: _step2FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 2: Create Manager Account',
            style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: WarmCounterSpacing.space4),
          Text(
            'Create the primary administrative account with a secure 4–8 digit PIN.',
            style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          TextFormField(
            key: const ValueKey('manager_name_input'),
            controller: _managerNameController,
            decoration: const InputDecoration(
              labelText: 'Manager Full Name *',
              border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Manager name is required.' : null,
          ),
          const SizedBox(height: WarmCounterSpacing.space16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('manager_pin_input'),
                  controller: _managerPinController,
                  obscureText: _obscureManagerPin,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: InputDecoration(
                    labelText: 'Secure Manager PIN (4–8 Digits) *',
                    hintText: '4 to 8 digits',
                    counterText: '',
                    border: const OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureManagerPin ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureManagerPin = !_obscureManagerPin),
                    ),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty || int.tryParse(t) == null || t.length < 4 || t.length > 8) {
                      return 'Must be 4–8 numeric digits.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('manager_confirm_pin_input'),
                  controller: _managerConfirmPinController,
                  obscureText: _obscureManagerPin,
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Manager PIN *',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) {
                    if (v?.trim() != _managerPinController.text.trim()) {
                      return 'PINs do not match.';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const ValueKey('step_2_next_button'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Next: Create Primary Cashier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WarmCounterColors.lightPrimaryAction,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, WarmCounterSpacing.touchTargetMin),
              ),
              onPressed: _handleStep2Submit,
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 3: MANDATORY CASHIER ACCOUNT ---
  Widget _buildStep3Cashier() {
    return Form(
      key: _step3FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 3: Create Primary Cashier',
            style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: WarmCounterSpacing.space4),
          Container(
            padding: const EdgeInsets.all(WarmCounterSpacing.space12),
            decoration: BoxDecoration(
              color: WarmCounterColors.lightActiveNavHighlight,
              borderRadius: WarmCounterSpacing.controlBorderRadius,
              border: Border.all(color: WarmCounterColors.lightBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, color: WarmCounterColors.lightPrimaryAction, size: 22),
                const SizedBox(width: WarmCounterSpacing.space12),
                Expanded(
                  child: Text(
                    'Strict Two-Role Separation: Manager accounts are strictly forbidden from operating cash registers. A dedicated Cashier profile with a unique 4-digit PIN is mandatory.',
                    style: WarmCounterTypography.bodySmall.copyWith(
                      color: WarmCounterColors.lightPrimaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          TextFormField(
            key: const ValueKey('cashier_name_input'),
            controller: _cashierNameController,
            decoration: const InputDecoration(
              labelText: 'Cashier Full Name *',
              hintText: 'e.g. Counter Cashier 1',
              border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Cashier name is required.' : null,
          ),
          const SizedBox(height: WarmCounterSpacing.space16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('cashier_pin_input'),
                  controller: _cashierPinController,
                  obscureText: _obscureCashierPin,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: 'Unique Cashier PIN (4 Digits) *',
                    hintText: '4 numeric digits',
                    counterText: '',
                    border: const OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureCashierPin ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscureCashierPin = !_obscureCashierPin),
                    ),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty || int.tryParse(t) == null || t.length != 4) {
                      return 'Cashier PIN must be exactly 4 numeric digits.';
                    }
                    if (t == _managerPinController.text.trim()) {
                      return 'Cashier PIN must be different from Manager PIN.';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('cashier_confirm_pin_input'),
                  controller: _cashierConfirmPinController,
                  obscureText: _obscureCashierPin,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Cashier PIN *',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) {
                    if (v?.trim() != _cashierPinController.text.trim()) {
                      return 'PINs do not match.';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const ValueKey('step_3_next_button'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Next: Create First Recipe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WarmCounterColors.lightPrimaryAction,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, WarmCounterSpacing.touchTargetMin),
              ),
              onPressed: _handleStep3Submit,
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 4: FIRST RECIPE CREATOR ---
  Widget _buildStep4Recipe() {
    return Form(
      key: _step4FormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step 4: Create First Recipe',
            style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
          ),
          const SizedBox(height: WarmCounterSpacing.space4),
          Text(
            'Every sellable item in this system requires a recipe with linked raw ingredients for BOM stock deduction.',
            style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          // Menu Item Details
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const ValueKey('menu_item_name_input'),
                  controller: _menuItemNameController,
                  decoration: const InputDecoration(
                    labelText: 'Menu Item Name *',
                    hintText: 'e.g. Classic Smash Burger',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Item name required.' : null,
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('category_name_input'),
                  controller: _categoryNameController,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    hintText: 'e.g. Burgers',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Category required.' : null,
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('menu_item_price_input'),
                  controller: _menuItemPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Selling Price (Rs.) *',
                    hintText: '450.00',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (double.tryParse(v ?? '') == null) ? 'Valid price required.' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),

          // Raw Ingredient & Recipe Consumption
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  key: const ValueKey('ingredient_name_input'),
                  controller: _ingredientNameController,
                  decoration: const InputDecoration(
                    labelText: 'Raw Ingredient Name *',
                    hintText: 'e.g. Beef Patty',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingredient name required.' : null,
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              Expanded(
                child: DropdownButtonFormField<StorageUnit>(
                  isExpanded: true,
                  initialValue: _selectedStorageUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  items: StorageUnit.values.map((u) {
                    return DropdownMenuItem(value: u, child: Text(u.code));
                  }).toList(),
                  onChanged: (u) {
                    if (u != null) setState(() => _selectedStorageUnit = u);
                  },
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space12),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('ingredient_stock_input'),
                  controller: _ingredientStockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Initial Stock *',
                    hintText: '10000',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (double.tryParse(v ?? '') == null) ? 'Valid stock required.' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('ingredient_cost_input'),
                  controller: _ingredientCostController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Unit Cost (Rs. per unit) *',
                    hintText: '1.20',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (double.tryParse(v ?? '') == null) ? 'Valid unit cost required.' : null,
                ),
              ),
              const SizedBox(width: WarmCounterSpacing.space16),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('recipe_qty_input'),
                  controller: _recipeQtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'BOM Consumption Per Order *',
                    hintText: '150',
                    border: OutlineInputBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  validator: (v) => (double.tryParse(v ?? '') == null) ? 'Valid quantity required.' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: WarmCounterSpacing.space24),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              key: const ValueKey('step_4_next_button'),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Next: Open Business Day'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WarmCounterColors.lightPrimaryAction,
                foregroundColor: Colors.white,
                minimumSize: const Size(220, WarmCounterSpacing.touchTargetMin),
              ),
              onPressed: _handleStep4Submit,
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 5: OPEN BUSINESS DAY & HANDOVER ---
  Widget _buildStep5OpenDay() {
    final isDayOpen = _openedBusinessDay != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 5: Open First Business Day',
          style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
        ),
        const SizedBox(height: WarmCounterSpacing.space4),
        Text(
          'The Manager must officially open the first Business Day to start daily operations and initialize daily tokens (#01).',
          style: WarmCounterTypography.bodyMedium.copyWith(color: WarmCounterColors.lightSecondaryText),
        ),
        const SizedBox(height: WarmCounterSpacing.space24),

        // Accounts summary card
        Container(
          padding: const EdgeInsets.all(WarmCounterSpacing.space16),
          decoration: BoxDecoration(
            color: WarmCounterColors.lightPageBackground,
            borderRadius: WarmCounterSpacing.controlBorderRadius,
            border: Border.all(color: WarmCounterColors.lightBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Configured Manager:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('${_createdManager?.name ?? "Manager"} (Admin)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Configured Primary Cashier:', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('${_createdCashier?.name ?? "Cashier"} (Front Counter)', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: WarmCounterSpacing.space24),

        if (!isDayOpen) ...[
          Center(
            child: ElevatedButton.icon(
              key: const ValueKey('open_first_business_day_button'),
              icon: const Icon(Icons.wb_sunny_rounded, size: 20),
              label: const Text('Manager Authorize & Open Business Day #1'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WarmCounterColors.lightPrimaryAction,
                foregroundColor: Colors.white,
                minimumSize: const Size(300, 52),
                shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
              ),
              onPressed: _handleOpenFirstBusinessDay,
            ),
          ),
        ] else ...[
          // Day is open -> Guided switch to cashier prompt
          Container(
            padding: const EdgeInsets.all(WarmCounterSpacing.space16),
            decoration: BoxDecoration(
              color: WarmCounterColors.lightActiveNavHighlight,
              borderRadius: WarmCounterSpacing.panelBorderRadius,
              border: Border.all(color: WarmCounterColors.lightBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: WarmCounterColors.lightPrimaryAction, size: 32),
                    const SizedBox(width: WarmCounterSpacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Business Day #1 is Officially Open!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: WarmCounterColors.lightPrimaryText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Strict Two-Role Policy: Manager credentials cannot operate register billing or drawer shifts. Handing over to Cashier "${_createdCashier?.name}".',
                            style: const TextStyle(fontSize: 13, color: WarmCounterColors.lightSecondaryText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WarmCounterSpacing.space16),
                ElevatedButton.icon(
                  key: const ValueKey('switch_to_cashier_button'),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 20),
                  label: const Text('Switch to Cashier & Open Register Shift'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: WarmCounterColors.lightPrimaryAction,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(320, WarmCounterSpacing.touchTargetMin),
                    shape: const RoundedRectangleBorder(borderRadius: WarmCounterSpacing.controlBorderRadius),
                  ),
                  onPressed: _handleFinishAndSwitchToCashier,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
