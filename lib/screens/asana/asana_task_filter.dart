import '../../app_state.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../services/landing_task_filters_storage.dart';

/// One row in **All tasks & sub-tasks** (flattened task or sub-task).
class AsanaFlatRow {
  const AsanaFlatRow.task(this.task) : sub = null;
  const AsanaFlatRow.subtask(this.task, this.sub);

  final Task task;
  final SingularSubtask? sub;

  bool get isTask => sub == null;
}

/// Landing-style task filters for [AsanaTasksPanel] (mirrors Overview / Tasks tab).
class AsanaTaskFilterState {
  AsanaTaskFilterState();

  /// `all` | `assigned` | `created`
  String scope = 'all';
  /// Empty = all statuses / all submissions (no chip filter).
  final Set<String> statuses = {};
  final Set<String> submissions = {};
  DateTime? createDateStart;
  DateTime? createDateEnd;
  bool overdueOnly = false;

  /// `due` | `created` | `name`
  String sortKey = 'due';
  bool sortAscending = true;
  List<String> assigneeStaffIds = [];
  List<String> picStaffIds = [];
  List<String> creatorStaffIds = [];
  static const statusIncomplete = 'incomplete';
  static const statusCompleted = 'completed';
  static const statusDeleted = 'deleted';
  static const submissionPending = 'pending';
  static const submissionSubmitted = 'submitted';
  static const submissionAccepted = 'accepted';
  static const submissionReturned = 'returned';
  bool get createDateEngaged =>
      createDateStart != null || createDateEnd != null;

  void resetToDefaults() {
    scope = 'all';
    statuses.clear();
    submissions.clear();
    overdueOnly = false;
    sortKey = 'due';
    sortAscending = true;
    assigneeStaffIds = [];
    picStaffIds = [];
    creatorStaffIds = [];
    createDateStart = null;
    createDateEnd = null;
  }

  /// Restore filters saved from the main landing / Overview screen.
  void applyLandingFilters(LandingTaskFilters data) {
    var ft = data.filterType;
    if (ft == 'my') ft = 'all';
    if (ft != 'all' && ft != 'assigned' && ft != 'created') ft = 'all';
    scope = ft;
    statuses.clear();
    for (final s in data.statuses) {
      if (s == statusIncomplete || s == statusCompleted || s == statusDeleted) {
        statuses.add(s);
      }
    }
    submissions.clear();
    for (final s in data.submissionFilters) {
      if (s == submissionPending ||
          s == submissionSubmitted ||
          s == submissionAccepted ||
          s == submissionReturned) {
        submissions.add(s);
      }
    }
    overdueOnly = data.filterOverdueOnly;
    createDateStart = data.filterCreateDateStartMs != null
        ? DateTime.fromMillisecondsSinceEpoch(data.filterCreateDateStartMs!)
        : null;
    createDateEnd = data.filterCreateDateEndMs != null
        ? DateTime.fromMillisecondsSinceEpoch(data.filterCreateDateEndMs!)
        : null;
    assigneeStaffIds = List<String>.from(data.filterAssigneeStaffIds);
    picStaffIds = List<String>.from(data.filterPicStaffIds);
    creatorStaffIds = List<String>.from(data.filterCreatorStaffIds);
    switch (data.sortColumn) {
      case 'dueDate':
        sortKey = 'due';
        sortAscending = data.sortAscending;
      case 'startDate':
        sortKey = 'due';
        sortAscending = data.sortAscending;
      case 'creator':
      case 'assignee':
        sortKey = 'name';
        sortAscending = data.sortAscending;
      case 'status':
      case 'submission':
        sortKey = 'name';
        sortAscending = data.sortAscending;
      default:
        sortKey = data.sortColumn == null ? 'due' : 'created';
        sortAscending = data.sortColumn == null ? true : data.sortAscending;
    }
  }

  /// Restores shared prefs (scope, status, sort, …) but not Overview menu role filters
  /// (assignee / PIC / creator), which would hide every row in the Asana table.
  void applyAsanaPanelFilters(LandingTaskFilters data) {
    applyLandingFilters(data);
    assigneeStaffIds = [];
    picStaffIds = [];
    creatorStaffIds = [];
  }
}

