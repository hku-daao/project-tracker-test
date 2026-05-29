import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
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
    this.onCreateProject,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final void Function(String projectId)? onOpenProject;
  final VoidCallback? onCreateProject;

  @override
  State<AsanaProjectsPanel> createState() => _AsanaProjectsPanelState();
}

class _AsanaProjectsPanelState extends State<AsanaProjectsPanel> {
  final _filters = AsanaProjectFilterState();
  List<ProjectRecord> _displayProjects = [];
  String _projectsDataSig = '';

  @override
  void initState() {
    super.initState();
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
    final theme = Theme.of(context);
    final tableColors = widget.palette.tableColors;

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
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                  height: 1.25,
                ),
              ),
            ),
          ),
          AsanaPanelFilterToolbar(
              palette: widget.palette,
              createLabel: 'Create Project',
              onCreate: widget.onCreateProject ?? () {},
              onClearAll: () {
                setState(_filters.resetToDefaults);
                _rebuildList();
              },
              filterChildren: [
                AsanaFilterDropdown(
                  title: 'Scope',
                  value: _scopeLabel(),
                  onPressed: _showScopeMenu,
                ),
                AsanaFilterDropdown(
                  title: 'Status',
                  value: _statusLabel(),
                  onPressed: _showStatusMenu,
                ),
                AsanaFilterDropdown(
                  title: 'Due date',
                  value: _dueDateLabel(),
                  buttonWidth: 188,
                  onPressed: _showDueDateRangePicker,
                ),
                AsanaFilterDropdown(
                  title: 'Sort',
                  value: _sortLabel(),
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
                final tableWidth = constraints.maxWidth <
                        _ProjectTableLayout.minTableWidth
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
                            onTap: () => widget.onOpenProject?.call(p.id),
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
                              _ProjectTableRow(
                                tableWidth: tableWidth,
                                tableColors: tableColors,
                                project: p,
                                appState: state,
                                onRowTap: () => widget.onOpenProject?.call(p.id),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth < _ProjectTableLayout.minTableWidth) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      height: constraints.maxHeight,
                      child: table,
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
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all')) return 'All';
    if (_filters.scopes.length == 1) {
      if (_filters.scopes.contains('assigned')) return 'Assigned to me';
      if (_filters.scopes.contains('created')) return 'Created by me';
    }
    return '${_filters.scopes.length} selected';
  }

  String _scopeSectionTitle() {
    if (_filters.scopes.isEmpty || _filters.scopes.contains('all')) {
      return 'Projects created by or assigned to my team';
    }
    if (_filters.scopes.length == 1) {
      if (_filters.scopes.contains('assigned')) return 'Projects assigned to me';
      if (_filters.scopes.contains('created')) return 'Projects created by me';
    }
    return 'Projects (Multiple scopes)';
  }

  String _statusLabel() {
    if (_filters.statuses.isEmpty) return 'All';
    return _filters.statuses.join(', ');
  }

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

  Future<void> _showDueDateRangePicker(BuildContext buttonContext) async {
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

  String _sortLabel() {
    final name = switch (_filters.sortKey) {
      'name' => 'Name',
      'created' => 'Created',
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
      _rebuildList();
    }
  }

  Future<void> _showStatusMenu(BuildContext buttonContext) async {
    const allKey = '__all__';
    const options = [
      'Not started',
      'In progress',
      'Completed',
      'Deleted',
    ];
    final selection = await showAsanaCheckboxFilterPanel(
      anchorContext: buttonContext,
      options: [
        const AsanaFilterCheckboxOption(key: allKey, label: 'All', isAll: true),
        for (final s in options)
          AsanaFilterCheckboxOption(key: s, label: s),
      ],
      initialSelection: _filters.statuses,
    );
    if (selection != null) {
      setState(() => _filters.statuses = selection);
      _rebuildList();
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
      _rebuildList();
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
  /// Plain-text columns (name, due, creator, PIC, assignees) each followed by a gap.
  static const int textColumnGapCount = 5;
  static const double singleLineExtent = 24;
  static const double hPad = 12;

  static const double _flexWeightSum = 0.24 + 0.10 + 0.09 + 0.14 + 0.16;

  late final double _inner = (tableWidth -
          typeCol -
          typeColGap -
          kAsanaTextColumnGap * textColumnGapCount -
          hPad * 2 -
          kAsanaTableStatusColWidth)
      .clamp(320, double.infinity);

  double get nameCol => _inner * (0.24 / _flexWeightSum);
  double get dueCol => _inner * (0.10 / _flexWeightSum);
  double get creatorCol => _inner * (0.09 / _flexWeightSum);
  double get picCol => _inner * (0.14 / _flexWeightSum);
  double get assigneeCol => _inner * (0.16 / _flexWeightSum);
  double get statusCol => kAsanaTableStatusColWidth;
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
          SizedBox(width: _ProjectTableLayout.typeCol, child: Text('', style: style)),
          const SizedBox(width: _ProjectTableLayout.typeColGap),
          SizedBox(
            width: cols.nameCol,
            child: Row(
              children: [
                const SizedBox(width: _ProjectTableLayout.nameGutter),
                Expanded(
                  child: Text('Project Name', style: style),
                ),
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

class _ProjectTableRow extends StatelessWidget {
  const _ProjectTableRow({
    required this.tableWidth,
    required this.tableColors,
    required this.project,
    required this.appState,
    this.onRowTap,
  });

  final double tableWidth;
  final AsanaTableColors tableColors;
  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onRowTap;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final cols = _ProjectTableLayout(tableWidth);
    final rowValueStyle =
        asanaTableRowValueStyle(context, completed: _completed);
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: _completed,
    );

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
                      const SizedBox(
                        width: _ProjectTableLayout.nameGutter,
                        height: _ProjectTableLayout.singleLineExtent,
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
    this.onTap,
  });

  final AsanaTableColors tableColors;
  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onTap;

  bool get _completed => project.status.trim() == 'Completed';
  bool get _deleted {
    final s = project.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  @override
  Widget build(BuildContext context) {
    final name =
        project.name.trim().isEmpty ? '(Unnamed project)' : project.name.trim();
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: _completed,
    );
    final valueStyle = asanaTableRowValueStyle(
      context,
      completed: _completed,
    );
    final metaLine = [
      'Cr: ${AsanaProjectFilter.creatorLine(project, appState)}',
      'PIC: ${AsanaProjectFilter.picLine(project, appState)}',
    ].join(' · ');
    final dateLine = [
      'Start: ${_formatDueDate(project.startDate)}',
      'Due: ${_formatDueDate(project.endDate)}',
    ].join(' · ');

    return Material(
      color: tableColors.projectRow,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AsanaRowTypeLetter(
                  letter: 'P',
                  completed: _completed,
                  deleted: _deleted,
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
