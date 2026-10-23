/// An editable staff job title. Job roles never grant POS permissions.
class JobRole {
  const JobRole({required this.id, required this.name});

  final int id;
  final String name;

  factory JobRole.fromMap(Map<String, Object?> row) =>
      JobRole(id: row['id'] as int, name: row['name'] as String);
}
