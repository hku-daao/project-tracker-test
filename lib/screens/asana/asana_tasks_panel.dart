import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../services/asana_filter_cookie_storage.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../../widgets/task_list_card.dart';
import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_filter_widgets.dart';
import 'asana_task_filter.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Tasks / All tasks & sub-tasks tab: filter toolbar + Asana-style table.
class AsanaTasksPanel extends StatefulWidget {
  const AsanaTasksPanel({
    super.key,
    required this.palette,
    required this.searchQuery,
    this.flatTasksAndSubtasks = false,
    this.onOpenTask,
    this.onOpenSubtask,
    this.onCreateTask,
    this.refreshToken = 0,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;

  /// When true, show flattened task + sub-task rows (no expand chevrons).
  final bool flatTasksAndSubtasks;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final VoidCallback? onCreateTask;
  final int refreshToken;

  @override
  State<AsanaTasksPanel> createState() => _AsanaTasksPanelState();
}

class _AsanaTasksPanelState extends State<AsanaTasksPanel> {
  final _filters = AsanaTaskFilterState();
  List<Task> _displayTasks = [];
  List<AsanaFlatRow> _displayFlatRows = [];
  Map<String, List<SingularSubtask>> _groupedSubtasks = {};
  Map<String, int> _subtaskCountByTaskId = {};
  final Set<String> _expandedTaskIds = {};
  bool _filtersReady = false;
  bool _loadingTasks = true;
  int _listGeneration = 0;
  String _tasksDataSig = '';

  String get _cookieStorageKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final tab = widget.flatTasksAndSubtasks ? 'all_tasks_subtasks' : 'tasks';
    return uid == null || uid.isEmpty
        ? 'asana_filters_$tab'
        : 'asana_filters_${tab}_$uid';
  }

  @override
  void initState() {
    super.initState();
    _loadSavedFilters();
  }

  @override
  void didUpdateWidget(covariant AsanaTasksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_filtersReady) return;
    if (oldWidget.flatTasksAndSubtasks != widget.flatTasksAndSubtasks) {
      _loadSavedFilters();
      return;
    }
    if (oldWidget.searchQuery != widget.searchQuery) {
      _rebuildTaskList(showBlockingOverlay: false);
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _rebuildTaskList();
    }
  }

  Future<void> _loadSavedFilters() async {
    setState(() => _filtersReady = false);
    _filters.resetToDefaults();
    final cookieData = AsanaFilterCookieStorage.load(_cookieStorageKey);
    if (cookieData != null && mounted) {
      setState(() => _filters.applyCookieJson(cookieData));
    }
    if (!mounted) return;
    setState(() => _filtersReady = true);
    _rebuildTaskList();
  }

  Future<void> _rebuildTaskList({bool showBlockingOverlay = true}) async {
    if (!mounted || !_filtersReady) return;
    final gen = ++_listGeneration;
    if (showBlockingOverlay) {
      AsanaBlockingLoadingOverlay.show(context);
    }
    setState(() => _loadingTasks = true);

    try {
      final state = context.read<AppState>();
      final phase1 = AsanaTaskFilter.buildPhase1Tasks(
        state,
        _filters,
        searchQuery: widget.searchQuery,
      );
      final prefetchIds = AsanaTaskFilter.subtaskPrefetchTaskIds(
        phase1,
        state,
        _filters,
      );

      Map<String, List<SingularSubtask>> grouped = {};
      if (prefetchIds.isNotEmpty) {
        try {
          grouped =
              await SupabaseService.fetchSubtasksGroupedForLandingPrefetch(
                prefetchIds,
              );
        } catch (_) {
          // List still renders from phase-1 when sub-task fetch fails.
        }
      }

      if (!mounted || gen != _listGeneration) return;

      final active = AsanaTaskFilter.enrichActiveTasks(
        phase1,
        state,
        _filters,
        grouped,
      );
      final tasks = widget.flatTasksAndSubtasks
          ? <Task>[]
          : AsanaTaskFilter.applyTasksTabRows(
              active,
              grouped,
              state,
              _filters,
              searchQuery: widget.searchQuery,
            );
      final flatRows = widget.flatTasksAndSubtasks
          ? AsanaTaskFilter.applyAllTasksAndSubtasksFlat(
              active,
              grouped,
              state,
              _filters,
              searchQuery: widget.searchQuery,
            )
          : <AsanaFlatRow>[];

      if (kDebugMode) {
        final prefetchedSubs = grouped.values.fold<int>(
          0,
          (sum, list) => sum + list.length,
        );
        final flatTaskRows = flatRows.where((r) => r.isTask).length;
        final flatSubRows = flatRows.length - flatTaskRows;
        debugPrint(
          'AsanaTasksPanel: mode=${widget.flatTasksAndSubtasks ? "flat" : "tasks"} '
          'AppState.tasks=${state.tasks.length} phase1=${phase1.length} '
          'active=${active.length} prefetchIds=${prefetchIds.length} '
          'prefetchedSubs=$prefetchedSubs displayTasks=${tasks.length} '
          'flatRows=${flatRows.length} (tasks=$flatTaskRows subs=$flatSubRows) '
          'scoped=${state.tasksLoadedWithVisibilityScope} '
          'statuses=${_filters.statuses} submissions=${_filters.submissions}',
        );
      }

      setState(() {
        _displayTasks = tasks;
        _displayFlatRows = flatRows;
        _groupedSubtasks = grouped;
        _subtaskCountByTaskId = {
          for (final e in grouped.entries)
            e.key: e.value.where((s) => !s.isDeleted).length,
        };
        if (!widget.flatTasksAndSubtasks) {
          _expandedTaskIds.removeWhere((id) => !tasks.any((t) => t.id == id));
        }
        _loadingTasks = false;
      });
    } finally {
      if (showBlockingOverlay) {
        AsanaBlockingLoadingOverlay.hide();
      }
      if (mounted && gen == _listGeneration && _loadingTasks) {
        setState(() => _loadingTasks = false);
      }
    }
  }

