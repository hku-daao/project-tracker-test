import 'dart:async';
import 'dart:math' show min;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/initiative.dart';
import '../../models/task.dart';
import '../../models/assignee.dart';
import '../../priority.dart';
import '../../services/landing_task_filters_storage.dart';
import '../../widgets/task_list_card.dart';
import 'initiative_detail_screen.dart';

/// Landing task list sort column (persisted as [storageKey]).
enum TaskListSortColumn {
  creator('creator'),
  assignee('assignee'),
  pic('pic'),
  startDate('startDate'),
  dueDate('dueDate'),
  status('status'),
  submission('submission');

  const TaskListSortColumn(this.storageKey);
  final String storageKey;

  static TaskListSortColumn? fromStorage(String? s) {
    if (s == null || s.isEmpty) return null;
    for (final v in TaskListSortColumn.values) {
      if (v.storageKey == s) return v;
    }
    return null;
  }

  String get label {
    switch (this) {
      case TaskListSortColumn.creator:
        return 'Creator';
      case TaskListSortColumn.assignee:
        return 'Assignee';
      case TaskListSortColumn.pic:
        return 'PIC';
      case TaskListSortColumn.startDate:
        return 'Start date';
      case TaskListSortColumn.dueDate:
        return 'Due date';
      case TaskListSortColumn.status:
        return 'Status';
      case TaskListSortColumn.submission:
        return 'Submission';
    }
  }
}

class InitiativeListScreen extends StatefulWidget {
  const InitiativeListScreen({super.key});

  @override
  State<InitiativeListScreen> createState() => _InitiativeListScreenState();
}

class _InitiativeListScreenState extends State<InitiativeListScreen> {
  /// Landing list column max width ([TaskListCard] + search below filter chips).
  static const double _kLandingTaskListMaxWidth = 1100;

  /// Max width for team / status filter fields (readable on wide layouts).
  static const double _filterFieldMaxWidth = 420;

  /// Selected `Team.id` values. Empty = all teams (default).
  final Set<String> _selectedTeamIds = {};

  /// When exactly one team is selected: subset of that team's member ids to filter by.
  /// Empty = all members (default).
  final Set<String> _selectedAssigneeIds = {};

  /// Scope: `all` | `assigned` | `created` (chips: All, Assigned to me, My created tasks).
  String _filterType = 'all';

  /// Subset of `incomplete` | `completed` | `deleted`. Empty = all statuses (label "All status").
  final Set<String> _selectedTaskStatuses = {};

  /// Subset of [_submissionPending]…[_submissionReturned]. Empty = all (label "All submission").
  final Set<String> _selectedSubmissionFilters = {};
  final TextEditingController _taskSearchController = TextEditingController();
  final MenuController _filterMenuController = MenuController();
  bool _remindersExpanded = false;

  /// Single-column sort for task lists on the landing page (null = default order).
  TaskListSortColumn? _taskSortColumn;
  bool _taskSortAscending = true;

  /// Client-side paging for [TaskListCard] lists (search/filter unchanged; slice after).
  static const List<int> _landingTaskPageSizes = [25, 50, 100, 200];
  int _tasksPageSize = 50;
  int _tasksPageIndex = 0;
  int _deletedTasksPageIndex = 0;

  /// Per-user prefs: do not persist until first load finished (avoids clobbering saved teams).
  bool _landingFiltersPrefsReady = false;

  /// When saved team ids exist but [AppState.teams] is still empty, apply the rest first; then this.
  LandingTaskFilters? _deferredPrefsForTeams;

  AppState? _appStateListenerRef;
  Timer? _searchPersistDebounce;

  /// Skip debounced persist while restoring from disk (search [TextEditingController] updates).
  bool _suppressFilterPersist = false;

  static const _statusIncomplete = 'incomplete';
  static const _statusCompleted = 'completed';
  static const _statusDeleted = 'deleted';

  static const _submissionPending = 'pending';
  static const _submissionSubmitted = 'submitted';
  static const _submissionAccepted = 'accepted';
  static const _submissionReturned = 'returned';

  /// Normalizes [Task.submission] to a landing filter key (defaults to pending when empty/unknown).
  static String _submissionFilterKey(Task t) {
    final raw = t.submission?.trim().toLowerCase() ?? '';
    if (raw.isEmpty || raw == 'pending') return _submissionPending;
    if (raw == 'submitted') return _submissionSubmitted;
    if (raw == 'accepted') return _submissionAccepted;
    if (raw == 'returned') return _submissionReturned;
    return _submissionPending;
  }

  /// On my plate as assignee — dark blue chip when selected.
  Widget _assignedToMeFilterIcon(bool selected) {
    return Icon(
      Icons.assignment_ind,
      size: 18,
      color: selected ? Colors.white : const Color(0xFF0D47A1),
    );
  }

