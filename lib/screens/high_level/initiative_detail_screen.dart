import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/comment.dart';
import '../../models/initiative.dart';
import '../../models/sub_task.dart';
import '../../priority.dart';

class InitiativeDetailScreen extends StatefulWidget {
  final String initiativeId;

  const InitiativeDetailScreen({super.key, required this.initiativeId});

  @override
  State<InitiativeDetailScreen> createState() => _InitiativeDetailScreenState();
}

class _InitiativeDetailScreenState extends State<InitiativeDetailScreen> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final init = state.initiativeById(widget.initiativeId);
    if (init == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Initiative')),
        body: const Center(child: Text('Initiative not found')),
      );
    }
    final comments = state.commentsForTaskOrInitiative(init.id);
    final subTasks = state.subTasksForInitiative(init.id);
    final deletedSubTasks = state.deletedSubTasksForInitiative(init.id);
    final progress = state.initiativeProgressPercent(init.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(init.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (init.description.isNotEmpty)
                      Text(
                        init.description,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    if (init.description.isNotEmpty) const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _Chip(label: priorityToDisplayName(init.priority)),
                        _Chip(
                          label: '$progress%',
                          backgroundColor: _progressColor(progress),
                        ),
                        if (init.startDate != null)
                          _Chip(
                              label:
                                  'Start ${DateFormat.yMMMd().format(init.startDate!)}'),
                        if (init.endDate != null)
                          _Chip(
                              label:
                                  'Due ${DateFormat.yMMMd().format(init.endDate!)}'),
                        ...init.directorIds.map((id) {
                          final a = state.assigneeById(id);
                          final isDirector = state.isDirector(id);
                          return _Chip(
                            label: a?.name ?? id,
                            backgroundColor: isDirector
                                ? Colors.lightBlue.shade100
                                : Colors.purple.shade100,
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Sub-tasks & progress',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 10,
              borderRadius: BorderRadius.circular(4),
              valueColor: AlwaysStoppedAnimation<Color>(_progressColor(progress)),
              backgroundColor: _progressColor(progress).withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text('$progress%',
                style: Theme.of(context).textTheme.titleMedium),
            if (subTasks.isEmpty) ...[
              const SizedBox(height: 8),
              progress >= 100
                  ? OutlinedButton.icon(
                      onPressed: () {
                        state.markInitiativeIncomplete(init.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Marked incomplete')),
                        );
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Mark incomplete'),
                    )
                  : FilledButton.icon(
                      onPressed: () {
                        state.markInitiativeComplete(init.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Marked as complete')),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Mark Initiative/ Task complete'),
                    ),
            ],
            if (subTasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...subTasks.map((s) => _SubTaskRow(
                    subTask: s,
                    onToggleCompleted: () => state.updateSubTaskCompleted(
                        s.id, !s.isCompleted),
                    onDelete: () => _confirmDeleteSubTask(
                        context, state, init, s),
                  )),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _showAddSubTask(context, state, init.id),
              icon: const Icon(Icons.add),
              label: const Text('Add sub-task'),
            ),
            if (deletedSubTasks.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Deleted sub-tasks (audit)',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              ...deletedSubTasks.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.grey.shade100,
                    child: ListTile(
                      title: Text(
                        r.subTask.label,
                        style: TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey.shade700),
                      ),
                      subtitle: Text(
                        'Deleted by ${r.deletedByName} · ${DateFormat.yMMMd().add_Hm().format(r.deletedAt)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 24),
            const Text('Updates/ Comments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Add an update/ comment…',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _addComment(context, state, init),
              icon: const Icon(Icons.add),
              label: const Text('Add update/ comment'),
            ),
            const SizedBox(height: 16),
            ...comments.map((c) => _CommentCard(
                  comment: c,
                  state: state,
                  onEdit: () => _editComment(context, state, c),
                  onDelete: () => _deleteComment(context, state, c),
                )),
          ],
        ),
      ),
    );
  }

  static Color _progressColor(int percent) {
    if (percent >= 100) return Colors.green;
    if (percent >= 50) return Color.lerp(Colors.yellow, Colors.green, (percent - 50) / 50)!;
    return Color.lerp(Colors.red, Colors.yellow, percent / 50)!;
  }

  void _addComment(
      BuildContext context, AppState state, Initiative init) {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    // Attribute to the logged-in user (from /api/me), not the first director.
    final userId = state.userStaffAppId;
    final String authorId;
    final String authorName;
    if (userId != null && userId.isNotEmpty) {
      authorId = userId;
      authorName = state.assigneeById(userId)?.name ?? userId;
    } else {
      authorId = init.directorIds.isNotEmpty
          ? init.directorIds.first
          : state.assignees.first.id;
      final author = state.assigneeById(authorId);
      authorName = author?.name ?? authorId;
    }
    state.addComment(
      taskId: init.id,
      authorId: authorId,
      authorName: authorName,
      body: body,
    );
    _commentController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update/ comment added')));
  }

  void _editComment(BuildContext context, AppState state, TaskComment c) {
    final controller = TextEditingController(text: c.body);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit update/ comment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newBody = controller.text.trim();
              if (newBody.isNotEmpty) state.updateComment(c.id, newBody);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteComment(BuildContext context, AppState state, TaskComment c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete update/ comment'),
        content: const Text('Remove this update/ comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              state.deleteComment(c.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddSubTask(
      BuildContext context, AppState state, String initiativeId) {
    final labelController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add sub-task'),
        content: TextField(
          controller: labelController,
          decoration: const InputDecoration(labelText: 'Sub-task name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (labelController.text.trim().isEmpty) return;
              final err = await state.addSubTask(
                initiativeId: initiativeId,
                label: labelController.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!context.mounted) return;
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Sub-task kept locally only. Cloud: $err',
                    ),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 10),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sub-task added')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubTask(
      BuildContext context, AppState state, Initiative init, SubTask subTask) {
    final directorName = init.directorIds.isNotEmpty
        ? (state.assigneeById(init.directorIds.first)?.name ?? 'Director')
        : 'Director';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete sub-task'),
        content: Text(
            'Delete "${subTask.label}"? It will be moved to the deleted sub-tasks audit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              state.deleteSubTask(subTask.id, directorName);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sub-task deleted')));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _SubTaskRow extends StatelessWidget {
  final SubTask subTask;
  final VoidCallback onToggleCompleted;
  final VoidCallback onDelete;

  const _SubTaskRow({
    required this.subTask,
    required this.onToggleCompleted,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Checkbox(
            value: subTask.isCompleted,
            onChanged: (_) => onToggleCompleted(),
          ),
          Expanded(
            child: Text(
              subTask.label,
              style: TextStyle(
                decoration: subTask.isCompleted
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
            tooltip: 'Delete sub-task',
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? backgroundColor;

  const _Chip({required this.label, this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: backgroundColor,
    );
  }
}

class _CommentCard extends StatelessWidget {
  final TaskComment comment;
  final AppState state;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CommentCard({
    required this.comment,
    required this.state,
    required this.onEdit,
    required this.onDelete,
  });

  static const Duration _editWindow = Duration(hours: 1);

  @override
  Widget build(BuildContext context) {
    final canEdit = DateTime.now().difference(comment.createdAt) < _editWindow;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(comment.body),
        subtitle: Text(
          '${comment.authorName} · ${DateFormat.yMMMd().add_Hm().format(comment.createdAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: canEdit
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit,
                    tooltip: 'Edit',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                    tooltip: 'Delete',
                  ),
                ],
              )
            : null,
      ),
    );
  }
}