  void _onFiltersChanged() {
    AsanaFilterCookieStorage.save(_cookieStorageKey, _filters.toCookieJson());
    _rebuildTaskList();
  }

  Future<void> _ensureSubtasksLoaded(String taskId) async {
    final existing = _groupedSubtasks[taskId];
    if (existing != null && existing.isNotEmpty) return;
    try {
      final list = await SupabaseService.fetchSubtasksForTask(taskId);
      if (!mounted) return;
      setState(() {
        _groupedSubtasks[taskId] = list;
        _subtaskCountByTaskId[taskId] = list.where((s) => !s.isDeleted).length;
      });
    } catch (_) {
      // Keep expand UI; rows may stay empty until prefetch succeeds.
    }
  }

  void _toggleTaskExpanded(String taskId) {
    final opening = !_expandedTaskIds.contains(taskId);
    setState(() {
      if (opening) {
        _expandedTaskIds.add(taskId);
      } else {
        _expandedTaskIds.remove(taskId);
      }
    });
    if (opening) {
      unawaited(_ensureSubtasksLoaded(taskId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState state;
    try {
      state = context.watch<AppState>();
    } catch (e) {
      return ColoredBox(
        color: widget.palette.panelBackground,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load tasks. Open this screen from the main app after sign-in.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final taskSig = _tasksContentSig(state.tasks);
    if (_filtersReady && taskSig != _tasksDataSig) {
      _tasksDataSig = taskSig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildTaskList();
      });
    }

    final tasks = _displayTasks;
    final flatRows = _displayFlatRows;
    final rowCount = widget.flatTasksAndSubtasks
        ? flatRows.length
        : tasks.length;
    final theme = Theme.of(context);
    final tableColors = widget.palette.tableColors;
    final compactTitle = MediaQuery.sizeOf(context).width < 600;

    if (!_filtersReady ||
        (_loadingTasks && _displayTasks.isEmpty && _displayFlatRows.isEmpty)) {
      return ColoredBox(color: widget.palette.panelBackground);
    }

    return ColoredBox(
      color: widget.palette.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _scopeSectionTitle(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: compactTitle ? 14 : 18,
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                  height: 1.25,
                ),
                maxLines: compactTitle ? 1 : null,
                overflow: compactTitle
                    ? TextOverflow.ellipsis
                    : TextOverflow.visible,
              ),
            ),
          ),
          AsanaPanelFilterToolbar(
            palette: widget.palette,
            createLabel: 'Create Task',
            onCreate: widget.onCreateTask ?? () {},
            onClearAll: () {
              setState(_filters.resetForClearAll);
              _onFiltersChanged();
            },
            filterChildren: [
              AsanaFilterDropdown(
                title: 'Scope',
                value: _scopeLabel(),
                buttonWidth: 148,
                onPressed: _showScopeMenu,
              ),
              AsanaFilterDropdown(
                title: 'Status',
                value: _statusLabel(),
                onPressed: _showStatusMenu,
              ),
              AsanaFilterDropdown(
                title: 'Submission',
                value: _submissionLabel(),
                onPressed: _showSubmissionMenu,
              ),
              AsanaFilterDropdown(
                title: 'Creator',
                value: _creatorLabel(state),
                onPressed: _showCreatorMenu,
              ),
              AsanaFilterDropdown(
                title: 'PIC',
                value: _picLabel(state),
                onPressed: _showPicMenu,
              ),
              AsanaFilterDropdown(
                title: 'Due date',
                value: _dueDateLabel(),
                buttonWidth: 168,
                onPressed: _showDueDateRangePicker,
              ),
              AsanaFilterDropdown(
                title: 'Sort',
                value: _sortLabel(),
                buttonWidth: 136,
                onPressed: _showSortMenu,
              ),
              AsanaFilterDropdown(
                title: 'Overdue',
                value: _overdueLabel(),
                onPressed: _showOverdueMenu,
              ),
            ],
          ),
          Expanded(
            child: AsanaPanelListSurface(
              palette: widget.palette,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mobileFlatList =
                      widget.flatTasksAndSubtasks && constraints.maxWidth < 600;
                  final mobileTaskList =
                      !widget.flatTasksAndSubtasks &&
                      constraints.maxWidth < 600;
                  final tableWidth =
                      constraints.maxWidth < _TaskTableLayout.minTableWidth
                      ? _TaskTableLayout.minTableWidth
                      : constraints.maxWidth;
                  if (rowCount == 0) {
                    return Center(
                      child: Text(
                        widget.flatTasksAndSubtasks
                            ? 'No tasks or sub-tasks match your filters.'
                            : 'No tasks match your filters.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  if (mobileFlatList) {
                    return ListView.builder(
                      itemCount: rowCount,
                      itemBuilder: (context, index) {
                        final row = flatRows[index];
                        final sub = row.sub;
                        final isSub = sub != null;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (index > 0)
                              Divider(height: 1, color: Colors.grey.shade300),
                            _FlatMobileRow(
                              tableColors: tableColors,
                              appState: state,
                              task: row.task,
                              subtask: sub,
                              onTap: isSub
                                  ? () => widget.onOpenSubtask?.call(sub.id)
                                  : () => widget.onOpenTask?.call(row.task.id),
                            ),
                          ],
                        );
                      },
                    );
                  }
                  if (mobileTaskList) {
                    return ListView.builder(
                      itemCount: rowCount,
                      itemBuilder: (context, index) {
                        final t = tasks[index];
                        final subCount = _subtaskCountByTaskId[t.id] ?? 0;
                        final rawSubs = _groupedSubtasks[t.id] ?? [];
                        final expandedSubs =
                            AsanaTaskFilter.subtasksForExpandedPanel(
                              rawSubs,
                              _filters,
                              parentTask: t,
                            );
                        final visibleSubCount = subCount > 0
                            ? subCount
                            : rawSubs.where((s) => !s.isDeleted).length;
                        final expanded = _expandedTaskIds.contains(t.id);
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (index > 0)
                              Divider(height: 1, color: Colors.grey.shade300),
                            _FlatMobileRow(
                              tableColors: tableColors,
                              appState: state,
                              task: t,
                              onTap: () => widget.onOpenTask?.call(t.id),
                              expandControl: visibleSubCount > 0
                                  ? _ExpandChevron(
                                      expanded: expanded,
                                      onPressed: () =>
                                          _toggleTaskExpanded(t.id),
                                    )
                                  : null,
                            ),
                            if (visibleSubCount > 0)
                              _AnimatedSubtaskExpansion(
                                expanded: expanded,
                                child: ColoredBox(
                                  color: tableColors.subtaskSection,
                                  child: Column(
                                    children: [
                                      if (expandedSubs.isEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              'No visible sub-tasks',
                                              style: asanaTableRowValueStyle(
                                                context,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        for (
                                          var i = 0;
                                          i < expandedSubs.length;
                                          i++
                                        ) ...[
                                          if (i > 0)
                                            Divider(
                                              height: 1,
                                              color: Colors.grey.shade300,
                                            ),
                                          _FlatMobileRow(
                                            tableColors: tableColors,
                                            appState: state,
                                            task: t,
                                            subtask: expandedSubs[i],
                                            onTap: () => widget.onOpenSubtask
                                                ?.call(expandedSubs[i].id),
                                          ),
                                        ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  }
                  final table = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TableHeaderRow(
                        tableWidth: tableWidth,
                        flatList: widget.flatTasksAndSubtasks,
                      ),
                      Divider(height: 1, color: Colors.grey.shade300),
                      Expanded(
                        child: ListView.builder(
                          itemCount: rowCount,
                          itemBuilder: (context, index) {
                            if (widget.flatTasksAndSubtasks) {
                              final row = flatRows[index];
                              final sub = row.sub;
                              final isSub = sub != null;
                              final name = isSub
                                  ? (sub.subtaskName.trim().isEmpty
                                        ? '(Unnamed sub-task)'
                                        : sub.subtaskName.trim())
                                  : row.task.name;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (index > 0)
                                    Divider(
                                      height: 1,
                                      color: Colors.grey.shade300,
                                    ),
                                  _ItemTableRow(
                                    tableWidth: tableWidth,
                                    tableColors: tableColors,
                                    appState: state,
                                    onRowTap: isSub
                                        ? () =>
                                              widget.onOpenSubtask?.call(sub.id)
                                        : () => widget.onOpenTask?.call(
                                            row.task.id,
                                          ),
                                    projectName: row.task.projectName ?? '—',
                                    name: name,
                                    isSubtask: isSub,
                                    completed: isSub
                                        ? _subtaskCompleted(sub)
                                        : _taskCompleted(row.task),
                                    dueDate: isSub
                                        ? sub.dueDate
                                        : row.task.endDate,
                                    creator: isSub
                                        ? sub.createByStaffName
                                        : row.task.createByStaffName,
                                    picKey: isSub ? sub.pic : row.task.pic,
                                    priority: isSub
                                        ? sub.priority
                                        : row.task.priority,
                                    status: isSub
                                        ? sub.status
                                        : TaskListCard.statusLabel(row.task),
                                    submission: isSub
                                        ? sub.submission
                                        : row.task.submission,
                                  ),
                                ],
                              );
                            }
                            final t = tasks[index];
                            final subCount = _subtaskCountByTaskId[t.id] ?? 0;
                            final rawSubs = _groupedSubtasks[t.id] ?? [];
                            final expandedSubs =
                                AsanaTaskFilter.subtasksForExpandedPanel(
                                  rawSubs,
                                  _filters,
                                  parentTask: t,
                                );
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (index > 0)
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                _ExpandableTaskTableRow(
                                  tableWidth: tableWidth,
                                  tableColors: tableColors,
                                  task: t,
                                  appState: state,
                                  onOpenTask: widget.onOpenTask,
                                  onOpenSubtask: widget.onOpenSubtask,
                                  subtaskCount: subCount > 0
                                      ? subCount
                                      : rawSubs
                                            .where((s) => !s.isDeleted)
                                            .length,
                                  expandedSubtasks: expandedSubs,
                                  expanded: _expandedTaskIds.contains(t.id),
                                  onToggleExpand: () =>
                                      _toggleTaskExpanded(t.id),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );
                  if (constraints.maxWidth < _TaskTableLayout.minTableWidth) {
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          height: constraints.maxHeight,
                          child: table,
                        ),
                      ),
                    );
                  }
                  return table;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _scopeLabel() {
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all'))
      return 'All';
    final labels = <String>[];
    if (_filters.scopes.contains('assigned')) labels.add('Assigned to me');
    if (_filters.scopes.contains('created')) labels.add('Created by me');
    if (labels.isNotEmpty) return labels.join(', ');
    return '${_filters.scopes.length} selected';
  }

  String _scopeSectionTitle() {
    final prefix = widget.flatTasksAndSubtasks ? 'Tasks/Sub-tasks' : 'Tasks';
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all')) {
      return '$prefix created by or assigned to my team';
    }
    if (_filters.scopes.length == 1) {
      if (_filters.scopes.contains('assigned')) return '$prefix assigned to me';
      if (_filters.scopes.contains('created')) return '$prefix created by me';
    }
    if (_filters.scopes.contains('assigned') &&
        _filters.scopes.contains('created')) {
      return '$prefix created by or assigned to me';
    }
    return '$prefix (Multiple scopes)';
  }

  String _statusLabel() {
    if (_filters.statuses.isEmpty) return 'All';
    const labels = {
      AsanaTaskFilterState.statusIncomplete: 'Incomplete',
      AsanaTaskFilterState.statusCompleted: 'Completed',
      AsanaTaskFilterState.statusDeleted: 'Deleted',
    };
    return _filters.statuses.map((k) => labels[k] ?? k).join(', ');
  }

  String _submissionLabel() {
    if (_filters.submissions.isEmpty) return 'All';
    const labels = {
      AsanaTaskFilterState.submissionPending: 'Pending',
      AsanaTaskFilterState.submissionSubmitted: 'Submitted',
      AsanaTaskFilterState.submissionAccepted: 'Accepted',
      AsanaTaskFilterState.submissionReturned: 'Returned',
    };
    return _filters.submissions.map((k) => labels[k] ?? k).join(', ');
  }

  String _staffFilterLabel(AppState state, List<String> ids) {
    if (ids.isEmpty) return 'All';
    if (ids.length == 1)
      return state.assigneeById(ids.first)?.name ?? ids.first;
    return '${ids.length} selected';
  }

  String _creatorLabel(AppState state) =>
      _staffFilterLabel(state, _filters.creatorStaffIds);

  String _picLabel(AppState state) =>
      _staffFilterLabel(state, _filters.picStaffIds);

  String _dueDateLabel() {
    final s = _filters.createDateStart;
    final e = _filters.createDateEnd;
    if (s == null && e == null) return 'All';
    if (s != null && e != null) {
      return '${HkTime.formatInstantAsHk(s, 'MMM d')} – ${HkTime.formatInstantAsHk(e, 'MMM d')}';
    }
    if (s != null) {
      return 'From ${HkTime.formatInstantAsHk(s, 'MMM d')}';
    }
    return 'To ${HkTime.formatInstantAsHk(e!, 'MMM d')}';
  }

  String _overdueLabel() =>
      _filters.overdueOptions.contains('overdue') ? 'Overdue only' : 'All';

  List<AsanaFilterCheckboxOption> _staffOptions(
    AppState state,
    Iterable<String?> ids,
  ) {
    final map = <String, String>{};
    for (final raw in ids) {
      final id = raw?.trim();
      if (id == null || id.isEmpty) continue;
      map[id] = state.assigneeById(id)?.name.trim() ?? id;
    }
    final list = map.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return [
      const AsanaFilterCheckboxOption(
        key: '__all__',
        label: 'All',
        isAll: true,
      ),
      for (final a in list)
        AsanaFilterCheckboxOption(key: a.key, label: a.value),
    ];
  }

  Iterable<String?> _visibleCreatorIds() sync* {
    if (widget.flatTasksAndSubtasks) {
      for (final row in _displayFlatRows) {
        yield row.sub?.createByStaffId ?? row.task.createByAssigneeKey;
      }
      return;
    }
    for (final task in _displayTasks) {
      yield task.createByAssigneeKey;
    }
  }

  Iterable<String?> _visiblePicIds() sync* {
    if (widget.flatTasksAndSubtasks) {
      for (final row in _displayFlatRows) {
        yield row.sub?.pic ?? row.task.pic;
      }
      return;
    }
    for (final task in _displayTasks) {
      yield task.pic;
    }
  }

  Future<void> _showDueDateRangePicker(BuildContext buttonContext) async {
    final all = await showMenu<bool>(
      context: buttonContext,
      position: _menuPosition(buttonContext),
      initialValue: !_filters.createDateEngaged,
      color: Theme.of(buttonContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      items: const [
        PopupMenuItem(value: true, child: Text('All')),
        PopupMenuItem(value: false, child: Text('Choose date range')),
      ],
    );
    if (all == null) return;
    if (all) {
      setState(() {
        _filters.createDateStart = null;
        _filters.createDateEnd = null;
      });
      _onFiltersChanged();
      return;
    }
    final picked = await showAsanaAnchoredDateRangePicker(
      anchorContext: buttonContext,
      start: _filters.createDateStart,
      end: _filters.createDateEnd,
    );
    if (picked == null) return;
    setState(() {
      _filters.createDateStart = asanaDateOnlyFromPicker(picked.start);
      _filters.createDateEnd = asanaDateOnlyFromPicker(picked.end);
    });
    _onFiltersChanged();
  }

  Future<void> _showCreatorMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _staffOptions(state, _visibleCreatorIds()),
      initialSelection: _filters.creatorStaffIds.toSet(),
    );
    if (selection != null) {
      setState(() => _filters.creatorStaffIds = selection.toList());
      _onFiltersChanged();
    }
  }

  Future<void> _showPicMenu(BuildContext buttonContext) async {
    final state = context.read<AppState>();
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: _staffOptions(state, _visiblePicIds()),
      initialSelection: _filters.picStaffIds.toSet(),
    );
    if (selection != null) {
      setState(() => _filters.picStaffIds = selection.toList());
      _onFiltersChanged();
    }
  }

  String _sortLabel() {
    final name = switch (_filters.sortKey) {
      'name' => 'Name',
      'created' => 'Created',
      'updated' => 'Last updated',
      _ => 'Due date',
    };
    final arrow = _filters.sortAscending ? '↑' : '↓';
    return '$name $arrow';
  }

  Future<void> _showScopeMenu(BuildContext buttonContext) async {
    const allKey = 'all';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: const [
        AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        AsanaFilterCheckboxOption(key: 'assigned', label: 'Assigned to me'),
        AsanaFilterCheckboxOption(key: 'created', label: 'Created by me'),
      ],
      initialSelection: _filters.scopes,
    );
    if (selection != null) {
      setState(() => _filters.scopes = selection);
      _onFiltersChanged();
    }
  }

  Future<void> _showStatusMenu(BuildContext buttonContext) async {
    const allKey = '__all__';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: const [
        AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.statusIncomplete,
          label: 'Incomplete',
        ),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.statusCompleted,
          label: 'Completed',
        ),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.statusDeleted,
          label: 'Deleted',
        ),
      ],
      initialSelection: _filters.statuses,
    );
    if (selection != null) {
      setState(() => _filters.statuses = selection);
      _onFiltersChanged();
    }
  }

  Future<void> _showSubmissionMenu(BuildContext buttonContext) async {
    const allKey = '__all__';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: const [
        AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.submissionPending,
          label: 'Pending',
        ),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.submissionSubmitted,
          label: 'Submitted',
        ),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.submissionAccepted,
          label: 'Accepted',
        ),
        AsanaFilterCheckboxOption(
          key: AsanaTaskFilterState.submissionReturned,
          label: 'Returned',
        ),
      ],
      initialSelection: _filters.submissions,
    );
    if (selection != null) {
      setState(() => _filters.submissions = selection);
      _onFiltersChanged();
    }
  }

  Future<void> _showOverdueMenu(BuildContext buttonContext) async {
    const allKey = 'all';
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: const [
        AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        AsanaFilterCheckboxOption(key: 'overdue', label: 'Overdue only'),
      ],
      initialSelection: _filters.overdueOptions,
    );
    if (selection != null) {
      setState(() => _filters.overdueOptions = selection);
      _onFiltersChanged();
    }
  }

  Future<void> _showSortMenu(BuildContext buttonContext) async {
    await showMenu<String>(
      context: buttonContext,
      position: _menuPosition(buttonContext),
      color: Theme.of(buttonContext).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      items: const [
        PopupMenuItem(value: 'due_asc', child: Text('Due date ↑')),
        PopupMenuItem(value: 'due_desc', child: Text('Due date ↓')),
        PopupMenuItem(value: 'created_desc', child: Text('Created ↓')),
        PopupMenuItem(value: 'created_asc', child: Text('Created ↑')),
        PopupMenuItem(value: 'updated_desc', child: Text('Last updated ↓')),
        PopupMenuItem(value: 'updated_asc', child: Text('Last updated ↑')),
        PopupMenuItem(value: 'name_asc', child: Text('Name A–Z')),
        PopupMenuItem(value: 'name_desc', child: Text('Name Z–A')),
      ],
    ).then((v) {
      if (v == null) return;
      setState(() {
        switch (v) {
          case 'due_desc':
            _filters.sortKey = 'due';
            _filters.sortAscending = false;
          case 'created_desc':
            _filters.sortKey = 'created';
            _filters.sortAscending = false;
          case 'created_asc':
            _filters.sortKey = 'created';
            _filters.sortAscending = true;
          case 'updated_desc':
            _filters.sortKey = 'updated';
            _filters.sortAscending = false;
          case 'updated_asc':
            _filters.sortKey = 'updated';
            _filters.sortAscending = true;
          case 'name_asc':
            _filters.sortKey = 'name';
            _filters.sortAscending = true;
          case 'name_desc':
            _filters.sortKey = 'name';
            _filters.sortAscending = false;
          default:
            _filters.sortKey = 'due';
            _filters.sortAscending = true;
        }
      });
      _onFiltersChanged();
    });
  }

  RelativeRect _menuPosition(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return const RelativeRect.fromLTRB(0, 80, 200, 0);
    }
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    return RelativeRect.fromLTRB(
      offset.dx,
      offset.dy + size.height,
      offset.dx + size.width,
      offset.dy + size.height + 4,
    );
  }
}