  /// Tasks I created — task icon on "My created tasks".
  Widget _myCreatedTasksFilterIcon(bool selected) {
    return Icon(
      Icons.task_alt,
      size: 18,
      color: selected ? Colors.black87 : Colors.lightBlue.shade800,
    );
  }

  /// Scrollable chips so labels stay on one line on narrow / mobile screens.
  Widget _buildTaskFilterChip({
    required String value,
    required String label,
    required bool selected,
    Color? selectedBg,
    Color? selectedLabelColor,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final Color onLabel;
    if (!selected) {
      onLabel = theme.colorScheme.onSurface;
    } else if (selectedLabelColor != null) {
      onLabel = selectedLabelColor;
    } else if (selectedBg == null) {
      onLabel = theme.colorScheme.onPrimary;
    } else {
      onLabel = theme.colorScheme.onSecondaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        showCheckmark: false,
        avatar: leading,
        label: Text(label, maxLines: 1, softWrap: false),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _filterType = value;
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        selectedColor: selectedBg,
        labelStyle: TextStyle(
          color: onLabel,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  /// Closed field preview: "Team" until user picks one or more teams from the menu.
  String _teamFilterDisplayText(AppState state) {
    if (_selectedTeamIds.isEmpty) return 'Team';
    final names = <String>[];
    for (final team in state.teams) {
      if (_selectedTeamIds.contains(team.id)) names.add(team.name);
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  /// Closed field preview: "Status" until user picks one or more statuses from the menu.
  String _statusFilterDisplayText() {
    if (_selectedTaskStatuses.isEmpty) return 'Status';
    const labels = {
      _statusIncomplete: 'Incomplete',
      _statusCompleted: 'Completed',
      _statusDeleted: 'Deleted',
    };
    const order = [_statusIncomplete, _statusCompleted, _statusDeleted];
    return order
        .where(_selectedTaskStatuses.contains)
        .map((k) => labels[k]!)
        .join(', ');
  }

  String _submissionFilterDisplayText() {
    if (_selectedSubmissionFilters.isEmpty) return 'All submission';
    const labels = {
      _submissionPending: 'Pending',
      _submissionSubmitted: 'Submitted',
      _submissionAccepted: 'Accepted',
      _submissionReturned: 'Returned',
    };
    const order = [
      _submissionPending,
      _submissionSubmitted,
      _submissionAccepted,
      _submissionReturned,
    ];
    return order
        .where(_selectedSubmissionFilters.contains)
        .map((k) => labels[k]!)
        .join(', ');
  }

  /// True when team/status filters, assignee, or search are not at default (all).
  bool get _hasTeamOrStatusFilterSelections =>
      _selectedTeamIds.isNotEmpty ||
      _selectedTaskStatuses.isNotEmpty ||
      _selectedSubmissionFilters.isNotEmpty ||
      _selectedAssigneeIds.isNotEmpty ||
      _taskSearchController.text.trim().isNotEmpty;

  void _clearTeamAndStatusFilters() {
    setState(() {
      _selectedTeamIds.clear();
      _selectedTaskStatuses.clear();
      _selectedSubmissionFilters.clear();
      _selectedAssigneeIds.clear();
      _taskSearchController.clear();
      _tasksPageIndex = 0;
      _deletedTasksPageIndex = 0;
    });
    _persistLandingFilters();
  }

  /// One-line summary inside the closed "Filter" control.
  String _filterMenuSummaryLine(AppState state) {
    final parts = <String>[];
    if (_selectedTeamIds.isEmpty) {
      parts.add('All teams');
    } else {
      parts.add(_teamFilterDisplayText(state));
    }
    if (_selectedTeamIds.length == 1) {
      if (_selectedAssigneeIds.isEmpty) {
        parts.add('All members');
      } else {
        final names =
            _selectedAssigneeIds
                .map((id) => state.assigneeById(id)?.name ?? id)
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        parts.add(names.join(', '));
      }
    }
    if (_selectedTaskStatuses.isEmpty) {
      parts.add('All status');
    } else {
      parts.add(_statusFilterDisplayText());
    }
    if (_selectedSubmissionFilters.isEmpty) {
      parts.add('All submission');
    } else {
      parts.add(_submissionFilterDisplayText());
    }
    return parts.join(' · ');
  }

  /// Each whitespace-separated keyword must appear in [Task.name] or [Task.description] (case-insensitive).
  static bool _taskMatchesLandingSearch(Task t, String query) {
    final tokens = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return true;
    final name = t.name.toLowerCase();
    final desc = t.description.toLowerCase();
    for (final token in tokens) {
      if (!name.contains(token) && !desc.contains(token)) {
        return false;
      }
    }
    return true;
  }

  List<Task> _applyTaskSearch(List<Task> tasks) {
    final raw = _taskSearchController.text.trim();
    if (raw.isEmpty) return tasks;
    return tasks.where((t) => _taskMatchesLandingSearch(t, raw)).toList();
  }

  String _assigneeSortKey(Task t, AppState state) {
    final names =
        t.assigneeIds
            .map((id) => state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  String _picSortKey(Task t, AppState state) {
    final p = t.pic?.trim();
    if (p == null || p.isEmpty) return '';
    return state.assigneeById(p)?.name ?? p;
  }

  static int _cmpStrNullable(String? a, String? b, bool ascending) {
    final sa = a?.trim().toLowerCase() ?? '';
    final sb = b?.trim().toLowerCase() ?? '';
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    final c = sa.compareTo(sb);
    return ascending ? c : -c;
  }

  static int _cmpDateForSort(DateTime? a, DateTime? b, bool ascending) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.compareTo(b);
    return ascending ? c : -c;
  }

  List<Task> _sortTasks(List<Task> tasks, AppState state) {
    if (_taskSortColumn == null) return tasks;
    final col = _taskSortColumn!;
    final asc = _taskSortAscending;
    final out = List<Task>.from(tasks);
    out.sort((a, b) {
      int c;
      switch (col) {
        case TaskListSortColumn.creator:
          c = _cmpStrNullable(a.createByStaffName, b.createByStaffName, asc);
          break;
        case TaskListSortColumn.assignee:
          c = _cmpStrNullable(
            _assigneeSortKey(a, state),
            _assigneeSortKey(b, state),
            asc,
          );
          break;
        case TaskListSortColumn.pic:
          c = _cmpStrNullable(
            _picSortKey(a, state),
            _picSortKey(b, state),
            asc,
          );
          break;
        case TaskListSortColumn.startDate:
          c = _cmpDateForSort(a.startDate, b.startDate, asc);
          break;
        case TaskListSortColumn.dueDate:
          c = _cmpDateForSort(a.endDate, b.endDate, asc);
          break;
        case TaskListSortColumn.status:
          c = _cmpStrNullable(
            TaskListCard.statusLabel(a),
            TaskListCard.statusLabel(b),
            asc,
          );
          break;
        case TaskListSortColumn.submission:
          c = _cmpStrNullable(a.submission, b.submission, asc);
          break;
      }
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  List<Initiative> _applyInitiativeNameSearch(List<Initiative> list) {
    final q = _taskSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((i) => i.name.toLowerCase().contains(q)).toList();
  }

  String _emptyListMessage() {
    if (_taskSearchController.text.trim().isNotEmpty) {
      return 'No tasks match your search.';
    }
    if (_selectedTeamIds.isEmpty) {
      return 'No tasks yet. Create one in the "Create task" tab.';
    }
    return 'No tasks for this filter.';
  }

  @override
  void initState() {
    super.initState();
    _taskSearchController.addListener(_onSearchTextChangedForPersist);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appStateListenerRef = context.read<AppState>();
      _appStateListenerRef!.addListener(_onAppStateForDeferredTeamRestore);
      _loadLandingFilters();
    });
  }

  void _onSearchTextChangedForPersist() {
    if (!_landingFiltersPrefsReady || _suppressFilterPersist) return;
    _searchPersistDebounce?.cancel();
    _searchPersistDebounce = Timer(const Duration(milliseconds: 450), () {
      if (mounted) _persistLandingFilters();
    });
  }

  void _onAppStateForDeferredTeamRestore() {
    if (_deferredPrefsForTeams == null) return;
    final state = context.read<AppState>();
    if (state.teams.isEmpty) return;
    final data = _deferredPrefsForTeams!;
    _deferredPrefsForTeams = null;
    if (!mounted) return;
    setState(() => _applyTeamsAndAssigneesFromSaved(data, state));
    _landingFiltersPrefsReady = true;
  }

  Future<void> _loadLandingFilters() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _landingFiltersPrefsReady = true;
      return;
    }
    final data = await LandingTaskFiltersStorage.load(uid);
    if (!mounted) return;
    final state = context.read<AppState>();
    if (data == null) {
      _landingFiltersPrefsReady = true;
      return;
    }
    final needsDefer = data.teamIds.isNotEmpty && state.teams.isEmpty;
    if (needsDefer) {
      _deferredPrefsForTeams = data;
      setState(() => _applySavedFiltersPartial(data, state));
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted || _landingFiltersPrefsReady) return;
        if (_deferredPrefsForTeams != null &&
            context.read<AppState>().teams.isEmpty) {
          _deferredPrefsForTeams = null;
          _landingFiltersPrefsReady = true;
        }
      });
      return;
    }
    setState(() => _applySavedFiltersFull(data, state));
    _landingFiltersPrefsReady = true;
  }

  void _applySavedFiltersPartial(LandingTaskFilters data, AppState state) {
    var ft = data.filterType;
    if (ft == 'my') ft = 'all';
    if (ft != 'all' && ft != 'assigned' && ft != 'created') ft = 'all';
    _filterType = ft;
    _selectedTaskStatuses.clear();
    for (final s in data.statuses) {
      if (s == _statusIncomplete ||
          s == _statusCompleted ||
          s == _statusDeleted) {
        _selectedTaskStatuses.add(s);
      }
    }
    _selectedSubmissionFilters.clear();
    for (final s in data.submissionFilters) {
      if (s == _submissionPending ||
          s == _submissionSubmitted ||
          s == _submissionAccepted ||
          s == _submissionReturned) {
        _selectedSubmissionFilters.add(s);
      }
    }
    _suppressFilterPersist = true;
    try {
      _taskSearchController.text = data.search;
    } finally {
      _suppressFilterPersist = false;
    }
    _taskSortColumn = TaskListSortColumn.fromStorage(data.sortColumn);
    _taskSortAscending = data.sortAscending;
  }

  void _applyTeamsAndAssigneesFromSaved(LandingTaskFilters data, AppState state) {
    _selectedTeamIds.clear();
    final validTeamIds = state.teams.map((t) => t.id).toSet();
    for (final id in data.teamIds) {
      if (validTeamIds.contains(id)) _selectedTeamIds.add(id);
    }
    _selectedAssigneeIds.clear();
    if (_selectedTeamIds.length == 1) {
      final memberIds = _getTeamMembers(state, _selectedTeamIds.first)
          .map((a) => a.id)
          .toSet();
      for (final id in data.assigneeIds) {
        if (memberIds.contains(id)) _selectedAssigneeIds.add(id);
      }
    }
  }

  void _applySavedFiltersFull(LandingTaskFilters data, AppState state) {
    _applySavedFiltersPartial(data, state);
    _applyTeamsAndAssigneesFromSaved(data, state);
  }

  void _persistLandingFilters() {
    if (!_landingFiltersPrefsReady || _suppressFilterPersist) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    LandingTaskFiltersStorage.save(
      uid,
      LandingTaskFilters(
        filterType: _filterType,
        teamIds: _selectedTeamIds.toList(),
        assigneeIds: _selectedAssigneeIds.toList(),
        statuses: _selectedTaskStatuses.toList(),
        submissionFilters: _selectedSubmissionFilters.toList(),
        search: _taskSearchController.text,
        sortColumn: _taskSortColumn?.storageKey,
        sortAscending: _taskSortAscending,
      ),
    );
  }

  @override
  void dispose() {
    _searchPersistDebounce?.cancel();
    _taskSearchController.removeListener(_onSearchTextChangedForPersist);
    _appStateListenerRef?.removeListener(_onAppStateForDeferredTeamRestore);
    _taskSearchController.dispose();
    super.dispose();
  }

  Widget _buildSortColumnControl(TaskListSortColumn column) {
    final active = _taskSortColumn == column;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Sort by ${column.label}',
        onSelected: (v) {
          setState(() {
            if (v == 'clear') {
              if (_taskSortColumn == column) {
                _taskSortColumn = null;
                _taskSortAscending = true;
              }
            } else if (v == 'asc') {
              _taskSortColumn = column;
              _taskSortAscending = true;
            } else if (v == 'desc') {
              _taskSortColumn = column;
              _taskSortAscending = false;
            }
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'asc', child: Text('Ascending')),
          const PopupMenuItem(value: 'desc', child: Text('Descending')),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clear',
            enabled: active,
            child: const Text('Clear sort'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                column.label,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _taskSortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static int _landingLastPageIndex(int itemCount, int pageSize) {
    if (itemCount <= 0 || pageSize <= 0) return 0;
    return (itemCount - 1) ~/ pageSize;
  }

  static List<T> _landingPageSlice<T>(
    List<T> items,
    int pageIndex,
    int pageSize,
  ) {
    if (items.isEmpty || pageSize <= 0) return const [];
    final last = _landingLastPageIndex(items.length, pageSize);
    final p = pageIndex.clamp(0, last);
    final start = p * pageSize;
    final end = min(start + pageSize, items.length);
    return items.sublist(start, end);
  }

  Widget _buildLandingTaskPaginationBar({
    required BuildContext context,
    required int totalCount,
    required int pageIndex,
    required void Function(int newPageIndex) onPageChanged,
    required bool showPageSizeDropdown,
  }) {
    if (totalCount <= 0) return const SizedBox.shrink();
    final lastPage = _landingLastPageIndex(totalCount, _tasksPageSize);
    final cur = pageIndex.clamp(0, lastPage);
    final from = cur * _tasksPageSize + 1;
    final to = min((cur + 1) * _tasksPageSize, totalCount);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.zero,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (showPageSizeDropdown)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Per page',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _tasksPageSize,
                  items: _landingTaskPageSizes
                      .map(
                        (n) => DropdownMenuItem<int>(
                          value: n,
                          child: Text('$n'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _tasksPageSize = v;
                      _tasksPageIndex = 0;
                      _deletedTasksPageIndex = 0;
                    });
                  },
                ),
              ],
            ),
          Text(
            'Page ${cur + 1} of ${lastPage + 1} · $from–$to of $totalCount',
            style: theme.textTheme.bodySmall,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: cur > 0
                    ? () => onPageChanged(cur - 1)
                    : null,
                child: const Text('Previous'),
              ),
              TextButton(
                onPressed: cur < lastPage
                    ? () => onPageChanged(cur + 1)
                    : null,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Landing Tasks tab — same width as the task list column below.
  Widget _buildLandingTaskSearchField() {
    return TextField(
      controller: _taskSearchController,
      onChanged: (_) {
        setState(() {
          _tasksPageIndex = 0;
          _deletedTasksPageIndex = 0;
        });
      },
      decoration: InputDecoration(
        labelText: 'Search tasks',
        hintText: 'Search by task name, description',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _taskSearchController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  setState(() {
                    _taskSearchController.clear();
                    _tasksPageIndex = 0;
                    _deletedTasksPageIndex = 0;
                  });
                },
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_filterType == 'my') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _filterType = 'all');
          _persistLandingFilters();
        }
      });
    }
    final state = context.watch<AppState>();
    final teamsSorted = [...state.teams]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    var initiatives = state.initiativesForTeams(_selectedTeamIds);
    var tasks = state.tasksForTeams(_selectedTeamIds);

    if (_selectedAssigneeIds.isNotEmpty) {
      initiatives = initiatives
          .where((i) => i.directorIds.any(_selectedAssigneeIds.contains))
          .toList();
      tasks = tasks
          .where((t) => t.assigneeIds.any(_selectedAssigneeIds.contains))
          .toList();
    }

    bool singularDeleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'delete' || s == 'deleted';
    }

    bool singularCompleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'completed' || s == 'complete';
    }

