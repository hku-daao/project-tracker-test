import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/hk_time.dart';
import '../../utils/home_navigation.dart';
import '../../widgets/flow_navigation_bar.dart';
import '../../utils/project_task_sort.dart';
import '../../widgets/staff_assignee_picker_panel.dart';
import '../../widgets/task_list_card.dart';
import '../task_detail_screen.dart';
import 'create_task_screen.dart';

/// Detail for [`project`] — status chips, tasks under project, create task.
class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.projectId,
    this.openedFromLanding = true,
    this.openedFromOverview = false,
  });

  final String projectId;
  final bool openedFromLanding;
  final bool openedFromOverview;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  ProjectRecord? _project;
  List<Task> _tasks = [];
  bool _loading = true;
  String? _loadErr;
  bool _saving = false;

  ProjectDetailTaskSortColumn? _taskSortColumn;
  bool _taskSortAscending = true;

  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _pickerLoading = false;
  final Map<String, String> _staffAssigneeToTeamId = {};
  final Set<String> _editAssigneeIds = {};

  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _editStart;
  DateTime? _editEnd;

  /// Local status selection; persisted only when user taps **Update**.
  String? _draftStatus;

  String? _myStaffUuid;

  /// From [`staff.director`] for the logged-in user's staff row.
  bool _staffDirector = false;

  static const Color _kGreen = Color(0xFF298A00);
  static const Color _kBlue = Color(0xFF0B0094);
  static const Color _kGreySel = Color(0xFF424242);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadErr = null;
    });
    final state = context.read<AppState>();
    final mine = state.userStaffAppId?.trim();
    if (mine != null && mine.isNotEmpty) {
      _myStaffUuid =
          await SupabaseService.resolveStaffRowIdForAssigneeKey(mine);
    } else {
      _myStaffUuid = null;
    }
    var staffDirector = false;
    final sid = _myStaffUuid?.trim();
    if (sid != null && sid.isNotEmpty) {
      staffDirector = await SupabaseService.fetchStaffDirectorByStaffUuid(sid);
    }
    try {
      final p = await SupabaseService.fetchProjectById(widget.projectId);
      final tasks =
          await SupabaseService.fetchSingularTasksForProject(widget.projectId);
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _loading = false;
          _loadErr = 'Project not found';
          _staffDirector = false;
        });
        return;
      }
      _nameController.text = p.name;
      _descController.text = p.description;
      _editStart = p.startDate;
      _editEnd = p.endDate;
      _editAssigneeIds.clear();
      for (final u in p.assigneeStaffUuids) {
        final k = await SupabaseService.assigneeListKeyFromStaffUuid(u);
        _editAssigneeIds.add(k);
      }
      await _loadPickerIfNeeded();
      if (!mounted) return;
      setState(() {
        _project = p;
        _tasks = tasks;
        _draftStatus = null;
        _staffDirector = staffDirector;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadErr = e.toString();
        _staffDirector = false;
      });
    }
  }

  Future<void> _loadPickerIfNeeded() async {
    if (!SupabaseConfig.isConfigured || _pickerStaff.isNotEmpty) return;
    setState(() => _pickerLoading = true);
    try {
      final data = await SupabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      setState(() {
        _pickerLoading = false;
        if (data != null) {
          _pickerTeams = data.teams;
          _pickerStaff = data.staff;
          _staffAssigneeToTeamId.clear();
          for (final s in data.staff) {
            if (s.teamId != null && s.teamId!.isNotEmpty) {
              _staffAssigneeToTeamId[s.assigneeId] = s.teamId!;
            }
          }
        }
      });
    } catch (_) {
      if (mounted) setState(() => _pickerLoading = false);
    }
  }

  bool _isCreator(ProjectRecord p) {
    final cb = p.createByStaffUuid?.trim();
    final me = _myStaffUuid?.trim();
    if (cb == null || cb.isEmpty || me == null || me.isEmpty) return false;
    return cb == me;
  }

  bool _canDeleteProject(ProjectRecord p) =>
      _isCreator(p) || _staffDirector;

  bool _viewerIsProjectAssignee() {
    final mine = context.read<AppState>().userStaffAppId?.trim();
    if (mine == null || mine.isEmpty) return false;
    return _editAssigneeIds.contains(mine);
  }

  List<StaffForAssignment> _pickerStaffForRole() =>
      List<StaffForAssignment>.from(_pickerStaff);

  List<TeamOptionRow> _pickerTeamsForRole() {
    final staff = _pickerStaffForRole();
    final teamIds = staff
        .map((s) => s.teamId)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    if (teamIds.isEmpty) return List<TeamOptionRow>.from(_pickerTeams);
    return _pickerTeams.where((t) => teamIds.contains(t.teamId)).toList();
  }

  String _inferTeamId(List<String> assigneeAppIds) {
    if (assigneeAppIds.isEmpty) return '';
    final sorted = [...assigneeAppIds]..sort();
    for (final id in sorted) {
      final t = _staffAssigneeToTeamId[id];
      if (t != null && t.isNotEmpty) return t;
    }
    return '';
  }

  Future<void> _saveProject(AppState state, ProjectRecord p) async {
    if (!_isCreator(p)) return;
    if (_editAssigneeIds.isEmpty) {
      showCopyableSnackBar(context, 'Select at least one assignee',
          backgroundColor: Colors.orange);
      return;
    }
    final teamId = _inferTeamId(_editAssigneeIds.toList());
    if (teamId.isEmpty && SupabaseConfig.isConfigured) {
      showCopyableSnackBar(
        context,
        'Could not resolve team for assignees',
        backgroundColor: Colors.orange,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final slots =
          await SupabaseService.assigneeSlotsForTask(_editAssigneeIds.toList());
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        assigneeSlots: slots,
        startDate: _editStart,
        endDate: _editEnd,
        clearStartDate: _editStart == null,
        clearEndDate: _editEnd == null,
        status: _draftStatus ?? p.status,
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        final data = await SupabaseService.fetchTasksFromSupabase();
        if (data != null && mounted) state.applyTasksFromSupabase(data);
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      await _reload();
      if (mounted) {
        showCopyableSnackBar(context, 'Project updated',
            backgroundColor: Colors.green);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDeleteProject(AppState state, ProjectRecord p) async {
    if (!_canDeleteProject(p)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project'),
        content: Text('Delete "${p.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.deleteProjectRow(widget.projectId);
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        final data = await SupabaseService.fetchTasksFromSupabase();
        if (data != null && mounted) state.applyTasksFromSupabase(data);
      }
      if (!mounted) return;
      if (widget.openedFromOverview) {
        Navigator.of(context).popUntil((route) {
          final n = route.settings.name;
          return n == kOverviewDashboardRouteName || route.isFirst;
        });
      } else if (widget.openedFromLanding) {
        navigateToHomeTasksTab(context);
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _statusChip({
    required String label,
    required bool selected,
    required Color selectedBg,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: FilledButton(
          onPressed: enabled && !_saving ? onTap : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: selected ? selectedBg : Colors.white,
            foregroundColor: selected ? Colors.white : Colors.black87,
          ),
          child: Text(label),
        ),
      ),
    );
  }

  String _assigneesLine(AppState state) {
    final names = _editAssigneeIds
        .map((k) => state.assigneeById(k)?.name ?? k)
        .where((s) => s.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.isEmpty ? '—' : names.join(', ');
  }

  String _lastUpdatedLine(DateTime? u) {
    if (u == null) return 'Last updated: —';
    return 'Last updated: ${HkTime.formatInstantAsHk(u, 'yyyy-MM-dd HH:mm')}';
  }

  Widget _buildProjectSortColumnControl(ProjectDetailTaskSortColumn column) {
    final active = _taskSortColumn == column;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Sort by ${column.label}',
        onSelected: (v) {
          setState(() {
            if (v == 'clear') {
              if (_taskSortColumn == column) {
                _taskSortColumn = null;
                _taskSortAscending = true;
              }
            } else if (v == 'asc') {
              _taskSortColumn = column;
              _taskSortAscending = true;
            } else if (v == 'desc') {
              _taskSortColumn = column;
              _taskSortAscending = false;
            }
          });
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'asc', child: Text('Ascending')),
          const PopupMenuItem(value: 'desc', child: Text('Descending')),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clear',
            enabled: active,
            child: const Text('Clear sort'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                column.label,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  _taskSortAscending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadErr != null || _project == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: Center(child: Text(_loadErr ?? 'Not found')),
      );
    }
    final p = _project!;
    final creator = _isCreator(p);
    final assigneeViewer = _viewerIsProjectAssignee();
    final canCreateTask = creator;
    final ymd = DateFormat('yyyy-MM-dd');
    final effectiveStatus = _draftStatus ?? p.status;
    final sortedTasks = ProjectTaskSort.sortTasks(
      _tasks,
      _taskSortColumn,
      _taskSortAscending,
      state,
    );

    final pickerTeams = _pickerTeamsForRole();
    final pickerStaff = _pickerStaffForRole();
    final usePicker = creator &&
        SupabaseConfig.isConfigured &&
        pickerStaff.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text('Project: ${p.name}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + kFlowNavBarScrollBottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Project creator: ${p.createByDisplayName ?? '—'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    if (creator && _pickerLoading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                    ] else if (creator && usePicker) ...[
                      StaffAssigneePickerPanel(
                        teams: pickerTeams,
                        staff: pickerStaff,
                        selectedIds: _editAssigneeIds,
                        onSelectionChanged: creator && !_saving
                            ? (s) => setState(() {
                                  _editAssigneeIds
                                    ..clear()
                                    ..addAll(s);
                                })
                            : (_) {},
                      ),
                      const SizedBox(height: 16),
                    ] else if ((assigneeViewer && !creator) ||
                        (creator && !usePicker && !_pickerLoading)) ...[
                      Text(
                        'Project assignee(s): ${_assigneesLine(state)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      'Project',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    creator
                        ? TextField(
                            controller: _nameController,
                            readOnly: _saving,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                          )
                        : SelectableText(
                            p.name,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                    const SizedBox(height: 12),
                    Text(
                      'Description',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    creator
                        ? TextField(
                            controller: _descController,
                            readOnly: _saving,
                            minLines: 3,
                            maxLines: 8,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          )
                        : SelectableText(
                            p.description.isEmpty ? '—' : p.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                    const SizedBox(height: 12),
                    if (!creator) ...[
                      Text(
                        'Start date: ${p.startDate != null ? ymd.format(p.startDate!) : '—'}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'End date: ${p.endDate != null ? ymd.format(p.endDate!) : '—'}',
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (creator) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Start: ${_editStart != null ? ymd.format(_editStart!) : '—'}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _editStart ?? HkTime.todayDateOnlyHk(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 365 * 10)),
                                    );
                                    if (d != null) setState(() => _editStart = d);
                                  },
                            icon: const Icon(Icons.calendar_today),
                            label: const Text('Pick'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'End: ${_editEnd != null ? ymd.format(_editEnd!) : '—'}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: _editEnd ??
                                          _editStart ??
                                          HkTime.todayDateOnlyHk(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 365 * 10)),
                                    );
                                    if (d != null) setState(() => _editEnd = d);
                                  },
                            icon: const Icon(Icons.event),
                            label: const Text('Pick'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    const Divider(height: 28),
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _statusChip(
                          label: 'Not started',
                          selected: effectiveStatus == 'Not started',
                          selectedBg: _kGreySel,
                          enabled: creator,
                          onTap: () =>
                              setState(() => _draftStatus = 'Not started'),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(
                          label: 'In progress',
                          selected: effectiveStatus == 'In progress',
                          selectedBg: _kBlue,
                          enabled: creator,
                          onTap: () =>
                              setState(() => _draftStatus = 'In progress'),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(
                          label: 'Completed',
                          selected: effectiveStatus == 'Completed',
                          selectedBg: _kGreen,
                          enabled: creator,
                          onTap: () =>
                              setState(() => _draftStatus = 'Completed'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Last updated by: ${p.updateByDisplayName ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _lastUpdatedLine(p.updateDate),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Tasks',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (canCreateTask)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () {
                          Navigator.of(context)
                              .push(
                            MaterialPageRoute<void>(
                              builder: (ctx) => Scaffold(
                                appBar:
                                    AppBar(title: const Text('Create task')),
                                body: CreateTaskScreen(
                                  projectId: widget.projectId,
                                  entryPoint:
                                      CreateTaskEntryPoint.projectDetail,
                                ),
                              ),
                            ),
                          )
                              .then((_) async {
                            await _reload();
                            final data =
                                await SupabaseService.fetchTasksFromSupabase();
                            if (!mounted || data == null) return;
                            context.read<AppState>().applyTasksFromSupabase(data);
                          });
                        },
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Create task'),
                ),
              ),
            if (_tasks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  alignment: WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: ProjectDetailTaskSortColumn.values
                      .map(_buildProjectSortColumnControl)
                      .toList(),
                ),
              ),
            ],
            for (final t in sortedTasks) ...[
              const SizedBox(height: 12),
              TaskListCard(
                task: t,
                openedFromOverview: widget.openedFromOverview,
                onTaskTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TaskDetailScreen(
                        taskId: t.id,
                        openedFromOverview: widget.openedFromOverview,
                        openedFromProjectDetail: true,
                        projectIdForBack: widget.projectId,
                      ),
                    ),
                  );
                },
              ),
            ],
            if (creator) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : () => _saveProject(state, p),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(_saving ? 'Saving…' : 'Update'),
              ),
            ],
            if (_canDeleteProject(p)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _confirmDeleteProject(state, p),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: Colors.red.shade800,
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: FlowHomeBackBar(
        onBack: _projectDetailFlowBack,
        onHome: () {
          _projectDetailFlowHome();
        },
        enabled: !_saving,
      ),
    );
  }

  void _projectDetailFlowBack() {
    if (_saving) return;
    if (widget.openedFromOverview) {
      Navigator.of(context).popUntil((route) {
        final n = route.settings.name;
        return n == kOverviewDashboardRouteName || route.isFirst;
      });
    } else if (widget.openedFromLanding) {
      navigateToHomeTasksTab(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _projectDetailFlowHome() async {
    if (_saving) return;
    await navigateToPinnedHomeFromDrawer(context);
  }
}
