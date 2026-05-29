import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/project_record.dart';
import '../../models/task.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_project_filter.dart';
import 'asana_task_filter.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Home tab: greeting, task lists, people summary, and projects.
class AsanaHomePanel extends StatefulWidget {
  const AsanaHomePanel({
    super.key,
    required this.palette,
    this.onOpenTask,
    this.onOpenProject,
  });

  final AsanaLandingPalette palette;
  final void Function(String taskId)? onOpenTask;
  final void Function(String projectId)? onOpenProject;

  @override
  State<AsanaHomePanel> createState() => _AsanaHomePanelState();

  static const double _cardRadius = 16;
  static const double _gridGap = 12;
  static const double _panelTitleFontSize = 22;
  /// Home content width at or above this keeps the 2×2 card grid.
  static const double _twoColumnGridMinWidth = 1000;
  /// Below this card width, task/project lists use two-line labeled rows.
  static const double _homeCompactMaxWidth = 540;
  static const int _minVisibleTaskRows = 5;
  static const double _taskRowHeight = 44;
  static const double _taskRowCompactHeight = 64;
  static const double _homeDueColWidth = 76;
  static const double _homePicColWidth = 118;
  static const double _homePeopleNameMinWidth = _homePicColWidth;
  static const double _homeSubmissionColWidth = 92;
  static const double _homeStatusColWidth = 100;
  static const double _rowDividerHeight = 1;
  static const double _tableHeaderHeight = 34;
  static const double _cardPaddingVertical = 30;
  static const double _cardTitleBlockHeight =
      _panelTitleFontSize * 1.2 + 12;
  static const double homeListMinHeight =
      _rowDividerHeight +
      _minVisibleTaskRows * _taskRowHeight +
      (_minVisibleTaskRows - 1) * _rowDividerHeight;
  static const double homeCardMinHeight =
      _cardPaddingVertical +
      _cardTitleBlockHeight +
      _tableHeaderHeight +
      _rowDividerHeight +
      homeListMinHeight;
  static const double _homeTaskTableChromeAboveList =
      _taskRowHeight + 8 + _rowDividerHeight;

  static bool homeUseCompact(double cardWidth) =>
      cardWidth > 0 && cardWidth < _homeCompactMaxWidth;

  /// Title block + top/bottom padding in [_HomeCardShell] (excludes list body).
  static const double _homeShellHeaderHeight =
      18 + _panelTitleFontSize * 1.2 + 4 + 12 + 12;

  /// List viewport height inside the card body (shell chrome already excluded).
  static double listViewportHeight({
    required double maxHeight,
    required bool fillHeight,
    required double chromeAboveList,
  }) {
    if (!fillHeight || !maxHeight.isFinite || maxHeight <= 0) {
      return homeListMinHeight;
    }
    final listH = maxHeight - chromeAboveList;
    return listH < homeListMinHeight ? homeListMinHeight : listH;
  }
}

class _AsanaHomePanelState extends State<AsanaHomePanel> {
  final Map<String, bool> _expanded = {
    'created': true,
    'assigned': true,
    'people': true,
    'projects': true,
  };

  void _toggleSection(String key) {
    setState(() => _expanded[key] = !(_expanded[key] ?? true));
  }

  AsanaLandingPalette get palette => widget.palette;

  static String _formatHeaderDate(DateTime today) {
    final main = DateFormat('MMM d, yyyy').format(today);
    final weekday = DateFormat('EEEE').format(today);
    return '$main ($weekday)';
  }

  static List<Task> _activeSingularTasks(AppState state) {
    return state
        .tasksForTeams({})
        .where((t) {
          if (!t.isSingularTableRow) return false;
          final ds = t.dbStatus?.trim().toLowerCase() ?? '';
          return ds != 'delete' && ds != 'deleted';
        })
        .toList();
  }

