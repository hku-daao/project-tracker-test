import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/hk_time.dart';
import '../../utils/home_navigation.dart';
import '../../widgets/flow_navigation_bar.dart';
import '../../widgets/pic_multi_dropdown_text_field.dart';
import '../../utils/project_task_sort.dart';
import '../../widgets/staff_assignee_picker_panel.dart';
import '../../widgets/task_list_card.dart';
import '../../web_deep_link.dart';
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

  /// Collapsible **Deleted tasks** section (singular [`task.status`] deleted).
  bool _deletedTasksExpanded = false;

  ProjectDetailTaskSortColumn? _taskSortColumn;
  /// For **Created date (default)** (`_taskSortColumn == null`): `false` = descending (newest first).
  bool _taskSortAscending = false;

  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _pickerLoading = false;
  final Map<String, String> _staffAssigneeToTeamId = {};
  final Set<String> _editAssigneeIds = {};
  /// Editable PIC assignee keys (project creator only); subset of [_editAssigneeIds].
  final Set<String> _editPicIds = {};
  /// Assignee keys for [`project.pic`] (read-only display for non-editors).
  List<String> _picDisplayKeys = [];

  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _editStart;
  DateTime? _editEnd;

  /// Local status selection; persisted only when user taps **Update**.
  String? _draftStatus;

  String? _myStaffUuid;

  static const Color _kGreen = Color(0xFF298A00);
  static const Color _kBlue = Color(0xFF0B0094);
  static const Color _kGreySel = Color(0xFF424242);

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      syncWebLocationForProjectDetail(widget.projectId);
    }
    _reload();
  }

  @override
  void dispose() {
    if (kIsWeb) {
      clearWebProjectDetailFromLocation();
    }
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
    try {
      final p = await SupabaseService.fetchProjectById(widget.projectId);
      final tasks =
          await SupabaseService.fetchSingularTasksForProject(widget.projectId);
      if (!mounted) return;
      if (p == null) {
        setState(() {
          _loading = false;
          _loadErr = 'Project not found';
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
      _picDisplayKeys = [];
      _editPicIds.clear();
      for (final u in p.picStaffUuids) {
        final k = await SupabaseService.assigneeListKeyFromStaffUuid(u);
        _picDisplayKeys.add(k);
        _editPicIds.add(k);
      }
      var effectiveProject = p;
      if (effectiveProject.picStaffUuids.isEmpty &&
          effectiveProject.assigneeStaffUuids.length == 1) {
        final sole = effectiveProject.assigneeStaffUuids.first.trim();
        if (sole.isNotEmpty) {
          final k = await SupabaseService.assigneeListKeyFromStaffUuid(sole);
          _picDisplayKeys.add(k);
          _editPicIds.add(k);
          final soleCreator = effectiveProject.createByStaffUuid?.trim() ==
              _myStaffUuid?.trim();
          if (soleCreator &&
              mine != null &&
              mine.isNotEmpty &&
              SupabaseConfig.isConfigured) {
            final err = await SupabaseService.updateProjectRow(
              projectId: widget.projectId,
              picStaffUuids: [sole],
              updateByStaffLookupKey: mine,
            );
            if (err == null && mounted) {
              final refreshed =
                  await SupabaseService.fetchProjectById(widget.projectId);
              if (refreshed != null) effectiveProject = refreshed;
            }
          }
        }
      }
      await _loadPickerIfNeeded();
      if (!mounted) return;
      setState(() {
        _project = effectiveProject;
        _tasks = tasks;
        _draftStatus = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadErr = e.toString();
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

  bool _canDeleteProject(ProjectRecord p) => _isCreator(p);

  bool _viewerIsProjectAssignee() {
    final mine = context.read<AppState>().userStaffAppId?.trim();
    if (mine == null || mine.isEmpty) return false;
    return _editAssigneeIds.contains(mine);
  }

  bool _viewerIsProjectPic(ProjectRecord p) {
    final me = _myStaffUuid?.trim();
    if (me == null || me.isEmpty) return false;
    for (final u in p.picStaffUuids) {
      if (u.trim() == me) return true;
    }
    return false;
  }

  String _picNamesLine(AppState state) {
    if (_picDisplayKeys.isEmpty) return '—';
    return _picDisplayKeys
        .map((k) => state.assigneeById(k)?.name ?? k)
        .join(', ');
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

  static String _formatYmdForNotify(DateTime d) {
    return DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));
  }

  static bool _dateOnlyEqual(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _stringSetEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.contains(e)) return false;
    }
    return true;
  }

  String _labelForAssigneeKey(String key, AppState state) {
    final a = state.assigneeById(key);
    if (a != null) {
      final n = a.name.trim();
      if (n.isNotEmpty) return n;
    }
    return key;
  }

  String _assigneeNamesCsv(AppState state, List<String> assigneeKeys) {
    if (assigneeKeys.isEmpty) return '—';
    final sorted = [...assigneeKeys]..sort(
          (a, b) => _labelForAssigneeKey(a, state)
              .toLowerCase()
              .compareTo(_labelForAssigneeKey(b, state).toLowerCase()),
        );
    return sorted
        .map((id) => _labelForAssigneeKey(id, state).trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  Future<Set<String>> _assigneeKeysFromStaffUuids(List<String> staffUuids) async {
    final out = <String>{};
    for (final u in staffUuids) {
      out.add(await SupabaseService.assigneeListKeyFromStaffUuid(u));
    }
    return out;
  }

  /// Field keys must match the backend allow-list for project-updated emails.
  Future<List<Map<String, String>>> _buildProjectUpdateNotifyChanges(
    AppState state,
    ProjectRecord p,
  ) async {
    final out = <Map<String, String>>[];
    if (p.name.trim() != _nameController.text.trim()) {
      out.add({'field': 'projectName', 'value': _nameController.text.trim()});
    }
    if (p.description.trim() != _descController.text.trim()) {
      out.add({'field': 'description', 'value': _descController.text.trim()});
    }
    final oldAssigneeKeys = await _assigneeKeysFromStaffUuids(p.assigneeStaffUuids);
    final newAssigneeKeys = Set<String>.from(_editAssigneeIds);
    if (!_stringSetEqual(oldAssigneeKeys, newAssigneeKeys)) {
      out.add({
        'field': 'assignees',
        'value': _assigneeNamesCsv(state, _editAssigneeIds.toList()),
      });
    }
    final oldPicKeys = await _assigneeKeysFromStaffUuids(p.picStaffUuids);
    final newPicKeys = Set<String>.from(_editPicIds);
    if (!_stringSetEqual(oldPicKeys, newPicKeys)) {
      out.add({
        'field': 'pic',
        'value': _assigneeNamesCsv(state, _editPicIds.toList()),
      });
    }
    final effStatus = (_draftStatus ?? p.status).trim();
    if (p.status.trim() != effStatus) {
      out.add({'field': 'status', 'value': effStatus});
    }
    if (!_dateOnlyEqual(p.startDate, _editStart)) {
      out.add({
        'field': 'startDate',
        'value': _editStart == null ? '—' : _formatYmdForNotify(_editStart!),
      });
    }
    if (!_dateOnlyEqual(p.endDate, _editEnd)) {
      out.add({
        'field': 'endDate',
        'value': _editEnd == null ? '—' : _formatYmdForNotify(_editEnd!),
      });
    }
    return out;
  }

  Future<void> _saveProject(AppState state, ProjectRecord p) async {
    if (!_isCreator(p)) return;
    if (_editAssigneeIds.isEmpty) {
      showCopyableSnackBar(context, 'Select at least one assignee',
          backgroundColor: Colors.orange);
      return;
    }
    if (_editPicIds.isEmpty && _editAssigneeIds.length == 1) {
      _editPicIds.add(_editAssigneeIds.first);
    }
    if (_editPicIds.isEmpty) {
      showCopyableSnackBar(
        context,
        'Select at least one PIC from assignees',
        backgroundColor: Colors.orange,
      );
      return;
    }
    for (final id in _editPicIds) {
      if (!_editAssigneeIds.contains(id)) {
        showCopyableSnackBar(
          context,
          'Each PIC must be one of the project assignees',
          backgroundColor: Colors.orange,
        );
        return;
      }
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
      final changesForEmail = await _buildProjectUpdateNotifyChanges(state, p);
      final slots =
          await SupabaseService.assigneeSlotsForTask(_editAssigneeIds.toList());
      final picUuids = <String>[];
      for (final key in _editPicIds) {
        final u = await SupabaseService.resolveStaffRowIdForAssigneeKey(key);
        if (u != null && u.trim().isNotEmpty) picUuids.add(u.trim());
      }
      if (picUuids.isEmpty) {
        if (!mounted) return;
        showCopyableSnackBar(
          context,
          'Could not resolve PIC staff ids',
          backgroundColor: Colors.orange,
        );
        return;
      }
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        assigneeSlots: slots,
        picStaffUuids: picUuids,
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
      if (token != null && changesForEmail.isNotEmpty) {
        try {
          final notifyErr = await BackendApi().notifyProjectUpdated(
            idToken: token,
            projectId: widget.projectId,
            changes: changesForEmail,
          );
          if (notifyErr != null && mounted) {
            showCopyableSnackBar(
              context,
              'Project saved; update email: $notifyErr',
              backgroundColor: Colors.orange,
            );
          }
        } catch (e) {
          if (mounted) {
            showCopyableSnackBar(
              context,
              'Project update email failed: $e',
              backgroundColor: Colors.orange,
            );
          }
        }
      }
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
    required bool interactive,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: FilledButton(
        onPressed: interactive && !_saving ? onTap : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: selected ? selectedBg : Colors.white,
          foregroundColor: selected ? Colors.white : Colors.black87,
          // Assignees use onPressed: null; without these, M3 greys out chips and hides status colours.
          disabledBackgroundColor: selected ? selectedBg : Colors.white,
          disabledForegroundColor: selected ? Colors.white : Colors.black87,
          surfaceTintColor: Colors.transparent,
        ),
        child: Text(label),
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

  Widget _buildProjectDetailTaskSortDropdown() {
    final theme = Theme.of(context);
    final hasColumn = _taskSortColumn != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasColumn
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: DropdownButton<ProjectDetailTaskSortColumn?>(
              value: _taskSortColumn,
              isDense: true,
              isExpanded: false,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(8),
              style: theme.textTheme.labelLarge,
              items: [
                DropdownMenuItem<ProjectDetailTaskSortColumn?>(
                  value: null,
                  child: Text(
                    'Created date (default)',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: _taskSortColumn == null
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                for (final c in ProjectDetailTaskSortColumn.values)
                  DropdownMenuItem<ProjectDetailTaskSortColumn?>(
                    value: c,
                    child: Text(
                      c.label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: _taskSortColumn == c
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) {
                setState(() {
                  _taskSortColumn = v;
                });
              },
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: _taskSortColumn == null
              ? (_taskSortAscending
                  ? 'Created date: oldest first — tap for newest first'
                  : 'Created date: newest first — tap for oldest first')
              : (_taskSortAscending
                  ? 'Ascending — tap for descending'
                  : 'Descending — tap for ascending'),
          child: IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            icon: Icon(
              _taskSortAscending
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            onPressed: () {
              setState(() => _taskSortAscending = !_taskSortAscending);
            },
          ),
        ),
      ],
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
    final picViewer = _viewerIsProjectPic(p);
    final canCreateTask = creator || assigneeViewer || picViewer;
    final ymd = DateFormat('yyyy-MM-dd');
    final effectiveStatus = _draftStatus ?? p.status;
    final sortedTasks = ProjectTaskSort.sortTasks(
      _tasks,
      _taskSortColumn,
      _taskSortAscending,
      state,
    );

    bool singularTaskDeleted(Task t) {
      if (!t.isSingularTableRow) return false;
      final s = t.dbStatus?.trim().toLowerCase() ?? '';
      return s == 'delete' || s == 'deleted';
    }

    final activeProjectTasks =
        sortedTasks.where((t) => !singularTaskDeleted(t)).toList();
    final deletedProjectTasks =
        sortedTasks.where(singularTaskDeleted).toList();

    final pickerTeams = _pickerTeamsForRole();
    final pickerStaff = _pickerStaffForRole();
    final usePicker = creator &&
        SupabaseConfig.isConfigured &&
        pickerStaff.isNotEmpty;
    final showPicEditor = creator && usePicker;
    final picCandidates = pickerStaff
        .where((s) => _editAssigneeIds.contains(s.assigneeId))
        .toList();

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
                    if (!showPicEditor) ...[
                      Text(
                        'PIC(s): ${_picNamesLine(state)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 12),
                    ],
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
                                  _editPicIds
                                      .removeWhere((id) => !s.contains(id));
                                })
                            : (_) {},
                      ),
                      const SizedBox(height: 16),
                      PicMultiDropdownTextField(
                        key: ValueKey(
                          '${(_editAssigneeIds.toList()..sort()).join(',')}|'
                          '${(_editPicIds.toList()..sort()).join(',')}',
                        ),
                        label: 'PIC(s)',
                        hint: 'Choose from assignees above',
                        candidates: picCandidates,
                        selectedIds: _editPicIds,
                        enabled: !_saving,
                        onSelectionChanged: (next) => setState(() {
                          _editPicIds
                            ..clear()
                            ..addAll(next);
                        }),
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
                        : TextField(
                            controller: _nameController,
                            readOnly: true,
                            enableInteractiveSelection: assigneeViewer,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
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
                        : TextField(
                            controller: _descController,
                            readOnly: true,
                            minLines: 3,
                            maxLines: 8,
                            enableInteractiveSelection: assigneeViewer,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
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
                          interactive: creator,
                          onTap: () =>
                              setState(() => _draftStatus = 'Not started'),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(
                          label: 'In progress',
                          selected: effectiveStatus == 'In progress',
                          selectedBg: _kBlue,
                          interactive: creator,
                          onTap: () =>
                              setState(() => _draftStatus = 'In progress'),
                        ),
                        const SizedBox(width: 8),
                        _statusChip(
                          label: 'Completed',
                          selected: effectiveStatus == 'Completed',
                          selectedBg: _kGreen,
                          interactive: creator,
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
                          final appState = context.read<AppState>();
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
                            if (!mounted) return;
                            final data =
                                await SupabaseService.fetchTasksFromSupabase();
                            if (!mounted || data == null) return;
                            appState.applyTasksFromSupabase(data);
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'Sort',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    _buildProjectDetailTaskSortDropdown(),
                  ],
                ),
              ),
            ],
            for (final t in activeProjectTasks) ...[
              const SizedBox(height: 12),
              TaskListCard(
                task: t,
                openedFromOverview: widget.openedFromOverview,
                onTaskTap: () {
                  final appState = context.read<AppState>();
                  Navigator.of(context)
                      .push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => TaskDetailScreen(
                        taskId: t.id,
                        openedFromOverview: widget.openedFromOverview,
                        openedFromProjectDetail: true,
                        projectIdForBack: widget.projectId,
                      ),
                    ),
                  )
                      .then((_) async {
                    if (!mounted) return;
                    await _reload();
                    if (!mounted) return;
                    final data =
                        await SupabaseService.fetchTasksFromSupabase();
                    if (!mounted || data == null) return;
                    appState.applyTasksFromSupabase(data);
                  });
                },
              ),
            ],
            if (deletedProjectTasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setState(() {
                  _deletedTasksExpanded = !_deletedTasksExpanded;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _deletedTasksExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.grey.shade700,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Deleted tasks (${deletedProjectTasks.length})',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_deletedTasksExpanded)
                for (final t in deletedProjectTasks) ...[
                  const SizedBox(height: 12),
                  TaskListCard(
                    task: t,
                    openedFromOverview: widget.openedFromOverview,
                    onTaskTap: () {
                      final appState = context.read<AppState>();
                      Navigator.of(context)
                          .push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => TaskDetailScreen(
                            taskId: t.id,
                            openedFromOverview: widget.openedFromOverview,
                            openedFromProjectDetail: true,
                            projectIdForBack: widget.projectId,
                          ),
                        ),
                      )
                          .then((_) async {
                        if (!mounted) return;
                        await _reload();
                        if (!mounted) return;
                        final data =
                            await SupabaseService.fetchTasksFromSupabase();
                        if (!mounted || data == null) return;
                        appState.applyTasksFromSupabase(data);
                      });
                    },
                  ),
                ],
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
