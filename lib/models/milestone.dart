/// A milestone for a task to track quantitative progress (e.g. 60% done).
class Milestone {
  final String id;
  final String taskId;
  final String label;
  final int progressPercent; // 0-100
  final DateTime? completedAt;
  final bool isCompleted;

  const Milestone({
    required this.id,
    required this.taskId,
    required this.label,
    required this.progressPercent,
    this.completedAt,
    this.isCompleted = false,
  });

  Milestone copyWith({
    String? id,
    String? taskId,
    String? label,
    int? progressPercent,
    DateTime? completedAt,
    bool? isCompleted,
  }) {
    return Milestone(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      label: label ?? this.label,
      progressPercent: progressPercent ?? this.progressPercent,
      completedAt: completedAt ?? this.completedAt,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
