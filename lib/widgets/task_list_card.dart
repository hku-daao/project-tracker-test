import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/singular_subtask.dart';
import '../models/task.dart';
import '../priority.dart';
import '../screens/high_level/subtask_detail_screen.dart';
import '../screens/task_detail_screen.dart';
import '../services/supabase_service.dart';
import '../utils/hk_time.dart';
import '../utils/subtask_list_sort.dart';
import 'singular_subtask_row_card.dart';
import 'subtask_meta_line.dart';
import 'subtask_sort_column_chip.dart';

/// PIC team colour definition (`staff.team_id` / `team.team_id` business keys).
class PicTeamColorEntry {
  const PicTeamColorEntry({
    required this.teamKey,
    required this.color,
    required this.legendLabel,
  });

  final String teamKey;
  final Color color;
  final String legendLabel;
}

/// Ordered list for [TaskListCard.cardColorForPicTeam] and [PicTeamColorLegend].
const List<PicTeamColorEntry> kPicTeamColorEntries = [
  PicTeamColorEntry(
    teamKey: 'advancement_intel',
    color: Color(0xFFFFFBE8),
    legendLabel: 'Advancement Intelligence',
  ),
  PicTeamColorEntry(
    teamKey: 'president_office',
    color: Color(0xFFFEE8FF),
    legendLabel: 'President Office',
  ),
  PicTeamColorEntry(
    teamKey: 'fundraising',
    color: Color(0xFFE8FDFF),
    legendLabel: 'Fundraising',
  ),
  PicTeamColorEntry(
    teamKey: 'alumni',
    color: Color(0xFFEEFFD4),
    legendLabel: 'Alumni',
  ),
  PicTeamColorEntry(
    teamKey: 'admin_team',
    color: Color(0xFFFFE9E3),
    legendLabel: 'Administration',
  ),
];

/// Legend for list screens: explains team tint swatches ([TaskListCard], project rows).
class PicTeamColorLegend extends StatelessWidget {
  const PicTeamColorLegend({
    super.key,
    this.caption =
        "Task and sub-task background colour reflect the PIC's team.",
  });

  /// Short line above the colour chips (Overview vs Project dashboard wording differs).
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            fontSize: kLandingListCardFontSize - 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final e in kPicTeamColorEntries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: e.color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.35),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    e.legendLabel,
                    style: (theme.textTheme.bodyMedium ?? const TextStyle())
                        .copyWith(fontSize: kLandingListCardFontSize),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

typedef _TaskListCardData = (
  Map<String, String> names,
  String? picTeam,
  List<SingularSubtask> subtasks,
  List<SingularSubtask> deletedSubtasks,
);

/// Task row for list tabs: name, assignees, status, start/due dates (matches singular + legacy tasks).
class TaskListCard extends StatefulWidget {
  const TaskListCard({
    super.key,
    required this.task,
    /// When true (e.g. Customized dashboard), sub-tasks are always listed — no expand/collapse header.
    this.flatSubtasksAlwaysVisible = false,
    /// When true (Customized dashboard), only the task block is shown — sub-tasks are listed as sibling cards.
    this.taskOnly = false,
    /// Prefix title with **Task:** (Customized dashboard).
    this.showCustomizedTaskTitle = false,
    this.openedFromOverview = false,
    /// Overview meta line: `yyyy-MM-dd` from task update vs comment activity.
    this.overviewLastUpdatedYmd,
    this.onTaskTap,
    /// When the landing filter includes **Deleted**, list deleted sub-tasks under a grey header.
    this.includeDeletedSubtasks = false,
    /// Overview **All tasks & sub-tasks** tab: compact layout (T badge; hide assignees/project;
    /// PIC under title when exactly one assignee).
    this.overviewAllTabStyling = false,
  });

  final Task task;

  /// When set, called instead of pushing [TaskDetailScreen] (e.g. project detail).
  final VoidCallback? onTaskTap;

  /// See [buildTaskMetaLine] — set with [taskOnly] + Overview flat list.
  final String? overviewLastUpdatedYmd;

  /// Sub-tasks shown inline without tapping expand ([flatSubtasksAlwaysVisible]) — landing uses `false`.
  final bool flatSubtasksAlwaysVisible;

  /// Task summary only; sub-tasks omitted ([taskOnly] implies no nested sub-task UI).
  final bool taskOnly;

  /// When [taskOnly], show **Task:** label before the bold task name.
  final bool showCustomizedTaskTitle;

  final bool openedFromOverview;

