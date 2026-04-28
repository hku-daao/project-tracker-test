/// Row from `public.subtask` (child of singular `task`).
class SingularSubtask {
  static const Object _unsetChangeDueReason = Object();

  const SingularSubtask({
    required this.id,
    required this.taskId,
    this.createByStaffId,
    this.createByStaffName,
    required this.subtaskName,
    required this.description,
    required this.priority,
    this.startDate,
    this.dueDate,
    required this.status,
    this.submission,
    this.submitDate,
    this.completionDate,
    required this.assigneeIds,
    this.pic,
    this.createDate,
    this.updateDate,
    this.updateByStaffName,
    this.changeDueReason,
    this.overdueDay = 0,
    this.overdue = 'No',
  });

  final String id;
  final String taskId;

  /// `staff.id` uuid
  final String? createByStaffId;

  /// Resolved from `subtask.create_by` → `staff.name` (same as [Task.createByStaffName]).
  final String? createByStaffName;
  final String subtaskName;
  final String description;

  /// 1 = Standard, 2 = URGENT
  final int priority;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String status;
  final String? submission;

  /// When assignee clicked **Submit** (`subtask.submit_date`).
  final DateTime? submitDate;

  /// When sub-task became **Completed** (`subtask.completion_date`).
  final DateTime? completionDate;

  /// Resolved to `staff.app_id` where possible (same as [Task.assigneeIds]).
  final List<String> assigneeIds;

  /// PIC as `staff.app_id` or uuid string.
  final String? pic;
  final DateTime? createDate;
  final DateTime? updateDate;

  /// Resolved from `subtask.update_by` → `staff.name`.
  final String? updateByStaffName;

  /// When start→due span exceeds policy (`subtask.change_due_reason`).
  final String? changeDueReason;

  /// HK calendar days past due (`subtask.overdue_day`).
  final int overdueDay;

  /// `Yes` / `No` (`subtask.overdue`).
  final String overdue;

  bool get isDeleted => status.trim().toLowerCase() == 'deleted';

  /// Comma-separated staff names (same order as `assignee_01`… in DB).
  String assigneeNamesDisplayLine(String Function(String assigneeKey) nameFor) {
    if (assigneeIds.isEmpty) return '—';
    return assigneeIds.map((id) => nameFor(id)).join(', ');
  }

  /// Resolved display name for [pic], or em dash.
  String picDisplayName(String Function(String assigneeKey) nameFor) {
    final p = pic?.trim();
    if (p == null || p.isEmpty) return '—';
    return nameFor(p);
  }

  SingularSubtask copyWith({
    String? id,
    String? taskId,
    String? createByStaffId,
    String? createByStaffName,
    String? subtaskName,
    String? description,
    int? priority,
    DateTime? startDate,
    DateTime? dueDate,
    String? status,
    String? submission,
    DateTime? submitDate,
    bool clearSubmitDate = false,
    DateTime? completionDate,
    bool clearCompletionDate = false,
    List<String>? assigneeIds,
    String? pic,
    DateTime? createDate,
    DateTime? updateDate,
    String? updateByStaffName,
    Object? changeDueReason = _unsetChangeDueReason,
    int? overdueDay,
    String? overdue,
  }) {
    return SingularSubtask(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      createByStaffId: createByStaffId ?? this.createByStaffId,
      createByStaffName: createByStaffName ?? this.createByStaffName,
      subtaskName: subtaskName ?? this.subtaskName,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      startDate: startDate ?? this.startDate,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      submission: submission ?? this.submission,
      submitDate: clearSubmitDate ? null : (submitDate ?? this.submitDate),
      completionDate: clearCompletionDate
          ? null
          : (completionDate ?? this.completionDate),
      assigneeIds: assigneeIds ?? this.assigneeIds,
      pic: pic ?? this.pic,
      createDate: createDate ?? this.createDate,
      updateDate: updateDate ?? this.updateDate,
      updateByStaffName: updateByStaffName ?? this.updateByStaffName,
      changeDueReason: identical(changeDueReason, _unsetChangeDueReason)
          ? this.changeDueReason
          : changeDueReason as String?,
      overdueDay: overdueDay ?? this.overdueDay,
      overdue: overdue ?? this.overdue,
    );
  }
}

/// Display row for `subtask_comment` (mirrors [SingularCommentRowDisplay]).
class SubtaskCommentRowDisplay {
  const SubtaskCommentRowDisplay({
    required this.id,
    required this.description,
    required this.status,
    this.createByStaffId,
    required this.displayStaffName,
    this.createTimestampUtc,
    this.updateTimestampUtc,
  });

  final String id;
  final String description;
  final String status;
  final String? createByStaffId;
  final String displayStaffName;
  final DateTime? createTimestampUtc;
  final DateTime? updateTimestampUtc;

  bool get isDeleted => status.trim().toLowerCase() == 'deleted';
}
