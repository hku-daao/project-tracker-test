import '../app_state.dart';
import '../models/task.dart';
import '../widgets/task_list_card.dart';

/// Sort dimensions for tasks on [ProjectDetailScreen] (matches landing columns except Creator).
enum ProjectDetailTaskSortColumn {
  assignee,
  pic,
  startDate,
  dueDate,
  status,
  submission;

  String get label {
    switch (this) {
      case ProjectDetailTaskSortColumn.assignee:
        return 'Assignee';
      case ProjectDetailTaskSortColumn.pic:
        return 'PIC';
      case ProjectDetailTaskSortColumn.startDate:
        return 'Start date';
      case ProjectDetailTaskSortColumn.dueDate:
        return 'Due date';
      case ProjectDetailTaskSortColumn.status:
        return 'Status';
      case ProjectDetailTaskSortColumn.submission:
        return 'Submission';
    }
  }
}

/// Shared comparison helpers for project task ordering.
abstract final class ProjectTaskSort {
  static String assigneeSortKey(Task t, AppState state) {
    final names =
        t.assigneeIds
            .map((id) => state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  static String picSortKey(Task t, AppState state) {
    final p = t.pic?.trim();
    if (p == null || p.isEmpty) return '';
    return state.assigneeById(p)?.name ?? p;
  }

  static int cmpStrNullable(String? a, String? b, bool ascending) {
    final sa = a?.trim().toLowerCase() ?? '';
    final sb = b?.trim().toLowerCase() ?? '';
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    final c = sa.compareTo(sb);
    return ascending ? c : -c;
  }

  static int cmpDateForSort(DateTime? a, DateTime? b, bool ascending) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final c = a.compareTo(b);
    return ascending ? c : -c;
  }

  /// Sorts [tasks] for display on project detail (task-level due date only).
  static List<Task> sortTasks(
    List<Task> tasks,
    ProjectDetailTaskSortColumn? column,
    bool ascending,
    AppState state,
  ) {
    final asc = ascending;
    if (column == null) {
      final out = List<Task>.from(tasks);
      out.sort((a, b) {
        final c = cmpDateForSort(a.createdAt, b.createdAt, asc);
        if (c != 0) return c;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return out;
    }
    final col = column;
    final out = List<Task>.from(tasks);
    out.sort((a, b) {
      int c;
      switch (col) {
        case ProjectDetailTaskSortColumn.assignee:
          c = cmpStrNullable(
            assigneeSortKey(a, state),
            assigneeSortKey(b, state),
            asc,
          );
          break;
        case ProjectDetailTaskSortColumn.pic:
          c = cmpStrNullable(
            picSortKey(a, state),
            picSortKey(b, state),
            asc,
          );
          break;
        case ProjectDetailTaskSortColumn.startDate:
          c = cmpDateForSort(a.startDate, b.startDate, asc);
          break;
        case ProjectDetailTaskSortColumn.dueDate:
          c = cmpDateForSort(a.endDate, b.endDate, asc);
          break;
        case ProjectDetailTaskSortColumn.status:
          c = cmpStrNullable(
            TaskListCard.statusLabel(a),
            TaskListCard.statusLabel(b),
            asc,
          );
          break;
        case ProjectDetailTaskSortColumn.submission:
          c = cmpStrNullable(a.submission, b.submission, asc);
          break;
      }
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
}
