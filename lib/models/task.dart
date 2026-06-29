/// Status of a task (low-level view: Not started, In progress, Completed).
enum TaskStatus { todo, inProgress, done }

const Map<TaskStatus, String> taskStatusDisplayNames = {
  TaskStatus.todo: 'Not started',
  TaskStatus.inProgress: 'In progress',
  TaskStatus.done: 'Completed',
};

/// Low-level task (Planner-style) assigned by Directors to Responsible Officers.
class Task {
  static const Object _unsetChangeDueReason = Object();

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

  /// True when this row comes from singular [`task`] (not legacy [`tasks`]).
  final bool isSingularTableRow;

  /// Raw `task.status` from DB for singular table (e.g. Incomplete, Completed).
  final String? dbStatus;

  /// Last updater display name (singular `task.update_by` → `staff.name`).
  final String? updateByStaffName;

  /// Creator display name (singular `task.create_by` → `staff.name`).
  final String? createByStaffName;

  /// Creator as assignee key (`staff.app_id` when known), for "My tasks" filter.
  final String? createByAssigneeKey;

  /// Person in charge (`staff.app_id` when known); mirrors singular `task.pic` (staff id in DB).
  final String? pic;

  /// Last update time from singular `task.update_date`.
  final DateTime? updateDate;

  /// Denormalized last activity: task row updates vs `comment` (Supabase `task.last_updated`).
  final DateTime? lastUpdated;

  /// PIC/creator workflow: `Submitted`, `Accepted`, `Returned`, or null.
  final String? submission;

  /// When PIC clicked **Submit** (`task.submit_date`, HK instant written by app).
  final DateTime? submitDate;

  /// When task became **Completed**; product rule: equals [submitDate] at accept (`task.completion_date`).
  final DateTime? completionDate;

  /// Manual archive marker for completed tasks. Deleted tasks are archived by status.
  final DateTime? archivedAt;
  final String? archivedByStaffId;

  /// When start→due span exceeds policy for priority (`task.change_due_reason`).
  final String? changeDueReason;

  /// `Paused` | `Not Paused`; parent project pause is computed separately.
  final String pauseStatus;

  /// HK calendar days past due from DB (`task.overdue_day`); 0 when not overdue.
  final int overdueDay;

  /// `Yes` / `No` from DB (`task.overdue`); aligns with [overdueDay] > 0.
  final String overdue;

  /// Singular `task.project_id` → [`project`].
  final String? projectId;

  /// [`project.name`] when joined at load time (search / cards).
  final String? projectName;

  /// [`project.description`] when joined at load time (landing search).
  final String? projectDescription;

  bool get isArchivedCompleted => archivedAt != null;

  bool get isPaused => pauseStatus.trim().toLowerCase() == 'paused';

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
    this.isSingularTableRow = false,
    this.dbStatus,
    this.updateByStaffName,
    this.createByStaffName,
    this.createByAssigneeKey,
    this.pic,
    this.updateDate,
    this.lastUpdated,
    this.submission,
    this.submitDate,
    this.completionDate,
    this.archivedAt,
    this.archivedByStaffId,
    this.changeDueReason,
    this.pauseStatus = 'Not Paused',
    this.overdueDay = 0,
    this.overdue = 'No',
    this.projectId,
    this.projectName,
    this.projectDescription,
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
    bool? isSingularTableRow,
    String? dbStatus,
    String? updateByStaffName,
    String? createByStaffName,
    String? createByAssigneeKey,
    String? pic,
    DateTime? updateDate,
    DateTime? lastUpdated,
    bool clearLastUpdated = false,
    String? submission,
    DateTime? submitDate,
    bool clearSubmitDate = false,
    DateTime? completionDate,
    bool clearCompletionDate = false,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
    String? archivedByStaffId,
    bool clearArchivedByStaffId = false,
    Object? changeDueReason = _unsetChangeDueReason,
    String? pauseStatus,
    int? overdueDay,
    String? overdue,
    String? projectId,
    String? projectName,
    String? projectDescription,
    bool clearProject = false,
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
      isSingularTableRow: isSingularTableRow ?? this.isSingularTableRow,
      dbStatus: dbStatus ?? this.dbStatus,
      updateByStaffName: updateByStaffName ?? this.updateByStaffName,
      createByStaffName: createByStaffName ?? this.createByStaffName,
      createByAssigneeKey: createByAssigneeKey ?? this.createByAssigneeKey,
      pic: pic ?? this.pic,
      updateDate: updateDate ?? this.updateDate,
      lastUpdated: clearLastUpdated ? null : (lastUpdated ?? this.lastUpdated),
      submission: submission ?? this.submission,
      submitDate: clearSubmitDate ? null : (submitDate ?? this.submitDate),
      completionDate: clearCompletionDate
          ? null
          : (completionDate ?? this.completionDate),
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      archivedByStaffId: clearArchivedByStaffId
          ? null
          : (archivedByStaffId ?? this.archivedByStaffId),
      changeDueReason: identical(changeDueReason, _unsetChangeDueReason)
          ? this.changeDueReason
          : changeDueReason as String?,
      pauseStatus: pauseStatus ?? this.pauseStatus,
      overdueDay: overdueDay ?? this.overdueDay,
      overdue: overdue ?? this.overdue,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      projectName: clearProject ? null : (projectName ?? this.projectName),
      projectDescription: clearProject
          ? null
          : (projectDescription ?? this.projectDescription),
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
