import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/assignee.dart';
import '../models/comment.dart';
import '../models/initiative.dart';
import '../models/milestone.dart';
import '../models/sub_task.dart';
import '../models/deleted_record.dart';
import '../models/singular_comment.dart';
import '../models/singular_subtask.dart';
import '../models/staff_for_assignment.dart';
import '../models/task.dart';
import '../models/team.dart';
import '../utils/hk_time.dart';

/// Row from `public.attachment` (singular task).
class TaskAttachmentRow {
  const TaskAttachmentRow({
    required this.id,
    this.content,
    this.description,
  });
  final String id;
  final String? content;
  final String? description;
}

/// Row from `public.subtask_attachment`.
class SubtaskAttachmentRow {
  const SubtaskAttachmentRow({
    required this.id,
    this.content,
    this.description,
  });
  final String id;
  final String? content;
  final String? description;
}

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

  static const empty = TasksLoadResult(tasks: [], milestones: [], comments: []);
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

  static DateTime? _parseDateTimeNullable(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      final p = DateTime.tryParse(v);
      return p;
    }
    return null;
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

  /// Status strings on singular [`task`] (e.g. Incomplete) vs legacy [`tasks`] (todo/in_progress/done).
  static TaskStatus _taskStatusFromSingularTaskDb(String? s) {
    final t = s?.trim().toLowerCase() ?? '';
    if (t == 'done' || t == 'completed' || t == 'complete')
      return TaskStatus.done;
    if (t == 'in_progress' || t == 'in progress') return TaskStatus.inProgress;
    if (t == 'delete' || t == 'deleted') return TaskStatus.todo;
    return TaskStatus.todo;
  }

  static String? _updateByDisplayName(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToName,
  ) {
    final raw = row['update_by']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return staffUuidToName[raw] ?? raw;
  }

  /// Same key space as [Task.assigneeIds] (`staff.app_id` when known).
  static String? _createByAssigneeKey(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToAppId,
  ) {
    final raw = row['create_by']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return staffUuidToAppId[raw] ?? raw;
  }

  /// Singular `task.pic` → assignee key (`staff.app_id` when known).
  static String? _picAssigneeKey(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToAppId,
  ) {
    final raw = row['pic']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return staffUuidToAppId[raw] ?? raw;
  }

  /// `task.create_by` is usually `staff.id` (uuid); may be `staff.app_id` text.
  static String? _createByDisplayName(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToName,
    Map<String, String> staffUuidToAppId,
  ) {
    final raw = row['create_by']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final byUuid = staffUuidToName[raw];
    if (byUuid != null) return byUuid;
    for (final e in staffUuidToAppId.entries) {
      if (e.value == raw) return staffUuidToName[e.key];
    }
    return raw;
  }

  static final Map<String, String> _staffNameCache = {};

  /// Resolves [staff.id] or [staff.app_id] to display name (cached).
  static Future<String> staffDisplayNameForKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) return '';
    final cached = _staffNameCache[k];
    if (cached != null) return cached;
    if (!_enabled) return k;
    try {
      final supabase = Supabase.instance.client;
      final byApp = await supabase
          .from('staff')
          .select('name')
          .eq('app_id', k)
          .maybeSingle();
      if (byApp != null) {
        final n = byApp['name'] as String? ?? k;
        _staffNameCache[k] = n;
        return n;
      }
      if (_looksLikeUuid(k)) {
        final byId = await supabase
            .from('staff')
            .select('name')
            .eq('id', k)
            .maybeSingle();
        if (byId != null) {
          final n = byId['name'] as String? ?? k;
          _staffNameCache[k] = n;
          return n;
        }
      }
    } catch (_) {}
    return k;
  }

  /// Batch resolve assignee keys to names for list subtitles.
  static Future<Map<String, String>> staffDisplayNamesForKeys(
    List<String> keys,
  ) async {
    final out = <String, String>{};
    for (final k in keys.toSet()) {
      if (k.isEmpty) continue;
      out[k] = await staffDisplayNameForKey(k);
    }
    return out;
  }

  /// Resolves [assigneeKey] (`staff.app_id` or `staff.id`) to the business team key
  /// (`team.team_id`, same as [StaffForAssignment.teamId]) for the PIC row.
  static Future<String?> fetchStaffTeamBusinessIdForAssigneeKey(
    String? assigneeKey,
  ) async {
    if (!_enabled) return null;
    final k = assigneeKey?.trim() ?? '';
    if (k.isEmpty) return null;
    try {
      final supabase = Supabase.instance.client;
      Map<String, dynamic>? row = await supabase
          .from('staff')
          .select('team_id')
          .eq('app_id', k)
          .maybeSingle();
      row ??= await supabase
          .from('staff')
          .select('team_id')
          .eq('id', k)
          .maybeSingle();
      var tid = row?['team_id']?.toString().trim();
      if (tid == null || tid.isEmpty) return null;
      if (_looksLikeUuid(tid)) {
        final trow = await supabase
            .from('team')
            .select('team_id')
            .eq('id', tid)
            .maybeSingle();
        final biz = trow?['team_id']?.toString().trim();
        if (biz != null && biz.isNotEmpty) return biz;
      }
      return tid;
    } catch (e, st) {
      debugPrint('fetchStaffTeamBusinessIdForAssigneeKey: $e\n$st');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchSingularTaskById(
    String taskId,
  ) async {
    if (!_enabled) return null;
    try {
      final r = await Supabase.instance.client
          .from('task')
          .select()
          .eq('id', taskId)
          .maybeSingle();
      if (r == null) return null;
      return Map<String, dynamic>.from(r);
    } catch (_) {
      return null;
    }
  }

  /// Singular [`task`] row as [Task] with assignee keys resolved (fresh from DB).
  static Future<Task?> fetchSingularTaskModelById(String taskId) async {
    if (!_enabled) return null;
    try {
      final row = await fetchSingularTaskById(taskId);
      if (row == null) return null;
      var teamUuidToAppId = <String, String>{};
      var staffUuidToAppId = <String, String>{};
      var staffUuidToName = <String, String>{};
      final maps = await _loadMaps();
      if (maps != null) {
        teamUuidToAppId = maps.teamUuidToAppId;
        staffUuidToAppId = maps.staffUuidToAppId;
        staffUuidToName = maps.staffUuidToName;
      }
      return _taskFromSingularTaskRow(
        row,
        staffUuidToAppId,
        teamUuidToAppId,
        staffUuidToName,
      );
    } catch (_) {
      return null;
    }
  }

  /// `staff.director` — used for delete permissions. False if column missing or error.
  static Future<bool> fetchStaffDirectorByStaffUuid(String staffUuid) async {
    if (!_enabled) return false;
    final id = staffUuid.trim();
    if (id.isEmpty) return false;
    try {
      final r = await Supabase.instance.client
          .from('staff')
          .select('director')
          .eq('id', id)
          .maybeSingle();
      if (r == null) return false;
      final v = r['director'];
      if (v is bool) return v;
      if (v == null) return false;
      return v == true || v == 1 || v == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Updates one row in singular [`task`]. Pass only fields to change.
  static Future<String?> updateSingularTaskRow({
    required String taskId,
    String? taskName,
    String? description,
    String? priority,
    List<String?>? assigneeSlots,
    DateTime? startDate,
    DateTime? dueDate,
    bool clearStartDate = false,
    bool clearDueDate = false,
    String? status,
    String? submission,
    String? updateByStaffLookupKey,

    /// Sets `task.pic` (staff id); omit to leave column unchanged.
    String? picStaffLookupKey,

    /// When true, sets `change_due_reason` (null clears).
    bool updateChangeDueReason = false,
    String? changeDueReason,

    /// Sets `task.submit_date` to current HK instant (PIC **Submit**).
    bool stampSubmitDateNow = false,

    /// Sets `task.completion_date` (use [task.submitDate] at **Accept**).
    DateTime? completionDateAt,

    /// Clears `task.completion_date` (e.g. **Return**).
    bool clearCompletionDate = false,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    try {
      final map = <String, dynamic>{};
      if (taskName != null) map['task_name'] = taskName;
      if (description != null) map['description'] = description;
      if (priority != null) map['priority'] = priority;
      if (assigneeSlots != null) {
        for (var i = 0; i < 10; i++) {
          final key = 'assignee_${(i + 1).toString().padLeft(2, '0')}';
          final v = i < assigneeSlots.length ? assigneeSlots[i]?.trim() : null;
          map[key] = (v == null || v.isEmpty) ? null : v;
        }
      }
      if (clearStartDate) {
        map['start_date'] = null;
      } else if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (clearDueDate) {
        map['due_date'] = null;
      } else if (dueDate != null) {
        map['due_date'] = HkTime.dateOnlyHkMidnightForDb(dueDate);
      }
      if (status != null) map['status'] = status;
      if (submission != null) map['submission'] = submission;
      final lookup = updateByStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId == null || staffId.isEmpty) {
          return 'Could not resolve staff id for update_by';
        }
        map['update_by'] = staffId;
        map['update_date'] = HkTime.timestampForDb();
      }
      final picLookup = picStaffLookupKey?.trim();
      if (picLookup != null && picLookup.isNotEmpty) {
        final picStaffId = await _staffRowIdForAssigneeKey(picLookup);
        if (picStaffId != null && picStaffId.isNotEmpty) {
          map['pic'] = picStaffId;
        }
      }
      if (updateChangeDueReason) {
        final t = changeDueReason?.trim();
        map['change_due_reason'] = (t == null || t.isEmpty) ? null : t;
      }
      if (clearCompletionDate) {
        map['completion_date'] = null;
      } else if (completionDateAt != null) {
        map['completion_date'] =
            HkTime.timestampForDbFromStoredUtc(completionDateAt.toUtc());
      }
      if (stampSubmitDateNow) {
        map['submit_date'] = HkTime.timestampForDb();
      }
      if (map.isEmpty) return null;
      await Supabase.instance.client.from('task').update(map).eq('id', taskId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// All attachment rows for a singular task.
  ///
  /// Selects only `id`, `content`, `description` and orders by `id` so schemas that use
  /// `create_date` / `created_at` / neither do not break PostgREST (see sub-task attachments).
  static Future<List<TaskAttachmentRow>> fetchAttachmentsForTask(
    String taskId,
  ) async {
    if (!_enabled) return [];
    final id = taskId.trim();
    if (id.isEmpty) return [];
    try {
      final res = await Supabase.instance.client
          .from('attachment')
          .select('id, content, description')
          .eq('task_id', id)
          .order('id', ascending: true);
      final out = <TaskAttachmentRow>[];
      var i = 0;
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final content = m['content']?.toString();
        final description = m['description']?.toString();
        final rowId = m['id']?.toString().trim() ?? '';
        final rowUuid = rowId.isNotEmpty
            ? rowId
            : 'task-att-$i-${content.hashCode}-${description.hashCode}';
        i++;
        out.add(
          TaskAttachmentRow(
            id: rowUuid,
            content: content,
            description: description,
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('fetchAttachmentsForTask: $e');
      rethrow;
    }
  }

  /// First hyperlink only (legacy callers).
  static Future<String?> fetchAttachmentContentForTask(String taskId) async {
    try {
      final rows = await fetchAttachmentsForTask(taskId);
      for (final r in rows) {
        final c = r.content?.trim();
        if (c != null && c.isNotEmpty) return c;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Replaces all `attachment` rows for [taskId] with [rows] (skips rows where both fields are empty).
  static Future<String?> replaceAttachmentsForTask({
    required String taskId,
    required List<({String? content, String? description})> rows,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final id = taskId.trim();
    if (id.isEmpty) return 'Missing task id';
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('attachment').delete().eq('task_id', id);
      for (final r in rows) {
        final c = r.content?.trim() ?? '';
        final d = r.description?.trim() ?? '';
        if (c.isEmpty && d.isEmpty) continue;
        final map = <String, dynamic>{
          'task_id': id,
          'content': c.isEmpty ? null : c,
          'description': d.isEmpty ? null : d,
        };
        await supabase.from('attachment').insert(map);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Upserts the single attachment row for [taskId]. Pass empty [content] to delete all rows.
  @Deprecated('Use replaceAttachmentsForTask')
  static Future<String?> upsertAttachmentContentForTask({
    required String taskId,
    required String content,
  }) async {
    return replaceAttachmentsForTask(
      taskId: taskId,
      rows: [
        (content: content, description: null),
      ],
    );
  }

  static int _priorityFromFlexible(dynamic p) {
    if (p is num) return p.toInt().clamp(1, 2);
    final s = p?.toString().trim().toLowerCase() ?? '';
    if (s.contains('urgent') || s == '2') return 2;
    return 1;
  }

  /// Maps a row from singular [`task`] (task_name, assignee_01…) into [Task].
  /// Includes rows with status `Deleted` for the Deleted tab.
  static Task? _taskFromSingularTaskRow(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToAppId,
    Map<String, String> teamUuidToAppId,
    Map<String, String> staffUuidToName,
  ) {
    final id = row['id']?.toString() ?? row['task_id']?.toString();
    if (id == null || id.isEmpty) return null;
    final statusRaw = row['status']?.toString().trim() ?? '';

    final assigneeIds = <String>[];
    for (var i = 1; i <= 10; i++) {
      final key = 'assignee_${i.toString().padLeft(2, '0')}';
      final v = row[key];
      if (v == null) continue;
      final sid = v.toString().trim();
      if (sid.isEmpty) continue;
      assigneeIds.add(staffUuidToAppId[sid] ?? sid);
    }

    final teamUuid = row['team_id']?.toString();
    String? teamAppId;
    if (teamUuid != null && teamUuid.isNotEmpty) {
      teamAppId = teamUuidToAppId[teamUuid];
    }

    return Task(
      id: id,
      teamId: teamAppId,
      name: row['task_name'] as String? ?? row['name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      assigneeIds: assigneeIds,
      priority: _priorityFromFlexible(row['priority']),
      startDate: _parseDate(row['start_date']),
      endDate: _parseDate(row['due_date']) ?? _parseDate(row['end_date']),
      createdAt: _parseDateTime(row['created_at'] ?? row['create_date']),
      status: _taskStatusFromSingularTaskDb(row['status'] as String?),
      progressPercent: (row['progress_percent'] as num?)?.toInt() ?? 0,
      isSingularTableRow: true,
      dbStatus: statusRaw.isEmpty ? null : statusRaw,
      updateByStaffName: _updateByDisplayName(row, staffUuidToName),
      createByStaffName: _createByDisplayName(
        row,
        staffUuidToName,
        staffUuidToAppId,
      ),
      createByAssigneeKey: _createByAssigneeKey(row, staffUuidToAppId),
      pic: _picAssigneeKey(row, staffUuidToAppId),
      updateDate: _parseDateTimeNullable(row['update_date']),
      submission: _submissionFromRow(row['submission']),
      submitDate: _parseDateTimeNullable(row['submit_date']),
      completionDate: _parseDateTimeNullable(row['completion_date']),
      changeDueReason: _nullableTrimmedString(row['change_due_reason']),
    );
  }

  static String? _nullableTrimmedString(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return s;
  }

  static String? _submissionFromRow(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return s;
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
      final byPk = await supabase
          .from('team')
          .select('id')
          .eq('id', k)
          .maybeSingle();
      if (byPk != null) return byPk['id'] as String?;
    }
    return null;
  }

  static Future<
    ({
      Map<String, String> teamUuidToAppId,
      Map<String, String> staffUuidToAppId,
      Map<String, String> staffUuidToName,
    })?
  >
  _loadMaps() async {
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
    return (
      teamUuidToAppId: teamUuidToAppId,
      staffUuidToAppId: staffUuidToAppId,
      staffUuidToName: staffUuidToName,
    );
  }

  static Future<String?> _staffUuidForAppId(String appId) async {
    final supabase = Supabase.instance.client;
    final r = await supabase
        .from('staff')
        .select('id')
        .eq('app_id', appId)
        .maybeSingle();
    return r?['id'] as String?;
  }

  /// `team` rows (`team_id`, `team_name`) and `staff` rows joined by `staff.team_id` = `team.team_id`.
  static Future<StaffAssigneePickerData?> fetchStaffAssigneePickerData() async {
    if (!_enabled) return null;
    try {
      final supabase = Supabase.instance.client;
      final teamRes = await supabase
          .from('team')
          .select('team_id, team_name')
          .order('team_name');
      final teams = <TeamOptionRow>[];
      for (final r in (teamRes as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final tid = m['team_id']?.toString() ?? '';
        if (tid.isEmpty) continue;
        final tn = m['team_name'] as String? ?? tid;
        teams.add(TeamOptionRow(teamId: tid, teamName: tn));
      }
      final staffRes = await supabase
          .from('staff')
          .select('id, app_id, name, team_id')
          .order('name');
      final staff = <StaffForAssignment>[];
      for (final r in (staffRes as List)) {
        final m = Map<String, dynamic>.from(r as Map);
        final appId = m['app_id'] as String?;
        final id = m['id']?.toString() ?? '';
        final assigneeId = (appId != null && appId.isNotEmpty) ? appId : id;
        if (assigneeId.isEmpty) continue;
        final name = m['name'] as String? ?? assigneeId;
        final rawTeam = m['team_id']?.toString();
        final teamId = rawTeam != null && rawTeam.isNotEmpty ? rawTeam : null;
        staff.add(
          StaffForAssignment(
            assigneeId: assigneeId,
            name: name,
            teamId: teamId,
          ),
        );
      }
      return StaffAssigneePickerData(teams: teams, staff: staff);
    } catch (e) {
      return null;
    }
  }

  /// Teams for the Tasks tab "Filter by team". [Team.id] is `team.team_id`, same as [Task.teamId].
  static Future<List<Team>> fetchTeamsForFilterFromSupabase() async {
    if (!_enabled) return [];
    try {
      final supabase = Supabase.instance.client;
      final teamRes = await supabase
          .from('team')
          .select('team_id, team_name')
          .order('team_name');
      final staffRes = await supabase.from('staff').select('app_id, team_id');
      final byTeam = <String, List<String>>{};
      for (final raw in (staffRes as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final tid = m['team_id']?.toString().trim() ?? '';
        final aid = m['app_id']?.toString().trim() ?? '';
        if (tid.isEmpty || aid.isEmpty) continue;
        byTeam.putIfAbsent(tid, () => []).add(aid);
      }
      final teams = <Team>[];
      for (final raw in (teamRes as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final tid = m['team_id']?.toString().trim() ?? '';
        if (tid.isEmpty) continue;
        final name = m['team_name'] as String? ?? tid;
        final members = List<String>.from(byTeam[tid] ?? [])..sort();
        teams.add(
          Team(id: tid, name: name, directorIds: const [], officerIds: members),
        );
      }
      return teams;
    } catch (e, st) {
      debugPrint('fetchTeamsForFilterFromSupabase: $e\n$st');
      return [];
    }
  }

  /// Lookup keys ( `staff.app_id` or `staff.id` UUID ) → `staff.team_id` for team filtering.
  static Future<Map<String, String>> fetchStaffAppIdToTeamIdMap() async {
    if (!_enabled) return {};
    try {
      final res = await Supabase.instance.client
          .from('staff')
          .select('id, app_id, team_id');
      final map = <String, String>{};
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final pk = m['id']?.toString().trim() ?? '';
        final aid = m['app_id']?.toString().trim() ?? '';
        final tid = m['team_id']?.toString().trim() ?? '';
        if (tid.isEmpty) continue;
        if (aid.isNotEmpty) map[aid] = tid;
        if (pk.isNotEmpty) map[pk] = tid;
      }
      return map;
    } catch (e, st) {
      debugPrint('fetchStaffAppIdToTeamIdMap: $e\n$st');
      return {};
    }
  }

  /// Staff rows for assignee name resolution (e.g. "Filter by team member").
  static Future<List<Assignee>> fetchStaffAssigneesFromSupabase() async {
    if (!_enabled) return [];
    try {
      final res = await Supabase.instance.client
          .from('staff')
          .select('app_id, name')
          .order('name');
      final out = <Assignee>[];
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['app_id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        out.add(Assignee(id: id, name: m['name'] as String? ?? id));
      }
      return out;
    } catch (e, st) {
      debugPrint('fetchStaffAssigneesFromSupabase: $e\n$st');
      return [];
    }
  }

  /// Rows in [subordinate] where [supervisor_id] is the supervisor's `staff.app_id`.
  static Future<List<String>> fetchSubordinateAppIdsForSupervisor(
    String supervisorAppId,
  ) async {
    if (!_enabled) return [];
    final s = supervisorAppId.trim();
    if (s.isEmpty) return [];
    try {
      final res = await Supabase.instance.client
          .from('subordinate')
          .select('subordinate_id')
          .eq('supervisor_id', s);
      final out = <String>[];
      for (final row in (res as List)) {
        final id = (row as Map)['subordinate_id']?.toString().trim();
        if (id != null && id.isNotEmpty) out.add(id);
      }
      return out;
    } catch (_) {
      return [];
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

      final initRes = await supabase
          .from('initiatives')
          .select()
          .order('created_at', ascending: false);
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
        initiatives.add(
          Initiative(
            id: id,
            teamId: teamAppId,
            directorIds: List<String>.from(dirsByInit[id] ?? []),
            name: row['name'] as String? ?? '',
            description: row['description'] as String? ?? '',
            priority: (row['priority'] as num?)?.toInt() ?? 1,
            startDate: _parseDate(row['start_date']),
            endDate: _parseDate(row['end_date']),
            createdAt: _parseDateTime(row['created_at']),
          ),
        );
      }

      final subRes = await supabase
          .from('sub_tasks')
          .select()
          .inFilter('initiative_id', initiativeIds);
      final subTasks = <SubTask>[];
      for (final row in (subRes as List)) {
        subTasks.add(
          SubTask(
            id: row['id'] as String,
            initiativeId: row['initiative_id'] as String,
            label: row['label'] as String? ?? '',
            isCompleted: row['is_completed'] as bool? ?? false,
          ),
        );
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
        comments.add(
          TaskComment(
            id: row['id'] as String,
            taskId: row['entity_id'] as String,
            authorId: staffUuidToAppId[authorId] ?? authorId,
            authorName: staffUuidToName[authorId] ?? authorId,
            body: row['body'] as String? ?? '',
            createdAt: _parseDateTime(row['created_at']),
          ),
        );
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
      var teamUuidToAppId = <String, String>{};
      var staffUuidToAppId = <String, String>{};
      var staffUuidToName = <String, String>{};
      try {
        final maps = await _loadMaps();
        if (maps != null) {
          teamUuidToAppId = maps.teamUuidToAppId;
          staffUuidToAppId = maps.staffUuidToAppId;
          staffUuidToName = maps.staffUuidToName;
        }
      } catch (_) {}
      final supabase = Supabase.instance.client;

      final taskRows = <dynamic>[];
      try {
        final taskRes = await supabase
            .from('tasks')
            .select()
            .order('created_at', ascending: false);
        taskRows.addAll(taskRes as List);
      } catch (_) {
        // Plural `tasks` missing, RLS, or unused — still load singular `task` below.
      }
      final taskIds = taskRows
          .map((r) => (r as Map)['id'] as String?)
          .whereType<String>()
          .toList();

      final assignByTask = <String, List<String>>{};
      if (taskIds.isNotEmpty) {
        final assignRes = await supabase
            .from('task_assignees')
            .select('task_id, staff_id')
            .inFilter('task_id', taskIds);
        for (final row in (assignRes as List)) {
          final tid = row['task_id'] as String;
          final sid = row['staff_id'] as String;
          final appId = staffUuidToAppId[sid] ?? sid;
          assignByTask.putIfAbsent(tid, () => []).add(appId);
        }
      }

      final tasks = <Task>[];
      for (final raw in taskRows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id'] as String;
        final teamUuid = row['team_id'] as String?;
        final teamAppId = teamUuid == null ? null : teamUuidToAppId[teamUuid];
        tasks.add(
          Task(
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
          ),
        );
      }

      // Rows created by [insertTaskTableRow] live in singular [`task`], not [`tasks`].
      final singularTasks = <Task>[];
      try {
        dynamic singularRes;
        try {
          singularRes = await supabase
              .from('task')
              .select()
              .order('created_at', ascending: false);
        } catch (_) {
          try {
            singularRes = await supabase
                .from('task')
                .select()
                .order('create_date', ascending: false);
          } catch (_) {
            singularRes = await supabase.from('task').select();
          }
        }
        for (final raw in (singularRes as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          final t = _taskFromSingularTaskRow(
            row,
            staffUuidToAppId,
            teamUuidToAppId,
            staffUuidToName,
          );
          if (t != null) singularTasks.add(t);
        }
      } catch (_) {
        // table missing or RLS
      }

      final byId = <String, Task>{};
      for (final t in tasks) {
        byId[t.id] = t;
      }
      // Singular `task` rows take precedence over legacy `tasks` when ids collide.
      for (final t in singularTasks) {
        byId[t.id] = t;
      }
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      List<Milestone> milestones = [];
      if (taskIds.isNotEmpty) {
        try {
          final mileRes = await supabase
              .from('task_milestones')
              .select()
              .inFilter('task_id', taskIds);
          for (final row in (mileRes as List)) {
            milestones.add(
              Milestone(
                id: row['id'] as String,
                taskId: row['task_id'] as String,
                label: row['label'] as String? ?? '',
                progressPercent:
                    (row['progress_percent'] as num?)?.toInt() ?? 0,
                isCompleted: row['is_completed'] as bool? ?? false,
                completedAt: _parseDate(row['completed_at']),
              ),
            );
          }
        } catch (_) {
          // table may not exist yet
        }
      }

      final comments = <TaskComment>[];
      if (taskIds.isNotEmpty) {
        final commRes = await supabase
            .from('comments')
            .select()
            .eq('entity_type', 'task')
            .inFilter('entity_id', taskIds)
            .order('created_at');
        for (final row in (commRes as List)) {
          final authorId = row['author_id'] as String;
          comments.add(
            TaskComment(
              id: row['id'] as String,
              taskId: row['entity_id'] as String,
              authorId: staffUuidToAppId[authorId] ?? authorId,
              authorName: staffUuidToName[authorId] ?? authorId,
              body: row['body'] as String? ?? '',
              createdAt: _parseDateTime(row['created_at']),
            ),
          );
        }
      }

      return TasksLoadResult(
        tasks: merged,
        milestones: milestones,
        comments: comments,
      );
    } catch (_) {
      return TasksLoadResult.empty;
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
  static Future<List<String?>> assigneeSlotsForTask(
    List<String> staffKeys,
  ) async {
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

  /// Returns [staff.app_id] when set, else [staffUuid] — matches how [Task.assigneeIds] is stored after fetch.
  static Future<String> assigneeListKeyFromStaffUuid(String staffUuid) async {
    final u = staffUuid.trim();
    if (u.isEmpty) return u;
    if (!_enabled) return u;
    try {
      final r = await Supabase.instance.client
          .from('staff')
          .select('app_id')
          .eq('id', u)
          .maybeSingle();
      final app = r?['app_id'] as String?;
      if (app != null && app.trim().isNotEmpty) return app.trim();
    } catch (_) {}
    return u;
  }

  static Future<String?> _staffRowIdForAssigneeKey(String key) async {
    final k = key.trim();
    if (k.isEmpty) return null;
    final supabase = Supabase.instance.client;
    final byApp = await supabase
        .from('staff')
        .select('id')
        .eq('app_id', k)
        .maybeSingle();
    if (byApp != null) return byApp['id'] as String?;
    if (_looksLikeUuid(k)) {
      final byId = await supabase
          .from('staff')
          .select('id')
          .eq('id', k)
          .maybeSingle();
      if (byId != null) return byId['id'] as String?;
    }
    return null;
  }

  /// Resolves `staff.app_id` or `staff.id` (uuid) to `staff.id` (uuid).
  static Future<String?> staffRowIdForAssigneeKey(String key) =>
      _staffRowIdForAssigneeKey(key);

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
        list.add(
          StaffListRow(
            id: id,
            name: (m['name'] as String?)?.trim().isNotEmpty == true
                ? m['name'] as String
                : id,
          ),
        );
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Inserts one row into the singular [`task`] table (not legacy [`tasks`]).
  /// [assignees] — up to 10 values, each the string form of **`staff.id`** (uuid).
  /// [status] — must match your DB `task.status` constraint (default `Incomplete`).
  /// [creatorStaffLookupKey] — `staff.app_id` or `staff.id` (uuid); sets `create_by` to
  /// resolved **`staff.id`** and `create_date` to now. `update_by` / `update_date` left unset (NULL).
  ///
  /// Returns `(error, taskId)` — [error] if insert failed, else [taskId] from the new row.
  static Future<({String? error, String? taskId})> insertTaskTableRow({
    required String taskName,
    List<String?> assignees = const [],
    String? priority,
    DateTime? startDate,
    DateTime? dueDate,
    String? description,
    String status = 'Incomplete',
    String? creatorStaffLookupKey,

    /// `staff.app_id` or uuid; stored as `task.pic` (staff id).
    String? picStaffLookupKey,

    /// When due span exceeds policy for priority.
    String? changeDueReason,
  }) async {
    if (!_enabled) return (error: 'Supabase not configured', taskId: null);
    final name = taskName.trim();
    if (name.isEmpty) return (error: 'task_name is required', taskId: null);
    try {
      var padded = List<String?>.from(assignees);
      while (padded.length < 10) {
        padded.add(null);
      }
      if (padded.length > 10) {
        padded = padded.sublist(0, 10);
      }
      final s = status.trim();
      if (s.isEmpty) return (error: 'status is required', taskId: null);
      final map = <String, dynamic>{
        'task_name': name,
        'priority': priority,
        'description': description,
        'status': s,
      };
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
          map['create_date'] = HkTime.timestampForDb();
        }
      }
      if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (dueDate != null) {
        map['due_date'] = HkTime.dateOnlyHkMidnightForDb(dueDate);
      }
      for (var i = 0; i < 10; i++) {
        final raw = padded[i]?.trim();
        if (raw != null && raw.isNotEmpty) {
          map['assignee_${(i + 1).toString().padLeft(2, '0')}'] = raw;
        }
      }
      final picLookup = picStaffLookupKey?.trim();
      if (picLookup != null && picLookup.isNotEmpty) {
        final picStaffId = await _staffRowIdForAssigneeKey(picLookup);
        if (picStaffId != null && picStaffId.isNotEmpty) {
          map['pic'] = picStaffId;
        }
      }
      final cdr = changeDueReason?.trim();
      if (cdr != null && cdr.isNotEmpty) {
        map['change_due_reason'] = cdr;
      }
      final res = await Supabase.instance.client
          .from('task')
          .insert(map)
          .select('id')
          .maybeSingle();
      final id = res?['id']?.toString();
      return (error: null, taskId: id);
    } catch (e) {
      return (error: e.toString(), taskId: null);
    }
  }

  /// Inserts into `public."comment"` (singular table name in Postgres).
  static Future<({String? error, String? commentId})> insertSingularCommentRow({
    required String taskId,
    required String description,
    String status = 'Active',
    String? creatorStaffLookupKey,
  }) async {
    if (!_enabled) return (error: 'Supabase not configured', commentId: null);
    final d = description.trim();
    if (d.isEmpty) return (error: null, commentId: null);
    try {
      final st = status.trim();
      final map = <String, dynamic>{
        'task_id': taskId,
        'description': d,
        'status': st.isEmpty ? 'Active' : st,
        'create_date': HkTime.timestampForDb(),
      };
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
        }
      }
      final res = await Supabase.instance.client
          .from('comment')
          .insert(map)
          .select('id')
          .maybeSingle();
      final id = res?['id']?.toString();
      return (error: null, commentId: id);
    } catch (e) {
      return (error: e.toString(), commentId: null);
    }
  }

  static Future<String?> updateSingularCommentRow({
    required String commentId,
    required String description,
    String? updaterStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final d = description.trim();
    if (d.isEmpty) return 'Comment is empty';
    try {
      final map = <String, dynamic>{
        'description': d,
        'update_date': HkTime.timestampForDb(),
      };
      final lookup = updaterStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
        }
      }
      await Supabase.instance.client
          .from('comment')
          .update(map)
          .eq('id', commentId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Sets `status` to `Deleted` and stamps `update_date` / `update_by`.
  static Future<String?> softDeleteSingularCommentRow({
    required String commentId,
    String? updaterStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    try {
      final map = <String, dynamic>{
        'status': 'Deleted',
        'update_date': HkTime.timestampForDb(),
      };
      final lookup = updaterStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
        }
      }
      await Supabase.instance.client
          .from('comment')
          .update(map)
          .eq('id', commentId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Loads `public."comment"` for [taskId]. Active rows first, then deleted; within each
  /// group, descending by `create_date` only (newest first). [update_date] is ignored for order.
  static Future<List<SingularCommentRowDisplay>> fetchSingularCommentsForTask(
    String taskId,
  ) async {
    if (!_enabled) return [];
    try {
      final res = await Supabase.instance.client
          .from('comment')
          .select()
          .eq('task_id', taskId);
      final rows = <Map<String, dynamic>>[];
      for (final raw in (res as List)) {
        rows.add(Map<String, dynamic>.from(raw as Map));
      }
      final idSet = <String>{};
      for (final r in rows) {
        final cb = r['create_by']?.toString().trim();
        if (cb != null && cb.isNotEmpty) idSet.add(cb);
      }
      final names = <String, String>{};
      for (final id in idSet) {
        names[id] = await staffDisplayNameForKey(id);
      }
      final out = <SingularCommentRowDisplay>[];
      for (final r in rows) {
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final cb = r['create_by']?.toString().trim();
        final name = (cb != null && cb.isNotEmpty) ? (names[cb] ?? cb) : '—';
        final statusStr = r['status']?.toString() ?? '';
        out.add(
          SingularCommentRowDisplay(
            id: id,
            description: r['description']?.toString() ?? '',
            status: statusStr,
            createByStaffId: cb,
            displayStaffName: name,
            createTimestampUtc: _parseDateTimeNullable(r['create_date']),
            updateTimestampUtc: _parseDateTimeNullable(r['update_date']),
          ),
        );
      }
      out.sort((a, b) {
        if (a.isDeleted != b.isDeleted) {
          return a.isDeleted ? 1 : -1;
        }
        final ac =
            a.createTimestampUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bc =
            b.createTimestampUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bc.compareTo(ac);
      });
      return out;
    } catch (_) {
      return [];
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
      await Supabase.instance.client
          .from('sub_tasks')
          .update({'is_completed': isCompleted})
          .eq('id', subTaskId);
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
      await Supabase.instance.client
          .from('task_milestones')
          .update({
            'progress_percent': progressPercent,
            'is_completed': progressPercent >= 100,
            'completed_at': progressPercent >= 100
                ? DateTime.now().toIso8601String()
                : null,
          })
          .eq('id', milestoneId);
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
        list.add(
          DeletedTaskRecord(
            taskId: row['task_id'] as String,
            taskName: row['task_name'] as String? ?? '',
            teamId: teamAppId,
            assigneeIds: assigneeAppIds,
            deletedAt: _parseDateTime(row['deleted_at']),
            deletedByName: row['deleted_by'] as String? ?? '',
          ),
        );
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

  static Future<Map<String, String>> _staffUuidToAppIdMapAll() async {
    final m = <String, String>{};
    if (!_enabled) return m;
    try {
      final res =
          await Supabase.instance.client.from('staff').select('id, app_id');
      for (final raw in (res as List)) {
        final r = Map<String, dynamic>.from(raw as Map);
        final id = r['id']?.toString().trim() ?? '';
        if (id.isEmpty) continue;
        final app = r['app_id']?.toString().trim() ?? '';
        m[id] = app.isNotEmpty ? app : id;
      }
    } catch (_) {}
    return m;
  }

  static SingularSubtask? _singularSubtaskFromRow(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToAppId,
    Map<String, String> staffUuidToName,
  ) {
    final id = row['id']?.toString() ?? '';
    final taskId = row['task_id']?.toString() ?? '';
    if (id.isEmpty || taskId.isEmpty) return null;
    final assigneeIds = <String>[];
    for (var i = 1; i <= 10; i++) {
      final key = 'assignee_${i.toString().padLeft(2, '0')}';
      final v = row[key];
      if (v == null) continue;
      final sid = v.toString().trim();
      if (sid.isEmpty) continue;
      assigneeIds.add(staffUuidToAppId[sid] ?? sid);
    }
    final picRaw = row['pic']?.toString().trim();
    String? picKey;
    if (picRaw != null && picRaw.isNotEmpty) {
      picKey = staffUuidToAppId[picRaw] ?? picRaw;
    }
    final cb = row['create_by']?.toString().trim();
    return SingularSubtask(
      id: id,
      taskId: taskId,
      createByStaffId: cb?.isNotEmpty == true ? cb : null,
      createByStaffName: _createByDisplayName(
        row,
        staffUuidToName,
        staffUuidToAppId,
      ),
      subtaskName: row['subtask_name'] as String? ?? '',
      description: row['description'] as String? ?? '',
      priority: _priorityFromFlexible(row['priority']),
      startDate: _parseDate(row['start_date']),
      dueDate: _parseDate(row['due_date']),
      status: row['status'] as String? ?? 'Incomplete',
      submission: row['submission'] as String?,
      submitDate: _parseDateTimeNullable(row['submit_date']),
      completionDate: _parseDateTimeNullable(row['completion_date']),
      assigneeIds: assigneeIds,
      pic: picKey,
      createDate: _parseDateTime(row['create_date']),
      updateDate: _parseDateTimeNullable(row['update_date']),
      updateByStaffName: _updateByDisplayName(row, staffUuidToName),
      changeDueReason: _nullableTrimmedString(row['change_due_reason']),
    );
  }

  /// Non-deleted subtasks for a parent [taskId], newest first.
  static Future<List<SingularSubtask>> fetchSubtasksForTask(
    String taskId,
  ) async {
    if (!_enabled) return [];
    try {
      final maps = await _loadMaps();
      final staffMap = maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
      final staffNames = maps?.staffUuidToName ?? <String, String>{};
      final res = await Supabase.instance.client
          .from('subtask')
          .select()
          .eq('task_id', taskId)
          .order('create_date', ascending: false);
      final out = <SingularSubtask>[];
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final st = _singularSubtaskFromRow(row, staffMap, staffNames);
        if (st != null && !st.isDeleted) out.add(st);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<SingularSubtask?> fetchSubtaskById(String subtaskId) async {
    if (!_enabled) return null;
    try {
      final maps = await _loadMaps();
      final staffMap = maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
      final staffNames = maps?.staffUuidToName ?? <String, String>{};
      final res = await Supabase.instance.client
          .from('subtask')
          .select()
          .eq('id', subtaskId)
          .maybeSingle();
      if (res == null) return null;
      return _singularSubtaskFromRow(
        Map<String, dynamic>.from(res as Map),
        staffMap,
        staffNames,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<({String? error, String? subtaskId})> insertSubtaskRow({
    required String taskId,
    required String subtaskName,
    required String description,
    required String priorityDisplay,
    DateTime? startDate,
    DateTime? dueDate,
    required List<String?> assigneeStaffUuids,
    required String picStaffUuid,
    String? creatorStaffLookupKey,
    String? initialComment,
    String? changeDueReason,
  }) async {
    if (!_enabled) return (error: 'Supabase not configured', subtaskId: null);
    final name = subtaskName.trim();
    if (name.isEmpty) return (error: 'subtask_name is required', subtaskId: null);
    try {
      var padded = List<String?>.from(assigneeStaffUuids);
      while (padded.length < 10) {
        padded.add(null);
      }
      if (padded.length > 10) padded = padded.sublist(0, 10);
      final map = <String, dynamic>{
        'task_id': taskId,
        'subtask_name': name,
        'description': description.trim(),
        'priority': priorityDisplay,
        'status': 'Incomplete',
        'submission': 'Pending',
      };
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
          map['create_date'] = HkTime.timestampForDb();
        }
      }
      if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (dueDate != null) {
        map['due_date'] = HkTime.dateOnlyHkMidnightForDb(dueDate);
      }
      for (var i = 0; i < 10; i++) {
        final raw = padded[i]?.trim();
        if (raw != null && raw.isNotEmpty) {
          map['assignee_${(i + 1).toString().padLeft(2, '0')}'] = raw;
        }
      }
      final pic = picStaffUuid.trim();
      if (pic.isNotEmpty) {
        map['pic'] = pic;
      }
      final cdr = changeDueReason?.trim();
      if (cdr != null && cdr.isNotEmpty) {
        map['change_due_reason'] = cdr;
      }
      final ins = await Supabase.instance.client
          .from('subtask')
          .insert(map)
          .select('id')
          .maybeSingle();
      final sid = ins?['id']?.toString();
      if (sid == null || sid.isEmpty) {
        return (error: 'Insert returned no id', subtaskId: null);
      }
      if (initialComment != null && initialComment.trim().isNotEmpty) {
        await insertSubtaskCommentRow(
          subtaskId: sid,
          description: initialComment.trim(),
          creatorStaffLookupKey: creatorStaffLookupKey,
        );
      }
      return (error: null, subtaskId: sid);
    } catch (e) {
      return (error: e.toString(), subtaskId: null);
    }
  }

  static Future<String?> updateSubtaskRow({
    required String subtaskId,
    String? subtaskName,
    String? description,
    String? priorityDisplay,
    DateTime? startDate,
    bool clearStartDate = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    String? status,
    String? submission,

    /// Sets `subtask.pic` (staff id); omit to leave column unchanged.
    String? picStaffLookupKey,
    String? updaterStaffLookupKey,

    /// When true, sets `change_due_reason` (null clears).
    bool updateChangeDueReason = false,
    String? changeDueReason,

    bool stampSubmitDateNow = false,
    DateTime? completionDateAt,
    bool clearCompletionDate = false,

    /// When false, does not set `update_date` (and omit [updaterStaffLookupKey] to leave `update_by` unchanged).
    /// Use for edits that should not appear as “Last updated” on the sub-task row (e.g. non-creator PIC only).
    bool bumpSubtaskRowAuditFields = true,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    try {
      final map = <String, dynamic>{};
      if (bumpSubtaskRowAuditFields) {
        map['update_date'] = HkTime.timestampForDb();
      }
      if (subtaskName != null) map['subtask_name'] = subtaskName.trim();
      if (description != null) map['description'] = description.trim();
      if (priorityDisplay != null) map['priority'] = priorityDisplay;
      if (clearStartDate) {
        map['start_date'] = null;
      } else if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (clearDueDate) {
        map['due_date'] = null;
      } else if (dueDate != null) {
        map['due_date'] = HkTime.dateOnlyHkMidnightForDb(dueDate);
      }
      if (status != null) map['status'] = status;
      if (submission != null) map['submission'] = submission;
      final picLookup = picStaffLookupKey?.trim();
      if (picLookup != null && picLookup.isNotEmpty) {
        final picStaffId = await _staffRowIdForAssigneeKey(picLookup);
        if (picStaffId != null && picStaffId.isNotEmpty) {
          map['pic'] = picStaffId;
        }
      }
      final lookup = updaterStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId == null || staffId.isEmpty) {
          return 'Could not resolve staff id for update_by';
        }
        map['update_by'] = staffId;
      }
      if (updateChangeDueReason) {
        final t = changeDueReason?.trim();
        map['change_due_reason'] = (t == null || t.isEmpty) ? null : t;
      }
      if (clearCompletionDate) {
        map['completion_date'] = null;
      } else if (completionDateAt != null) {
        map['completion_date'] =
            HkTime.timestampForDbFromStoredUtc(completionDateAt.toUtc());
      }
      if (stampSubmitDateNow) {
        map['submit_date'] = HkTime.timestampForDb();
      }
      await Supabase.instance.client.from('subtask').update(map).eq('id', subtaskId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> markSubtaskDeleted({
    required String subtaskId,
    String? updaterStaffLookupKey,
    bool bumpSubtaskRowAuditFields = true,
  }) async {
    return updateSubtaskRow(
      subtaskId: subtaskId,
      status: 'Deleted',
      updaterStaffLookupKey: updaterStaffLookupKey,
      bumpSubtaskRowAuditFields: bumpSubtaskRowAuditFields,
    );
  }

  /// All `subtask_attachment` rows for [subtaskId].
  static Future<List<SubtaskAttachmentRow>> fetchSubtaskAttachments(
    String subtaskId,
  ) async {
    if (!_enabled) return [];
    final sid = subtaskId.trim();
    if (sid.isEmpty) return [];
    try {
      // Avoid created_at vs create_date drift across DBs; id order is stable for the list UI.
      final res = await Supabase.instance.client
          .from('subtask_attachment')
          .select('id, content, description')
          .eq('subtask_id', sid)
          .order('id', ascending: true);
      final out = <SubtaskAttachmentRow>[];
      var i = 0;
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final content = m['content']?.toString();
        final description = m['description']?.toString();
        final rowId = m['id']?.toString().trim() ?? '';
        final id = rowId.isNotEmpty
            ? rowId
            : 'subtask-att-$i-${content.hashCode}-${description.hashCode}';
        i++;
        out.add(
          SubtaskAttachmentRow(
            id: id,
            content: content,
            description: description,
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('fetchSubtaskAttachments: $e');
      rethrow;
    }
  }

  /// Replaces all `subtask_attachment` rows (skips rows where both fields are empty).
  ///
  /// Inserts use `subtask_id` only (see migration `035_subtask_tables.sql`). If your database
  /// adds an optional `task_id` column (e.g. `042_subtask_attachment_task_id.sql`), run that
  /// migration and extend this method to set it; PostgREST errors with PGRST204 if the client
  /// sends a column that does not exist.
  static Future<String?> replaceSubtaskAttachments({
    required String subtaskId,
    required List<({String? content, String? description})> rows,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final sid = subtaskId.trim();
    if (sid.isEmpty) return 'Missing sub-task id';
    try {
      final supabase = Supabase.instance.client;
      await supabase.from('subtask_attachment').delete().eq('subtask_id', sid);
      for (final r in rows) {
        final c = r.content?.trim() ?? '';
        final d = r.description?.trim() ?? '';
        if (c.isEmpty && d.isEmpty) continue;
        final map = <String, dynamic>{
          'subtask_id': sid,
          'content': c.isEmpty ? null : c,
          'description': d.isEmpty ? null : d,
        };
        await supabase.from('subtask_attachment').insert(map);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  @Deprecated('Use replaceSubtaskAttachments')
  static Future<String?> upsertSubtaskAttachmentContent({
    required String subtaskId,
    required String content,
  }) async {
    return replaceSubtaskAttachments(
      subtaskId: subtaskId,
      rows: [(content: content, description: null)],
    );
  }

  /// First hyperlink only (legacy).
  static Future<String?> fetchSubtaskAttachmentContent(String subtaskId) async {
    try {
      final rows = await fetchSubtaskAttachments(subtaskId);
      for (final r in rows) {
        final c = r.content?.trim();
        if (c != null && c.isNotEmpty) return c;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<({String? error, String? commentId})> insertSubtaskCommentRow({
    required String subtaskId,
    required String description,
    String status = 'Active',
    String? creatorStaffLookupKey,
  }) async {
    if (!_enabled) return (error: 'Supabase not configured', commentId: null);
    final d = description.trim();
    if (d.isEmpty) return (error: null, commentId: null);
    try {
      final map = <String, dynamic>{
        'subtask_id': subtaskId,
        'description': d,
        'status': status.trim().isEmpty ? 'Active' : status.trim(),
        'create_date': HkTime.timestampForDb(),
      };
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
        }
      }
      final res = await Supabase.instance.client
          .from('subtask_comment')
          .insert(map)
          .select('id')
          .maybeSingle();
      return (error: null, commentId: res?['id']?.toString());
    } catch (e) {
      return (error: e.toString(), commentId: null);
    }
  }

  static Future<String?> updateSubtaskCommentRow({
    required String commentId,
    required String description,
    String? updaterStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final d = description.trim();
    if (d.isEmpty) return 'Comment is empty';
    try {
      final map = <String, dynamic>{
        'description': d,
        'update_date': HkTime.timestampForDb(),
      };
      final lookup = updaterStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
        }
      }
      await Supabase.instance.client
          .from('subtask_comment')
          .update(map)
          .eq('id', commentId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> softDeleteSubtaskCommentRow({
    required String commentId,
    String? updaterStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    try {
      final map = <String, dynamic>{
        'status': 'Deleted',
        'update_date': HkTime.timestampForDb(),
      };
      final lookup = updaterStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
        }
      }
      await Supabase.instance.client
          .from('subtask_comment')
          .update(map)
          .eq('id', commentId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<List<SubtaskCommentRowDisplay>> fetchSubtaskComments(
    String subtaskId,
  ) async {
    if (!_enabled) return [];
    try {
      final res = await Supabase.instance.client
          .from('subtask_comment')
          .select()
          .eq('subtask_id', subtaskId);
      final rows = <Map<String, dynamic>>[];
      for (final raw in (res as List)) {
        rows.add(Map<String, dynamic>.from(raw as Map));
      }
      final idSet = <String>{};
      for (final r in rows) {
        final cb = r['create_by']?.toString().trim();
        if (cb != null && cb.isNotEmpty) idSet.add(cb);
      }
      final names = <String, String>{};
      for (final id in idSet) {
        names[id] = await staffDisplayNameForKey(id);
      }
      final out = <SubtaskCommentRowDisplay>[];
      for (final r in rows) {
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final cb = r['create_by']?.toString().trim();
        final name = (cb != null && cb.isNotEmpty) ? (names[cb] ?? cb) : '—';
        final statusStr = r['status']?.toString() ?? '';
        out.add(
          SubtaskCommentRowDisplay(
            id: id,
            description: r['description']?.toString() ?? '',
            status: statusStr,
            createByStaffId: cb,
            displayStaffName: name,
            createTimestampUtc: _parseDateTimeNullable(r['create_date']),
            updateTimestampUtc: _parseDateTimeNullable(r['update_date']),
          ),
        );
      }
      out.sort((a, b) {
        if (a.isDeleted != b.isDeleted) {
          return a.isDeleted ? 1 : -1;
        }
        final ac =
            a.createTimestampUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bc =
            b.createTimestampUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bc.compareTo(ac);
      });
      return out;
    } catch (_) {
      return [];
    }
  }
}