    bool singularIncomplete(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      if (s.isEmpty) return true;
      return s == 'incomplete';
    }

    final tasksNonDeleted = tasks.where((t) => !singularDeleted(t)).toList();
    final tasksDeletedSingular = tasks.where(singularDeleted).toList();
    final mine = state.userStaffAppId?.trim();
    bool hasMine() => mine != null && mine.isNotEmpty;
    bool isAssignedToMe(Task t) => hasMine() && t.assigneeIds.contains(mine!);
    bool isCreatedByMe(Task t) => state.taskIsCreatedByCurrentUser(t);

    final filterKey = _filterType == 'my' ? 'all' : _filterType;

    bool taskMatchesSubmissionSelection(Task t) {
      if (_selectedSubmissionFilters.isEmpty) return true;
      return _selectedSubmissionFilters.contains(_submissionFilterKey(t));
    }

    bool nonDeletedMatchesTaskStatus(Task t) {
      if (_selectedTaskStatuses.isEmpty) {
        return taskMatchesSubmissionSelection(t);
      }
      if (singularDeleted(t)) return false;
      if (t.isSingularTableRow) {
        if (_selectedTaskStatuses.contains(_statusIncomplete) &&
            singularIncomplete(t)) {
          return taskMatchesSubmissionSelection(t);
        }
        if (_selectedTaskStatuses.contains(_statusCompleted) &&
            singularCompleted(t)) {
          return taskMatchesSubmissionSelection(t);
        }
        return false;
      }
      if (_selectedTaskStatuses.contains(_statusIncomplete) &&
          t.status != TaskStatus.done) {
        return taskMatchesSubmissionSelection(t);
      }
      if (_selectedTaskStatuses.contains(_statusCompleted) &&
          t.status == TaskStatus.done) {
        return taskMatchesSubmissionSelection(t);
      }
      return false;
    }

