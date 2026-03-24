import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../models/staff_for_assignment.dart';
import '../priority.dart';
import '../services/supabase_service.dart';
import '../utils/copyable_snackbar.dart';

/// Inserts one row into Supabase `task`. Assignee slots use **`staff.id`** (uuid strings).
class CreateSupabaseTaskScreen extends StatefulWidget {
  const CreateSupabaseTaskScreen({super.key});

  @override
  State<CreateSupabaseTaskScreen> createState() =>
      _CreateSupabaseTaskScreenState();
}

class _CreateSupabaseTaskScreenState extends State<CreateSupabaseTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _taskNameController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();

  List<StaffListRow> _allStaff = [];
  bool _loadingStaff = true;
  final Set<String> _selectedStaffIds = {};

  int _priority = 1;
  DateTime? _startDate;
  DateTime? _dueDate;
  bool _active = true;
  bool _submitting = false;

  static const int _maxAssignees = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStaff());
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _loadStaff() async {
    if (!SupabaseConfig.isConfigured) {
      setState(() {
        _loadingStaff = false;
        _allStaff = [];
      });
      return;
    }
    setState(() => _loadingStaff = true);
    final rows = await SupabaseService.fetchStaffListForTaskPicker();
    if (!mounted) return;
    setState(() {
      _allStaff = rows;
      _loadingStaff = false;
    });
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<StaffListRow> get _filteredStaff {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _allStaff;
    return _allStaff
        .where((s) => s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q))
        .toList();
  }

  void _toggleStaff(String id, bool selected) {
    if (selected &&
        _selectedStaffIds.length >= _maxAssignees &&
        !_selectedStaffIds.contains(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('At most $_maxAssignees assignees (staff.id).'),
        ),
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

  /// First 10 selected ids, stable order by name.
  List<String?> _assigneeIdsForInsert() {
    final selected = _allStaff.where((s) => _selectedStaffIds.contains(s.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final ids = selected.take(_maxAssignees).map((s) => s.id).toList();
    final out = <String?>[];
    for (var i = 0; i < _maxAssignees; i++) {
      out.add(i < ids.length ? ids[i] : null);
    }
    return out;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(
        context,
        'Supabase is not configured.',
        duration: const Duration(seconds: 6),
      );
      return;
    }
    setState(() => _submitting = true);
    final assignees = _assigneeIdsForInsert();
    final err = await SupabaseService.insertTaskTableRow(
      taskName: _taskNameController.text.trim(),
      assignees: assignees,
      priority: priorityToDisplayName(_priority),
      startDate: _startDate,
      dueDate: _dueDate,
      description: _descController.text.trim().isEmpty
          ? null
          : _descController.text.trim(),
      active: _active ? 1 : 0,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (err != null) {
      showCopyableSnackBar(
        context,
        err,
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 12),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Task row inserted into Supabase.'),
        backgroundColor: Colors.green,
      ),
    );
    _taskNameController.clear();
    _descController.clear();
    _searchController.clear();
    setState(() {
      _selectedStaffIds.clear();
      _priority = 1;
      _startDate = null;
      _dueDate = null;
      _active = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRows = _allStaff.where((s) => _selectedStaffIds.contains(s.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create task (Supabase)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!SupabaseConfig.isConfigured)
                Card(
                  color: Colors.amber.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Supabase URL/key not set — insert will fail until configured.',
                      style: TextStyle(color: Colors.amber.shade900),
                    ),
                  ),
                ),
              TextFormField(
                controller: _taskNameController,
                decoration: const InputDecoration(
                  labelText: 'Task name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Assignees (optional, up to $_maxAssignees) — stores staff.id',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (_loadingStaff)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_allStaff.isEmpty)
                Text(
                  'No staff rows returned from Supabase (check RLS on staff, or add data).',
                  style: TextStyle(color: Colors.orange.shade800),
                )
              else ...[
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search staff',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_filteredStaff.length} shown · ${_selectedStaffIds.length} selected',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListView.builder(
                      itemCount: _filteredStaff.length,
                      itemBuilder: (context, i) {
                        final s = _filteredStaff[i];
                        final checked = _selectedStaffIds.contains(s.id);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          onChanged: (v) => _toggleStaff(s.id, v ?? false),
                          title: Text(s.name),
                          subtitle: Text(
                            s.id,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (selectedRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Selected (order → assignee_01 …)', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: selectedRows.take(_maxAssignees).map((s) {
                      return InputChip(
                        label: Text(s.name),
                        onDeleted: () => _toggleStaff(s.id, false),
                      );
                    }).toList(),
                  ),
                ],
              ],
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
              const Text('Start date', style: TextStyle(fontWeight: FontWeight.w500)),
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
                        initialDate: _dueDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 5)),
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
              const SizedBox(height: 8),
              const Text('Due date', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _dueDate != null
                        ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                        : 'Not set',
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? _dueDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (d != null) setState(() => _dueDate = d);
                    },
                    icon: const Icon(Icons.calendar_today),
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
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Off = deleted / inactive (0)'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(_submitting ? 'Saving…' : 'Create task'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
