import 'package:flutter/material.dart';
import 'package:resturant_sys/core/catalog/raw_ingredient.dart';
import 'package:resturant_sys/core/procurement/kitchen_wastage.dart';
import 'package:resturant_sys/core/procurement/procurement_and_wastage_controller.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'kitchen_wastage_workspace.dart';

/// Modal dialog wrapping the Kitchen Wastage workspace for modal launching.
class KitchenWastageDialog extends StatelessWidget {
  const KitchenWastageDialog({
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
                'Kitchen Wastage Log',
                style: WarmCounterTypography.pageHeading.copyWith(fontSize: 18),
              ),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: KitchenWastageWorkspace(
              controller: controller,
              initialIngredients: initialIngredients,
              initialWastageLogs: initialWastageLogs,
              onWastageLogged: onWastageLogged,
            ),
          ),
        ),
      ),
    );
  }
}