/// Column widths for the Asana-style task table (fixed layout, no [Expanded] in scroll).
class _TaskTableLayout {
  _TaskTableLayout(this.tableWidth);

  final double tableWidth;

  static const double minTableWidth = 1184;
  static const double typeCol = 48;
  static const double typeColGap = 10;

  /// Reserved before task name text (expand chevron or empty) so names align.
  static const double nameGutter = 36;

  /// Plain-text columns (name, due, project, creator, PIC) each followed by a gap.
  static const int textColumnGapCount = 5;

  /// Fixed height for name gutter + single-line row alignment.
  static const double singleLineExtent = 24;
  static const double hPad = 12;
  static const double submissionColWidth = 116;

  static const double _flexWeightSum =
      0.29 + 0.065 + 0.11 + 0.075 + 0.075 + 0.0665;

  late final double _inner =
      (tableWidth -
              typeCol -
              typeColGap -
              kAsanaTextColumnGap * textColumnGapCount -
              hPad * 2 -
              kAsanaTableStatusColWidth -
              submissionColWidth)
          .clamp(400, double.infinity);

  double get taskNameCol => _inner * (0.29 / _flexWeightSum);
  double get dueCol => _inner * (0.065 / _flexWeightSum);
  double get projectCol => _inner * (0.11 / _flexWeightSum);
  double get creatorCol => _inner * (0.075 / _flexWeightSum);
  double get picCol => _inner * (0.075 / _flexWeightSum);
  double get priorityCol => _inner * (0.0665 / _flexWeightSum);
  double get statusCol => kAsanaTableStatusColWidth;
  double get submissionCol => submissionColWidth;
}

