import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import 'asana_detail_panel_host.dart';
import 'asana_detail_selection.dart';
import 'asana_task_detail_panel.dart';

/// Right-hand slide: task panel stays mounted; sub-task / create sub-task slide over it.
class AsanaDetailSlidePanel extends StatefulWidget {
  const AsanaDetailSlidePanel({
    super.key,
    required this.stack,
    required this.palette,
    required this.width,
    required this.onDismissAll,
    required this.onPop,
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

  final List<AsanaDetailSelection> stack;
  final int detailRefreshToken;
  final AsanaLandingPalette palette;
  final double width;
  final VoidCallback onDismissAll;
  final VoidCallback onPop;
  final void Function(String parentTaskId)? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;
  final void Function(String projectId)? onPushCreateTaskForProject;
  final void Function(String taskId)? onPushTaskFromProject;
  final void Function(String taskId)? onTaskCreated;
  final void Function(String projectId)? onProjectCreated;
  final VoidCallback? onProjectChanged;
  final void Function(String parentTaskId, String subtaskId)? onSubtaskCreated;
  final VoidCallback? onSubtaskChanged;

  @override
  State<AsanaDetailSlidePanel> createState() => _AsanaDetailSlidePanelState();
}

class _AsanaDetailSlidePanelState extends State<AsanaDetailSlidePanel> {
  final Map<String, GlobalKey> _taskPanelKeys = {};

  GlobalKey _taskPanelKey(String taskId) =>
      _taskPanelKeys.putIfAbsent(taskId, GlobalKey.new);

  Future<void> _handleClose() async {
    if (widget.stack.length > 1) {
      widget.onPop();
    } else {
      widget.onDismissAll();
    }
  }

  static String? _baseTaskId(List<AsanaDetailSelection> stack) {
    if (stack.isEmpty) return null;
    return switch (stack.first) {
      AsanaTaskDetailSelection(:final taskId) => taskId,
      AsanaCreateSubtaskDetailSelection(:final parentTaskId) => parentTaskId,
      _ => null,
    };
  }

  /// Top overlay when drilling in from a task; sole panel when opened without a task base.
  static AsanaDetailSelection? _overlaySelection(
    List<AsanaDetailSelection> stack,
  ) {
    if (stack.isEmpty) return null;
    if (stack.length > 1) return stack.last;
    return switch (stack.last) {
      AsanaTaskDetailSelection() => null,
      AsanaCreateTaskDetailSelection() => null,
      AsanaProjectDetailSelection() => null,
      AsanaCreateProjectDetailSelection() => null,
      _ => stack.last,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stack.isEmpty) return const SizedBox.shrink();

    final chrome = AsanaSlideChrome(widget.palette);
    final baseTaskId = _baseTaskId(widget.stack);
    final overlay = _overlaySelection(widget.stack);
    final hasOverlay = overlay != null;
    final subtaskOverlay =
        overlay is AsanaSubtaskDetailSelection ||
        overlay is AsanaCreateSubtaskDetailSelection;

    final currentSelection = overlay ?? widget.stack.last;
    final String slideTitle = switch (currentSelection) {
      AsanaTaskDetailSelection() ||
      AsanaCreateTaskDetailSelection() => 'Task Details',
      AsanaSubtaskDetailSelection() ||
      AsanaCreateSubtaskDetailSelection() => 'Sub-task Details',
      AsanaProjectDetailSelection() ||
      AsanaCreateProjectDetailSelection() => 'Project Details',
    };

    return Material(
      elevation: 8,
      shadowColor: Colors.black26,
      color: chrome.body,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: chrome.header,
              elevation: 0,
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        slideTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: chrome.onHeader.withValues(alpha: 0.6),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        subtaskOverlay || !hasOverlay
                            ? Icons.close
                            : Icons.arrow_back,
                        color: chrome.onHeader,
                      ),
                      tooltip: subtaskOverlay || !hasOverlay ? 'Close' : 'Back',
                      onPressed: _handleClose,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: chrome.footerBorder),
            Expanded(
              child: baseTaskId != null
                  ? _TaskWithOverlayStack(
                      taskPanelKey: _taskPanelKey(baseTaskId),
                      taskId: baseTaskId,
                      palette: widget.palette,
                      detailRefreshToken: widget.detailRefreshToken,
                      overlay: overlay,
                      onDismissAll: widget.onDismissAll,
                      onPop: widget.onPop,
                      onPushCreateSubtask: widget.onPushCreateSubtask,
                      onPushSubtask: widget.onPushSubtask,
                      onPushCreateTaskForProject:
                          widget.onPushCreateTaskForProject,
                      onPushTaskFromProject: widget.onPushTaskFromProject,
                      onTaskCreated: widget.onTaskCreated,
                      onProjectCreated: widget.onProjectCreated,
                      onProjectChanged: widget.onProjectChanged,
                      onSubtaskCreated: widget.onSubtaskCreated,
                      onSubtaskChanged: widget.onSubtaskChanged,
                    )
                  : AsanaDetailPanelHost(
                      selection: widget.stack.last,
                      palette: widget.palette,
                      onClose: _handleClose,
                      onPop: widget.onPop,
                      onPushCreateSubtask: widget.onPushCreateSubtask,
                      onPushSubtask: widget.onPushSubtask,
                      onPushCreateTaskForProject:
                          widget.onPushCreateTaskForProject,
                      onPushTaskFromProject: widget.onPushTaskFromProject,
                      onTaskCreated: widget.onTaskCreated,
                      onProjectCreated: widget.onProjectCreated,
                      onProjectChanged: widget.onProjectChanged,
                      onSubtaskCreated: widget.onSubtaskCreated,
                      onSubtaskChanged: widget.onSubtaskChanged,
                      detailRefreshToken: widget.detailRefreshToken,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Task detail always in the tree; optional sub-task layer on top (never replaces task).
class _TaskWithOverlayStack extends StatelessWidget {
  const _TaskWithOverlayStack({
    required this.taskPanelKey,
    required this.taskId,
    required this.palette,
    required this.detailRefreshToken,
    required this.overlay,
    required this.onDismissAll,
    required this.onPop,
    this.onPushCreateSubtask,
    this.onPushSubtask,
    this.onPushCreateTaskForProject,
    this.onPushTaskFromProject,
    this.onTaskCreated,
    this.onProjectCreated,
    this.onProjectChanged,
    this.onSubtaskCreated,
    this.onSubtaskChanged,
  });

  final GlobalKey taskPanelKey;
  final String taskId;
  final AsanaLandingPalette palette;
  final int detailRefreshToken;
  final AsanaDetailSelection? overlay;
  final VoidCallback onDismissAll;
  final VoidCallback onPop;
  final void Function(String parentTaskId)? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;
  final void Function(String projectId)? onPushCreateTaskForProject;
  final void Function(String taskId)? onPushTaskFromProject;
  final void Function(String taskId)? onTaskCreated;
  final void Function(String projectId)? onProjectCreated;
  final VoidCallback? onProjectChanged;
  final void Function(String parentTaskId, String subtaskId)? onSubtaskCreated;
  final VoidCallback? onSubtaskChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: AsanaTaskDetailPanel(
            key: taskPanelKey,
            taskId: taskId,
            palette: palette,
            refreshToken: detailRefreshToken,
            onClose: onDismissAll,
            onPushCreateSubtask: onPushCreateSubtask == null
                ? null
                : () => onPushCreateSubtask!(taskId),
            onPushSubtask: onPushSubtask,
          ),
        ),
        if (overlay != null)
          Positioned.fill(
            child: _DetailOverlayLayer(
              key: ValueKey(_overlayKey(overlay!)),
              selection: overlay!,
              palette: palette,
              onPop: onPop,
              onPushCreateSubtask: onPushCreateSubtask,
              onPushSubtask: onPushSubtask,
              onPushCreateTaskForProject: onPushCreateTaskForProject,
              onPushTaskFromProject: onPushTaskFromProject,
              onTaskCreated: onTaskCreated,
              onProjectCreated: onProjectCreated,
              onProjectChanged: onProjectChanged,
              onSubtaskCreated: onSubtaskCreated,
              onSubtaskChanged: onSubtaskChanged,
              detailRefreshToken: detailRefreshToken,
            ),
          ),
      ],
    );
  }

  static String _overlayKey(AsanaDetailSelection s) => switch (s) {
    AsanaSubtaskDetailSelection(:final subtaskId) => 'overlay-sub:$subtaskId',
    AsanaCreateSubtaskDetailSelection(:final parentTaskId) =>
      'overlay-create-sub:$parentTaskId',
    _ => 'overlay-other',
  };
}

class _DetailOverlayLayer extends StatefulWidget {
  const _DetailOverlayLayer({
    super.key,
    required this.selection,
    required this.palette,
    required this.onPop,
    this.onPushCreateSubtask,
    this.onPushSubtask,
    this.onPushCreateTaskForProject,
    this.onPushTaskFromProject,
    this.onTaskCreated,
    this.onProjectCreated,
    this.onProjectChanged,
    this.onSubtaskCreated,
    this.onSubtaskChanged,
    required this.detailRefreshToken,
  });

  final AsanaDetailSelection selection;
  final AsanaLandingPalette palette;
  final VoidCallback onPop;
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
  State<_DetailOverlayLayer> createState() => _DetailOverlayLayerState();
}

class _DetailOverlayLayerState extends State<_DetailOverlayLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(widget.palette);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic)),
      child: Material(
        color: chrome.body,
        elevation: 2,
        shadowColor: Colors.black26,
        child: AsanaDetailPanelHost(
          selection: widget.selection,
          palette: widget.palette,
          onClose: widget.onPop,
          onPop: widget.onPop,
          onPushCreateSubtask: widget.onPushCreateSubtask,
          onPushSubtask: widget.onPushSubtask,
          onPushCreateTaskForProject: widget.onPushCreateTaskForProject,
          onPushTaskFromProject: widget.onPushTaskFromProject,
          onTaskCreated: widget.onTaskCreated,
          onProjectCreated: widget.onProjectCreated,
          onProjectChanged: widget.onProjectChanged,
          onSubtaskCreated: widget.onSubtaskCreated,
          onSubtaskChanged: widget.onSubtaskChanged,
          detailRefreshToken: widget.detailRefreshToken,
        ),
      ),
    );
  }
}
