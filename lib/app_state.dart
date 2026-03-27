import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'models/assignee.dart';
import 'models/staff_team_lookup.dart';
import 'models/comment.dart';
import 'models/deleted_record.dart';
import 'models/initiative.dart';
import 'models/milestone.dart';
import 'models/sub_task.dart';
import 'models/task.dart';
import 'models/reminder.dart';
import 'models/team.dart';
import 'priority.dart';
import 'services/backend_api.dart';
import 'services/supabase_service.dart';
import 'utils/hk_time.dart';

/// Global app state: initiatives (high-level), tasks (low-level), assignees, teams, comments, milestones.
class AppState extends ChangeNotifier {
  /// Staff members loaded from database (via /api/staff).
  final List<Assignee> _assignees = [];

  /// Teams with hierarchy loaded from database (via /api/teams).
  List<Team> _teams = [];

  /// [staff.app_id] → [staff.team_id] for team filter (assignees may belong to a team when `task.team_id` is null).
  Map<String, String> _staffTeamIdByAssigneeAppId = {};

  List<Team> get teams => List.unmodifiable(_teams);

  final List<Initiative> _initiatives = [];
  final List<Task> _tasks = [];
  final List<TaskComment> _comments = [];
  final List<Milestone> _milestones = [];
  final List<SubTask> _subTasks = [];
  final List<DeletedSubTaskRecord> _deletedSubTasks = [];
  final List<DeletedTaskRecord> _deletedTasks = [];
  final Set<String> _manuallyCompletedInitiatives = {};

  /// Current user's `staff.app_id` (from Supabase lookup or backend).
  String? _userStaffAppId;
  List<AssignableStaffEntry> _assignableStaffFromServer = [];

  /// `staff.app_id` values from `subordinate.subordinate_id` where `supervisor_id` = current user.
  List<String> _subordinateAppIds = [];

  /// Revamp step 1: staff + team lookup by login email (Supabase).
  StaffTeamLookupResult? _revampStaffLookup;

  StaffTeamLookupResult? get revampStaffLookup => _revampStaffLookup;

  void setRevampStaffLookup(StaffTeamLookupResult? v) {
    _revampStaffLookup = v;
    notifyListeners();
  }

  String? get userStaffAppId => _userStaffAppId;
  List<AssignableStaffEntry> get assignableStaffFromServer =>
      List.unmodifiable(_assignableStaffFromServer);

  List<String> get subordinateAppIds => List.unmodifiable(_subordinateAppIds);

  /// Logged-in user plus subordinates from `subordinate` (same `staff.app_id` keys).
  Set<String> get assigneeVisibilityAppIds {
    final mine = _userStaffAppId?.trim();
    if (mine == null || mine.isEmpty) return {};
    return {mine, ..._subordinateAppIds};
  }

  void setSubordinateAppIds(List<String> ids) {
    _subordinateAppIds = List<String>.from(ids);
    notifyListeners();
  }

  void setUserStaffContext({
    String? staffAppId,
    List<AssignableStaffEntry>? assignableStaff,
  }) {
    _userStaffAppId = staffAppId;
    _assignableStaffFromServer = assignableStaff ?? [];
    notifyListeners();
  }

  /// Replace teams used for filters (ids must match [Task.teamId] from Supabase singular `task`).
  void setTeamsForFilter(List<Team> teams) {
    _teams = List<Team>.from(teams);
    notifyListeners();
  }

  /// Merge/replace assignees from Supabase `staff` (for filter labels when backend staff is not loaded).
  void mergeAssigneesFromSupabase(List<Assignee> incoming) {
    final map = <String, Assignee>{for (final a in _assignees) a.id: a};
    for (final a in incoming) {
      map[a.id] = a;
    }
    _assignees
      ..clear()
      ..addAll(map.values);
    notifyListeners();
  }

  void setStaffAppIdToTeamIdMap(Map<String, String> map) {
    _staffTeamIdByAssigneeAppId = Map<String, String>.from(map);
    notifyListeners();
  }