TextStyle? _taskTableHeaderStyle(BuildContext context) =>
    asanaTableHeaderStyle(context);

class _TableHeaderRow extends StatelessWidget {
  const _TableHeaderRow({required this.tableWidth, this.flatList = false});

  final double tableWidth;
  final bool flatList;

  @override
  Widget build(BuildContext context) {
    final cols = _TaskTableLayout(tableWidth);
    final style = _taskTableHeaderStyle(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _TaskTableLayout.hPad,
        vertical: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _TaskTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _TaskTableLayout.typeColGap),
          SizedBox(
            width: cols.taskNameCol,
            child: Row(
              children: [
                const SizedBox(width: _TaskTableLayout.nameGutter),
                Expanded(
                  child: Text(
                    flatList ? 'Task / Sub-task Name' : 'Task Name',
                    style: style,
                  ),
                ),
              ],
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.dueCol,
            label: 'Due Date',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.projectCol,
            label: 'Project',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.priorityCol,
            label: 'Priority',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.submissionCol,
            label: 'Submission',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
        ],
      ),
    );
  }
}

class _ExpandableTaskTableRow extends StatelessWidget {
  const _ExpandableTaskTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.task,
    required this.appState,
    required this.subtaskCount,
    required this.expandedSubtasks,
    required this.expanded,
    required this.onToggleExpand,
    this.onOpenTask,
    this.onOpenSubtask,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final Task task;
  final AppState appState;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;
  final int subtaskCount;
  final List<SingularSubtask> expandedSubtasks;
  final bool expanded;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final hasSubs = subtaskCount > 0;