/// Applies the same visibility rules as [InitiativeListScreen] Overview **Tasks** tab.
class AsanaTaskFilter {
  AsanaTaskFilter._();
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _submissionKeyRaw(String? submission) {
    final raw = submission?.trim().toLowerCase() ?? '';
    if (raw.isEmpty || raw == 'pending') {
      return AsanaTaskFilterState.submissionPending;
    }
    if (raw == 'submitted') return AsanaTaskFilterState.submissionSubmitted;
    if (raw == 'accepted') return AsanaTaskFilterState.submissionAccepted;
    if (raw == 'returned') return AsanaTaskFilterState.submissionReturned;
    return AsanaTaskFilterState.submissionPending;
  }

  static String _submissionKey(Task t) => _submissionKeyRaw(t.submission);
  static bool _singularDeleted(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'delete' || s == 'deleted';
  }

  static bool _singularCompleted(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'completed' || s == 'complete';
  }

  static bool _singularIncomplete(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return true;
    if (s == 'incomplete') return true;
    // Treat other non-terminal statuses as incomplete for filtering.
    return s != 'completed' &&
        s != 'complete' &&
        s != 'deleted' &&
        s != 'delete';
  }

  static bool _singularSubtaskCompleted(SingularSubtask s) {
    final x = s.status.trim().toLowerCase();
    return x == 'completed' || x == 'complete';
  }

  /// Tasks where the signed-in user is in [Task.assigneeIds].
  static bool taskAssignedToCurrentUser(AppState state, Task t) {
    return _taskAssignedToCurrentUser(state, t);
  }

  static bool _taskAssignedToCurrentUser(AppState state, Task t) {
    final mine = state.userStaffAppId?.trim();
    final myUuid = state.userStaffId?.trim();
    if (mine != null && mine.isNotEmpty && t.assigneeIds.contains(mine)) {
      return true;
    }
    if (myUuid != null && myUuid.isNotEmpty) {
      for (final id in t.assigneeIds) {
        if (id.trim().toLowerCase() == myUuid.toLowerCase()) return true;
      }
    }
    return false;
  }

  static bool _landingVisible(AppState state, Task t, String filterKey) {
    final fk = filterKey == 'my' ? 'all' : filterKey;
    if (fk == 'assigned') return _taskAssignedToCurrentUser(state, t);
    if (fk == 'created') return state.taskIsCreatedByCurrentUser(t);
    return state.taskMatchesSupervisorScope(t);
  }

  static List<String> _searchTokens(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static bool _taskTextMatchesAllTokens(Task t, List<String> tokens) {
    if (tokens.isEmpty) return false;
    final name = t.name.toLowerCase();
    final desc = t.description.toLowerCase();
    final pn = (t.projectName ?? '').toLowerCase();
    final pd = (t.projectDescription ?? '').toLowerCase();
    for (final tkn in tokens) {
      if (!name.contains(tkn) &&
          !desc.contains(tkn) &&
          !pn.contains(tkn) &&
          !pd.contains(tkn)) {
        return false;
      }
    }
    return true;
  }

  static bool _subtaskTextMatchesAllTokens(
    SingularSubtask s,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) return false;
    final n = s.subtaskName.toLowerCase();
    final d = s.description.toLowerCase();
    for (final tkn in tokens) {
      if (!n.contains(tkn) && !d.contains(tkn)) return false;
    }
    return true;
  }

  static bool _subtaskPassesStatusChips(
    SingularSubtask s,
    AsanaTaskFilterState filters,
  ) {
    if (filters.statuses.isEmpty) return true;
    final wantInc = filters.statuses.contains(
      AsanaTaskFilterState.statusIncomplete,
    );
    final wantComp = filters.statuses.contains(
      AsanaTaskFilterState.statusCompleted,
    );
    final wantDel = filters.statuses.contains(
      AsanaTaskFilterState.statusDeleted,
    );
    if (!wantInc && !wantComp && !wantDel) return true;
    if (s.isDeleted) return wantDel;
    if (_singularSubtaskCompleted(s)) return wantComp;
    return wantInc;
  }

  static bool _overviewCompletedOnlyWithoutIncomplete(
    AsanaTaskFilterState filters,
  ) {
    return filters.statuses.contains(AsanaTaskFilterState.statusCompleted) &&
        !filters.statuses.contains(AsanaTaskFilterState.statusIncomplete);
  }

