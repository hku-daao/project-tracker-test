import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted landing-page task list filters (per Firebase user id).
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
  });

  final String filterType;
  final List<String> teamIds;
  final List<String> assigneeIds;
  final List<String> statuses;

  /// `pending` | `submitted` | `accepted` | `returned` — empty = all submissions.
  final List<String> submissionFilters;
  final String search;

  /// `creator` | `assignee` | `startDate` | `dueDate` | `status` | `submission`, or null.
  final String? sortColumn;
  final bool sortAscending;

  Map<String, dynamic> toJson() => {
        'filterType': filterType,
        'teamIds': teamIds,
        'assigneeIds': assigneeIds,
        'statuses': statuses,
        'submissionFilters': submissionFilters,
        'search': search,
        // Persist explicit null so clearing sort overwrites any previous column in storage.
        'sortColumn': sortColumn,
        'sortAscending': sortAscending,
      };

  static LandingTaskFilters? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return LandingTaskFilters(
      filterType: j['filterType'] as String? ?? 'all',
      teamIds: List<String>.from(j['teamIds'] as List? ?? const []),
      assigneeIds: List<String>.from(j['assigneeIds'] as List? ?? const []),
      statuses: List<String>.from(j['statuses'] as List? ?? const []),
      submissionFilters: List<String>.from(
        j['submissionFilters'] as List? ?? const [],
      ),
      search: j['search'] as String? ?? '',
      sortColumn: j['sortColumn'] as String?,
      sortAscending: j['sortAscending'] as bool? ?? true,
    );
  }
}

class LandingTaskFiltersStorage {
  static String _key(String uid) => 'landing_task_filters_v1_$uid';

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
