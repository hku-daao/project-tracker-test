import 'package:flutter/foundation.dart';
import 'models/assignee.dart';
import 'models/comment.dart';
import 'models/deleted_record.dart';
import 'models/initiative.dart';
import 'models/milestone.dart';
import 'models/sub_task.dart';
import 'models/task.dart';
import 'models/reminder.dart';
import 'models/team.dart';
import 'priority.dart';

/// Global app state: initiatives (high-level), tasks (low-level), assignees, teams, comments, milestones.
class AppState extends ChangeNotifier {
  final List<Assignee> _assignees = [
    // Directors
    const Assignee(id: 'may', name: 'May Wong'),
    const Assignee(id: 'olive', name: 'Olive Wong'),
    const Assignee(id: 'janice', name: 'Janice Chan'),
    const Assignee(id: 'ken', name: 'Ken Lee'),
    const Assignee(id: 'monica', name: 'Monica Wong'),
    // Alumni Team – Responsible Officers
    const Assignee(id: 'funa', name: 'Funa Li'),
    const Assignee(id: 'anthony_tai', name: 'Anthony Tai'),
    const Assignee(id: 'holly_tang', name: 'Holly Tang'),
    const Assignee(id: 'sally_oh', name: 'Sally Oh Yea Won'),
    const Assignee(id: 'sally_cheng', name: 'Sally Cheng'),
    const Assignee(id: 'rui_wang', name: 'Rui Wang'),
    const Assignee(id: 'i_ki_chan', name: 'I Ki Chan'),
    const Assignee(id: 'janelle_wong', name: 'Janelle Wong'),
    const Assignee(id: 'carol_luk', name: 'Carol Luk'),
    // Fundraising Team – Responsible Officers
    const Assignee(id: 'charlotte_siu', name: 'Charlotte Siu'),
    const Assignee(id: 'eva_tang', name: 'Eva Tang'),
    const Assignee(id: 'katerina', name: 'Katerina Au'),
    const Assignee(id: 'elaine_lam', name: 'Elaine Lam'),
    const Assignee(id: 'judi_tsang', name: 'Judi Tsang'),
    const Assignee(id: 'kelly_lee', name: 'Kelly Lee'),
    const Assignee(id: 'melody_tang', name: 'Melody Tang'),
    const Assignee(id: 'aura_lu', name: 'Aura Lu'),
    // Advancement Intelligence Team – Responsible Officers
    const Assignee(id: 'calvin_lee', name: 'Calvin Lee'),
    const Assignee(id: 'lunan_chow', name: 'Lunan Chow'),
    const Assignee(id: 'ken_wong', name: 'Ken Wong'),
    const Assignee(id: 'waikay_pang', name: 'Wai-kay Pang'),
  ];

  /// Teams with hierarchy: Directors and Responsible Officers (2.1.2, 2.1.3).
  static const List<Team> teams = [
    Team(
      id: 'alumni',
      name: 'Alumni Team',
      directorIds: ['monica'],
      officerIds: [
        'funa', 'anthony_tai', 'holly_tang', 'sally_oh', 'sally_cheng',
        'rui_wang', 'i_ki_chan', 'janelle_wong', 'carol_luk',
      ],
    ),
    Team(
      id: 'fundraising',
      name: 'Fundraising Team',
      directorIds: ['may', 'olive', 'janice'],
      officerIds: [
        'charlotte_siu', 'eva_tang', 'katerina', 'elaine_lam', 'judi_tsang',
        'kelly_lee', 'melody_tang', 'aura_lu',
      ],
    ),
    Team(
      id: 'advancement_intel',
      name: 'Advancement Intelligence Team',
      directorIds: ['ken'],
      officerIds: ['calvin_lee', 'lunan_chow', 'ken_wong', 'waikay_pang'],
    ),
  ];

  final List<Initiative> _initiatives = [];
  final List<Task> _tasks = [];
  final List<TaskComment> _comments = [];
  final List<Milestone> _milestones = [];
  final List<SubTask> _subTasks = [];
  final List<DeletedSubTaskRecord> _deletedSubTasks = [];
  final List<DeletedTaskRecord> _deletedTasks = [];

