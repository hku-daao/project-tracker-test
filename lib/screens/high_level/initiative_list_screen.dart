import 'dart:async';
import 'dart:math' show max, min;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/initiative.dart';
import '../../models/singular_subtask.dart';
import '../../models/project_record.dart';
import '../../models/task.dart';
import '../../models/assignee.dart';
import '../../models/team.dart';
import '../../config/supabase_config.dart';
import '../../priority.dart';
import '../../services/landing_task_filters_storage.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../../utils/project_task_sort.dart';
import '../../widgets/task_list_card.dart';
import '../../widgets/singular_subtask_row_card.dart';
import '../../utils/subtask_list_sort.dart';
import 'initiative_detail_screen.dart';
import 'project_detail_screen.dart';
import 'subtask_detail_screen.dart';

/// Landing task list sort column (persisted as [storageKey]).
enum TaskListSortColumn {
  creator('creator'),
  assignee('assignee'),
  pic('pic'),
  startDate('startDate'),
  dueDate('dueDate'),
  lastUpdated('lastUpdated'),
  status('status'),
  submission('submission');

  const TaskListSortColumn(this.storageKey);
  final String storageKey;

  static TaskListSortColumn? fromStorage(String? s) {
    if (s == null || s.isEmpty) return null;
    // Legacy persisted column removed from UI — treat as **Due date** (task + sub-task).
    if (s == 'subtaskDueDate') return TaskListSortColumn.dueDate;
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
      case TaskListSortColumn.lastUpdated:
        return 'Last updated';
      case TaskListSortColumn.status:
        return 'Status';
      case TaskListSortColumn.submission:
        return 'Submission';
    }
  }
}

/// Sort columns for the Projects-only dashboard ([InitiativeListScreen.projectsOnlyDashboard]).
enum ProjectListSortColumn {
  creator,
  assignee,
  startDate,
  endDate,
  status;

  String get label {
    switch (this) {
      case ProjectListSortColumn.creator:
        return 'Creator';
      case ProjectListSortColumn.assignee:
        return 'Assignee';
      case ProjectListSortColumn.startDate:
        return 'Start date';
      case ProjectListSortColumn.endDate:
        return 'End date';
      case ProjectListSortColumn.status:
        return 'Status';
    }
  }
}

/// One row in the Customized flat list — either a task card or a sub-task card.
class _CustomizedFlatEntry {
  _CustomizedFlatEntry.task(this.task) : sub = null;
  _CustomizedFlatEntry.subtask(this.task, this.sub);

  final Task task;
  final SingularSubtask? sub;

  bool get isTaskRow => sub == null;
}

/// [SliverAppBar] for Default / Overview / Project when [InitiativeListScreen.dashboardScrollAppBar] is set.
class DashboardScrollAppBarConfig {
  const DashboardScrollAppBarConfig({
    required this.title,
    this.showDrawerMenuLeading = false,
    this.actions = const <Widget>[],
  });

  final String title;
  final bool showDrawerMenuLeading;
  final List<Widget> actions;
}

/// Keeps filters / chips / sort / search height stable while sliding off-screen on scroll down
/// and floating back on scroll up ([SliverPersistentHeader.floating]).
class _OverviewFiltersFloatingHeaderDelegate extends SliverPersistentHeaderDelegate {
  _OverviewFiltersFloatingHeaderDelegate({
    required this.extent,
    required this.child,
  });

  final double extent;
  final Widget child;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black26,
      clipBehavior: Clip.hardEdge,
      child: Align(
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _OverviewFiltersFloatingHeaderDelegate oldDelegate) {
    return extent != oldDelegate.extent || child != oldDelegate.child;
  }
}

class InitiativeListScreen extends StatefulWidget {
  const InitiativeListScreen({
    super.key,
    /// Dashboards → Customized: same filters/sort as landing; sub-tasks always visible on each card.
    this.customizedFlat = false,
    /// Views → Project: projects only (no tasks/sub-tasks); do not combine with [customizedFlat].
    this.projectsOnlyDashboard = false,
    /// Default / Overview / Project: [SliverAppBar] (floating, pinned, snap) in the same scroll view as content.
    this.dashboardScrollAppBar,
  });

  /// When true, initiatives are hidden and each [TaskListCard] shows sub-tasks without expand/collapse.
  final bool customizedFlat;

  /// When true, only project cards (search/filter/sort for projects).
  final bool projectsOnlyDashboard;

  /// When non-null, embeds a Material [SliverAppBar] + floating filter headers with list content.
  final DashboardScrollAppBarConfig? dashboardScrollAppBar;

  @override
  State<InitiativeListScreen> createState() => _InitiativeListScreenState();
}

class _InitiativeListScreenState extends State<InitiativeListScreen> {
  /// Landing list column max width ([TaskListCard] + search below filter chips).
  static const double _kLandingTaskListMaxWidth = 1100;

  /// Max width for team / status filter fields (readable on wide layouts).
  static const double _filterFieldMaxWidth = 420;

  /// Task landing / Overview floating filters header height.
  final GlobalKey _taskDashboardFiltersMeasureKey = GlobalKey();
  double _taskDashboardFiltersSliverExtent = 460;

  /// Project dashboard floating filters header height.
  final GlobalKey _projectDashboardFiltersMeasureKey = GlobalKey();
  double _projectDashboardFiltersSliverExtent = 440;

  /// "Filter by assignee" submenu: roster team, then multi-select teammates (tasks/initiatives).
  String? _filterAssigneeMenuTeamId;
  final Set<String> _filterAssigneeMenuStaffIds = {};

  /// "Filter by PIC" — [`task.pic`] as assignee key.
  String? _filterPicMenuTeamId;
  final Set<String> _filterPicMenuStaffIds = {};

  /// "Filter by creator" submenu: roster team, then multi-select teammates (tasks by creator).
  String? _filterCreatorMenuTeamId;
  final Set<String> _filterCreatorMenuStaffIds = {};

  late final ExpansibleController _filterAssigneeRootController;
  late final ExpansibleController _filterAssigneeTeamController;
  late final ExpansibleController _filterAssigneeTeammateTileController;
  late final ExpansibleController _filterPicRootController;
  late final ExpansibleController _filterPicTeamController;
  late final ExpansibleController _filterPicTeammateTileController;
  late final ExpansibleController _filterCreatorRootController;
  late final ExpansibleController _filterCreatorTeamController;
  late final ExpansibleController _filterCreatorTeammateTileController;
  late final ExpansibleController _filterStatusTileController;
  late final ExpansibleController _filterOverdueTileController;
  late final ExpansibleController _filterSubmissionTileController;
  late final ExpansibleController _filterCreateDateTileController;

  /// Create-date range filter (task `createdAt` / sub-task `createDate` on Customized).
  DateTime? _filterCreateDateStart;
  DateTime? _filterCreateDateEnd;

  /// Scope: `all` | `assigned` | `created` (chips vary by view; Overview uses "My created...").
  String _filterType = 'all';

  /// Subset of `incomplete` | `completed` | `deleted`. Empty = all statuses (label "All status").
  final Set<String> _selectedTaskStatuses = {};

  /// Subset of [_submissionPending]…[_submissionReturned]. Empty = all (label "All submission").
  final Set<String> _selectedSubmissionFilters = {};

  /// When true, only rows where [`Task.overdue`] or a sub-task's [`SingularSubtask.overdue`] is `Yes` (DB).
  bool _filterOverdueOnly = false;
  final TextEditingController _taskSearchController = TextEditingController();
  final MenuController _filterMenuController = MenuController();
  bool _remindersExpanded = false;

  /// Single-column sort for task lists on the landing page (null = default order).
  TaskListSortColumn? _taskSortColumn;
  /// For **Created date (default)** (`_taskSortColumn == null`): `false` = descending (newest first).
  bool _taskSortAscending = false;

  /// Projects-only dashboard: `staff.id` → `staff.app_id` (from Supabase maps).
  Map<String, String> _staffUuidToAppId = {};
  bool _staffMapsReady = false;

  /// Subset of project [`ProjectRecord.status`] values to show; empty = all.
  final Set<String> _selectedProjectStatusFilters = {};

  ProjectListSortColumn? _projectSortColumn;
  /// For **Created date (default)** (`_projectSortColumn == null`): `false` = descending (newest first).
  bool _projectSortAscending = false;

  /// Client-side paging for [TaskListCard] lists (search/filter unchanged; slice after).
  static const List<int> _landingTaskPageSizes = [25, 50, 100, 200];
  int _tasksPageSize = 50;
  int _tasksPageIndex = 0;
  int _deletedTasksPageIndex = 0;

  /// Bumped after editing a sub-task on the Customized page so grouped fetch refreshes.
  int _customizedFlatListRefreshSeq = 0;

  /// Min / max sub-task `due_date` per parent task id (singular tasks only); used for [TaskListSortColumn.dueDate].
  final Map<String, DateTime?> _subtaskMinDueByTaskId = {};
  final Map<String, DateTime?> _subtaskMaxDueByTaskId = {};
  /// Singular tasks only: after fetch, true if any non-deleted, non-completed sub-task has calendar due before HK today.
  final Map<String, bool> _subtaskHasOverdueByTaskId = {};
  /// Lowercased sub-task names + descriptions per parent task id (singular only); used for landing search.
  final Map<String, String> _subtaskSearchBlobByTaskId = {};
  /// Max `(comment.update_date ?? comment.create_date)` per task id ([comment] table).
  final Map<String, DateTime?> _taskCommentActivityByTaskId = {};
  /// Max `(subtask_comment.update_date ?? create_date)` per sub-task id.
  final Map<String, DateTime?> _subtaskCommentActivityBySubtaskId = {};
  String _cachedSingularTaskIdsSig = '';

  /// Bumped when a new sub-task prefetch starts or caches clear; stale [Future]s skip [setState].
  int _subtaskFetchGeneration = 0;

  /// Last trimmed search string used for sub-task blob cache; when it changes, blobs are cleared
  /// so a new [fetchSubtasksForTask] pass runs (avoids stale empty maps blocking matches).
  String _lastSubtaskSearchQueryForBlob = '';

  /// Normalized landing search string that [_subtaskServerSetsByToken] belongs to (see [_landingSearchNormalized]).
  String _subtaskServerQueryNormalized = '';

  /// Per search token: parent task ids with a non-deleted subtask matching that token in name/description.
  /// Populated by debounced [SupabaseService.fetchTaskIdsHavingSubtaskToken] so landing search does not
  /// depend only on sequential client-side sub-task prefetch.
  Map<String, Set<String>>? _subtaskServerSetsByToken;

  int _landingSubtaskServerSearchSeq = 0;
  Timer? _landingSubtaskServerSearchDebounce;

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

  /// Normalizes task/sub-task `submission` to a landing filter key (defaults to pending).
  static String _submissionFilterKeyRaw(String? submission) {
    final raw = submission?.trim().toLowerCase() ?? '';
    if (raw.isEmpty || raw == 'pending') return _submissionPending;
    if (raw == 'submitted') return _submissionSubmitted;
    if (raw == 'accepted') return _submissionAccepted;
    if (raw == 'returned') return _submissionReturned;
    return _submissionPending;
  }

  /// Normalizes [Task.submission] to a landing filter key (defaults to pending when empty/unknown).
  static String _submissionFilterKey(Task t) => _submissionFilterKeyRaw(t.submission);

  static bool _singularSubtaskCompleted(SingularSubtask s) {
    final x = s.status.trim().toLowerCase();
    return x == 'completed' || x == 'complete';
  }

  /// Matches [singularIncomplete] closure used in build for singular [`task`] rows.
  bool _singularTaskIncomplete(Task t) {
    if (!t.isSingularTableRow) return false;
    final s = t.dbStatus?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return true;
    return s == 'incomplete';
  }

  /// Completed filter without Incomplete: flat list only Completed tasks / Completed sub-tasks.
  bool get _overviewCompletedOnlyWithoutIncomplete =>
      widget.customizedFlat &&
      _selectedTaskStatuses.contains(_statusCompleted) &&
      !_selectedTaskStatuses.contains(_statusIncomplete);

  /// Overview customized flat: omit sub-task row per status/submission conflict rules.
  bool _customizedFlatShouldOmitSubtaskRow(Task t, SingularSubtask s) {
    if (!t.isSingularTableRow || !widget.customizedFlat) return false;

    // Incomplete selected: never list Completed sub-tasks under an Incomplete parent (task row only).
    if (_selectedTaskStatuses.contains(_statusIncomplete) &&
        _singularTaskIncomplete(t) &&
        _singularSubtaskCompleted(s)) {
      return true;
    }

    // Completed only (vs Incomplete): hide non-Completed sub-tasks everywhere.
    if (_overviewCompletedOnlyWithoutIncomplete && !_singularSubtaskCompleted(s)) {
      return true;
    }

    if (_selectedSubmissionFilters.length == 1) {
      final tk = _submissionFilterKey(t);
      final sk = _submissionFilterKeyRaw(s.submission);
      if (_selectedSubmissionFilters.contains(_submissionPending) &&
          tk == _submissionPending &&
          (sk == _submissionSubmitted ||
              sk == _submissionAccepted ||
              sk == _submissionReturned)) {
        return true;
      }
      if (_selectedSubmissionFilters.contains(_submissionSubmitted) &&
          tk == _submissionSubmitted &&
          (sk == _submissionAccepted ||
              sk == _submissionReturned ||
              sk == _submissionPending)) {
        return true;
      }
      if (_selectedSubmissionFilters.contains(_submissionAccepted) &&
          tk == _submissionAccepted &&
          (sk == _submissionSubmitted ||
              sk == _submissionReturned ||
              sk == _submissionPending)) {
        return true;
      }
      if (_selectedSubmissionFilters.contains(_submissionReturned) &&
          tk == _submissionReturned &&
          (sk == _submissionSubmitted ||
              sk == _submissionAccepted ||
              sk == _submissionPending)) {
        return true;
      }
    }

    return false;
  }

