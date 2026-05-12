import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted landing-page task list filters (per Firebase user id). Storage key `landing_task_filters_v2_*`.
class LandingTaskFilters {
  const LandingTaskFilters({
    required this.filterType,
    required this.teamIds,
    required this.assigneeIds,
    required this.statuses,
    this.submissionFilters = const [],
    required this.search,
    this.sortColumn,
    this.sortAscending = true,
    this.filterAssigneeTeamId,
    this.filterAssigneeStaffIds = const [],
    this.filterPicTeamId,
    this.filterPicStaffIds = const [],
    this.filterCreatorTeamId,
    this.filterCreatorStaffIds = const [],
    this.filterOverdueOnly = false,
    this.filterCreateDateStartMs,
    this.filterCreateDateEndMs,
    /// Overview (`InitiativeListScreen.customizedFlat`): `all` | `project` | `task` | `subtask`.
    this.overviewEntityTab,
  });

  final String filterType;
  final List<String> teamIds;
  final List<String> assigneeIds;
  final List<String> statuses;

  /// Team roster for "Filter by assignee" submenu; staff ids filter tasks/initiatives.
  final String? filterAssigneeTeamId;
  final List<String> filterAssigneeStaffIds;

  /// Team roster for "Filter by PIC"; staff ids match [`task.pic`].
  final String? filterPicTeamId;
  final List<String> filterPicStaffIds;

  /// Team roster for "Filter by creator" submenu; staff ids filter tasks by [Task.createByAssigneeKey].
  final String? filterCreatorTeamId;
  final List<String> filterCreatorStaffIds;

  /// `pending` | `submitted` | `accepted` | `returned` — empty = all submissions.
  final List<String> submissionFilters;

  /// When true, landing lists only tasks/sub-tasks whose DB [`overdue`] flag is `Yes`.
  final bool filterOverdueOnly;

  /// Inclusive calendar-day bounds (local); null = not set. Applies to task create date (and sub-task rows on Customized).
  final int? filterCreateDateStartMs;
  final int? filterCreateDateEndMs;

  /// Persisted Overview segment tab (browser return visit).
  final String? overviewEntityTab;
  final String search;

  /// `creator` | `assignee` | `startDate` | `dueDate` | `status` | `submission`, or null.
  /// [filterOverdueOnly] is stored separately as a bool.
  final String? sortColumn;
  final bool sortAscending;

  Map<String, dynamic> toJson() => {
        'filterType': filterType,
        'teamIds': teamIds,
        'assigneeIds': assigneeIds,
        'statuses': statuses,
        'submissionFilters': submissionFilters,
        'filterOverdueOnly': filterOverdueOnly,
        'search': search,
        // Persist explicit null so clearing sort overwrites any previous column in storage.
        'sortColumn': sortColumn,
        'sortAscending': sortAscending,
        'filterAssigneeTeamId': filterAssigneeTeamId,
        'filterAssigneeStaffIds': filterAssigneeStaffIds,
        'filterPicTeamId': filterPicTeamId,
        'filterPicStaffIds': filterPicStaffIds,
        'filterCreatorTeamId': filterCreatorTeamId,
        'filterCreatorStaffIds': filterCreatorStaffIds,
        'filterCreateDateStartMs': filterCreateDateStartMs,
        'filterCreateDateEndMs': filterCreateDateEndMs,
        'overviewEntityTab': overviewEntityTab,
      };

  static LandingTaskFilters? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return LandingTaskFilters(
      filterType: j['filterType'] as String? ?? 'all',
      teamIds: List<String>.from(j['teamIds'] as List? ?? const []),
      assigneeIds: List<String>.from(j['assigneeIds'] as List? ?? const []),
      statuses: List<String>.from(j['statuses'] as List? ?? const []),
      submissionFilters: <String>[
        for (final e in (j['submissionFilters'] as List? ?? const []))
          if (e != null) e.toString(),
      ],
      filterOverdueOnly: j['filterOverdueOnly'] as bool? ?? false,
      search: j['search'] as String? ?? '',
      sortColumn: j['sortColumn'] as String?,
      sortAscending: j['sortAscending'] as bool? ?? true,
      filterAssigneeTeamId: j['filterAssigneeTeamId'] as String?,
      filterAssigneeStaffIds: List<String>.from(
        j['filterAssigneeStaffIds'] as List? ?? const [],
      ),
      filterPicTeamId: j['filterPicTeamId'] as String?,
      filterPicStaffIds: List<String>.from(
        j['filterPicStaffIds'] as List? ?? const [],
      ),
      filterCreatorTeamId: j['filterCreatorTeamId'] as String?,
      filterCreatorStaffIds: List<String>.from(
        j['filterCreatorStaffIds'] as List? ?? const [],
      ),
      filterCreateDateStartMs: j['filterCreateDateStartMs'] as int?,
      filterCreateDateEndMs: j['filterCreateDateEndMs'] as int?,
      overviewEntityTab: j['overviewEntityTab'] as String?,
    );
  }
}

class LandingTaskFiltersStorage {
  static String _key(String uid) => 'landing_task_filters_v2_$uid';

  static Future<void> save(String uid, LandingTaskFilters f) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key(uid), jsonEncode(f.toJson()));
  }

  static Future<LandingTaskFilters?> load(String uid) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key(uid));
    if (s == null || s.isEmpty) return null;
    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      return LandingTaskFilters.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
