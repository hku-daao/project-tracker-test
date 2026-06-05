import '../../app_state.dart';
import '../../models/project_record.dart';

class AsanaProjectFilterState {
  AsanaProjectFilterState() {
    resetToDefaults();
  }

  Set<String> scopes = {};

  /// Empty = all statuses (default).
  Set<String> statuses = {};
  List<String> creatorStaffIds = [];
  List<String> picStaffIds = [];

  DateTime? createDateStart;
  DateTime? createDateEnd;
  String sortKey = 'created';
  bool sortAscending = false;

  bool get createDateEngaged =>
      createDateStart != null || createDateEnd != null;

  Map<String, dynamic> toCookieJson() => {
    'scopes': scopes.toList(),
    'statuses': statuses.toList(),
    'creatorStaffIds': creatorStaffIds,
    'picStaffIds': picStaffIds,
    'createDateStart': createDateStart?.millisecondsSinceEpoch,
    'createDateEnd': createDateEnd?.millisecondsSinceEpoch,
    'sortKey': sortKey,
    'sortAscending': sortAscending,
  };

  void applyCookieJson(Map<String, dynamic> data) {
    scopes = _stringSet(data['scopes']);
    statuses = _stringSet(data['statuses']);
    creatorStaffIds = _stringList(data['creatorStaffIds']);
    picStaffIds = _stringList(data['picStaffIds']);
    createDateStart = _dateFromMs(data['createDateStart']);
    createDateEnd = _dateFromMs(data['createDateEnd']);
    final rawSortKey = data['sortKey'] as String?;
    if (rawSortKey == 'due' ||
        rawSortKey == 'created' ||
        rawSortKey == 'updated' ||
        rawSortKey == 'name') {
      sortKey = rawSortKey!;
    }
    sortAscending = data['sortAscending'] as bool? ?? sortAscending;
  }

  static Set<String> _stringSet(Object? value) => {
    for (final e in value is List ? value : const [])
      if (e != null) e.toString(),
  };

  static List<String> _stringList(Object? value) => [
    for (final e in value is List ? value : const [])
      if (e != null) e.toString(),
  ];

  static DateTime? _dateFromMs(Object? value) {
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }

  void resetToDefaults() {
    scopes = {};
    statuses = {};
    creatorStaffIds = [];
    picStaffIds = [];
    sortKey = 'created';
    sortAscending = false;
    createDateStart = null;
    createDateEnd = null;
  }
}

class AsanaProjectFilter {
  AsanaProjectFilter._();

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _calendarDayInDueRange(DateTime day, AsanaProjectFilterState f) {
    if (!f.createDateEngaged) return true;
    final s = f.createDateStart != null ? _dateOnly(f.createDateStart!) : null;
    final e = f.createDateEnd != null ? _dateOnly(f.createDateEnd!) : null;
    if (s != null && day.isBefore(s)) return false;
    if (e != null && day.isAfter(e)) return false;
    return true;
  }

  static bool _projectPassesDueDate(
    ProjectRecord p,
    AsanaProjectFilterState filters,
  ) {
    if (!filters.createDateEngaged) return true;
    final due = p.endDate;
    if (due == null) return true;
    return _calendarDayInDueRange(_dateOnly(due), filters);
  }