    bool deletedMatchesTaskStatus(Task t) {
      if (!singularDeleted(t)) return false;
      if (_selectedTaskStatuses.isEmpty) return false;
      if (!_selectedTaskStatuses.contains(_statusDeleted)) return false;
      return taskMatchesSubmissionSelection(t);
    }

    bool shouldShowDeletedSection() {
      if (_selectedTaskStatuses.isEmpty) return false;
      return _selectedTaskStatuses.contains(_statusDeleted);
    }

    List<Task> filterTasksWithScopeAndStatus(
      List<Task> source,
      bool Function(Task) statusMatch,
    ) {
      Iterable<Task> it = source;
      if (filterKey == 'assigned') {
        it = it.where(isAssignedToMe);
      } else if (filterKey == 'created') {
        it = it.where(isCreatedByMe);
      }
      return it.where(statusMatch).toList();
    }

    List<Initiative> filteredInitiatives = [];
    List<Task> filteredTasks = [];
    List<Task> filteredDeletedTasks = [];

    if (filterKey == 'all') {
      filteredInitiatives = initiatives;
      filteredTasks = filterTasksWithScopeAndStatus(
        tasksNonDeleted,
        nonDeletedMatchesTaskStatus,
      );
      filteredDeletedTasks = shouldShowDeletedSection()
          ? filterTasksWithScopeAndStatus(
              tasksDeletedSingular,
              deletedMatchesTaskStatus,
            )
          : [];
    } else if (filterKey == 'assigned') {
      filteredInitiatives = [];
      filteredTasks = filterTasksWithScopeAndStatus(
        tasksNonDeleted,
        nonDeletedMatchesTaskStatus,
      );
      filteredDeletedTasks = shouldShowDeletedSection()
          ? filterTasksWithScopeAndStatus(
              tasksDeletedSingular,
              deletedMatchesTaskStatus,
            )
          : [];
    } else if (filterKey == 'created') {
      filteredInitiatives = [];
      filteredTasks = filterTasksWithScopeAndStatus(
        tasksNonDeleted,
        nonDeletedMatchesTaskStatus,
      );
      filteredDeletedTasks = shouldShowDeletedSection()
          ? filterTasksWithScopeAndStatus(
              tasksDeletedSingular,
              deletedMatchesTaskStatus,
            )
          : [];
    }

