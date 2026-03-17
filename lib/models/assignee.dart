/// Represents a team member who can be assigned tasks.
class Assignee {
  final String id;
  final String name;

  const Assignee({required this.id, required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Assignee && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}
