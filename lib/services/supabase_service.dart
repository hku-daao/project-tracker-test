import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/comment.dart';
import '../models/initiative.dart';
import '../models/milestone.dart';
import '../models/sub_task.dart';
import '../models/deleted_record.dart';
import '../models/staff_for_assignment.dart';
import '../models/task.dart';

class InitiativesLoadResult {
  final List<Initiative> initiatives;
  final List<SubTask> subTasks;
  final List<TaskComment> comments;

  const InitiativesLoadResult({
    required this.initiatives,
    required this.subTasks,
    required this.comments,
  });
}

class TasksLoadResult {
  final List<Task> tasks;
  final List<Milestone> milestones;
  final List<TaskComment> comments;

  const TasksLoadResult({
    required this.tasks,
    required this.milestones,
    required this.comments,
  });
}

class SupabaseService {
  static bool get _enabled => SupabaseConfig.isConfigured;

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static DateTime _parseDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  static TaskStatus _taskStatusFromDb(String? s) {
    switch (s) {
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'done':
        return TaskStatus.done;
      default:
        return TaskStatus.todo;
    }
  }

  static String _taskStatusToDb(TaskStatus s) {
    switch (s) {
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.done:
        return 'done';
      case TaskStatus.todo:
        return 'todo';
    }
  }

  static bool _looksLikeUuid(String s) {
    final t = s.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(t);
  }

  /// Maps app `teamId` (usually `team.team_id` text) to `team.id` (uuid) for FK columns.
  static Future<String?> _resolveTeamIdUuid(String teamKey) async {
    final k = teamKey.trim();
    if (k.isEmpty) return null;
    final supabase = Supabase.instance.client;
    final byBiz = await supabase
        .from('team')
        .select('id')
        .eq('team_id', k)
        .limit(1)
        .maybeSingle();
    if (byBiz != null) return byBiz['id'] as String?;
    if (_looksLikeUuid(k)) {
      final byPk = await supabase.from('team').select('id').eq('id', k).maybeSingle();
      if (byPk != null) return byPk['id'] as String?;
    }
    return null;
  }

  static Future<({Map<String, String> teamUuidToAppId, Map<String, String> staffUuidToAppId, Map<String, String> staffUuidToName})?> _loadMaps() async {
    if (!_enabled) return null;
    final supabase = Supabase.instance.client;
    final teamsRes = await supabase.from('team').select('id, team_id');
    final teamUuidToAppId = <String, String>{};
    for (final row in (teamsRes as List)) {
      final id = row['id'] as String?;
      final teamId = row['team_id'] as String?;
      if (id != null && teamId != null && teamId.isNotEmpty) {
        teamUuidToAppId[id] = teamId;
      }
    }
    final staffRes = await supabase.from('staff').select('id, app_id, name');
    final staffUuidToAppId = <String, String>{};
    final staffUuidToName = <String, String>{};
    for (final row in (staffRes as List)) {
      final id = row['id'] as String;
      staffUuidToName[id] = row['name'] as String? ?? id;
      final appId = row['app_id'] as String?;
      if (appId != null && appId.isNotEmpty) {
        staffUuidToAppId[id] = appId;
      }
    }
    return (teamUuidToAppId: teamUuidToAppId, staffUuidToAppId: staffUuidToAppId, staffUuidToName: staffUuidToName);
  }

  static Future<String?> _staffUuidForAppId(String appId) async {
    final supabase = Supabase.instance.client;
    final r = await supabase.from('staff').select('id').eq('app_id', appId).maybeSingle();
    return r?['id'] as String?;
  }

