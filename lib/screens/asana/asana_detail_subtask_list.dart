import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/singular_subtask.dart';
import '../../utils/hk_time.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Column layout aligned with [AsanaTasksPanel] task table rows.
class AsanaDetailSubtaskTableLayout {
  AsanaDetailSubtaskTableLayout(this.tableWidth, {this.nameAndDueOnly = false});

  static const double minTableWidth = 1104;
  static const double minNameDueTableWidth = 360;
  static const double typeCol = 48;
  static const double typeColGap = 10;
  static const double nameGutter = 36;
  static const int textColumnGapCount = 5;
  static const int nameDueTextColumnGapCount = 1;
  static const double singleLineExtent = 24;
  static const double hPad = 12;

  final double tableWidth;
  final bool nameAndDueOnly;

  late final double _inner = (tableWidth -
          (nameAndDueOnly
              ? 0
              : typeCol + typeColGap) -
          kAsanaTextColumnGap *
              (nameAndDueOnly
                  ? nameDueTextColumnGapCount
                  : textColumnGapCount) -
          hPad * 2)
      .clamp(200, double.infinity);

  double get nameCol => nameAndDueOnly ? _inner * 0.72 : _inner * 0.32;
  double get dueCol => nameAndDueOnly ? _inner * 0.28 : _inner * 0.08;
  double get projectCol => _inner * 0.12;
  double get creatorCol => _inner * 0.10;
  double get picCol => _inner * 0.10;
  double get statusCol => _inner * 0.09;
  double get submissionCol => _inner * 0.10;
}

TextStyle? _headerStyle(BuildContext context) => asanaTableHeaderStyle(context);

String _formatDue(DateTime? d) {
  if (d == null) return '—';
  final today = HkTime.todayDateOnlyHk();
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  return HkTime.formatInstantAsHk(d, 'MMM d');
}

String _formatPic(AppState state, String? pic) {
  final p = pic?.trim();
  if (p == null || p.isEmpty) return '—';
  return state.assigneeById(p)?.name ?? p;
}

bool _subCompleted(SingularSubtask s) {
  final x = s.status.trim().toLowerCase();
  return x == 'completed' || x == 'complete';
}

/// Sub-tasks in the same horizontal row layout as the task list.
class AsanaDetailSubtaskList extends StatelessWidget {
  const AsanaDetailSubtaskList({
    super.key,
    required this.viewportWidth,
    required this.subtasks,
    required this.tableColors,
    required this.appState,
    this.projectName = '—',
    this.nameAndDueOnly = false,
    this.onOpenSubtask,
  });

  final double viewportWidth;
  final List<SingularSubtask> subtasks;
  final AsanaTableColors tableColors;
  final AppState appState;
  final String projectName;
  final bool nameAndDueOnly;
  final void Function(String subtaskId)? onOpenSubtask;