  static bool _shouldOmitSubtaskRow(
    Task t,
    SingularSubtask s,
    AsanaTaskFilterState filters,
  ) {
    if (s.isDeleted) {
      if (!filters.statuses.contains(AsanaTaskFilterState.statusDeleted)) {
        return true;
      }
      return false;
    }
    if (filters.statuses.contains(AsanaTaskFilterState.statusIncomplete) &&
        !filters.statuses.contains(AsanaTaskFilterState.statusCompleted) &&
        _singularIncomplete(t) &&
        _singularSubtaskCompleted(s)) {
      return true;
    }
    if (_overviewCompletedOnlyWithoutIncomplete(filters) &&
        !_singularSubtaskCompleted(s)) {
      return true;
    }
    if (filters.submissions.length == 1) {
      final tk = _submissionKey(t);
      final sk = _submissionKeyRaw(s.submission);
      if (filters.submissions.contains(
            AsanaTaskFilterState.submissionPending,
          ) &&
          tk == AsanaTaskFilterState.submissionPending &&
          (sk == AsanaTaskFilterState.submissionSubmitted ||
              sk == AsanaTaskFilterState.submissionAccepted ||
              sk == AsanaTaskFilterState.submissionReturned)) {
        return true;
      }
      if (filters.submissions.contains(
            AsanaTaskFilterState.submissionSubmitted,
          ) &&
          tk == AsanaTaskFilterState.submissionSubmitted &&
          (sk == AsanaTaskFilterState.submissionAccepted ||
              sk == AsanaTaskFilterState.submissionReturned ||
              sk == AsanaTaskFilterState.submissionPending)) {
        return true;
      }
      if (filters.submissions.contains(
            AsanaTaskFilterState.submissionAccepted,
          ) &&
          tk == AsanaTaskFilterState.submissionAccepted &&
          (sk == AsanaTaskFilterState.submissionSubmitted ||
              sk == AsanaTaskFilterState.submissionReturned ||
              sk == AsanaTaskFilterState.submissionPending)) {
        return true;
      }
      if (filters.submissions.contains(
            AsanaTaskFilterState.submissionReturned,
          ) &&
          tk == AsanaTaskFilterState.submissionReturned &&
          (sk == AsanaTaskFilterState.submissionSubmitted ||
              sk == AsanaTaskFilterState.submissionAccepted ||
              sk == AsanaTaskFilterState.submissionPending)) {
        return true;
      }
    }
    return false;
  }

  static bool _hideIncompleteParentWhenCompletedOnly(
    Task t,
    AsanaTaskFilterState filters,
  ) {
    if (!_overviewCompletedOnlyWithoutIncomplete(filters)) return false;
    return _singularIncomplete(t);
  }

  static bool _calendarDayInDueRange(DateTime day, AsanaTaskFilterState f) {
    if (!f.createDateEngaged) return true;
    final s = f.createDateStart != null ? _dateOnly(f.createDateStart!) : null;
    final e = f.createDateEnd != null ? _dateOnly(f.createDateEnd!) : null;
    if (s != null && day.isBefore(s)) return false;
    if (e != null && day.isAfter(e)) return false;
    return true;
  }

  static bool _rowPassesDueDate(
    Task t,
    SingularSubtask? sub,
    AsanaTaskFilterState filters,
  ) {
    if (!filters.createDateEngaged) return true;
    final DateTime? due = sub == null ? t.endDate : sub.dueDate;
    if (due == null) return false;
    return _calendarDayInDueRange(_dateOnly(due), filters);
  }

  static bool _rowPassesDueDateSubtask(
    Task t,
    SingularSubtask s,
    AsanaTaskFilterState filters,
  ) {
    return _rowPassesDueDate(t, s, filters);
  }