  /// Mirrors [InitiativeListScreen._projectIsVisibleToCurrentUser].
  static bool _projectVisible(
    ProjectRecord p,
    AppState state,
    Set<String> scopes,
  ) {
    final mine = state.userStaffAppId?.trim();
    final myUuid = state.userStaffId?.trim();

    if (scopes.isNotEmpty && !scopes.contains('all')) {
      bool pass = false;
      if (scopes.contains('assigned')) {
        if (myUuid != null && myUuid.isNotEmpty) {
          if (p.assigneeStaffUuids.any((u) => u.trim() == myUuid) ||
              p.picStaffUuids.any((u) => u.trim() == myUuid)) {
            pass = true;
          }
        }
      }
      if (!pass && scopes.contains('created')) {
        if (myUuid != null && myUuid.isNotEmpty) {
          if (p.createByStaffUuid?.trim() == myUuid) {
            pass = true;
          }
        }
      }
      if (!pass) return false;
    }

    if (mine == null || mine.isEmpty) return false;
    if (myUuid != null &&
        myUuid.isNotEmpty &&
        p.createByStaffUuid?.trim() == myUuid) {
      return true;
    }
    for (final u in p.assigneeStaffUuids) {
      final uid = u.trim();
      if (myUuid != null && uid == myUuid) return true;
      final appId = state.assigneeById(uid)?.id ?? uid;
      if (appId == mine) return true;
    }
    if (myUuid != null &&
        myUuid.isNotEmpty &&
        p.picStaffUuids.any((u) => u.trim() == myUuid)) {
      return true;
    }
    final subs = state.subordinateAppIds;
    if (subs.isEmpty) return false;
    final cb = p.createByStaffUuid?.trim();
    if (cb != null && cb.isNotEmpty) {
      final creatorApp = state.assigneeById(cb)?.id ?? cb;
      if (subs.contains(creatorApp)) return true;
    }
    for (final u in p.assigneeStaffUuids) {
      final appId = state.assigneeById(u.trim())?.id ?? u.trim();
      if (subs.contains(appId)) return true;
    }
    for (final u in p.picStaffUuids) {
      final appId = state.assigneeById(u.trim())?.id ?? u.trim();
      if (subs.contains(appId)) return true;
    }
    return false;
  }

  static String _staffName(
    AppState state,
    String staffUuid, {
    String? resolvedName,
  }) {
    final stored = resolvedName?.trim();
    if (stored != null && stored.isNotEmpty && stored != staffUuid.trim()) {
      return stored;
    }
    final u = staffUuid.trim();
    if (u.isEmpty) return '';
    final byApp = state.assigneeById(u);
    if (byApp != null && byApp.name.trim().isNotEmpty) {
      return byApp.name.trim();
    }
    return u;
  }

  static bool projectCreatedByCurrentUser(AppState state, ProjectRecord p) {
    final myUuid = state.userStaffId?.trim();
    if (myUuid == null || myUuid.isEmpty) return false;
    return p.createByStaffUuid?.trim() == myUuid;
  }

  static bool projectAssignedToCurrentUser(AppState state, ProjectRecord p) {
    final myUuid = state.userStaffId?.trim();
    if (myUuid == null || myUuid.isEmpty) return false;
    return p.assigneeStaffUuids.any((u) => u.trim() == myUuid);
  }

