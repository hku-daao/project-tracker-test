import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
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
                        _Chip(label: '$progress%'),
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
                          return _Chip(label: a?.name ?? id);
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
            ),
            const SizedBox(height: 8),
            Text('$progress%',
                style: Theme.of(context).textTheme.titleMedium),
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
            const Text('Comments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Add a comment...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _addComment(context, state, init),
              child: const Text('Post comment'),
            ),
            const SizedBox(height: 16),
            ...comments.map((c) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(c.body),
                    subtitle: Text(
                      '${c.authorName} · ${DateFormat.yMMMd().add_Hm().format(c.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _addComment(
      BuildContext context, AppState state, Initiative init) {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    final authorId = init.directorIds.isNotEmpty
        ? init.directorIds.first
        : state.assignees.first.id;
    final author = state.assigneeById(authorId);
    state.addComment(
      taskId: init.id,
      authorId: authorId,
      authorName: author?.name ?? authorId,
      body: body,
    );
    _commentController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment added')));
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
            onPressed: () {
              if (labelController.text.trim().isEmpty) return;
              state.addSubTask(
                initiativeId: initiativeId,
                label: labelController.text.trim(),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sub-task added')));
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

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}
