import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../models/task.dart';
import '../../services/asana_filter_cookie_storage.dart';
import '../../utils/hk_time.dart';
import '../../widgets/task_list_card.dart';
import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_filter_widgets.dart';
import 'asana_project_filter.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Projects nav content: filter toolbar + project table (mirrors [AsanaTasksPanel]).
class AsanaProjectsPanel extends StatefulWidget {
  const AsanaProjectsPanel({
    super.key,
    required this.palette,
    required this.searchQuery,
    this.refreshToken = 0,
    this.onOpenProject,
    this.onOpenTask,
    this.onCreateProject,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final void Function(String projectId)? onOpenProject;
  final void Function(String taskId)? onOpenTask;
  final VoidCallback? onCreateProject;

  @override
  State<AsanaProjectsPanel> createState() => _AsanaProjectsPanelState();
}

class _AsanaProjectsPanelState extends State<AsanaProjectsPanel> {
  final _filters = AsanaProjectFilterState();
  List<ProjectRecord> _displayProjects = [];
  String _projectsDataSig = '';
  final Set<String> _expandedProjectIds = {};

  String get _cookieStorageKey {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null || uid.isEmpty
        ? 'asana_filters_projects'
        : 'asana_filters_projects_$uid';
  }

  @override
  void initState() {
    super.initState();
    final cookieData = AsanaFilterCookieStorage.load(_cookieStorageKey);
    if (cookieData != null) {
      _filters.applyCookieJson(cookieData);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuildList();
    });
  }

  @override
  void didUpdateWidget(covariant AsanaProjectsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery ||
        oldWidget.refreshToken != widget.refreshToken) {
      _rebuildList();
    }
  }

  void _rebuildList() {
    final state = context.read<AppState>();
    setState(() {
      _displayProjects = AsanaProjectFilter.apply(
        state,
        _filters,
        searchQuery: widget.searchQuery,
      );
    });
  }

  void _onFiltersChanged() {
    AsanaFilterCookieStorage.save(_cookieStorageKey, _filters.toCookieJson());
    AsanaBlockingLoadingOverlay.show(context);
    try {
      _rebuildList();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
    }
  }

  Map<String, List<Task>> _tasksByProject(AppState state) {
    final grouped = <String, List<Task>>{};
    for (final task in state.tasksForTeams({})) {
      if (!task.isSingularTableRow) continue;
      final projectId = task.projectId?.trim();
      if (projectId == null || projectId.isEmpty) continue;
      final status = task.dbStatus?.trim().toLowerCase() ?? '';
      if (status == 'delete' || status == 'deleted') continue;
      grouped.putIfAbsent(projectId, () => []).add(task);
    }
    for (final list in grouped.values) {
      list.sort((a, b) {
        final ad = a.endDate;
        final bd = b.endDate;
        if (ad == null && bd == null) return a.name.compareTo(b.name);
        if (ad == null) return 1;
        if (bd == null) return -1;
        final cmp = ad.compareTo(bd);
        return cmp != 0 ? cmp : a.name.compareTo(b.name);
      });
    }
    return grouped;
  }

