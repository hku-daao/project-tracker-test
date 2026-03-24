import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/task.dart';
import '../../models/team.dart';
import '../../priority.dart';
import '../task_detail_screen.dart';

/// Low-level view: list tasks (Planner-style), filter by team.
class LowLevelTaskListScreen extends StatefulWidget {
  const LowLevelTaskListScreen({super.key});

  @override
  State<LowLevelTaskListScreen> createState() => _LowLevelTaskListScreenState();
}

class _LowLevelTaskListScreenState extends State<LowLevelTaskListScreen> {
  String? _selectedTeamId;
  bool _remindersExpanded = false;

  /// Sort key for ordering tasks by Responsible Officer name (ascending).
  String _assigneeSortKey(AppState state, Task t) {
    if (t.assigneeIds.isEmpty) return '';
    final names = t.assigneeIds
        .map((id) => state.assigneeById(id)?.name ?? id)
        .toList()
      ..sort();
    return names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tasks = state.tasksForTeam(_selectedTeamId);
    final incomplete = tasks.where((t) => t.status != TaskStatus.done).toList()
      ..sort((a, b) => _assigneeSortKey(state, a).compareTo(_assigneeSortKey(state, b)));
    final completed = tasks.where((t) => t.status == TaskStatus.done).toList()
      ..sort((a, b) => _assigneeSortKey(state, a).compareTo(_assigneeSortKey(state, b)));
    final deletedRecords = state.deletedTasksForTeam(_selectedTeamId);
    final reminders = state.getPendingReminders(_selectedTeamId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reminders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ExpansionTile(
              title: const Text('Reminders (would send to Directors)'),
              initiallyExpanded: _remindersExpanded,
              onExpansionChanged: (v) => setState(() => _remindersExpanded = v),
              children: reminders.map((r) => ListTile(
                title: Text(r.itemName),
                subtitle: Text(
                  '${r.reminderType} → ${r.recipientNames.join(", ")}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: DropdownButtonFormField<String?>(
            value: _selectedTeamId,
            decoration: const InputDecoration(
              labelText: 'Filter by team',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All tasks'),
              ),
              ...context.watch<AppState>().teams.map(
                (Team team) => DropdownMenuItem<String?>(
                  value: team.id,
                  child: Text(team.name),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedTeamId = v),
          ),
        ),
        Expanded(
          child: tasks.isEmpty && deletedRecords.isEmpty
              ? Center(
                  child: Text(
                    _selectedTeamId == null
                        ? 'No tasks yet. Create one in the "Create Task" tab.'
                        : 'No tasks for this team.',
                  ),
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
                      ...incomplete.map((t) => _buildTaskCard(context, state, t)),
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
                      ...completed.map((t) => _buildTaskCard(context, state, t)),
                    ],
                    if (deletedRecords.isNotEmpty) ...[
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
                      ...deletedRecords.map((r) => Card(
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

  Widget _buildTaskCard(BuildContext context, AppState state, Task t) {
    final officerNames = t.assigneeIds
        .map((id) => state.assigneeById(id)?.name ?? id)
        .toList()
      ..sort();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(t.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (officerNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Responsible Officer(s): ${officerNames.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            Text(
              '${priorityToDisplayName(t.priority)} · ${taskStatusDisplayNames[t.status]}'
                  + (t.startDate != null
                      ? ' · Start ${DateFormat.yMMMd().format(t.startDate!)}'
                      : '')
                  + (t.endDate != null
                      ? ' · Due ${DateFormat.yMMMd().format(t.endDate!)}'
                      : ''),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TaskDetailScreen(taskId: t.id),
          ),
        ),
      ),
    );
  }
}