  /// Completed without Incomplete: never show a task row for an Incomplete parent (only Completed task rows and Completed sub-task rows).
  bool _customizedFlatHideIncompleteParentTaskRowWhenCompletedOnly(Task t) {
    if (!t.isSingularTableRow || !widget.customizedFlat) return false;
    if (!_overviewCompletedOnlyWithoutIncomplete) return false;
    return _singularTaskIncomplete(t);
  }

  /// On my plate as assignee — dark blue chip when selected.
  Widget _assignedToMeFilterIcon(bool selected) {
    return Icon(
      Icons.assignment_ind,
      size: 18,
      color: selected ? Colors.white : const Color(0xFF0D47A1),
    );
  }

  /// Tasks I created — same icon as the task flow bottom bar.
  Widget _myCreatedTasksFilterIcon(bool selected) {
    return Icon(
      Icons.assignment_outlined,
      size: 18,
      color: selected ? Colors.black87 : Colors.lightBlue.shade800,
    );
  }

  /// Projects I created — same icon as the project flow bottom bar.
  Widget _myCreatedProjectsFilterIcon(bool selected) {
    return Icon(
      Icons.folder_outlined,
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
    /// When set, constrains label width (e.g. long text + smaller type).
    double? labelMaxWidth,
    double? labelFontSize,
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
    final baseSize =
        labelFontSize ?? theme.textTheme.labelLarge?.fontSize ?? 14.0;
    final labelWidget = labelMaxWidth != null
        ? SizedBox(
            width: labelMaxWidth,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: baseSize,
                  color: onLabel,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          )
        : Text(label, maxLines: 1, softWrap: false);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        showCheckmark: false,
        avatar: leading,
        label: labelWidget,
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
          fontSize: labelMaxWidth == null ? baseSize : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
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

  bool get _filterCreateDateEngaged =>
      _filterCreateDateStart != null || _filterCreateDateEnd != null;

  /// Rolling window matching [_dateWithinLastRollingMonth] (HK calendar; inclusive).
  (DateTime start, DateTime end) _defaultCreateDateRangeHk() {
    final end = HkTime.todayDateOnlyHk();
    final start = end.subtract(const Duration(days: 30));
    return (start, end);
  }

  String _defaultCreateDateRangeSummary(DateFormat fmt) {
    final r = _defaultCreateDateRangeHk();
    return '${fmt.format(r.$1)} – ${fmt.format(r.$2)}';
  }

  /// True when status / submission / assignee / creator / search are not at default (all).
  bool get _hasTeamOrStatusFilterSelections =>
      _selectedTaskStatuses.isNotEmpty ||
      _filterOverdueOnly ||
      _selectedSubmissionFilters.isNotEmpty ||
      _filterAssigneeMenuStaffIds.isNotEmpty ||
      _filterPicMenuStaffIds.isNotEmpty ||
      _filterCreatorMenuStaffIds.isNotEmpty ||
      _filterCreateDateEngaged ||
      _taskSearchController.text.trim().isNotEmpty;

  void _clearTeamAndStatusFilters() {
    _landingSubtaskServerSearchDebounce?.cancel();
    setState(() {
      _selectedProjectStatusFilters.clear();
      _selectedTaskStatuses.clear();
      _selectedSubmissionFilters.clear();
      _filterOverdueOnly = false;
      _filterAssigneeMenuTeamId = null;
      _filterAssigneeMenuStaffIds.clear();
      _filterPicMenuTeamId = null;
      _filterPicMenuStaffIds.clear();
      _filterCreatorMenuTeamId = null;
      _filterCreatorMenuStaffIds.clear();
      _filterCreateDateStart = null;
      _filterCreateDateEnd = null;
      _taskSearchController.clear();
      _lastSubtaskSearchQueryForBlob = '';
      _subtaskMinDueByTaskId.clear();
      _subtaskMaxDueByTaskId.clear();
      _subtaskHasOverdueByTaskId.clear();
      _subtaskSearchBlobByTaskId.clear();
      _subtaskFetchGeneration++;
      _landingSubtaskServerSearchSeq++;
      _subtaskServerSetsByToken = null;
      _subtaskServerQueryNormalized = '';
      _tasksPageIndex = 0;
      _deletedTasksPageIndex = 0;
    });
    _persistLandingFilters();
    _collapseAllFilterMenuExpansionTiles();
  }

  void _collapseAllFilterMenuExpansionTiles() {
    _filterAssigneeRootController.collapse();
    _filterAssigneeTeamController.collapse();
    _filterAssigneeTeammateTileController.collapse();
    _filterPicRootController.collapse();
    _filterPicTeamController.collapse();
    _filterPicTeammateTileController.collapse();
    _filterCreatorRootController.collapse();
    _filterCreatorTeamController.collapse();
    _filterCreatorTeammateTileController.collapse();
    _filterStatusTileController.collapse();
    _filterOverdueTileController.collapse();
    _filterSubmissionTileController.collapse();
    _filterCreateDateTileController.collapse();
  }

  /// When the filter [MenuAnchor] closes (e.g. tap outside), reset all expansion tiles.
  void _onFilterMenuAnchorClosed() {
    _collapseAllFilterMenuExpansionTiles();
  }

  bool get _filterAssigneeRosterEngaged =>
      (_filterAssigneeMenuTeamId != null &&
          _filterAssigneeMenuTeamId!.isNotEmpty) ||
      _filterAssigneeMenuStaffIds.isNotEmpty;

  bool get _filterCreatorRosterEngaged =>
      (_filterCreatorMenuTeamId != null &&
          _filterCreatorMenuTeamId!.isNotEmpty) ||
      _filterCreatorMenuStaffIds.isNotEmpty;

  void _collapseAssigneeFilterExpansionIfEngaged() {
    if (!_filterAssigneeRosterEngaged) return;
    _filterAssigneeRootController.collapse();
    _filterAssigneeTeamController.collapse();
    _filterAssigneeTeammateTileController.collapse();
  }

  void _collapseCreatorFilterExpansionIfEngaged() {
    if (!_filterCreatorRosterEngaged) return;
    _filterCreatorRootController.collapse();
    _filterCreatorTeamController.collapse();
    _filterCreatorTeammateTileController.collapse();
  }

  /// After changing Status or Submission from a checkbox, hide roster panels if used.
  void _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange() {
    _collapseAssigneeFilterExpansionIfEngaged();
    _collapsePicFilterExpansionIfEngaged();
    _collapseCreatorFilterExpansionIfEngaged();
  }

  void _collapsePicFilterExpansionIfEngaged() {
    if (!_filterPicRosterEngaged) return;
    _filterPicRootController.collapse();
    _filterPicTeamController.collapse();
    _filterPicTeammateTileController.collapse();
  }

  bool get _filterPicRosterEngaged =>
      (_filterPicMenuTeamId != null && _filterPicMenuTeamId!.isNotEmpty) ||
      _filterPicMenuStaffIds.isNotEmpty;

  /// Accordion: only one of Assignee / Creator / Status / Overdue / Submission stays expanded.
  void _onTopLevelFilterSectionExpanded(String openedId) {
    if (openedId != 'assignee') {
      _filterAssigneeRootController.collapse();
      _filterAssigneeTeamController.collapse();
      _filterAssigneeTeammateTileController.collapse();
    }
    if (openedId != 'pic') {
      _filterPicRootController.collapse();
      _filterPicTeamController.collapse();
      _filterPicTeammateTileController.collapse();
    }
    if (openedId != 'creator') {
      _filterCreatorRootController.collapse();
      _filterCreatorTeamController.collapse();
      _filterCreatorTeammateTileController.collapse();
    }
    if (openedId != 'status') _filterStatusTileController.collapse();
    if (openedId != 'overdue') _filterOverdueTileController.collapse();
    if (openedId != 'submission') _filterSubmissionTileController.collapse();
    if (openedId != 'createDate') _filterCreateDateTileController.collapse();
  }

  /// Under Assignee or Creator: only Team or Teammate stays expanded.
  void _onTeamStaffNestedSectionExpanded({
    required String rootId,
    required String openedNestedId,
  }) {
    if (rootId == 'assignee') {
      if (openedNestedId != 'team') _filterAssigneeTeamController.collapse();
      if (openedNestedId != 'teammate') {
        _filterAssigneeTeammateTileController.collapse();
      }
    } else if (rootId == 'pic') {
      if (openedNestedId != 'team') _filterPicTeamController.collapse();
      if (openedNestedId != 'teammate') {
        _filterPicTeammateTileController.collapse();
      }
    } else if (rootId == 'creator') {
      if (openedNestedId != 'team') _filterCreatorTeamController.collapse();
      if (openedNestedId != 'teammate') {
        _filterCreatorTeammateTileController.collapse();
      }
    }
  }

  /// One-line summary inside the closed "Filter" control.
  String _filterMenuSummaryLine(AppState state) {
    final parts = <String>[];
    if (_filterCreatorMenuStaffIds.isNotEmpty) {
      final names =
          _filterCreatorMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('Creator: ${names.join(', ')}');
    }
    if (_filterAssigneeMenuStaffIds.isNotEmpty) {
      final names =
          _filterAssigneeMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('Assignee: ${names.join(', ')}');
    }
    if (_filterPicMenuStaffIds.isNotEmpty) {
      final names =
          _filterPicMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('PIC: ${names.join(', ')}');
    }
    {
      final fmt = DateFormat.yMMMd();
      if (_filterCreateDateEngaged) {
        final a = _filterCreateDateStart != null
            ? fmt.format(_filterCreateDateStart!)
            : '…';
        final b =
            _filterCreateDateEnd != null ? fmt.format(_filterCreateDateEnd!) : '…';
        parts.add('Created date: $a – $b');
      } else {
        parts.add(
          'Created date: ${_defaultCreateDateRangeSummary(fmt)} (default)',
        );
      }
    }
    if (_selectedTaskStatuses.isEmpty) {
      parts.add('All status');
    } else {
      parts.add(_statusFilterDisplayText());
    }
    if (_filterOverdueOnly) {
      parts.add('Overdue');
    }
    if (_selectedSubmissionFilters.isEmpty) {
      parts.add('All submission');
    } else {
      parts.add(_submissionFilterDisplayText());
    }
    return parts.join(' · ');
  }

  static String _landingSearchNormalized(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .join(' ');
  }

  static List<String> _landingSearchTokens(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Customized search: every token must appear in task name or description.
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

  /// Customized search: every token must appear in sub-task name or description.
  static bool _subtaskTextMatchesAllTokens(SingularSubtask s, List<String> tokens) {
    if (tokens.isEmpty) return false;
    final n = s.subtaskName.toLowerCase();
    final d = s.description.toLowerCase();
    for (final tkn in tokens) {
      if (!n.contains(tkn) && !d.contains(tkn)) return false;
    }
    return true;
  }

  void _scheduleLandingSubtaskServerSearch() {
    _landingSubtaskServerSearchDebounce?.cancel();
    final requestSeq = _landingSubtaskServerSearchSeq;
    _landingSubtaskServerSearchDebounce = Timer(
      const Duration(milliseconds: 320),
      () async {
        if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
        final raw = _taskSearchController.text;
        final norm = _landingSearchNormalized(raw);
        if (!SupabaseConfig.isConfigured || norm.isEmpty) {
          if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
          setState(() {
            _subtaskServerSetsByToken = null;
            _subtaskServerQueryNormalized = '';
          });
          return;
        }
        final tokens = _landingSearchTokens(raw);
        if (tokens.isEmpty) {
          if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
          setState(() {
            _subtaskServerSetsByToken = null;
            _subtaskServerQueryNormalized = '';
          });
          return;
        }
        final unique = tokens.toSet().toList();
        final map = <String, Set<String>>{};
        for (final tok in unique) {
          if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
          map[tok] = await SupabaseService.fetchTaskIdsHavingSubtaskToken(tok);
        }
        if (!mounted || requestSeq != _landingSubtaskServerSearchSeq) return;
        if (_landingSearchNormalized(_taskSearchController.text) != norm) return;
        setState(() {
          _subtaskServerSetsByToken = map;
          _subtaskServerQueryNormalized = norm;
        });
      },
    );
  }

  /// Each whitespace-separated keyword must appear in [Task.name], [Task.description],
  /// or any non-deleted sub-task’s `subtask_name` / `description` (case-insensitive).
  bool _taskMatchesLandingSearch(Task t, String query) {
    final tokens = _landingSearchTokens(query);
    if (tokens.isEmpty) return true;
    final norm = _landingSearchNormalized(query);
    final serverMap = _subtaskServerSetsByToken;
    final serverReady =
        serverMap != null && _subtaskServerQueryNormalized == norm;
    final name = t.name.toLowerCase();
    final desc = t.description.toLowerCase();
    final pn = (t.projectName ?? '').toLowerCase();
    final pd = (t.projectDescription ?? '').toLowerCase();
    final subBlob = t.isSingularTableRow
        ? (_subtaskSearchBlobByTaskId[t.id] ?? '')
        : '';
    for (final token in tokens) {
      final inTask = name.contains(token) ||
          desc.contains(token) ||
          pn.contains(token) ||
          pd.contains(token);
      final inSub = subBlob.contains(token);
      final inSubServer =
          serverReady && (serverMap[token]?.contains(t.id) ?? false);
      if (!inTask && !inSub && !inSubServer) return false;
    }
    return true;
  }

  /// DB: `subtask.subtask_name`, `subtask.description` (via [SingularSubtask]).
  static String _subtaskSearchBlobFromList(List<SingularSubtask> list) {
    final parts = <String>[];
    for (final st in list) {
      if (st.isDeleted) continue;
      parts.add(st.subtaskName);
      parts.add(st.description);
    }
    return parts.join(' ').trim().toLowerCase();
  }

  List<Task> _applyTaskSearch(List<Task> tasks) {
    final raw = _taskSearchController.text;
    if (_landingSearchNormalized(raw).isEmpty) return tasks;
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

  /// Normalizes to local calendar midnight for comparing task vs sub-task **due dates**.
  static DateTime? _landingCalendarDueDay(DateTime? d) {
    if (d == null) return null;
    return DateTime(d.year, d.month, d.day);
  }

  /// Ascending **Due date**: earliest calendar day among [Task.endDate] and all loaded sub-task dues.
  DateTime? _effectiveDueSortMin(Task t) {
    final taskDay = _landingCalendarDueDay(t.endDate);
    if (!t.isSingularTableRow) return taskDay;
    if (!_subtaskMaxDueByTaskId.containsKey(t.id)) return taskDay;
    DateTime? best;
    void pick(DateTime? d) {
      final n = _landingCalendarDueDay(d);
      if (n == null) return;
      if (best == null || n.isBefore(best!)) best = n;
    }
    pick(t.endDate);
    pick(_subtaskMinDueByTaskId[t.id]);
    return best;
  }

  /// Descending **Due date**: latest calendar day among [Task.endDate] and all loaded sub-task dues.
  DateTime? _effectiveDueSortMax(Task t) {
    final taskDay = _landingCalendarDueDay(t.endDate);
    if (!t.isSingularTableRow) return taskDay;
    if (!_subtaskMaxDueByTaskId.containsKey(t.id)) return taskDay;
    DateTime? best;
    void pick(DateTime? d) {
      final n = _landingCalendarDueDay(d);
      if (n == null) return;
      if (best == null || n.isAfter(best!)) best = n;
    }
    pick(t.endDate);
    pick(_subtaskMaxDueByTaskId[t.id]);
    return best;
  }

  String _singularTaskIdsSignature(AppState state) {
    final ids = state.tasks
        .where((t) => t.isSingularTableRow)
        .map((t) => t.id)
        .toList()
      ..sort();
    return ids.join('|');
  }

  void _scheduleSubtaskRowDataPrefetch(
    List<Task> tasks,
    List<Task> deletedTasks,
  ) {
    if (!SupabaseConfig.isConfigured) return;
    final needDue = _taskSortColumn == TaskListSortColumn.dueDate;
    final needBlob = _taskSearchController.text.trim().isNotEmpty;
    final needOverdue = _filterOverdueOnly;
    final needLastUpdated =
        !widget.customizedFlat && _taskSortColumn == TaskListSortColumn.lastUpdated;

    final seen = <String>{};
    final combined = <Task>[];
    for (final t in [...tasks, ...deletedTasks]) {
      if (!t.isSingularTableRow || seen.contains(t.id)) continue;
      seen.add(t.id);
      combined.add(t);
    }
    final singularIds = combined.map((t) => t.id).toList()..sort();

    /// Sort/filter aggregates (due date line, search blob, overdue chip, etc.).
    final idsForAggregates = singularIds.where((id) {
      final missingDue = needDue && !_subtaskMaxDueByTaskId.containsKey(id);
      final missingBlob =
          needBlob && !_subtaskSearchBlobByTaskId.containsKey(id);
      final missingOverdue =
          needOverdue && !_subtaskHasOverdueByTaskId.containsKey(id);
      return missingDue || missingBlob || missingOverdue;
    }).toList();

    /// Seed [_subtaskListMemoryCache] so [TaskListCard] avoids one round-trip per card (Default + Overview).
    final idsForCardCache = !widget.projectsOnlyDashboard
        ? singularIds
            .where((id) => !SupabaseService.hasSubtaskListCached(id))
            .toList()
        : <String>[];

    final mergedToFetch = <String>{
      ...idsForAggregates,
      ...idsForCardCache,
    }.toList()
      ..sort();

    final idsForCommentActivity = singularIds.where((id) {
      return needLastUpdated && !_taskCommentActivityByTaskId.containsKey(id);
    }).toList();
    if (idsForCommentActivity.isNotEmpty) {
      unawaited(_loadTaskCommentActivityForTasks(idsForCommentActivity));
    }
    if (mergedToFetch.isNotEmpty) {
      unawaited(_loadSubtaskRowDataForTasks(mergedToFetch));
    }
  }

  Future<void> _loadTaskCommentActivityForTasks(List<String> taskIds) async {
    if (taskIds.isEmpty) return;
    try {
      final m =
          await SupabaseService.fetchMaxTaskCommentActivityByTaskIds(taskIds);
      if (!mounted) return;
      setState(() {
        for (final e in m.entries) {
          _taskCommentActivityByTaskId[e.key] = e.value;
        }
      });
    } catch (_) {}
  }

  /// Writes aggregated sub-task fields for one parent task id into landing caches.
  void _applySubtaskPrefetchFromList(String id, List<SingularSubtask> list) {
    final minDue = TaskListCard.minSubtaskDueForSort(list);
    final maxDue = TaskListCard.maxSubtaskDueForSort(list);
    final blob = _subtaskSearchBlobFromList(list);
    var hasOverdueSub = false;
    for (final st in list) {
      if (st.isDeleted) continue;
      if (st.overdue == 'Yes') {
        hasOverdueSub = true;
        break;
      }
    }
    _subtaskMinDueByTaskId[id] = minDue;
    _subtaskMaxDueByTaskId[id] = maxDue;
    _subtaskSearchBlobByTaskId[id] = blob;
    _subtaskHasOverdueByTaskId[id] = hasOverdueSub;
  }

  /// Loads sub-task rows per task; updates maps **per task** so search (e.g. sub-task name "HKU")
  /// can match as soon as that task’s rows are loaded, not only after all tasks finish.
  ///
  /// Uses batched Supabase queries + one [setState] when possible; falls back to per-task fetch.
  ///
  /// [_subtaskFetchGeneration] is bumped when the singular-task id set changes so in-flight
  /// work after a cache clear does not call [setState].
  Future<void> _loadSubtaskRowDataForTasks(List<String> taskIds) async {
    final startGen = _subtaskFetchGeneration;
    if (taskIds.isEmpty) return;
    try {
      final grouped =
          await SupabaseService.fetchSubtasksGroupedForLandingPrefetch(taskIds);
      if (!mounted || startGen != _subtaskFetchGeneration) return;
      setState(() {
        for (final id in taskIds) {
          _applySubtaskPrefetchFromList(id, grouped[id] ?? []);
        }
      });
    } catch (_) {
      await _loadSubtaskRowDataForTasksSequentialFallback(taskIds, startGen);
    }
  }

  Future<void> _loadSubtaskRowDataForTasksSequentialFallback(
    List<String> taskIds,
    int startGen,
  ) async {
    for (final id in taskIds) {
      if (!mounted || startGen != _subtaskFetchGeneration) return;
      try {
        final list = await SupabaseService.fetchSubtasksForTask(id);
        if (!mounted || startGen != _subtaskFetchGeneration) return;
        setState(() => _applySubtaskPrefetchFromList(id, list));
      } catch (_) {
        if (!mounted || startGen != _subtaskFetchGeneration) return;
        setState(() => _applySubtaskPrefetchFromList(id, []));
      }
    }
  }

  List<Task> _sortTasks(List<Task> tasks, AppState state) {
    final asc = _taskSortAscending;
    if (_taskSortColumn == null) {
      final out = List<Task>.from(tasks);
      out.sort((a, b) {
        final c = _cmpDateForSort(a.createdAt, b.createdAt, asc);
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return out;
    }
    final col = _taskSortColumn!;
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
          final aKey = asc ? _effectiveDueSortMin(a) : _effectiveDueSortMax(a);
          final bKey = asc ? _effectiveDueSortMin(b) : _effectiveDueSortMax(b);
          c = _cmpDateForSort(aKey, bKey, asc);
          break;
        case TaskListSortColumn.lastUpdated:
          c = _cmpDateForSort(
            _taskLastActivityInstant(a),
            _taskLastActivityInstant(b),
            asc,
          );
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
    final raw = _taskSearchController.text.trim().toLowerCase();
    if (raw.isEmpty) return list;
    return list.where((i) => i.name.toLowerCase().contains(raw)).toList();
  }

  bool _dateWithinLastRollingMonth(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final today = HkTime.todayDateOnlyHk();
    final start = today.subtract(const Duration(days: 30));
    return !day.isBefore(start) && !day.isAfter(today);
  }

  bool _taskCreatedWithinLastMonth(Task t) =>
      _dateWithinLastRollingMonth(t.createdAt);

  bool _subtaskCreatedWithinLastMonth(SingularSubtask s) {
    final cd = s.createDate;
    if (cd == null) return false;
    return _dateWithinLastRollingMonth(cd);
  }

  static DateTime _dateOnlyCal(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  bool _calendarDayInCreateFilterRange(DateTime day) {
    if (!_filterCreateDateEngaged) return true;
    final s = _filterCreateDateStart != null
        ? _dateOnlyCal(_filterCreateDateStart!)
        : null;
    final e = _filterCreateDateEnd != null
        ? _dateOnlyCal(_filterCreateDateEnd!)
        : null;
    if (s != null && day.isBefore(s)) return false;
    if (e != null && day.isAfter(e)) return false;
    return true;
  }

  bool _rowPassesCreateDateForCustomized(Task t, SingularSubtask? sub) {
    final DateTime day;
    if (sub == null) {
      day = _dateOnlyCal(t.createdAt);
    } else {
      final cd = sub.createDate;
      day = cd == null ? _dateOnlyCal(t.createdAt) : _dateOnlyCal(cd);
    }
    if (_filterCreateDateEngaged) {
      return _calendarDayInCreateFilterRange(day);
    }
    if (sub == null) return _taskCreatedWithinLastMonth(t);
    return _subtaskCreatedWithinLastMonth(sub);
  }

  /// Sub-tasks for Overview flat list plus comment-activity maps for **Last updated** sort + meta line.
  Future<
      ({
        Map<String, List<SingularSubtask>> grouped,
        Map<String, DateTime?> taskCommentActivity,
        Map<String, DateTime?> subtaskCommentActivity,
      })> _futureGroupedForCustomized(
    List<Task> active,
    List<Task> deleted,
  ) async {
    final ids = <String>{};
    for (final t in active) {
      if (t.isSingularTableRow) ids.add(t.id);
    }
    for (final t in deleted) {
      if (t.isSingularTableRow) ids.add(t.id);
    }
    if (ids.isEmpty) {
      return (
        grouped: <String, List<SingularSubtask>>{},
        taskCommentActivity: <String, DateTime?>{},
        subtaskCommentActivity: <String, DateTime?>{},
      );
    }
    final idList = ids.toList();
    final grouped =
        await SupabaseService.fetchSubtasksGroupedForLandingPrefetch(idList);
    final subIds = <String>[];
    for (final list in grouped.values) {
      for (final s in list) {
        subIds.add(s.id);
      }
    }
    subIds.sort();
    final commentPair = await Future.wait([
      SupabaseService.fetchMaxTaskCommentActivityByTaskIds(idList),
      SupabaseService.fetchMaxSubtaskCommentActivityBySubtaskIds(subIds),
    ]);
    final taskCommentActivity =
        commentPair[0] as Map<String, DateTime?>;
    final subtaskCommentActivity =
        commentPair[1] as Map<String, DateTime?>;
    return (
      grouped: grouped,
      taskCommentActivity: taskCommentActivity,
      subtaskCommentActivity: subtaskCommentActivity,
    );
  }

  /// Prefer DB [`task.last_updated`]; else max of [Task.updateDate] and comment activity.
  DateTime? _taskLastActivityInstant(
    Task t, {
    Map<String, DateTime?>? taskCommentActivityOverride,
  }) {
    final lu = t.lastUpdated;
    if (lu != null) return lu;
    final tu = t.updateDate;
    final ca = taskCommentActivityOverride != null
        ? taskCommentActivityOverride[t.id]
        : _taskCommentActivityByTaskId[t.id];
    DateTime? best = tu;
    if (ca != null && (best == null || ca.isAfter(best))) best = ca;
    return best;
  }

  /// Prefer DB [`subtask.last_updated`]; else max of [SingularSubtask.updateDate] and comment activity.
  DateTime? _subtaskLastActivityInstant(
    SingularSubtask s, {
    Map<String, DateTime?>? subtaskCommentActivityOverride,
  }) {
    final lu = s.lastUpdated;
    if (lu != null) return lu;
    final su = s.updateDate;
    final ca = subtaskCommentActivityOverride != null
        ? subtaskCommentActivityOverride[s.id]
        : _subtaskCommentActivityBySubtaskId[s.id];
    DateTime? best = su;
    if (ca != null && (best == null || ca.isAfter(best))) best = ca;
    return best;
  }

  String? _lastUpdatedYmdFromInstant(DateTime? i) {
    if (i == null) return null;
    return DateFormat('yyyy-MM-dd').format(i.toLocal());
  }

  DateTime? _customizedLastUpdatedSortKey(
    _CustomizedFlatEntry e, {
    required Map<String, DateTime?> taskCommentActivity,
    required Map<String, DateTime?> subtaskCommentActivity,
  }) {
    if (e.isTaskRow) {
      return _taskLastActivityInstant(
        e.task,
        taskCommentActivityOverride: taskCommentActivity,
      );
    }
    return _subtaskLastActivityInstant(
      e.sub!,
      subtaskCommentActivityOverride: subtaskCommentActivity,
    );
  }

  List<_CustomizedFlatEntry> _buildCustomizedFlatEntries(
    List<Task> tasks,
    Map<String, List<SingularSubtask>> grouped,
    String searchRaw,
  ) {
    final tokens = _landingSearchTokens(searchRaw);
    final searchActive = tokens.isNotEmpty;
    final out = <_CustomizedFlatEntry>[];

    for (final t in tasks) {
      if (!t.isSingularTableRow) {
        if (_filterOverdueOnly) {
          if (t.overdue != 'Yes') continue;
          if (!searchActive) {
            if (_rowPassesCreateDateForCustomized(t, null)) {
              out.add(_CustomizedFlatEntry.task(t));
            }
          } else if (_taskTextMatchesAllTokens(t, tokens) &&
              _rowPassesCreateDateForCustomized(t, null)) {
            out.add(_CustomizedFlatEntry.task(t));
          }
          continue;
        }
        if (!searchActive) {
          if (_rowPassesCreateDateForCustomized(t, null)) {
            out.add(_CustomizedFlatEntry.task(t));
          }
        } else if (_taskTextMatchesAllTokens(t, tokens) &&
            _rowPassesCreateDateForCustomized(t, null)) {
          out.add(_CustomizedFlatEntry.task(t));
        }
        continue;
      }

      final subs = grouped[t.id] ?? [];
      final subsNonDeleted = subs.where((s) => !s.isDeleted).toList();

      if (_filterOverdueOnly) {
        if (t.overdue == 'Yes') {
          if (!searchActive) {
            if (_rowPassesCreateDateForCustomized(t, null)) {
              out.add(_CustomizedFlatEntry.task(t));
            }
          } else if (_taskTextMatchesAllTokens(t, tokens) &&
              _rowPassesCreateDateForCustomized(t, null)) {
            out.add(_CustomizedFlatEntry.task(t));
          }
        } else {
          for (final s in subsNonDeleted) {
            if (s.overdue != 'Yes') continue;
            if (_customizedFlatShouldOmitSubtaskRow(t, s)) continue;
            if (!searchActive) {
              if (_rowPassesCreateDateForCustomized(t, s)) {
                out.add(_CustomizedFlatEntry.subtask(t, s));
              }
            } else {
              if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
              if (!_rowPassesCreateDateForCustomized(t, s)) continue;
              out.add(_CustomizedFlatEntry.subtask(t, s));
            }
          }
        }
        continue;
      }

      if (!searchActive) {
        final subsInRange = subsNonDeleted
            .where((s) => _rowPassesCreateDateForCustomized(t, s))
            .where((s) => !_customizedFlatShouldOmitSubtaskRow(t, s))
            .toList();
        final taskInRange = _rowPassesCreateDateForCustomized(t, null);
        if (!taskInRange && subsInRange.isEmpty) continue;
        if (taskInRange &&
            !_customizedFlatHideIncompleteParentTaskRowWhenCompletedOnly(t)) {
          out.add(_CustomizedFlatEntry.task(t));
        }
        for (final s in subsInRange) {
          out.add(_CustomizedFlatEntry.subtask(t, s));
        }
        continue;
      }

      final taskTextMatch = _taskTextMatchesAllTokens(t, tokens);
      final taskRowAllowed = taskTextMatch &&
          _rowPassesCreateDateForCustomized(t, null);

      if (taskRowAllowed) {
        if (!_customizedFlatHideIncompleteParentTaskRowWhenCompletedOnly(t)) {
          out.add(_CustomizedFlatEntry.task(t));
        }
        continue;
      }

      for (final s in subsNonDeleted) {
        if (!_subtaskTextMatchesAllTokens(s, tokens)) continue;
        if (!_rowPassesCreateDateForCustomized(t, s)) continue;
        if (_customizedFlatShouldOmitSubtaskRow(t, s)) continue;
        out.add(_CustomizedFlatEntry.subtask(t, s));
      }
    }
    return out;
  }

  DateTime _customizedCreateInstant(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.createdAt;
    final cd = e.sub!.createDate;
    return cd ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  String? _customizedCreatorKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.createByStaffName;
    return e.sub!.createByStaffName;
  }

  String _customizedAssigneeKey(_CustomizedFlatEntry e, AppState state) {
    if (e.isTaskRow) return _assigneeSortKey(e.task, state);
    return SubtaskListSort.assigneeSortKey(
      e.sub!,
      (id) => state.assigneeById(id)?.name ?? id,
    );
  }

  String _customizedPicKey(_CustomizedFlatEntry e, AppState state) {
    if (e.isTaskRow) return _picSortKey(e.task, state);
    return SubtaskListSort.picSortKey(
      e.sub!,
      (id) => state.assigneeById(id)?.name ?? id,
    );
  }

  DateTime? _customizedStartKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.startDate;
    return e.sub!.startDate;
  }

  DateTime? _customizedDueKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) {
      return _landingCalendarDueDay(e.task.endDate);
    }
    return _landingCalendarDueDay(e.sub!.dueDate);
  }

  String _customizedStatusKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return TaskListCard.statusLabel(e.task);
    return e.sub!.status;
  }

  String _customizedSubmissionKey(_CustomizedFlatEntry e) {
    if (e.isTaskRow) return e.task.submission ?? '';
    return e.sub!.submission ?? '';
  }

  int _tieBreakCustomizedFlat(_CustomizedFlatEntry a, _CustomizedFlatEntry b) {
    final ta = a.isTaskRow ? a.task.name : a.sub!.subtaskName;
    final tb = b.isTaskRow ? b.task.name : b.sub!.subtaskName;
    return ta.toLowerCase().compareTo(tb.toLowerCase());
  }

  List<_CustomizedFlatEntry> _sortCustomizedFlatEntries(
    List<_CustomizedFlatEntry> rows,
    AppState state, {
    required Map<String, DateTime?> taskCommentActivity,
    required Map<String, DateTime?> subtaskCommentActivity,
  }) {
    if (rows.isEmpty) return rows;
    final col = _taskSortColumn;
    final asc = _taskSortAscending;
    final out = List<_CustomizedFlatEntry>.from(rows);
    out.sort((a, b) {
      int c;
      if (col == null) {
        c = _cmpDateForSort(
          _customizedCreateInstant(a),
          _customizedCreateInstant(b),
          asc,
        );
      } else {
        switch (col) {
          case TaskListSortColumn.creator:
            c = _cmpStrNullable(
              _customizedCreatorKey(a),
              _customizedCreatorKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.assignee:
            c = _cmpStrNullable(
              _customizedAssigneeKey(a, state),
              _customizedAssigneeKey(b, state),
              asc,
            );
            break;
          case TaskListSortColumn.pic:
            c = _cmpStrNullable(
              _customizedPicKey(a, state),
              _customizedPicKey(b, state),
              asc,
            );
            break;
          case TaskListSortColumn.startDate:
            c = _cmpDateForSort(
              _customizedStartKey(a),
              _customizedStartKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.dueDate:
            c = _cmpDateForSort(
              _customizedDueKey(a),
              _customizedDueKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.lastUpdated:
            c = _cmpDateForSort(
              _customizedLastUpdatedSortKey(
                a,
                taskCommentActivity: taskCommentActivity,
                subtaskCommentActivity: subtaskCommentActivity,
              ),
              _customizedLastUpdatedSortKey(
                b,
                taskCommentActivity: taskCommentActivity,
                subtaskCommentActivity: subtaskCommentActivity,
              ),
              asc,
            );
            break;
          case TaskListSortColumn.status:
            c = _cmpStrNullable(
              _customizedStatusKey(a),
              _customizedStatusKey(b),
              asc,
            );
            break;
          case TaskListSortColumn.submission:
            c = _cmpStrNullable(
              _customizedSubmissionKey(a),
              _customizedSubmissionKey(b),
              asc,
            );
            break;
        }
      }
      if (c != 0) return c;
      return _tieBreakCustomizedFlat(a, b);
    });
    return out;
  }

  Widget _customizedEntryTile(
    BuildContext context,
    AppState state,
    _CustomizedFlatEntry e, {
    required Map<String, DateTime?> taskCommentActivity,
    required Map<String, DateTime?> subtaskCommentActivity,
  }) {
    if (e.isTaskRow) {
      final lu = _lastUpdatedYmdFromInstant(
        _taskLastActivityInstant(
          e.task,
          taskCommentActivityOverride: taskCommentActivity,
        ),
      );
      return TaskListCard(
        task: e.task,
        taskOnly: true,
        showCustomizedTaskTitle: true,
        openedFromOverview: true,
        overviewLastUpdatedYmd: lu,
      );
    }
    final s = e.sub!;
    String resolveName(String id) => state.assigneeById(id)?.name ?? id;
    final picKey = s.pic?.trim();
    return FutureBuilder<String?>(
      future: (picKey == null || picKey.isEmpty)
          ? Future<String?>.value(null)
          : SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey),
      builder: (context, snap) {
        final tint = TaskListCard.cardColorForPicTeam(snap.data);
        final lu = _lastUpdatedYmdFromInstant(
          _subtaskLastActivityInstant(
            s,
            subtaskCommentActivityOverride: subtaskCommentActivity,
          ),
        );
        return SingularSubtaskRowCard(
          subtask: s,
          resolveName: resolveName,
          cardMargin: const EdgeInsets.only(bottom: 12),
          cardBackgroundColor: tint,
          showCustomizedLayout: true,
          parentTaskName: e.task.name,
          parentProjectName: e.task.projectName,
          overviewLastUpdatedYmd: lu,
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => SubtaskDetailScreen(
                  subtaskId: s.id,
                  replaceWithParentTaskOnBack: true,
                  openedFromOverview: true,
                ),
              ),
            );
            if (changed == true && mounted) {
              SupabaseService.clearSubtaskListMemoryCache();
              setState(() => _customizedFlatListRefreshSeq++);
            }
          },
        );
      },
    );
  }

  /// Filters field, clear-all, scope chips, sort, and search (shared by landing and Overview sliver scroll).
  Widget _buildLandingFiltersSortSearchSection(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted,
    String filterKey,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                onClose: _onFilterMenuAnchorClosed,
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
                              ..._landingFilterMenuSections(
                                context,
                                state,
                                teamsSorted,
                              ),
                              ..._landingCreateDateSection(context),
                              ..._landingStatusSubmissionSections(context),
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
                  final summaryLine = _filterMenuSummaryLine(state);
                  return Tooltip(
                    message: summaryLine,
                    child: InkWell(
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
                          summaryLine,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
        LayoutBuilder(
          builder: (context, constraints) {
            final listColumnMaxWidth = min(
              _kLandingTaskListMaxWidth,
              constraints.maxWidth,
            );
            final constrained = BoxConstraints(maxWidth: listColumnMaxWidth);
            Widget bandFiltersLeft(Widget child) {
              return Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: constrained,
                  child: child,
                ),
              );
            }

            Widget bandSearch(Widget child) {
              return Center(
                child: ConstrainedBox(
                  constraints: constrained,
                  child: child,
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bandFiltersLeft(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        primary: false,
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.only(right: 12),
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
                              leading: _assignedToMeFilterIcon(
                                filterKey == 'assigned',
                              ),
                            ),
                            _buildTaskFilterChip(
                              value: 'created',
                              label: widget.customizedFlat
                                  ? 'My created...'
                                  : 'My created tasks',
                              selected: filterKey == 'created',
                              selectedBg: Colors.lightBlue.shade200,
                              selectedLabelColor: Colors.black87,
                              leading: _myCreatedTasksFilterIcon(
                                filterKey == 'created',
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: SizedBox(
                                height: 32,
                                child: VerticalDivider(
                                  width: 1,
                                  thickness: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                'Sort',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            _buildTaskSortDropdown(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                bandSearch(
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: _buildLandingTaskSearchField(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  TextStyle _dashboardSliverAppBarTitleStyle(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ) ??
        const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        );
  }

  List<Widget> _buildDashboardScrollPrefixSlivers(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted, {
    required DashboardScrollAppBarConfig appBarConfig,
    required String filterKey,
    required double filtersHeaderExtent,
    required GlobalKey filtersMeasureKey,
    required Widget filtersHeaderChild,
  }) {
    final titleStyle = _dashboardSliverAppBarTitleStyle(context);
    return <Widget>[
      SliverAppBar(
        floating: true,
        pinned: true,
        snap: true,
        automaticallyImplyLeading: false,
        centerTitle: true,
        titleSpacing: 0,
        leading: appBarConfig.showDrawerMenuLeading
            ? Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              )
            : null,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            appBarConfig.title,
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: appBarConfig.actions,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      SliverPersistentHeader(
        pinned: false,
        floating: true,
        delegate: _OverviewFiltersFloatingHeaderDelegate(
          extent: filtersHeaderExtent,
          child: KeyedSubtree(
            key: filtersMeasureKey,
            child: filtersHeaderChild,
          ),
        ),
      ),
    ];
  }

  /// [SliverPersistentHeader] uses a fixed [extent]. Measuring [RenderBox.size]
  /// alone fails when content is taller than that extent: layout is clipped to
  /// the header max height, so [size.height] never grows and the search field
  /// stays squashed. [getMaxIntrinsicHeight] returns the full natural height.
  void _measureTaskDashboardFiltersSliverExtent() {
    final box =
        _taskDashboardFiltersMeasureKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return;
    final maxW = box.constraints.maxWidth;
    if (maxW <= 0 || !maxW.isFinite) return;
    final intrinsic = box.getMaxIntrinsicHeight(maxW);
    final h = max(box.size.height, intrinsic);
    if (h <= 0 || !h.isFinite) return;
    if ((h - _taskDashboardFiltersSliverExtent).abs() < 0.5) return;
    setState(() => _taskDashboardFiltersSliverExtent = h);
  }

  void _measureProjectDashboardFiltersSliverExtent() {
    final box =
        _projectDashboardFiltersMeasureKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return;
    final maxW = box.constraints.maxWidth;
    if (maxW <= 0 || !maxW.isFinite) return;
    final intrinsic = box.getMaxIntrinsicHeight(maxW);
    final h = max(box.size.height, intrinsic);
    if (h <= 0 || !h.isFinite) return;
    if ((h - _projectDashboardFiltersSliverExtent).abs() < 0.5) return;
    setState(() => _projectDashboardFiltersSliverExtent = h);
  }

  Widget _buildCustomizedFlatFullColumn(
    BuildContext context,
    AppState state,
    List<Task> filteredTasks,
    List<Task> filteredDeletedTasks, {
    List<Widget>? dashboardScrollPrefixSlivers,
  }) {
    return FutureBuilder<
        ({
          Map<String, List<SingularSubtask>> grouped,
          Map<String, DateTime?> taskCommentActivity,
          Map<String, DateTime?> subtaskCommentActivity,
        })>(
      key: ValueKey(
        '${filteredTasks.map((t) => t.id).join('|')}'
        '_${filteredDeletedTasks.map((t) => t.id).join('|')}'
        '_$_tasksPageIndex$_tasksPageSize$_deletedTasksPageIndex'
        '_$_customizedFlatListRefreshSeq'
        '_${_taskSearchController.text}'
        '_$_filterCreateDateStart$_filterCreateDateEnd'
        '_$_filterOverdueOnly',
      ),
      future: _futureGroupedForCustomized(filteredTasks, filteredDeletedTasks),
      builder: (context, snapshot) {
        final prefix = dashboardScrollPrefixSlivers;
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          if (prefix != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      ...prefix,
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        final payload = snapshot.data;
        final grouped = payload?.grouped ?? {};
        final taskCommentActivity = payload?.taskCommentActivity ?? {};
        final subtaskCommentActivity = payload?.subtaskCommentActivity ?? {};
        var activeEntries = _buildCustomizedFlatEntries(
          filteredTasks,
          grouped,
          _taskSearchController.text,
        );
        activeEntries = _sortCustomizedFlatEntries(
          activeEntries,
          state,
          taskCommentActivity: taskCommentActivity,
          subtaskCommentActivity: subtaskCommentActivity,
        );
        var delEntries = _buildCustomizedFlatEntries(
          filteredDeletedTasks,
          grouped,
          _taskSearchController.text,
        );
        delEntries = _sortCustomizedFlatEntries(
          delEntries,
          state,
          taskCommentActivity: taskCommentActivity,
          subtaskCommentActivity: subtaskCommentActivity,
        );

        if (activeEntries.isEmpty && delEntries.isEmpty) {
          if (prefix != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      ...prefix,
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No tasks or sub-tasks match your filters '
                              '(search, created date, and other filters).',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
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
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No tasks or sub-tasks match your filters '
                '(search, created date, and other filters).',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }

        final pagedActive = _landingPageSlice(
          activeEntries,
          _tasksPageIndex,
          _tasksPageSize,
        );
        final pagedDel = _landingPageSlice(
          delEntries,
          _deletedTasksPageIndex,
          _tasksPageSize,
        );

        final listChildren = <Widget>[
          if (filteredTasks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                'Tasks & sub-tasks (${activeEntries.length})',
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
            ...pagedActive.map(
              (e) => _customizedEntryTile(
                context,
                state,
                e,
                taskCommentActivity: taskCommentActivity,
                subtaskCommentActivity: subtaskCommentActivity,
              ),
            ),
          ],
          if (filteredDeletedTasks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Text(
                'Deleted tasks',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
          ],
          ...pagedDel.map(
            (e) => _customizedEntryTile(
              context,
              state,
              e,
              taskCommentActivity: taskCommentActivity,
              subtaskCommentActivity: subtaskCommentActivity,
            ),
          ),
        ];

        final paginationBar = (activeEntries.isNotEmpty || delEntries.isNotEmpty)
            ? Material(
                elevation: 6,
                shadowColor: Colors.black26,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kLandingTaskListMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (activeEntries.isNotEmpty)
                              _buildLandingTaskPaginationBar(
                                context: context,
                                totalCount: activeEntries.length,
                                pageIndex: _tasksPageIndex,
                                onPageChanged: (i) {
                                  setState(() => _tasksPageIndex = i);
                                },
                                showPageSizeDropdown: true,
                              ),
                            if (activeEntries.isNotEmpty &&
                                delEntries.isNotEmpty)
                              const Divider(height: 12),
                            if (delEntries.isNotEmpty)
                              _buildLandingTaskPaginationBar(
                                context: context,
                                totalCount: delEntries.length,
                                pageIndex: _deletedTasksPageIndex,
                                onPageChanged: (i) {
                                  setState(() => _deletedTasksPageIndex = i);
                                },
                                showPageSizeDropdown: false,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null;

        if (prefix != null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    ...prefix,
                    SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _kLandingTaskListMaxWidth,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: listChildren,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?paginationBar,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kLandingTaskListMaxWidth,
                  ),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: listChildren,
                  ),
                ),
              ),
            ),
            ?paginationBar,
          ],
        );
      },
    );
  }

  String _emptyListMessage() {
    if (_taskSearchController.text.trim().isNotEmpty) {
      return 'No tasks match your search.';
    }
    if (_hasTeamOrStatusFilterSelections) {
      return 'No tasks for this filter.';
    }
    return 'No tasks yet. Create one in the "Create task" tab.';
  }

  @override
  void initState() {
    super.initState();
    _filterAssigneeRootController = ExpansibleController();
    _filterAssigneeTeamController = ExpansibleController();
    _filterAssigneeTeammateTileController = ExpansibleController();
    _filterPicRootController = ExpansibleController();
    _filterPicTeamController = ExpansibleController();
    _filterPicTeammateTileController = ExpansibleController();
    _filterCreatorRootController = ExpansibleController();
    _filterCreatorTeamController = ExpansibleController();
    _filterCreatorTeammateTileController = ExpansibleController();
    _filterStatusTileController = ExpansibleController();
    _filterOverdueTileController = ExpansibleController();
    _filterSubmissionTileController = ExpansibleController();
    _filterCreateDateTileController = ExpansibleController();
    _taskSearchController.addListener(_onSearchTextChangedForPersist);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.projectsOnlyDashboard) {
        unawaited(_loadStaffMapsForProjectsDashboard());
        return;
      }
      _appStateListenerRef = context.read<AppState>();
      _appStateListenerRef!.addListener(_onAppStateForDeferredTeamRestore);
      _loadLandingFilters();
    });
  }

  Future<void> _loadStaffMapsForProjectsDashboard() async {
    try {
      final m = await SupabaseService.fetchStaffUuidToAppIdMap();
      if (!mounted) return;
      setState(() {
        _staffUuidToAppId = m;
        _staffMapsReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _staffMapsReady = true;
      });
    }
  }

  void _onSearchTextChangedForPersist() {
    if (widget.projectsOnlyDashboard) return;
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
      _lastSubtaskSearchQueryForBlob = data.search.trim();
      _subtaskSearchBlobByTaskId.clear();
      _subtaskFetchGeneration++;
      _landingSubtaskServerSearchSeq++;
      _subtaskServerSetsByToken = null;
      _subtaskServerQueryNormalized = '';
    } finally {
      _suppressFilterPersist = false;
    }
    _landingSubtaskServerSearchDebounce?.cancel();
    _scheduleLandingSubtaskServerSearch();
    _taskSortColumn = TaskListSortColumn.fromStorage(data.sortColumn);
    _taskSortAscending = data.sortAscending;
    if (_taskSortColumn == null) {
      _taskSortAscending = false;
    }
    _filterOverdueOnly = data.filterOverdueOnly;
    _filterCreateDateStart = data.filterCreateDateStartMs != null
        ? DateTime.fromMillisecondsSinceEpoch(data.filterCreateDateStartMs!)
        : null;
    _filterCreateDateEnd = data.filterCreateDateEndMs != null
        ? DateTime.fromMillisecondsSinceEpoch(data.filterCreateDateEndMs!)
        : null;
  }

  void _applyTeamsAndAssigneesFromSaved(LandingTaskFilters data, AppState state) {
    _restoreMenuRoleFiltersFromSaved(data, state);
  }

  void _restoreMenuRoleFiltersFromSaved(
    LandingTaskFilters data,
    AppState state,
  ) {
    final validTeamIds = state.teams.map((t) => t.id).toSet();
    final at = data.filterAssigneeTeamId?.trim();
    if (at != null && at.isNotEmpty && validTeamIds.contains(at)) {
      _filterAssigneeMenuTeamId = at;
      _filterAssigneeMenuStaffIds.clear();
      final assigneeMembers =
          _getTeamMembers(state, at).map((e) => e.id).toSet();
      for (final id in data.filterAssigneeStaffIds) {
        if (assigneeMembers.contains(id)) _filterAssigneeMenuStaffIds.add(id);
      }
    } else {
      _filterAssigneeMenuTeamId = null;
      _filterAssigneeMenuStaffIds.clear();
    }
    final pt = data.filterPicTeamId?.trim();
    if (pt != null && pt.isNotEmpty && validTeamIds.contains(pt)) {
      _filterPicMenuTeamId = pt;
      _filterPicMenuStaffIds.clear();
      final picMembers = _getTeamMembers(state, pt).map((e) => e.id).toSet();
      for (final id in data.filterPicStaffIds) {
        if (picMembers.contains(id)) _filterPicMenuStaffIds.add(id);
      }
    } else {
      _filterPicMenuTeamId = null;
      _filterPicMenuStaffIds.clear();
    }
    final ct = data.filterCreatorTeamId?.trim();
    if (ct != null && ct.isNotEmpty && validTeamIds.contains(ct)) {
      _filterCreatorMenuTeamId = ct;
      _filterCreatorMenuStaffIds.clear();
      final creatorMembers = _getTeamMembers(state, ct).map((e) => e.id).toSet();
      for (final id in data.filterCreatorStaffIds) {
        if (creatorMembers.contains(id)) _filterCreatorMenuStaffIds.add(id);
      }
    } else {
      _filterCreatorMenuTeamId = null;
      _filterCreatorMenuStaffIds.clear();
    }
  }

  void _applySavedFiltersFull(LandingTaskFilters data, AppState state) {
    _applySavedFiltersPartial(data, state);
    _applyTeamsAndAssigneesFromSaved(data, state);
  }

  void _persistLandingFilters() {
    if (widget.projectsOnlyDashboard) return;
    if (!_landingFiltersPrefsReady || _suppressFilterPersist) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    LandingTaskFiltersStorage.save(
      uid,
      LandingTaskFilters(
        filterType: _filterType,
        teamIds: const [],
        assigneeIds: const [],
        statuses: _selectedTaskStatuses.toList(),
        submissionFilters: _selectedSubmissionFilters.toList(),
        filterOverdueOnly: _filterOverdueOnly,
        search: _taskSearchController.text,
        sortColumn: _taskSortColumn?.storageKey,
        sortAscending: _taskSortAscending,
        filterAssigneeTeamId: _filterAssigneeMenuTeamId,
        filterAssigneeStaffIds: _filterAssigneeMenuStaffIds.toList(),
        filterPicTeamId: _filterPicMenuTeamId,
        filterPicStaffIds: _filterPicMenuStaffIds.toList(),
        filterCreatorTeamId: _filterCreatorMenuTeamId,
        filterCreatorStaffIds: _filterCreatorMenuStaffIds.toList(),
        filterCreateDateStartMs: _filterCreateDateStart?.millisecondsSinceEpoch,
        filterCreateDateEndMs: _filterCreateDateEnd?.millisecondsSinceEpoch,
      ),
    );
  }

  @override
  void dispose() {
    _landingSubtaskServerSearchDebounce?.cancel();
    _searchPersistDebounce?.cancel();
    _taskSearchController.removeListener(_onSearchTextChangedForPersist);
    _appStateListenerRef?.removeListener(_onAppStateForDeferredTeamRestore);
    _filterAssigneeRootController.dispose();
    _filterAssigneeTeamController.dispose();
    _filterAssigneeTeammateTileController.dispose();
    _filterPicRootController.dispose();
    _filterPicTeamController.dispose();
    _filterPicTeammateTileController.dispose();
    _filterCreatorRootController.dispose();
    _filterCreatorTeamController.dispose();
    _filterCreatorTeammateTileController.dispose();
    _filterStatusTileController.dispose();
    _filterOverdueTileController.dispose();
    _filterSubmissionTileController.dispose();
    _filterCreateDateTileController.dispose();
    _taskSearchController.dispose();
    super.dispose();
  }

  /// Landing + Overview: single dropdown for sort column + direction toggle.
  Widget _buildTaskSortDropdown() {
    final theme = Theme.of(context);
    final hasColumn = _taskSortColumn != null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasColumn
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: DropdownButton<TaskListSortColumn?>(
                value: _taskSortColumn,
                isDense: true,
                isExpanded: false,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(8),
                style: theme.textTheme.labelLarge,
                items: [
                  DropdownMenuItem<TaskListSortColumn?>(
                    value: null,
                    child: Text(
                      'Created date (default)',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: _taskSortColumn == null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  for (final c in TaskListSortColumn.values)
                    DropdownMenuItem<TaskListSortColumn?>(
                      value: c,
                      child: Text(
                        c.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: _taskSortColumn == c
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    _taskSortColumn = v;
                    _tasksPageIndex = 0;
                    _deletedTasksPageIndex = 0;
                  });
                  _persistLandingFilters();
                },
              ),
            ),
          ),
          const SizedBox(width: 2),
          Tooltip(
            message: _taskSortColumn == null
                ? (_taskSortAscending
                    ? 'Created date: oldest first — tap for newest first'
                    : 'Created date: newest first — tap for oldest first')
                : (_taskSortAscending
                    ? 'Ascending — tap for descending'
                    : 'Descending — tap for ascending'),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              icon: Icon(
                _taskSortAscending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              onPressed: () {
                setState(() {
                  _taskSortAscending = !_taskSortAscending;
                  _tasksPageIndex = 0;
                  _deletedTasksPageIndex = 0;
                });
                _persistLandingFilters();
              },
            ),
          ),
        ],
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
      onChanged: (value) {
        final q = value.trim();
        if (q != _lastSubtaskSearchQueryForBlob) {
          _lastSubtaskSearchQueryForBlob = q;
          _subtaskSearchBlobByTaskId.clear();
          _subtaskFetchGeneration++;
        }
        _landingSubtaskServerSearchSeq++;
        _scheduleLandingSubtaskServerSearch();
        setState(() {
          _tasksPageIndex = 0;
          _deletedTasksPageIndex = 0;
        });
      },
      decoration: InputDecoration(
        labelText: 'Search',
        hintText:
            'Project, project description, task, task description, sub-task, sub-task description',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _taskSearchController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _landingSubtaskServerSearchDebounce?.cancel();
                  _landingSubtaskServerSearchSeq++;
                  setState(() {
                    _taskSearchController.clear();
                    _lastSubtaskSearchQueryForBlob = '';
                    _subtaskSearchBlobByTaskId.clear();
                    _subtaskFetchGeneration++;
                    _subtaskServerSetsByToken = null;
                    _subtaskServerQueryNormalized = '';
                    _tasksPageIndex = 0;
                    _deletedTasksPageIndex = 0;
                  });
                },
              )
            : null,
      ),
    );
  }

  static const _kProjectStatuses = ['Not started', 'In progress', 'Completed'];

  String _projectDashboardFilterSummaryLine(AppState state) {
    final parts = <String>[];
    if (_filterCreatorMenuStaffIds.isNotEmpty) {
      final names =
          _filterCreatorMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('Creator: ${names.join(', ')}');
    }
    if (_filterAssigneeMenuStaffIds.isNotEmpty) {
      final names =
          _filterAssigneeMenuStaffIds
              .map((id) => state.assigneeById(id)?.name ?? id)
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      parts.add('Assignee: ${names.join(', ')}');
    }
    final fmt = DateFormat.yMMMd();
    if (_filterCreateDateEngaged) {
      final a = _filterCreateDateStart != null
          ? fmt.format(_filterCreateDateStart!)
          : '…';
      final b =
          _filterCreateDateEnd != null ? fmt.format(_filterCreateDateEnd!) : '…';
      parts.add('Created date: $a – $b');
    } else {
      final r = _defaultCreateDateRangeHk();
      parts.add(
        'Created date: ${fmt.format(r.$1)} – ${fmt.format(r.$2)} (default)',
      );
    }
    if (_selectedProjectStatusFilters.isEmpty) {
      parts.add('All status');
    } else {
      final sorted = _selectedProjectStatusFilters.toList()
        ..sort();
      parts.add('Status: ${sorted.join(', ')}');
    }
    return parts.join(' · ');
  }

  bool _projectPassesCreateDateForDashboard(ProjectRecord p) {
    final cd = p.createDate;
    if (cd == null) return false;
    final day = _dateOnlyCal(cd);
    if (_filterCreateDateEngaged) {
      return _calendarDayInCreateFilterRange(day);
    }
    return _dateWithinLastRollingMonth(cd);
  }

  /// Project list visibility: self as creator or assignee, or a subordinate (from
  /// Supabase [subordinate]) as creator or assignee — same app_ids as [AppState.subordinateAppIds].
  bool _projectIsVisibleToCurrentUser(ProjectRecord p, AppState state) {
    final mine = state.userStaffAppId?.trim();
    if (mine == null || mine.isEmpty) return false;
    final myUuid = state.userStaffId?.trim();
    final cb = p.createByStaffUuid?.trim();
    if (myUuid != null &&
        myUuid.isNotEmpty &&
        cb != null &&
        cb.isNotEmpty &&
        cb.toLowerCase() == myUuid.toLowerCase()) {
      return true;
    }
    final keys = p.assigneeKeys(_staffUuidToAppId);
    if (keys.contains(mine)) return true;
    final subs = state.subordinateAppIds;
    if (subs.isEmpty) return false;
    if (cb != null && cb.isNotEmpty) {
      final creatorApp = _staffUuidToAppId[cb] ?? cb;
      if (subs.contains(creatorApp)) return true;
    }
    if (keys.any(subs.contains)) return true;
    return false;
  }

  List<ProjectRecord> _filteredSortedProjectsForDashboard(AppState state) {
    final filterKey = _filterType == 'my' ? 'all' : _filterType;
    final sid = state.userStaffId?.trim();
    Iterable<ProjectRecord> it =
        state.projects.where((p) => _projectIsVisibleToCurrentUser(p, state));
    if (filterKey == 'assigned') {
      if (sid == null || sid.isEmpty) return [];
      it = it.where((p) => p.assigneeStaffUuids.contains(sid));
    } else if (filterKey == 'created') {
      if (sid == null || sid.isEmpty) return [];
      it = it.where((p) => p.createByStaffUuid == sid);
    }
    var list = it.toList();
    if (_filterAssigneeMenuStaffIds.isNotEmpty) {
      list = list.where((p) {
        final keys = p.assigneeKeys(_staffUuidToAppId);
        return keys.any(_filterAssigneeMenuStaffIds.contains);
      }).toList();
    }
    if (_filterCreatorMenuStaffIds.isNotEmpty) {
      list = list.where((p) {
        final cb = p.createByStaffUuid?.trim();
        if (cb == null || cb.isEmpty) return false;
        final key = _staffUuidToAppId[cb] ?? cb;
        return _filterCreatorMenuStaffIds.contains(key);
      }).toList();
    }
    list = list.where(_projectPassesCreateDateForDashboard).toList();
    if (_selectedProjectStatusFilters.isNotEmpty) {
      list = list
          .where((p) => _selectedProjectStatusFilters.contains(p.status))
          .toList();
    }
    final q = _taskSearchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                p.description.toLowerCase().contains(q),
          )
          .toList();
    }
    return _sortProjectsDashboard(list, state);
  }

  List<ProjectRecord> _sortProjectsDashboard(
    List<ProjectRecord> projects,
    AppState state,
  ) {
    final asc = _projectSortAscending;
    if (_projectSortColumn == null) {
      final out = List<ProjectRecord>.from(projects);
      out.sort((a, b) {
        final c =
            ProjectTaskSort.cmpDateForSort(a.createDate, b.createDate, asc);
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return out;
    }
    final col = _projectSortColumn!;
    final out = List<ProjectRecord>.from(projects);
    String assigneeLine(ProjectRecord p) {
      final keys = p.assigneeKeys(_staffUuidToAppId);
      final names = keys
          .map((k) => state.assigneeById(k)?.name ?? k)
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return names.join(', ');
    }

    out.sort((a, b) {
      int c;
      switch (col) {
        case ProjectListSortColumn.creator:
          c = ProjectTaskSort.cmpStrNullable(
            a.createByDisplayName,
            b.createByDisplayName,
            asc,
          );
          break;
        case ProjectListSortColumn.assignee:
          c = ProjectTaskSort.cmpStrNullable(
            assigneeLine(a),
            assigneeLine(b),
            asc,
          );
          break;
        case ProjectListSortColumn.startDate:
          c = ProjectTaskSort.cmpDateForSort(a.startDate, b.startDate, asc);
          break;
        case ProjectListSortColumn.endDate:
          c = ProjectTaskSort.cmpDateForSort(a.endDate, b.endDate, asc);
          break;
        case ProjectListSortColumn.status:
          c = ProjectTaskSort.cmpStrNullable(a.status, b.status, asc);
          break;
      }
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  /// Project dashboard: sort column dropdown + direction toggle.
  Widget _buildProjectSortDropdown() {
    final theme = Theme.of(context);
    final hasColumn = _projectSortColumn != null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IntrinsicWidth(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasColumn
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: DropdownButton<ProjectListSortColumn?>(
                value: _projectSortColumn,
                isDense: true,
                isExpanded: false,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(8),
                style: theme.textTheme.labelLarge,
                items: [
                  DropdownMenuItem<ProjectListSortColumn?>(
                    value: null,
                    child: Text(
                      'Created date (default)',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: _projectSortColumn == null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  for (final c in ProjectListSortColumn.values)
                    DropdownMenuItem<ProjectListSortColumn?>(
                      value: c,
                      child: Text(
                        c.label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: _projectSortColumn == c
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    _projectSortColumn = v;
                    _tasksPageIndex = 0;
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 2),
          Tooltip(
            message: _projectSortColumn == null
                ? (_projectSortAscending
                    ? 'Created date: oldest first — tap for newest first'
                    : 'Created date: newest first — tap for oldest first')
                : (_projectSortAscending
                    ? 'Ascending — tap for descending'
                    : 'Descending — tap for ascending'),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              icon: Icon(
                _projectSortAscending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 22,
                color: theme.colorScheme.primary,
              ),
              onPressed: () {
                setState(() {
                  _projectSortAscending = !_projectSortAscending;
                  _tasksPageIndex = 0;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _projectDashboardStatusSection(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    return [
      ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Status', style: titleStyle),
        children: [
          for (final s in _kProjectStatuses)
            CheckboxMenuButton(
              closeOnActivate: false,
              value: _selectedProjectStatusFilters.contains(s),
              onChanged: (bool? v) {
                if (v == null) return;
                setState(() {
                  if (v) {
                    _selectedProjectStatusFilters.add(s);
                  } else {
                    _selectedProjectStatusFilters.remove(s);
                  }
                  _tasksPageIndex = 0;
                });
              },
              child: Text(s),
            ),
        ],
      ),
    ];
  }

  String? _firstAssigneeKeyForProject(ProjectRecord p) {
    final keys = p.assigneeKeys(_staffUuidToAppId);
    if (keys.isEmpty) return null;
    return keys.first;
  }

  /// Parallel team lookups for one page of project cards (avoids one FutureBuilder + query per row).
  Future<Map<String, String?>> _fetchProjectCardTeamTints(
    List<ProjectRecord> pageProjects,
  ) async {
    final keys = <String>{};
    for (final p in pageProjects) {
      final k = _firstAssigneeKeyForProject(p);
      if (k != null && k.isNotEmpty) keys.add(k);
    }
    if (keys.isEmpty) return {};
    final list = keys.toList();
    final entries = await Future.wait(
      list.map(
        (k) async => MapEntry(
          k,
          await SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(k),
        ),
      ),
    );
    return Map<String, String?>.fromEntries(entries);
  }

  Widget _buildProjectDashboardCard(
    BuildContext context,
    ProjectRecord p,
    Map<String, String?> teamTintByAssigneeKey,
  ) {
    final state = context.read<AppState>();
    final keys = p.assigneeKeys(_staffUuidToAppId);
    final firstKey = _firstAssigneeKeyForProject(p);
    final assigneeLine = keys
        .map((k) => state.assigneeById(k)?.name ?? k)
        .join(', ');
    final fmt = DateFormat('yyyy-MM-dd');
    final teamBiz =
        firstKey != null ? teamTintByAssigneeKey[firstKey] : null;
    final tint = TaskListCard.cardColorForPicTeam(teamBiz);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      color: tint,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProjectDetailScreen(
                projectId: p.id,
                openedFromLanding: false,
                openedFromOverview: false,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Assignee(s): ${assigneeLine.isNotEmpty ? assigneeLine : '—'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Creator: ${p.createByDisplayName?.trim().isNotEmpty == true ? p.createByDisplayName!.trim() : '—'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${p.status} · Start ${p.startDate != null ? fmt.format(p.startDate!) : '—'} · End ${p.endDate != null ? fmt.format(p.endDate!) : '—'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectDashboardFiltersAndLegendSection(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted, {
    required List<ProjectRecord> projects,
    required String filterKey,
    required bool hasProjFilters,
  }) {
    final menuMaxHeight = MediaQuery.sizeOf(context).height * 0.65;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wideFilterWidth = min(
                280.0,
                constraints.maxWidth * 0.38,
              ).clamp(120.0, _filterFieldMaxWidth);

              final filterMenu = MenuAnchor(
                controller: _filterMenuController,
                onClose: _onFilterMenuAnchorClosed,
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
                              ..._landingFilterMenuSections(
                                context,
                                state,
                                teamsSorted,
                                includePic: false,
                              ),
                              ..._landingCreateDateSection(context),
                              ..._projectDashboardStatusSection(context),
                              const Divider(height: 16),
                              MenuItemButton(
                                closeOnActivate: false,
                                onPressed: _clearTeamAndStatusFilters,
                                leadingIcon:
                                    const Icon(Icons.clear_all, size: 20),
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
                  final summaryLine = _projectDashboardFilterSummaryLine(state);
                  return Tooltip(
                    message: summaryLine,
                    child: InkWell(
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
                          summaryLine,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 3,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
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
        if (hasProjFilters)
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
                    label: 'My created projects',
                    selected: filterKey == 'created',
                    selectedBg: Colors.lightBlue.shade200,
                    selectedLabelColor: Colors.black87,
                    leading:
                        _myCreatedProjectsFilterIcon(filterKey == 'created'),
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
                  _buildProjectSortDropdown(),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _taskSearchController,
                        onChanged: (_) => setState(() => _tasksPageIndex = 0),
                        decoration: const InputDecoration(
                          labelText: 'Search',
                          hintText: 'Search project name, description',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Project (${projects.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const PicTeamColorLegend(
                        caption:
                            "Project background colour reflect the assignee's team.",
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildProjectsOnlyDashboard(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted,
  ) {
    final projects = _filteredSortedProjectsForDashboard(state);
    final pagedProjects = _landingPageSlice(
      projects,
      _tasksPageIndex,
      _tasksPageSize,
    );
    final filterKey = _filterType == 'my' ? 'all' : _filterType;

    final hasProjFilters =
        _filterAssigneeMenuStaffIds.isNotEmpty ||
        _filterCreatorMenuStaffIds.isNotEmpty ||
        _filterCreateDateEngaged ||
        _selectedProjectStatusFilters.isNotEmpty ||
        _taskSearchController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildProjectDashboardFiltersAndLegendSection(
          context,
          state,
          teamsSorted,
          projects: projects,
          filterKey: filterKey,
          hasProjFilters: hasProjFilters,
        ),
        Expanded(
          child: projects.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _taskSearchController.text.trim().isNotEmpty
                          ? 'No projects match your search.'
                          : hasProjFilters
                              ? 'No projects for this filter.'
                              : 'No projects yet.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: FutureBuilder<Map<String, String?>>(
                        key: ValueKey(
                          '${pagedProjects.map((e) => e.id).join('|')}'
                          '_$_tasksPageIndex',
                        ),
                        future: _fetchProjectCardTeamTints(pagedProjects),
                        builder: (context, snap) {
                          final tintMap = snap.data ?? {};
                          return Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _kLandingTaskListMaxWidth,
                              ),
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                itemCount: pagedProjects.length,
                                itemBuilder: (context, i) =>
                                    _buildProjectDashboardCard(
                                  context,
                                  pagedProjects[i],
                                  tintMap,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
                                  _buildLandingTaskPaginationBar(
                                    context: context,
                                    totalCount: projects.length,
                                    pageIndex: _tasksPageIndex,
                                    onPageChanged: (i) {
                                      setState(() => _tasksPageIndex = i);
                                    },
                                    showPageSizeDropdown: true,
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

  Widget _buildProjectsOnlyDashboardWithSliver(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted,
  ) {
    final cfg = widget.dashboardScrollAppBar!;
    final projects = _filteredSortedProjectsForDashboard(state);
    final pagedProjects = _landingPageSlice(
      projects,
      _tasksPageIndex,
      _tasksPageSize,
    );
    final filterKey = _filterType == 'my' ? 'all' : _filterType;
    final hasProjFilters =
        _filterAssigneeMenuStaffIds.isNotEmpty ||
        _filterCreatorMenuStaffIds.isNotEmpty ||
        _filterCreateDateEngaged ||
        _selectedProjectStatusFilters.isNotEmpty ||
        _taskSearchController.text.trim().isNotEmpty;

    final prefixSlivers = _buildDashboardScrollPrefixSlivers(
      context,
      state,
      teamsSorted,
      appBarConfig: cfg,
      filterKey: filterKey,
      filtersHeaderExtent: _projectDashboardFiltersSliverExtent,
      filtersMeasureKey: _projectDashboardFiltersMeasureKey,
      filtersHeaderChild: _buildProjectDashboardFiltersAndLegendSection(
        context,
        state,
        teamsSorted,
        projects: projects,
        filterKey: filterKey,
        hasProjFilters: hasProjFilters,
      ),
    );

    if (projects.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                ...prefixSlivers,
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        _taskSearchController.text.trim().isNotEmpty
                            ? 'No projects match your search.'
                            : hasProjFilters
                                ? 'No projects for this filter.'
                                : 'No projects yet.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
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

    final paginationBar = Material(
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
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLandingTaskPaginationBar(
                    context: context,
                    totalCount: projects.length,
                    pageIndex: _tasksPageIndex,
                    onPageChanged: (i) {
                      setState(() => _tasksPageIndex = i);
                    },
                    showPageSizeDropdown: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              ...prefixSlivers,
              SliverToBoxAdapter(
                child: FutureBuilder<Map<String, String?>>(
                  key: ValueKey(
                    '${pagedProjects.map((e) => e.id).join('|')}'
                    '_$_tasksPageIndex',
                  ),
                  future: _fetchProjectCardTeamTints(pagedProjects),
                  builder: (context, snap) {
                    final tintMap = snap.data ?? {};
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _kLandingTaskListMaxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final p in pagedProjects)
                                _buildProjectDashboardCard(
                                  context,
                                  p,
                                  tintMap,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        paginationBar,
      ],
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
    if (widget.dashboardScrollAppBar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.projectsOnlyDashboard) {
          _measureProjectDashboardFiltersSliverExtent();
        } else {
          _measureTaskDashboardFiltersSliverExtent();
        }
      });
    }
    final teamsSorted = [...state.teams]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (widget.projectsOnlyDashboard) {
      if (!_staffMapsReady) {
        return const Center(child: CircularProgressIndicator());
      }
      if (widget.dashboardScrollAppBar != null) {
        return _buildProjectsOnlyDashboardWithSliver(
          context,
          state,
          teamsSorted,
        );
      }
      return _buildProjectsOnlyDashboard(context, state, teamsSorted);
    }
    const allTeams = <String>{};
    var initiatives = state.initiativesForTeams(allTeams);
    var tasks = state.tasksForTeams(allTeams);

    final singularSig = _singularTaskIdsSignature(state);
    if (singularSig != _cachedSingularTaskIdsSig) {
      _cachedSingularTaskIdsSig = singularSig;
      _subtaskFetchGeneration++;
      _subtaskMinDueByTaskId.clear();
      _subtaskMaxDueByTaskId.clear();
      _subtaskHasOverdueByTaskId.clear();
      _subtaskSearchBlobByTaskId.clear();
      _taskCommentActivityByTaskId.clear();
      _subtaskCommentActivityBySubtaskId.clear();
      SupabaseService.clearSubtaskListMemoryCache();
      _landingSubtaskServerSearchSeq++;
      _landingSubtaskServerSearchDebounce?.cancel();
      _subtaskServerSetsByToken = null;
      _subtaskServerQueryNormalized = '';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scheduleLandingSubtaskServerSearch();
      });
    }

    if (_filterAssigneeMenuStaffIds.isNotEmpty) {
      initiatives = initiatives
          .where((i) => i.directorIds.any(_filterAssigneeMenuStaffIds.contains))
          .toList();
      tasks = tasks
          .where((t) => t.assigneeIds.any(_filterAssigneeMenuStaffIds.contains))
          .toList();
    }
    if (_filterPicMenuStaffIds.isNotEmpty) {
      tasks = tasks.where((t) {
        final p = t.pic?.trim();
        return p != null &&
            p.isNotEmpty &&
            _filterPicMenuStaffIds.contains(p);
      }).toList();
    }
    if (_filterCreatorMenuStaffIds.isNotEmpty) {
      tasks = tasks
          .where((t) {
            final k = t.createByAssigneeKey?.trim();
            return k != null &&
                k.isNotEmpty &&
                _filterCreatorMenuStaffIds.contains(k);
          })
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

    bool taskMatchesOverdueFilter(Task t) {
      if (!_filterOverdueOnly) return true;
      if (t.isSingularTableRow) {
        if (t.overdue == 'Yes') return true;
        if (!_subtaskHasOverdueByTaskId.containsKey(t.id)) return false;
        return _subtaskHasOverdueByTaskId[t.id] == true;
      }
      return t.overdue == 'Yes';
    }

    final tasksForSubtaskPrefetch = List<Task>.from(filteredTasks);
    final deletedForSubtaskPrefetch = List<Task>.from(filteredDeletedTasks);
    if (_filterOverdueOnly) {
      filteredInitiatives = [];
      filteredTasks = filteredTasks.where(taskMatchesOverdueFilter).toList();
      filteredDeletedTasks =
          filteredDeletedTasks.where(taskMatchesOverdueFilter).toList();
    }

    filteredInitiatives = _applyInitiativeNameSearch(filteredInitiatives);
    // Run after this frame so [onChanged] blob invalidation (clear + generation bump) is applied
    // before we decide which task ids still need [fetchSubtasksForTask].
    final prefetchTasks = List<Task>.from(tasksForSubtaskPrefetch);
    final prefetchDeleted = List<Task>.from(deletedForSubtaskPrefetch);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleSubtaskRowDataPrefetch(prefetchTasks, prefetchDeleted);
    });
    filteredTasks = _applyTaskSearch(filteredTasks);
    filteredDeletedTasks = _applyTaskSearch(filteredDeletedTasks);
    if (_filterCreateDateEngaged && !widget.customizedFlat) {
      bool taskCreateDayOk(Task t) {
        final day =
            DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
        return _calendarDayInCreateFilterRange(day);
      }
      filteredTasks = filteredTasks.where(taskCreateDayOk).toList();
      filteredDeletedTasks =
          filteredDeletedTasks.where(taskCreateDayOk).toList();
    }
    if (!widget.customizedFlat) {
      filteredTasks = _sortTasks(filteredTasks, state);
      filteredDeletedTasks = _sortTasks(filteredDeletedTasks, state);
    }

    List<Task> customizedFlatActiveTasks = filteredTasks;
    if (widget.customizedFlat &&
        _selectedTaskStatuses.contains(_statusCompleted) &&
        !_selectedTaskStatuses.contains(_statusIncomplete)) {
      final byId = {for (final t in filteredTasks) t.id: t};
      Iterable<Task> scopeIt = tasksNonDeleted;
      if (filterKey == 'assigned') {
        scopeIt = scopeIt.where(isAssignedToMe);
      } else if (filterKey == 'created') {
        scopeIt = scopeIt.where(isCreatedByMe);
      }
      for (final t in scopeIt) {
        if (!t.isSingularTableRow || byId.containsKey(t.id)) continue;
        if (!_singularTaskIncomplete(t)) continue;
        if (_selectedSubmissionFilters.isNotEmpty &&
            !taskMatchesSubmissionSelection(t)) {
          continue;
        }
        byId[t.id] = t;
      }
      customizedFlatActiveTasks = byId.values.toList();
    }

    final pagedTasks = widget.customizedFlat
        ? const <Task>[]
        : _landingPageSlice(
            filteredTasks,
            _tasksPageIndex,
            _tasksPageSize,
          );
    final pagedDeletedTasks = widget.customizedFlat
        ? const <Task>[]
        : _landingPageSlice(
            filteredDeletedTasks,
            _deletedTasksPageIndex,
            _tasksPageSize,
          );

    final reminders = state.getPendingRemindersForTeams(allTeams);

    final dashCfg = widget.dashboardScrollAppBar;

    if (dashCfg != null &&
        !widget.customizedFlat &&
        !widget.projectsOnlyDashboard) {
      final prefixSlivers = _buildDashboardScrollPrefixSlivers(
        context,
        state,
        teamsSorted,
        appBarConfig: dashCfg,
        filterKey: filterKey,
        filtersHeaderExtent: _taskDashboardFiltersSliverExtent,
        filtersMeasureKey: _taskDashboardFiltersMeasureKey,
        filtersHeaderChild: _buildLandingFiltersSortSearchSection(
          context,
          state,
          teamsSorted,
          filterKey,
        ),
      );

      final reminderSlivers = <Widget>[
        if (reminders.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: ExpansionTile(
                title: const Text('Reminders (would send to Directors)'),
                initiallyExpanded: _remindersExpanded,
                onExpansionChanged: (v) =>
                    setState(() => _remindersExpanded = v),
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
          ),
      ];

      if (filteredInitiatives.isEmpty &&
          filteredTasks.isEmpty &&
          filteredDeletedTasks.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  ...prefixSlivers,
                  ...reminderSlivers,
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(_emptyListMessage())),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      final landingListChildren = <Widget>[
        if (filteredInitiatives.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              'Initiatives',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...filteredInitiatives.map(
            (init) => _buildInitiativeCard(context, state, init),
          ),
        ],
        if (filteredTasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
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
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              'Deleted tasks',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
          ...pagedDeletedTasks.map((t) => TaskListCard(task: t)),
        ],
      ];

      final landingPaginationBar =
          (filteredTasks.isNotEmpty || filteredDeletedTasks.isNotEmpty)
              ? Material(
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
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                  totalCount: filteredDeletedTasks.length,
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
                )
              : null;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                ...prefixSlivers,
                ...reminderSlivers,
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: _kLandingTaskListMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: landingListChildren,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ?landingPaginationBar,
        ],
      );
    }

    if (widget.customizedFlat && dashCfg != null) {
      final prefixSlivers = _buildDashboardScrollPrefixSlivers(
        context,
        state,
        teamsSorted,
        appBarConfig: dashCfg,
        filterKey: filterKey,
        filtersHeaderExtent: _taskDashboardFiltersSliverExtent,
        filtersMeasureKey: _taskDashboardFiltersMeasureKey,
        filtersHeaderChild: _buildLandingFiltersSortSearchSection(
          context,
          state,
          teamsSorted,
          filterKey,
        ),
      );

      if (filteredInitiatives.isEmpty &&
          filteredTasks.isEmpty &&
          filteredDeletedTasks.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  ...prefixSlivers,
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text(_emptyListMessage())),
                  ),
                ],
              ),
            ),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildCustomizedFlatFullColumn(
              context,
              state,
              customizedFlatActiveTasks,
              filteredDeletedTasks,
              dashboardScrollPrefixSlivers: prefixSlivers,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reminders.isNotEmpty && !widget.customizedFlat)
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
        _buildLandingFiltersSortSearchSection(
          context,
          state,
          teamsSorted,
          filterKey,
        ),
        Expanded(
          child: filteredInitiatives.isEmpty &&
                  filteredTasks.isEmpty &&
                  filteredDeletedTasks.isEmpty
              ? Center(child: Text(_emptyListMessage()))
              : widget.customizedFlat
                  ? _buildCustomizedFlatFullColumn(
                      context,
                      state,
                      customizedFlatActiveTasks,
                      filteredDeletedTasks,
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _kLandingTaskListMaxWidth,
                              ),
                              child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
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
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 12),
                                      child: PicTeamColorLegend(),
                                    ),
                                    ...pagedTasks.map(
                                      (t) => TaskListCard(task: t),
                                    ),
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

  /// Assignee or Creator: root [ExpansionTile] → **Team** → **Teammate** (checkboxes).
  Widget _landingTeamStaffFilterExpansion(
    BuildContext context, {
    required String sectionTitle,
    required String topSectionId,
    required ExpansibleController rootController,
    required ExpansibleController teamController,
    required List<Team> teamsSorted,
    required String? rosterTeamId,
    required List<Assignee> teammates,
    required Set<String> staffIds,
    required void Function(String teamId) onSelectTeam,
    required VoidCallback onClearAllStaff,
    required void Function(String staffId, bool selected) onStaffSelectionChanged,
    required ExpansibleController teammateExpansionController,
  }) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    const innerTilePadding = EdgeInsets.fromLTRB(12, 0, 4, 0);

    return ExpansionTile(
      controller: rootController,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(sectionTitle, style: titleStyle),
      onExpansionChanged: (expanded) {
        if (expanded) _onTopLevelFilterSectionExpanded(topSectionId);
      },
      children: [
        ExpansionTile(
          controller: teamController,
          tilePadding: innerTilePadding,
          title: const Text('Team'),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _onTeamStaffNestedSectionExpanded(
                rootId: topSectionId,
                openedNestedId: 'team',
              );
            }
          },
          children: teamsSorted.isEmpty
              ? const [
                  ListTile(
                    dense: true,
                    enabled: false,
                    title: Text('No teams loaded'),
                  ),
                ]
              : teamsSorted
                  .map(
                    (t) => MenuItemButton(
                      closeOnActivate: false,
                      onPressed: () {
                        onSelectTeam(t.id);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (context.mounted) {
                            teammateExpansionController.expand();
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Expanded(child: Text(t.name)),
                          if (rosterTeamId == t.id)
                            Icon(
                              Icons.check,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
        ),
        ExpansionTile(
          controller: teammateExpansionController,
          tilePadding: innerTilePadding,
          title: const Text('Teammate'),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _onTeamStaffNestedSectionExpanded(
                rootId: topSectionId,
                openedNestedId: 'teammate',
              );
            }
          },
          children: rosterTeamId == null
              ? const [
                  ListTile(
                    dense: true,
                    enabled: false,
                    title: Text('Select a team first'),
                  ),
                ]
              : [
                  CheckboxMenuButton(
                    closeOnActivate: false,
                    value: staffIds.isEmpty,
                    onChanged: (bool? v) {
                      if (v != true) return;
                      onClearAllStaff();
                    },
                    child: const Text('All teammates'),
                  ),
                  ...teammates.map(
                    (a) => CheckboxMenuButton(
                      closeOnActivate: false,
                      value: staffIds.contains(a.id),
                      onChanged: (bool? v) {
                        if (v == null) return;
                        onStaffSelectionChanged(a.id, v);
                      },
                      child: Text(a.name),
                    ),
                  ),
                ],
        ),
      ],
    );
  }

  /// Created date range — below Creator; applies to task/sub-task create dates on Customized,
  /// and to task `createdAt` on the landing list.
  List<Widget> _landingCreateDateSection(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    final fmt = DateFormat.yMMMd();
    final def = _defaultCreateDateRangeHk();

    Future<void> pickStart() async {
      final now = DateTime.now();
      final initial = _filterCreateDateStart ?? now;
      final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
      );
      if (d == null || !mounted) return;
      setState(() {
        _filterCreateDateStart = d;
        _tasksPageIndex = 0;
        _deletedTasksPageIndex = 0;
      });
      _persistLandingFilters();
    }

    Future<void> pickEnd() async {
      final now = DateTime.now();
      final initial = _filterCreateDateEnd ?? _filterCreateDateStart ?? now;
      final d = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 5),
      );
      if (d == null || !mounted) return;
      setState(() {
        _filterCreateDateEnd = d;
        _tasksPageIndex = 0;
        _deletedTasksPageIndex = 0;
      });
      _persistLandingFilters();
    }

    void clearCreateDate() {
      setState(() {
        _filterCreateDateStart = null;
        _filterCreateDateEnd = null;
        _tasksPageIndex = 0;
        _deletedTasksPageIndex = 0;
      });
      _persistLandingFilters();
    }

    return [
      ExpansionTile(
        controller: _filterCreateDateTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Created date', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('createDate');
        },
        children: [
          ListTile(
            dense: true,
            title: const Text('From'),
            subtitle: Text(
              _filterCreateDateStart == null
                  ? 'Default: ${fmt.format(def.$1)}'
                  : fmt.format(_filterCreateDateStart!),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, size: 22),
              onPressed: pickStart,
              tooltip: 'Set start date',
            ),
            onTap: pickStart,
          ),
          ListTile(
            dense: true,
            title: const Text('To'),
            subtitle: Text(
              _filterCreateDateEnd == null
                  ? 'Default: ${fmt.format(def.$2)}'
                  : fmt.format(_filterCreateDateEnd!),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit_calendar_outlined, size: 22),
              onPressed: pickEnd,
              tooltip: 'Set end date',
            ),
            onTap: pickEnd,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextButton(
              onPressed: _filterCreateDateEngaged ? clearCreateDate : null,
              child: const Text('Clear created date range'),
            ),
          ),
        ],
      ),
    ];
  }

  /// Status / Submission: expandable sections with [CheckboxMenuButton].
  List<Widget> _landingStatusSubmissionSections(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        );
    return [
      ExpansionTile(
        controller: _filterStatusTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Status', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('status');
        },
        children: [
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedTaskStatuses.contains(_statusIncomplete),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedTaskStatuses.add(_statusIncomplete);
                } else {
                  _selectedTaskStatuses.remove(_statusIncomplete);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Incomplete'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedTaskStatuses.contains(_statusCompleted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedTaskStatuses.add(_statusCompleted);
                } else {
                  _selectedTaskStatuses.remove(_statusCompleted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Completed'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedTaskStatuses.contains(_statusDeleted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedTaskStatuses.add(_statusDeleted);
                } else {
                  _selectedTaskStatuses.remove(_statusDeleted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Deleted'),
          ),
        ],
      ),
      ExpansionTile(
        controller: _filterOverdueTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Overdue', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('overdue');
        },
        children: [
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _filterOverdueOnly,
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                _filterOverdueOnly = v;
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Show only overdue tasks/ sub-tasks'),
          ),
        ],
      ),
      ExpansionTile(
        controller: _filterSubmissionTileController,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Submission', style: titleStyle),
        onExpansionChanged: (expanded) {
          if (expanded) _onTopLevelFilterSectionExpanded('submission');
        },
        children: [
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionPending),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionPending);
                } else {
                  _selectedSubmissionFilters.remove(_submissionPending);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Pending'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionSubmitted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionSubmitted);
                } else {
                  _selectedSubmissionFilters.remove(_submissionSubmitted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Submitted'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionAccepted),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionAccepted);
                } else {
                  _selectedSubmissionFilters.remove(_submissionAccepted);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Accepted'),
          ),
          CheckboxMenuButton(
            closeOnActivate: false,
            value: _selectedSubmissionFilters.contains(_submissionReturned),
            onChanged: (bool? v) {
              if (v == null) return;
              setState(() {
                if (v) {
                  _selectedSubmissionFilters.add(_submissionReturned);
                } else {
                  _selectedSubmissionFilters.remove(_submissionReturned);
                }
                _tasksPageIndex = 0;
                _deletedTasksPageIndex = 0;
              });
              _persistLandingFilters();
              _collapseRosterFilterExpansionsAfterStatusOrSubmissionChange();
            },
            child: const Text('Returned'),
          ),
        ],
      ),
    ];
  }

  /// Filter [MenuAnchor] body: Creator → Assignee → (optional) PIC, each with Team → Teammate.
  List<Widget> _landingFilterMenuSections(
    BuildContext context,
    AppState state,
    List<Team> teamsSorted, {
    bool includePic = true,
  }) {
    String? rosterTeamIdOrNull(String? stored) {
      if (stored == null || stored.isEmpty) return null;
      return teamsSorted.any((t) => t.id == stored) ? stored : null;
    }

    final assigneeTeamField = rosterTeamIdOrNull(_filterAssigneeMenuTeamId);
    final picTeamField = rosterTeamIdOrNull(_filterPicMenuTeamId);
    final creatorTeamField = rosterTeamIdOrNull(_filterCreatorMenuTeamId);
    final assigneeMembers = assigneeTeamField == null
        ? <Assignee>[]
        : _getTeamMembers(state, assigneeTeamField);
    final picMembers = picTeamField == null
        ? <Assignee>[]
        : _getTeamMembers(state, picTeamField);
    final creatorMembers = creatorTeamField == null
        ? <Assignee>[]
        : _getTeamMembers(state, creatorTeamField);

    return [
      _landingTeamStaffFilterExpansion(
        context,
        sectionTitle: 'Creator',
        topSectionId: 'creator',
        rootController: _filterCreatorRootController,
        teamController: _filterCreatorTeamController,
        teamsSorted: teamsSorted,
        rosterTeamId: creatorTeamField,
        teammates: creatorMembers,
        staffIds: _filterCreatorMenuStaffIds,
        teammateExpansionController: _filterCreatorTeammateTileController,
        onSelectTeam: (teamId) {
          setState(() {
            _filterCreatorMenuTeamId = teamId;
            _filterCreatorMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onClearAllStaff: () {
          setState(() {
            _filterCreatorMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onStaffSelectionChanged: (id, selected) {
          setState(() {
            if (selected) {
              _filterCreatorMenuStaffIds.add(id);
            } else {
              _filterCreatorMenuStaffIds.remove(id);
            }
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
      ),
      _landingTeamStaffFilterExpansion(
        context,
        sectionTitle: 'Assignee',
        topSectionId: 'assignee',
        rootController: _filterAssigneeRootController,
        teamController: _filterAssigneeTeamController,
        teamsSorted: teamsSorted,
        rosterTeamId: assigneeTeamField,
        teammates: assigneeMembers,
        staffIds: _filterAssigneeMenuStaffIds,
        teammateExpansionController: _filterAssigneeTeammateTileController,
        onSelectTeam: (teamId) {
          setState(() {
            _filterAssigneeMenuTeamId = teamId;
            _filterAssigneeMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onClearAllStaff: () {
          setState(() {
            _filterAssigneeMenuStaffIds.clear();
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
        onStaffSelectionChanged: (id, selected) {
          setState(() {
            if (selected) {
              _filterAssigneeMenuStaffIds.add(id);
            } else {
              _filterAssigneeMenuStaffIds.remove(id);
            }
            _tasksPageIndex = 0;
            _deletedTasksPageIndex = 0;
          });
          _persistLandingFilters();
        },
      ),
      if (includePic)
        _landingTeamStaffFilterExpansion(
          context,
          sectionTitle: 'PIC',
          topSectionId: 'pic',
          rootController: _filterPicRootController,
          teamController: _filterPicTeamController,
          teamsSorted: teamsSorted,
          rosterTeamId: picTeamField,
          teammates: picMembers,
          staffIds: _filterPicMenuStaffIds,
          teammateExpansionController: _filterPicTeammateTileController,
          onSelectTeam: (teamId) {
            setState(() {
              _filterPicMenuTeamId = teamId;
              _filterPicMenuStaffIds.clear();
              _tasksPageIndex = 0;
              _deletedTasksPageIndex = 0;
            });
            _persistLandingFilters();
          },
          onClearAllStaff: () {
            setState(() {
              _filterPicMenuStaffIds.clear();
              _tasksPageIndex = 0;
              _deletedTasksPageIndex = 0;
            });
            _persistLandingFilters();
          },
          onStaffSelectionChanged: (id, selected) {
            setState(() {
              if (selected) {
                _filterPicMenuStaffIds.add(id);
              } else {
                _filterPicMenuStaffIds.remove(id);
              }
              _tasksPageIndex = 0;
              _deletedTasksPageIndex = 0;
            });
            _persistLandingFilters();
          },
        ),
    ];
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