    return SizedBox(
      width: tableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ItemTableRow(
            tableWidth: tableWidth,
            tableColors: tableColors,
            appState: appState,
            onRowTap: () => onOpenTask?.call(task.id),
            projectName: task.projectName ?? '—',
            name: task.name,
            isSubtask: false,
            completed: _taskCompleted(task),
            dueDate: task.endDate,
            creator: task.createByStaffName,
            picKey: task.pic,
            priority: task.priority,
            status: TaskListCard.statusLabel(task),
            submission: task.submission,
            expandControl: hasSubs
                ? _ExpandChevron(expanded: expanded, onPressed: onToggleExpand)
                : null,
          ),
          if (hasSubs)
            _AnimatedSubtaskExpansion(
              expanded: expanded,
              child: ColoredBox(
                color: tableColors.subtaskSection,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SubtaskSectionHeader(tableWidth: tableWidth),
                      if (expandedSubtasks.isEmpty)
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            _TaskTableLayout.hPad +
                                _TaskTableLayout.typeCol +
                                _TaskTableLayout.typeColGap +
                                _TaskTableLayout.nameGutter,
                            8,
                            16,
                            12,
                          ),
                          child: Text(
                            'No sub-tasks to display.',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: kAsanaTextSecondary),
                          ),
                        ),
                      for (var i = 0; i < expandedSubtasks.length; i++)
                        _SubtaskDataRow(
                          tableWidth: tableWidth,
                          tableColors: tableColors,
                          appState: appState,
                          parent: task,
                          subtask: expandedSubtasks[i],
                          showDivider: i > 0,
                          onOpenSubtask: onOpenSubtask,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedSubtaskExpansion extends StatelessWidget {
  const _AnimatedSubtaskExpansion({
    required this.expanded,
    required this.child,
  });

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        offset: expanded ? Offset.zero : const Offset(0, -0.08),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: expanded ? child : const SizedBox(width: double.infinity),
        ),
      ),
    );
  }
}