  static String _greetingDisplayName(AppState state) {
    final id = state.userStaffAppId?.trim();
    if (id != null && id.isNotEmpty) {
      final name = state.assigneeById(id)?.name.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return 'there';
  }

  static String _greetingPhrase() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _picLine(AppState state, String? picKey) {
    final key = picKey?.trim();
    if (key == null || key.isEmpty) return '—';
    return state.assigneeById(key)?.name.trim() ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final today = HkTime.todayDateOnlyHk();
    final dateLine = _formatHeaderDate(today);
    final greeting = '${_greetingPhrase()}, ${_greetingDisplayName(state)}';

    final all = _activeSingularTasks(state);
    final created =
        all.where(state.taskIsCreatedByCurrentUser).toList()..sort(_sortByDue);
    final assigned = all
        .where((t) => AsanaTaskFilter.taskAssignedToCurrentUser(state, t))
        .toList()
      ..sort(_sortByDue);

    final people = _peopleRows(state, all, today);

    final projects = state.projects;
    final projectsCreated = projects
        .where((p) => AsanaProjectFilter.projectCreatedByCurrentUser(state, p))
        .toList()
      ..sort(_sortProjectsByDue);
    final projectsAssigned = projects
        .where((p) => AsanaProjectFilter.projectAssignedToCurrentUser(state, p))
        .toList()
      ..sort(_sortProjectsByDue);

    return ColoredBox(
      color: palette.panelBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    dateLine,
                    style: asanaTextStyle(
                      Theme.of(context).textTheme.bodyMedium,
                      fontSize: 14,
                      color: kAsanaTextSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const _HomeHeaderBrand(),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              greeting,
              style: asanaTextStyle(
                Theme.of(context).textTheme.headlineMedium,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: kAsanaTextPrimary,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useSingleColumn =
                      constraints.maxWidth <
                      AsanaHomePanel._twoColumnGridMinWidth;
                  final allowCollapse = useSingleColumn;
                  // Narrow: fixed min card height, stack may extend below viewport.
                  // Wide: cards fill grid cells (min height still enforced).
                  final fillHeight = !useSingleColumn;
                  final layoutKey = useSingleColumn ? 'stack' : 'grid';
                  final createdCard = _HomeTaskCard(
                    key: ValueKey('home-created-$layoutKey'),
                    palette: palette,
                    title: "Tasks I've created",
                    tasks: created,
                    middleHeader: 'PIC',
                    middleValue: (t) => _picLine(state, t.pic),
                    onOpenTask: widget.onOpenTask,
                    expanded:
                        allowCollapse ? (_expanded['created'] ?? true) : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('created')
                        : null,
                    fillHeight: fillHeight,
                  );
                  final assignedCard = _HomeTaskCard(
                    key: ValueKey('home-assigned-$layoutKey'),
                    palette: palette,
                    title: 'Tasks assigned to me',
                    tasks: assigned,
                    middleHeader: 'Creator',
                    middleValue: (t) =>
                        t.createByStaffName?.trim().isNotEmpty == true
                            ? t.createByStaffName!.trim()
                            : '—',
                    onOpenTask: widget.onOpenTask,
                    expanded: allowCollapse
                        ? (_expanded['assigned'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('assigned')
                        : null,
                    fillHeight: fillHeight,
                  );
                  final peopleCard = _HomePeopleCard(
                    key: ValueKey('home-people-$layoutKey'),
                    palette: palette,
                    rows: people,
                    expanded:
                        allowCollapse ? (_expanded['people'] ?? true) : true,
                    onToggleExpanded:
                        allowCollapse ? () => _toggleSection('people') : null,
                    fillHeight: fillHeight,
                  );
                  final projectsCard = _HomeProjectsCard(
                    key: ValueKey('home-projects-$layoutKey'),
                    palette: palette,
                    created: projectsCreated,
                    assigned: projectsAssigned,
                    onOpenProject: widget.onOpenProject,
                    expanded: allowCollapse
                        ? (_expanded['projects'] ?? true)
                        : true,
                    onToggleExpanded: allowCollapse
                        ? () => _toggleSection('projects')
                        : null,
                    fillHeight: fillHeight,
                  );

                  if (useSingleColumn) {
                    // Cards keep min height; stack may extend below viewport (clip, no page scroll).
                    return KeyedSubtree(
                      key: const ValueKey('home-stacked'),
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _stackedHomeSections(
                                  cards: [
                                    createdCard,
                                    assignedCard,
                                    peopleCard,
                                    projectsCard,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return KeyedSubtree(
                    key: const ValueKey('home-grid'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: createdCard),
                              const SizedBox(width: AsanaHomePanel._gridGap),
                              Expanded(child: assignedCard),
                            ],
                          ),
                        ),
                        const SizedBox(height: AsanaHomePanel._gridGap),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: peopleCard),
                              const SizedBox(width: AsanaHomePanel._gridGap),
                              Expanded(child: projectsCard),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stackedHomeSections({required List<Widget> cards}) {
    final out = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) out.add(const SizedBox(height: AsanaHomePanel._gridGap));
      out.add(cards[i]);
    }
    return out;
  }

  static int _sortByDue(Task a, Task b) {
    final ae = a.endDate;
    final be = b.endDate;
    if (ae == null && be == null) return a.name.compareTo(b.name);
    if (ae == null) return 1;
    if (be == null) return -1;
    final c = ae.compareTo(be);
    return c != 0 ? c : a.name.compareTo(b.name);
  }

  static int _sortProjectsByDue(ProjectRecord a, ProjectRecord b) {
    final ae = a.endDate;
    final be = b.endDate;
    if (ae == null && be == null) return a.name.compareTo(b.name);
    if (ae == null) return 1;
    if (be == null) return -1;
    final c = ae.compareTo(be);
    return c != 0 ? c : a.name.compareTo(b.name);
  }

  static List<_PersonTaskSummary> _peopleRows(
    AppState state,
    List<Task> tasks,
    DateTime today,
  ) {
    final rows = <_PersonTaskSummary>[];
    final mine = state.userStaffAppId?.trim();
    final myUuid = state.userStaffId?.trim();
    if (mine != null && mine.isNotEmpty) {
      final me = state.assigneeById(mine);
      rows.add(
        _PersonTaskSummary(
          name: me?.name.trim().isNotEmpty == true ? me!.name.trim() : mine,
          counts: _countsForStaff(state, tasks, today, mine, myUuid),
          isSelf: true,
        ),
      );
    }
    final subs = List<String>.from(state.subordinateAppIds)..sort((a, b) {
        final na = state.assigneeById(a)?.name.trim() ?? a;
        final nb = state.assigneeById(b)?.name.trim() ?? b;
        return na.compareTo(nb);
      });
    for (final appId in subs) {
      final a = state.assigneeById(appId);
      String? staffUuid;
      for (final u in state.subordinateStaffUuids) {
        final linked = state.assigneeById(u)?.id;
        if (linked == appId || u == appId) {
          staffUuid = u;
          break;
        }
      }
      rows.add(
        _PersonTaskSummary(
          name: a?.name.trim().isNotEmpty == true ? a!.name.trim() : appId,
          counts: _countsForStaff(state, tasks, today, appId, staffUuid),
        ),
      );
    }
    return rows;
  }

  static bool _taskMatchesStaff(
    AppState state,
    Task t,
    String appId,
    String? staffUuid,
  ) {
    final pic = t.pic?.trim();
    if (pic != null && pic.isNotEmpty) {
      if (pic == appId) return true;
      if (staffUuid != null &&
          pic.toLowerCase() == staffUuid.toLowerCase()) {
        return true;
      }
    }
    for (final id in t.assigneeIds) {
      final x = id.trim();
      if (x == appId) return true;
      if (staffUuid != null && x.toLowerCase() == staffUuid.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  static _TaskCounts _countsForStaff(
    AppState state,
    List<Task> tasks,
    DateTime today,
    String appId,
    String? staffUuid,
  ) {
    var overdue = 0;
    var incomplete = 0;
    var completed = 0;
    var upcoming = 0;
    for (final t in tasks) {
      if (!_taskMatchesStaff(state, t, appId, staffUuid)) continue;
      if (_isCompleted(t)) {
        completed++;
        continue;
      }
      final due = _dateOnly(t.endDate);
      final start = _dateOnly(t.startDate);
      if (due != null && due.isBefore(today)) {
        overdue++;
      } else if (start != null && start.isAfter(today)) {
        upcoming++;
      } else {
        incomplete++;
      }
    }
    return _TaskCounts(
      overdue: overdue,
      incomplete: incomplete,
      completed: completed,
      upcoming: upcoming,
    );
  }

  static bool _isCompleted(Task t) {
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    return s == 'completed' ||
        s == 'complete' ||
        t.status == TaskStatus.done;
  }

  static DateTime? _dateOnly(DateTime? d) {
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }
}

class _TaskCounts {
  const _TaskCounts({
    required this.overdue,
    required this.incomplete,
    required this.completed,
    required this.upcoming,
  });

  final int overdue;
  final int incomplete;
  final int completed;
  final int upcoming;
}

class _HomeHeaderBrand extends StatelessWidget {
  const _HomeHeaderBrand();

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheH = (22 * dpr).round().clamp(1, 4096);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 22,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheHeight: cacheH,
          semanticLabel: 'Project Tracker logo',
        ),
        const SizedBox(width: 6),
        Text(
          'Project Tracker',
          style: asanaTextStyle(
            Theme.of(context).textTheme.bodyMedium,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kAsanaTextPrimary,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _PersonTaskSummary {
  const _PersonTaskSummary({
    required this.name,
    required this.counts,
    this.isSelf = false,
  });

  final String name;
  final _TaskCounts counts;
  final bool isSelf;
}

/// Single-line table cell with fixed width (headers and values align).
Widget _homeFixedCell({
  required double width,
  required Widget child,
  double height = AsanaHomePanel._taskRowHeight,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

String _homeLabeledMetaLine({
  required String label,
  required String value,
}) {
  final v = value.trim().isEmpty ? '—' : value.trim();
  return '$label: $v';
}

String _firstNameOnly(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == '—') return trimmed.isEmpty ? '—' : trimmed;
  final first = trimmed.split(',').first.trim();
  if (first.isEmpty) return trimmed;
  return first.split(RegExp(r'\s+')).first;
}

Widget _homeListViewport({
  required double height,
  required Widget child,
}) {
  return SizedBox(height: height, child: child);
}

class _HomeCardShell extends StatelessWidget {
  const _HomeCardShell({
    required this.palette,
    required this.title,
    required this.child,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final String title;
  final Widget child;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    final collapsible = onToggleExpanded != null;
    final titleStyle = asanaTextStyle(
      Theme.of(context).textTheme.titleLarge,
      fontSize: AsanaHomePanel._panelTitleFontSize,
      fontWeight: FontWeight.w700,
      color: kAsanaTextPrimary,
      height: 1.2,
    );

    if (!expanded) {
      return Material(
        color: palette.listSurface,
        borderRadius: BorderRadius.circular(AsanaHomePanel._cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: InkWell(
            onTap: collapsible ? onToggleExpanded : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title, style: titleStyle),
                  ),
                  if (collapsible)
                    Icon(
                      Icons.expand_more,
                      size: 22,
                      color: kAsanaTextSecondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildShell(BoxConstraints outer) {
      Widget body = child;
      if (fillHeight && outer.maxHeight.isFinite) {
        final bodyHeight = (outer.maxHeight - AsanaHomePanel._homeShellHeaderHeight)
            .clamp(AsanaHomePanel.homeListMinHeight, double.infinity);
        body = SizedBox(
          height: bodyHeight,
          width: double.infinity,
          child: child,
        );
      }
      return Material(
        color: palette.listSurface,
        borderRadius: BorderRadius.circular(AsanaHomePanel._cardRadius),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: collapsible ? onToggleExpanded : null,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: titleStyle),
                      ),
                      if (collapsible)
                        Icon(
                          Icons.expand_less,
                          size: 22,
                          color: kAsanaTextSecondary,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              body,
            ],
          ),
        ),
      );
    }

    final shell = fillHeight
        ? SizedBox.expand(
            child: LayoutBuilder(builder: (_, c) => buildShell(c)),
          )
        : LayoutBuilder(builder: (_, c) => buildShell(c));

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AsanaHomePanel.homeCardMinHeight,
      ),
      child: shell,
    );
  }
}

class _HomeTaskCard extends StatelessWidget {
  const _HomeTaskCard({
    super.key,
    required this.palette,
    required this.title,
    required this.tasks,
    required this.middleHeader,
    required this.middleValue,
    this.onOpenTask,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final String title;
  final List<Task> tasks;
  final String middleHeader;
  final String Function(Task task) middleValue;
  final void Function(String taskId)? onOpenTask;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _HomeCardShell(
      palette: palette,
      title: title,
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = constraints.maxWidth;
          final compact = AsanaHomePanel.homeUseCompact(cardWidth);
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: compact
                ? 1
                : AsanaHomePanel._homeTaskTableChromeAboveList,
          );
          if (compact) {
            return _HomeTaskCompactList(
              tasks: tasks,
              middleHeader: middleHeader,
              middleValue: middleValue,
              onOpenTask: onOpenTask,
              listHeight: listH,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _HomeTaskTableHeader(middleHeader: middleHeader),
              Divider(height: 1, color: Colors.grey.shade300),
              _homeListViewport(
                height: listH,
                child: _homeTaskListBody(
                  context: context,
                  tasks: tasks,
                  middleHeader: middleHeader,
                  middleValue: middleValue,
                  onOpenTask: onOpenTask,
                  compact: false,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _homeTaskListBody({
  required BuildContext context,
  required List<Task> tasks,
  required String Function(Task task) middleValue,
  required void Function(String taskId)? onOpenTask,
  required bool compact,
  required String middleHeader,
}) {
  if (tasks.isEmpty) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'No tasks to show.',
          style: asanaTableRowValueStyle(context),
        ),
      ),
    );
  }

  Widget rowAt(int index) {
    final t = tasks[index];
    if (compact) {
      return _HomeTaskCompactRow(
        task: t,
        middleHeader: middleHeader,
        middle: middleValue(t),
        onTap: onOpenTask == null ? null : () => onOpenTask(t.id),
      );
    }
    return _HomeTaskRow(
      task: t,
      middle: middleValue(t),
      onTap: onOpenTask == null ? null : () => onOpenTask(t.id),
    );
  }

  return ListView.separated(
    primary: false,
    itemCount: tasks.length,
    separatorBuilder: (_, _) => Divider(
      height: 1,
      color: Colors.grey.shade200,
    ),
    itemBuilder: (context, index) => rowAt(index),
  );
}

class _HomeTaskCompactList extends StatelessWidget {
  const _HomeTaskCompactList({
    required this.tasks,
    required this.middleHeader,
    required this.middleValue,
    required this.listHeight,
    this.onOpenTask,
  });

  final List<Task> tasks;
  final String middleHeader;
  final String Function(Task task) middleValue;
  final double listHeight;
  final void Function(String taskId)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: Colors.grey.shade300),
        _homeListViewport(
          height: listHeight,
          child: _homeTaskListBody(
            context: context,
            tasks: tasks,
            middleHeader: middleHeader,
            middleValue: middleValue,
            onOpenTask: onOpenTask,
            compact: true,
          ),
        ),
      ],
    );
  }
}

class _HomeTaskTableHeader extends StatelessWidget {
  const _HomeTaskTableHeader({required this.middleHeader});

  final String middleHeader;

  @override
  Widget build(BuildContext context) {
    final style = asanaTableHeaderStyle(context);
    const headerH = AsanaHomePanel._taskRowHeight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: headerH,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Task Name', style: style),
              ),
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homePicColWidth,
            label: middleHeader,
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeDueColWidth,
            label: 'Due Date',
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeSubmissionColWidth,
            label: 'Submission',
            style: style,
            rowHeight: headerH,
          ),
        ],
      ),
    );
  }
}

class _HomeTaskRow extends StatelessWidget {
  const _HomeTaskRow({
    required this.task,
    required this.middle,
    this.onTap,
  });

  final Task task;
  final String middle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim();
    final valueStyle = asanaTableRowValueStyle(context);
    final nameStyle = asanaTableRowNameStyle(context);

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AsanaHomePanel._taskRowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                name,
                style: nameStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            asanaTextColumnGap(),
            _homeFixedCell(
              width: AsanaHomePanel._homePicColWidth,
              child: Text(
                middle,
                style: valueStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            asanaTextColumnGap(),
            _homeFixedCell(
              width: AsanaHomePanel._homeDueColWidth,
              child: Text(
                _formatDueDate(task.endDate),
                style: valueStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            asanaTextColumnGap(),
            _homeFixedCell(
              width: AsanaHomePanel._homeSubmissionColWidth,
              child: AsanaSubmissionChip(
                submission: task.submission,
                preserveFullLabel: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-line row: task name, then `PIC: … · Due Date: …` + submission chip.
class _HomeTaskCompactRow extends StatelessWidget {
  const _HomeTaskCompactRow({
    required this.task,
    required this.middleHeader,
    required this.middle,
    this.onTap,
  });

  final Task task;
  final String middleHeader;
  final String middle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = task.name.trim().isEmpty ? '(Unnamed task)' : task.name.trim();
    final nameStyle = asanaTableRowNameStyle(context);
    final metaStyle = asanaTableRowValueStyle(context);
    final metaLine = [
      _homeLabeledMetaLine(label: middleHeader, value: middle),
      _homeLabeledMetaLine(
        label: 'Due',
        value: _formatDueDate(task.endDate),
      ),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: AsanaHomePanel._taskRowCompactHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              name,
              style: nameStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    metaLine,
                    style: metaStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                AsanaSubmissionChip(
                  submission: task.submission,
                  preserveFullLabel: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePeopleCard extends StatelessWidget {
  const _HomePeopleCard({
    super.key,
    required this.palette,
    required this.rows,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final List<_PersonTaskSummary> rows;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _HomeCardShell(
      palette: palette,
      title: 'People',
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final list = rows.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    'No people to show.',
                    style: asanaTableRowValueStyle(context),
                  ),
                )
              : ListView.separated(
                  primary: false,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                  ),
                  itemBuilder: (context, index) {
                    return _HomePeopleRow(
                      palette: palette,
                      summary: rows[index],
                      useMetricAcronym: false,
                    );
                  },
                );
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: 0,
          );
          return _homeListViewport(height: listH, child: list);
        },
      ),
    );
  }
}

class _HomePeopleRow extends StatelessWidget {
  const _HomePeopleRow({
    required this.palette,
    required this.summary,
    required this.useMetricAcronym,
  });

  final AsanaLandingPalette palette;
  final _PersonTaskSummary summary;
  final bool useMetricAcronym;

  @override
  Widget build(BuildContext context) {
    final nameStyle = asanaTableRowNameStyle(context)?.copyWith(
      fontWeight: summary.isSelf ? FontWeight.w700 : FontWeight.w600,
    );
    final c = summary.counts;
    final chips = [
      _HomeMetricChip(
        palette: palette,
        count: c.overdue,
        label: 'overdue',
        metric: 'overdue',
        useAcronym: useMetricAcronym,
      ),
      _HomeMetricChip(
        palette: palette,
        count: c.incomplete,
        label: 'incomplete',
        metric: 'incomplete',
        useAcronym: useMetricAcronym,
      ),
      _HomeMetricChip(
        palette: palette,
        count: c.completed,
        label: 'completed',
        metric: 'completed',
        useAcronym: useMetricAcronym,
      ),
      _HomeMetricChip(
        palette: palette,
        count: c.upcoming,
        label: 'upcoming',
        metric: 'upcoming',
        useAcronym: useMetricAcronym,
      ),
    ];

    final metrics = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chips[0],
            const SizedBox(width: 6),
            chips[1],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chips[2],
            const SizedBox(width: 6),
            chips[3],
          ],
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (useMetricAcronym)
            SizedBox(
              width: AsanaHomePanel._homePeopleNameMinWidth,
              child: Text(
                summary.name,
                style: nameStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AsanaHomePanel._homePeopleNameMinWidth,
                ),
                child: Text(
                  summary.name,
                  style: nameStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          const SizedBox(width: 8),
          metrics,
        ],
      ),
    );
  }
}

class _HomeMetricChip extends StatelessWidget {
  const _HomeMetricChip({
    required this.palette,
    required this.count,
    required this.label,
    required this.metric,
    this.useAcronym = false,
  });

  final AsanaLandingPalette palette;
  final int count;
  final String label;
  final String metric;
  final bool useAcronym;

  static String _displayLabel(String label, bool acronym) {
    if (!acronym) return label;
    switch (label) {
      case 'overdue':
        return 'OVD';
      case 'incomplete':
        return 'INC';
      case 'completed':
        return 'CMP';
      case 'upcoming':
        return 'UPC';
      default:
        return label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = palette.homeMetricStyle(metric);
    final shown = _displayLabel(label, useAcronym);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count $shown',
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodySmall,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
      ),
    );
    if (!useAcronym) return chip;
    return Tooltip(
      message: '$count $label',
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }
}

class _HomeProjectsCard extends StatelessWidget {
  const _HomeProjectsCard({
    super.key,
    required this.palette,
    required this.created,
    required this.assigned,
    this.onOpenProject,
    this.expanded = true,
    this.onToggleExpanded,
    this.fillHeight = false,
  });

  final AsanaLandingPalette palette;
  final List<ProjectRecord> created;
  final List<ProjectRecord> assigned;
  final void Function(String projectId)? onOpenProject;
  final bool expanded;
  final VoidCallback? onToggleExpanded;
  final bool fillHeight;

  List<Widget> _projectSection({
    required BuildContext context,
    required AppState state,
    required bool compact,
    required String bannerTitle,
    required List<ProjectRecord> projects,
  }) {
    if (projects.isEmpty) return [];
    return [
      _HomeSectionBanner(
        palette: palette,
        title: bannerTitle,
      ),
      if (!compact) const _HomeProjectTableHeader(),
      ...projects.map(
        (p) => compact
            ? _HomeProjectCompactRow(
                project: p,
                appState: state,
                onTap: onOpenProject == null
                    ? null
                    : () => onOpenProject!(p.id),
              )
            : _HomeProjectRow(
                project: p,
                appState: state,
                onTap: onOpenProject == null
                    ? null
                    : () => onOpenProject!(p.id),
              ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return _HomeCardShell(
      palette: palette,
      title: 'Projects',
      expanded: expanded,
      onToggleExpanded: onToggleExpanded,
      fillHeight: fillHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final listH = AsanaHomePanel.listViewportHeight(
            maxHeight: constraints.maxHeight,
            fillHeight: fillHeight,
            chromeAboveList: 0,
          );
          if (created.isEmpty && assigned.isEmpty) {
            return _homeListViewport(
              height: listH,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'No projects to show.',
                  style: asanaTableRowValueStyle(context),
                ),
              ),
            );
          }
          final compact =
              AsanaHomePanel.homeUseCompact(constraints.maxWidth);
          final children = <Widget>[
            ..._projectSection(
              context: context,
              state: state,
              compact: compact,
              bannerTitle: "Projects I've created",
              projects: created,
            ),
            if (created.isNotEmpty && assigned.isNotEmpty)
              const SizedBox(height: 12),
            ..._projectSection(
              context: context,
              state: state,
              compact: compact,
              bannerTitle: 'Projects assigned to me',
              projects: assigned,
            ),
          ];

          return _homeListViewport(
            height: listH,
            child: ListView(
              primary: false,
              children: children,
            ),
          );
        },
      ),
    );
  }
}

class _HomeSectionBanner extends StatelessWidget {
  const _HomeSectionBanner({
    required this.palette,
    required this.title,
  });

  final AsanaLandingPalette palette;
  final String title;

  @override
  Widget build(BuildContext context) {
    final bg = palette.darkChrome
        ? palette.selectedNav
        : Color.alphaBlend(
            palette.accent.withValues(alpha: 0.14),
            palette.listSurface,
          );
    final fg = palette.darkChrome ? palette.onSidebar : palette.accent;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        title,
        style: asanaTextStyle(
          Theme.of(context).textTheme.labelLarge,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _HomeProjectTableHeader extends StatelessWidget {
  const _HomeProjectTableHeader();

  @override
  Widget build(BuildContext context) {
    final style = asanaTableHeaderStyle(context);
    const headerH = AsanaHomePanel._taskRowHeight;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SizedBox(
              height: headerH,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Project Name', style: style),
              ),
            ),
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homePicColWidth,
            label: 'PIC',
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeDueColWidth,
            label: 'Due Date',
            style: style,
            rowHeight: headerH,
          ),
          asanaTextColumnGap(),
          asanaTableHeaderLabel(
            width: AsanaHomePanel._homeStatusColWidth,
            label: 'Status',
            style: style,
            rowHeight: headerH,
          ),
        ],
      ),
    );
  }
}

class _HomeProjectRow extends StatelessWidget {
  const _HomeProjectRow({
    required this.project,
    required this.appState,
    this.onTap,
  });

  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        project.name.trim().isEmpty ? '(Unnamed project)' : project.name.trim();
    final completed = project.status.trim() == 'Completed';
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
    );
    final valueStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: Colors.grey.shade200),
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AsanaHomePanel._taskRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: nameStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homePicColWidth,
                  child: Text(
                    _firstNameOnly(
                      AsanaProjectFilter.picLine(project, appState),
                    ),
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homeDueColWidth,
                  child: Text(
                    _formatDueDate(project.endDate),
                    style: valueStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                asanaTextColumnGap(),
                _homeFixedCell(
                  width: AsanaHomePanel._homeStatusColWidth,
                  child: AsanaStatusChip(
                    status: project.status,
                    preserveFullLabel: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Two-line project row: name, then `PIC: … · Due Date: …` + status chip.
class _HomeProjectCompactRow extends StatelessWidget {
  const _HomeProjectCompactRow({
    required this.project,
    required this.appState,
    this.onTap,
  });

  final ProjectRecord project;
  final AppState appState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name =
        project.name.trim().isEmpty ? '(Unnamed project)' : project.name.trim();
    final completed = project.status.trim() == 'Completed';
    final nameStyle = asanaTableRowNameStyle(
      context,
      completed: completed,
    );
    final metaStyle = asanaTableRowValueStyle(
      context,
      completed: completed,
    );
    final metaLine = [
      _homeLabeledMetaLine(
        label: 'PIC',
        value: _firstNameOnly(
          AsanaProjectFilter.picLine(project, appState),
        ),
      ),
      _homeLabeledMetaLine(
        label: 'Due',
        value: _formatDueDate(project.endDate),
      ),
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, color: Colors.grey.shade200),
        InkWell(
          onTap: onTap,
          child: SizedBox(
            height: AsanaHomePanel._taskRowCompactHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: nameStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        metaLine,
                        style: metaStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AsanaStatusChip(
                      status: project.status,
                      preserveFullLabel: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
