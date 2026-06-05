import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/staff_for_assignment.dart';
import 'asana_anchored_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

/// Live data for [showAsanaAssigneePicker] (load in background, panel opens instantly).
class AsanaAssigneePickerSnapshot {
  const AsanaAssigneePickerSnapshot({
    this.loading = false,
    this.teams = const [],
    this.staff = const [],
    this.projectStaff = const [],
    this.hasProjectTeam = false,
    this.error,
  });

  final bool loading;
  final List<TeamOptionRow> teams;
  final List<StaffForAssignment> staff;
  final List<StaffForAssignment> projectStaff;
  final bool hasProjectTeam;
  final String? error;

  bool get hasData => staff.isNotEmpty;
}

/// Assignee mini-panel anchored under the field (Asana slide styling only).
Future<void> showAsanaAssigneePicker({
  required LayerLink anchorLink,
  required BuildContext anchorContext,
  required ValueListenable<AsanaAssigneePickerSnapshot> snapshot,
  required Set<String> selectedIds,
  required ValueChanged<Set<String>> onSelectionChanged,
  VoidCallback? whenClosed,
}) {
  final media = MediaQuery.of(anchorContext);
  final panelWidth = asanaAnchoredFieldWidth(anchorContext);
  final box = anchorContext.findRenderObject() as RenderBox?;
  final topEstimate = box?.localToGlobal(Offset.zero).dy ?? 0;
  final maxPanelHeight =
      (media.size.height - topEstimate - 80).clamp(200.0, 520.0);

  return showAsanaAnchoredOverlay(
    anchorLink: anchorLink,
    anchorContext: anchorContext,
    panelWidth: panelWidth,
    whenClosed: whenClosed,
    builder: (ctx, close) {
      return _AssigneePickerOverlay(
          snapshot: snapshot,
          initialSelected: selectedIds,
          maxPanelHeight: maxPanelHeight,
          onSelectionChanged: onSelectionChanged,
          onDone: () {
            close();
          },
        );
    },
  );
}

class _AssigneePickerOverlay extends StatefulWidget {
  const _AssigneePickerOverlay({
    required this.snapshot,
    required this.initialSelected,
    required this.maxPanelHeight,
    required this.onSelectionChanged,
    required this.onDone,
  });

  final ValueListenable<AsanaAssigneePickerSnapshot> snapshot;
  final Set<String> initialSelected;
  final double maxPanelHeight;
  final ValueChanged<Set<String>> onSelectionChanged;
  final VoidCallback onDone;

  @override
  State<_AssigneePickerOverlay> createState() => _AssigneePickerOverlayState();
}