  bool _taskMatchesTeamFilter(Task t, String teamId) {
    final rowTeam = t.teamId?.trim();
    if (rowTeam != null && rowTeam.isNotEmpty && rowTeam == teamId) {
      return true;
    }
    for (final assigneeKey in t.assigneeIds) {
      if (_staffTeamIdByAssigneeAppId[assigneeKey] == teamId) return true;
    }
    return false;
  }

  bool _deletedTaskMatchesTeamFilter(DeletedTaskRecord r, String teamId) {
    final rowTeam = r.teamId?.trim();
    if (rowTeam != null && rowTeam.isNotEmpty && rowTeam == teamId) {
      return true;
    }
    for (final id in r.assigneeIds) {
      if (_staffTeamIdByAssigneeAppId[id] == teamId) return true;
    }
    return false;
  }

  /// Load teams and staff from backend. Call this after user authentication.
  Future<void> loadTeamsAndStaff(String idToken) async {
    try {
      final api = BackendApi();
      final [teamsData, staffData] = await Future.wait([
        api.getTeams(idToken),
        api.getStaff(idToken),
      ]);

      debugPrint('AppState.loadTeamsAndStaff: teams=${teamsData.length}, staff=${staffData.length}');

      // Update teams
      _teams = teamsData.map((t) {
        final directorIds = (t['directorIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        final officerIds = (t['officerIds'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        return Team(
          id: t['id']?.toString() ?? '',
          name: t['name']?.toString() ?? '',
          directorIds: directorIds,
          officerIds: officerIds,
        );
      }).toList();

      // Update assignees
      _assignees.clear();
      _assignees.addAll(staffData.map((s) {
        return Assignee(
          id: s['id']?.toString() ?? '',
          name: s['name']?.toString() ?? '',
        );
      }));

      debugPrint('AppState.loadTeamsAndStaff: Loaded ${_teams.length} teams, ${_assignees.length} assignees');
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load teams and staff: $e');
    }
  }

  List<Assignee> get assignees => List.unmodifiable(_assignees);

  List<Initiative> get initiatives => List.unmodifiable(_initiatives);

  /// Replace initiatives (and related sub-tasks/comments) from Supabase after fetch.
  void applyInitiativesFromSupabase(InitiativesLoadResult result) {
    final ids = result.initiatives.map((e) => e.id).toSet();
    _comments.removeWhere((c) => ids.contains(c.taskId));
    _comments.addAll(result.comments);
    _subTasks.removeWhere((s) => ids.contains(s.initiativeId));
    _subTasks.addAll(result.subTasks);
    _initiatives.clear();
    _initiatives.addAll(result.initiatives);
    notifyListeners();
  }

  /// Replace tasks, task milestones, and task comments from Supabase after fetch.
  void applyTasksFromSupabase(TasksLoadResult result) {
    final ids = result.tasks.map((t) => t.id).toSet();
    _comments.removeWhere((c) => ids.contains(c.taskId));
    _comments.addAll(result.comments);
    _milestones.removeWhere((m) => ids.contains(m.taskId));
    _milestones.addAll(result.milestones);
    _tasks.clear();
    _tasks.addAll(result.tasks);
    notifyListeners();
  }

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
    return _deletedTasks
        .where((r) => _deletedTaskMatchesTeamFilter(r, teamId))
        .toList();
  }

  /// Deleted tasks that were assigned to this assignee (for My Tasks audit).
  List<DeletedTaskRecord> deletedTasksForAssignee(String assigneeId) {
    return _deletedTasks
        .where((r) => r.assigneeIds.contains(assigneeId))
        .toList();
  }

  /// Overall progress % for an initiative (from sub-tasks, or 100 if manually completed).
  int initiativeProgressPercent(String initiativeId) {
    if (_manuallyCompletedInitiatives.contains(initiativeId)) return 100;
    final st = subTasksForInitiative(initiativeId);
    if (st.isEmpty) return 0;
    final completed = st.where((s) => s.isCompleted).length;
    return ((completed / st.length) * 100).round().clamp(0, 100);
  }