/// One expanded sub-task line — same columns and values as the parent task row.
class _SubtaskDataRow extends StatelessWidget {
  const _SubtaskDataRow({
    required this.tableWidth,
    required this.tableColors,
    required this.appState,
    required this.parent,
    required this.subtask,
    required this.showDivider,
    this.onOpenSubtask,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AppState appState;
  final Task parent;
  final SingularSubtask subtask;
  final bool showDivider;
  final void Function(String subtaskId)? onOpenSubtask;

  @override
  Widget build(BuildContext context) {
    final name = subtask.subtaskName.trim().isEmpty
        ? '(Unnamed sub-task)'
        : subtask.subtaskName.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Divider(
            height: 1,
            indent:
                _TaskTableLayout.hPad +
                _TaskTableLayout.typeCol +
                _TaskTableLayout.typeColGap +
                _TaskTableLayout.nameGutter,
            color: Colors.grey.shade200,
          ),
        _ItemTableRow(
          tableWidth: tableWidth,
          tableColors: tableColors,
          appState: appState,
          onRowTap: () => onOpenSubtask?.call(subtask.id),
          projectName: parent.projectName ?? '—',
          name: name,
          isSubtask: true,
          completed: _subtaskCompleted(subtask),
          dueDate: subtask.dueDate,
          creator: subtask.createByStaffName,
          picKey: subtask.pic,
          priority: subtask.priority,
          status: subtask.status,
          submission: subtask.submission,
          indentSubtaskBadge: true,
        ),
      ],
    );
  }
}

