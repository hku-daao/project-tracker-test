import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../../widgets/task_list_card.dart';
import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_filter_widgets.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

enum _ArchiveCategory {
  deletedProjects,
  deletedTasks,
  deletedSubtasks,
  completedTasks,
}

class AsanaArchivedPanel extends StatefulWidget {
  const AsanaArchivedPanel({
    super.key,
    required this.palette,
    required this.searchQuery,
    this.refreshToken = 0,
    this.onOpenProject,
    this.onOpenTask,
    this.onOpenSubtask,
  });

  final AsanaLandingPalette palette;
  final String searchQuery;
  final int refreshToken;
  final void Function(String projectId)? onOpenProject;
  final void Function(String taskId)? onOpenTask;
  final void Function(String subtaskId)? onOpenSubtask;

  @override
  State<AsanaArchivedPanel> createState() => _AsanaArchivedPanelState();
}

class _AsanaArchivedPanelState extends State<AsanaArchivedPanel> {
  _ArchiveCategory _category = _ArchiveCategory.deletedProjects;
  final Set<String> _expandedProjectIds = {};
  final Set<String> _expandedTaskIds = {};
  Map<String, List<SingularSubtask>> _subtasksByTask = {};
  bool _loadingSubtasks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllSubtasks());
  }

  @override
  void didUpdateWidget(covariant AsanaArchivedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadAllSubtasks();
    }
  }

  Future<void> _loadAllSubtasks() async {
    if (!mounted) return;
    final taskIds = context.read<AppState>().tasks.map((t) => t.id).toList();
    setState(() => _loadingSubtasks = true);
    try {
      final grouped =
          await SupabaseService.fetchSubtasksGroupedIncludingDeleted(taskIds);
      if (mounted) setState(() => _subtasksByTask = grouped);
    } finally {
      if (mounted) setState(() => _loadingSubtasks = false);
    }
  }

  bool _matchesSearch(Iterable<String?> values) {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return values
        .whereType<String>()
        .map((v) => v.toLowerCase())
        .any((v) => v.contains(q));
  }

  bool _projectDeleted(ProjectRecord p) {
    final s = p.status.trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  bool _taskDeleted(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'deleted' || s == 'delete';
  }

  bool _taskCompleted(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'completed' || s == 'complete' || t.status == TaskStatus.done;
  }

  List<Task> _tasksForProject(AppState state, String projectId) {
    final out = state.tasks
        .where((t) => t.projectId?.trim() == projectId.trim())
        .toList();
    out.sort(_compareTaskDueThenName);
    return out;
  }

  int _compareTaskDueThenName(Task a, Task b) {
    final ad = a.endDate;
    final bd = b.endDate;
    if (ad == null && bd != null) return 1;
    if (ad != null && bd == null) return -1;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<void> _unarchiveTask(AppState state, Task task) async {
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        updateByStaffLookupKey: state.userStaffAppId,
        clearArchive: true,
      );
      if (err != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not unarchive task: $err')),
        );
        return;
      }
      state.replaceTask(
        task.copyWith(clearArchivedAt: true, clearArchivedByStaffId: true),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final deletedProjects = state.projects
        .where(_projectDeleted)
        .where((p) => _matchesSearch([p.name, p.description]))
        .toList();
    final deletedTasks =
        state.tasks
            .where(_taskDeleted)
            .where(
              (t) => _matchesSearch([t.name, t.description, t.projectName]),
            )
            .toList()
          ..sort(_compareTaskDueThenName);
    final completedTasks =
        state.tasks
            .where(
              (t) =>
                  !_taskDeleted(t) && _taskCompleted(t) && t.archivedAt != null,
            )
            .where(
              (t) => _matchesSearch([t.name, t.description, t.projectName]),
            )
            .toList()
          ..sort(_compareTaskDueThenName);
    final deletedSubtasks = _subtasksByTask.values
        .expand((e) => e)
        .where((s) => s.isDeleted)
        .where((s) => _matchesSearch([s.subtaskName, s.description]))
        .toList();

    return ColoredBox(
      color: widget.palette.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              'Archived',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: kAsanaTextPrimary,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                _categoryChip(
                  _ArchiveCategory.deletedProjects,
                  'Deleted Projects',
                ),
                _categoryChip(_ArchiveCategory.deletedTasks, 'Deleted Tasks'),
                _categoryChip(
                  _ArchiveCategory.deletedSubtasks,
                  'Deleted Subtasks',
                ),
                _categoryChip(
                  _ArchiveCategory.completedTasks,
                  'Completed Tasks',
                ),
              ],
            ),
          ),
          Expanded(
            child: AsanaPanelListSurface(
              palette: widget.palette,
              child: _loadingSubtasks
                  ? const SizedBox.shrink()
                  : LayoutBuilder(
                      builder: (context, constraints) => _archiveBody(
                        state: state,
                        constraints: constraints,
                        deletedProjects: deletedProjects,
                        deletedTasks: deletedTasks,
                        deletedSubtasks: deletedSubtasks,
                        completedTasks: completedTasks,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChip(_ArchiveCategory category, String label) {
    final selected = _category == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _category = category),
      ),
    );
  }

  Widget _archiveBody({
    required AppState state,
    required BoxConstraints constraints,
    required List<ProjectRecord> deletedProjects,
    required List<Task> deletedTasks,
    required List<SingularSubtask> deletedSubtasks,
    required List<Task> completedTasks,
  }) {
    final mobile = constraints.maxWidth < 600;
    if (!mobile && _category == _ArchiveCategory.deletedProjects) {
      return _projectArchiveTable(
        state: state,
        projects: deletedProjects,
        tableWidth:
            constraints.maxWidth < _ArchiveProjectTableLayout.minTableWidth
            ? _ArchiveProjectTableLayout.minTableWidth
            : constraints.maxWidth,
        viewportHeight: constraints.maxHeight,
      );
    }
    if (!mobile &&
        (_category == _ArchiveCategory.deletedTasks ||
            _category == _ArchiveCategory.completedTasks)) {
      final tasks = _category == _ArchiveCategory.completedTasks
          ? completedTasks
          : deletedTasks;
      return _taskArchiveTable(
        state: state,
        tasks: tasks,
        tableWidth: constraints.maxWidth < _ArchiveTaskTableLayout.minTableWidth
            ? _ArchiveTaskTableLayout.minTableWidth
            : constraints.maxWidth,
        showUnarchive: _category == _ArchiveCategory.completedTasks,
        viewportHeight: constraints.maxHeight,
      );
    }
    return ListView(
      children: switch (_category) {
        _ArchiveCategory.deletedProjects => [
          for (final p in deletedProjects) _projectRow(state, p),
        ],
        _ArchiveCategory.deletedTasks => [
          for (final t in deletedTasks)
            _taskRow(state, t, showUnarchive: false),
        ],
        _ArchiveCategory.deletedSubtasks => [
          for (final s in deletedSubtasks) _subtaskRow(s),
        ],
        _ArchiveCategory.completedTasks => [
          for (final t in completedTasks)
            _taskRow(state, t, showUnarchive: true),
        ],
      },
    );
  }

  Widget _taskArchiveTable({
    required AppState state,
    required List<Task> tasks,
    required double tableWidth,
    required double viewportHeight,
    required bool showUnarchive,
  }) {
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ArchiveTaskTableHeader(tableWidth: tableWidth),
        Divider(height: 1, color: Colors.grey.shade300),
        Expanded(
          child: ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0)
                    Divider(height: 1, color: Colors.grey.shade300),
                  _taskTableRow(
                    state: state,
                    task: task,
                    tableWidth: tableWidth,
                    showUnarchive: showUnarchive,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
    if (tableWidth > MediaQuery.sizeOf(context).width) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          height: viewportHeight,
          child: table,
        ),
      );
    }
    return table;
  }

  Widget _projectArchiveTable({
    required AppState state,
    required List<ProjectRecord> projects,
    required double tableWidth,
    required double viewportHeight,
  }) {
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ArchiveProjectTableHeader(tableWidth: tableWidth),
        Divider(height: 1, color: Colors.grey.shade300),
        Expanded(
          child: ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              final expanded = _expandedProjectIds.contains(project.id);
              final tasks = _tasksForProject(state, project.id);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (index > 0)
                    Divider(height: 1, color: Colors.grey.shade300),
                  _ArchiveProjectTableRow(
                    tableWidth: tableWidth,
                    color: widget.palette.tableColors.projectRow,
                    project: project,
                    creator: _formatCreator(project.createByDisplayName),
                    pic: _projectPicLine(project),
                    expanded: expanded,
                    onToggleExpand: () => setState(() {
                      expanded
                          ? _expandedProjectIds.remove(project.id)
                          : _expandedProjectIds.add(project.id);
                    }),
                    onTap: () => widget.onOpenProject?.call(project.id),
                  ),
                  if (expanded)
                    ColoredBox(
                      color: widget.palette.tableColors.subtaskSection,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ArchiveTaskTableHeader(tableWidth: tableWidth),
                          for (var i = 0; i < tasks.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: Colors.grey.shade300),
                            _taskTableRow(
                              state: state,
                              task: tasks[i],
                              tableWidth: tableWidth,
                              showUnarchive: false,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
    if (tableWidth > MediaQuery.sizeOf(context).width) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          height: viewportHeight,
          child: table,
        ),
      );
    }
    return table;
  }

  Widget _taskTableRow({
    required AppState state,
    required Task task,
    required double tableWidth,
    required bool showUnarchive,
  }) {
    final expanded = _expandedTaskIds.contains(task.id);
    final subtasks = _subtasksByTask[task.id] ?? [];
    final unarchive = showUnarchive ? () => _unarchiveTask(state, task) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ArchiveTaskTableRow(
          tableWidth: tableWidth,
          color: widget.palette.tableColors.taskRow,
          letter: 'T',
          completed: _taskCompleted(task),
          deleted: _taskDeleted(task),
          name: task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim(),
          dueDate: task.endDate,
          projectName: task.projectName ?? '—',
          creator: _formatCreator(task.createByStaffName),
          pic: _formatPic(state, task.pic),
          priority: task.priority,
          status: TaskListCard.statusLabel(task),
          submission: task.submission,
          expandControl: subtasks.isEmpty
              ? null
              : _ArchiveExpandButton(
                  expanded: expanded,
                  onPressed: () => setState(() {
                    expanded
                        ? _expandedTaskIds.remove(task.id)
                        : _expandedTaskIds.add(task.id);
                  }),
                ),
          trailing: unarchive == null
              ? null
              : _ArchiveActionButton(
                  icon: Icons.unarchive_outlined,
                  tooltip: 'Unarchive task',
                  onPressed: unarchive,
                ),
          onTap: () => widget.onOpenTask?.call(task.id),
        ),
        if (expanded)
          ColoredBox(
            color: widget.palette.tableColors.subtaskSection,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ArchiveTaskTableHeader(
                  tableWidth: tableWidth,
                  subtaskHeader: true,
                ),
                for (var i = 0; i < subtasks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
                  _ArchiveTaskTableRow(
                    tableWidth: tableWidth,
                    color: widget.palette.tableColors.subtaskRow,
                    letter: 'S',
                    completed: _subtaskCompleted(subtasks[i]),
                    deleted: subtasks[i].isDeleted,
                    name: subtasks[i].subtaskName.trim().isEmpty
                        ? '(Unnamed sub-task)'
                        : subtasks[i].subtaskName.trim(),
                    dueDate: subtasks[i].dueDate,
                    projectName: task.projectName ?? '—',
                    creator: _formatCreator(subtasks[i].createByStaffName),
                    pic: _formatPic(state, subtasks[i].pic),
                    priority: subtasks[i].priority,
                    status: subtasks[i].status,
                    submission: subtasks[i].submission,
                    indentSubtaskBadge: true,
                    onTap: () => widget.onOpenSubtask?.call(subtasks[i].id),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _projectRow(AppState state, ProjectRecord project) {
    final expanded = _expandedProjectIds.contains(project.id);
    final tasks = _tasksForProject(state, project.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _archiveEntityRow(
          color: widget.palette.tableColors.projectRow,
          letter: 'P',
          deleted: true,
          completed: false,
          title: project.name.trim().isEmpty
              ? '(Unnamed project)'
              : project.name,
          meta: project.description.trim().isEmpty
              ? 'Deleted project'
              : project.description.trim(),
          chips: [AsanaStatusChip(status: project.status)],
          expandControl: _ArchiveExpandButton(
            expanded: expanded,
            onPressed: () => setState(() {
              expanded
                  ? _expandedProjectIds.remove(project.id)
                  : _expandedProjectIds.add(project.id);
            }),
          ),
          onTap: () => widget.onOpenProject?.call(project.id),
        ),
        if (expanded)
          ColoredBox(
            color: widget.palette.tableColors.subtaskSection,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tasks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
                  _taskRow(state, tasks[i], nested: true),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _taskRow(
    AppState state,
    Task task, {
    bool nested = false,
    bool showUnarchive = false,
  }) {
    final expanded = _expandedTaskIds.contains(task.id);
    final subtasks = _subtasksByTask[task.id] ?? [];
    final title = task.name.trim().isEmpty
        ? '(Unnamed task)'
        : task.name.trim();
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final unarchive = showUnarchive ? () => _unarchiveTask(state, task) : null;
    final row = _archiveEntityRow(
      color: nested
          ? widget.palette.tableColors.subtaskRow
          : widget.palette.tableColors.taskRow,
      indentLevel: nested ? 1 : 0,
      letter: 'T',
      deleted: _taskDeleted(task),
      completed: _taskCompleted(task),
      title: title,
      meta:
          '${task.projectName?.trim().isNotEmpty == true ? '${task.projectName!.trim()} · ' : ''}Due ${_formatDate(task.endDate)}',
      chips: [
        AsanaStatusChip(status: TaskListCard.statusLabel(task)),
        AsanaSubmissionChip(submission: task.submission),
      ],
      expandControl: subtasks.isEmpty
          ? null
          : _ArchiveExpandButton(
              expanded: expanded,
              onPressed: () => setState(() {
                expanded
                    ? _expandedTaskIds.remove(task.id)
                    : _expandedTaskIds.add(task.id);
              }),
            ),
      trailing: unarchive == null || mobile
          ? null
          : _ArchiveActionButton(
              icon: Icons.unarchive_outlined,
              tooltip: 'Unarchive task',
              onPressed: unarchive,
            ),
      onTap: () => widget.onOpenTask?.call(task.id),
    );
    final visibleRow = unarchive != null && mobile
        ? _SwipeRevealAction(
            actionIcon: Icons.unarchive_outlined,
            tooltip: 'Unarchive task',
            onAction: unarchive,
            child: row,
          )
        : row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        visibleRow,
        if (expanded)
          ColoredBox(
            color: widget.palette.tableColors.subtaskSection,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < subtasks.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
                  _subtaskRow(subtasks[i], indentLevel: nested ? 2 : 1),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _subtaskRow(SingularSubtask subtask, {int indentLevel = 0}) {
    final title = subtask.subtaskName.trim().isEmpty
        ? '(Unnamed sub-task)'
        : subtask.subtaskName.trim();
    return _archiveEntityRow(
      color: widget.palette.tableColors.subtaskRow,
      indentLevel: indentLevel,
      letter: 'S',
      deleted: subtask.isDeleted,
      completed: _subtaskCompleted(subtask),
      title: title,
      meta: 'Due ${_formatDate(subtask.dueDate)}',
      chips: [
        AsanaStatusChip(status: subtask.status),
        AsanaSubmissionChip(submission: subtask.submission),
      ],
      onTap: () => widget.onOpenSubtask?.call(subtask.id),
    );
  }

  bool _subtaskCompleted(SingularSubtask subtask) {
    final s = subtask.status.trim().toLowerCase();
    return s == 'completed' || s == 'complete';
  }

  Widget _archiveEntityRow({
    required Color color,
    required String letter,
    required bool deleted,
    required bool completed,
    required String title,
    required String meta,
    required List<Widget> chips,
    int indentLevel = 0,
    Widget? expandControl,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12 + indentLevel * 28.0, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 30,
                child: Center(
                  child:
                      expandControl ??
                      AsanaRowTypeLetter(
                        letter: letter,
                        completed: completed,
                        deleted: deleted,
                      ),
                ),
              ),
              if (expandControl != null) ...[
                const SizedBox(width: 6),
                AsanaRowTypeLetter(
                  letter: letter,
                  completed: completed,
                  deleted: deleted,
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: asanaTableRowNameStyle(
                        context,
                        completed: completed,
                        isSubtask: letter == 'S',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      meta,
                      style: asanaTableRowValueStyle(
                        context,
                        completed: completed,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 6, children: chips),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '-';
    return HkTime.formatInstantAsHk(d, 'MMM d');
  }

  String _formatCreator(String? name) {
    final n = name?.trim();
    return (n == null || n.isEmpty) ? '—' : n;
  }

  String _formatPic(AppState state, String? pic) {
    final p = pic?.trim();
    if (p == null || p.isEmpty) return '—';
    return state.assigneeById(p)?.name.trim() ?? p;
  }

  String _projectPicLine(ProjectRecord project) {
    final names = project.picStaffDisplayNames
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (names.isNotEmpty) return names.join(', ');
    if (project.picStaffUuids.isNotEmpty) {
      return project.picStaffUuids.join(', ');
    }
    return '—';
  }
}

class _ArchiveTaskTableLayout {
  _ArchiveTaskTableLayout(this.tableWidth);

  final double tableWidth;

  static const double minTableWidth = 1184;
  static const double typeCol = 48;
  static const double typeColGap = 10;
  static const double nameGutter = 36;
  static const double singleLineExtent = 24;
  static const double hPad = 12;
  static const double submissionColWidth = 116;
  static const double actionColWidth = 36;
  static const int textColumnGapCount = 5;

  static const double _flexWeightSum =
      0.29 + 0.065 + 0.11 + 0.075 + 0.075 + 0.0665;

  late final double _inner =
      (tableWidth -
              typeCol -
              typeColGap -
              kAsanaTextColumnGap * textColumnGapCount -
              hPad * 2 -
              kAsanaTableStatusColWidth -
              submissionColWidth -
              actionColWidth)
          .clamp(400, double.infinity);

  double get taskNameCol => _inner * (0.29 / _flexWeightSum);
  double get dueCol => _inner * (0.065 / _flexWeightSum);
  double get projectCol => _inner * (0.11 / _flexWeightSum);
  double get creatorCol => _inner * (0.075 / _flexWeightSum);
  double get picCol => _inner * (0.075 / _flexWeightSum);
  double get priorityCol => _inner * (0.0665 / _flexWeightSum);
  double get statusCol => kAsanaTableStatusColWidth;
  double get submissionCol => submissionColWidth;
  double get actionCol => actionColWidth;
}

class _ArchiveProjectTableLayout {
  _ArchiveProjectTableLayout(this.tableWidth);

  final double tableWidth;

  static const double minTableWidth = 900;
  static const double typeCol = 48;
  static const double typeColGap = 10;
  static const double nameGutter = 36;
  static const double hPad = 12;
  static const double statusColWidth = 120;
  static const int textColumnGapCount = 3;

  late final double _inner =
      (tableWidth -
              typeCol -
              typeColGap -
              kAsanaTextColumnGap * textColumnGapCount -
              hPad * 2 -
              statusColWidth)
          .clamp(360, double.infinity);

  double get projectNameCol => _inner * 0.40;
  double get dueCol => _inner * 0.14;
  double get creatorCol => _inner * 0.20;
  double get picCol => _inner * 0.26;
  double get statusCol => statusColWidth;
}

class _ArchiveProjectTableHeader extends StatelessWidget {
  const _ArchiveProjectTableHeader({required this.tableWidth});

  final double tableWidth;

  @override
  Widget build(BuildContext context) {
    final cols = _ArchiveProjectTableLayout(tableWidth);
    final style = asanaTableHeaderStyle(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _ArchiveProjectTableLayout.hPad,
        vertical: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _ArchiveProjectTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _ArchiveProjectTableLayout.typeColGap),
          SizedBox(
            width: cols.projectNameCol,
            child: Row(
              children: [
                const SizedBox(width: _ArchiveProjectTableLayout.nameGutter),
                Expanded(child: Text('Project Name', style: style)),
              ],
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.dueCol,
            label: 'Due Date',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
        ],
      ),
    );
  }
}

class _ArchiveProjectTableRow extends StatelessWidget {
  const _ArchiveProjectTableRow({
    required this.tableWidth,
    required this.color,
    required this.project,
    required this.creator,
    required this.pic,
    required this.expanded,
    required this.onToggleExpand,
    this.onTap,
  });

  final double tableWidth;
  final Color color;
  final ProjectRecord project;
  final String creator;
  final String pic;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cols = _ArchiveProjectTableLayout(tableWidth);
    final rowValueStyle = asanaTableRowValueStyle(context);
    final nameStyle = asanaTableRowNameStyle(context);
    final name = project.name.trim().isEmpty
        ? '(Unnamed project)'
        : project.name.trim();
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _ArchiveProjectTableLayout.hPad,
            10,
            _ArchiveProjectTableLayout.hPad,
            10,
          ),
          child: SizedBox(
            width: tableWidth - _ArchiveProjectTableLayout.hPad * 2,
            child: Row(
              children: [
                const SizedBox(
                  width: _ArchiveProjectTableLayout.typeCol,
                  child: Center(
                    child: AsanaRowTypeLetter(
                      letter: 'P',
                      completed: false,
                      deleted: true,
                    ),
                  ),
                ),
                const SizedBox(width: _ArchiveProjectTableLayout.typeColGap),
                SizedBox(
                  width: cols.projectNameCol,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _ArchiveProjectTableLayout.nameGutter,
                        height: _ArchiveTaskTableLayout.singleLineExtent,
                        child: Center(
                          child: _ArchiveExpandButton(
                            expanded: expanded,
                            onPressed: onToggleExpand,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          name,
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
                    _formatArchiveDueDate(project.endDate),
                    style: rowValueStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.creatorCol,
                  child: Text(
                    creator,
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.picCol,
                  child: Text(
                    pic,
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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

class _ArchiveTaskTableHeader extends StatelessWidget {
  const _ArchiveTaskTableHeader({
    required this.tableWidth,
    this.subtaskHeader = false,
  });

  final double tableWidth;
  final bool subtaskHeader;

  @override
  Widget build(BuildContext context) {
    final cols = _ArchiveTaskTableLayout(tableWidth);
    final style = asanaTableHeaderStyle(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _ArchiveTaskTableLayout.hPad,
        vertical: 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: _ArchiveTaskTableLayout.typeCol,
            child: Text('', style: style),
          ),
          const SizedBox(width: _ArchiveTaskTableLayout.typeColGap),
          SizedBox(
            width: cols.taskNameCol,
            child: Row(
              children: [
                const SizedBox(width: _ArchiveTaskTableLayout.nameGutter),
                Expanded(
                  child: Text(
                    subtaskHeader ? 'Sub-task Name' : 'Task Name',
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
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.projectCol,
            label: 'Project',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.creatorCol,
            label: 'Creator',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.picCol,
            label: 'PIC',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: cols.priorityCol,
            label: 'Priority',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.statusCol,
            label: 'Status',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          asanaTableHeaderLabel(
            width: cols.submissionCol,
            label: 'Submission',
            style: style,
            rowHeight: _ArchiveTaskTableLayout.singleLineExtent,
          ),
          SizedBox(width: cols.actionCol),
        ],
      ),
    );
  }
}

class _ArchiveTaskTableRow extends StatelessWidget {
  const _ArchiveTaskTableRow({
    required this.tableWidth,
    required this.color,
    required this.letter,
    required this.completed,
    required this.deleted,
    required this.name,
    required this.dueDate,
    required this.projectName,
    required this.creator,
    required this.pic,
    required this.priority,
    required this.status,
    required this.submission,
    this.expandControl,
    this.trailing,
    this.indentSubtaskBadge = false,
    this.onTap,
  });

  final double tableWidth;
  final Color color;
  final String letter;
  final bool completed;
  final bool deleted;
  final String name;
  final DateTime? dueDate;
  final String projectName;
  final String creator;
  final String pic;
  final int priority;
  final String status;
  final String? submission;
  final Widget? expandControl;
  final Widget? trailing;
  final bool indentSubtaskBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cols = _ArchiveTaskTableLayout(tableWidth);
    final rowValueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
      isSubtask: letter == 'S',
    );
    final typeLetter = AsanaRowTypeLetter(
      letter: letter,
      completed: completed,
      deleted: deleted,
    );
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            _ArchiveTaskTableLayout.hPad,
            10,
            _ArchiveTaskTableLayout.hPad,
            10,
          ),
          child: SizedBox(
            width: tableWidth - _ArchiveTaskTableLayout.hPad * 2,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _ArchiveTaskTableLayout.typeCol,
                  child: Center(
                    child: indentSubtaskBadge
                        ? const SizedBox.shrink()
                        : typeLetter,
                  ),
                ),
                const SizedBox(width: _ArchiveTaskTableLayout.typeColGap),
                SizedBox(
                  width: cols.taskNameCol,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: _ArchiveTaskTableLayout.nameGutter,
                        height: _ArchiveTaskTableLayout.singleLineExtent,
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
                          maxLines: letter == 'S' ? 2 : 1,
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
                    _formatArchiveDueDate(dueDate),
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
                    creator,
                    style: rowValueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                SizedBox(
                  width: cols.picCol,
                  child: Text(
                    pic,
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
                SizedBox(
                  width: cols.actionCol,
                  child: trailing == null
                      ? const SizedBox.shrink()
                      : Center(child: trailing),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatArchiveDueDate(DateTime? d) {
  if (d == null) return '—';
  return HkTime.formatInstantAsHk(d, 'MMM d');
}

class _ArchiveExpandButton extends StatelessWidget {
  const _ArchiveExpandButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onPressed,
      radius: 16,
      child: Icon(
        expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
        size: 22,
        color: kAsanaTextSecondary,
      ),
    );
  }
}

class _ArchiveActionButton extends StatelessWidget {
  const _ArchiveActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _SwipeRevealAction extends StatefulWidget {
  const _SwipeRevealAction({
    required this.child,
    required this.actionIcon,
    required this.tooltip,
    required this.onAction,
  });

  final Widget child;
  final IconData actionIcon;
  final String tooltip;
  final VoidCallback onAction;

  @override
  State<_SwipeRevealAction> createState() => _SwipeRevealActionState();
}

class _SwipeRevealActionState extends State<_SwipeRevealAction> {
  bool _open = false;
  double _dragDx = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = constraints.maxWidth * 0.30;
        final dragOffset = _dragDx.clamp(-actionWidth, 0.0);
        final restingOffset = _open ? -actionWidth : 0.0;
        final offset = _dragDx == 0 ? restingOffset : dragOffset;

        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: actionWidth,
                    child: Material(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Tooltip(
                        message: widget.tooltip,
                        child: InkWell(
                          onTap: () {
                            setState(() => _open = false);
                            widget.onAction();
                          },
                          child: Center(
                            child: Icon(
                              widget.actionIcon,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  setState(() => _dragDx += details.delta.dx);
                },
                onHorizontalDragEnd: (_) {
                  setState(() {
                    _open = _dragDx < -actionWidth * 0.35;
                    _dragDx = 0;
                  });
                },
                child: AnimatedContainer(
                  duration: _dragDx == 0
                      ? const Duration(milliseconds: 180)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(offset, 0, 0),
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
