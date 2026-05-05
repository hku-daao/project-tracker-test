import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/singular_subtask.dart';
import '../priority.dart';
import '../utils/hk_time.dart';

/// Body text size for [TaskListCard], [SubtaskMetaLine], and [SingularSubtaskRowCard].
const double kLandingListCardFontSize = 14;

/// Same green as **Accepted** / “Completed on” on list cards (`#298A00`).
const Color kSubtaskCompletedOnMetaColor = Color(0xFF298A00);

/// Due date text when calendar overdue (landing + task detail sub-task rows).
const Color kOverdueDueDateColor = Color(0xFFD32F2F);

/// Hyphenation point (U+2027) before “Completed on …” — default colour, not green.
const String kSubtaskCompletedOnBullet = '\u2027';

/// [null] = do not show “Completed on …”.
String? _completedOnDateYmd(SingularSubtask s) {
  final cd = s.completionDate;
  if (cd == null) return null;
  final sub = s.submission?.trim().toLowerCase() ?? '';
  final st = s.status.trim().toLowerCase();
  final show = sub == 'completed' ||
      st == 'completed' ||
      st == 'complete';
  if (!show) return null;
  return HkTime.formatInstantAsHk(cd, 'yyyy-MM-dd');
}

/// Priority · status · Start · Due (red if overdue) · ‧ Completed on … — list + task-detail sub-task rows.
class SubtaskMetaLine extends StatelessWidget {
  const SubtaskMetaLine({
    super.key,
    required this.subtask,
    /// Overview: `yyyy-MM-dd` from sub-task update vs comment activity.
    this.overviewLastUpdatedYmd,
  });

  final SingularSubtask subtask;
  final String? overviewLastUpdatedYmd;

  @override
  Widget build(BuildContext context) {
    final s = subtask;
    final theme = Theme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final overdueTextStyle = baseStyle.copyWith(
      color: kOverdueDueDateColor,
      fontWeight: FontWeight.w600,
      fontSize: kLandingListCardFontSize,
    );
    final greenStyle = baseStyle.copyWith(
      color: kSubtaskCompletedOnMetaColor,
      fontWeight: FontWeight.w600,
      fontSize: kLandingListCardFontSize,
    );
    final prefix = '${priorityToDisplayName(s.priority)} · ${s.status}';
    final startPart = s.startDate != null
        ? ' · Start ${DateFormat('yyyy-MM-dd').format(s.startDate!)}'
        : '';
    final ymd = DateFormat('yyyy-MM-dd');
    String? resolvedOverviewLu = overviewLastUpdatedYmd;
    if (resolvedOverviewLu == null || resolvedOverviewLu.isEmpty) {
      final lu = s.lastUpdated;
      if (lu != null) {
        resolvedOverviewLu = ymd.format(lu.toLocal());
      }
    }
    final completedYmd = _completedOnDateYmd(s);
    final completedSuffix = completedYmd == null
        ? const <InlineSpan>[]
        : [
            TextSpan(
              text: ' $kSubtaskCompletedOnBullet ',
              style: baseStyle,
            ),
            TextSpan(
              text: 'Completed on $completedYmd',
              style: greenStyle,
            ),
          ];

    List<InlineSpan> overdueDaySpans() {
      if (s.overdueDay <= 0) return const [];
      return [
        const TextSpan(text: ' · '),
        TextSpan(
          text: 'Overdue ${s.overdueDay} day(s)',
          style: overdueTextStyle,
        ),
      ];
    }

    List<InlineSpan> overviewLastUpdatedSpans() {
      final y = resolvedOverviewLu;
      if (y == null || y.isEmpty) return const <InlineSpan>[];
      return [
        TextSpan(text: ' $kSubtaskCompletedOnBullet ', style: baseStyle),
        TextSpan(text: 'Last updated $y', style: baseStyle),
      ];
    }

    if (s.dueDate == null) {
      if (completedYmd == null) {
        if (resolvedOverviewLu == null || resolvedOverviewLu.isEmpty) {
          return Text(
            '$prefix$startPart',
            style: baseStyle,
          );
        }
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              TextSpan(text: '$prefix$startPart'),
              ...overviewLastUpdatedSpans(),
            ],
          ),
        );
      }
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '$prefix$startPart'),
            ...overdueDaySpans(),
            ...overviewLastUpdatedSpans(),
            ...completedSuffix,
          ],
        ),
      );
    }
    final dueDay = DateTime(s.dueDate!.year, s.dueDate!.month, s.dueDate!.day);
    final st = s.status.trim().toLowerCase();
    final blocked = s.isDeleted ||
        st == 'completed' ||
        st == 'complete' ||
        st == 'deleted';
    final calOverdue = !blocked && dueDay.isBefore(HkTime.todayDateOnlyHk());
    final dueStr = ymd.format(s.dueDate!);

    if (!calOverdue) {
      if (completedYmd == null) {
        return Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              TextSpan(text: '$prefix$startPart · Due $dueStr'),
              ...overdueDaySpans(),
              ...overviewLastUpdatedSpans(),
            ],
          ),
        );
      }
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '$prefix$startPart · Due $dueStr'),
            ...overdueDaySpans(),
            ...overviewLastUpdatedSpans(),
            ...completedSuffix,
          ],
        ),
      );
    }
    if (completedYmd == null) {
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '$prefix$startPart · Due '),
            TextSpan(
              text: dueStr,
              style: baseStyle.copyWith(
                color: kOverdueDueDateColor,
                fontWeight: FontWeight.w600,
                fontSize: kLandingListCardFontSize,
              ),
            ),
            ...overdueDaySpans(),
            ...overviewLastUpdatedSpans(),
          ],
        ),
      );
    }
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '$prefix$startPart · Due '),
          TextSpan(
            text: dueStr,
            style: baseStyle.copyWith(
              color: kOverdueDueDateColor,
              fontWeight: FontWeight.w600,
              fontSize: kLandingListCardFontSize,
            ),
          ),
          ...overdueDaySpans(),
          ...overviewLastUpdatedSpans(),
          ...completedSuffix,
        ],
      ),
    );
  }
}
