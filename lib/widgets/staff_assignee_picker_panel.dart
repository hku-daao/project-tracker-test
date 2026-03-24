import 'package:flutter/material.dart';

import '../models/staff_for_assignment.dart';

/// Filterable multi-select list: filter by [TeamOptionRow.teamName], search by [StaffForAssignment.name].
class StaffAssigneePickerPanel extends StatefulWidget {
  const StaffAssigneePickerPanel({
    super.key,
    required this.teams,
    required this.staff,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final List<TeamOptionRow> teams;
  final List<StaffForAssignment> staff;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;

  @override
  State<StaffAssigneePickerPanel> createState() => _StaffAssigneePickerPanelState();
}

class _StaffAssigneePickerPanelState extends State<StaffAssigneePickerPanel> {
  String? _filterTeamId;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<StaffForAssignment> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    return widget.staff.where((s) {
      if (_filterTeamId != null && _filterTeamId!.isNotEmpty) {
        if (s.teamId != _filterTeamId) return false;
      }
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String? _teamNameForId(String teamId) {
    for (final t in widget.teams) {
      if (t.teamId == teamId) return t.teamName;
    }
    return null;
  }

  void _toggle(String id, bool selected) {
    final next = Set<String>.from(widget.selectedIds);
    if (selected) {
      next.add(id);
    } else {
      next.remove(id);
    }
    widget.onSelectionChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedStaff = widget.staff
        .where((s) => widget.selectedIds.contains(s.assigneeId))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Assignees (multiple)',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Team',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _filterTeamId,
                        isExpanded: true,
                        hint: const Text('All teams'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('All teams'),
                          ),
                          ...widget.teams.map(
                            (t) => DropdownMenuItem<String?>(
                              value: t.teamId,
                              child: Text(
                                t.teamName.isNotEmpty ? t.teamName : t.teamId,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _filterTeamId = v),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search name',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_filtered.length} shown · ${widget.selectedIds.length} selected',
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
                child: _filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No staff match this filter.',
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final s = _filtered[i];
                          final checked = widget.selectedIds.contains(s.assigneeId);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            onChanged: (v) => _toggle(s.assigneeId, v ?? false),
                            title: Text(s.name),
                            subtitle: s.teamId != null && s.teamId!.isNotEmpty
                                ? Text(
                                    _teamNameForId(s.teamId!) ?? s.teamId!,
                                    style: theme.textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ),
            if (selectedStaff.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Selected',
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: selectedStaff
                    .map(
                      (s) => InputChip(
                        label: Text(s.name),
                        onDeleted: () => _toggle(s.assigneeId, false),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