  int _initiativeIdCounter = 1;
  int _taskIdCounter = 1;
  int _commentIdCounter = 1;
  int _milestoneIdCounter = 1;
  int _subTaskIdCounter = 1;

  List<Assignee> get assignees => List.unmodifiable(_assignees);

  List<Initiative> get initiatives => List.unmodifiable(_initiatives);

  List<Task> get tasks {
    return _tasks.map((t) => _taskWithCommentsAndMilestones(t)).toList();
  }

  Task _taskWithCommentsAndMilestones(Task t) {
    final taskComments = _comments.where((c) => c.taskId == t.id).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final taskMilestones =
        _milestones.where((m) => m.taskId == t.id).toList();
    return t.copyWith(
      comments: taskComments,
      milestones: taskMilestones,
    );
  }

  Assignee? assigneeById(String id) {
    try {
      return _assignees.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Initiative? initiativeById(String id) {
    try {
      return _initiatives.firstWhere((x) => x.id == id);
    } catch (_) {
      return null;
    }
  }


  List<TaskComment> commentsForTaskOrInitiative(String taskOrInitiativeId) {
    return _comments.where((c) => c.taskId == taskOrInitiativeId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<Milestone> milestonesForTaskOrInitiative(String taskOrInitiativeId) {
    return _milestones.where((m) => m.taskId == taskOrInitiativeId).toList();
  }

  List<SubTask> subTasksForInitiative(String initiativeId) {
    return _subTasks.where((s) => s.initiativeId == initiativeId).toList();
  }

  List<DeletedSubTaskRecord> deletedSubTasksForInitiative(String initiativeId) {
    return _deletedSubTasks
        .where((r) => r.subTask.initiativeId == initiativeId)
        .toList();
  }

  List<DeletedTaskRecord> get deletedTasks => List.unmodifiable(_deletedTasks);

  List<DeletedTaskRecord> deletedTasksForTeam(String? teamId) {
    if (teamId == null || teamId.isEmpty) return _deletedTasks;
    return _deletedTasks.where((r) => r.teamId == teamId).toList();
  }

  /// Deleted tasks that were assigned to this assignee (for My Tasks audit).
  List<DeletedTaskRecord> deletedTasksForAssignee(String assigneeId) {
    return _deletedTasks
        .where((r) => r.assigneeIds.contains(assigneeId))
        .toList();
  }

  /// Overall progress % for an initiative (from sub-tasks: completed / total).
  int initiativeProgressPercent(String initiativeId) {
    final st = subTasksForInitiative(initiativeId);
    if (st.isEmpty) return 0;
    final completed = st.where((s) => s.isCompleted).length;
    return ((completed / st.length) * 100).round().clamp(0, 100);
  }

  Task? taskById(String id) {
    try {
      final t = _tasks.firstWhere((x) => x.id == id);
      return _taskWithCommentsAndMilestones(t);
    } catch (_) {
      return null;
    }
  }

  List<Assignee> getDirectorsForTeam(String teamId) {
    try {
      final team = teams.firstWhere((t) => t.id == teamId);
      return team.directorIds
          .map((id) => assigneeById(id))
          .whereType<Assignee>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<Assignee> getOfficersForTeam(String teamId) {
    try {
      final team = teams.firstWhere((t) => t.id == teamId);
      final list = team.officerIds
          .map((id) => assigneeById(id))
          .whereType<Assignee>()
          .toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    } catch (_) {
      return [];
    }
  }

  List<Task> tasksForAssignee(String assigneeId) {
    return tasks.where((t) => t.assigneeIds.contains(assigneeId)).toList();
  }

  /// Low-level tasks for a team (task.teamId == teamId). Pass null for all.
  List<Task> tasksForTeam(String? teamId) {
    final all = tasks;
    if (teamId == null || teamId.isEmpty) return all;
    return all.where((t) => t.teamId == teamId).toList();
  }

  List<Initiative> initiativesForTeam(String? teamId) {
    if (teamId == null || teamId.isEmpty) return initiatives;
    return initiatives.where((i) => i.teamId == teamId).toList();
  }

  /// Reminders: Urgent = daily to Directors; Standard = 2 days before due to Directors.
  List<PendingReminder> getPendingReminders(String? teamId) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final list = <PendingReminder>[];
    for (final i in _initiatives) {
      if (teamId != null && i.teamId != teamId) continue;
      if (initiativeProgressPercent(i.id) >= 100) continue;
      final names =
          i.directorIds.map((id) => assigneeById(id)?.name ?? id).toList();
      if (i.priority == priorityUrgent) {
        list.add(PendingReminder(
          itemName: i.name,
          recipientNames: names,
          reminderType: 'Urgent (daily)',
          isInitiative: true,
        ));
      } else if (i.priority == priorityStandard && i.endDate != null) {
        final due = DateTime(
            i.endDate!.year, i.endDate!.month, i.endDate!.day);
        if (due.difference(today).inDays == 2) {
          list.add(PendingReminder(
            itemName: i.name,
            recipientNames: names,
            reminderType: 'Standard (2 days before due)',
            isInitiative: true,
          ));
        }
      }
    }
    for (final t in _tasks) {
      if (t.teamId == null) continue;
      if (teamId != null && t.teamId != teamId) continue;
      if (t.status == TaskStatus.done) continue;
      try {
        final team = teams.firstWhere((x) => x.id == t.teamId);
        final names = team.directorIds
            .map((id) => assigneeById(id)?.name ?? id)
            .toList();
      if (t.priority == priorityUrgent) {
        list.add(PendingReminder(
          itemName: t.name,
          recipientNames: names,
          reminderType: 'Urgent (daily)',
          isInitiative: false,
        ));
      } else if (t.priority == priorityStandard && t.endDate != null) {
        final due = DateTime(
            t.endDate!.year, t.endDate!.month, t.endDate!.day);
        if (due.difference(today).inDays == 2) {
          list.add(PendingReminder(
            itemName: t.name,
            recipientNames: names,
            reminderType: 'Standard (2 days before due)',
            isInitiative: false,
          ));
        }
      }
    } catch (_) {}
    }
    return list;
  }

  void addInitiative({
    required String teamId,
    required List<String> directorIds,
    required String name,
    required String description,
    required int priority,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final id = 'init_${_initiativeIdCounter++}';
    _initiatives.add(Initiative(
      id: id,
      teamId: teamId,
      directorIds: directorIds,
      name: name,
      description: description,
      priority: priority.clamp(1, 2),
      startDate: startDate,
      endDate: endDate,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void updateInitiative(String id, {String? teamId, List<String>? directorIds, String? name, String? description, int? priority, DateTime? startDate, DateTime? endDate}) {
    final i = _initiatives.indexWhere((x) => x.id == id);
    if (i < 0) return;
    _initiatives[i] = _initiatives[i].copyWith(
      teamId: teamId,
      directorIds: directorIds,
      name: name,
      description: description,
      priority: priority,
      startDate: startDate,
      endDate: endDate,
    );
    notifyListeners();
  }

  void addTask({
    required String name,
    required String description,
    required List<String> assigneeIds,
    required int priority,
    String? teamId,
    TaskStatus status = TaskStatus.todo,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final id = 'task_${_taskIdCounter++}';
    final task = Task(
      id: id,
      teamId: teamId,
      name: name,
      description: description,
      assigneeIds: assigneeIds,
      priority: priority.clamp(1, 2),
      status: status,
      startDate: startDate,
      endDate: endDate,
      createdAt: DateTime.now(),
    );
    _tasks.add(task);
    notifyListeners();
  }

  void addComment({
    required String taskId,
    required String authorId,
    required String authorName,
    required String body,
  }) {
    final id = 'comment_${_commentIdCounter++}';
    _comments.add(TaskComment(
      id: id,
      taskId: taskId,
      authorId: authorId,
      authorName: authorName,
      body: body,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
  }

  void addMilestone({
    required String taskId,
    required String label,
    required int progressPercent,
  }) {
    final id = 'milestone_${_milestoneIdCounter++}';
    _milestones.add(Milestone(
      id: id,
      taskId: taskId,
      label: label,
      progressPercent: progressPercent.clamp(0, 100),
    ));
    notifyListeners();
  }

  void updateTaskProgress(String taskId, int progressPercent) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    _tasks[i] = _tasks[i].copyWith(
      progressPercent: progressPercent.clamp(0, 100),
      status: progressPercent >= 100 ? TaskStatus.done : TaskStatus.inProgress,
    );
    notifyListeners();
  }

  void updateTaskStatus(String taskId, TaskStatus status) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    _tasks[i] = _tasks[i].copyWith(
      status: status,
      progressPercent: status == TaskStatus.done ? 100 : _tasks[i].progressPercent,
    );
    notifyListeners();
  }

  void updateMilestoneProgress(String milestoneId, int progressPercent) {
    final i = _milestones.indexWhere((m) => m.id == milestoneId);
    if (i < 0) return;
    _milestones[i] = _milestones[i].copyWith(
      progressPercent: progressPercent.clamp(0, 100),
      isCompleted: progressPercent >= 100,
      completedAt: progressPercent >= 100 ? DateTime.now() : null,
    );
    notifyListeners();
  }

  void addSubTask({
    required String initiativeId,
    required String label,
  }) {
    final id = 'subtask_${_subTaskIdCounter++}';
    _subTasks.add(SubTask(
      id: id,
      initiativeId: initiativeId,
      label: label,
    ));
    notifyListeners();
  }

  void updateSubTaskCompleted(String subTaskId, bool isCompleted) {
    final i = _subTasks.indexWhere((s) => s.id == subTaskId);
    if (i < 0) return;
    _subTasks[i] = _subTasks[i].copyWith(isCompleted: isCompleted);
    notifyListeners();
  }

  void deleteSubTask(String subTaskId, String deletedByName) {
    final i = _subTasks.indexWhere((s) => s.id == subTaskId);
    if (i < 0) return;
    final st = _subTasks.removeAt(i);
    _deletedSubTasks.add(DeletedSubTaskRecord(
      subTask: st,
      deletedAt: DateTime.now(),
      deletedByName: deletedByName,
    ));
    notifyListeners();
  }

  void deleteTask(String taskId, String deletedByName) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final t = _tasks.removeAt(i);
    _deletedTasks.add(DeletedTaskRecord(
      taskId: t.id,
      taskName: t.name,
      teamId: t.teamId,
      assigneeIds: t.assigneeIds,
      deletedAt: DateTime.now(),
      deletedByName: deletedByName,
    ));
    notifyListeners();
  }

  /// Assignee stats for performance view.
  Map<String, AssigneeStats> assigneeStats() {
    final map = <String, AssigneeStats>{};
    for (final a in _assignees) {
      final myTasks = tasksForAssignee(a.id);
      final completed = myTasks.where((t) => t.status == TaskStatus.done).length;
      final total = myTasks.length;
      final progress = total == 0
          ? 0.0
          : myTasks.fold<double>(
                  0, (sum, t) => sum + t.progressPercent) /
              total;
      final delayDays =
          myTasks.fold<int>(0, (sum, t) => sum + t.delayDays);
      map[a.id] = AssigneeStats(
        assigneeId: a.id,
        assigneeName: a.name,
        assignedCount: total,
        completedCount: completed,
        averageProgressPercent: progress,
        totalDelayDays: delayDays,
      );
    }
    return map;
  }
}

class AssigneeStats {
  final String assigneeId;
  final String assigneeName;
  final int assignedCount;
  final int completedCount;
  final double averageProgressPercent;
  final int totalDelayDays;

  AssigneeStats({
    required this.assigneeId,
    required this.assigneeName,
    required this.assignedCount,
    required this.completedCount,
    required this.averageProgressPercent,
    required this.totalDelayDays,
  });
}