class _AssigneePickerOverlayState extends State<_AssigneePickerOverlay> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelected);
  }

  void _toggle(String id, bool checked) {
    setState(() {
      if (checked) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _finish() {
    widget.onSelectionChanged(Set<String>.from(_selected));
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AsanaAssigneePickerSnapshot>(
      valueListenable: widget.snapshot,
      builder: (context, snap, _) {
        return _AsanaPickerShell(
          maxHeight: widget.maxPanelHeight,
          child: _AsanaAssigneePickerBody(
            snapshot: snap,
            selectedIds: _selected,
            onToggle: _toggle,
            onDone: _finish,
          ),
        );
      },
    );
  }
}

class _AsanaPickerShell extends StatelessWidget {
  const _AsanaPickerShell({required this.maxHeight, required this.child});

  final double maxHeight;
  final Widget child;

  static const _border = Color(0xFFD1D5DB);
  static const _bg = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _AsanaAssigneePickerBody extends StatefulWidget {
  const _AsanaAssigneePickerBody({
    required this.snapshot,
    required this.selectedIds,
    required this.onToggle,
    required this.onDone,
  });

  final AsanaAssigneePickerSnapshot snapshot;
  final Set<String> selectedIds;
  final void Function(String assigneeId, bool checked) onToggle;
  final VoidCallback onDone;

  @override
  State<_AsanaAssigneePickerBody> createState() => _AsanaAssigneePickerBodyState();
}

class _AsanaAssigneePickerBodyState extends State<_AsanaAssigneePickerBody> {
  final _searchController = TextEditingController();
  String? _teamId;
  bool _teamListOpen = false;
  bool _projectTeamOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? _teamName(String? id) {
    if (id == null) return null;
    for (final t in widget.snapshot.teams) {
      if (t.teamId == id) return t.teamName;
    }
    return null;
  }

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  bool get _searching => _searchQuery.isNotEmpty;

  List<StaffForAssignment> get _visibleMembers {
    final q = _searchQuery;
    Iterable<StaffForAssignment> list = widget.snapshot.staff;
    if (q.isNotEmpty) {
      list = list.where((s) => s.name.toLowerCase().contains(q));
      if (_teamId != null && _teamId!.isNotEmpty) {
        list = list.where((s) => s.teamId == _teamId);
      }
    } else if (_teamId == null || _teamId!.isEmpty) {
      return const [];
    } else {
      list = list.where((s) => s.teamId == _teamId);
    }
    return list.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final teamChosen = _teamId != null && _teamId!.isNotEmpty;
    final selectedTeamName = teamChosen ? (_teamName(_teamId) ?? 'Selected Team') : '';
    final members = _visibleMembers;
    final selectedInView =
        members.where((s) => widget.selectedIds.contains(s.assigneeId)).length;
    final showMemberGrid = _searching || teamChosen;
    final projectMembers = List<StaffForAssignment>.from(snap.projectStaff)
      ..sort((a, b) => a.name.compareTo(b.name));
    final hasProjectTeam = snap.hasProjectTeam;
    final projectSelectedInView = projectMembers
        .where((s) => widget.selectedIds.contains(s.assigneeId))
        .length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (snap.loading && !snap.hasData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kAsanaTextSecondary,
                        ),
                      ),
                    ),
                  )
                else if (!snap.hasData)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      snap.error?.trim().isNotEmpty == true
                          ? snap.error!.trim()
                          : 'Teammate list unavailable',
                      style: asanaDetailValueStyle(context),
                    ),
                  )
                else ...[
                  _AsanaPickerSearchField(
                    controller: _searchController,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  _AsanaPickerTeamRow(
                    label: teamChosen
                        ? (_teamName(_teamId) ?? 'Team')
                        : 'Select Team',
                    open: _teamListOpen,
                    onTap: () => setState(() => _teamListOpen = !_teamListOpen),
                  ),
                  if (_teamListOpen) ...[
                    const SizedBox(height: 4),
                    _AsanaPickerTeamList(
                      teams: snap.teams,
                      selectedTeamId: _teamId,
                      onPick: (id) => setState(() {
                        _teamId = id;
                        _teamListOpen = false;
                      }),
                    ),
                  ],
                  if (!showMemberGrid) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Search by name or pick a team',
                      style: asanaDetailLabelStyle(context),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      members.isEmpty
                          ? 'No names match'
                          : '$selectedInView of ${members.length} selected from $selectedTeamName',
                      style: asanaDetailLabelStyle(context),
                    ),
                    const SizedBox(height: 6),
                    _AsanaPickerNameGrid(
                      members: members,
                      selectedIds: widget.selectedIds,
                      onToggle: widget.onToggle,
                    ),
                  ],
                  if (hasProjectTeam) ...[
                    const SizedBox(height: 8),
                    _AsanaPickerTeamRow(
                      label: 'Project Team',
                      open: _projectTeamOpen,
                      onTap: () => setState(
                        () => _projectTeamOpen = !_projectTeamOpen,
                      ),
                    ),
                    if (_projectTeamOpen) ...[
                      const SizedBox(height: 6),
                      if (projectMembers.isEmpty)
                        Text(
                          'No project assignees available',
                          style: asanaDetailLabelStyle(context),
                        )
                      else ...[
                        Text(
                          '$projectSelectedInView of ${projectMembers.length} selected from Project Team',
                          style: asanaDetailLabelStyle(context),
                        ),
                        const SizedBox(height: 6),
                        _AsanaPickerNameGrid(
                          members: projectMembers,
                          selectedIds: widget.selectedIds,
                          onToggle: widget.onToggle,
                        ),
                      ],
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDone,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Done',
                  style: asanaDetailValueStyle(
                    context,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AsanaPickerSearchField extends StatelessWidget {
  const _AsanaPickerSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFB0BEC5)),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: kAsanaTextSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: controller,
              style: asanaDetailValueStyle(context),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search name',
                hintStyle: asanaDetailValueStyle(context).copyWith(
                  color: kAsanaTextSecondary,
                  fontWeight: FontWeight.w400,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AsanaPickerTeamRow extends StatelessWidget {
  const _AsanaPickerTeamRow({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB0BEC5)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: asanaDetailValueStyle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18,
              color: kAsanaTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AsanaPickerTeamList extends StatelessWidget {
  const _AsanaPickerTeamList({
    required this.teams,
    required this.selectedTeamId,
    required this.onPick,
  });

  final List<TeamOptionRow> teams;
  final String? selectedTeamId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final sorted = List<TeamOptionRow>.from(teams)
      ..sort((a, b) => a.teamName.compareTo(b.teamName));

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(4),
        color: const Color(0xFFF9FAFB),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFE5E7EB)),
            InkWell(
              onTap: () => onPick(sorted[i].teamId),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                child: Text(
                  sorted[i].teamName,
                  style: asanaDetailValueStyle(
                    context,
                    weight: sorted[i].teamId == selectedTeamId
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Below this popup width, name checklist uses 2 columns instead of 3.
const double kAsanaAssigneeNameGridNarrowWidth = 320;

class _AsanaPickerNameGrid extends StatelessWidget {
  const _AsanaPickerNameGrid({
    required this.members,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<StaffForAssignment> members;
  final Set<String> selectedIds;
  final void Function(String assigneeId, bool checked) onToggle;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth < kAsanaAssigneeNameGridNarrowWidth
            ? 2
            : 3;
        final rows = <List<StaffForAssignment>>[];
        for (var i = 0; i < members.length; i += columnCount) {
          rows.add(
            members.sublist(
              i,
              i + columnCount > members.length ? members.length : i + columnCount,
            ),
          );
        }

        return Column(
          children: [
            for (final row in rows) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < columnCount; col++)
                    Expanded(
                      child: col < row.length
                          ? _AsanaPickerNameCell(
                              name: row[col].name,
                              selected: selectedIds.contains(
                                row[col].assigneeId,
                              ),
                              onTap: () => onToggle(
                                row[col].assigneeId,
                                !selectedIds.contains(row[col].assigneeId),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
              const SizedBox(height: 2),
            ],
          ],
        );
      },
    );
  }
}

class _AsanaPickerNameCell extends StatelessWidget {
  const _AsanaPickerNameCell({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
        child: Row(
          children: [
            _AsanaMiniCheck(selected: selected),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: asanaDetailValueStyle(
                  context,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AsanaMiniCheck extends StatelessWidget {
  const _AsanaMiniCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: selected ? kAsanaTextPrimary : Colors.white,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: selected ? kAsanaTextPrimary : const Color(0xFFB0BEC5),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 10, color: Colors.white)
          : null,
    );
  }
}
