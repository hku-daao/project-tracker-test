import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../models/task.dart';
import '../priority.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  /// When set (e.g. from My Tasks), comments are posted as this assignee.
  final String? commentAuthorAssigneeId;

  const TaskDetailScreen({super.key, required this.taskId, this.commentAuthorAssigneeId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final task = state.taskById(widget.taskId);
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('Task not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(task.name),
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
                    Text(
                      task.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _Chip(label: priorityToDisplayName(task.priority)),
                        if (task.teamId == null) _Chip(label: '${task.progressPercent}%'),
                        _Chip(
                          label: taskStatusDisplayNames[task.status] ?? 'Unknown',
                          color: _statusColor(task.status),
                        ),
                        if (task.startDate != null)
                          _Chip(label: 'Start ${DateFormat.yMMMd().format(task.startDate!)}'),
                        if (task.endDate != null)
                          _Chip(
                            label: 'End ${DateFormat.yMMMd().format(task.endDate!)}',
                            color: task.isOverdue ? Colors.red.shade100 : null,
                          ),
                        if (task.assigneeIds.isNotEmpty)
                          ...task.assigneeIds.map((id) {
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
            const Text('Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TaskStatus.values.map((s) {
                final selected = task.status == s;
                return FilterChip(
                  label: Text(taskStatusDisplayNames[s]!),
                  selected: selected,
                  onSelected: (_) => state.updateTaskStatus(widget.taskId, s),
                );
              }).toList(),
            ),
            if (task.teamId != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmDeleteTask(context, state, task),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete task'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (task.teamId == null) ...[
              const SizedBox(height: 16),
              const Text('Progress & milestones', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: task.progressPercent / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Slider(
                value: task.progressPercent.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${task.progressPercent}%',
                onChanged: (v) {
                  state.updateTaskProgress(widget.taskId, v.round());
                },
              ),
              if (task.milestones.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...task.milestones.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: m.progressPercent / 100,
                              backgroundColor: Colors.grey.shade300,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${m.label} ${m.progressPercent}%'),
                        ],
                      ),
                    )),
              ],
              ElevatedButton.icon(
                onPressed: () => _showAddMilestone(context, state),
                icon: const Icon(Icons.add),
                label: const Text('Add milestone'),
              ),
            ],
            const SizedBox(height: 24),
            const Text('Comments / progress updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Add a comment or progress update...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _addComment(context, state),
              child: const Text('Post comment'),
            ),
            const SizedBox(height: 16),
            ...task.comments.map((c) => Card(
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

  void _confirmDeleteTask(BuildContext context, AppState state, Task task) {
    final deletedByName = task.assigneeIds.isNotEmpty
        ? (state.assigneeById(task.assigneeIds.first)?.name ?? 'Responsible Officer')
        : 'Director';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task'),
        content: Text(
            'Delete "${task.name}"? It will be moved to the deleted tasks audit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              state.deleteTask(task.id, deletedByName);
              Navigator.pop(ctx);
              Navigator.pop(context); // back to task list
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task deleted')));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addComment(BuildContext context, AppState state) {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    final task = state.taskById(widget.taskId);
    if (task == null || task.assigneeIds.isEmpty) return;
    final authorId = widget.commentAuthorAssigneeId ?? task.assigneeIds.first;
    if (!task.assigneeIds.contains(authorId)) return;
    final author = state.assigneeById(authorId);
    state.addComment(
      taskId: widget.taskId,
      authorId: authorId,
      authorName: author?.name ?? authorId,
      body: body,
    );
    _commentController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment added')));
  }

  void _showAddMilestone(BuildContext context, AppState state) {
    final labelController = TextEditingController();
    int percent = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add milestone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 16),
              Text('Progress: $percent%'),
              Slider(
                value: percent.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (v) => setDialogState(() => percent = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (labelController.text.trim().isEmpty) return;
                state.addMilestone(
                  taskId: widget.taskId,
                  label: labelController.text.trim(),
                  progressPercent: percent,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Milestone added')));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Color? _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.todo:
        return Colors.grey.shade200;
      case TaskStatus.inProgress:
        return Colors.blue.shade100;
      case TaskStatus.done:
        return Colors.green.shade100;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;

  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color,
    );
  }
}
