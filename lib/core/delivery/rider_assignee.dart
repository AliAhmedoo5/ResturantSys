/// An active staff member who can carry a delivery trip.
///
/// Assignment does not grant a POS login or require an interactive account role.
class RiderAssignee {
  const RiderAssignee({required this.id, required this.name});

  final int id;
  final String name;

  factory RiderAssignee.fromMap(Map<String, Object?> map) => RiderAssignee(
    id: map['id'] as int,
    name: map['name'] as String,
  );
}
