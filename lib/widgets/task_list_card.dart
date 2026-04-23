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

/// Legend for Home / Tasks: explains PIC team background colours on [TaskListCard].
class PicTeamColorLegend extends StatelessWidget {
  const PicTeamColorLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Task background colour reflects the PIC’s team.',
          style: (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            fontSize: kLandingListCardFontSize,
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
);

/// Task row for list tabs: name, assignees, status, start/due dates (matches singular + legacy tasks).
class TaskListCard extends StatefulWidget {
  const TaskListCard({super.key, required this.task});

  final Task task;

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

  /// Same green as the **Accepted** submission chip (`#298A00`).
  static const Color kCompletedOnMetaColor = kSubtaskCompletedOnMetaColor;

  /// Priority · status · Start · Due · Completed on … (single line).
  static Widget buildTaskMetaLine(BuildContext context, Task t) {
    final theme = Theme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final ymd = DateFormat('yyyy-MM-dd');
    final prefix =
        '${priorityToDisplayName(t.priority)} · ${statusLabel(t)}'
        '${t.startDate != null ? ' · Start ${ymd.format(t.startDate!)}' : ''}';
    final due = t.endDate;
    final duePart = due != null ? ' · Due ${ymd.format(due)}' : '';
    final comp = t.completionDate;
    final showCompleted = _isTaskDisplayCompleted(t) && comp != null;
    if (!showCompleted) {
      return Text(
        '$prefix$duePart',
        style: baseStyle,
      );
    }
    final completedSeg =
        ' · Completed on ${HkTime.formatInstantAsHk(comp, 'yyyy-MM-dd')}';
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '$prefix$duePart'),
          TextSpan(
            text: completedSeg,
            style: baseStyle.copyWith(
              color: kCompletedOnMetaColor,
              fontWeight: FontWeight.w600,
              fontSize: kLandingListCardFontSize,
            ),
          ),
        ],
      ),
    );
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

  @override
  State<TaskListCard> createState() => _TaskListCardState();
}

class _TaskListCardState extends State<TaskListCard> {
  late Future<_TaskListCardData> _cardDataFuture;
  bool _subtasksExpanded = false;

  /// `null` = default order: [SingularSubtask.createDate] descending (newest first).
  SubtaskListSortColumn? _activeSubtaskSort;
  bool _subtaskSortAscending = true;

  @override
  void initState() {
    super.initState();
    _cardDataFuture = _loadCardData();
  }

  @override
  void didUpdateWidget(covariant TaskListCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id) {
      _cardDataFuture = _loadCardData();
      _subtasksExpanded = false;
      _activeSubtaskSort = null;
      _subtaskSortAscending = true;
    }
  }

  Future<_TaskListCardData> _loadCardData() async {
    final t = widget.task;
    final picKey = t.pic?.trim();
    final subtasks = t.isSingularTableRow
        ? await SupabaseService.fetchSubtasksForTask(t.id)
        : <SingularSubtask>[];
    final keys = <String>{
      ...t.assigneeIds,
      if (picKey != null && picKey.isNotEmpty) picKey,
    };
    for (final st in subtasks) {
      keys.addAll(st.assigneeIds);
      final p = st.pic?.trim();
      if (p != null && p.isNotEmpty) keys.add(p);
    }
    final names = await SupabaseService.staffDisplayNamesForKeys(keys.toList());
    final picTeam =
        await SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey);
    return (names, picTeam, subtasks);
  }

  /// Latest calendar due among all sub-tasks (any count); `null` if none have a due date.
  DateTime? _maxSubtaskDue(List<SingularSubtask> subtasks) {
    DateTime? maxD;
    for (final st in subtasks) {
      final d = st.dueDate;
      if (d == null) continue;
      if (maxD == null || d.isAfter(maxD)) maxD = d;
    }
    return maxD;
  }

  void _onSubtaskSortMenu(SubtaskListSortColumn column, String v) {
    setState(() {
      if (v == 'clear') {
        if (_activeSubtaskSort == column) {
          _activeSubtaskSort = null;
          _subtaskSortAscending = true;
        }
      } else if (v == 'asc') {
        _activeSubtaskSort = column;
        _subtaskSortAscending = true;
      } else if (v == 'desc') {
        _activeSubtaskSort = column;
        _subtaskSortAscending = false;
      }
    });
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
        final officerNames = t.assigneeIds
            .map((id) => nameMap[id] ?? state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort();
        final showPicLine = t.assigneeIds.length > 1 &&
            picKey != null &&
            picKey.isNotEmpty;
        final pk = picKey;
        final cardTint = TaskListCard.cardColorForPicTeam(picTeamId);
        final maxSubDue = _maxSubtaskDue(subtasks);
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TaskDetailScreen(taskId: t.id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
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
                            const SizedBox(height: 8),
                            if (officerNames.isNotEmpty)
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
                            TaskListCard.buildTaskMetaLine(context, t),
                            if (subtasks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                maxSubDue != null
                                    ? 'Max. sub-task due: ${DateFormat('yyyy-MM-dd').format(maxSubDue)}'
                                    : 'Max. sub-task due: —',
                                style: listTextVariant,
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
              if (subtasks.isNotEmpty) ...[
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
                if (_subtasksExpanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                'Sort',
                                style: subtasksHeaderStyle,
                              ),
                            ),
                            for (final col in SubtaskListSortColumn.values)
                              SubtaskSortColumnChip(
                                column: col,
                                active: _activeSubtaskSort == col,
                                ascending: _subtaskSortAscending,
                                onMenuSelected: (v) =>
                                    _onSubtaskSortMenu(col, v),
                              ),
                          ],
                        ),
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
                            onTap: () async {
                              final changed =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute<bool>(
                                  builder: (_) => SubtaskDetailScreen(
                                    subtaskId: s.id,
                                    replaceWithParentTaskOnBack: true,
                                  ),
                                ),
                              );
                              if (changed == true && mounted) {
                                await _reloadAfterSubtaskReturn();
                              }
                            },
                          ),
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
