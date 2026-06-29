import 'package:flutter/material.dart';

import '../../priority.dart';
import 'asana_theme.dart';

/// Matches task table [bodyMedium] (~14px).
const double kAsanaTableChipFontSize = 14;

/// Left column marker: **T**ask, **S**ub-task, or **P**roject.
class AsanaRowTypeLetter extends StatelessWidget {
  const AsanaRowTypeLetter({
    super.key,
    required this.letter,
    this.completed = false,
    this.deleted = false,
  });

  final String letter;
  final bool completed;
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    final bg = deleted
        ? const Color(0xFFFFEBEE)
        : completed
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFECEFF1);
    final fg = deleted
        ? const Color(0xFFC62828)
        : completed
        ? const Color(0xFF2E7D32)
        : kAsanaTextPrimary;

    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
          height: 1,
        ),
      ),
    );
  }
}

/// Keeps status/submission pills only as wide as their label (not the full column).
class AsanaTableCellChip extends StatelessWidget {
  const AsanaTableCellChip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IntrinsicWidth(child: child),
    );
  }
}

/// Colored pill for task / sub-task status in Asana tables.
class AsanaStatusChip extends StatelessWidget {
  const AsanaStatusChip({
    super.key,
    required this.status,
    this.fontSize = kAsanaTableChipFontSize,
    this.preserveFullLabel = false,
    this.displayLabel,
  });

  final String status;
  final double fontSize;
  final bool preserveFullLabel;
  final String? displayLabel;

  static (String label, Color bg, Color fg) statusStyle(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'completed' || s == 'complete') {
      return ('Completed', const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
    }
    if (s == 'deleted' || s == 'delete') {
      return ('Deleted', const Color(0xFFFFEBEE), const Color(0xFFC62828));
    }
    if (s == 'paused') {
      return ('Paused', const Color(0xFFEFEBE9), const Color(0xFF6D4C41));
    }
    if (s == 'not started') {
      return ('Not started', const Color(0xFFFFF3E0), const Color(0xFFE65100));
    }
    if (s == 'in progress') {
      return ('In progress', const Color(0xFFE3F2FD), const Color(0xFF1565C0));
    }
    if (s.isEmpty || s == 'incomplete') {
      return ('Incomplete', const Color(0xFFECEFF1), const Color(0xFF455A64));
    }
    final label = raw.trim().isEmpty
        ? '—'
        : '${raw[0].toUpperCase()}${raw.substring(1).toLowerCase()}';
    return (label, const Color(0xFFE3F2FD), const Color(0xFF1565C0));
  }

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = statusStyle(status);
    final visibleLabel = displayLabel ?? label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        visibleLabel,
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodyMedium,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
        maxLines: 1,
        overflow: preserveFullLabel
            ? TextOverflow.visible
            : TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

/// Colored pill for task / sub-task priority.
class AsanaPriorityChip extends StatelessWidget {
  const AsanaPriorityChip({
    super.key,
    required this.priority,
    this.fontSize = kAsanaTableChipFontSize,
  });

  final int priority;
  final double fontSize;

  static (String label, Color bg, Color fg) priorityStyle(int priority) {
    if (priority == priorityUrgent) {
      return ('URGENT', const Color(0xFFFFEBEE), const Color(0xFFC62828));
    }
    return ('Standard', const Color(0xFFECEFF1), const Color(0xFF455A64));
  }

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = priorityStyle(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        priorityToDisplayName(priority),
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodyMedium,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

/// Colored pill for submission (same colours as [TaskListCard.buildSubmissionTag]).
class AsanaSubmissionChip extends StatelessWidget {
  const AsanaSubmissionChip({
    super.key,
    required this.submission,
    this.fontSize = kAsanaTableChipFontSize,
    this.preserveFullLabel = false,
    this.displayLabel,
  });

  final String? submission;
  final double fontSize;
  final String? displayLabel;

  /// When true, the pill label is never ellipsized (e.g. home table last column).
  final bool preserveFullLabel;

  static const Color _acceptedBg = Color(0xFF298A00);
  static const Color _returnedBg = Color(0xFF0B0094);

  static (String label, Color bg, Color fg) submissionStyle(String? raw) {
    final lower = (raw?.trim() ?? '').toLowerCase();
    if (lower.isEmpty || lower == 'pending') {
      return ('Pending', const Color(0xFF616161), Colors.white);
    }
    if (lower == 'submitted') {
      return ('Submitted', Colors.red, Colors.white);
    }
    if (lower == 'accepted') {
      return ('Accepted', _acceptedBg, Colors.white);
    }
    if (lower == 'returned') {
      return ('Returned', _returnedBg, Colors.white);
    }
    return (raw!.trim(), const Color(0xFF757575), Colors.white);
  }

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = submissionStyle(submission);
    final visibleLabel = displayLabel ?? label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        visibleLabel,
        style: asanaTextStyle(
          Theme.of(context).textTheme.bodyMedium,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: fg,
          height: 1.2,
        ),
        maxLines: 1,
        overflow: preserveFullLabel
            ? TextOverflow.visible
            : TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}