  /// Phase 1: scope, status, submission, role menus, overdue â€” no create-date (customized flat).
  static List<Task> buildPhase1Tasks(
    AppState state,
    AsanaTaskFilterState filters, {
    required String searchQuery,
  }) {
    const allTeams = <String>{};
    var tasks = state
        .tasksForTeams(allTeams)
        .where((t) => t.isSingularTableRow);
    if (filters.assigneeStaffIds.isNotEmpty) {
      tasks = tasks.where(
        (t) => t.assigneeIds.any(filters.assigneeStaffIds.contains),
      );
    }
    if (filters.picStaffIds.isNotEmpty) {
      tasks = tasks.where((t) {
        final p = t.pic?.trim();
        return p != null && p.isNotEmpty && filters.picStaffIds.contains(p);
      });
    }
    if (filters.creatorStaffIds.isNotEmpty) {
      tasks = tasks.where((t) {
        final k = t.createByAssigneeKey?.trim();
        return k != null && k.isNotEmpty && filters.creatorStaffIds.contains(k);
      });
    }
    final tasksList = tasks.toList();
    final tasksNonDeleted = tasksList
        .where((t) => !_singularDeleted(t))
        .toList();
    final tasksDeletedSingular = tasksList.where(_singularDeleted).toList();
    final filterKey = filters.scope;
    bool taskMatchesSubmission(Task t) {
      if (filters.submissions.isEmpty) return true;
      return filters.submissions.contains(_submissionKey(t));
    }

    bool nonDeletedMatchesStatus(Task t) {
      if (filters.statuses.isEmpty) return taskMatchesSubmission(t);
      if (_singularDeleted(t)) return false;
      if (filters.statuses.contains(AsanaTaskFilterState.statusIncomplete) &&
          _singularIncomplete(t)) {
        return taskMatchesSubmission(t);
      }
      if (filters.statuses.contains(AsanaTaskFilterState.statusCompleted) &&
          _singularCompleted(t)) {
        return taskMatchesSubmission(t);
      }
      return false;
    }

    bool deletedMatchesStatus(Task t) {
      if (!_singularDeleted(t)) return false;
      if (filters.statuses.isEmpty) return false;
      if (!filters.statuses.contains(AsanaTaskFilterState.statusDeleted)) {
        return false;
      }
      return taskMatchesSubmission(t);
    }

    bool shouldShowDeleted() {
      if (filters.statuses.isEmpty) return false;
      return filters.statuses.contains(AsanaTaskFilterState.statusDeleted);
    }

    List<Task> withScopeAndStatus(
      List<Task> source,
      bool Function(Task) statusMatch,
    ) {
      Iterable<Task> it = source;
      if (filterKey == 'assigned') {
        it = it.where((t) => _taskAssignedToCurrentUser(state, t));
      } else if (filterKey == 'created') {
        it = it.where(state.taskIsCreatedByCurrentUser);
      } else {
        it = it.where((t) => _landingVisible(state, t, 'all'));
      }
      return it.where(statusMatch).toList();
    }

    var filtered = withScopeAndStatus(tasksNonDeleted, nonDeletedMatchesStatus);
    if (shouldShowDeleted()) {
      filtered = [
        ...filtered,
        ...withScopeAndStatus(tasksDeletedSingular, deletedMatchesStatus),
      ];
    }
    // Customized Overview: parent task rows stay in phase 1 when overdue filter is on.
    if (filters.overdueOnly) {
      // Sub-task overdue inclusion happens in [applyTasksTabRows].
    }
    // Search is applied in [applyTasksTabRows] (token / sub-task aware).
    return filtered;
  }

  /// Task ids to prefetch sub-tasks (includes extra parents for deleted/completed chips).
  static List<String> subtaskPrefetchTaskIds(
    List<Task> phase1,
    AppState state,
    AsanaTaskFilterState filters,
  ) {
    final ids = phase1.map((t) => t.id).toList();
    final have = ids.toSet();
    if (!filters.statuses.contains(AsanaTaskFilterState.statusDeleted) &&
        !filters.statuses.contains(AsanaTaskFilterState.statusCompleted)) {
      return ids;
    }
    const allTeams = <String>{};
    final scope = state
        .tasksForTeams(allTeams)
        .where((t) => t.isSingularTableRow);
    Iterable<Task> it = scope.where((t) => !_singularDeleted(t));
    if (filters.scope == 'assigned') {
      it = it.where((t) => _taskAssignedToCurrentUser(state, t));
    } else if (filters.scope == 'created') {
      it = it.where(state.taskIsCreatedByCurrentUser);
    } else {
      it = it.where((t) => _landingVisible(state, t, 'all'));
    }
    for (final t in it) {
      if (!have.contains(t.id)) {
        ids.add(t.id);
        have.add(t.id);
      }
    }
    return ids;
  }

