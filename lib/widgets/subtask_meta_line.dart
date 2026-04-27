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

String? _completedOnColoredSegment(SingularSubtask s) {
  final cd = s.completionDate;
  if (cd == null) return null;
  final sub = s.submission?.trim().toLowerCase() ?? '';
  final st = s.status.trim().toLowerCase();
  final show = sub == 'completed' ||
      st == 'completed' ||
      st == 'complete';
  if (!show) return null;
  return ' · Completed on ${HkTime.formatInstantAsHk(cd, 'yyyy-MM-dd')}';
}

/// Priority · status · Start · Due (red if overdue) · Completed on … — matches task-detail sub-task card meta.
class SubtaskMetaLine extends StatelessWidget {
  const SubtaskMetaLine({super.key, required this.subtask});

  final SingularSubtask subtask;

  @override
  Widget build(BuildContext context) {
    final s = subtask;
    final theme = Theme.of(context);
    final baseStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final prefix = '${priorityToDisplayName(s.priority)} · ${s.status}';
    final startPart = s.startDate != null
        ? ' · Start ${DateFormat('yyyy-MM-dd').format(s.startDate!)}'
        : '';
    final greenSeg = _completedOnColoredSegment(s);
    final greenStyle = baseStyle.copyWith(
      color: kSubtaskCompletedOnMetaColor,
      fontWeight: FontWeight.w600,
      fontSize: kLandingListCardFontSize,
    );

    if (s.dueDate == null) {
      if (greenSeg == null) {
        return Text('$prefix$startPart', style: baseStyle);
      }
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '$prefix$startPart'),
            TextSpan(text: greenSeg, style: greenStyle),
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
    final overdue = !blocked && dueDay.isBefore(HkTime.todayDateOnlyHk());
    final dueStr = DateFormat('yyyy-MM-dd').format(s.dueDate!);
    if (!overdue) {
      if (greenSeg == null) {
        return Text('$prefix$startPart · Due $dueStr', style: baseStyle);
      }
      return Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: '$prefix$startPart · Due $dueStr'),
            TextSpan(text: greenSeg, style: greenStyle),
          ],
        ),
      );
    }
    if (greenSeg == null) {
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
          TextSpan(text: greenSeg, style: greenStyle),
        ],
      ),
    );
  }
}
