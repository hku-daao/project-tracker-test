import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import 'asana_detail_selection.dart';
import 'asana_create_project_detail_panel.dart';
import 'asana_project_detail_panel.dart';
import 'asana_subtask_detail_panel.dart';
import 'asana_task_detail_panel.dart';

/// Right-hand slide content (Asana-styled detail, not legacy full screens).
class AsanaDetailPanelHost extends StatelessWidget {
  const AsanaDetailPanelHost({
    super.key,
    required this.selection,
    required this.palette,
    required this.onClose,
    this.onPop,
    this.onPushCreateSubtask,
    this.onPushSubtask,
    this.onPushCreateTaskForProject,
    this.onPushTaskFromProject,
    this.onTaskCreated,
    this.onProjectCreated,
    this.onProjectChanged,
    this.onSubtaskCreated,
    this.onSubtaskChanged,
    this.detailRefreshToken = 0,
  });

  final AsanaDetailSelection selection;
  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final VoidCallback? onPop;
  final void Function(String parentTaskId)? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;
  final void Function(String projectId)? onPushCreateTaskForProject;
  final void Function(String taskId)? onPushTaskFromProject;
  final void Function(String taskId)? onTaskCreated;
  final void Function(String projectId)? onProjectCreated;
  final VoidCallback? onProjectChanged;
  final void Function(String parentTaskId, String subtaskId)? onSubtaskCreated;
  final VoidCallback? onSubtaskChanged;
  final int detailRefreshToken;

  @override
  Widget build(BuildContext context) {
    return switch (selection) {
      AsanaTaskDetailSelection(:final taskId) => AsanaTaskDetailPanel(
        taskId: taskId,
        palette: palette,
        refreshToken: detailRefreshToken,
        onClose: onClose,
        onPushCreateSubtask: onPushCreateSubtask == null
            ? null
            : () => onPushCreateSubtask!(taskId),
        onPushSubtask: onPushSubtask,
      ),
      AsanaSubtaskDetailSelection(:final subtaskId) => AsanaSubtaskDetailPanel(
        subtaskId: subtaskId,
        palette: palette,
        onClose: onPop ?? onClose,
        onChanged: onSubtaskChanged,
      ),
      AsanaProjectDetailSelection(:final projectId) => AsanaProjectDetailPanel(
        projectId: projectId,
        palette: palette,
        onClose: onClose,
        onChanged: onProjectChanged,
        onPushCreateTask: onPushCreateTaskForProject == null
            ? null
            : () => onPushCreateTaskForProject!(projectId),
        onPushTask: onPushTaskFromProject,
      ),
      AsanaCreateSubtaskDetailSelection(:final parentTaskId) =>
        AsanaSubtaskDetailPanel(
          createMode: true,
          parentTaskId: parentTaskId,
          palette: palette,
          onClose: onPop ?? onClose,
          onCreated: onSubtaskCreated == null
              ? null
              : (subtaskId) => onSubtaskCreated!(parentTaskId, subtaskId),
          onChanged: onSubtaskChanged,
        ),
      AsanaCreateTaskDetailSelection(:final initialProjectId) =>
        AsanaTaskDetailPanel(
          createMode: true,
          initialProjectId: initialProjectId,
          palette: palette,
          onClose: onClose,
          onCreated: onTaskCreated,
        ),
      AsanaCreateProjectDetailSelection() => AsanaCreateProjectDetailPanel(
        palette: palette,
        onClose: onClose,
        onCreated: onProjectCreated,
      ),
    };
  }
}
