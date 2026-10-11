/// Represents a menu item category with display ordering and color coding.
class MenuCategory {
  const MenuCategory({
    required this.id,
    required this.name,
    required this.displayOrder,
    required this.colorHex,
    this.createdAt,
  });

  final int id;
  final String name;
  final int displayOrder;
  final String colorHex;
  final DateTime? createdAt;

  factory MenuCategory.fromMap(Map<String, Object?> map) {
    return MenuCategory(
      id: map['id'] as int,
      name: map['name'] as String,
      displayOrder: (map['display_order'] as int?) ?? 0,
      colorHex: (map['color_hex'] as String?) ?? '#2E7D32',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'display_order': displayOrder,
      'color_hex': colorHex,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  MenuCategory copyWith({
    int? id,
    String? name,
    int? displayOrder,
    String? colorHex,
    DateTime? createdAt,
  }) {
    return MenuCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      colorHex: colorHex ?? this.colorHex,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
