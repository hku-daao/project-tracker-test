import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/assignee.dart';
import '../models/singular_comment.dart';
import '../models/singular_subtask.dart';
import '../models/staff_for_assignment.dart';
import '../models/calendar_holiday.dart';
import '../models/project_record.dart';
import '../models/task.dart';
import '../models/team.dart';
import '../utils/hk_time.dart';
import 'task_fetch_visibility.dart';

class FileAttachmentRow {
  const FileAttachmentRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.url,
    this.storagePath,
    this.filename,
    this.description,
    this.mimeType,
    this.fileSizeBytes,
    this.createdBy,
    this.createdAt,
    this.sortOrder = 0,
    this.status = 'Active',
  });

  final String id;
  final String entityType;
  final String entityId;
  final String url;
  final String? storagePath;
  final String? filename;
  final String? description;
  final String? mimeType;
  final int? fileSizeBytes;
  final String? createdBy;
  final DateTime? createdAt;
  final int sortOrder;
  final String status;
}

class UrlAttachmentRow {
  const UrlAttachmentRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.url,
    required this.label,
    this.createdBy,
    this.createdAt,
    this.sortOrder = 0,
    this.status = 'Active',
  });

  final String id;
  final String entityType;
  final String entityId;
  final String url;
  final String label;
  final String? createdBy;
  final DateTime? createdAt;
  final int sortOrder;
  final String status;
}

class InlineAttachmentRow {
  const InlineAttachmentRow({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.url,
    this.description,
    this.mimeType,
    this.createdBy,
    this.createdAt,
    this.sortOrder = 0,
    this.status = 'Active',
  });

  final String id;
  final String entityType;
  final String entityId;
  final String url;
  final String? description;
  final String? mimeType;
  final String? createdBy;
  final DateTime? createdAt;
  final int sortOrder;
  final String status;
}

class TasksLoadResult {
  final List<Task> tasks;

  const TasksLoadResult({required this.tasks});

  static const empty = TasksLoadResult(tasks: []);
}

class SupabaseService {
  static bool get _enabled => SupabaseConfig.isConfigured;

  /// Coalesces concurrent [fetchSubtasksForTask] calls for the same parent task id so landing
  /// prefetch, many [TaskListCard]s, and [SingularTaskDetailView] do not stampede Supabase.
  static final Map<String, Future<List<SingularSubtask>>>
  _fetchSubtasksInflight = {};

  /// Short-lived list cache filled by landing batch prefetch and single-task loads; avoids duplicate
  /// HTTP when many [TaskListCard]s mount after prefetch. Cleared when the singular task set changes.
  static final Map<String, List<SingularSubtask>> _subtaskListMemoryCache = {};

  static Future<String?> insertAiAssistantAuditLog({
    required String entityType,
    String? entityId,
    String? staffId,
    String? staffDisplayName,
    required String actionType,
    required String userPrompt,
    required Map<String, dynamic> aiResponse,
    required Map<String, dynamic> fieldSuggestions,
  }) async {
    if (!_enabled) return null;
    try {
      final row = await Supabase.instance.client
          .from('ai_assistant_audit_logs')
          .insert({
            'staff_id': staffId,
            'staff_display_name': staffDisplayName,
            'entity_type': entityType,
            'entity_id': entityId,
            'action_type': actionType,
            'user_prompt': userPrompt,
            'ai_response': aiResponse,
            'field_suggestions': fieldSuggestions,
          })
          .select('id')
          .maybeSingle();
      return row?['id']?.toString();
    } catch (e) {
      debugPrint('AI audit insert failed: $e');
      return null;
    }
  }

  static Future<void> updateAiAssistantAuditSuggestions({
    required String auditLogId,
    required Map<String, dynamic> fieldSuggestions,
  }) async {
    if (!_enabled || auditLogId.trim().isEmpty) return;
    try {
      await Supabase.instance.client
          .from('ai_assistant_audit_logs')
          .update({'field_suggestions': fieldSuggestions})
          .eq('id', auditLogId.trim());
    } catch (e) {
      debugPrint('AI audit update failed: $e');
    }
  }

  static Future<void> updateAiAssistantAuditEntityId({
    required String auditLogId,
    required String entityId,
  }) async {
    if (!_enabled || auditLogId.trim().isEmpty || entityId.trim().isEmpty) {
      return;
    }
    try {
      await Supabase.instance.client
          .from('ai_assistant_audit_logs')
          .update({'entity_id': entityId.trim()})
          .eq('id', auditLogId.trim());
    } catch (e) {
      debugPrint('AI audit entity update failed: $e');
    }
  }

  /// Clears [_subtaskListMemoryCache] (e.g. when [AppState] singular task ids change).
  static void clearSubtaskListMemoryCache() => _subtaskListMemoryCache.clear();

  /// Optional listeners when [invalidateSubtasksCacheForTask] runs so list cards can reload without a full screen refresh.
  static final List<void Function(String taskId)>
  _subtaskCacheInvalidateListeners = [];

  static void addSubtaskCacheInvalidateListener(
    void Function(String taskId) listener,
  ) {
    if (!_subtaskCacheInvalidateListeners.contains(listener)) {
      _subtaskCacheInvalidateListeners.add(listener);
    }
  }

  static void removeSubtaskCacheInvalidateListener(
    void Function(String taskId) listener,
  ) {
    _subtaskCacheInvalidateListeners.remove(listener);
  }

  /// Whether [fetchSubtasksForTask] would read from [_subtaskListMemoryCache] without a network round-trip.
  static bool hasSubtaskListCached(String taskId) {
    final tid = taskId.trim();
    if (tid.isEmpty) return false;
    return _subtaskListMemoryCache.containsKey(tid);
  }

  /// Drops the cached sub-task list for [taskId] so the next [fetchSubtasksForTask] loads from the server.
  static void invalidateSubtasksCacheForTask(String taskId) {
    final tid = taskId.trim();
    if (tid.isEmpty) return;
    _subtaskListMemoryCache.remove(tid);
    for (final f in List<void Function(String)>.from(
      _subtaskCacheInvalidateListeners,
    )) {
      f(tid);
    }
  }

  static Future<void> _invalidateSubtasksCacheForSubtaskId(
    String subtaskId,
  ) async {
    final sid = subtaskId.trim();
    if (!_enabled || sid.isEmpty) return;
    try {
      final row = await Supabase.instance.client
          .from('subtask')
          .select('task_id')
          .eq('id', sid)
          .maybeSingle();
      final taskId = row?['task_id']?.toString().trim();
      if (taskId != null && taskId.isNotEmpty) {
        invalidateSubtasksCacheForTask(taskId);
      }
    } catch (_) {}
  }

  static void _storeSubtaskListMemoryCache(
    String tid,
    List<SingularSubtask> list,
  ) {
    _subtaskListMemoryCache[tid] = List<SingularSubtask>.from(list);
  }

  static void _sortSingularSubtasksNewestFirst(List<SingularSubtask> out) {
    sortSingularSubtasksNewestFirstInPlace(out);
  }

  /// Same ordering as landing cards / task detail sub-task lists.
  static void sortSingularSubtasksNewestFirstInPlace(
    List<SingularSubtask> out,
  ) {
    out.sort((a, b) {
      final ca = a.createDate;
      final cb = b.createDate;
      if (ca == null && cb == null) {
        return b.subtaskName.toLowerCase().compareTo(
          a.subtaskName.toLowerCase(),
        );
      }
      if (ca == null) return 1;
      if (cb == null) return -1;
      final c = cb.compareTo(ca);
      if (c != 0) return c;
      return b.subtaskName.toLowerCase().compareTo(a.subtaskName.toLowerCase());
    });
  }

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

