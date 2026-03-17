import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/team.dart';
import '../../priority.dart';

class CreateInitiativeScreen extends StatefulWidget {
  const CreateInitiativeScreen({super.key});

  @override
  State<CreateInitiativeScreen> createState() => _CreateInitiativeScreenState();
}

class _CreateInitiativeScreenState extends State<CreateInitiativeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentsController = TextEditingController();
  String? _selectedTeamId;
  final Set<String> _selectedDirectorIds = {};
  int _priority = 1; // 1 = Standard, 2 = Urgent
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  List<dynamic> _directorsForSelectedTeam() {
    if (_selectedTeamId == null) return [];
    return context.read<AppState>().getDirectorsForTeam(_selectedTeamId!);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTeamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a team')),
      );
      return;
    }
    if (_selectedDirectorIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one Director')),
      );
      return;
    }
    final state = context.read<AppState>();
    state.addInitiative(
          teamId: _selectedTeamId!,
          directorIds: _selectedDirectorIds.toList(),
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          priority: _priority,
          startDate: _startDate,
          endDate: _endDate,
        );
    final commentText = _commentsController.text.trim();
    if (commentText.isNotEmpty && state.initiatives.isNotEmpty) {
      final lastInit = state.initiatives.last;
      final authorId = lastInit.directorIds.isNotEmpty ? lastInit.directorIds.first : state.assignees.first.id;
      final author = state.assigneeById(authorId);
      state.addComment(taskId: lastInit.id, authorId: authorId, authorName: author?.name ?? authorId, body: commentText);
    }
    _nameController.clear();
    _descController.clear();
    _commentsController.clear();
    setState(() {
      _selectedTeamId = null;
      _selectedDirectorIds.clear();
      _priority = 1;
      _startDate = null;
      _endDate = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Initiative created')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final directors = _directorsForSelectedTeam();

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
                ...AppState.teams.map(
                  (Team t) => DropdownMenuItem<String?>(
                    value: t.id,
                    child: Text(t.name),
                  ),
                ),
              ],
              onChanged: (v) => setState(() {
                _selectedTeamId = v;
                _selectedDirectorIds.clear();
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Directors (multiple)',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            if (_selectedTeamId == null)
              const Text(
                'Select a team first',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 8,
                children: directors.map((a) {
                  final selected = _selectedDirectorIds.contains(a.id);
                  return FilterChip(
                    label: Text(a.name),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        if (v) {
                          _selectedDirectorIds.add(a.id);
                        } else {
                          _selectedDirectorIds.remove(a.id);
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
            const Text('Start Date', style: TextStyle(fontWeight: FontWeight.w500)),
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
                      lastDate: _endDate ?? DateTime.now().add(const Duration(days: 365 * 3)),
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
            const Text('Due Date', style: TextStyle(fontWeight: FontWeight.w500)),
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
                      initialDate: _startDate ?? _endDate ?? DateTime.now(),
                      firstDate: _startDate ?? DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
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
                labelText: 'Comments',
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
                child: Text('Create Initiative'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