    filteredInitiatives = _applyInitiativeNameSearch(filteredInitiatives);
    filteredTasks = _applyTaskSearch(filteredTasks);
    filteredTasks = _sortTasks(filteredTasks, state);
    filteredDeletedTasks = _applyTaskSearch(filteredDeletedTasks);
    filteredDeletedTasks = _sortTasks(filteredDeletedTasks, state);

    final pagedTasks = _landingPageSlice(
      filteredTasks,
      _tasksPageIndex,
      _tasksPageSize,
    );
    final pagedDeletedTasks = _landingPageSlice(
      filteredDeletedTasks,
      _deletedTasksPageIndex,
      _tasksPageSize,
    );

    final reminders = state.getPendingRemindersForTeams(_selectedTeamIds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reminders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ExpansionTile(
              title: const Text('Reminders (would send to Directors)'),
              initiallyExpanded: _remindersExpanded,
              onExpansionChanged: (v) => setState(() => _remindersExpanded = v),
              children: reminders
                  .map(
                    (r) => ListTile(
                      title: Text(r.itemName),
                      subtitle: Text(
                        '${r.reminderType} → ${r.recipientNames.join(", ")}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final menuMaxHeight = MediaQuery.sizeOf(context).height * 0.65;

              final wideFilterWidth = min(
                280.0,
                constraints.maxWidth * 0.38,
              ).clamp(120.0, _filterFieldMaxWidth);

              final filterMenu = MenuAnchor(
                controller: _filterMenuController,
                menuChildren: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: SizedBox(
                      width: 320,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: menuMaxHeight),
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                                child: Text(
                                  'Team',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              for (final team in teamsSorted)
                                CheckboxMenuButton(
                                  closeOnActivate: false,
                                  value: _selectedTeamIds.contains(team.id),
                                  onChanged: (bool? v) {
                                    if (v == null) return;
                                    setState(() {
                                      if (v) {
                                        _selectedTeamIds.add(team.id);
                                      } else {
                                        _selectedTeamIds.remove(team.id);
                                      }
                                      if (_selectedTeamIds.length != 1) {
                                        _selectedAssigneeIds.clear();
                                      }
                                      _tasksPageIndex = 0;
                                      _deletedTasksPageIndex = 0;
                                    });
                                    _persistLandingFilters();
                                  },
                  child: Text(team.name),
                ),
                              if (_selectedTeamIds.length == 1) ...[
                                const Divider(height: 24),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    0,
                                    4,
                                    8,
                                  ),
                                  child: Text(
                                    'Team member',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                CheckboxMenuButton(
                                  closeOnActivate: false,
                                  value: _selectedAssigneeIds.isEmpty,
                                  onChanged: (bool? v) {
                                    if (v == null || !v) return;
                                    setState(() {
                                      _selectedAssigneeIds.clear();
                                      _tasksPageIndex = 0;
                                      _deletedTasksPageIndex = 0;
                                    });
                                    _persistLandingFilters();
                                  },
                                  child: const Text('All team members'),
                                ),
                                for (final assignee in _getTeamMembers(
                                  state,
                                  _selectedTeamIds.first,
                                ))
                                  CheckboxMenuButton(
                                    closeOnActivate: false,
                                    value: _selectedAssigneeIds.contains(
                                      assignee.id,
                                    ),
                                    onChanged: (bool? v) {
                                      if (v == null) return;
                                      setState(() {
                                        if (v) {
                                          _selectedAssigneeIds.add(assignee.id);
                                        } else {
                                          _selectedAssigneeIds.remove(
                                            assignee.id,
                                          );
                                        }
                                        _tasksPageIndex = 0;
                                        _deletedTasksPageIndex = 0;
                                      });
                                      _persistLandingFilters();
                                    },
                                    child: Text(assignee.name),
                                  ),
                              ],
                              const Divider(height: 24),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                                child: Text(
                                  'Status',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedTaskStatuses.contains(
                                  _statusIncomplete,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedTaskStatuses.add(
                                        _statusIncomplete,
                                      );
                                    } else {
                                      _selectedTaskStatuses.remove(
                                        _statusIncomplete,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Incomplete'),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedTaskStatuses.contains(
                                  _statusCompleted,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedTaskStatuses.add(
                                        _statusCompleted,
                                      );
                                    } else {
                                      _selectedTaskStatuses.remove(
                                        _statusCompleted,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Completed'),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedTaskStatuses.contains(
                                  _statusDeleted,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedTaskStatuses.add(_statusDeleted);
                                    } else {
                                      _selectedTaskStatuses.remove(
                                        _statusDeleted,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Deleted'),
                              ),
                              const Divider(height: 24),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                                  'Submission',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedSubmissionFilters.contains(
                                  _submissionPending,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedSubmissionFilters.add(
                                        _submissionPending,
                                      );
                                    } else {
                                      _selectedSubmissionFilters.remove(
                                        _submissionPending,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Pending'),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedSubmissionFilters.contains(
                                  _submissionSubmitted,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedSubmissionFilters.add(
                                        _submissionSubmitted,
                                      );
                                    } else {
                                      _selectedSubmissionFilters.remove(
                                        _submissionSubmitted,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Submitted'),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedSubmissionFilters.contains(
                                  _submissionAccepted,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedSubmissionFilters.add(
                                        _submissionAccepted,
                                      );
                                    } else {
                                      _selectedSubmissionFilters.remove(
                                        _submissionAccepted,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Accepted'),
                              ),
                              CheckboxMenuButton(
                                closeOnActivate: false,
                                value: _selectedSubmissionFilters.contains(
                                  _submissionReturned,
                                ),
                                onChanged: (bool? v) {
                                  if (v == null) return;
                                  setState(() {
                                    if (v) {
                                      _selectedSubmissionFilters.add(
                                        _submissionReturned,
                                      );
                                    } else {
                                      _selectedSubmissionFilters.remove(
                                        _submissionReturned,
                                      );
                                    }
                                    _tasksPageIndex = 0;
                                    _deletedTasksPageIndex = 0;
                                  });
                                  _persistLandingFilters();
                                },
                                child: const Text('Returned'),
                              ),
                              const Divider(height: 16),
                              MenuItemButton(
                                closeOnActivate: false,
                                onPressed: _clearTeamAndStatusFilters,
                                leadingIcon: const Icon(
                                  Icons.clear_all,
                                  size: 20,
                                ),
                                child: const Text('Clear all'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                builder: (context, controller, child) {
                  return InkWell(
                    onTap: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
            decoration: const InputDecoration(
                        labelText: 'Filters',
              border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      child: Text(
                        _filterMenuSummaryLine(state),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                },
              );

              final filterWidth = constraints.maxWidth < 600
                  ? min(_filterFieldMaxWidth, constraints.maxWidth)
                  : wideFilterWidth;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: filterWidth),
                      child: filterMenu,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_hasTeamOrStatusFilterSelections)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _clearTeamAndStatusFilters,
                child: const Text('Clear all'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                  _buildTaskFilterChip(
                    value: 'all',
                    label: 'All',
                    selected: filterKey == 'all',
                    selectedBg: null,
                    selectedLabelColor: null,
                    leading: null,
                  ),
                  _buildTaskFilterChip(
                    value: 'assigned',
                    label: 'Assigned to me',
                    selected: filterKey == 'assigned',
                    selectedBg: const Color(0xFF0D47A1),
                    selectedLabelColor: Colors.white,
                    leading: _assignedToMeFilterIcon(filterKey == 'assigned'),
                  ),
                  _buildTaskFilterChip(
                    value: 'created',
                    label: 'My created tasks',
                    selected: filterKey == 'created',
                    selectedBg: Colors.lightBlue.shade200,
                    selectedLabelColor: Colors.black87,
                    leading: _myCreatedTasksFilterIcon(filterKey == 'created'),
                  ),
                      Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: SizedBox(
                      height: 32,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                        child: Text(
                      'Sort',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  for (final col in TaskListSortColumn.values)
                    _buildSortColumnControl(col),
                ],
              ),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final listColumnMaxWidth = min(
              _kLandingTaskListMaxWidth,
              constraints.maxWidth,
            );
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: listColumnMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _buildLandingTaskSearchField(),
                ),
              ),
            );
          },
        ),
        Expanded(
          child:               filteredInitiatives.isEmpty &&
                  filteredTasks.isEmpty &&
                  filteredDeletedTasks.isEmpty
              ? Center(child: Text(_emptyListMessage()))
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _kLandingTaskListMaxWidth,
                          ),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            children: [
                              if (filteredInitiatives.isNotEmpty) ...[
                      Padding(
                                  padding: const EdgeInsets.only(
                                    top: 8,
                                    bottom: 8,
                                  ),
                        child: Text(
                                    'Initiatives',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...filteredInitiatives.map(
                                  (init) => _buildInitiativeCard(
                                    context,
                                    state,
                                    init,
                                  ),
                                ),
                              ],
                              if (filteredTasks.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 16,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    'Tasks (${filteredTasks.length})',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: PicTeamColorLegend(),
                                ),
                                ...pagedTasks.map((t) => TaskListCard(task: t)),
                              ],
                              if (filteredDeletedTasks.isNotEmpty) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 24,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    'Deleted tasks',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                              ),
                        ),
                      ),
                                if (filteredTasks.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: PicTeamColorLegend(),
                                  ),
                                ...pagedDeletedTasks.map(
                                  (t) => TaskListCard(task: t),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (filteredTasks.isNotEmpty ||
                        filteredDeletedTasks.isNotEmpty)
                      Material(
                        elevation: 6,
                        shadowColor: Colors.black26,
                        color: Theme.of(context).colorScheme.surface,
                        child: SafeArea(
                          top: false,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _kLandingTaskListMaxWidth,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  6,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (filteredTasks.isNotEmpty)
                                      _buildLandingTaskPaginationBar(
                                        context: context,
                                        totalCount: filteredTasks.length,
                                        pageIndex: _tasksPageIndex,
                                        onPageChanged: (i) {
                                          setState(() => _tasksPageIndex = i);
                                        },
                                        showPageSizeDropdown: true,
                                      ),
                                    if (filteredTasks.isNotEmpty &&
                                        filteredDeletedTasks.isNotEmpty)
                                      const Divider(height: 12),
                                    if (filteredDeletedTasks.isNotEmpty)
                                      _buildLandingTaskPaginationBar(
                                        context: context,
                                        totalCount:
                                            filteredDeletedTasks.length,
                                        pageIndex: _deletedTasksPageIndex,
                                        onPageChanged: (i) {
                                          setState(
                                            () => _deletedTasksPageIndex = i,
                                          );
                                        },
                                        showPageSizeDropdown: false,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  List<Assignee> _getTeamMembers(AppState state, String teamId) {
    try {
      final team = state.teams.firstWhere((t) => t.id == teamId);
      final allMemberIds = [...team.directorIds, ...team.officerIds];
      return allMemberIds
          .map((id) => state.assigneeById(id))
          .whereType<Assignee>()
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return [];
    }
  }

  static Color _progressColor(int percent) {
    if (percent >= 100) return Colors.green;
    if (percent >= 50) {
      return Color.lerp(Colors.yellow, Colors.green, (percent - 50) / 50)!;
    }
    return Color.lerp(Colors.red, Colors.yellow, percent / 50)!;
  }

  Widget _buildInitiativeCard(
    BuildContext context,
    AppState state,
    Initiative init,
  ) {
    final progress = state.initiativeProgressPercent(init.id);
    final progressColor = _progressColor(progress);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(init.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${priorityToDisplayName(init.priority)} · $progress%'
              '${init.startDate != null ? ' · Start ${DateFormat.yMMMd().format(init.startDate!)}' : ''}'
              '${init.endDate != null ? ' · Due ${DateFormat.yMMMd().format(init.endDate!)}' : ''}',
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              backgroundColor: progressColor.withValues(alpha: 0.3),
            ),
            if (init.directorIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: init.directorIds.map((id) {
                  final a = state.assigneeById(id);
                  final isDirector = state.isDirector(id);
                  return Chip(
                    label: Text(
                      a?.name ?? id,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: isDirector
                        ? Colors.lightBlue.shade100
                        : Colors.purple.shade100,
                  );
                }).toList(),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InitiativeDetailScreen(initiativeId: init.id),
          ),
        ),
      ),
    );
  }
}