  void markInitiativeComplete(String initiativeId) {
    _manuallyCompletedInitiatives.add(initiativeId);
    notifyListeners();
  }

  void markInitiativeIncomplete(String initiativeId) {
    _manuallyCompletedInitiatives.remove(initiativeId);
    notifyListeners();
  }

  Task? taskById(String id) {
    try {
      final t = _tasks.firstWhere((x) => x.id == id);
      return _taskWithCommentsAndMilestones(t);
    } catch (_) {
      return null;
    }
  }

  /// True if this assignee is a Director (supervisor level) in any team.
  bool isDirector(String assigneeId) {
    return teams.any((t) => t.directorIds.contains(assigneeId));
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

  /// Directors + Officers for given team ids, sorted by name (ascending).
  List<Assignee> getAssigneesForTeams(List<String> teamIds) {
    final seen = <String>{};
    final list = <Assignee>[];
    for (final tid in teamIds) {
      try {
        final team = teams.firstWhere((t) => t.id == tid);
        for (final id in [...team.directorIds, ...team.officerIds]) {
          if (seen.add(id)) {
            final a = assigneeById(id);
            if (a != null) list.add(a);
          }
        }
      } catch (_) {}
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
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

  /// Low-level tasks for a team: `task.team_id` matches **or** any assignee's `staff.team_id` matches
  /// (same id as filter dropdown: Supabase `team.team_id`).
  /// Tasks visible to the current user: assignee slots must be self or a subordinate (see [subordinate] table).
  List<Task> tasksForTeam(String? teamId) {
    var all = tasks;
    final scope = assigneeVisibilityAppIds;
    if (scope.isEmpty) {
      all = [];
    } else {
      all = all
          .where((t) => t.assigneeIds.any((id) => scope.contains(id)))
          .toList();
    }
    if (teamId == null || teamId.isEmpty) return all;
    return all.where((t) => _taskMatchesTeamFilter(t, teamId)).toList();
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
        final names = [...team.directorIds, ...team.officerIds]
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

  /// Returns the new initiative id (UUID). Supabase sync is done by the caller.
  String addInitiative({
    required String teamId,
    required List<String> directorIds,
    required String name,
    required String description,
    required int priority,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final id = const Uuid().v4();
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
    return id;
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

  void replaceTask(Task t) {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i < 0) return;
    _tasks[i] = t;
    notifyListeners();
  }

  void removeTaskFromList(String taskId) {
    _tasks.removeWhere((t) => t.id == taskId);
    _comments.removeWhere((c) => c.taskId == taskId);
    _milestones.removeWhere((m) => m.taskId == taskId);
    notifyListeners();
  }

  String addTask({
    required String name,
    required String description,
    required List<String> assigneeIds,
    required int priority,
    String? teamId,
    TaskStatus status = TaskStatus.todo,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final id = const Uuid().v4();
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
      createdAt: HkTime.localCreatedAtForTask(),
    );
    _tasks.add(task);
    notifyListeners();
    return id;
  }

  void addComment({
    required String taskId,
    required String authorId,
    required String authorName,
    required String body,
  }) {
    final id = const Uuid().v4();
    _comments.add(TaskComment(
      id: id,
      taskId: taskId,
      authorId: authorId,
      authorName: authorName,
      body: body,
      createdAt: DateTime.now(),
    ));
    notifyListeners();
    final entityType =
        _initiatives.any((i) => i.id == taskId) ? 'initiative' : 'task';
    SupabaseService.insertComment(
      commentId: id,
      entityType: entityType,
      entityId: taskId,
      authorAppId: authorId,
      body: body,
    );
  }

  void updateComment(String commentId, String newBody) {
    final i = _comments.indexWhere((c) => c.id == commentId);
    if (i < 0) return;
    _comments[i] = TaskComment(
      id: _comments[i].id,
      taskId: _comments[i].taskId,
      authorId: _comments[i].authorId,
      authorName: _comments[i].authorName,
      body: newBody,
      createdAt: _comments[i].createdAt,
    );
    notifyListeners();
  }

  void deleteComment(String commentId) {
    _comments.removeWhere((c) => c.id == commentId);
    notifyListeners();
  }

  void addMilestone({
    required String taskId,
    required String label,
    required int progressPercent,
  }) {
    final id = const Uuid().v4();
    final p = progressPercent.clamp(0, 100);
    _milestones.add(Milestone(
      id: id,
      taskId: taskId,
      label: label,
      progressPercent: p,
    ));
    notifyListeners();
    SupabaseService.insertTaskMilestone(
      milestoneId: id,
      taskId: taskId,
      label: label,
      progressPercent: p,
    );
  }

  void updateTaskProgress(String taskId, int progressPercent) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final p = progressPercent.clamp(0, 100);
    final st = p >= 100 ? TaskStatus.done : TaskStatus.inProgress;
    _tasks[i] = _tasks[i].copyWith(
      progressPercent: p,
      status: st,
    );
    notifyListeners();
    SupabaseService.updateTask(
      taskId: taskId,
      status: st,
      progressPercent: p,
    );
  }

  void updateTaskStatus(String taskId, TaskStatus status) {
    final i = _tasks.indexWhere((t) => t.id == taskId);
    if (i < 0) return;
    final pp = status == TaskStatus.done ? 100 : _tasks[i].progressPercent;
    _tasks[i] = _tasks[i].copyWith(
      status: status,
      progressPercent: pp,
    );
    notifyListeners();
    SupabaseService.updateTask(
      taskId: taskId,
      status: status,
      progressPercent: status == TaskStatus.done ? 100 : null,
    );
  }

  void updateMilestoneProgress(String milestoneId, int progressPercent) {
    final i = _milestones.indexWhere((m) => m.id == milestoneId);
    if (i < 0) return;
    final p = progressPercent.clamp(0, 100);
    _milestones[i] = _milestones[i].copyWith(
      progressPercent: p,
      isCompleted: p >= 100,
      completedAt: p >= 100 ? DateTime.now() : null,
    );
    notifyListeners();
    SupabaseService.updateTaskMilestone(
      milestoneId: milestoneId,
      progressPercent: p,
    );
  }

  /// Returns Supabase error string if cloud save failed; null if OK or Supabase off.
  Future<String?> addSubTask({
    required String initiativeId,
    required String label,
  }) async {
    final id = const Uuid().v4();
    _subTasks.add(SubTask(
      id: id,
      initiativeId: initiativeId,
      label: label,
    ));
    notifyListeners();
    return SupabaseService.insertInitiativeSubTask(
      subTaskId: id,
      initiativeId: initiativeId,
      label: label,
    );
  }

  void updateSubTaskCompleted(String subTaskId, bool isCompleted) {
    final i = _subTasks.indexWhere((s) => s.id == subTaskId);
    if (i < 0) return;
    _subTasks[i] = _subTasks[i].copyWith(isCompleted: isCompleted);
    notifyListeners();
    SupabaseService.updateInitiativeSubTask(
      subTaskId: subTaskId,
      isCompleted: isCompleted,
    );
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
    _comments.removeWhere((c) => c.taskId == taskId);
    _milestones.removeWhere((m) => m.taskId == taskId);
    _deletedTasks.add(DeletedTaskRecord(
      taskId: t.id,
      taskName: t.name,
      teamId: t.teamId,
      assigneeIds: t.assigneeIds,
      deletedAt: DateTime.now(),
      deletedByName: deletedByName,
    ));
    notifyListeners();
    SupabaseService.recordDeletedTaskAudit(
      taskId: t.id,
      taskName: t.name,
      teamId: t.teamId,
      assigneeIds: t.assigneeIds,
      deletedByName: deletedByName,
    );
  }

  void applyDeletedTasksFromSupabase(List<DeletedTaskRecord> records) {
    _deletedTasks.clear();
    _deletedTasks.addAll(records);
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
