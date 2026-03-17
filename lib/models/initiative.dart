/// High-level initiative assigned by Professor to Directors. Tracks milestones and progress.
class Initiative {
  final String id;
  final String teamId;
  final List<String> directorIds;
  final String name;
  final String description;
  final int priority; // 1 = Standard, 2 = Urgent
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;

  const Initiative({
    required this.id,
    required this.teamId,
    required this.directorIds,
    required this.name,
    required this.description,
    required this.priority,
    this.startDate,
    this.endDate,
    required this.createdAt,
  });

  Initiative copyWith({
    String? id,
    String? teamId,
    List<String>? directorIds,
    String? name,
    String? description,
    int? priority,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
  }) {
    return Initiative(
      id: id ?? this.id,
      teamId: teamId ?? this.teamId,
      directorIds: directorIds ?? this.directorIds,
      name: name ?? this.name,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
