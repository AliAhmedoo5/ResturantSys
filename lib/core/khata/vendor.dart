/// Domain entity representing a raw ingredient supplier / vendor.
class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.phone,
    this.suppliedIngredients,
    required this.openingBalance,
    required this.currentBalance,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final String phone;
  final String? suppliedIngredients;
  final double openingBalance;
  final double currentBalance;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasOutstandingPayable => currentBalance > 0.001;

  factory Vendor.fromMap(Map<String, dynamic> map) {
    return Vendor(
      id: map['id'] as int,
      name: map['name'] as String,
      phone: map['phone'] as String,
      suppliedIngredients: map['supplied_ingredients'] as String?,
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
      currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id > 0) 'id': id,
      'name': name,
      'phone': phone,
      'supplied_ingredients': suppliedIngredients,
      'opening_balance': openingBalance,
      'current_balance': currentBalance,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Vendor copyWith({
    int? id,
    String? name,
    String? phone,
    String? suppliedIngredients,
    double? openingBalance,
    double? currentBalance,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vendor(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      suppliedIngredients: suppliedIngredients ?? this.suppliedIngredients,
      openingBalance: openingBalance ?? this.openingBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
