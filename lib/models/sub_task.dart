/// A sub-task under an initiative. Progress is computed from completed sub-tasks.
class SubTask {
  final String id;
  final String initiativeId;
  final String label;
  final bool isCompleted;

  const SubTask({
    required this.id,
    required this.initiativeId,
    required this.label,
    this.isCompleted = false,
  });

  SubTask copyWith({
    String? id,
    String? initiativeId,
    String? label,
    bool? isCompleted,
  }) {
    return SubTask(
      id: id ?? this.id,
      initiativeId: initiativeId ?? this.initiativeId,
      label: label ?? this.label,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
