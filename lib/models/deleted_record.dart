import 'sub_task.dart';

/// Audit record for a deleted sub-task (initiative level).
class DeletedSubTaskRecord {
  final SubTask subTask;
  final DateTime deletedAt;
  final String deletedByName;

  const DeletedSubTaskRecord({
    required this.subTask,
    required this.deletedAt,
    required this.deletedByName,
  });
}

/// Snapshot of a deleted low-level task for audit.
class DeletedTaskRecord {
  final String taskId;
  final String taskName;
  final String? teamId;
  final List<String> assigneeIds;
  final DateTime deletedAt;
  final String deletedByName;

  const DeletedTaskRecord({
    required this.taskId,
    required this.taskName,
    this.teamId,
    this.assigneeIds = const [],
    required this.deletedAt,
    required this.deletedByName,
  });
}
