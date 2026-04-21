import '../models/singular_subtask.dart';

/// Same columns as the landing [TaskListCard] sub-task sort row.
enum SubtaskListSortColumn {
  assignee,
  pic,
  startDate,
  dueDate,
  status,
  submission,
}

String subtaskListSortColumnLabel(SubtaskListSortColumn c) {
  switch (c) {
    case SubtaskListSortColumn.assignee:
      return 'Assignee';
    case SubtaskListSortColumn.pic:
      return 'PIC';
    case SubtaskListSortColumn.startDate:
      return 'Start date';
    case SubtaskListSortColumn.dueDate:
      return 'Due date';
    case SubtaskListSortColumn.status:
      return 'Status';
    case SubtaskListSortColumn.submission:
      return 'Submission';
  }
}

/// Sorts sub-tasks for list UIs (landing card, [TaskDetailScreen]).
///
/// When [activeColumn] is `null`, order is **[SingularSubtask.createDate] descending**
/// (newest first), then [SingularSubtask.subtaskName].
class SubtaskListSort {
  SubtaskListSort._();

  static String assigneeSortKey(
    SingularSubtask s,
    String Function(String id) res,
  ) {
    final names = s.assigneeIds.map((id) => res(id)).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  static String picSortKey(SingularSubtask s, String Function(String id) res) {
    final p = s.pic?.trim();
    if (p == null || p.isEmpty) return '';
    return res(p);
  }

  static int cmpStr(String a, String b, bool ascending) {
    final sa = a.trim().toLowerCase();
    final sb = b.trim().toLowerCase();
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    final c = sa.compareTo(sb);
    return ascending ? c : -c;
  }

  static int cmpDateNullable(
    DateTime? a,
    DateTime? b,
    bool ascending, {
    bool dateOnly = false,
  }) {
    DateTime? na = a;
    DateTime? nb = b;
    if (dateOnly && a != null) {
      na = DateTime(a.year, a.month, a.day);
    }
    if (dateOnly && b != null) {
      nb = DateTime(b.year, b.month, b.day);
    }
    if (na == null && nb == null) return 0;
    if (na == null) return 1;
    if (nb == null) return -1;
    final c = na.compareTo(nb);
    return ascending ? c : -c;
  }

  static int _tieBreakCreateDateDesc(SingularSubtask a, SingularSubtask b) {
    final ad = a.createDate;
    final bd = b.createDate;
    if (ad == null && bd == null) {
      return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
    }
    if (ad == null) return 1;
    if (bd == null) return -1;
    final c = bd.compareTo(ad);
    if (c != 0) return c;
    return a.subtaskName.toLowerCase().compareTo(b.subtaskName.toLowerCase());
  }

  static List<SingularSubtask> sort(
    List<SingularSubtask> raw, {
    required String Function(String id) resolveName,
    SubtaskListSortColumn? activeColumn,
    required bool ascending,
  }) {
    final out = List<SingularSubtask>.from(raw);
    if (activeColumn == null) {
      out.sort((a, b) => _tieBreakCreateDateDesc(a, b));
      return out;
    }

    final col = activeColumn;
    final asc = ascending;
    out.sort((a, b) {
      int c;
      switch (col) {
        case SubtaskListSortColumn.assignee:
          c = cmpStr(
            assigneeSortKey(a, resolveName),
            assigneeSortKey(b, resolveName),
            asc,
          );
          break;
        case SubtaskListSortColumn.pic:
          c = cmpStr(
            picSortKey(a, resolveName),
            picSortKey(b, resolveName),
            asc,
          );
          break;
        case SubtaskListSortColumn.startDate:
          c = cmpDateNullable(a.startDate, b.startDate, asc, dateOnly: true);
          break;
        case SubtaskListSortColumn.dueDate:
          c = cmpDateNullable(a.dueDate, b.dueDate, asc, dateOnly: true);
          break;
        case SubtaskListSortColumn.status:
          c = cmpStr(a.status, b.status, asc);
          break;
        case SubtaskListSortColumn.submission:
          c = cmpStr(
            a.submission ?? '',
            b.submission ?? '',
            asc,
          );
          break;
      }
      if (c != 0) return c;
      return _tieBreakCreateDateDesc(a, b);
    });
    return out;
  }
}