  /// See landing status filter (Deleted).
  final bool includeDeletedSubtasks;

  /// Overview flat list — **All tasks & sub-tasks** tab only.
  final bool overviewAllTabStyling;

  /// Background tint from PIC's [`staff.team_id`] / [`team.team_id`] (home / initiative task lists).
  static Color? cardColorForPicTeam(String? teamBusinessId) {
    final t = teamBusinessId?.trim().toLowerCase();
    if (t == null || t.isEmpty) return null;
    for (final e in kPicTeamColorEntries) {
      if (e.teamKey == t) return e.color;
    }
    return null;
  }

  static String statusLabel(Task t) {
    if (t.isSingularTableRow) {
      final raw = t.dbStatus?.trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return taskStatusDisplayNames[t.status] ?? '';
  }

  static bool _isTaskDisplayCompleted(Task t) {
    if (t.isSingularTableRow) {
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'completed' || s == 'complete';
    }
    return t.status == TaskStatus.done;
  }

  /// True when [Task.endDate] is set and strictly before HK today (not deleted / completed).
  static bool taskEndDateCalendarOverdue(Task t) {
    if (_isTaskDisplayCompleted(t)) return false;
    if (t.isSingularTableRow) {
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      if (s == 'delete' || s == 'deleted') return false;
    }
    final due = t.endDate;
    if (due == null) return false;
    final day = DateTime(due.year, due.month, due.day);
    return day.isBefore(HkTime.todayDateOnlyHk());
  }

  /// Same green as the **Accepted** submission chip (`#298A00`).
  static const Color kCompletedOnMetaColor = kSubtaskCompletedOnMetaColor;

  /// Hyphenation point (U+2027) before “Completed on …” — default colour, not green.
  static const String kCompletedOnBullet = '\u2027';

  /// Optional **Last updated** suffix (Overview flat list; [ymd] is `yyyy-MM-dd`).
  static List<InlineSpan> _overviewTaskLastUpdatedSpans(
    String? ymd,
    TextStyle baseStyle,
  ) {
    if (ymd == null || ymd.isEmpty) return const <InlineSpan>[];
    return [
      TextSpan(text: ' $kCompletedOnBullet ', style: baseStyle),
      TextSpan(text: 'Last updated $ymd', style: baseStyle),
    ];
  }

  /// Priority · status · Start · Due (red if overdue) · ‧ Completed on … (single line).
  static Widget buildTaskMetaLine(
    BuildContext context,
    Task t, {
    String? overviewLastUpdatedYmd,
  }) {
    final theme = Theme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final overdueLabelStyle = baseStyle.copyWith(
      color: kOverdueDueDateColor,
      fontWeight: FontWeight.w600,
      fontSize: kLandingListCardFontSize,
    );
    final greenCompletedStyle = baseStyle.copyWith(
      color: kCompletedOnMetaColor,
      fontWeight: FontWeight.w600,
      fontSize: kLandingListCardFontSize,
    );
    final ymd = DateFormat('yyyy-MM-dd');
    final prefix =
        '${priorityToDisplayName(t.priority)} · ${statusLabel(t)}'
        '${t.startDate != null ? ' · Start ${ymd.format(t.startDate!)}' : ''}';
    final due = t.endDate;
    final comp = t.completionDate;
    final showCompleted = _isTaskDisplayCompleted(t) && comp != null;
    final dueOverdue = taskEndDateCalendarOverdue(t);
    final dueStr = due != null ? ymd.format(due) : null;
    final showTaskOverdue =
        t.isSingularTableRow && t.overdueDay > 0;

    String? resolvedLastUpdatedYmd = overviewLastUpdatedYmd;
    if (resolvedLastUpdatedYmd == null || resolvedLastUpdatedYmd.isEmpty) {
      final lu = t.lastUpdated;
      if (lu != null) {
        resolvedLastUpdatedYmd = ymd.format(lu.toLocal());
      }
    }

    List<InlineSpan> dueSpans() {
      if (due == null || dueStr == null) return const <InlineSpan>[];
      if (dueOverdue) {
        return [
          const TextSpan(text: ' · Due '),
          TextSpan(
            text: dueStr,
            style: baseStyle.copyWith(
              color: kOverdueDueDateColor,
              fontWeight: FontWeight.w600,
              fontSize: kLandingListCardFontSize,
            ),
          ),
        ];
      }
      return [TextSpan(text: ' · Due $dueStr')];
    }

    List<InlineSpan> taskOverdueSpans() {
      if (!showTaskOverdue) return const <InlineSpan>[];
      return [
        const TextSpan(text: ' · '),
        TextSpan(
          text: 'Overdue ${t.overdueDay} day(s)',
          style: overdueLabelStyle,
        ),
      ];
    }

    List<InlineSpan> completedOnSpans() {
      return [
        TextSpan(text: ' $kCompletedOnBullet ', style: baseStyle),
        TextSpan(
          text:
              'Completed on ${HkTime.formatInstantAsHk(comp, 'yyyy-MM-dd')}',
          style: greenCompletedStyle,
        ),
      ];
    }

    List<InlineSpan> overviewLu() =>
        _overviewTaskLastUpdatedSpans(resolvedLastUpdatedYmd, baseStyle);

    if (!showCompleted) {
      if (due == null) {
        if (!showTaskOverdue) {
          if (resolvedLastUpdatedYmd == null || resolvedLastUpdatedYmd.isEmpty) {
            return Text(prefix, style: baseStyle);
          }
          return Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                TextSpan(text: prefix),
                ...overviewLu(),
              ],
            ),
          );
        }
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              TextSpan(text: prefix),
              ...taskOverdueSpans(),
              ...overviewLu(),
            ],
          ),
        );
      }
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: prefix),
            ...dueSpans(),
            ...taskOverdueSpans(),
            ...overviewLu(),
          ],
        ),
      );
    }
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: prefix),
          ...dueSpans(),
          ...taskOverdueSpans(),
          ...overviewLu(),
          ...completedOnSpans(),
        ],
      ),
    );
  }

  /// Largest [SingularSubtask.overdueDay] among **Incomplete** subtasks whose due date
  /// equals [earliestDue] (calendar day). Pairs with [minSubtaskDueIncompleteOnly].
  static int maxOverdueDayOnEarliestSubtaskDue(
    List<SingularSubtask> subtasks,
    DateTime? earliestDue,
  ) {
    if (earliestDue == null) return 0;
    final target = DateTime(
      earliestDue.year,
      earliestDue.month,
      earliestDue.day,
    );
    var m = 0;
    for (final st in subtasks) {
      if (!_subtaskEligibleForEarliestDueLine(st)) continue;
      if (st.dueDate == null) continue;
      final d = DateTime(st.dueDate!.year, st.dueDate!.month, st.dueDate!.day);
      if (d == target && st.overdueDay > m) m = st.overdueDay;
    }
    return m;
  }

  static bool _isSubmissionSubmitted(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'submitted';
  }

  static bool _isSubmissionAccepted(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'accepted';
  }

  static bool _isSubmissionReturned(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'returned';
  }

  static const Color _kAcceptedTagColor = kCompletedOnMetaColor;
  static const Color _kReturnedTagColor = Color(0xFF0B0094);

  /// Submission chips on list cards and sub-task rows ([_submissionBadge], [buildSubmissionTag]).
  static const double kSubmissionChipFontSize = 11;

  /// “Over preset timeline” pill on list cards ([buildOverPresetTimelineTag]).
  static const double kOverPresetPillFontSize = 11;

  static Widget _submissionBadge(String label, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: kSubmissionChipFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Same colours as the submission chips on the home task list ([_submissionBadge]).
  /// Returns `null` if [submission] is empty.
  static Widget? buildSubmissionTag(String? submission) {
    final raw = submission?.trim() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == 'submitted') {
      return _submissionBadge('Submitted', Colors.red);
    }
    if (lower == 'accepted') {
      return _submissionBadge('Accepted', _kAcceptedTagColor);
    }
    if (lower == 'returned') {
      return _submissionBadge('Returned', _kReturnedTagColor);
    }
    if (lower == 'pending') {
      return _submissionBadge('Pending', Colors.grey.shade700);
    }
    return _submissionBadge(raw, Colors.grey.shade600);
  }

  static const Color _kOverPresetTimelineColor = Color(0xFFFFCD05);

  /// Tag when extend-timeline reason exists (list cards; no raw reason text).
  static Widget buildOverPresetTimelineTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kOverPresetTimelineColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Over preset timeline',
        style: TextStyle(
          color: const Color(0xFF1A1A1A),
          fontSize: kOverPresetPillFontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Earliest **calendar day** due among sub-tasks; `null` if none have a due date.
  /// Used with [maxSubtaskDueForSort] for landing **Due date** sort vs [Task.endDate] (date-only).
  static DateTime? minSubtaskDueForSort(List<SingularSubtask> subtasks) {
    DateTime? minDay;
    for (final st in subtasks) {
      final d = st.dueDate;
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (minDay == null || day.isBefore(minDay)) minDay = day;
    }
    return minDay;
  }

  static bool _subtaskEligibleForEarliestDueLine(SingularSubtask st) {
    if (st.isDeleted) return false;
    return st.status.trim().toLowerCase() == 'incomplete';
  }

  /// Earliest calendar due among sub-tasks with status **Incomplete** only (landing card line).
  static DateTime? minSubtaskDueIncompleteOnly(List<SingularSubtask> subtasks) {
    DateTime? minDay;
    for (final st in subtasks) {
      if (!_subtaskEligibleForEarliestDueLine(st)) continue;
      final d = st.dueDate;
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (minDay == null || day.isBefore(minDay)) minDay = day;
    }
    return minDay;
  }

  /// Latest **calendar day** due among sub-tasks; `null` if none have a due date.
  static DateTime? maxSubtaskDueForSort(List<SingularSubtask> subtasks) {
    DateTime? maxDay;
    for (final st in subtasks) {
      final d = st.dueDate;
      if (d == null) continue;
      final day = DateTime(d.year, d.month, d.day);
      if (maxDay == null || day.isAfter(maxDay)) maxDay = day;
    }
    return maxDay;
  }

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  late Future<_TaskListCardData> _cardDataFuture;
  bool _subtasksExpanded = false;

  /// `null` = default order: [SingularSubtask.createDate] descending (newest first).
  SubtaskListSortColumn? _activeSubtaskSort;
  /// For **Created date (default)** (`_activeSubtaskSort == null`): `false` = descending (newest first).
  bool _subtaskSortAscending = false;

  @override
  void initState() {
    super.initState();
    SupabaseService.addSubtaskCacheInvalidateListener(_onSubtaskCacheInvalidated);
    _cardDataFuture = _loadCardData();
    if (widget.flatSubtasksAlwaysVisible && !widget.taskOnly) {
      _subtasksExpanded = true;
    } else if (widget.includeDeletedSubtasks) {
      // Landing **Deleted** filter: show deleted sub-tasks without an extra expand tap.
      _subtasksExpanded = true;
    }
  }

  void _onSubtaskCacheInvalidated(String taskId) {
    if (taskId != widget.task.id || !mounted) return;
    setState(() {
      _cardDataFuture = _loadCardData();
    });
  }

  @override
  void dispose() {
    SupabaseService.removeSubtaskCacheInvalidateListener(_onSubtaskCacheInvalidated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TaskListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _cardDataFuture = _loadCardData();
      _subtasksExpanded =
          widget.flatSubtasksAlwaysVisible && !widget.taskOnly;
      _activeSubtaskSort = null;
      _subtaskSortAscending = false;
    }
    if (!oldWidget.flatSubtasksAlwaysVisible &&
        widget.flatSubtasksAlwaysVisible &&
        !widget.taskOnly) {
      _subtasksExpanded = true;
    }
    if (oldWidget.includeDeletedSubtasks != widget.includeDeletedSubtasks) {
      _cardDataFuture = _loadCardData();
      if (widget.includeDeletedSubtasks) {
        _subtasksExpanded = true;
      }
    }
  }

  Future<_TaskListCardData> _loadCardData() async {
    final t = widget.task;
    final picKey = t.pic?.trim();
    List<SingularSubtask> subtasks = <SingularSubtask>[];
    List<SingularSubtask> deletedSubtasks = <SingularSubtask>[];
    if (t.isSingularTableRow) {
      if (widget.includeDeletedSubtasks) {
        final all =
            await SupabaseService.fetchAllSubtasksForTaskForDetail(t.id);
        subtasks = all.where((s) => !s.isDeleted).toList();
        deletedSubtasks = all.where((s) => s.isDeleted).toList();
      } else {
        subtasks = await SupabaseService.fetchSubtasksForTask(t.id);
      }
    }
    final keys = <String>{
      ...t.assigneeIds,
      if (picKey != null && picKey.isNotEmpty) picKey,
    };
    for (final st in [...subtasks, ...deletedSubtasks]) {
      keys.addAll(st.assigneeIds);
      final p = st.pic?.trim();
      if (p != null && p.isNotEmpty) keys.add(p);
    }
    final names = await SupabaseService.staffDisplayNamesForKeys(keys.toList());
    final picTeam =
        await SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey);
    return (names, picTeam, subtasks, deletedSubtasks);
  }

  Future<void> _reloadAfterSubtaskReturn() async {
    setState(() {
      _cardDataFuture = _loadCardData();
    });
    await _cardDataFuture;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final t = widget.task;
    final picKey = t.pic?.trim();
    return FutureBuilder<_TaskListCardData>(
      future: _cardDataFuture,
      builder: (context, snapshot) {
        final theme = Theme.of(context);
        final listText = (theme.textTheme.bodyMedium ?? const TextStyle())
            .copyWith(fontSize: kLandingListCardFontSize);
        final taskTitleStyle =
            listText.copyWith(fontWeight: FontWeight.bold);
        final listTextW500 =
            listText.copyWith(fontWeight: FontWeight.w500);
        final listTextVariant = listText.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        );
        final subtasksHeaderStyle =
            listText.copyWith(fontWeight: FontWeight.w600);
        final nameMap = snapshot.data?.$1 ?? {};
        final picTeamId = snapshot.data?.$2;
        final subtasks = snapshot.data?.$3 ?? <SingularSubtask>[];
        final deletedSubtasks =
            snapshot.data?.$4 ?? <SingularSubtask>[];
        final officerNames = t.assigneeIds
            .map((id) => nameMap[id] ?? state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort();
        final showPicLine = !widget.overviewAllTabStyling &&
            t.assigneeIds.length > 1 &&
            picKey != null &&
            picKey.isNotEmpty;
        final showOverviewAllSingleAssigneePic = widget.overviewAllTabStyling &&
            t.assigneeIds.length == 1 &&
            picKey != null &&
            picKey.isNotEmpty;
        final pk = picKey;
        final cardTint = TaskListCard.cardColorForPicTeam(picTeamId);
        final earliestSubDue =
            TaskListCard.minSubtaskDueIncompleteOnly(subtasks);
        final todayHk = HkTime.todayDateOnlyHk();
        final earliestSubDueOverdue = earliestSubDue != null &&
            earliestSubDue.isBefore(todayHk);
        final maxOdOnEarliest = TaskListCard.maxOverdueDayOnEarliestSubtaskDue(
          subtasks,
          earliestSubDue,
        );
        String resolveName(String id) =>
            nameMap[id] ?? state.assigneeById(id)?.name ?? id;
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: cardTint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: widget.onTaskTap ??
                    () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TaskDetailScreen(
                              taskId: t.id,
                              openedFromOverview: widget.openedFromOverview,
                            ),
                          ),
                        ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.overviewAllTabStyling) ...[
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              theme.colorScheme.primaryContainer,
                          child: Text(
                            'T',
                            style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontSize: 13,
                                ) ??
                                TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: widget.showCustomizedTaskTitle
                                      ? (widget.overviewAllTabStyling
                                          ? Text(
                                              t.name,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: taskTitleStyle,
                                            )
                                          : Text.rich(
                                              TextSpan(
                                                style: listText,
                                                children: [
                                                  const TextSpan(text: 'Task: '),
                                                  TextSpan(
                                                    text: t.name,
                                                    style: taskTitleStyle,
                                                  ),
                                                ],
                                              ),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ))
                                      : Text(
                                          t.name,
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: taskTitleStyle,
                                        ),
                                ),
                                if (TaskListCard._isSubmissionSubmitted(t)) ...[
                                  const SizedBox(width: 8),
                                  TaskListCard._submissionBadge(
                                    'Submitted',
                                    Colors.red,
                                  ),
                                ],
                                if (TaskListCard._isSubmissionAccepted(t)) ...[
                                  const SizedBox(width: 8),
                                  TaskListCard._submissionBadge(
                                    'Accepted',
                                    TaskListCard._kAcceptedTagColor,
                                  ),
                                ],
                                if (TaskListCard._isSubmissionReturned(t)) ...[
                                  const SizedBox(width: 8),
                                  TaskListCard._submissionBadge(
                                    'Returned',
                                    TaskListCard._kReturnedTagColor,
                                  ),
                                ],
                              ],
                            ),
                            if (showOverviewAllSingleAssigneePic &&
                                pk != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'PIC: ${nameMap[pk] ?? state.assigneeById(pk)?.name ?? pk}',
                                style: listTextW500,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            if (!widget.overviewAllTabStyling &&
                                (t.projectName ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Project: ${t.projectName!.trim()}',
                                style: listTextW500,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (!widget.overviewAllTabStyling &&
                                officerNames.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Assignee(s): ${officerNames.join(', ')}',
                                  style: listTextW500,
                                ),
                              ),
                            if (showPicLine && pk != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'PIC: ${nameMap[pk] ?? state.assigneeById(pk)?.name ?? pk}',
                                  style: listTextW500,
                                ),
                              ),
                            if (t.createByStaffName != null &&
                                t.createByStaffName!.trim().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  'Creator: ${t.createByStaffName!.trim()}',
                                  style: listTextVariant,
                                ),
                              ),
                            TaskListCard.buildTaskMetaLine(
                              context,
                              t,
                              overviewLastUpdatedYmd: widget.overviewLastUpdatedYmd,
                            ),
                            if (subtasks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              earliestSubDue == null
                                  ? Text(
                                      'Earliest sub-task due —',
                                      style: listTextVariant,
                                    )
                                  : Text.rich(
                                      TextSpan(
                                        style: listTextVariant,
                                        children: [
                                          const TextSpan(
                                            text: 'Earliest sub-task due ',
                                          ),
                                          TextSpan(
                                            text: DateFormat('yyyy-MM-dd')
                                                .format(earliestSubDue),
                                            style: listTextVariant.copyWith(
                                              color: earliestSubDueOverdue
                                                  ? kOverdueDueDateColor
                                                  : listTextVariant.color,
                                              fontWeight: earliestSubDueOverdue
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          if (maxOdOnEarliest > 0) ...[
                                            TextSpan(
                                              text:
                                                  ' ${TaskListCard.kCompletedOnBullet} ',
                                              style: listTextVariant,
                                            ),
                                            TextSpan(
                                              text:
                                                  'Overdue $maxOdOnEarliest day(s)',
                                              style: listTextVariant.copyWith(
                                                color: kOverdueDueDateColor,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                            ],
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 4, top: 4),
                        child: Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
              ),
              if (!widget.taskOnly &&
                  (subtasks.isNotEmpty || deletedSubtasks.isNotEmpty)) ...[
                if (!widget.flatSubtasksAlwaysVisible) ...[
                  const Divider(height: 1),
                  InkWell(
                    onTap: () => setState(() {
                      _subtasksExpanded = !_subtasksExpanded;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _subtasksExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 22,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sub-tasks (${subtasks.length})',
                              style: subtasksHeaderStyle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  const Divider(height: 1),
                if (widget.flatSubtasksAlwaysVisible || _subtasksExpanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SubtaskSortDropdown(
                        sortColumn: _activeSubtaskSort,
                        ascending: _subtaskSortAscending,
                        sortLabelStyle: subtasksHeaderStyle,
                        onSortColumnChanged: (v) {
                          setState(() => _activeSubtaskSort = v);
                        },
                        onToggleAscending: () {
                          setState(
                            () => _subtaskSortAscending = !_subtaskSortAscending,
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in SubtaskListSort.sort(
                          subtasks,
                          resolveName: resolveName,
                          activeColumn: _activeSubtaskSort,
                          ascending: _subtaskSortAscending,
                        ))
                          SingularSubtaskRowCard(
                            subtask: s,
                            resolveName: resolveName,
                            overviewAllTabStyling: widget.overviewAllTabStyling,
                            onTap: () async {
                              final changed =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute<bool>(
                                  builder: (_) => SubtaskDetailScreen(
                                    subtaskId: s.id,
                                    replaceWithParentTaskOnBack: true,
                                    openedFromOverview: widget.openedFromOverview,
                                  ),
                                ),
                              );
                              if (changed == true && mounted) {
                                await _reloadAfterSubtaskReturn();
                              }
                            },
                          ),
                        if (deletedSubtasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Deleted (${deletedSubtasks.length})',
                                style: subtasksHeaderStyle.copyWith(
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          for (final s in SubtaskListSort.sort(
                            deletedSubtasks,
                            resolveName: resolveName,
                            activeColumn: _activeSubtaskSort,
                            ascending: _subtaskSortAscending,
                          ))
                            SingularSubtaskRowCard(
                              subtask: s,
                              resolveName: resolveName,
                              overviewAllTabStyling:
                                  widget.overviewAllTabStyling,
                              onTap: () async {
                                final changed =
                                    await Navigator.of(context).push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => SubtaskDetailScreen(
                                      subtaskId: s.id,
                                      replaceWithParentTaskOnBack: true,
                                      openedFromOverview:
                                          widget.openedFromOverview,
                                    ),
                                  ),
                                );
                                if (changed == true && mounted) {
                                  await _reloadAfterSubtaskReturn();
                                }
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