  static bool _keyMatches(String? value, Iterable<String> selected) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return false;
    for (final s in selected) {
      if (v.toLowerCase() == s.trim().toLowerCase()) return true;
    }
    return false;
  }

  static bool _projectPassesRoleFilters(
    ProjectRecord p,
    AsanaProjectFilterState filters,
  ) {
    if (filters.creatorStaffIds.isNotEmpty &&
        !_keyMatches(p.createByStaffUuid, filters.creatorStaffIds)) {
      return false;
    }
    if (filters.picStaffIds.isNotEmpty &&
        !p.picStaffUuids.any((u) => _keyMatches(u, filters.picStaffIds))) {
      return false;
    }
    return true;
  }

  static List<String> searchTokens(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static bool _containsAllTokens(
    Iterable<String?> values,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return false;
    final haystack = values
        .whereType<String>()
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .join(' ')
        .toLowerCase();
    if (haystack.isEmpty) return false;
    for (final tkn in tokens) {
      if (!haystack.contains(tkn)) return false;
    }
    return true;
  }

  static bool projectSearchMatches(
    AppState state,
    ProjectRecord p,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return false;
    return _containsAllTokens([
      p.name,
      p.description,
      p.createByDisplayName,
      p.createByStaffUuid,
      creatorLine(p, state),
      assigneesLine(p, state),
      picLine(p, state),
      ...p.assigneeStaffDisplayNames,
      ...p.assigneeStaffUuids,
      ...p.picStaffDisplayNames,
      ...p.picStaffUuids,
    ], tokens);
  }

  static List<ProjectRecord> apply(
    AppState state,
    AsanaProjectFilterState filters, {
    required String searchQuery,
  }) {
    var list = state.projects
        .where((p) => _projectVisible(p, state, filters.scopes))
        .toList();

    final statuses = filters.statuses.difference({'all', '__all__'});
    if (statuses.isNotEmpty) {
      list = list.where((p) => statuses.contains(p.status)).toList();
    }

    list = list.where((p) => _projectPassesDueDate(p, filters)).toList();
    list = list.where((p) => _projectPassesRoleFilters(p, filters)).toList();

    final tokens = searchTokens(searchQuery);
    if (tokens.isNotEmpty) {
      list = list.where((p) => projectSearchMatches(state, p, tokens)).toList();
    }

    list.sort((a, b) {
      int cmp;
      switch (filters.sortKey) {
        case 'name':
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'created':
          final ac = a.createDate;
          final bc = b.createDate;
          if (ac == null && bc == null) {
            cmp = 0;
          } else if (ac == null) {
            cmp = 1;
          } else if (bc == null) {
            cmp = -1;
          } else {
            cmp = ac.compareTo(bc);
          }
        case 'updated':
          final au = a.updateDate ?? a.createDate;
          final bu = b.updateDate ?? b.createDate;
          if (au == null && bu == null) {
            cmp = 0;
          } else if (au == null) {
            cmp = 1;
          } else if (bu == null) {
            cmp = -1;
          } else {
            cmp = au.compareTo(bu);
          }
        case 'due':
        default:
          final ad = a.endDate;
          final bd = b.endDate;
          if (ad == null && bd == null) {
            cmp = 0;
          } else if (ad == null) {
            cmp = 1;
          } else if (bd == null) {
            cmp = -1;
          } else {
            cmp = ad.compareTo(bd);
          }
      }
      if (cmp == 0) {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return filters.sortAscending ? cmp : -cmp;
    });

    return list;
  }

  static String assigneesLine(ProjectRecord p, AppState state) {
    if (p.assigneeStaffUuids.isEmpty) return '—';
    final parts = <String>[];
    for (var i = 0; i < p.assigneeStaffUuids.length; i++) {
      final uuid = p.assigneeStaffUuids[i];
      final stored = i < p.assigneeStaffDisplayNames.length
          ? p.assigneeStaffDisplayNames[i]
          : null;
      parts.add(_staffName(state, uuid, resolvedName: stored));
    }
    return parts.join(', ');
  }

  static String creatorLine(ProjectRecord p, AppState state) {
    final stored = p.createByDisplayName?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final id = p.createByStaffUuid?.trim();
    if (id == null || id.isEmpty) return '—';
    return _staffName(state, id);
  }

  static String picLine(ProjectRecord p, AppState state) {
    if (p.picStaffUuids.isEmpty) return '—';
    final parts = <String>[];
    for (var i = 0; i < p.picStaffUuids.length; i++) {
      final uuid = p.picStaffUuids[i].trim();
      if (uuid.isEmpty) continue;

      String? name;
      if (i < p.picStaffDisplayNames.length) {
        final stored = p.picStaffDisplayNames[i].trim();
        if (stored.isNotEmpty && stored != uuid) {
          name = state.assigneeById(stored)?.name ?? stored;
        }
      }
      name ??= state.assigneeById(uuid)?.name;
      if (name == null || name.isEmpty) {
        for (final a in state.assignees) {
          if (a.id == uuid) {
            name = a.name;
            break;
          }
        }
      }
      parts.add((name != null && name.isNotEmpty) ? name : uuid);
    }
    return parts.isEmpty ? '—' : parts.join(', ');
  }
}
