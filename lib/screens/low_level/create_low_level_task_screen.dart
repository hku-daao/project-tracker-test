import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/task.dart';
import '../../models/team.dart';
import '../../priority.dart';
import '../../config/supabase_config.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';

/// Low-level view: Directors assign tasks to Responsible Officers (Planner-style).
class CreateLowLevelTaskScreen extends StatefulWidget {
  const CreateLowLevelTaskScreen({super.key});

  @override
  State<CreateLowLevelTaskScreen> createState() =>
      _CreateLowLevelTaskScreenState();
}

class _CreateLowLevelTaskScreenState extends State<CreateLowLevelTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentsController = TextEditingController();
  String? _selectedTeamId;
  final Set<String> _selectedOfficerIds = {};
  int _priority = 1; // 1 = Standard, 2 = Urgent
  TaskStatus _status = TaskStatus.todo;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  List<dynamic> _officersForSelectedTeam() {
    if (_selectedTeamId == null) return [];
    return context.read<AppState>().getOfficersForTeam(_selectedTeamId!);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a team first')),
      );
      return;
    }
    final officers = _officersForSelectedTeam();
    if (officers.isEmpty && _selectedOfficerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'No Responsible Officers for this team yet (to be provided). Add team officers in app state.')),
      );
      return;
    }
    if (_selectedOfficerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one Responsible Officer')),
      );
      return;
    }
    final teamId = _selectedTeamId!;
    final assigneeIds = _selectedOfficerIds.toList();
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    final priority = _priority;
    final status = _status;
    final start = _startDate;
    final end = _endDate;

    final id = context.read<AppState>().addTask(
          name: name,
          description: description,
          assigneeIds: assigneeIds,
          priority: priority,
          teamId: teamId,
          status: status,
          startDate: start,
          endDate: end,
        );
    _nameController.clear();
    _descController.clear();
    _commentsController.clear();
    setState(() {
      _selectedTeamId = null;
      _selectedOfficerIds.clear();
      _priority = 1;
      _status = TaskStatus.todo;
      _startDate = null;
      _endDate = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task created')),
    );
    if (SupabaseConfig.isConfigured) {
      final err = await SupabaseService.insertTask(
        taskId: id,
        teamId: teamId,
        assigneeIds: assigneeIds,
        name: name,
        description: description,
        priority: priority,
        status: status,
        startDate: start,
        endDate: end,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(
          context,
          'Supabase: $err',
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 12),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task synced to Supabase'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final officers = _officersForSelectedTeam();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String?>(
              value: _selectedTeamId,
              decoration: const InputDecoration(
                labelText: 'Team',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Select team'),
                ),
                ...context.watch<AppState>().teams.map(
                  (Team t) => DropdownMenuItem<String?>(
                    value: t.id,
                    child: Text(t.name),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _selectedTeamId = v;
                _selectedOfficerIds.clear();
              }),
            ),
            const SizedBox(height: 16),
            const Text('Responsible Officers (multiple)',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            if (_selectedTeamId == null)
              const Text('Select a team first',
                  style: TextStyle(color: Colors.grey))
            else if (officers.isEmpty)
              const Text(
                'No officers for this team (to be provided later).',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 8,
                children: officers.map((a) {
                  final selected = _selectedOfficerIds.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedOfficerIds.add(a.id);
                        } else {
                          _selectedOfficerIds.remove(a.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Task',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Priority', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: priorityOptions.map((p) {
                final selected = _priority == p;
                return FilterChip(
                  label: Text(priorityToDisplayName(p)),
                  selected: selected,
                  onSelected: (v) => setState(() => _priority = p),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Status', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TaskStatus.values.map((s) {
                final selected = _status == s;
                return FilterChip(
                  label: Text(taskStatusDisplayNames[s]!),
                  selected: selected,
                  onSelected: (v) => setState(() => _status = s),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('Start Date',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _startDate != null
                      ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate:
                          _endDate ?? DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _startDate = d);
                  },
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
            const SizedBox(height: 12),
            const Text('Due Date',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _endDate != null
                      ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                      : 'Not set',
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate:
                          _startDate ?? _endDate ?? DateTime.now(),
                      firstDate: _startDate ?? DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _endDate = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick'),
                ),
                if (_endDate != null)
                  TextButton(
                    onPressed: () => setState(() => _endDate = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _commentsController,
              decoration: const InputDecoration(
                labelText: 'Updates/ Comments',
                hintText: 'Add an update/ comment…',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Create Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
