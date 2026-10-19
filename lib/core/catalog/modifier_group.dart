import 'modifier.dart';

/// Selection constraints for a menu item's customization options.
class ModifierGroup {
  const ModifierGroup({required this.id, required this.menuItemId, required this.name, this.selectionMode = 'SINGLE', this.minSelected = 0, this.maxSelected = 1, this.isRequired = false});
  final int id;
  final int menuItemId;
  final String name;
  final String selectionMode;
  final int minSelected;
  final int maxSelected;
  final bool isRequired;
  int get requiredCount => isRequired && minSelected == 0 ? 1 : minSelected;

  void validate() {
    if (name.trim().isEmpty || !['SINGLE', 'MULTIPLE'].contains(selectionMode) || minSelected < 0 || maxSelected < 1 || minSelected > maxSelected || (selectionMode == 'SINGLE' && maxSelected != 1)) {
      throw ArgumentError('Invalid modifier group selection limits.');
    }
  }

  factory ModifierGroup.fromMap(Map<String, Object?> row) => ModifierGroup(id: row['id'] as int, menuItemId: row['menu_item_id'] as int, name: row['name'] as String, selectionMode: row['selection_mode'] as String, minSelected: row['min_selected'] as int, maxSelected: row['max_selected'] as int, isRequired: row['is_required'] == 1);
  Map<String, Object?> toMap() => {'menu_item_id': menuItemId, 'name': name.trim(), 'selection_mode': selectionMode, 'min_selected': minSelected, 'max_selected': maxSelected, 'is_required': isRequired ? 1 : 0};
}

abstract final class ModifierSelection {
  static List<Modifier> select(List<Modifier> current, Modifier option, {bool selected = true}) {
    final result = current.where((m) => m.id != option.id && !(selected && option.group?.selectionMode == 'SINGLE' && m.groupId == option.groupId)).toList();
    if (selected) result.add(option);
    return result;
  }

  static void validate(List<Modifier> selected, List<ModifierGroup> groups) {
    if (selected.map((m) => m.id).toSet().length != selected.length) throw StateError('A modifier cannot be selected twice.');
    for (final group in groups) {
      final count = selected.where((m) => m.groupId == group.id).length;
      if (count < group.requiredCount || count > group.maxSelected) throw StateError('${group.name}: choose ${group.requiredCount} to ${group.maxSelected} options.');
    }
  }
}