  /// `team` rows (`team_id`, `team_name`) and `staff` rows joined by `staff.team_id` = `team.team_id`.
  static Future<StaffAssigneePickerData?> fetchStaffAssigneePickerData() async {
    if (!_enabled) return null;
    try {
      final supabase = Supabase.instance.client;
      final teamRes =
          await supabase.from('team').select('team_id, team_name').order('team_name');
      final teams = <TeamOptionRow>[];
      for (final r in (teamRes as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final tid = m['team_id']?.toString() ?? '';
        if (tid.isEmpty) continue;
        final tn = m['team_name'] as String? ?? tid;
        teams.add(TeamOptionRow(teamId: tid, teamName: tn));
      }
      final staffRes =
          await supabase.from('staff').select('id, app_id, name, team_id').order('name');
      final staff = <StaffForAssignment>[];
      for (final r in (staffRes as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final appId = m['app_id'] as String?;
        final id = m['id']?.toString() ?? '';
        final assigneeId = (appId != null && appId.isNotEmpty) ? appId : id;
        if (assigneeId.isEmpty) continue;
        final name = m['name'] as String? ?? assigneeId;
        final rawTeam = m['team_id']?.toString();
        final teamId =
            rawTeam != null && rawTeam.isNotEmpty ? rawTeam : null;
        staff.add(StaffForAssignment(
          assigneeId: assigneeId,
          name: name,
          teamId: teamId,
        ));
      }
      return StaffAssigneePickerData(teams: teams, staff: staff);
    } catch (e) {
      return null;
    }
  }

  static Future<InitiativesLoadResult?> fetchInitiativesFromSupabase() async {
    if (!_enabled) return null;
    try {
      final maps = await _loadMaps();
      if (maps == null) return null;
      final teamUuidToAppId = maps.teamUuidToAppId;
      final staffUuidToAppId = maps.staffUuidToAppId;
      final staffUuidToName = maps.staffUuidToName;
      final supabase = Supabase.instance.client;

      final initRes =
          await supabase.from('initiatives').select().order('created_at', ascending: false);
      final initRows = initRes as List;
      if (initRows.isEmpty) {
        return const InitiativesLoadResult(
          initiatives: [],
          subTasks: [],
          comments: [],
        );
      }

      final initiativeIds = initRows.map((r) => r['id'] as String).toList();

      final dirRes = await supabase
          .from('initiative_directors')
          .select('initiative_id, staff_id')
          .inFilter('initiative_id', initiativeIds);
      final dirsByInit = <String, List<String>>{};
      for (final row in (dirRes as List)) {
        final iid = row['initiative_id'] as String;
        final sid = row['staff_id'] as String;
        final appId = staffUuidToAppId[sid] ?? sid;
        dirsByInit.putIfAbsent(iid, () => []).add(appId);
      }

      final initiatives = <Initiative>[];
      for (final row in initRows) {
        final id = row['id'] as String;
        final teamUuid = row['team_id'] as String;
        final teamAppId = teamUuidToAppId[teamUuid] ?? 'unknown_team';
        initiatives.add(Initiative(
          id: id,
          teamId: teamAppId,
          directorIds: List<String>.from(dirsByInit[id] ?? []),
          name: row['name'] as String? ?? '',
          description: row['description'] as String? ?? '',
          priority: (row['priority'] as num?)?.toInt() ?? 1,
          startDate: _parseDate(row['start_date']),
          endDate: _parseDate(row['end_date']),
          createdAt: _parseDateTime(row['created_at']),
        ));
      }

      final subRes = await supabase
          .from('sub_tasks')
          .select()
          .inFilter('initiative_id', initiativeIds);
      final subTasks = <SubTask>[];
      for (final row in (subRes as List)) {
        subTasks.add(SubTask(
          id: row['id'] as String,
          initiativeId: row['initiative_id'] as String,
          label: row['label'] as String? ?? '',
          isCompleted: row['is_completed'] as bool? ?? false,
        ));
      }

      final commRes = await supabase
          .from('comments')
          .select()
          .eq('entity_type', 'initiative')
          .inFilter('entity_id', initiativeIds)
          .order('created_at');
      final comments = <TaskComment>[];
      for (final row in (commRes as List)) {
        final authorId = row['author_id'] as String;
        comments.add(TaskComment(
          id: row['id'] as String,
          taskId: row['entity_id'] as String,
          authorId: staffUuidToAppId[authorId] ?? authorId,
          authorName: staffUuidToName[authorId] ?? authorId,
          body: row['body'] as String? ?? '',
          createdAt: _parseDateTime(row['created_at']),
        ));
      }

      return InitiativesLoadResult(
        initiatives: initiatives,
        subTasks: subTasks,
        comments: comments,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<TasksLoadResult?> fetchTasksFromSupabase() async {
    if (!_enabled) return null;
    try {
      final maps = await _loadMaps();
      if (maps == null) return null;
      final teamUuidToAppId = maps.teamUuidToAppId;
      final staffUuidToAppId = maps.staffUuidToAppId;
      final staffUuidToName = maps.staffUuidToName;
      final supabase = Supabase.instance.client;

      final taskRes =
          await supabase.from('tasks').select().order('created_at', ascending: false);
      final taskRows = taskRes as List;
      if (taskRows.isEmpty) {
        return const TasksLoadResult(tasks: [], milestones: [], comments: []);
      }

      final taskIds = taskRows.map((r) => r['id'] as String).toList();

      final assignRes = await supabase
          .from('task_assignees')
          .select('task_id, staff_id')
          .inFilter('task_id', taskIds);
      final assignByTask = <String, List<String>>{};
      for (final row in (assignRes as List)) {
        final tid = row['task_id'] as String;
        final sid = row['staff_id'] as String;
        final appId = staffUuidToAppId[sid] ?? sid;
        assignByTask.putIfAbsent(tid, () => []).add(appId);
      }

      final tasks = <Task>[];
      for (final row in taskRows) {
        final id = row['id'] as String;
        final teamUuid = row['team_id'] as String?;
        final teamAppId =
            teamUuid == null ? null : teamUuidToAppId[teamUuid];
        tasks.add(Task(
          id: id,
          teamId: teamAppId,
          name: row['name'] as String? ?? '',
          description: row['description'] as String? ?? '',
          assigneeIds: List<String>.from(assignByTask[id] ?? []),
          priority: (row['priority'] as num?)?.toInt() ?? 1,
          startDate: _parseDate(row['start_date']),
          endDate: _parseDate(row['end_date']),
          createdAt: _parseDateTime(row['created_at']),
          status: _taskStatusFromDb(row['status'] as String?),
          progressPercent: (row['progress_percent'] as num?)?.toInt() ?? 0,
        ));
      }

      List<Milestone> milestones = [];
      try {
        final mileRes = await supabase
            .from('task_milestones')
            .select()
            .inFilter('task_id', taskIds);
        for (final row in (mileRes as List)) {
          milestones.add(Milestone(
            id: row['id'] as String,
            taskId: row['task_id'] as String,
            label: row['label'] as String? ?? '',
            progressPercent: (row['progress_percent'] as num?)?.toInt() ?? 0,
            isCompleted: row['is_completed'] as bool? ?? false,
            completedAt: _parseDate(row['completed_at']),
          ));
        }
      } catch (_) {
        // table may not exist yet
      }

      final commRes = await supabase
          .from('comments')
          .select()
          .eq('entity_type', 'task')
          .inFilter('entity_id', taskIds)
          .order('created_at');
      final comments = <TaskComment>[];
      for (final row in (commRes as List)) {
        final authorId = row['author_id'] as String;
        comments.add(TaskComment(
          id: row['id'] as String,
          taskId: row['entity_id'] as String,
          authorId: staffUuidToAppId[authorId] ?? authorId,
          authorName: staffUuidToName[authorId] ?? authorId,
          body: row['body'] as String? ?? '',
          createdAt: _parseDateTime(row['created_at']),
        ));
      }

      return TasksLoadResult(
        tasks: tasks,
        milestones: milestones,
        comments: comments,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<String?> insertInitiative({
    required String initiativeId,
    required String teamId,
    required List<String> directorIds,
    required String name,
    required String description,
    required int priority,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!_enabled) return null;
    try {
      final supabase = Supabase.instance.client;
      final teamUuid = await _resolveTeamIdUuid(teamId);
      if (teamUuid == null) {
        return 'Team not found for "$teamId". Expected a row in public.team where team_id matches or id is a UUID.';
      }
      final directorUuids = <String>[];
      for (final appId in directorIds) {
        final staffRes = await supabase
            .from('staff')
            .select('id')
            .eq('app_id', appId)
            .maybeSingle();
        final uuid = staffRes?['id'] as String?;
        if (uuid != null) directorUuids.add(uuid);
      }
      if (directorUuids.isEmpty && directorIds.isNotEmpty) {
        return 'No directors found for app_ids ${directorIds.join(", ")}. Run seed_teams_and_staff.sql in Supabase.';
      }
      await supabase.from('initiatives').insert({
        'id': initiativeId,
        'team_id': teamUuid,
        'name': name,
        'description': description,
        'priority': priority,
        'start_date': startDate?.toIso8601String().split('T').first,
        'end_date': endDate?.toIso8601String().split('T').first,
      });
      for (final staffUuid in directorUuids) {
        await supabase.from('initiative_directors').insert({
          'initiative_id': initiativeId,
          'staff_id': staffUuid,
        });
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Maps assignee keys (`staff.app_id` or `staff.id` uuid) to `staff.id` for `task.assignee_xx`.
  static Future<List<String?>> assigneeSlotsForTask(List<String> staffKeys) async {
    if (!_enabled) return List<String?>.filled(10, null);
    final out = <String?>[];
    for (final key in staffKeys.take(10)) {
      final id = await _staffRowIdForAssigneeKey(key);
      out.add(id);
    }
    while (out.length < 10) {
      out.add(null);
    }
    return out.take(10).toList();
  }

  static Future<String?> _staffRowIdForAssigneeKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) return null;
    final supabase = Supabase.instance.client;
    final byApp =
        await supabase.from('staff').select('id').eq('app_id', k).maybeSingle();
    if (byApp != null) return byApp['id'] as String?;
    if (_looksLikeUuid(k)) {
      final byId = await supabase.from('staff').select('id').eq('id', k).maybeSingle();
      if (byId != null) return byId['id'] as String?;
    }
    return null;
  }

  /// Loads all staff for multi-select; values stored in `task.assignee_xx` are [`StaffListRow.id`].
  static Future<List<StaffListRow>> fetchStaffListForTaskPicker() async {
    if (!_enabled) return [];
    try {
      final res = await Supabase.instance.client
          .from('staff')
          .select('id, name')
          .order('name');
      final list = <StaffListRow>[];
      for (final r in (res as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        list.add(StaffListRow(
          id: id,
          name: (m['name'] as String?)?.trim().isNotEmpty == true
              ? m['name'] as String
              : id,
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Inserts one row into the singular [`task`] table (not legacy [`tasks`]).
  /// [assignees] — up to 10 values, each the string form of **`staff.id`** (uuid).
  static Future<String?> insertTaskTableRow({
    required String taskName,
    List<String?> assignees = const [],
    String? priority,
    DateTime? startDate,
    DateTime? dueDate,
    String? description,
    int active = 1,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final name = taskName.trim();
    if (name.isEmpty) return 'task_name is required';
    try {
      var padded = List<String?>.from(assignees);
      while (padded.length < 10) {
        padded.add(null);
      }
      if (padded.length > 10) {
        padded = padded.sublist(0, 10);
      }
      final map = <String, dynamic>{
        'task_name': name,
        'priority': priority,
        'description': description,
        'active': active.clamp(0, 1),
      };
      if (startDate != null) {
        map['start_date'] = startDate.toUtc().toIso8601String();
      }
      if (dueDate != null) {
        map['due_date'] = dueDate.toUtc().toIso8601String();
      }
      for (var i = 0; i < 10; i++) {
        final raw = padded[i]?.trim();
        if (raw != null && raw.isNotEmpty) {
          map['assignee_${(i + 1).toString().padLeft(2, '0')}'] = raw;
        }
      }
      await Supabase.instance.client.from('task').insert(map);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> insertTask({
    required String taskId,
    required String? teamId,
    required List<String> assigneeIds,
    required String name,
    required String description,
    required int priority,
    required TaskStatus status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!_enabled) return null;
    try {
      final supabase = Supabase.instance.client;
      String? teamUuid;
      if (teamId != null && teamId.isNotEmpty) {
        teamUuid = await _resolveTeamIdUuid(teamId);
        if (teamUuid == null) {
          return 'Team not found for "$teamId". Check public.team (team_id or id).';
        }
      }
      final assigneeUuids = <String>[];
      for (final appId in assigneeIds) {
        final u = await _staffUuidForAppId(appId);
        if (u != null) assigneeUuids.add(u);
      }
      if (assigneeUuids.isEmpty && assigneeIds.isNotEmpty) {
        return 'No staff found for assignees. Run seed_teams_and_staff.sql.';
      }
      await supabase.from('tasks').insert({
        'id': taskId,
        'team_id': teamUuid,
        'name': name,
        'description': description,
        'priority': priority,
        'status': _taskStatusToDb(status),
        'start_date': startDate?.toIso8601String().split('T').first,
        'end_date': endDate?.toIso8601String().split('T').first,
      });
      for (final sid in assigneeUuids) {
        await supabase.from('task_assignees').insert({
          'task_id': taskId,
          'staff_id': sid,
        });
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<void> insertComment({
    required String commentId,
    required String entityType,
    required String entityId,
    required String authorAppId,
    required String body,
  }) async {
    if (!_enabled) return;
    try {
      final authorUuid = await _staffUuidForAppId(authorAppId);
      if (authorUuid == null) return;
      await Supabase.instance.client.from('comments').insert({
        'id': commentId,
        'entity_type': entityType,
        'entity_id': entityId,
        'author_id': authorUuid,
        'body': body,
      });
    } catch (_) {}
  }

  /// Legacy no-op: `sub_tasks` / initiatives schema not used in current rebuild.
  static Future<String?> insertInitiativeSubTask({
    required String subTaskId,
    required String initiativeId,
    required String label,
  }) async {
    return null;
  }

  static Future<void> updateInitiativeSubTask({
    required String subTaskId,
    required bool isCompleted,
  }) async {
    if (!_enabled) return;
    try {
      await Supabase.instance.client.from('sub_tasks').update({
        'is_completed': isCompleted,
      }).eq('id', subTaskId);
    } catch (_) {}
  }

  static Future<void> insertTaskMilestone({
    required String milestoneId,
    required String taskId,
    required String label,
    required int progressPercent,
  }) async {
    if (!_enabled) return;
    try {
      await Supabase.instance.client.from('task_milestones').insert({
        'id': milestoneId,
        'task_id': taskId,
        'label': label,
        'progress_percent': progressPercent,
        'is_completed': progressPercent >= 100,
      });
    } catch (_) {}
  }

  static Future<void> updateTaskMilestone({
    required String milestoneId,
    required int progressPercent,
  }) async {
    if (!_enabled) return;
    try {
      await Supabase.instance.client.from('task_milestones').update({
        'progress_percent': progressPercent,
        'is_completed': progressPercent >= 100,
        'completed_at': progressPercent >= 100 ? DateTime.now().toIso8601String() : null,
      }).eq('id', milestoneId);
    } catch (_) {}
  }

  static Future<void> updateTask({
    required String taskId,
    TaskStatus? status,
    int? progressPercent,
  }) async {
    if (!_enabled) return;
    try {
      final map = <String, dynamic>{};
      if (status != null) map['status'] = _taskStatusToDb(status);
      if (progressPercent != null) map['progress_percent'] = progressPercent;
      if (map.isEmpty) return;
      await Supabase.instance.client.from('tasks').update(map).eq('id', taskId);
    } catch (_) {}
  }

  /// Load deleted-task audit rows for the website (All Tasks / My Tasks).
  static Future<List<DeletedTaskRecord>> fetchDeletedTasksFromSupabase() async {
    if (!_enabled) return [];
    try {
      final maps = await _loadMaps();
      if (maps == null) return [];
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('deleted_tasks')
          .select()
          .order('deleted_at', ascending: false);
      final list = <DeletedTaskRecord>[];
      for (final row in (res as List)) {
        final teamUuid = row['team_id'] as String?;
        final teamAppId = teamUuid == null
            ? null
            : maps.teamUuidToAppId[teamUuid];
        final rawAssignees = row['assignee_ids'];
        final assigneeAppIds = <String>[];
        if (rawAssignees is List) {
          for (final uid in rawAssignees) {
            final s = uid.toString();
            assigneeAppIds.add(maps.staffUuidToAppId[s] ?? s);
          }
        }
        list.add(DeletedTaskRecord(
          taskId: row['task_id'] as String,
          taskName: row['task_name'] as String? ?? '',
          teamId: teamAppId,
          assigneeIds: assigneeAppIds,
          deletedAt: _parseDateTime(row['deleted_at']),
          deletedByName: row['deleted_by'] as String? ?? '',
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Insert audit row, remove task comments, then delete task from Supabase.
  static Future<void> recordDeletedTaskAudit({
    required String taskId,
    required String taskName,
    required String? teamId,
    required List<String> assigneeIds,
    required String deletedByName,
  }) async {
    if (!_enabled) return;
    try {
      final supabase = Supabase.instance.client;
      String? teamUuid;
      if (teamId != null && teamId.isNotEmpty) {
        teamUuid = await _resolveTeamIdUuid(teamId);
      }
      final uuids = <String>[];
      for (final aid in assigneeIds) {
        final u = await _staffUuidForAppId(aid);
        if (u != null) uuids.add(u);
      }
      await supabase.from('deleted_tasks').insert({
        'task_id': taskId,
        'task_name': taskName,
        'team_id': teamUuid,
        'assignee_ids': uuids,
        'deleted_by': deletedByName,
      });
      await supabase
          .from('comments')
          .delete()
          .eq('entity_type', 'task')
          .eq('entity_id', taskId);
      await supabase.from('tasks').delete().eq('id', taskId);
    } catch (_) {}
  }
}