  /// Merge parents that only appear because of deleted/completed sub-tasks.
  static List<Task> enrichActiveTasks(
    List<Task> phase1,
    AppState state,
    AsanaTaskFilterState filters,
    Map<String, List<SingularSubtask>> grouped,
  ) {
    var active = List<Task>.from(phase1);
    final landingFk = filters.scope;
    if (filters.statuses.contains(AsanaTaskFilterState.statusDeleted)) {
      final have = active.map((t) => t.id).toSet();
      for (final tid in grouped.keys) {
        final sl = grouped[tid] ?? [];
        if (!sl.any((s) => s.isDeleted)) continue;
        if (have.contains(tid)) continue;
        final task = state.taskById(tid);
        if (task == null || !task.isSingularTableRow) continue;
        if (!_landingVisible(state, task, landingFk)) continue;
        final ds = task.dbStatus?.trim().toLowerCase() ?? '';
        if (ds == 'delete' || ds == 'deleted') continue;
        active = [...active, task];
        have.add(tid);
      }
    }
    if (filters.statuses.contains(AsanaTaskFilterState.statusCompleted)) {
      final have = active.map((t) => t.id).toSet();
      for (final tid in grouped.keys) {
        final sl = grouped[tid] ?? [];
        if (!sl.any(_singularSubtaskCompleted)) continue;
        if (have.contains(tid)) continue;
        final task = state.taskById(tid);
        if (task == null || !task.isSingularTableRow) continue;
        if (!_landingVisible(state, task, landingFk)) continue;
        final ds = task.dbStatus?.trim().toLowerCase() ?? '';
        if (ds == 'delete' || ds == 'deleted') continue;
        active = [...active, task];
        have.add(tid);
      }
    }
    if (_overviewCompletedOnlyWithoutIncomplete(filters)) {
      final byId = {for (final t in active) t.id: t};
      const allTeams = <String>{};
      Iterable<Task> scopeIt = state
          .tasksForTeams(allTeams)
          .where((t) => t.isSingularTableRow && !_singularDeleted(t));
      if (filters.scope == 'assigned') {
        scopeIt = scopeIt.where((t) => _taskAssignedToCurrentUser(state, t));
      } else if (filters.scope == 'created') {
        scopeIt = scopeIt.where(state.taskIsCreatedByCurrentUser);
      } else {
        scopeIt = scopeIt.where((t) => _landingVisible(state, t, 'all'));
      }
      for (final t in scopeIt) {
        if (!t.isSingularTableRow || byId.containsKey(t.id)) continue;
        if (!_singularIncomplete(t)) continue;
        if (filters.submissions.isNotEmpty &&
            !filters.submissions.contains(_submissionKey(t))) {
          continue;
        }
        byId[t.id] = t;
      }
      active = byId.values.toList();
    }
    return active;
  }

