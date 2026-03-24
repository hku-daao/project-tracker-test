import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../config/supabase_config.dart';
import '../models/task.dart';
import '../models/comment.dart';
import '../models/staff_for_assignment.dart';
import '../priority.dart';
import '../services/supabase_service.dart';
import '../utils/copyable_snackbar.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  final String? commentAuthorAssigneeId;

  const TaskDetailScreen({super.key, required this.taskId, this.commentAuthorAssigneeId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
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
    if (task.isSingularTableRow) {
      return SingularTaskDetailView(
        taskId: widget.taskId,
        commentAuthorAssigneeId: widget.commentAuthorAssigneeId,
      );
    }
    return _LegacyTaskDetailView(
      taskId: widget.taskId,
      commentAuthorAssigneeId: widget.commentAuthorAssigneeId,
    );
  }
}

/// Supabase singular [`task`] row: editable fields, status actions, comments, Update.
class SingularTaskDetailView extends StatefulWidget {
  final String taskId;
  final String? commentAuthorAssigneeId;

  const SingularTaskDetailView({
    super.key,
    required this.taskId,
    this.commentAuthorAssigneeId,
  });

  @override
  State<SingularTaskDetailView> createState() => _SingularTaskDetailViewState();
}

class _SingularTaskDetailViewState extends State<SingularTaskDetailView> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentController = TextEditingController();

  DateTime? _startDate;
  DateTime? _dueDate;
  int _localPriority = 1;
  String _localStatus = 'Incomplete';
  final Set<String> _selectedStaffIds = {};
  List<StaffListRow> _allStaff = [];
  bool _loadingStaff = true;
  bool _loadedForm = false;
  bool _saving = false;

  static const int _maxAssignees = 10;
  static const Color _selGreen = Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      _ensureLoaded(state);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  /// [stored] is `task.update_date` from DB; display adds +8h (Hong Kong offset).
  String _lastUpdatedLine(DateTime? stored) {
    if (stored == null) return 'Last updated: —';
    final shown = stored.add(const Duration(hours: 8));
    return 'Last updated: ${DateFormat.yMMMd().add_Hm().format(shown)}';
  }

  static int _dateOnlyCompare(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return da.compareTo(db);
  }

  String _normalizeLocalStatus(String? db) {
    if (db == null || db.trim().isEmpty) return 'Incomplete';
    final l = db.trim().toLowerCase();
    if (l == 'complete' || l == 'completed') return 'Completed';
    if (l == 'incomplete') return 'Incomplete';
    if (l == 'delete' || l == 'deleted') return 'Deleted';
    return 'Incomplete';
  }

  TaskStatus _mapLocalStatusToEnum(String s) {
    return s == 'Completed' ? TaskStatus.done : TaskStatus.todo;
  }

  int _priorityFromRow(dynamic p) {
    if (p is num) return p.toInt().clamp(1, 2);
    final s = p?.toString().trim().toLowerCase() ?? '';
    if (s.contains('urgent') || s == '2') return 2;
    return 1;
  }

  Widget _toggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: selected ? _selGreen : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _selGreen, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _ensureLoaded(AppState state) async {
    final task = state.taskById(widget.taskId);
    if (task == null) return;

    if (!_loadedForm) {
      _nameController.text = task.name;
      _descController.text = task.description;
      _startDate = task.startDate;
      _dueDate = task.endDate;
      _localPriority = task.priority.clamp(1, 2);
      _localStatus = _normalizeLocalStatus(task.dbStatus);
    }

    if (!SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _loadingStaff = false;
          _loadedForm = true;
        });
      }
      return;
    }

    if (_loadedForm) return;

    final staff = await SupabaseService.fetchStaffListForTaskPicker();
    final row = await SupabaseService.fetchSingularTaskById(widget.taskId);
    final selected = <String>{};
    if (row != null) {
      for (var i = 1; i <= 10; i++) {
        final key = 'assignee_${i.toString().padLeft(2, '0')}';
        final raw = row[key];
        if (raw != null && raw.toString().trim().isNotEmpty) {
          selected.add(raw.toString().trim());
        }
      }
    } else {
      for (final id in task.assigneeIds) {
        final slots = await SupabaseService.assigneeSlotsForTask([id]);
        final first = slots.isNotEmpty ? slots[0] : null;
        if (first != null && first.isNotEmpty) selected.add(first);
      }
    }

    if (!mounted) return;
    setState(() {
      _allStaff = staff;
      _selectedStaffIds.clear();
      _selectedStaffIds.addAll(selected);
      if (row != null) {
        _localPriority = _priorityFromRow(row['priority']);
        _localStatus = _normalizeLocalStatus(row['status']?.toString());
      }
      _loadingStaff = false;
      _loadedForm = true;
    });
  }

  Future<void> _saveTaskFields(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured.');
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _dateOnlyCompare(_startDate!, _dueDate!) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date cannot be after due date.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final keys = _allStaff.where((s) => _selectedStaffIds.contains(s.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final keyList = keys.take(_maxAssignees).map((s) => s.id).toList();
    final slots = await SupabaseService.assigneeSlotsForTask(keyList);
    final assigneeIdsForState = <String>[];
    for (final s in keys.take(_maxAssignees)) {
      assigneeIdsForState.add(await SupabaseService.assigneeListKeyFromStaffUuid(s.id));
    }

    final priorityLabel = priorityToDisplayName(_localPriority);
    final statusForDb = _localStatus;

    setState(() => _saving = true);
    final err = await SupabaseService.updateSingularTaskRow(
      taskId: task.id,
      taskName: _nameController.text.trim(),
      description: _descController.text.trim(),
      priority: priorityLabel,
      assigneeSlots: slots,
      startDate: _startDate,
      dueDate: _dueDate,
      clearStartDate: _startDate == null,
      clearDueDate: _dueDate == null,
      status: statusForDb,
      updateByStaffLookupKey: state.userStaffAppId,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (err != null) {
      showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
      return;
    }

    final commentBody = _commentController.text.trim();
    if (commentBody.isNotEmpty) {
      final cErr = await SupabaseService.insertSingularCommentRow(
        taskId: task.id,
        description: commentBody,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (cErr != null) {
        showCopyableSnackBar(
          context,
          'Task updated, but comment was not saved: $cErr',
          backgroundColor: Colors.orange,
        );
      } else {
        _commentController.clear();
      }
    }

    final lk = state.userStaffAppId?.trim();
    String? updaterName;
    if (lk != null && lk.isNotEmpty) {
      updaterName = state.assigneeById(lk)?.name ??
          await SupabaseService.staffDisplayNameForKey(lk);
    }
    if (!mounted) return;

    state.replaceTask(
      task.copyWith(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        assigneeIds: assigneeIdsForState,
        priority: _localPriority,
        startDate: _startDate,
        endDate: _dueDate,
        dbStatus: statusForDb,
        status: _mapLocalStatusToEnum(statusForDb),
        updateByStaffName: updaterName,
        updateDate: DateTime.now(),
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task updated'), backgroundColor: Colors.green),
    );
  }

  void _toggleStaff(String id, bool selected) {
    if (selected &&
        _selectedStaffIds.length >= _maxAssignees &&
        !_selectedStaffIds.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('At most $_maxAssignees assignees.')),
      );
      return;
    }
    setState(() {
      if (selected) {
        _selectedStaffIds.add(id);
      } else {
        _selectedStaffIds.remove(id);
      }
    });
  }

  Future<void> _pickStartDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate ?? _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (d == null || !mounted) return;
    if (_dueDate != null && _dateOnlyCompare(d, _dueDate!) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start date cannot be after due date.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _startDate = d);
  }

  Future<void> _pickDueDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (d == null || !mounted) return;
    if (_startDate != null && _dateOnlyCompare(_startDate!, d) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Due date cannot be before start date.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _dueDate = d);
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Task name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _descController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Assignees (up to $_maxAssignees)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingStaff)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ))
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _allStaff.map((s) {
                          final sel = _selectedStaffIds.contains(s.id);
                          return FilterChip(
                            label: Text(s.name),
                            selected: sel,
                            onSelected: (v) => _toggleStaff(s.id, v),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Priority',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _toggleButton(
                          label: 'Standard',
                          selected: _localPriority == 1,
                          onTap: () => setState(() => _localPriority = 1),
                        ),
                        const SizedBox(width: 12),
                        _toggleButton(
                          label: 'Urgent',
                          selected: _localPriority == 2,
                          onTap: () => setState(() => _localPriority = 2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _startDate == null
                                ? 'Start date: not set'
                                : 'Start: ${DateFormat.yMMMd().format(_startDate!)}',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pickStartDate,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Pick'),
                        ),
                        if (_startDate != null)
                          TextButton(
                            onPressed: () => setState(() => _startDate = null),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dueDate == null
                                ? 'Due date: not set'
                                : 'Due: ${DateFormat.yMMMd().format(_dueDate!)}',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pickDueDate,
                          icon: const Icon(Icons.event),
                          label: const Text('Pick'),
                        ),
                        if (_dueDate != null)
                          TextButton(
                            onPressed: () => setState(() => _dueDate = null),
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Text(
                      'Last updated by: ${task.updateByStaffName ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lastUpdatedLine(task.updateDate),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _toggleButton(
                          label: 'Completed',
                          selected: _localStatus == 'Completed',
                          onTap: () => setState(() => _localStatus = 'Completed'),
                        ),
                        const SizedBox(width: 8),
                        _toggleButton(
                          label: 'Incomplete',
                          selected: _localStatus == 'Incomplete',
                          onTap: () => setState(() => _localStatus = 'Incomplete'),
                        ),
                        const SizedBox(width: 8),
                        _toggleButton(
                          label: 'Deleted',
                          selected: _localStatus == 'Deleted',
                          onTap: () => setState(() => _localStatus = 'Deleted'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Comments',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Comments',
                hintText: 'Comments',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            ...task.comments.map((c) {
              final canEdit = DateTime.now().difference(c.createdAt) < const Duration(hours: 1);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(c.body),
                  subtitle: Text(
                    '${c.authorName} · ${DateFormat.yMMMd().add_Hm().format(c.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editComment(context, state, c),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteComment(context, state, c),
                              tooltip: 'Delete',
                            ),
                          ],
                        )
                      : null,
                ),
              );
            }),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : () => _saveTaskFields(state, task),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_saving ? 'Saving…' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _editComment(BuildContext context, AppState state, TaskComment c) {
    final controller = TextEditingController(text: c.body);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
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
        title: const Text('Delete comment'),
        content: const Text('Remove this comment?'),
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
}

/// Legacy [`tasks`] table row UI (Planner-style).
class _LegacyTaskDetailView extends StatefulWidget {
  final String taskId;
  final String? commentAuthorAssigneeId;

  const _LegacyTaskDetailView({
    required this.taskId,
    this.commentAuthorAssigneeId,
  });

  @override
  State<_LegacyTaskDetailView> createState() => _LegacyTaskDetailViewState();
}

class _LegacyTaskDetailViewState extends State<_LegacyTaskDetailView> {
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
              onPressed: () => _addComment(context, state, task),
              child: const Text('Post comment'),
            ),
            const SizedBox(height: 16),
            ...task.comments.map((c) {
              final canEdit = DateTime.now().difference(c.createdAt) < const Duration(hours: 1);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(c.body),
                  subtitle: Text(
                    '${c.authorName} · ${DateFormat.yMMMd().add_Hm().format(c.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editCommentLegacy(context, state, c),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteCommentLegacy(context, state, c),
                              tooltip: 'Delete',
                            ),
                          ],
                        )
                      : null,
                ),
              );
            }),
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
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Task deleted')));
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addComment(BuildContext context, AppState state, Task task) {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    if (task.assigneeIds.isEmpty) return;
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

  void _editCommentLegacy(BuildContext context, AppState state, TaskComment c) {
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

  void _deleteCommentLegacy(BuildContext context, AppState state, TaskComment c) {
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