class _SubtaskSectionHeader extends StatelessWidget {
  const _SubtaskSectionHeader({required this.tableWidth});

  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    final cols = _TaskTableLayout(tableWidth);
    final style = _taskTableHeaderStyle(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _TaskTableLayout.hPad,
        10,
        _TaskTableLayout.hPad,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _TaskTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _TaskTableLayout.typeColGap),
          SizedBox(
            width: cols.taskNameCol,
            height: _TaskTableLayout.singleLineExtent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: _TaskTableLayout.nameGutter),
                Expanded(
                  child: Text(
                    'Sub-task Name',
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.dueCol,
            label: 'Due Date',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.projectCol,
            label: 'Project',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.priorityCol,
            label: 'Priority',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.submissionCol,
            label: 'Submission',
            style: style,
            rowHeight: _TaskTableLayout.singleLineExtent,
          ),
        ],
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  const _ExpandChevron({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _TaskTableLayout.nameGutter,
      height: _TaskTableLayout.singleLineExtent,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 20,
              color: kAsanaTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemTableRow extends StatelessWidget {
  const _ItemTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.appState,
    this.onRowTap,
    required this.projectName,
    required this.name,
    required this.isSubtask,
    required this.completed,
    required this.dueDate,
    required this.creator,
    required this.picKey,
    required this.priority,
    required this.status,
    required this.submission,
    this.expandControl,
    this.indentSubtaskBadge = false,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AppState appState;
  final VoidCallback? onRowTap;
  final String projectName;
  final String name;
  final bool isSubtask;
  final bool completed;
  final DateTime? dueDate;
  final String? creator;
  final String? picKey;
  final int priority;
  final String status;
  final String? submission;

  /// Expand/collapse control shown in the fixed name gutter (tasks with sub-tasks).
  final Widget? expandControl;

  /// Expanded child sub-tasks use the task arrow gutter as their visual indent.
  final bool indentSubtaskBadge;

  @override
  Widget build(BuildContext context) {
    final cols = _TaskTableLayout(tableWidth);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: isSubtask,
    );
    final rowBg = isSubtask ? tableColors.subtaskRow : tableColors.taskRow;
    final typeLetter = AsanaRowTypeLetter(
      letter: isSubtask ? 'S' : 'T',
      completed: completed,
      deleted: _rowDeleted(isSubtask: isSubtask, status: status),
    );

    return Material(
      color: rowBg,
      child: InkWell(
        onTap: onRowTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _TaskTableLayout.hPad,
            10,
            _TaskTableLayout.hPad,
            10,
          ),
          child: SizedBox(
            width: tableWidth - _TaskTableLayout.hPad * 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _TaskTableLayout.typeCol,
                  child: Center(
                    child: indentSubtaskBadge
                        ? const SizedBox.shrink()
                        : typeLetter,
                  ),
                ),
                const SizedBox(width: _TaskTableLayout.typeColGap),
                SizedBox(
                  width: cols.taskNameCol,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: _TaskTableLayout.nameGutter,
                        height: _TaskTableLayout.singleLineExtent,
                        child: Center(
                          child: indentSubtaskBadge
                              ? Transform.translate(
                                  offset: const Offset(-8, 0),
                                  child: typeLetter,
                                )
                              : (expandControl ?? const SizedBox.shrink()),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          name,
                          style: nameStyle,
                          maxLines: isSubtask ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                        ),
                      ),
                    ],
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.dueCol,
                  child: Text(
                    _formatDueDate(dueDate),
                    style: rowValueStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.projectCol,
                  child: Text(
                    projectName,
                    style: rowValueStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.creatorCol,
                  child: Text(
                    _formatCreator(creator),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.picCol,
                  child: Text(
                    _formatPic(appState, picKey),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.priorityCol,
                  child: AsanaTableCellChip(
                    child: AsanaPriorityChip(priority: priority),
                  ),
                ),
                SizedBox(
                  width: cols.statusCol,
                  child: AsanaTableCellChip(
                    child: AsanaStatusChip(status: status),
                  ),
                ),
                SizedBox(
                  width: cols.submissionCol,
                  child: AsanaTableCellChip(
                    child: AsanaSubmissionChip(submission: submission),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlatMobileRow extends StatelessWidget {
  const _FlatMobileRow({
    required this.tableColors,
    required this.appState,
    required this.task,
    this.subtask,
    this.onTap,
    this.expandControl,
  });

  final AsanaTableColors tableColors;
  final AppState appState;
  final Task task;
  final SingularSubtask? subtask;
  final VoidCallback? onTap;
  final Widget? expandControl;

  @override
  Widget build(BuildContext context) {
    final isSubtask = subtask != null;
    final completed = isSubtask
        ? _subtaskCompleted(subtask!)
        : _taskCompleted(task);
    final name = isSubtask
        ? (subtask!.subtaskName.trim().isEmpty
              ? '(Unnamed sub-task)'
              : subtask!.subtaskName.trim())
        : (task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim());
    final dueDate = isSubtask ? subtask!.dueDate : task.endDate;
    final creator = isSubtask
        ? subtask!.createByStaffName
        : task.createByStaffName;
    final picKey = isSubtask ? subtask!.pic : task.pic;
    final status = isSubtask ? subtask!.status : TaskListCard.statusLabel(task);
    final submission = isSubtask ? subtask!.submission : task.submission;
    final projectName = task.projectName?.trim() ?? '';
    final rowBg = isSubtask ? tableColors.subtaskRow : tableColors.taskRow;
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: isSubtask,
    );
    final valueStyle = asanaTableRowValueStyle(context, completed: completed);
    final metaParts = [
      'Cr: ${_formatCreator(creator)}',
      'PIC: ${_formatPic(appState, picKey)}',
      if (!isSubtask && projectName.trim().isNotEmpty)
        'Pr: ${projectName.trim()}',
      'Due: ${_formatDueDate(dueDate)}',
    ];
    final metaLine = metaParts.join(' · ');

    final typeLetter = AsanaRowTypeLetter(
      letter: isSubtask ? 'S' : 'T',
      completed: completed,
      deleted: _rowDeleted(isSubtask: isSubtask, status: status),
    );

    return Material(
      color: rowBg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: expandControl == null
                      ? typeLetter
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            typeLetter,
                            const SizedBox(height: 2),
                            expandControl!,
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      name,
                      style: nameStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(metaLine, style: valueStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        AsanaStatusChip(status: status),
                        AsanaSubmissionChip(submission: submission),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _taskCompleted(Task task) {
  final s = task.dbStatus?.trim().toLowerCase() ?? '';
  return s == 'completed' || s == 'complete' || task.status == TaskStatus.done;
}

bool _subtaskCompleted(SingularSubtask s) {
  final x = s.status.trim().toLowerCase();
  return x == 'completed' || x == 'complete';
}

bool _rowDeleted({required bool isSubtask, required String status}) {
  final s = status.trim().toLowerCase();
  return s == 'deleted' || s == 'delete';
}

String _tasksContentSig(List<Task> tasks) {
  final b = StringBuffer();
  for (final t in tasks) {
    b
      ..write(t.id)
      ..write('|')
      ..write(t.name)
      ..write('|')
      ..write(t.dbStatus)
      ..write('|')
      ..write(t.priority)
      ..write('|')
      ..write(t.endDate?.millisecondsSinceEpoch)
      ..write('|')
      ..write(t.projectName)
      ..write('|')
      ..write(t.submission)
      ..write('|')
      ..write(t.pic)
      ..write(';');
  }
  return b.toString();
}

String _formatDueDate(DateTime? d) {
  if (d == null) return '—';
  final today = HkTime.todayDateOnlyHk();
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  return HkTime.formatInstantAsHk(d, 'MMM d');
}

String _formatCreator(String? name) {
  final n = name?.trim();
  return (n == null || n.isEmpty) ? '—' : n;
}

String _formatPic(AppState state, String? pic) {
  final p = pic?.trim();
  if (p == null || p.isEmpty) return '—';
  return state.assigneeById(p)?.name ?? p;
}