  /// Tasks-tab rows only â€” mirrors [_buildCustomizedFlatEntries] with `overviewTasksTab`.
  static List<Task> applyTasksTabRows(
    List<Task> activeTasks,
    Map<String, List<SingularSubtask>> grouped,
    AppState state,
    AsanaTaskFilterState filters, {
    required String searchQuery,
  }) {
    final tokens = _searchTokens(searchQuery);
    final searchActive = tokens.isNotEmpty;
    final out = <Task>[];
    for (final t in activeTasks) {
      if (!t.isSingularTableRow) continue;
      final subs = grouped[t.id] ?? [];
      final subsFiltered = subs
          .where((s) => _subtaskPassesStatusChips(s, filters))
          .toList();
      final subsNonDeleted = subsFiltered.where((s) => !s.isDeleted).toList();
      final subsDeleted =
          filters.statuses.contains(AsanaTaskFilterState.statusDeleted)
          ? subsFiltered.where((s) => s.isDeleted).toList()
          : <SingularSubtask>[];
      if (filters.overdueOnly) {
        if (t.overdue == 'Yes') {
          if (!searchActive) {
            if (_rowPassesDueDate(t, null, filters)) out.add(t);
          } else if (_taskTextMatchesAllTokens(t, tokens) &&
              _rowPassesDueDate(t, null, filters)) {
            out.add(t);
          }
        } else {
          var wantParent = false;
          for (final s in subsNonDeleted) {
            if (s.overdue != 'Yes') continue;
            if (_shouldOmitSubtaskRow(t, s, filters)) continue;
            if (!searchActive) {
              if (_rowPassesDueDateSubtask(t, s, filters)) {
                wantParent = true;
                break;
              }
            } else {
              if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
              if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
              wantParent = true;
              break;
            }
          }
          if (!wantParent) {
            for (final s in subsDeleted) {
              if (s.overdue != 'Yes') continue;
              if (_shouldOmitSubtaskRow(t, s, filters)) continue;
              if (!searchActive) {
                if (_rowPassesDueDateSubtask(t, s, filters)) {
                  wantParent = true;
                  break;
                }
              } else {
                if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
                if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
                wantParent = true;
                break;
              }
            }
          }
          if (wantParent &&
              !_hideIncompleteParentWhenCompletedOnly(t, filters)) {
            out.add(t);
          }
        }
        continue;
      }
      if (!searchActive) {
        final subsInRange = subsNonDeleted
            .where((s) => _rowPassesDueDateSubtask(t, s, filters))
            .where((s) => !_shouldOmitSubtaskRow(t, s, filters))
            .toList();
        final subsDeletedInRange = subsDeleted
            .where((s) => _rowPassesDueDateSubtask(t, s, filters))
            .where((s) => !_shouldOmitSubtaskRow(t, s, filters))
            .toList();
        final taskInRange = _rowPassesDueDate(t, null, filters);
        if (!taskInRange && subsInRange.isEmpty && subsDeletedInRange.isEmpty) {
          continue;
        }
        final hasVisibleSubs =
            subsInRange.isNotEmpty || subsDeletedInRange.isNotEmpty;
        final showParent = filters.createDateEngaged
            ? taskInRange
            : (taskInRange || hasVisibleSubs);
        if (showParent &&
            !_hideIncompleteParentWhenCompletedOnly(t, filters)) {
          out.add(t);
        }
        continue;
      }
      final taskTextMatch = _taskTextMatchesAllTokens(t, tokens);
      if (taskTextMatch) {
        if (!_hideIncompleteParentWhenCompletedOnly(t, filters)) {
          out.add(t);
        }
        continue;
      }
      var anySub = false;
      for (final s in subsNonDeleted) {
        if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
        if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
        if (_shouldOmitSubtaskRow(t, s, filters)) continue;
        anySub = true;
        break;
      }
      if (!anySub) {
        for (final s in subsDeleted) {
          if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
          if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
          if (_shouldOmitSubtaskRow(t, s, filters)) continue;
          anySub = true;
          break;
        }
      }
      if (anySub && !_hideIncompleteParentWhenCompletedOnly(t, filters)) {
        out.add(t);
      }
    }
    // Safety net: phase-1 already matched filters; do not hide every parent when
    // sub-task row rules or an empty prefetch would drop them all.
    if (out.isEmpty &&
        activeTasks.isNotEmpty &&
        !searchActive &&
        !filters.overdueOnly &&
        !filters.createDateEngaged) {
      out.addAll(
        activeTasks.where(
          (t) =>
              t.isSingularTableRow &&
              !_hideIncompleteParentWhenCompletedOnly(t, filters),
        ),
      );
    }
    out.sort((a, b) {
      int cmp;
      switch (filters.sortKey) {
        case 'name':
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case 'created':
          cmp = a.createdAt.compareTo(b.createdAt);
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
    return out;
  }

  /// Flat task + sub-task rows for **All tasks & sub-tasks** (no parent expansion).
  static List<AsanaFlatRow> applyAllTasksAndSubtasksFlat(
    List<Task> activeTasks,
    Map<String, List<SingularSubtask>> grouped,
    AppState state,
    AsanaTaskFilterState filters, {
    required String searchQuery,
  }) {
    final tokens = _searchTokens(searchQuery);
    final searchActive = tokens.isNotEmpty;
    final out = <AsanaFlatRow>[];

    for (final t in activeTasks) {
      if (!t.isSingularTableRow) continue;
      final subs = grouped[t.id] ?? [];
      final subsFiltered =
          subs.where((s) => _subtaskPassesStatusChips(s, filters)).toList();
      final subsNonDeleted =
          subsFiltered.where((s) => !s.isDeleted).toList();
      final subsDeleted = filters.statuses.contains(AsanaTaskFilterState.statusDeleted)
          ? subsFiltered.where((s) => s.isDeleted).toList()
          : <SingularSubtask>[];

      void addTaskIfAllowed() {
        if (!_hideIncompleteParentWhenCompletedOnly(t, filters)) {
          out.add(AsanaFlatRow.task(t));
        }
      }

      void addSubsInRange(List<SingularSubtask> list) {
        for (final s in list) {
          if (_shouldOmitSubtaskRow(t, s, filters)) continue;
          if (!searchActive) {
            if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
          } else {
            if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
            if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
          }
          out.add(AsanaFlatRow.subtask(t, s));
        }
      }

      if (filters.overdueOnly) {
        if (t.overdue == 'Yes') {
          if (!searchActive) {
            if (_rowPassesDueDate(t, null, filters)) addTaskIfAllowed();
          } else if (_taskTextMatchesAllTokens(t, tokens) &&
              _rowPassesDueDate(t, null, filters)) {
            addTaskIfAllowed();
          }
        }
        addSubsInRange(subsNonDeleted.where((s) => s.overdue == 'Yes').toList());
        addSubsInRange(subsDeleted.where((s) => s.overdue == 'Yes').toList());
        continue;
      }

      if (!searchActive) {
        final subsInRange = subsNonDeleted
            .where((s) => _rowPassesDueDateSubtask(t, s, filters))
            .where((s) => !_shouldOmitSubtaskRow(t, s, filters))
            .toList();
        final subsDeletedInRange = subsDeleted
            .where((s) => _rowPassesDueDateSubtask(t, s, filters))
            .where((s) => !_shouldOmitSubtaskRow(t, s, filters))
            .toList();
        final taskInRange = _rowPassesDueDate(t, null, filters);
        if (!taskInRange &&
            subsInRange.isEmpty &&
            subsDeletedInRange.isEmpty) {
          continue;
        }
        final showParent = filters.createDateEngaged
            ? taskInRange
            : (taskInRange ||
                subsInRange.isNotEmpty ||
                subsDeletedInRange.isNotEmpty);
        if (showParent) {
          addTaskIfAllowed();
        }
        addSubsInRange(subsInRange);
        addSubsInRange(subsDeletedInRange);
        continue;
      }

      final taskTextMatch = _taskTextMatchesAllTokens(t, tokens);
      if (taskTextMatch) {
        addTaskIfAllowed();
      }
      for (final s in subsNonDeleted) {
        if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
        if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
        if (_shouldOmitSubtaskRow(t, s, filters)) continue;
        out.add(AsanaFlatRow.subtask(t, s));
      }
      for (final s in subsDeleted) {
        if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
        if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
        if (_shouldOmitSubtaskRow(t, s, filters)) continue;
        out.add(AsanaFlatRow.subtask(t, s));
      }
    }

    out.sort((a, b) {
      DateTime? dueA = a.isTask ? a.task.endDate : a.sub!.dueDate;
      DateTime? dueB = b.isTask ? b.task.endDate : b.sub!.dueDate;
      int cmp;
      switch (filters.sortKey) {
        case 'name':
          final na = a.isTask
              ? a.task.name
              : a.sub!.subtaskName;
          final nb = b.isTask
              ? b.task.name
              : b.sub!.subtaskName;
          cmp = na.toLowerCase().compareTo(nb.toLowerCase());
        case 'created':
          final ca = a.isTask ? a.task.createdAt : a.sub!.createDate;
          final cb = b.isTask ? b.task.createdAt : b.sub!.createDate;
          if (ca == null && cb == null) {
            cmp = 0;
          } else if (ca == null) {
            cmp = 1;
          } else if (cb == null) {
            cmp = -1;
          } else {
            cmp = ca.compareTo(cb);
          }
        case 'due':
        default:
          if (dueA == null && dueB == null) {
            cmp = 0;
          } else if (dueA == null) {
            cmp = 1;
          } else if (dueB == null) {
            cmp = -1;
          } else {
            cmp = dueA.compareTo(dueB);
          }
      }
      if (cmp == 0) {
        final na = a.isTask ? a.task.name : a.sub!.subtaskName;
        final nb = b.isTask ? b.task.name : b.sub!.subtaskName;
        cmp = na.toLowerCase().compareTo(nb.toLowerCase());
      }
      return filters.sortAscending ? cmp : -cmp;
    });

    // Same safety net as [applyTasksTabRows]: phase-1 parents are already filter-qualified.
    if (out.isEmpty &&
        activeTasks.isNotEmpty &&
        !searchActive &&
        !filters.overdueOnly &&
        !filters.createDateEngaged) {
      for (final t in activeTasks) {
        if (!t.isSingularTableRow) continue;
        if (_hideIncompleteParentWhenCompletedOnly(t, filters)) continue;
        out.add(AsanaFlatRow.task(t));
        final subs = grouped[t.id] ?? [];
        for (final s in subs) {
          if (!_subtaskPassesStatusChips(s, filters)) continue;
          if (_shouldOmitSubtaskRow(t, s, filters)) continue;
          if (!_rowPassesDueDateSubtask(t, s, filters)) continue;
          out.add(AsanaFlatRow.subtask(t, s));
        }
      }
      out.sort((a, b) {
        DateTime? dueA = a.isTask ? a.task.endDate : a.sub!.dueDate;
        DateTime? dueB = b.isTask ? b.task.endDate : b.sub!.dueDate;
        int cmp;
        switch (filters.sortKey) {
          case 'name':
            final na = a.isTask ? a.task.name : a.sub!.subtaskName;
            final nb = b.isTask ? b.task.name : b.sub!.subtaskName;
            cmp = na.toLowerCase().compareTo(nb.toLowerCase());
          case 'created':
            final ca = a.isTask ? a.task.createdAt : a.sub!.createDate;
            final cb = b.isTask ? b.task.createdAt : b.sub!.createDate;
            if (ca == null && cb == null) {
              cmp = 0;
            } else if (ca == null) {
              cmp = 1;
            } else if (cb == null) {
              cmp = -1;
            } else {
              cmp = ca.compareTo(cb);
            }
          case 'due':
          default:
            if (dueA == null && dueB == null) {
              cmp = 0;
            } else if (dueA == null) {
              cmp = 1;
            } else if (dueB == null) {
              cmp = -1;
            } else {
              cmp = dueA.compareTo(dueB);
            }
        }
        if (cmp == 0) {
          final na = a.isTask ? a.task.name : a.sub!.subtaskName;
          final nb = b.isTask ? b.task.name : b.sub!.subtaskName;
          cmp = na.toLowerCase().compareTo(nb.toLowerCase());
        }
        return filters.sortAscending ? cmp : -cmp;
      });
    }

    return out;
  }

  /// Sub-tasks listed under an expanded task row (show data; status chips only).
  static List<SingularSubtask> subtasksForExpandedPanel(
    List<SingularSubtask> subs,
    AsanaTaskFilterState filters, {
    Task? parentTask,
  }) {
    Iterable<SingularSubtask> it =
        subs.where((s) => _subtaskPassesStatusChips(s, filters));
    if (!filters.statuses.contains(AsanaTaskFilterState.statusDeleted)) {
      it = it.where((s) => !s.isDeleted);
    }
    if (filters.createDateEngaged && parentTask != null) {
      it = it.where(
        (s) => _rowPassesDueDateSubtask(parentTask, s, filters),
      );
    }
    final out = it.toList();
    out.sort((a, b) {
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) {
        return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
      }
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = ad.compareTo(bd);
      if (c != 0) return c;
      return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
    });
    return out;
  }

  /// Sub-tasks that justify showing the parent on the Tasks tab (stricter filters).
  static List<SingularSubtask> visibleSubtasksForTask(
    Task task,
    List<SingularSubtask> subs,
    AsanaTaskFilterState filters, {
    required String searchQuery,
  }) {
    final tokens = _searchTokens(searchQuery);
    final searchActive = tokens.isNotEmpty;

    final subsFiltered =
        subs.where((s) => _subtaskPassesStatusChips(s, filters)).toList();
    final subsNonDeleted =
        subsFiltered.where((s) => !s.isDeleted).toList();
    final subsDeleted = filters.statuses.contains(AsanaTaskFilterState.statusDeleted)
        ? subsFiltered.where((s) => s.isDeleted).toList()
        : <SingularSubtask>[];

    bool includeSub(SingularSubtask s) {
      if (_shouldOmitSubtaskRow(task, s, filters)) return false;
      if (filters.overdueOnly && s.overdue != 'Yes') return false;
      if (!searchActive) {
        return _rowPassesDueDateSubtask(task, s, filters);
      }
      if (!_subtaskTextMatchesAllTokens(s, tokens)) return false;
      return _rowPassesDueDateSubtask(task, s, filters);
    }

    final out = <SingularSubtask>[
      ...subsNonDeleted.where(includeSub),
      ...subsDeleted.where(includeSub),
    ];
    out.sort((a, b) {
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) {
        return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
      }
      if (ad == null) return 1;
      if (bd == null) return -1;
      final c = ad.compareTo(bd);
      if (c != 0) return c;
      return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
    });
    return out;
  }

  /// @deprecated Use [buildPhase1Tasks] + [applyTasksTabRows] with sub-task prefetch.
  static List<Task> apply(
    AppState state,
    AsanaTaskFilterState filters, {
    required String searchQuery,
  }) {
    final phase1 = buildPhase1Tasks(state, filters, searchQuery: searchQuery);
    return applyTasksTabRows(
      phase1,
      const {},
      state,
      filters,
      searchQuery: searchQuery,
    );
  }
}