  void _toggleProjectExpanded(String projectId) {
    setState(() {
      if (_expandedProjectIds.contains(projectId)) {
        _expandedProjectIds.remove(projectId);
      } else {
        _expandedProjectIds.add(projectId);
      }
    });
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
              'Could not load projects. Open this screen from the main app after sign-in.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final sig = state.projects.map((p) => p.id).join('|');
    if (sig != _projectsDataSig) {
      _projectsDataSig = sig;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildList();
      });
    }

    final projects = _displayProjects;
    final tasksByProject = _tasksByProject(state);
    final theme = Theme.of(context);
    final tableColors = widget.palette.tableColors;
    final compactTitle = MediaQuery.sizeOf(context).width < 600;

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
            createLabel: 'Create Project',
            onCreate: widget.onCreateProject ?? () {},
            onClearAll: () {
              setState(_filters.resetToDefaults);
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
            ],
          ),
          Expanded(
            child: AsanaPanelListSurface(
              palette: widget.palette,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mobileList = constraints.maxWidth < 600;
                  final tableWidth =
                      constraints.maxWidth < _ProjectTableLayout.minTableWidth
                      ? _ProjectTableLayout.minTableWidth
                      : constraints.maxWidth;

                  if (projects.isEmpty) {
                    return Center(
                      child: Text(
                        'No projects match your filters.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }

                  if (mobileList) {
                    return ListView.builder(
                      itemCount: projects.length,
                      itemBuilder: (context, index) {
                        final p = projects[index];
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (index > 0)
                              Divider(height: 1, color: Colors.grey.shade300),
                            _ProjectMobileRow(
                              tableColors: tableColors,
                              project: p,
                              appState: state,
                              tasks: tasksByProject[p.id] ?? const [],
                              expanded: _expandedProjectIds.contains(p.id),
                              onToggleExpand: () =>
                                  _toggleProjectExpanded(p.id),
                              onTap: () => widget.onOpenProject?.call(p.id),
                              onOpenTask: widget.onOpenTask,
                            ),
                          ],
                        );
                      },
                    );
                  }

                  final table = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProjectTableHeader(tableWidth: tableWidth),
                      Divider(height: 1, color: Colors.grey.shade300),
                      Expanded(
                        child: ListView.builder(
                          itemCount: projects.length,
                          itemBuilder: (context, index) {
                            final p = projects[index];
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (index > 0)
                                  Divider(
                                    height: 1,
                                    color: Colors.grey.shade300,
                                  ),
                                _ExpandableProjectTableRow(
                                  tableWidth: tableWidth,
                                  tableColors: tableColors,
                                  project: p,
                                  appState: state,
                                  tasks: tasksByProject[p.id] ?? const [],
                                  expanded: _expandedProjectIds.contains(p.id),
                                  onToggleExpand: () =>
                                      _toggleProjectExpanded(p.id),
                                  onRowTap: () =>
                                      widget.onOpenProject?.call(p.id),
                                  onOpenTask: widget.onOpenTask,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  );

                  if (constraints.maxWidth <
                      _ProjectTableLayout.minTableWidth) {
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
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all')) {
      return 'Projects created by or assigned to my team';
    }
    if (_filters.scopes.length == 1) {
      if (_filters.scopes.contains('assigned'))
        return 'Projects assigned to me';
      if (_filters.scopes.contains('created')) return 'Projects created by me';
    }
    if (_filters.scopes.contains('assigned') &&
        _filters.scopes.contains('created')) {
      return 'Projects created by or assigned to me';
    }
    return 'Projects (Multiple scopes)';
  }

  String _statusLabel() {
    if (_filters.statuses.isEmpty) return 'All';
    return _filters.statuses.join(', ');
  }

  String _staffName(AppState state, String id) {
    final key = id.trim();
    if (key.isEmpty) return '';
    final fromProject = _projectStaffNameById(key);
    if (fromProject != null && fromProject.isNotEmpty) return fromProject;
    return state.assigneeById(key)?.name.trim() ?? key;
  }

  String? _projectStaffNameById(String id) {
    for (final project in _displayProjects) {
      final creatorId = project.createByStaffUuid?.trim();
      if (creatorId == id) {
        final name = project.createByDisplayName?.trim();
        if (name != null && name.isNotEmpty && name != id) return name;
      }
      for (var i = 0; i < project.picStaffUuids.length; i++) {
        if (project.picStaffUuids[i].trim() != id) continue;
        if (i < project.picStaffDisplayNames.length) {
          final name = project.picStaffDisplayNames[i].trim();
          if (name.isNotEmpty && name != id) return name;
        }
      }
      for (var i = 0; i < project.assigneeStaffUuids.length; i++) {
        if (project.assigneeStaffUuids[i].trim() != id) continue;
        if (i < project.assigneeStaffDisplayNames.length) {
          final name = project.assigneeStaffDisplayNames[i].trim();
          if (name.isNotEmpty && name != id) return name;
        }
      }
    }
    return null;
  }

  String _staffFilterLabel(AppState state, List<String> ids) {
    if (ids.isEmpty) return 'All';
    if (ids.length == 1) return _staffName(state, ids.first);
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

  List<AsanaFilterCheckboxOption> _staffOptions(
    AppState state,
    Iterable<String?> ids,
  ) {
    final map = <String, String>{};
    for (final raw in ids) {
      final id = raw?.trim();
      if (id == null || id.isEmpty) continue;
      map[id] = _staffName(state, id);
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
    for (final project in _displayProjects) {
      yield project.createByStaffUuid;
    }
  }

  Iterable<String?> _visiblePicIds() sync* {
    for (final project in _displayProjects) {
      for (final id in project.picStaffUuids) {
        yield id;
      }
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
      _rebuildList();
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
    _rebuildList();
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
      _rebuildList();
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
      _rebuildList();
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
    const options = ['Not started', 'In progress', 'Completed', 'Deleted'];
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        const AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        for (final s in options) AsanaFilterCheckboxOption(key: s, label: s),
      ],
      initialSelection: _filters.statuses,
    );
    if (selection != null) {
      setState(() => _filters.statuses = selection);
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

class _ProjectTableLayout {
  _ProjectTableLayout(this.tableWidth);

  final double tableWidth;

  static const double minTableWidth = 1000;
  static const double typeCol = 48;
  static const double typeColGap = 10;

  /// Aligns project name with task list (matches [_TaskTableLayout.nameGutter]).
  static const double nameGutter = 36;

  /// Plain-text columns each followed by a gap before the next column.
  static const int textColumnGapCount = 6;
  static const double singleLineExtent = 24;
  static const double hPad = 12;
  static const double statusColWidth = 320;

  static const double _flexWeightSum =
      0.28 + 0.075 + 0.065 + 0.098 + 0.112 + 0.08;

  late final double _inner =
      (tableWidth -
              typeCol -
              typeColGap -
              kAsanaTextColumnGap * textColumnGapCount -
              hPad * 2 -
              statusColWidth)
          .clamp(320, double.infinity);

  double get nameCol => _inner * (0.28 / _flexWeightSum);
  double get dueCol => _inner * (0.075 / _flexWeightSum);
  double get creatorCol => _inner * (0.065 / _flexWeightSum);
  double get picCol => _inner * (0.098 / _flexWeightSum);
  double get assigneeCol => _inner * (0.112 / _flexWeightSum);
  double get updatedCol => _inner * (0.08 / _flexWeightSum);
  double get statusCol => statusColWidth;
}

class _ProjectExpandedTaskTableLayout {
  _ProjectExpandedTaskTableLayout(this.tableWidth);

  final double tableWidth;

  static const double typeCol = 48;
  static const double typeColGap = 10;
  static const double nameGutter = 36;
  static const int textColumnGapCount = 5;
  static const double singleLineExtent = 24;
  static const double hPad = 12;

  late final _projectCols = _ProjectTableLayout(tableWidth);
  late final double _taskFieldsWidth =
      (tableWidth -
              hPad * 2 -
              typeCol -
              typeColGap -
              taskNameCol -
              dueCol -
              creatorCol -
              picCol -
              assigneeCol -
              kAsanaTextColumnGap * textColumnGapCount)
          .clamp(0, double.infinity);

  double get taskNameCol => _projectCols.nameCol;
  double get dueCol => _projectCols.dueCol;
  double get creatorCol => _projectCols.creatorCol;
  double get picCol => _projectCols.picCol;
  double get assigneeCol => _projectCols.assigneeCol;
  double get priorityCol => _taskFieldsWidth * 0.3105;
  double get statusCol => _taskFieldsWidth * 0.32975;
  double get submissionCol => _taskFieldsWidth * 0.35975;
}

class _ProjectTableHeader extends StatelessWidget {
  const _ProjectTableHeader({required this.tableWidth});

  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(tableWidth);
    final style = asanaTableHeaderStyle(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _ProjectTableLayout.hPad,
        vertical: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _ProjectTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _ProjectTableLayout.typeColGap),
          SizedBox(
            width: cols.nameCol,
            child: Row(
              children: [
                const SizedBox(width: _ProjectTableLayout.nameGutter),
                Expanded(child: Text('Project Name', style: style)),
              ],
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.dueCol,
            label: 'Due Date',
            style: style,
            rowHeight: _ProjectTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: _ProjectTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: _ProjectTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.assigneeCol,
            label: 'Assignees',
            style: style,
            rowHeight: _ProjectTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.updatedCol,
            label: 'Last updated',
            style: style,
            rowHeight: _ProjectTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: _ProjectTableLayout.singleLineExtent,
          ),
        ],
      ),
    );
  }
}

class _ExpandableProjectTableRow extends StatelessWidget {
  const _ExpandableProjectTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.project,
    required this.appState,
    required this.tasks,
    required this.expanded,
    required this.onToggleExpand,
    this.onRowTap,
    this.onOpenTask,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final ProjectRecord project;
  final AppState appState;
  final List<Task> tasks;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onRowTap;
  final void Function(String taskId)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final hasTasks = tasks.isNotEmpty;
    return SizedBox(
      width: tableWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProjectTableRow(
            tableWidth: tableWidth,
            tableColors: tableColors,
            project: project,
            appState: appState,
            onRowTap: onRowTap,
            expandControl: hasTasks
                ? _ProjectExpandChevron(
                    expanded: expanded,
                    onPressed: onToggleExpand,
                  )
                : null,
          ),
          if (hasTasks)
            _AnimatedProjectTaskExpansion(
              expanded: expanded,
              child: ColoredBox(
                color: tableColors.subtaskSection,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProjectTaskSectionHeader(tableWidth: tableWidth),
                      for (var i = 0; i < tasks.length; i++)
                        _ProjectTaskDataRow(
                          tableWidth: tableWidth,
                          tableColors: tableColors,
                          appState: appState,
                          task: tasks[i],
                          showDivider: i > 0,
                          onOpenTask: onOpenTask,
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

class _AnimatedProjectTaskExpansion extends StatelessWidget {
  const _AnimatedProjectTaskExpansion({
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

class _ProjectExpandChevron extends StatelessWidget {
  const _ProjectExpandChevron({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _ProjectTableLayout.nameGutter,
      height: _ProjectTableLayout.singleLineExtent,
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

class _ProjectTaskSectionHeader extends StatelessWidget {
  const _ProjectTaskSectionHeader({required this.tableWidth});

  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectExpandedTaskTableLayout(tableWidth);
    final style = asanaTableHeaderStyle(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _ProjectExpandedTaskTableLayout.hPad,
        10,
        _ProjectExpandedTaskTableLayout.hPad,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _ProjectExpandedTaskTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _ProjectExpandedTaskTableLayout.typeColGap),
          SizedBox(
            width: cols.taskNameCol,
            height: _ProjectExpandedTaskTableLayout.singleLineExtent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: _ProjectExpandedTaskTableLayout.nameGutter,
                ),
                Expanded(
                  child: Text(
                    'Task Name',
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
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.assigneeCol,
            label: 'Assignees',
            style: style,
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.priorityCol,
            label: 'Priority',
            style: style,
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.submissionCol,
            label: 'Submission',
            style: style,
            rowHeight: _ProjectExpandedTaskTableLayout.singleLineExtent,
          ),
        ],
      ),
    );
  }
}

class _ProjectTaskDataRow extends StatelessWidget {
  const _ProjectTaskDataRow({
    required this.tableWidth,
    required this.tableColors,
    required this.appState,
    required this.task,
    required this.showDivider,
    this.onOpenTask,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final AppState appState;
  final Task task;
  final bool showDivider;
  final void Function(String taskId)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final status = TaskListCard.statusLabel(task);
    final completed = _taskCompleted(task);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final cols = _ProjectExpandedTaskTableLayout(tableWidth);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDivider)
          Divider(
            height: 1,
            indent:
                _ProjectExpandedTaskTableLayout.hPad +
                _ProjectExpandedTaskTableLayout.typeCol +
                _ProjectExpandedTaskTableLayout.typeColGap +
                _ProjectExpandedTaskTableLayout.nameGutter,
            color: Colors.grey.shade200,
          ),
        Material(
          color: tableColors.subtaskRow,
          child: InkWell(
            onTap: () => onOpenTask?.call(task.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _ProjectExpandedTaskTableLayout.hPad,
                10,
                _ProjectExpandedTaskTableLayout.hPad,
                10,
              ),
              child: SizedBox(
                width: tableWidth - _ProjectExpandedTaskTableLayout.hPad * 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: _ProjectExpandedTaskTableLayout.typeCol,
                      child: const Center(child: SizedBox.shrink()),
                    ),
                    const SizedBox(
                      width: _ProjectExpandedTaskTableLayout.typeColGap,
                    ),
                    SizedBox(
                      width: cols.taskNameCol,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: _ProjectExpandedTaskTableLayout.nameGutter,
                            height: _ProjectExpandedTaskTableLayout
                                .singleLineExtent,
                            child: Center(
                              child: Transform.translate(
                                offset: const Offset(-8, 0),
                                child: AsanaRowTypeLetter(
                                  letter: 'T',
                                  completed: completed,
                                  deleted: _taskDeleted(task),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              task.name.trim().isEmpty
                                  ? '(Unnamed task)'
                                  : task.name.trim(),
                              style: nameStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.dueCol,
                      child: Text(
                        _formatDueDate(task.endDate),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.creatorCol,
                      child: Text(
                        (task.createByStaffName ?? '').trim().isEmpty
                            ? '—'
                            : task.createByStaffName!.trim(),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.picCol,
                      child: Text(
                        _formatTaskPic(appState, task.pic),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.assigneeCol,
                      child: Text(
                        _formatTaskAssignees(appState, task.assigneeIds),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    asanaTextColumnGap(),
                    SizedBox(
                      width: cols.priorityCol,
                      child: AsanaTableCellChip(
                        child: AsanaPriorityChip(priority: task.priority),
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
                        child: AsanaSubmissionChip(submission: task.submission),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProjectTableRow extends StatelessWidget {
  const _ProjectTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.project,
    required this.appState,
    this.onRowTap,
    this.expandControl,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onRowTap;
  final Widget? expandControl;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(tableWidth);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: _completed,
    );
    final nameStyle = asanaTableRowNameStyle(context, completed: _completed);

    return Material(
      color: tableColors.projectRow,
      child: InkWell(
        onTap: onRowTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _ProjectTableLayout.hPad,
            vertical: 10,
          ),
          child: SizedBox(
            width: tableWidth - _ProjectTableLayout.hPad * 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _ProjectTableLayout.typeCol,
                  child: Center(
                    child: AsanaRowTypeLetter(
                      letter: 'P',
                      completed: _completed,
                      deleted: _deleted,
                    ),
                  ),
                ),
                const SizedBox(width: _ProjectTableLayout.typeColGap),
                SizedBox(
                  width: cols.nameCol,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: _ProjectTableLayout.nameGutter,
                        height: _ProjectTableLayout.singleLineExtent,
                        child: Center(
                          child: expandControl ?? const SizedBox.shrink(),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          project.name,
                          style: nameStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.dueCol,
                  child: Text(
                    _formatDueDate(project.endDate),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.creatorCol,
                  child: Text(
                    AsanaProjectFilter.creatorLine(project, appState),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.picCol,
                  child: Text(
                    AsanaProjectFilter.picLine(project, appState),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.assigneeCol,
                  child: Text(
                    AsanaProjectFilter.assigneesLine(project, appState),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.updatedCol,
                  child: Text(
                    _formatUpdatedDate(project.updateDate),
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.statusCol,
                  child: AsanaTableCellChip(
                    child: AsanaStatusChip(status: project.status),
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

class _ProjectMobileRow extends StatelessWidget {
  const _ProjectMobileRow({
    required this.tableColors,
    required this.project,
    required this.appState,
    required this.tasks,
    required this.expanded,
    required this.onToggleExpand,
    this.onTap,
    this.onOpenTask,
  });

  final AsanaTableColors tableColors;
  final ProjectRecord project;
  final AppState appState;
  final List<Task> tasks;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onTap;
  final void Function(String taskId)? onOpenTask;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final name = project.name.trim().isEmpty
        ? '(Unnamed project)'
        : project.name.trim();
    final nameStyle = asanaTableRowNameStyle(context, completed: _completed);
    final valueStyle = asanaTableRowValueStyle(context, completed: _completed);
    final metaLine = [
      'Cr: ${AsanaProjectFilter.creatorLine(project, appState)}',
      'PIC: ${AsanaProjectFilter.picLine(project, appState)}',
    ].join(' · ');
    final dateLine = [
      'Start: ${_formatDueDate(project.startDate)}',
      'Due: ${_formatDueDate(project.endDate)}',
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: tableColors.projectRow,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AsanaRowTypeLetter(
                            letter: 'P',
                            completed: _completed,
                            deleted: _deleted,
                          ),
                          if (tasks.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            _ProjectMobileExpandChevron(
                              expanded: expanded,
                              onPressed: onToggleExpand,
                            ),
                          ],
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
                        Text(
                          metaLine,
                          style: valueStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              dateLine,
                              style: valueStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            AsanaStatusChip(status: project.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (tasks.isNotEmpty)
          _AnimatedProjectTaskExpansion(
            expanded: expanded,
            child: ColoredBox(
              color: tableColors.subtaskSection,
              child: _ProjectMobileTaskList(
                tasks: tasks,
                tableColors: tableColors,
                appState: appState,
                onOpenTask: onOpenTask,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectMobileExpandChevron extends StatelessWidget {
  const _ProjectMobileExpandChevron({
    required this.expanded,
    required this.onPressed,
  });

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        child: Icon(
          expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          size: 20,
          color: kAsanaTextSecondary,
        ),
      ),
    );
  }
}

class _ProjectMobileTaskList extends StatelessWidget {
  const _ProjectMobileTaskList({
    required this.tasks,
    required this.tableColors,
    required this.appState,
    this.onOpenTask,
  });

  final List<Task> tasks;
  final AsanaTableColors tableColors;
  final AppState appState;
  final void Function(String taskId)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < tasks.length; i++) ...[
          if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
          _ProjectMobileTaskRow(
            task: tasks[i],
            tableColors: tableColors,
            appState: appState,
            onTap: onOpenTask == null ? null : () => onOpenTask!(tasks[i].id),
          ),
        ],
      ],
    );
  }
}

class _ProjectMobileTaskRow extends StatelessWidget {
  const _ProjectMobileTaskRow({
    required this.task,
    required this.tableColors,
    required this.appState,
    this.onTap,
  });

  final Task task;
  final AsanaTableColors tableColors;
  final AppState appState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final completed = _taskCompleted(task);
    final status = TaskListCard.statusLabel(task);
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: true,
    );
    final valueStyle = asanaTableRowValueStyle(context, completed: completed);
    final name = task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim();
    final metaLine = [
      'Cr: ${(task.createByStaffName ?? '').trim().isEmpty ? '—' : task.createByStaffName!.trim()}',
      'PIC: ${_formatTaskPic(appState, task.pic)}',
      'Due: ${_formatDueDate(task.endDate)}',
    ].join(' · ');

    return Material(
      color: tableColors.subtaskRow,
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
                  child: AsanaRowTypeLetter(
                    letter: 'T',
                    completed: completed,
                    deleted: _taskDeleted(task),
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
                        AsanaSubmissionChip(submission: task.submission),
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

String _formatDueDate(DateTime? d) {
  if (d == null) return '—';
  final today = HkTime.todayDateOnlyHk();
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  return HkTime.formatInstantAsHk(d, 'MMM d');
}

String _formatUpdatedDate(DateTime? d) {
  if (d == null) return '—';
  return HkTime.formatInstantAsHk(d, 'MMM d, HH:mm');
}

bool _taskCompleted(Task task) {
  final status = task.dbStatus?.trim().toLowerCase() ?? '';
  return status == 'completed' || status == 'complete';
}

bool _taskDeleted(Task task) {
  final status = task.dbStatus?.trim().toLowerCase() ?? '';
  return status == 'deleted' || status == 'delete';
}

String _formatTaskPic(AppState state, String? key) {
  final id = key?.trim();
  if (id == null || id.isEmpty) return '—';
  return state.assigneeById(id)?.name.trim() ?? id;
}

String _formatTaskAssignees(AppState state, Iterable<String> ids) {
  final names = ids
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .map((id) => state.assigneeById(id)?.name.trim() ?? id)
      .where((name) => name.isNotEmpty)
      .toList();
  return names.isEmpty ? '—' : names.join(', ');
}
