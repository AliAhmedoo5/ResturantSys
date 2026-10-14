import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/procurement/mandi_procurement.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'quick_mandi_purchase_workspace.dart';

/// Modal dialog wrapping the Quick Mandi Purchase workspace for modal launching.
class QuickMandiPurchaseDialog extends StatelessWidget {
  const QuickMandiPurchaseDialog({
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
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 720),
        child: ClipRRect(
          borderRadius: WarmCounterSpacing.panelBorderRadius,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: WarmCounterColors.lightCardBackground,
              elevation: 0,
              title: Text(
                'Quick Mandi Purchase',
                style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: QuickMandiPurchaseWorkspace(
              controller: controller,
              initialIngredients: initialIngredients,
              initialProcurements: initialProcurements,
              onProcurementCompleted: onProcurementCompleted,
            ),
          ),
        ),
      ),
    );
  }
}