  /// Status strings on singular [`task`] (e.g. Incomplete, Completed).
  static TaskStatus _taskStatusFromSingularTaskDb(String? s) {
    final t = s?.trim().toLowerCase() ?? '';
    if (t == 'done' || t == 'completed' || t == 'complete') {
      return TaskStatus.done;
    }
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
      final pid = row['project_id']?.toString().trim();
      Map<String, ({String name, String description})>? summaries;
      if (pid != null && pid.isNotEmpty) {
        summaries = await fetchProjectSummariesByIds({pid});
      }
      return _taskFromSingularTaskRow(
        row,
        staffUuidToAppId,
        teamUuidToAppId,
        staffUuidToName,
        projectSummaries: summaries,
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

    /// Sets or clears `task.project_id`.
    String? projectId,
    bool clearProjectId = false,
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
        map['completion_date'] = HkTime.timestampForDbFromStoredUtc(
          completionDateAt.toUtc(),
        );
      }
      if (stampSubmitDateNow) {
        map['submit_date'] = HkTime.timestampForDb();
      }
      if (clearProjectId) {
        map['project_id'] = null;
      } else {
        final p = projectId?.trim();
        if (p != null && p.isNotEmpty) {
          map['project_id'] = p;
        }
      }
      if (map.isEmpty) return null;
      await Supabase.instance.client.from('task').update(map).eq('id', taskId);
      if (map.containsKey('update_date')) {
        final projectTouchError = await _touchTaskProjectFromTaskRow(taskId);
        if (projectTouchError != null) return projectTouchError;
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> _touchTaskProjectFromTaskRow(String taskId) async {
    final id = taskId.trim();
    if (!_enabled || id.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('task')
          .select('project_id,update_by,update_date,last_updated')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      final m = Map<String, dynamic>.from(row as Map);
      final projectId = m['project_id']?.toString().trim();
      final updateAt = m['last_updated'] ?? m['update_date'];
      if (projectId == null || projectId.isEmpty || updateAt == null) {
        return null;
      }
      final projectMap = <String, dynamic>{'update_date': updateAt};
      final updateBy = m['update_by']?.toString().trim();
      if (updateBy != null && updateBy.isNotEmpty) {
        projectMap['update_by'] = updateBy;
      }
      await Supabase.instance.client
          .from('project')
          .update(projectMap)
          .eq('id', projectId);
      return null;
    } catch (e) {
      return 'Task saved, but project audit sync failed: $e';
    }
  }

  static Future<String?> _touchProjectFromSubtaskRow(String subtaskId) async {
    final id = subtaskId.trim();
    if (!_enabled || id.isEmpty) return null;
    try {
      final row = await Supabase.instance.client
          .from('subtask')
          .select('task_id,update_by,update_date,last_updated')
          .eq('id', id)
          .maybeSingle();
      if (row == null) return null;
      final m = Map<String, dynamic>.from(row as Map);
      final taskId = m['task_id']?.toString().trim();
      final updateAt = m['last_updated'] ?? m['update_date'];
      if (taskId == null || taskId.isEmpty || updateAt == null) {
        return null;
      }

      final taskRow = await Supabase.instance.client
          .from('task')
          .select('project_id')
          .eq('id', taskId)
          .maybeSingle();
      if (taskRow == null) return null;
      final taskMap = Map<String, dynamic>.from(taskRow as Map);
      final projectId = taskMap['project_id']?.toString().trim();
      if (projectId == null || projectId.isEmpty) return null;

      final projectMap = <String, dynamic>{'update_date': updateAt};
      final updateBy = m['update_by']?.toString().trim();
      if (updateBy != null && updateBy.isNotEmpty) {
        projectMap['update_by'] = updateBy;
      }
      await Supabase.instance.client
          .from('project')
          .update(projectMap)
          .eq('id', projectId);
      return null;
    } catch (e) {
      return 'Sub-task saved, but project audit sync failed: $e';
    }
  }

  /// When the parent [task] is marked Deleted, set every non-deleted [subtask] under it to Deleted.
  static Future<String?> markSubtasksDeletedForParentTask({
    required String taskId,
    String? updateByStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final tid = taskId.trim();
    if (tid.isEmpty) return 'task id required';
    try {
      final rows = await _fetchSubtaskRawRowsForTask(tid);
      final map = <String, dynamic>{
        'status': 'Deleted',
        'update_date': HkTime.timestampForDb(),
      };
      final lookup = updateByStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
        }
      }
      for (final row in rows) {
        if (!_subtaskRowStatusNotDeleted(row)) continue;
        final sid = row['id']?.toString().trim();
        if (sid == null || sid.isEmpty) continue;
        await Supabase.instance.client
            .from('subtask')
            .update(map)
            .eq('id', sid);
      }
      invalidateSubtasksCacheForTask(tid);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<List<FileAttachmentRow>> fetchFileAttachments({
    required String entityType,
    required String entityId,
  }) async {
    if (!_enabled) return [];
    final type = entityType.trim();
    final id = entityId.trim();
    if (type.isEmpty || id.isEmpty) return [];
    final res = await Supabase.instance.client
        .from('file_attachment')
        .select(
          'id,entity_type,entity_id,url,storage_path,filename,description,mime_type,file_size_bytes,created_by,created_at,sort_order,status',
        )
        .eq('entity_type', type)
        .eq('entity_id', id)
        .eq('status', 'Active')
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    final out = <FileAttachmentRow>[];
    for (final raw in (res as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      final rowId = m['id']?.toString().trim() ?? '';
      final url = m['url']?.toString().trim() ?? '';
      if (rowId.isEmpty || url.isEmpty) continue;
      out.add(
        FileAttachmentRow(
          id: rowId,
          entityType: m['entity_type']?.toString().trim() ?? type,
          entityId: m['entity_id']?.toString().trim() ?? id,
          url: url,
          storagePath: m['storage_path']?.toString(),
          filename: m['filename']?.toString(),
          description: m['description']?.toString(),
          mimeType: m['mime_type']?.toString(),
          fileSizeBytes: _flexIntFromRow(m['file_size_bytes']),
          createdBy: m['created_by']?.toString(),
          createdAt: _parseDateTimeNullable(m['created_at']),
          sortOrder: _flexIntFromRow(m['sort_order']),
          status: m['status']?.toString().trim().isNotEmpty == true
              ? m['status'].toString().trim()
              : 'Active',
        ),
      );
    }
    return out;
  }

  static Future<List<UrlAttachmentRow>> fetchUrlAttachments({
    required String entityType,
    required String entityId,
  }) async {
    if (!_enabled) return [];
    final type = entityType.trim();
    final id = entityId.trim();
    if (type.isEmpty || id.isEmpty) return [];
    final res = await Supabase.instance.client
        .from('url_attachment')
        .select(
          'id,entity_type,entity_id,url,label,created_by,created_at,sort_order,status',
        )
        .eq('entity_type', type)
        .eq('entity_id', id)
        .eq('status', 'Active')
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);
    final out = <UrlAttachmentRow>[];
    for (final raw in (res as List)) {
      final m = Map<String, dynamic>.from(raw as Map);
      final rowId = m['id']?.toString().trim() ?? '';
      final url = m['url']?.toString().trim() ?? '';
      final label = m['label']?.toString().trim() ?? '';
      if (rowId.isEmpty || url.isEmpty) continue;
      out.add(
        UrlAttachmentRow(
          id: rowId,
          entityType: m['entity_type']?.toString().trim() ?? type,
          entityId: m['entity_id']?.toString().trim() ?? id,
          url: url,
          label: label.isEmpty ? url : label,
          createdBy: m['created_by']?.toString(),
          createdAt: _parseDateTimeNullable(m['created_at']),
          sortOrder: _flexIntFromRow(m['sort_order']),
          status: m['status']?.toString().trim().isNotEmpty == true
              ? m['status'].toString().trim()
              : 'Active',
        ),
      );
    }
    return out;
  }

  static Future<String?> replaceFileAttachments({
    required String entityType,
    required String entityId,
    required List<
      ({String? id, String? url, String? filename, String? description})
    >
    rows,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final type = entityType.trim();
    final id = entityId.trim();
    if (type.isEmpty || id.isEmpty) return 'Missing attachment owner';
    try {
      final supabase = Supabase.instance.client;
      final existing = await supabase
          .from('file_attachment')
          .select('id')
          .eq('entity_type', type)
          .eq('entity_id', id)
          .eq('status', 'Active');
      final existingIds = (existing as List)
          .map((row) => (row as Map)['id']?.toString().trim() ?? '')
          .where((rowId) => rowId.isNotEmpty)
          .toSet();
      final keptIds = <String>{};
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final url = r.url?.trim() ?? '';
        if (url.isEmpty) continue;
        final rowId = r.id?.trim() ?? '';
        final filename = r.filename?.trim();
        final description = r.description?.trim();
        final payload = {
          'entity_type': type,
          'entity_id': id,
          'url': url,
          if (filename != null && filename.isNotEmpty) 'filename': filename,
          if (description != null && description.isNotEmpty)
            'description': description,
          'sort_order': i,
          'status': 'Active',
        };
        if (rowId.isNotEmpty) {
          keptIds.add(rowId);
          await supabase
              .from('file_attachment')
              .update(payload)
              .eq('id', rowId);
        } else {
          await supabase.from('file_attachment').insert(payload);
        }
      }
      final deleteIds = existingIds.difference(keptIds).toList();
      if (deleteIds.isNotEmpty) {
        await supabase
            .from('file_attachment')
            .update({'status': 'Deleted'})
            .inFilter('id', deleteIds);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> deleteFileAttachmentById(String attachmentId) async {
    if (!_enabled) return 'Supabase not configured';
    final id = attachmentId.trim();
    if (id.isEmpty) return 'Missing attachment id';
    try {
      await Supabase.instance.client
          .from('file_attachment')
          .update({'status': 'Deleted'})
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> replaceUrlAttachments({
    required String entityType,
    required String entityId,
    required List<({String? id, String? url, String? label})> rows,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final type = entityType.trim();
    final id = entityId.trim();
    if (type.isEmpty || id.isEmpty) return 'Missing attachment owner';
    try {
      final supabase = Supabase.instance.client;
      final existing = await supabase
          .from('url_attachment')
          .select('id')
          .eq('entity_type', type)
          .eq('entity_id', id)
          .eq('status', 'Active');
      final existingIds = (existing as List)
          .map((row) => (row as Map)['id']?.toString().trim() ?? '')
          .where((rowId) => rowId.isNotEmpty)
          .toSet();
      final keptIds = <String>{};
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final url = r.url?.trim() ?? '';
        if (url.isEmpty) continue;
        final rowId = r.id?.trim() ?? '';
        final label = r.label?.trim();
        final payload = {
          'entity_type': type,
          'entity_id': id,
          'url': url,
          'label': label == null || label.isEmpty ? url : label,
          'sort_order': i,
          'status': 'Active',
        };
        if (rowId.isNotEmpty) {
          keptIds.add(rowId);
          await supabase.from('url_attachment').update(payload).eq('id', rowId);
        } else {
          await supabase.from('url_attachment').insert(payload);
        }
      }
      final deleteIds = existingIds.difference(keptIds).toList();
      if (deleteIds.isNotEmpty) {
        await supabase
            .from('url_attachment')
            .update({'status': 'Deleted'})
            .inFilter('id', deleteIds);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<String?> deleteUrlAttachmentById(String attachmentId) async {
    if (!_enabled) return 'Supabase not configured';
    final id = attachmentId.trim();
    if (id.isEmpty) return 'Missing attachment id';
    try {
      await Supabase.instance.client
          .from('url_attachment')
          .update({'status': 'Deleted'})
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<List<InlineAttachmentRow>> fetchInlineAttachments({
    required String entityType,
    required String entityId,
  }) async {
    if (!_enabled) return [];
    final type = entityType.trim();
    final id = entityId.trim();
    if (type.isEmpty || id.isEmpty) return [];
    try {
      final res = await Supabase.instance.client
          .from('inline_attachment')
          .select(
            'id,entity_type,entity_id,url,description,mime_type,created_by,created_at,sort_order,status',
          )
          .eq('entity_type', type)
          .eq('entity_id', id)
          .eq('status', 'Active')
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      final out = <InlineAttachmentRow>[];
      for (final raw in (res as List)) {
        final m = Map<String, dynamic>.from(raw as Map);
        final rowId = m['id']?.toString().trim() ?? '';
        final url = m['url']?.toString().trim() ?? '';
        if (rowId.isEmpty || url.isEmpty) continue;
        out.add(
          InlineAttachmentRow(
            id: rowId,
            entityType: m['entity_type']?.toString().trim() ?? type,
            entityId: m['entity_id']?.toString().trim() ?? id,
            url: url,
            description: m['description']?.toString(),
            mimeType: m['mime_type']?.toString(),
            createdBy: m['created_by']?.toString(),
            createdAt: _parseDateTimeNullable(m['created_at']),
            sortOrder: _flexIntFromRow(m['sort_order']),
            status: m['status']?.toString().trim().isNotEmpty == true
                ? m['status'].toString().trim()
                : 'Active',
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('fetchInlineAttachments: $e');
      return [];
    }
  }

  static Future<String?> markInlineAttachmentDeleted(
    String inlineAttachmentId,
  ) async {
    if (!_enabled) return 'Supabase not configured';
    final id = inlineAttachmentId.trim();
    if (id.isEmpty) return 'inline attachment id is required';
    try {
      await Supabase.instance.client
          .from('inline_attachment')
          .update({'status': 'Deleted'})
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<({String? error, String? inlineAttachmentId})>
  insertInlineAttachment({
    required String entityType,
    required String entityId,
    required String url,
    String? description,
    String? mimeType,
    String? creatorStaffLookupKey,
    int sortOrder = 0,
  }) async {
    if (!_enabled) {
      return (error: 'Supabase not configured', inlineAttachmentId: null);
    }
    final type = entityType.trim();
    final id = entityId.trim();
    final link = url.trim();
    if (type.isEmpty) {
      return (error: 'entity_type is required', inlineAttachmentId: null);
    }
    if (id.isEmpty) {
      return (error: 'entity_id is required', inlineAttachmentId: null);
    }
    if (link.isEmpty) {
      return (error: 'url is required', inlineAttachmentId: null);
    }
    try {
      final map = <String, dynamic>{
        'entity_type': type,
        'entity_id': id,
        'url': link,
        'sort_order': sortOrder,
      };
      final desc = description?.trim();
      if (desc != null && desc.isNotEmpty) map['description'] = desc;
      final mt = mimeType?.trim();
      if (mt != null && mt.isNotEmpty) map['mime_type'] = mt;
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['created_by'] = staffId;
        }
      }
      final res = await Supabase.instance.client
          .from('inline_attachment')
          .insert(map)
          .select('id')
          .maybeSingle();
      return (error: null, inlineAttachmentId: res?['id']?.toString());
    } catch (e) {
      return (error: e.toString(), inlineAttachmentId: null);
    }
  }

  static int _priorityFromFlexible(dynamic p) {
    if (p is num) return p.toInt().clamp(1, 2);
    final s = p?.toString().trim().toLowerCase() ?? '';
    if (s.contains('urgent') || s == '2') return 2;
    return 1;
  }

  /// Avoid `as num?` on PostgREST values (often [String] or [int]) — casts throw and
  /// empty the whole [fetchTasksFromSupabase] result.
  static int _flexIntFromRow(dynamic v, {int fallback = 0}) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return int.tryParse(v.toString().trim()) ?? fallback;
  }

  /// Maps a row from singular [`task`] (task_name, assignee_01…) into [Task].
  /// Includes rows with status `Deleted` for the Deleted tab.
  static Task? _taskFromSingularTaskRow(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToAppId,
    Map<String, String> teamUuidToAppId,
    Map<String, String> staffUuidToName, {
    Map<String, ({String name, String description})>? projectSummaries,
  }) {
    final id = row['id']?.toString() ?? row['task_id']?.toString();
    if (id == null || id.isEmpty) return null;
    final statusRaw = _dbStatusRawFromRow(row['status']);

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

    final pidRaw = row['project_id']?.toString().trim();
    final String? projectId = (pidRaw != null && pidRaw.isNotEmpty)
        ? pidRaw
        : null;
    String? projectName;
    String? projectDescription;
    if (projectId != null && projectSummaries != null) {
      final m = projectSummaries[projectId];
      if (m != null) {
        projectName = m.name;
        projectDescription = m.description;
      }
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
      status: _taskStatusFromSingularTaskDb(
        statusRaw.isEmpty ? null : statusRaw,
      ),
      progressPercent: _flexIntFromRow(row['progress_percent']),
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
      lastUpdated: _parseDateTimeNullable(row['last_updated']),
      submission: _submissionFromRow(row['submission']),
      submitDate: _parseDateTimeNullable(row['submit_date']),
      completionDate: _parseDateTimeNullable(row['completion_date']),
      changeDueReason: _nullableTrimmedString(row['change_due_reason']),
      overdueDay: _flexIntFromRow(row['overdue_day']),
      overdue: _overdueYnFromRow(row['overdue']),
      projectId: projectId,
      projectName: projectName,
      projectDescription: projectDescription,
    );
  }

  /// Loads `project.name` / `project.description` for singular-task rows.
  static Future<Map<String, ({String name, String description})>>
  fetchProjectSummariesByIds(Set<String> ids) async {
    final out = <String, ({String name, String description})>{};
    if (!_enabled || ids.isEmpty) return out;
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (clean.isEmpty) return out;
    try {
      final res = await Supabase.instance.client
          .from('project')
          .select('id,name,description')
          .inFilter('id', clean.toList());
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        final name = row['name']?.toString() ?? '';
        final desc = row['description']?.toString() ?? '';
        out[id] = (name: name, description: desc);
      }
    } catch (_) {}
    return out;
  }

  static ProjectRecord? _projectRecordFromMaps(
    Map<String, dynamic> row,
    Map<String, String> staffUuidToAppId,
    Map<String, String> staffUuidToName,
  ) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return null;
    final assignees = <String>[];
    final assigneeNames = <String>[];
    for (var i = 1; i <= 20; i++) {
      final key = 'assignee_${i.toString().padLeft(2, '0')}';
      final v = row[key]?.toString().trim();
      if (v != null && v.isNotEmpty) {
        assignees.add(v);
        final name = staffUuidToName[v]?.trim();
        if (name != null && name.isNotEmpty) {
          assigneeNames.add(name);
        } else {
          final appId = staffUuidToAppId[v]?.trim();
          assigneeNames.add(appId != null && appId.isNotEmpty ? appId : v);
        }
      }
    }
    final picUuids = <String>[];
    final picNames = <String>[];
    for (var i = 1; i <= 20; i++) {
      final key = 'pic_${i.toString().padLeft(2, '0')}';
      final v = row[key]?.toString().trim();
      if (v != null && v.isNotEmpty) {
        picUuids.add(v);
        final name = staffUuidToName[v]?.trim();
        if (name != null && name.isNotEmpty) {
          picNames.add(name);
        } else {
          final appId = staffUuidToAppId[v]?.trim();
          picNames.add(appId != null && appId.isNotEmpty ? appId : v);
        }
      }
    }
    final cb = row['create_by']?.toString().trim();
    final ub = row['update_by']?.toString().trim();
    return ProjectRecord(
      id: id,
      name: row['name'] as String? ?? '',
      assigneeStaffUuids: assignees,
      assigneeStaffDisplayNames: assigneeNames,
      picStaffUuids: picUuids,
      picStaffDisplayNames: picNames,
      description: row['description'] as String? ?? '',
      startDate: _parseDate(row['start_date']),
      endDate: _parseDate(row['end_date']),
      status: row['status'] as String? ?? 'Not started',
      createByStaffUuid: cb?.isNotEmpty == true ? cb : null,
      createByDisplayName: cb != null && cb.isNotEmpty
          ? (staffUuidToName[cb] ?? cb)
          : null,
      createDate: _parseDateTimeNullable(row['create_date']),
      updateByStaffUuid: ub?.isNotEmpty == true ? ub : null,
      updateByDisplayName: ub != null && ub.isNotEmpty
          ? (staffUuidToName[ub] ?? ub)
          : null,
      updateDate: _parseDateTimeNullable(row['update_date']),
    );
  }

  /// All [`project`] rows visible under RLS, newest first.
  static Future<List<ProjectRecord>> fetchAllProjectsFromSupabase() async {
    if (!_enabled) return [];
    try {
      Map<String, String> staffUuidToAppId = {};
      Map<String, String> staffUuidToName = {};
      try {
        final maps = await _loadMaps();
        staffUuidToAppId = maps?.staffUuidToAppId ?? {};
        staffUuidToName = maps?.staffUuidToName ?? {};
      } catch (_) {}
      final res = await Supabase.instance.client
          .from('project')
          .select()
          .order('create_date', ascending: false);
      final out = <ProjectRecord>[];
      for (final raw in (res as List)) {
        final r = _projectRecordFromMaps(
          Map<String, dynamic>.from(raw as Map),
          staffUuidToAppId,
          staffUuidToName,
        );
        if (r != null) out.add(r);
      }
      return out;
    } catch (e) {
      debugPrint('fetchAllProjectsFromSupabase: $e');
      return [];
    }
  }

  /// HKU / HK rows in [calendar_holiday] for date pickers (inclusive date bounds).
  static Future<List<CalendarHoliday>> fetchCalendarHolidaysBetween(
    DateTime fromInclusive,
    DateTime toInclusive,
  ) async {
    if (!_enabled) return const [];
    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    try {
      final res = await Supabase.instance.client
          .from('calendar_holiday')
          .select('holiday_type,name,holiday_date,full_or_pm')
          .gte('holiday_date', ymd(fromInclusive))
          .lte('holiday_date', ymd(toInclusive))
          .order('holiday_date', ascending: true);
      final list = res as List;
      return list
          .map(
            (raw) =>
                CalendarHoliday.fromMap(Map<String, dynamic>.from(raw as Map)),
          )
          .toList();
    } catch (e) {
      debugPrint('fetchCalendarHolidaysBetween: $e');
      return const [];
    }
  }

  static Future<ProjectRecord?> fetchProjectById(String projectId) async {
    if (!_enabled) return null;
    final id = projectId.trim();
    if (id.isEmpty) return null;
    try {
      Map<String, String> staffUuidToAppId = {};
      Map<String, String> staffUuidToName = {};
      try {
        final maps = await _loadMaps();
        staffUuidToAppId = maps?.staffUuidToAppId ?? {};
        staffUuidToName = maps?.staffUuidToName ?? {};
      } catch (_) {}
      final res = await Supabase.instance.client
          .from('project')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (res == null) return null;
      return _projectRecordFromMaps(
        Map<String, dynamic>.from(res as Map),
        staffUuidToAppId,
        staffUuidToName,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<Task>> fetchSingularTasksForProject(
    String projectId,
  ) async {
    if (!_enabled) return [];
    final pid = projectId.trim();
    if (pid.isEmpty) return [];
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
      final res = await Supabase.instance.client
          .from('task')
          .select()
          .eq('project_id', pid);
      final summaries = await fetchProjectSummariesByIds({pid});
      final out = <Task>[];
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final t = _taskFromSingularTaskRow(
          row,
          staffUuidToAppId,
          teamUuidToAppId,
          staffUuidToName,
          projectSummaries: summaries,
        );
        if (t != null) out.add(t);
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Inserts [`project`] row; [assignees] are `staff.id` uuid strings (up to 20).
  static Future<({String? error, String? projectId})> insertProjectRow({
    required String name,
    List<String?> assignees = const [],

    /// [`staff.id`] uuids; persisted in `project.pic_01` ... `pic_20`.
    List<String> picStaffUuids = const [],
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String status = 'Not started',
    String? creatorStaffLookupKey,
  }) async {
    if (!_enabled) return (error: 'Supabase not configured', projectId: null);
    final n = name.trim();
    if (n.isEmpty) return (error: 'Project name is required', projectId: null);
    try {
      var padded = List<String?>.from(assignees);
      while (padded.length < 20) {
        padded.add(null);
      }
      if (padded.length > 20) padded = padded.sublist(0, 20);
      final picPadded = List<String?>.from(picStaffUuids);
      while (picPadded.length < 20) {
        picPadded.add(null);
      }
      if (picPadded.length > 20) picPadded.removeRange(20, picPadded.length);
      final now = HkTime.timestampForDb();
      final map = <String, dynamic>{
        'name': n,
        'description': description?.trim() ?? '',
        'status': status.trim().isEmpty ? 'Not started' : status.trim(),
        'create_date': now,
        'update_date': now,
      };
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
          map['update_by'] = staffId;
        }
      }
      if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (endDate != null) {
        map['end_date'] = HkTime.dateOnlyHkMidnightForDb(endDate);
      }
      for (var i = 0; i < 20; i++) {
        final raw = padded[i]?.trim();
        if (raw != null && raw.isNotEmpty) {
          map['assignee_${(i + 1).toString().padLeft(2, '0')}'] = raw;
        }
      }
      for (var i = 0; i < 20; i++) {
        final raw = picPadded[i]?.trim();
        if (raw != null && raw.isNotEmpty) {
          map['pic_${(i + 1).toString().padLeft(2, '0')}'] = raw;
        }
      }
      final ins = await Supabase.instance.client
          .from('project')
          .insert(map)
          .select('id')
          .maybeSingle();
      final newId = ins?['id']?.toString();
      return (error: null, projectId: newId);
    } catch (e) {
      return (error: e.toString(), projectId: null);
    }
  }

  static Future<String?> updateProjectRow({
    required String projectId,
    String? name,
    String? description,
    List<String?>? assigneeSlots,

    /// When non-null, replaces `project.pic_01` ... `pic_20` (`staff.id` uuids).
    List<String>? picStaffUuids,
    DateTime? startDate,
    DateTime? endDate,
    bool clearStartDate = false,
    bool clearEndDate = false,
    String? status,
    String? updateByStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final map = <String, dynamic>{};
    try {
      if (name != null) map['name'] = name;
      if (description != null) map['description'] = description;
      if (assigneeSlots != null) {
        for (var i = 0; i < 20; i++) {
          final key = 'assignee_${(i + 1).toString().padLeft(2, '0')}';
          final v = i < assigneeSlots.length ? assigneeSlots[i]?.trim() : null;
          map[key] = (v == null || v.isEmpty) ? null : v;
        }
      }
      if (picStaffUuids != null) {
        for (var i = 0; i < 20; i++) {
          final key = 'pic_${(i + 1).toString().padLeft(2, '0')}';
          final v = i < picStaffUuids.length ? picStaffUuids[i].trim() : null;
          map[key] = (v == null || v.isEmpty) ? null : v;
        }
      }
      if (clearStartDate) {
        map['start_date'] = null;
      } else if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (clearEndDate) {
        map['end_date'] = null;
      } else if (endDate != null) {
        map['end_date'] = HkTime.dateOnlyHkMidnightForDb(endDate);
      }
      if (status != null) map['status'] = status;
      final lookup = updateByStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
          map['update_date'] = HkTime.timestampForDb();
        }
      }
      if (map.isEmpty) return null;
      await Supabase.instance.client
          .from('project')
          .update(map)
          .eq('id', projectId);
      return null;
    } catch (e, st) {
      debugPrint('PROJECT_UPDATE_ERROR projectId=$projectId payload=$map');
      debugPrint('PROJECT_UPDATE_ERROR exception=$e');
      debugPrint('PROJECT_UPDATE_ERROR stack=$st');
      return e.toString();
    }
  }

  /// Marks a [`project`] row as Deleted.
  static Future<String?> deleteProjectRow(String projectId) async {
    if (!_enabled) return 'Supabase not configured';
    final id = projectId.trim();
    if (id.isEmpty) return 'Invalid project';
    try {
      await Supabase.instance.client
          .from('project')
          .update({'status': 'Deleted'})
          .eq('id', id);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// DB stores `Yes` / `No` for singular task/subtask overdue flags.
  static String _overdueYnFromRow(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s == 'Yes' || s == 'No') return s;
    return 'No';
  }

  static String? _nullableTrimmedString(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty) return null;
    return s;
  }

  /// Pic/creator workflow values are typically `Pending` / `Submitted` / `Accepted` / `Returned`
  /// (any casing). Accepts String, enum-style JSON maps, and other dynamic SQL/PostgREST shapes
  /// so sub-task rows are not dropped by a failed `as String?` in [_singularSubtaskFromRow].
  static String? _submissionFromRow(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final s = v.trim();
      return s.isEmpty ? null : s;
    }
    if (v is Map) {
      final dynamic inner = v['value'] ?? v['Value'] ?? v['name'] ?? v['label'];
      if (inner != null) {
        final s = inner.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return s;
  }

  static bool _looksLikeUuid(String s) {
    final t = s.trim();
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(t);
  }

  /// Staff `id` (uuid) → `staff.app_id` for assignee/creator matching on project rows.
  static Future<Map<String, String>> fetchStaffUuidToAppIdMap() async {
    final m = await _loadMaps();
    return m?.staffUuidToAppId ?? {};
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
            staffUuid: id.isNotEmpty ? id : null,
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

  /// `staff.id` (uuid) for each `staff.app_id` in [appIds].
  static Future<List<String>> fetchStaffRowIdsForAppIds(
    List<String> appIds,
  ) async {
    if (!_enabled) return [];
    final ids = appIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (ids.isEmpty) return [];
    try {
      final res = await Supabase.instance.client
          .from('staff')
          .select('id')
          .inFilter('app_id', ids);
      final out = <String>[];
      for (final row in (res as List)) {
        final id = (row as Map)['id']?.toString().trim();
        if (id != null && id.isNotEmpty) out.add(id);
      }
      return out;
    } catch (e, st) {
      debugPrint('fetchStaffRowIdsForAppIds: $e\n$st');
      return [];
    }
  }

  /// Fills missing `staff.id` uuids (supervisor + subordinates) for scoped fetch.
  static Future<TaskFetchVisibility?> enrichTaskFetchVisibility(
    TaskFetchVisibility? visibility,
  ) async {
    if (visibility == null || !visibility.isConfigured) return visibility;

    var supUuid = visibility.supervisorStaffUuid?.trim();
    if (supUuid == null || supUuid.isEmpty) {
      final app = visibility.supervisorStaffAppId?.trim();
      if (app != null && app.isNotEmpty) {
        supUuid = await _staffRowIdForAssigneeKey(app);
      }
    }

    var subUuids = List<String>.from(visibility.subordinateStaffUuids);
    if (visibility.subordinateStaffAppIds.isNotEmpty) {
      final resolved = await fetchStaffRowIdsForAppIds(
        visibility.subordinateStaffAppIds,
      );
      final merged = <String>{
        ...subUuids.map((e) => e.trim()).where((e) => e.isNotEmpty),
        ...resolved,
      };
      subUuids = merged.toList();
    }

    return TaskFetchVisibility(
      supervisorStaffAppId: visibility.supervisorStaffAppId,
      supervisorStaffUuid: supUuid,
      subordinateStaffAppIds: visibility.subordinateStaffAppIds,
      subordinateStaffUuids: subUuids,
    );
  }

  /// Merges singular `task` rows visible to [visibility] (creator or assignee).
  static Future<List<Map<String, dynamic>>> _fetchSingularTaskRowsForVisibility(
    SupabaseClient supabase,
    TaskFetchVisibility visibility,
  ) async {
    final assigneeUuids = visibility.staffUuidsForAssigneeFilter.toList();
    final createByKeys = visibility.staffKeysForCreateByFilter.toList();
    if (assigneeUuids.isEmpty && createByKeys.isEmpty) return [];

    final byId = <String, Map<String, dynamic>>{};

    void absorb(dynamic res) {
      for (final raw in (res as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString() ?? row['task_id']?.toString();
        if (id != null && id.isNotEmpty) byId[id] = row;
      }
    }

    Future<void> runQuery(
      String label,
      Future<dynamic> Function() query,
    ) async {
      try {
        absorb(await query());
      } catch (e, st) {
        debugPrint('_fetchSingularTaskRowsForVisibility ($label): $e\n$st');
      }
    }

    final futures = <Future<void>>[];

    if (createByKeys.isNotEmpty) {
      futures.add(
        runQuery(
          'create_by',
          () => supabase
              .from('task')
              .select()
              .inFilter('create_by', createByKeys),
        ),
      );
    }

    if (assigneeUuids.isNotEmpty) {
      for (var i = 1; i <= 10; i++) {
        final col = 'assignee_${i.toString().padLeft(2, '0')}';
        futures.add(
          runQuery(
            col,
            () => supabase.from('task').select().inFilter(col, assigneeUuids),
          ),
        );
      }
    }

    await Future.wait(futures);

    final rows = byId.values.toList();
    rows.sort((a, b) {
      final ad = _parseDateTime(a['created_at'] ?? a['create_date']);
      final bd = _parseDateTime(b['created_at'] ?? b['create_date']);
      return bd.compareTo(ad);
    });
    debugPrint(
      '_fetchSingularTaskRowsForVisibility: ${rows.length} tasks '
      '(create_by keys=${createByKeys.length}, assignee uuids=${assigneeUuids.length})',
    );
    return rows;
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

  /// Loads tasks from Supabase.
  ///
  /// When [visibility] is set, only singular `task` rows are fetched where
  /// `create_by` or any `assignee_01`…`assignee_10` matches the supervisor or
  /// a subordinate (`staff.app_id` or `staff.id`). Legacy plural `tasks` is skipped.
  static Future<TasksLoadResult?> fetchTasksFromSupabase({
    TaskFetchVisibility? visibility,
  }) async {
    if (!_enabled) return null;
    try {
      visibility = await enrichTaskFetchVisibility(visibility);
      final scoped = visibility != null && visibility.isConfigured;

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
      final singularTasks = <Task>[];
      try {
        dynamic singularRes;
        if (scoped) {
          singularRes = await _fetchSingularTaskRowsForVisibility(
            supabase,
            visibility,
          );
        } else {
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
        }
        final singularRawRows = <Map<String, dynamic>>[];
        for (final raw in (singularRes as List)) {
          singularRawRows.add(Map<String, dynamic>.from(raw as Map));
        }
        final projectIds = <String>{};
        for (final row in singularRawRows) {
          final p = row['project_id']?.toString().trim();
          if (p != null && p.isNotEmpty) projectIds.add(p);
        }
        final projectSummaries = await fetchProjectSummariesByIds(projectIds);
        var parseFailures = 0;
        for (final row in singularRawRows) {
          try {
            final t = _taskFromSingularTaskRow(
              row,
              staffUuidToAppId,
              teamUuidToAppId,
              staffUuidToName,
              projectSummaries: projectSummaries.isEmpty
                  ? null
                  : projectSummaries,
            );
            if (t != null) {
              singularTasks.add(t);
            } else {
              parseFailures++;
              debugPrint(
                'fetchTasksFromSupabase: skipped singular row (no id): '
                'keys=${row.keys.take(8).join(",")}',
              );
            }
          } catch (e, st) {
            parseFailures++;
            debugPrint(
              'fetchTasksFromSupabase: singular row parse error: $e\n$st',
            );
          }
        }
        debugPrint(
          'fetchTasksFromSupabase: ${singularTasks.length}/${singularRawRows.length} '
          'singular rows parsed ($parseFailures skipped/failed)',
        );
      } catch (e, st) {
        debugPrint('fetchTasksFromSupabase singular `task` load: $e\n$st');
      }

      final merged = singularTasks.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      debugPrint(
        'fetchTasksFromSupabase: returning ${merged.length} tasks to AppState',
      );
      return TasksLoadResult(tasks: merged);
    } catch (e, st) {
      debugPrint('fetchTasksFromSupabase failed: $e\n$st');
      return TasksLoadResult.empty;
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

  /// Maps assignee keys (`staff.app_id` or `staff.id` uuid) to `staff.id`
  /// for `project.assignee_01` ... `project.assignee_20`.
  static Future<List<String?>> assigneeSlotsForProject(
    List<String> staffKeys,
  ) async {
    if (!_enabled) return List<String?>.filled(20, null);
    final out = <String?>[];
    for (final key in staffKeys.take(20)) {
      final id = await _staffRowIdForAssigneeKey(key);
      out.add(id);
    }
    while (out.length < 20) {
      out.add(null);
    }
    return out.take(20).toList();
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

  /// Public alias for permission checks (e.g. project creator).
  static Future<String?> resolveStaffRowIdForAssigneeKey(String key) =>
      _staffRowIdForAssigneeKey(key);

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

    /// Optional [`project.id`] (uuid).
    String? projectId,
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
      final now = HkTime.timestampForDb();
      final map = <String, dynamic>{
        'task_name': name,
        'priority': priority,
        'description': description,
        'status': s,
        'create_date': now,
        'update_date': now,
        'last_updated': now,
      };
      final p = projectId?.trim();
      if (p != null && p.isNotEmpty) {
        map['project_id'] = p;
      }
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
          map['update_by'] = staffId;
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
      if (id != null && id.trim().isNotEmpty) {
        final projectTouchError = await _touchTaskProjectFromTaskRow(id);
        if (projectTouchError != null) {
          return (error: projectTouchError, taskId: id);
        }
      }
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
      final id = const Uuid().v4();
      final map = <String, dynamic>{
        'id': id,
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
      await Supabase.instance.client.from('comment').insert(map);
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

  static Future<String?> touchSingularCommentRow({
    required String commentId,
    String? updaterStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final id = commentId.trim();
    if (id.isEmpty) return 'Comment id is empty';
    try {
      final map = <String, dynamic>{'update_date': HkTime.timestampForDb()};
      final lookup = updaterStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['update_by'] = staffId;
        }
      }
      await Supabase.instance.client.from('comment').update(map).eq('id', id);
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

  static Future<Map<String, String>> _staffUuidToAppIdMapAll() async {
    final m = <String, String>{};
    if (!_enabled) return m;
    try {
      final res = await Supabase.instance.client
          .from('staff')
          .select('id, app_id');
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

  /// Normalizes `task.status` / `subtask.status` from Supabase (string, Postgres enum, or `{value: …}` JSON).
  static String _dbStatusRawFromRow(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is Map) {
      final dynamic v =
          raw['value'] ?? raw['Value'] ?? raw['name'] ?? raw['label'];
      if (v != null) return v.toString().trim();
    }
    return raw.toString().trim();
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
      createByStaffId: cb?.isNotEmpty == true
          ? (staffUuidToAppId[cb] ?? cb)
          : null,
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
      status: () {
        final raw = _dbStatusRawFromRow(row['status']);
        return raw.isEmpty ? 'Incomplete' : raw;
      }(),
      submission: _submissionFromRow(row['submission']),
      submitDate: _parseDateTimeNullable(row['submit_date']),
      completionDate: _parseDateTimeNullable(row['completion_date']),
      assigneeIds: assigneeIds,
      pic: picKey,
      createDate: _parseDateTimeNullable(
        row['create_date'] ?? row['created_at'],
      ),
      updateDate: _parseDateTimeNullable(row['update_date']),
      lastUpdated: _parseDateTimeNullable(row['last_updated']),
      updateByStaffName: _updateByDisplayName(row, staffUuidToName),
      changeDueReason: _nullableTrimmedString(row['change_due_reason']),
      overdueDay: _flexIntFromRow(row['overdue_day']),
      overdue: _overdueYnFromRow(row['overdue']),
    );
  }

  /// Loads raw `subtask` rows for [taskId] with best-effort ordering (schema varies by deployment).
  static Future<List<Map<String, dynamic>>> _fetchSubtaskRawRowsForTask(
    String taskId,
  ) async {
    if (!_enabled) return [];
    final tid = taskId.trim();
    if (tid.isEmpty) return [];
    final client = Supabase.instance.client;
    List<Map<String, dynamic>> asMapList(dynamic res) =>
        (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    try {
      final res = await client
          .from('subtask')
          .select()
          .eq('task_id', tid)
          .order('create_date', ascending: false);
      return asMapList(res);
    } catch (_) {
      try {
        final res = await client
            .from('subtask')
            .select()
            .eq('task_id', tid)
            .order('created_at', ascending: false);
        return asMapList(res);
      } catch (_) {
        try {
          final res = await client.from('subtask').select().eq('task_id', tid);
          return asMapList(res);
        } catch (_) {
          return [];
        }
      }
    }
  }

  static bool _subtaskRowStatusNotDeleted(Map<String, dynamic> row) {
    final s = _dbStatusRawFromRow(row['status']).toLowerCase();
    return s != 'deleted' && s != 'delete';
  }

  static bool _subtaskRowIsDeleted(Map<String, dynamic> row) {
    final s = _dbStatusRawFromRow(row['status']).toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  /// All sub-task rows for [taskId] (including **Deleted**) — for task detail / filters.
  /// Does not use [_subtaskListMemoryCache].
  static Future<List<SingularSubtask>> fetchAllSubtasksForTaskForDetail(
    String taskId,
  ) async {
    if (!_enabled) return [];
    final tid = taskId.trim();
    if (tid.isEmpty) return [];
    Map<String, String> staffMap = {};
    Map<String, String> staffNames = {};
    try {
      final maps = await _loadMaps();
      staffMap = maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
      staffNames = maps?.staffUuidToName ?? <String, String>{};
    } catch (_) {
      try {
        staffMap = await _staffUuidToAppIdMapAll();
      } catch (_) {}
    }
    final rawRows = await _fetchSubtaskRawRowsForTask(tid);
    final out = <SingularSubtask>[];
    for (final row in rawRows) {
      try {
        final st = _singularSubtaskFromRow(row, staffMap, staffNames);
        if (st != null) out.add(st);
      } catch (_) {}
    }
    _sortSingularSubtasksNewestFirst(out);
    return out;
  }

  static Future<List<String?>> _staffRowIdSlotsForAssigneeKeys(
    List<String?> staffKeys,
  ) async {
    final out = <String?>[];
    for (final key in staffKeys.take(10)) {
      final lookup = key?.trim();
      if (lookup == null || lookup.isEmpty) {
        out.add(null);
        continue;
      }
      out.add(await _staffRowIdForAssigneeKey(lookup));
    }
    while (out.length < 10) {
      out.add(null);
    }
    return out;
  }

  /// Deleted sub-tasks only, grouped by parent `task_id` (landing Overview/Default filters).
  static Future<Map<String, List<SingularSubtask>>>
  fetchDeletedSubtasksGroupedForLandingPrefetch(List<String> taskIds) async {
    final out = <String, List<SingularSubtask>>{};
    final ids =
        taskIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    if (ids.isEmpty) return out;
    if (!_enabled) return out;

    Map<String, String> staffMap = {};
    Map<String, String> staffNames = {};
    try {
      final maps = await _loadMaps();
      staffMap = maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
      staffNames = maps?.staffUuidToName ?? <String, String>{};
    } catch (_) {
      try {
        staffMap = await _staffUuidToAppIdMapAll();
      } catch (_) {}
    }

    final client = Supabase.instance.client;
    const chunkSize = 80;
    final pendingRows = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      try {
        final res = await client
            .from('subtask')
            .select()
            .inFilter('task_id', chunk);
        for (final raw in (res as List)) {
          final row = Map<String, dynamic>.from(raw as Map);
          if (!_subtaskRowIsDeleted(row)) continue;
          pendingRows.add(row);
        }
      } catch (_) {}
    }

    for (final row in pendingRows) {
      if (!_subtaskRowIsDeleted(row)) continue;
      try {
        final st = _singularSubtaskFromRow(row, staffMap, staffNames);
        if (st == null) continue;
        final tid = st.taskId;
        out.putIfAbsent(tid, () => []).add(st);
      } catch (_) {}
    }

    for (final e in out.entries) {
      sortSingularSubtasksNewestFirstInPlace(e.value);
    }
    return out;
  }

  /// Parent [`task.id`] values where **every** trimmed token matches (AND). RPC
  /// [`search_parent_task_ids_for_tokens`] scans the indexed materialized view
  /// `task_subtask_search_mv` (pre-joined task + sub-task text). After bulk task/sub-task
  /// changes, refresh that MV in SQL (e.g. `select refresh_task_subtask_search_mv()`) or schedule it.
  static Future<Set<String>> searchParentTaskIdsForTokens(
    List<String> tokensLower,
  ) async {
    if (!_enabled || tokensLower.isEmpty) return {};
    final cleaned = tokensLower
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleaned.isEmpty) return {};
    try {
      final res = await Supabase.instance.client.rpc(
        'search_parent_task_ids_for_tokens',
        params: {'p_tokens': cleaned},
      );
      if (res == null) return {};
      final list = res as List;
      final out = <String>{};
      for (final e in list) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) out.add(s);
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Deprecated path: use [searchParentTaskIdsForTokens] for one round-trip.
  /// Single-token query uses the same RPC and materialized view.
  static Future<Set<String>> fetchTaskIdsHavingSubtaskToken(
    String tokenLower,
  ) async {
    final t = tokenLower.trim();
    if (t.isEmpty) return {};
    return searchParentTaskIdsForTokens([t]);
  }

  /// Non-deleted subtasks for a parent [taskId], newest first.
  static Future<List<SingularSubtask>> fetchSubtasksForTask(String taskId) {
    final tid = taskId.trim();
    if (!_enabled || tid.isEmpty) return Future.value([]);
    return _fetchSubtasksInflight.putIfAbsent(tid, () {
      final f = _fetchSubtasksForTaskImpl(tid);
      f.whenComplete(() => _fetchSubtasksInflight.remove(tid));
      return f;
    });
  }

  static Future<List<SingularSubtask>> _fetchSubtasksForTaskImpl(
    String tid,
  ) async {
    final cached = _subtaskListMemoryCache[tid];
    if (cached != null) return List<SingularSubtask>.from(cached);

    Map<String, String> staffMap = {};
    Map<String, String> staffNames = {};
    try {
      final maps = await _loadMaps();
      staffMap = maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
      staffNames = maps?.staffUuidToName ?? <String, String>{};
    } catch (_) {
      try {
        staffMap = await _staffUuidToAppIdMapAll();
      } catch (_) {}
    }
    final rawRows = await _fetchSubtaskRawRowsForTask(tid);
    final out = <SingularSubtask>[];
    for (final row in rawRows) {
      try {
        final st = _singularSubtaskFromRow(row, staffMap, staffNames);
        if (st != null && !st.isDeleted) out.add(st);
      } catch (_) {
        continue;
      }
    }
    _sortSingularSubtasksNewestFirst(out);
    _storeSubtaskListMemoryCache(tid, out);
    return List<SingularSubtask>.from(out);
  }

  /// Few HTTP calls instead of one per task — used by landing prefetch only.
  /// Seeds [_subtaskListMemoryCache] per id so [fetchSubtasksForTask] hits memory on cards.
  static Future<Map<String, List<SingularSubtask>>>
  fetchSubtasksGroupedForLandingPrefetch(List<String> taskIds) async {
    final out = <String, List<SingularSubtask>>{};
    final ids =
        taskIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    if (ids.isEmpty) return out;
    if (!_enabled) {
      for (final id in ids) {
        out[id] = [];
        _storeSubtaskListMemoryCache(id, []);
      }
      return out;
    }

    Map<String, String> staffMap = {};
    Map<String, String> staffNames = {};
    try {
      final maps = await _loadMaps();
      staffMap = maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
      staffNames = maps?.staffUuidToName ?? <String, String>{};
    } catch (_) {
      try {
        staffMap = await _staffUuidToAppIdMapAll();
      } catch (_) {}
    }

    final client = Supabase.instance.client;
    const chunkSize = 80;
    final pendingRows = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      try {
        final res = await client
            .from('subtask')
            .select()
            .inFilter('task_id', chunk);
        for (final raw in (res as List)) {
          pendingRows.add(Map<String, dynamic>.from(raw as Map));
        }
      } catch (_) {}
    }

    final byTask = <String, List<SingularSubtask>>{};
    for (final row in pendingRows) {
      try {
        final st = _singularSubtaskFromRow(row, staffMap, staffNames);
        if (st == null || st.isDeleted) continue;
        final tid = st.taskId;
        byTask.putIfAbsent(tid, () => []).add(st);
      } catch (_) {}
    }

    for (final id in ids) {
      final list = byTask[id] ?? [];
      _sortSingularSubtasksNewestFirst(list);
      out[id] = list;
      _storeSubtaskListMemoryCache(id, list);
    }
    return out;
  }

  static Future<SingularSubtask?> fetchSubtaskById(String subtaskId) async {
    if (!_enabled) return null;
    try {
      final maps = await _loadMaps();
      final staffMap =
          maps?.staffUuidToAppId ?? await _staffUuidToAppIdMapAll();
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
    if (name.isEmpty)
      return (error: 'subtask_name is required', subtaskId: null);
    try {
      final assigneeStaffIds = await _staffRowIdSlotsForAssigneeKeys(
        assigneeStaffUuids,
      );
      final now = HkTime.timestampForDb();
      final map = <String, dynamic>{
        'task_id': taskId,
        'subtask_name': name,
        'description': description.trim(),
        'priority': priorityDisplay,
        'status': 'Incomplete',
        'submission': 'Pending',
        'create_date': now,
        'update_date': now,
        'last_updated': now,
      };
      final lookup = creatorStaffLookupKey?.trim();
      if (lookup != null && lookup.isNotEmpty) {
        final staffId = await _staffRowIdForAssigneeKey(lookup);
        if (staffId != null && staffId.isNotEmpty) {
          map['create_by'] = staffId;
          map['update_by'] = staffId;
        }
      }
      if (startDate != null) {
        map['start_date'] = HkTime.dateOnlyHkMidnightForDb(startDate);
      }
      if (dueDate != null) {
        map['due_date'] = HkTime.dateOnlyHkMidnightForDb(dueDate);
      }
      for (var i = 0; i < 10; i++) {
        final staffId = assigneeStaffIds[i]?.trim();
        if (staffId != null && staffId.isNotEmpty) {
          map['assignee_${(i + 1).toString().padLeft(2, '0')}'] = staffId;
        }
      }
      final picLookup = picStaffUuid.trim();
      if (picLookup.isNotEmpty) {
        final picStaffId = await _staffRowIdForAssigneeKey(picLookup);
        if (picStaffId == null || picStaffId.isEmpty) {
          return (
            error: 'Could not resolve staff id for sub-task PIC',
            subtaskId: null,
          );
        }
        map['pic'] = picStaffId;
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
      final projectTouchError = await _touchProjectFromSubtaskRow(sid);
      if (projectTouchError != null) {
        return (error: projectTouchError, subtaskId: sid);
      }
      if (initialComment != null && initialComment.trim().isNotEmpty) {
        await insertSubtaskCommentRow(
          subtaskId: sid,
          description: initialComment.trim(),
          creatorStaffLookupKey: creatorStaffLookupKey,
        );
      }
      invalidateSubtasksCacheForTask(taskId);
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
    List<String?>? assigneeSlots,

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
      if (assigneeSlots != null) {
        final assigneeStaffIds = await _staffRowIdSlotsForAssigneeKeys(
          assigneeSlots,
        );
        for (var i = 0; i < 10; i++) {
          map['assignee_${(i + 1).toString().padLeft(2, '0')}'] =
              assigneeStaffIds[i];
        }
      }
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
        map['completion_date'] = HkTime.timestampForDbFromStoredUtc(
          completionDateAt.toUtc(),
        );
      }
      if (stampSubmitDateNow) {
        map['submit_date'] = HkTime.timestampForDb();
      }
      await Supabase.instance.client
          .from('subtask')
          .update(map)
          .eq('id', subtaskId);
      await _invalidateSubtasksCacheForSubtaskId(subtaskId);
      if (map.containsKey('update_date')) {
        final projectTouchError = await _touchProjectFromSubtaskRow(subtaskId);
        if (projectTouchError != null) return projectTouchError;
      }
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
      final id = const Uuid().v4();
      final map = <String, dynamic>{
        'id': id,
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
      await Supabase.instance.client.from('subtask_comment').insert(map);
      return (error: null, commentId: id);
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

  static Future<String?> touchSubtaskCommentRow({
    required String commentId,
    String? updaterStaffLookupKey,
  }) async {
    if (!_enabled) return 'Supabase not configured';
    final id = commentId.trim();
    if (id.isEmpty) return 'Comment id is empty';
    try {
      final map = <String, dynamic>{'update_date': HkTime.timestampForDb()};
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
          .eq('id', id);
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

  /// Max of `(update_date ?? create_date)` per `task_id` from [`comment`] (landing Overview).
  static Future<Map<String, DateTime?>> fetchMaxTaskCommentActivityByTaskIds(
    List<String> taskIds,
  ) async {
    final out = <String, DateTime?>{};
    if (!_enabled || taskIds.isEmpty) return out;
    final ids =
        taskIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    const chunkSize = 80;
    final client = Supabase.instance.client;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      try {
        final res = await client
            .from('comment')
            .select('task_id,create_date,update_date')
            .inFilter('task_id', chunk);
        for (final raw in (res as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final tid = m['task_id']?.toString().trim();
          if (tid == null || tid.isEmpty) continue;
          final u = _parseDateTimeNullable(m['update_date']);
          final c = _parseDateTimeNullable(m['create_date']);
          final eff = u ?? c;
          if (eff == null) continue;
          final prev = out[tid];
          if (prev == null || eff.isAfter(prev)) out[tid] = eff;
        }
      } catch (_) {}
    }
    return out;
  }

  /// Max of `(update_date ?? create_date)` per `subtask_id` from [`subtask_comment`].
  static Future<Map<String, DateTime?>>
  fetchMaxSubtaskCommentActivityBySubtaskIds(List<String> subtaskIds) async {
    final out = <String, DateTime?>{};
    if (!_enabled || subtaskIds.isEmpty) return out;
    final ids =
        subtaskIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    const chunkSize = 80;
    final client = Supabase.instance.client;
    for (var i = 0; i < ids.length; i += chunkSize) {
      final end = min(i + chunkSize, ids.length);
      final chunk = ids.sublist(i, end);
      try {
        final res = await client
            .from('subtask_comment')
            .select('subtask_id,create_date,update_date')
            .inFilter('subtask_id', chunk);
        for (final raw in (res as List)) {
          final m = Map<String, dynamic>.from(raw as Map);
          final sid = m['subtask_id']?.toString().trim();
          if (sid == null || sid.isEmpty) continue;
          final u = _parseDateTimeNullable(m['update_date']);
          final c = _parseDateTimeNullable(m['create_date']);
          final eff = u ?? c;
          if (eff == null) continue;
          final prev = out[sid];
          if (prev == null || eff.isAfter(prev)) out[sid] = eff;
        }
      } catch (_) {}
    }
    return out;
  }
}
