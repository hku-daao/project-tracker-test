import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/initiative.dart';
import '../../models/task.dart';
import '../../models/assignee.dart';
import '../../priority.dart';
import '../../widgets/task_list_card.dart';
import 'initiative_detail_screen.dart';

class InitiativeListScreen extends StatefulWidget {
  const InitiativeListScreen({super.key});

  @override
  State<InitiativeListScreen> createState() => _InitiativeListScreenState();
}

class _InitiativeListScreenState extends State<InitiativeListScreen> {
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
  final TextEditingController _taskSearchController = TextEditingController();
  final MenuController _filterMenuController = MenuController();
  bool _remindersExpanded = false;

  static const _statusIncomplete = 'incomplete';
  static const _statusCompleted = 'completed';
  static const _statusDeleted = 'deleted';

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
        onSelected: (_) => setState(() => _filterType = value),
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

  /// True when team/status filters, assignee, or search are not at default (all).
  bool get _hasTeamOrStatusFilterSelections =>
      _selectedTeamIds.isNotEmpty ||
      _selectedTaskStatuses.isNotEmpty ||
      _selectedAssigneeIds.isNotEmpty ||
      _taskSearchController.text.trim().isNotEmpty;

  void _clearTeamAndStatusFilters() {
    setState(() {
      _selectedTeamIds.clear();
      _selectedTaskStatuses.clear();
      _selectedAssigneeIds.clear();
      _taskSearchController.clear();
    });
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
    return parts.join(' · ');
  }

  List<Task> _applyTaskNameSearch(List<Task> tasks) {
    final q = _taskSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return tasks;
    return tasks.where((t) => t.name.toLowerCase().contains(q)).toList();
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
  void dispose() {
    _taskSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_filterType == 'my') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _filterType = 'all');
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

    bool nonDeletedMatchesTaskStatus(Task t) {
      if (_selectedTaskStatuses.isEmpty) return true;
      if (singularDeleted(t)) return false;
      if (t.isSingularTableRow) {
        if (_selectedTaskStatuses.contains(_statusIncomplete) &&
            singularIncomplete(t)) {
          return true;
        }
        if (_selectedTaskStatuses.contains(_statusCompleted) &&
            singularCompleted(t)) {
          return true;
        }
        return false;
      }
      if (_selectedTaskStatuses.contains(_statusIncomplete) &&
          t.status != TaskStatus.done) {
        return true;
      }
      if (_selectedTaskStatuses.contains(_statusCompleted) &&
          t.status == TaskStatus.done) {
        return true;
      }
      return false;
    }

    bool deletedMatchesTaskStatus(Task t) {
      if (!singularDeleted(t)) return false;
      if (_selectedTaskStatuses.isEmpty) return false;
      return _selectedTaskStatuses.contains(_statusDeleted);
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
    filteredTasks = _applyTaskNameSearch(filteredTasks);
    filteredDeletedTasks = _applyTaskNameSearch(filteredDeletedTasks);

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

              /// Matches [ListView] column: `Center` + `maxWidth: 700` + horizontal padding 16.
              final screenW = constraints.maxWidth + 32;
              final listColumnLeftInset = (screenW - min(700.0, screenW)) / 2;
              final searchMaxWidth = min(
                560.0,
                (constraints.maxWidth - listColumnLeftInset).clamp(
                  0.0,
                  double.infinity,
                ),
              );
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
                                    });
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
                                    setState(_selectedAssigneeIds.clear);
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
                                      });
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
                                  });
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
                                  });
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
                                  });
                                },
                                child: const Text('Deleted'),
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

              final searchField = TextField(
                controller: _taskSearchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Search tasks',
                  hintText: 'Search by task name',
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
                            });
                          },
                        )
                      : null,
                ),
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
                  const SizedBox(height: 12),
                  Padding(
                    padding: EdgeInsets.only(left: listColumnLeftInset),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: searchMaxWidth),
                        child: searchField,
                      ),
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
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child:
              filteredInitiatives.isEmpty &&
                  filteredTasks.isEmpty &&
                  filteredDeletedTasks.isEmpty
              ? Center(child: Text(_emptyListMessage()))
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (filteredInitiatives.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              'Initiatives',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          ...filteredInitiatives.map(
                            (init) =>
                                _buildInitiativeCard(context, state, init),
                          ),
                        ],
                        if (filteredTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: Text(
                              'Tasks',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: PicTeamColorLegend(),
                          ),
                          ...filteredTasks.map((t) => TaskListCard(task: t)),
                        ],
                        if (filteredDeletedTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 8),
                            child: Text(
                              'Deleted tasks',
                              style: Theme.of(context).textTheme.titleMedium
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
                          ...filteredDeletedTasks.map(
                            (t) => TaskListCard(task: t),
                          ),
                        ],
                      ],
                    ),
                  ),
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
