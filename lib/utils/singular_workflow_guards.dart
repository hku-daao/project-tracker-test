import '../models/singular_subtask.dart';
import '../models/task.dart';

/// Parent [`task`] DB row is Completed → must not create further sub-tasks.
bool singularTaskStatusIsCompleted(Task task) {
  if (!task.isSingularTableRow) return false;
  final d = task.dbStatus?.trim().toLowerCase() ?? '';
  return d == 'completed' || d == 'complete';
}

/// Non-deleted sub-task not yet Completed blocks PIC submitting the parent task.
bool subtaskPreventsParentTaskSubmission(SingularSubtask s) {
  if (s.isDeleted) return false;
  final st = s.status.trim().toLowerCase();
  if (st == 'completed' || st == 'complete') return false;
  return true;
}
