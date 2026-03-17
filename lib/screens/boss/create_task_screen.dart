import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../priority.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final Set<String> _selectedAssigneeIds = {};
  int _priority = 1; // 1 = Standard, 2 = Urgent
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAssigneeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one assignee')),
      );
      return;
    }
    context.read<AppState>().addTask(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          assigneeIds: _selectedAssigneeIds.toList(),
          priority: _priority,
          startDate: _startDate,
          endDate: _endDate,
        );
    _nameController.clear();
    _descController.clear();
    setState(() {
      _selectedAssigneeIds.clear();
      _priority = 1;
      _startDate = null;
      _endDate = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task created')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final assignees = state.assignees;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Task name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            const Text('Assignees (multiple)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: assignees.map((a) {
                final selected = _selectedAssigneeIds.contains(a.id);
                return FilterChip(
                  label: Text(a.name),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      if (v) {
                        _selectedAssigneeIds.add(a.id);
                      } else {
                        _selectedAssigneeIds.remove(a.id);
                      }
                    });
                  },
                );
              }).toList(),
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
            const SizedBox(height: 8),
            const Text('Start date', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_startDate != null
                    ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                    : 'Not set'),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _endDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: _endDate ?? DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _startDate = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick start'),
                ),
                if (_startDate != null)
                  TextButton(
                    onPressed: () => setState(() => _startDate = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('End date', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_endDate != null
                    ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                    : 'Not set'),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? _endDate ?? DateTime.now(),
                      firstDate: _startDate ?? DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _endDate = d);
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick end'),
                ),
                if (_endDate != null)
                  TextButton(
                    onPressed: () => setState(() => _endDate = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submit,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Create task'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