  @override
  Widget build(BuildContext context) {
    if (subtasks.isEmpty) return const SizedBox.shrink();

    final minWidth = nameAndDueOnly
        ? AsanaDetailSubtaskTableLayout.minNameDueTableWidth
        : AsanaDetailSubtaskTableLayout.minTableWidth;
    final tableWidth =
        viewportWidth < minWidth ? minWidth : viewportWidth;
    final cols = AsanaDetailSubtaskTableLayout(
      tableWidth,
      nameAndDueOnly: nameAndDueOnly,
    );
    final header = _headerStyle(context);

    Widget table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AsanaDetailSubtaskTableLayout.hPad,
            10,
            AsanaDetailSubtaskTableLayout.hPad,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (!nameAndDueOnly) ...[
                SizedBox(
                  width: AsanaDetailSubtaskTableLayout.typeCol,
                  child: Text('', style: header),
                ),
                const SizedBox(
                  width: AsanaDetailSubtaskTableLayout.typeColGap,
                ),
              ],
              SizedBox(
                width: cols.nameCol,
                height: AsanaDetailSubtaskTableLayout.singleLineExtent,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!nameAndDueOnly)
                      const SizedBox(
                        width: AsanaDetailSubtaskTableLayout.nameGutter,
                      ),
                    Expanded(
                      child: Text(
                        'Sub-task Name',
                        style: header,
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
                style: header,
                rowHeight: AsanaDetailSubtaskTableLayout.singleLineExtent,
              ),
              if (!nameAndDueOnly) ...[
                asanaTextColumnGap(),
                asanaTableHeaderLabel(
                  width: cols.projectCol,
                  label: 'Project',
                  style: header,
                  rowHeight: AsanaDetailSubtaskTableLayout.singleLineExtent,
                ),
                asanaTextColumnGap(),
                asanaTableHeaderLabel(
                  width: cols.creatorCol,
                  label: 'Creator',
                  style: header,
                  rowHeight: AsanaDetailSubtaskTableLayout.singleLineExtent,
                ),
                asanaTextColumnGap(),
                asanaTableHeaderLabel(
                  width: cols.picCol,
                  label: 'PIC',
                  style: header,
                  rowHeight: AsanaDetailSubtaskTableLayout.singleLineExtent,
                ),
                asanaTextColumnGap(),
                asanaTableHeaderLabel(
                  width: cols.statusCol,
                  label: 'Status',
                  style: header,
                  rowHeight: AsanaDetailSubtaskTableLayout.singleLineExtent,
                ),
                asanaTableHeaderLabel(
                  width: cols.submissionCol,
                  label: 'Submission',
                  style: header,
                  rowHeight: AsanaDetailSubtaskTableLayout.singleLineExtent,
                ),
              ],
            ],
          ),
        ),
        ...subtasks.map((s) {
          final completed = _subCompleted(s);
          final rowValueStyle =
              asanaTableRowValueStyle(context, completed: completed);
          final nameStyle = asanaTableRowNameStyle(
            context,
            completed: completed,
            isSubtask: true,
          );
          final name = s.subtaskName.trim().isEmpty
              ? '(Unnamed sub-task)'
              : s.subtaskName.trim();

          return Material(
            color: tableColors.subtaskRow,
            child: InkWell(
              onTap: onOpenSubtask == null ? null : () => onOpenSubtask!(s.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AsanaDetailSubtaskTableLayout.hPad,
                  8,
                  AsanaDetailSubtaskTableLayout.hPad,
                  8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (!nameAndDueOnly) ...[
                      SizedBox(
                        width: AsanaDetailSubtaskTableLayout.typeCol,
                        child: Center(
                          child: AsanaRowTypeLetter(
                            letter: 'S',
                            completed: completed,
                            deleted: s.isDeleted,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: AsanaDetailSubtaskTableLayout.typeColGap,
                      ),
                    ],
                    SizedBox(
                      width: cols.nameCol,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (!nameAndDueOnly)
                            const SizedBox(
                              width:
                                  AsanaDetailSubtaskTableLayout.nameGutter,
                              height: AsanaDetailSubtaskTableLayout
                                  .singleLineExtent,
                            ),
                          Expanded(
                            child: Text(
                              name,
                              style: nameStyle,
                              maxLines: 2,
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
                        _formatDue(s.dueDate),
                        style: rowValueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!nameAndDueOnly) ...[
                      asanaTextColumnGap(),
                      SizedBox(
                        width: cols.projectCol,
                        child: Text(
                          projectName,
                          style: rowValueStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      asanaTextColumnGap(),
                      SizedBox(
                        width: cols.creatorCol,
                        child: Text(
                          (s.createByStaffName ?? '').trim().isEmpty
                              ? '—'
                              : s.createByStaffName!.trim(),
                          style: rowValueStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      asanaTextColumnGap(),
                      SizedBox(
                        width: cols.picCol,
                        child: Text(
                          _formatPic(appState, s.pic),
                          style: rowValueStyle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      asanaTextColumnGap(),
                      SizedBox(
                        width: cols.statusCol,
                        child: AsanaTableCellChip(
                          child: AsanaStatusChip(status: s.status),
                        ),
                      ),
                      SizedBox(
                        width: cols.submissionCol,
                        child: AsanaTableCellChip(
                          child: AsanaSubmissionChip(submission: s.submission),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );

    if (viewportWidth < minWidth) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: tableWidth, child: table),
      );
    }
    return table;
  }
}
