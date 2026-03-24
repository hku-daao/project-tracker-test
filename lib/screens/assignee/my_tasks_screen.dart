import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../app_state.dart';
import '../../models/task.dart';
import '../../models/initiative.dart';
import '../../models/deleted_record.dart';
import '../../priority.dart';
import '../task_detail_screen.dart';
import '../high_level/initiative_detail_screen.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  String _filterType = 'all'; // 'all', 'incomplete', 'completed', 'deleted'

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Get current user's staff_app_id from AppState
    final userStaffAppId = state.userStaffAppId;
    
    // If user has no staff_app_id, show message
    if (userStaffAppId == null || userStaffAppId.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No staff profile found. Please contact your administrator.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    
    // Filter initiatives and tasks where assigneeIds contains the user's staff_app_id
    final myInitiatives = state.initiatives.where((i) => i.directorIds.contains(userStaffAppId)).toList();
    final myTasks = state.tasks.where((t) => t.assigneeIds.contains(userStaffAppId)).toList();
    final deletedForAssignee = state.deletedTasks.where((r) => r.assigneeIds.contains(userStaffAppId)).toList();
    
    // Apply status filter
    List<Initiative> filteredInitiatives = [];
    List<Task> filteredTasks = [];
    List<DeletedTaskRecord> filteredDeleted = [];
    
    if (_filterType == 'all') {
      filteredInitiatives = myInitiatives;
      filteredTasks = myTasks;
      filteredDeleted = [];
    } else if (_filterType == 'incomplete') {
      filteredInitiatives = myInitiatives.where((i) => state.initiativeProgressPercent(i.id) < 100).toList();
      filteredTasks = myTasks.where((t) => t.status != TaskStatus.done).toList();
      filteredDeleted = [];
    } else if (_filterType == 'completed') {
      filteredInitiatives = myInitiatives.where((i) => state.initiativeProgressPercent(i.id) >= 100).toList();
      filteredTasks = myTasks.where((t) => t.status == TaskStatus.done).toList();
      filteredDeleted = [];
    } else if (_filterType == 'deleted') {
      filteredInitiatives = [];
      filteredTasks = [];
      filteredDeleted = deletedForAssignee;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'incomplete', label: Text('Incomplete')),
              ButtonSegment(value: 'completed', label: Text('Completed')),
              ButtonSegment(value: 'deleted', label: Text('Deleted')),
            ],
            selected: {_filterType},
            onSelectionChanged: (Set<String> selected) {
              setState(() => _filterType = selected.first);
            },
          ),
        ),
        Expanded(
          child: filteredInitiatives.isEmpty && filteredTasks.isEmpty && filteredDeleted.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No initiatives/ tasks assigned to you yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      children: [
                        if (filteredInitiatives.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              'Initiatives',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          ...filteredInitiatives.map((init) => _buildInitiativeCard(context, state, init)),
                        ],
                        if (filteredTasks.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: Text(
                              'Tasks',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          ...filteredTasks.map((t) => _buildTaskCard(context, t, userStaffAppId)),
                        ],
                        if (filteredDeleted.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 8),
                            child: Text(
                              'Deleted initiatives/ tasks (audit)',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                            ),
                          ),
                          ...filteredDeleted.map((r) => Card(
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
                ),
        ),
      ],
    );
  }

  Widget _buildInitiativeCard(BuildContext context, AppState state, Initiative init) {
    final progress = state.initiativeProgressPercent(init.id);
    final progressColor = _progressColor(progress);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(init.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${priorityToDisplayName(init.priority)} · $progress%'
              + (init.startDate != null
                  ? ' · Start ${DateFormat.yMMMd().format(init.startDate!)}'
                  : '')
              + (init.endDate != null
                  ? ' · Due ${DateFormat.yMMMd().format(init.endDate!)}'
                  : ''),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              backgroundColor: progressColor.withValues(alpha: 0.3),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => InitiativeDetailScreen(initiativeId: init.id),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Task t, String currentId) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(t.name),
        subtitle: Text(
          '${_statusLabel(t.status)}${t.endDate != null ? ' · Due ${DateFormat.yMMMd().format(t.endDate!)}' : ''}${t.isOverdue ? ' (${t.delayDays}d overdue)' : ''}',
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

  static Color _progressColor(int percent) {
    if (percent >= 100) return Colors.green;
    if (percent >= 50) return Color.lerp(Colors.yellow, Colors.green, (percent - 50) / 50)!;
    return Color.lerp(Colors.red, Colors.yellow, percent / 50)!;
  }
}
