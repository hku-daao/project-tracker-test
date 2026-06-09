/// Which record the Asana right-hand detail slide panel is showing.
sealed class AsanaDetailSelection {
  const AsanaDetailSelection();

  const factory AsanaDetailSelection.task(String taskId) =
      AsanaTaskDetailSelection;
  const factory AsanaDetailSelection.subtask(String subtaskId) =
      AsanaSubtaskDetailSelection;
  const factory AsanaDetailSelection.project(String projectId) =
      AsanaProjectDetailSelection;
  const factory AsanaDetailSelection.createSubtask(String parentTaskId) =
      AsanaCreateSubtaskDetailSelection;
  const factory AsanaDetailSelection.createTask({String? initialProjectId}) =
      AsanaCreateTaskDetailSelection;
  const factory AsanaDetailSelection.createProject() =
      AsanaCreateProjectDetailSelection;
}

final class AsanaTaskDetailSelection extends AsanaDetailSelection {
  const AsanaTaskDetailSelection(this.taskId);
  final String taskId;
}

final class AsanaSubtaskDetailSelection extends AsanaDetailSelection {
  const AsanaSubtaskDetailSelection(this.subtaskId);
  final String subtaskId;
}

final class AsanaProjectDetailSelection extends AsanaDetailSelection {
  const AsanaProjectDetailSelection(this.projectId);
  final String projectId;
}

final class AsanaCreateSubtaskDetailSelection extends AsanaDetailSelection {
  const AsanaCreateSubtaskDetailSelection(this.parentTaskId);
  final String parentTaskId;
}

final class AsanaCreateTaskDetailSelection extends AsanaDetailSelection {
  const AsanaCreateTaskDetailSelection({this.initialProjectId});
  final String? initialProjectId;
}

final class AsanaCreateProjectDetailSelection extends AsanaDetailSelection {
  const AsanaCreateProjectDetailSelection();
}
