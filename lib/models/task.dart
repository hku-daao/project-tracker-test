import 'comment.dart';
import 'milestone.dart';

/// Status of a task (low-level view: Not started, In progress, Completed).
enum TaskStatus {
  todo,
  inProgress,
  done,
}

const Map<TaskStatus, String> taskStatusDisplayNames = {
  TaskStatus.todo: 'Not started',
  TaskStatus.inProgress: 'In progress',
  TaskStatus.done: 'Completed',
};

/// Low-level task (Planner-style) assigned by Directors to Responsible Officers.
class Task {
  final String id;
  /// Optional team ID for low-level view (filter officers by team).
  final String? teamId;
  final String name;
  final String description;
  final List<String> assigneeIds; // Responsible Officer IDs
  final int priority; // 1 = Standard, 2 = Urgent
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final TaskStatus status; // Not started, In progress, Completed
  final int progressPercent; // 0-100 (low-level: optional, derived from status)
  final List<Milestone> milestones;
  final List<TaskComment> comments;

  /// True when this row comes from singular [`task`] (not legacy [`tasks`]).
  final bool isSingularTableRow;

  /// Raw `task.status` from DB for singular table (e.g. Incomplete, Completed).
  final String? dbStatus;

  /// Last updater display name (singular `task.update_by` → `staff.name`).
  final String? updateByStaffName;

  /// Last update time from singular `task.update_date`.
  final DateTime? updateDate;

  const Task({
    required this.id,
    this.teamId,
    required this.name,
    required this.description,
    required this.assigneeIds,
    required this.priority,
    this.startDate,
    this.endDate,
    required this.createdAt,
    this.status = TaskStatus.todo,
    this.progressPercent = 0,
    this.milestones = const [],
    this.comments = const [],
    this.isSingularTableRow = false,
    this.dbStatus,
    this.updateByStaffName,
    this.updateDate,
  });

  Task copyWith({
    String? id,
    String? teamId,
    String? name,
    String? description,
    List<String>? assigneeIds,
    int? priority,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    TaskStatus? status,
    int? progressPercent,
    List<Milestone>? milestones,
    List<TaskComment>? comments,
    bool? isSingularTableRow,
    String? dbStatus,
    String? updateByStaffName,
    DateTime? updateDate,
  }) {
    return Task(
      id: id ?? this.id,
      teamId: teamId ?? this.teamId,
      name: name ?? this.name,
      description: description ?? this.description,
      assigneeIds: assigneeIds ?? this.assigneeIds,
      priority: priority ?? this.priority,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      progressPercent: progressPercent ?? this.progressPercent,
      milestones: milestones ?? this.milestones,
      comments: comments ?? this.comments,
      isSingularTableRow: isSingularTableRow ?? this.isSingularTableRow,
      dbStatus: dbStatus ?? this.dbStatus,
      updateByStaffName: updateByStaffName ?? this.updateByStaffName,
      updateDate: updateDate ?? this.updateDate,
    );
  }

  bool get isOverdue {
    if (endDate == null || status == TaskStatus.done) return false;
    return DateTime.now().isAfter(endDate!);
  }

  int get delayDays {
    if (endDate == null || status == TaskStatus.done) return 0;
    if (!isOverdue) return 0;
    return DateTime.now().difference(endDate!).inDays;
  }

  /// For backward compatibility where due date is used in display.
  DateTime? get dueDate => endDate;
}
