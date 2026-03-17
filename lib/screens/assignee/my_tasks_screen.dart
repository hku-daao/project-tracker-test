import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/task.dart';
import '../task_detail_screen.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  String? _selectedAssigneeId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final assignees = List.from(state.assignees)..sort((a, b) => a.name.compareTo(b.name));
    final currentId = _selectedAssigneeId ?? assignees.first.id;
    final myTasks = state.tasksForAssignee(currentId);
    final incomplete = myTasks.where((t) => t.status != TaskStatus.done).toList();
    final completed = myTasks.where((t) => t.status == TaskStatus.done).toList();
    final deletedForAssignee = state.deletedTasksForAssignee(currentId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            value: currentId,
            decoration: const InputDecoration(
              labelText: 'View as assignee',
              border: OutlineInputBorder(),
            ),
            items: assignees
                .map<DropdownMenuItem<String>>((a) => DropdownMenuItem<String>(value: a.id, child: Text(a.name)))
                .toList(),
            onChanged: (v) => setState(() => _selectedAssigneeId = v),
          ),
        ),
        Expanded(
          child: myTasks.isEmpty && deletedForAssignee.isEmpty
              ? const Center(
                  child: Text('No tasks assigned. Switch assignee or wait for assignments.'),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (incomplete.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          'Incomplete tasks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      ...incomplete.map((t) => _buildTaskCard(context, t, currentId)),
                    ],
                    if (completed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                          'Completed tasks',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                      ...completed.map((t) => _buildTaskCard(context, t, currentId)),
                    ],
                    if (deletedForAssignee.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 24, bottom: 8),
                        child: Text(
                          'Deleted tasks (audit)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                        ),
                      ),
                      ...deletedForAssignee.map((r) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: Colors.grey.shade100,
                            child: ListTile(
                              title: Text(
                                r.taskName,
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
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(BuildContext context, Task t, String currentId) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(t.name),
        subtitle: Text(
          '${_statusLabel(t.status)}'
          + (t.dueDate != null
              ? ' · Due ${DateFormat.yMMMd().format(t.dueDate!)}'
              : '')
          + (t.isOverdue ? ' (${t.delayDays}d overdue)' : ''),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(
              taskId: t.id,
              commentAuthorAssigneeId: currentId,
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(TaskStatus s) {
    return taskStatusDisplayNames[s] ?? 'Unknown';
  }
}
