import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/assignee.dart';
import '../../models/project_record.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../models/team.dart';
import '../../priority.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../../utils/home_navigation.dart';
import '../../widgets/flow_navigation_bar.dart';
import '../../widgets/staff_assignee_picker_panel.dart';
import '../task_detail_screen.dart';

Future<bool> _confirmLeaveCreateTaskDraftLocal(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved task'),
      content: Text.rich(
        TextSpan(
          style: Theme.of(ctx).textTheme.bodyLarge,
          children: const [
            TextSpan(text: 'Press '),
            TextSpan(
              text: 'Create task',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text:
                  ' to save your task. If you leave now, nothing will be saved.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Leave anyway'),
        ),
      ],
    ),
  );
  return r == true;
}

/// Where the user opened **Create task** (for back navigation).
enum CreateTaskEntryPoint {
  landing,
  overview,
  projectDetail,
  /// FAB on Project dashboard (projects-only view).
  projectDashboard,
}

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({
    super.key,
    this.projectId,
    this.entryPoint = CreateTaskEntryPoint.landing,
    this.showProjectPicker = false,
  });

  /// When set, new task rows get [`task.project_id`].
  final String? projectId;

  final CreateTaskEntryPoint entryPoint;

  /// When true (FAB flows), user picks one of their created projects from a dropdown.
  final bool showProjectPicker;

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentsController = TextEditingController();
  final _changeDueReasonController = TextEditingController();
  final Set<String> _selectedTeamIds = {};
  final Set<String> _selectedAssigneeIds = {};
  /// Person in charge — same key as [assigneeIds]; with one assignee, always that id.
  String? _picAssigneeId;
  int _priority = 1; // 1 = Standard, 2 = Urgent
  /// HK calendar date when the form was opened / reset (task “create date” for defaults).
  late DateTime _anchorCreateDate;
  DateTime? _startDate;
  DateTime? _endDate;
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _pickerLoading = false;
  String? _pickerError;
  final Map<String, String> _staffAssigneeToTeamId = {};
  bool _submitting = false;

  String? _selectedProjectId;
  List<ProjectRecord> _myCreatedProjects = [];
  bool _myProjectsLoading = false;
  String? _projectNameFromDetail;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.projectId != null && widget.projectId!.trim().isNotEmpty) {
      _selectedProjectId = widget.projectId!.trim();
    }
    _anchorCreateDate = HkTime.todayDateOnlyHk();
    _startDate = _anchorCreateDate;
    _endDate = _defaultDueForPriority(_priority);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadSupabaseAssigneePicker();
      context.read<AppState>().setCreateTaskDraftChecker(_hasUnsavedDraft);
      if (widget.entryPoint == CreateTaskEntryPoint.projectDetail &&
          widget.projectId != null &&
          widget.projectId!.trim().isNotEmpty) {
        _loadProjectNameForDetail();
      }
      if (widget.showProjectPicker) {
        _loadMyCreatedProjects();
      }
    });
  }

  Future<void> _loadProjectNameForDetail() async {
    if (!SupabaseConfig.isConfigured) return;
    final id = widget.projectId?.trim();
    if (id == null || id.isEmpty) return;
    final p = await SupabaseService.fetchProjectById(id);
    if (!mounted) return;
    setState(() => _projectNameFromDetail = p?.name.trim());
  }

  Future<void> _loadMyCreatedProjects() async {
    if (!SupabaseConfig.isConfigured) return;
    setState(() => _myProjectsLoading = true);
    try {
      final all = await SupabaseService.fetchAllProjectsFromSupabase();
      if (!mounted) return;
      final appId = context.read<AppState>().userStaffAppId?.trim();
      if (appId == null || appId.isEmpty) {
        setState(() {
          _myProjectsLoading = false;
          _myCreatedProjects = [];
        });
        return;
      }
      final uuid = await SupabaseService.resolveStaffRowIdForAssigneeKey(appId);
      final me = uuid?.trim();
      if (me == null || me.isEmpty) {
        setState(() {
          _myProjectsLoading = false;
          _myCreatedProjects = [];
        });
        return;
      }
      bool eligible(ProjectRecord p) {
        final s = p.status.trim();
        return s == 'Not started' || s == 'In progress';
      }

      final created = all
          .where((p) => p.createByStaffUuid?.trim() == me)
          .where(eligible)
          .toList()
        ..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      if (!mounted) return;
      final selected = _selectedProjectId?.trim();
      final selectedStillValid = selected == null ||
          selected.isEmpty ||
          created.any((p) => p.id == selected);
      setState(() {
        _myProjectsLoading = false;
        _myCreatedProjects = created;
        if (!selectedStillValid) {
          _selectedProjectId = null;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _myProjectsLoading = false;
          _myCreatedProjects = [];
        });
      }
    }
  }

  String? _projectIdForSubmit() {
    if (widget.entryPoint == CreateTaskEntryPoint.projectDetail) {
      final p = widget.projectId?.trim();
      return p != null && p.isNotEmpty ? p : null;
    }
    if (widget.showProjectPicker) {
      final p = _selectedProjectId?.trim();
      return p != null && p.isNotEmpty ? p : null;
    }
    final p = widget.projectId?.trim();
    return p != null && p.isNotEmpty ? p : null;
  }

  Future<void> _onFlowHome() async {
    if (_submitting) return;
    if (_hasUnsavedDraft()) {
      final leave = await _confirmLeaveCreateTaskDraftLocal(context);
      if (!mounted || !leave) return;
    }
    await navigateToPinnedHomeFromDrawer(context);
  }

  Future<void> _onFlowBack() async {
    if (_submitting) return;
    if (_hasUnsavedDraft()) {
      final leave = await _confirmLeaveCreateTaskDraftLocal(context);
      if (!mounted || !leave) return;
    }
    if (!mounted) return;
    switch (widget.entryPoint) {
      case CreateTaskEntryPoint.projectDetail:
        Navigator.of(context).pop();
        break;
      case CreateTaskEntryPoint.overview:
        Navigator.of(context).popUntil((route) {
          final n = route.settings.name;
          return n == kOverviewDashboardRouteName || route.isFirst;
        });
        break;
      case CreateTaskEntryPoint.projectDashboard:
        popUntilProjectDashboardOrHome(context);
        break;
      case CreateTaskEntryPoint.landing:
        Navigator.of(context).pop();
        break;
    }
  }

  Widget _buildProjectContextSection(BuildContext context) {
    if (widget.entryPoint == CreateTaskEntryPoint.projectDetail &&
        widget.projectId != null &&
        widget.projectId!.trim().isNotEmpty) {
      final name = _projectNameFromDetail?.trim().isNotEmpty == true
          ? _projectNameFromDetail!.trim()
          : '(loading…)';
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          'Project: $name',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    if (widget.showProjectPicker) {
      if (_myProjectsLoading) {
        return const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: LinearProgressIndicator(),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String?>(
          value: _selectedProjectId,
          decoration: const InputDecoration(
            labelText: 'Project',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('— No project —'),
            ),
            ..._myCreatedProjects.map(
              (p) => DropdownMenuItem<String?>(
                value: p.id,
                child: Text(
                  p.name.trim().isNotEmpty ? p.name.trim() : p.id,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: _submitting
              ? null
              : (v) => setState(() => _selectedProjectId = v),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  /// True if the user has started a task (text, teams, assignees, or non-default options).
  bool _hasUnsavedDraft() {
    if (_submitting) return false;
    if (_nameController.text.trim().isNotEmpty) return true;
    if (_descController.text.trim().isNotEmpty) return true;
    if (_commentsController.text.trim().isNotEmpty) return true;
    if (_selectedTeamIds.isNotEmpty) return true;
    if (_selectedAssigneeIds.isNotEmpty) return true;
    if (_priority != 1) return true;
    if (_startDate != null &&
        _dateOnlyCompare(_startDate!, _anchorCreateDate) != 0) {
      return true;
    }
    final defaultEnd = _defaultDueForPriority(_priority);
    if (_endDate != null && _dateOnlyCompare(_endDate!, defaultEnd) != 0) {
      return true;
    }
    if (_changeDueReasonController.text.trim().isNotEmpty) return true;
    return false;
  }

  bool _needsChangeDueReason() {
    final start = _startDate ?? _anchorCreateDate;
    final due = _endDate;
    return dueDateExceedsPolicyForPriority(start, due, _priority);
  }

  DateTime _defaultDueForPriority(int priority) {
    final workingDaysAfter = priority == priorityUrgent ? 1 : 3;
    return HkTime.addWorkingDaysAfter(_anchorCreateDate, workingDaysAfter);
  }

  static int _dateOnlyCompare(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return da.compareTo(db);
  }

  Future<void> _loadSupabaseAssigneePicker() async {
    if (!SupabaseConfig.isConfigured) return;
    setState(() {
      _pickerLoading = true;
      _pickerError = null;
    });
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
        } else {
          _pickerTeams = [];
          _pickerStaff = [];
          _staffAssigneeToTeamId.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickerLoading = false;
        _pickerError = e.toString();
        _pickerTeams = [];
        _pickerStaff = [];
        _staffAssigneeToTeamId.clear();
      });
    }
  }

  /// Staff shown in the Supabase picker (full list; not restricted by subordinate relationships).
  List<StaffForAssignment> _pickerStaffForRole() {
    return List<StaffForAssignment>.from(_pickerStaff);
  }

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

  String _inferTeamIdFromSupabasePick(
    List<String> directorIds,
    List<StaffForAssignment> staffPool,
  ) {
    if (directorIds.isEmpty) return '';
    final sorted = [...directorIds]..sort((a, b) {
        final na = staffPool
            .firstWhere((s) => s.assigneeId == a,
                orElse: () =>
                    StaffForAssignment(assigneeId: a, name: a))
            .name;
        final nb = staffPool
            .firstWhere((s) => s.assigneeId == b,
                orElse: () =>
                    StaffForAssignment(assigneeId: b, name: b))
            .name;
        return na.compareTo(nb);
      });
    for (final id in sorted) {
      final t = _staffAssigneeToTeamId[id];
      if (t != null && t.isNotEmpty) return t;
    }
    return '';
  }

  void _syncPicAfterAssigneesChange() {
    if (_selectedAssigneeIds.isEmpty) {
      _picAssigneeId = null;
      return;
    }
    if (_selectedAssigneeIds.length == 1) {
      _picAssigneeId = _selectedAssigneeIds.first;
      return;
    }
    if (_picAssigneeId == null ||
        !_selectedAssigneeIds.contains(_picAssigneeId)) {
      _picAssigneeId = null;
    }
  }

  String _labelForAssigneeId(String id, AppState state) {
    for (final s in _pickerStaffForRole()) {
      if (s.assigneeId == id) return s.name;
    }
    for (final e in _serverAssignable) {
      if (e.staffAppId == id) return e.staffName;
    }
    return state.assigneeById(id)?.name ?? id;
  }

  /// Shown only when there are multiple assignees; single assignee implies PIC without UI.
  Widget _buildPicSection(BuildContext context, AppState state) {
    final ids = _selectedAssigneeIds.toList()
      ..sort((a, b) =>
          _labelForAssigneeId(a, state).compareTo(_labelForAssigneeId(b, state)));
    if (ids.length < 2) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'PIC (person in charge)',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _picAssigneeId != null && ids.contains(_picAssigneeId)
              ? _picAssigneeId
              : null,
          decoration: const InputDecoration(
            labelText: 'PIC',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Choose person in charge'),
          items: ids
              .map(
                (id) => DropdownMenuItem<String>(
                  value: id,
                  child: Text(_labelForAssigneeId(id, state)),
                ),
              )
              .toList(),
          onChanged: _submitting
              ? null
              : (v) => setState(() => _picAssigneeId = v),
          validator: (v) => v == null || v.isEmpty
              ? 'Choose a PIC from the assignees'
              : null,
        ),
      ],
    );
  }

  @override
  void dispose() {
    context.read<AppState>().setCreateTaskDraftChecker(null);
    _nameController.dispose();
    _descController.dispose();
    _commentsController.dispose();
    _changeDueReasonController.dispose();
    super.dispose();
  }

  List<Assignee> _assigneesForSelectedTeams() {
    if (_selectedTeamIds.isEmpty) return [];
    return context.read<AppState>().getAssigneesForTeams(_selectedTeamIds.toList());
  }

  Future<void> _reloadTasksAfterCreate() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final data = await SupabaseService.fetchTasksFromSupabase();
      if (!mounted) return;
      context.read<AppState>().applyTasksFromSupabase(
            data ?? TasksLoadResult.empty,
          );
      final deleted = await SupabaseService.fetchDeletedTasksFromSupabase();
      if (!mounted) return;
      context.read<AppState>().applyDeletedTasksFromSupabase(deleted);
    } catch (e, st) {
      debugPrint('reload tasks after create: $e\n$st');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text('Due date is required'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_submitting) return;
    final state = context.read<AppState>();
    final useServer = state.assignableStaffFromServer.isNotEmpty;
    final teams = state.teams;

    late final String teamId;
    late final List<String> directorIds;

    if (SupabaseConfig.isConfigured && _pickerStaffForRole().isNotEmpty) {
      if (_selectedAssigneeIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text('Select at least one assignee')),
        );
        return;
      }
      directorIds = _selectedAssigneeIds.toList();
      final pool = _pickerStaffForRole();
      var tid = _inferTeamIdFromSupabasePick(directorIds, pool);
      if (tid.isEmpty) tid = teams.isNotEmpty ? teams.first.id : '';
      teamId = tid;
    } else if (useServer) {
      if (_selectedAssigneeIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text('Select at least one assignee')),
        );
        return;
      }
      directorIds = _selectedAssigneeIds.toList();
      if (_selectedTeamIds.isNotEmpty) {
        teamId = _selectedTeamIds.first;
      } else {
        final first = state.assignableStaffFromServer
            .firstWhere((e) => e.staffAppId == directorIds.first,
                orElse: () => state.assignableStaffFromServer.first);
        teamId = first.teamAppId ?? (teams.isNotEmpty ? teams.first.id : '');
      }
    } else if (_selectedTeamIds.isNotEmpty && _selectedAssigneeIds.isNotEmpty) {
      directorIds = _selectedAssigneeIds.toList();
      teamId = _selectedTeamIds.first;
    } else {
      final self = state.userStaffAppId;
      if (self == null || self.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text('Select team(s) and assignees, or configure Supabase'),
          ),
        );
        return;
      }
      directorIds = [self];
      teamId = teams.isNotEmpty ? teams.first.id : '';
    }
    final name = _nameController.text.trim();
    final description = _descController.text.trim();
    final priority = _priority;
    final capturedStart = _startDate ?? _anchorCreateDate;
    final capturedEnd = _endDate!;
    final commentText = _commentsController.text.trim();

    if (_dateOnlyCompare(capturedStart, capturedEnd) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text('Start date cannot be after due date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final needsDueReason =
        dueDateExceedsPolicyForPriority(capturedStart, capturedEnd, priority);
    if (needsDueReason && _changeDueReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text(
            'Enter a reason when the due date is beyond the allowed working days for this priority',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final String picKey;
    if (directorIds.length == 1) {
      picKey = directorIds.first;
    } else {
      if (_picAssigneeId == null || !directorIds.contains(_picAssigneeId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text(
              'Select a PIC (person in charge) from the assignees',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      picKey = _picAssigneeId!;
    }

    setState(() => _submitting = true);
    try {
    final localId = state.addTask(
      name: name,
      description: description,
      assigneeIds: directorIds,
      priority: priority,
      teamId: teamId.isEmpty ? null : teamId,
      status: TaskStatus.todo,
      startDate: capturedStart,
      endDate: capturedEnd,
      createByAssigneeKey: state.userStaffAppId,
      pic: picKey,
      changeDueReason: needsDueReason
          ? _changeDueReasonController.text.trim()
          : null,
    );

    String? cloudErr;
    String? insertedTaskId;
    if (SupabaseConfig.isConfigured) {
      final slots = await SupabaseService.assigneeSlotsForTask(directorIds);
      final ins = await SupabaseService.insertTaskTableRow(
        taskName: name,
        assignees: slots,
        priority: priorityToDisplayName(priority),
        startDate: capturedStart,
        dueDate: capturedEnd,
        description: description.isEmpty ? null : description,
        status: 'Incomplete',
        creatorStaffLookupKey: state.userStaffAppId,
        picStaffLookupKey: picKey,
        changeDueReason:
            needsDueReason ? _changeDueReasonController.text.trim() : null,
        projectId: _projectIdForSubmit(),
      );
      cloudErr = ins.error;
      insertedTaskId = ins.taskId;
      if (cloudErr == null && insertedTaskId != null) {
        try {
          final token = await FirebaseAuth.instance.currentUser?.getIdToken();
          if (token == null) {
            debugPrint('notifyTaskAssigned: skipped — Firebase ID token is null');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 4),
                  content: const Text(
                    'Task saved. Assignment email was not sent (sign-in token missing)',
                  ),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            final notifyErr = await BackendApi().notifyTaskAssigned(
              idToken: token,
              taskId: insertedTaskId,
            );
            if (notifyErr != null) {
              debugPrint('notifyTaskAssigned: $notifyErr');
              if (mounted) {
                final short = notifyErr.length > 160
                    ? '${notifyErr.substring(0, 160)}…'
                    : notifyErr;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Assignment email: $short'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          }
        } catch (e) {
          debugPrint('notifyTaskAssigned: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Assignment email failed: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }
    }

    if (commentText.isNotEmpty) {
      if (SupabaseConfig.isConfigured && cloudErr == null && insertedTaskId != null) {
        final cResult = await SupabaseService.insertSingularCommentRow(
          taskId: insertedTaskId,
          description: commentText,
          status: 'Active',
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (!mounted) return;
        if (cResult.error != null) {
          showCopyableSnackBar(
            context,
            'Task created, but comment was not saved: ${cResult.error}',
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          );
        }
      } else if (!SupabaseConfig.isConfigured) {
        final userId = state.userStaffAppId;
        final String authorId;
        final String authorName;
        if (userId != null && userId.isNotEmpty) {
          authorId = userId;
          authorName = state.assigneeById(userId)?.name ?? userId;
        } else {
          authorId = directorIds.isNotEmpty
              ? directorIds.first
              : state.assignees.first.id;
          final author = state.assigneeById(authorId);
          authorName = author?.name ?? authorId;
        }
        state.addComment(
          taskId: localId,
          authorId: authorId,
          authorName: authorName,
          body: commentText,
        );
      }
    }

    _nameController.clear();
    _descController.clear();
    _commentsController.clear();
    setState(() {
      _selectedTeamIds.clear();
      _selectedAssigneeIds.clear();
      _picAssigneeId = null;
      _priority = 1;
      _anchorCreateDate = HkTime.todayDateOnlyHk();
      _startDate = _anchorCreateDate;
      _endDate = _defaultDueForPriority(_priority);
    });

    if (!mounted) return;

    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(
        context,
        'Saved in this browser only. Set Supabase anon key for this environment (see docs/ENVIRONMENTS.md), rebuild web, redeploy — then data survives refresh',
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 4),
      );
      if (mounted) context.read<AppState>().requestSwitchToTasksTab();
    } else if (cloudErr != null) {
      showCopyableSnackBar(
        context,
        'Could not save to Supabase: $cloudErr',
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      );
    } else {
      await _reloadTasksAfterCreate();
      if (!mounted) return;
      if (widget.entryPoint == CreateTaskEntryPoint.projectDetail) {
        Navigator.of(context).pop();
        return;
      }
      final tid = insertedTaskId?.trim();
      if (tid != null &&
          tid.isNotEmpty &&
          widget.entryPoint != CreateTaskEntryPoint.projectDetail) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => TaskDetailScreen(
              taskId: tid,
              openedFromOverview:
                  widget.entryPoint == CreateTaskEntryPoint.overview,
              openedFromProjectDetail: false,
              openedFromProjectDashboard:
                  widget.entryPoint == CreateTaskEntryPoint.projectDashboard,
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 4),
          content: Text('Task is created'),
          backgroundColor: Colors.green,
        ),
      );
      if (mounted) context.read<AppState>().requestSwitchToTasksTab();
    }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Assignees from server (RBAC); when non-empty, team/assignee UI uses this.
  List<AssignableStaffEntry> get _serverAssignable =>
      context.read<AppState>().assignableStaffFromServer;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final useServer = _serverAssignable.isNotEmpty;
    final assignees = _assigneesForSelectedTeams();

    List<AssignableStaffEntry> serverAssigneesFiltered = [];
    if (useServer) {
      var base = List<AssignableStaffEntry>.from(_serverAssignable);
      if (_selectedTeamIds.isNotEmpty) {
        base = base
            .where((e) =>
                e.teamAppId != null && _selectedTeamIds.contains(e.teamAppId))
            .toList();
      }
      serverAssigneesFiltered = base;
    }

    final pickerStaffForRole = _pickerStaffForRole();
    final pickerTeamsForRole = _pickerTeamsForRole();
    final useSupabasePicker =
        SupabaseConfig.isConfigured && pickerStaffForRole.isNotEmpty;

    super.build(context);

    return Stack(
      children: [
        Scaffold(
          body: AbsorbPointer(
            absorbing: _submitting,
            child: Opacity(
              opacity: _submitting ? 0.55 : 1,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  24 + kFlowNavBarScrollBottomPadding,
                ),
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
            _buildProjectContextSection(context),
            if (SupabaseConfig.isConfigured) ...[
              if (_pickerLoading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
              ],
              if (_pickerError != null && !_pickerLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _pickerError!,
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                  ),
                ),
              if (useSupabasePicker)
                StaffAssigneePickerPanel(
                  teams: pickerTeamsForRole,
                  staff: pickerStaffForRole,
                  selectedIds: _selectedAssigneeIds,
                  onSelectionChanged: (s) => setState(() {
                    _selectedAssigneeIds
                      ..clear()
                      ..addAll(s);
                    _syncPicAfterAssigneesChange();
                  }),
                )
              else if (useServer) ...[
                const Text(
                  'Team (multiple)',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final state = context.read<AppState>();
                    final teams = state.teams;
                    if (teams.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No teams found in database.',
                              style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Please ensure teams exist and the backend /api/teams endpoint is working.',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: teams.map((Team t) {
                        final selected = _selectedTeamIds.contains(t.id);
                        return FilterChip(
                          label: Text(t.name),
                          selected: selected,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                _selectedTeamIds.add(t.id);
                              } else {
                                _selectedTeamIds.remove(t.id);
                                _selectedAssigneeIds.removeWhere((id) {
                                  final assignee = _serverAssignable.firstWhere(
                                    (e) => e.staffAppId == id,
                                    orElse: () => const AssignableStaffEntry(
                                      staffAppId: '',
                                      staffName: '',
                                      teamAppId: null,
                                      teamName: null,
                                    ),
                                  );
                                  return assignee.teamAppId == t.id &&
                                      !_selectedTeamIds.any((tid) {
                                        final otherAssignee = _serverAssignable.firstWhere(
                                          (e) => e.staffAppId == id,
                                          orElse: () => const AssignableStaffEntry(
                                            staffAppId: '',
                                            staffName: '',
                                            teamAppId: null,
                                            teamName: null,
                                          ),
                                        );
                                        return otherAssignee.teamAppId == tid;
                                      });
                                });
                              }
                              _syncPicAfterAssigneesChange();
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],
            ],
            if (!useSupabasePicker) ...[
            Text(
              useServer ? 'Assignees (multiple)' : 'Directors & Responsible Officers (multiple)',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            if (useServer) ...[
              if (serverAssigneesFiltered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No assignable staff found for the selected team(s).',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: serverAssigneesFiltered.map((e) {
                    final selected = _selectedAssigneeIds.contains(e.staffAppId);
                    return FilterChip(
                      label: Text(e.staffName),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedAssigneeIds.add(e.staffAppId);
                            if (e.teamAppId != null) {
                              _selectedTeamIds.add(e.teamAppId!);
                            }
                          } else {
                            _selectedAssigneeIds.remove(e.staffAppId);
                          }
                          _syncPicAfterAssigneesChange();
                        });
                      },
                    );
                  }).toList(),
                ),
            ] else ...[
              if (_selectedTeamIds.isEmpty)
                const Text(
                  'Select team(s) first',
                  style: TextStyle(color: Colors.grey),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: assignees.map((a) {
                    final selected = _selectedAssigneeIds.contains(a.id);
                    final isDirector = state.isDirector(a.id);
                    return FilterChip(
                      label: Text(a.name),
                      selected: selected,
                      backgroundColor: isDirector ? Colors.lightBlue.shade100 : Colors.purple.shade100,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedAssigneeIds.add(a.id);
                          } else {
                            _selectedAssigneeIds.remove(a.id);
                          }
                          _syncPicAfterAssigneesChange();
                        });
                      },
                    );
                  }).toList(),
                ),
            ],
            ],
            if (_selectedAssigneeIds.length > 1) ...[
              const SizedBox(height: 16),
              _buildPicSection(context, state),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              readOnly: _submitting,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Task name',
                hintText: 'Task name',
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
                  label: Text(
                    priorityToDisplayName(p),
                    style: const TextStyle(fontSize: 16),
                  ),
                  selected: selected,
                  onSelected: _submitting
                      ? null
                      : (v) {
                          if (!v) return;
                          setState(() {
                            _priority = p;
                            _endDate = _defaultDueForPriority(p);
                          });
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start date',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _startDate != null
                      ? '${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}'
                      : '${_anchorCreateDate.year}-${_anchorCreateDate.month.toString().padLeft(2, '0')}-${_anchorCreateDate.day.toString().padLeft(2, '0')}',
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          final initial = _startDate ?? _anchorCreateDate;
                          final d = await showDatePicker(
                            context: context,
                            initialDate: initial,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 3),
                            ),
                          );
                          if (d != null) setState(() => _startDate = d);
                        },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text(
                  'Due Date',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '*',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  _endDate != null
                      ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                      : 'Not set — pick a date',
                  style: TextStyle(
                    color: _endDate == null ? Colors.orange.shade800 : null,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () async {
                          final start = _startDate ?? _anchorCreateDate;
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _endDate ?? HkTime.addWorkingDaysAfter(start, 1),
                            firstDate: start,
                            lastDate:
                                DateTime.now().add(const Duration(days: 365 * 3)),
                          );
                          if (d != null) setState(() => _endDate = d);
                        },
                  icon: const Icon(Icons.calendar_today),
                  label: const Text('Pick'),
                ),
              ],
            ),
            if (_needsChangeDueReason()) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _changeDueReasonController,
                readOnly: _submitting,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Extend timeline reason',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (v) {
                  if (!_needsChangeDueReason()) return null;
                  if (v == null || v.trim().isEmpty) {
                    return 'Required when due date exceeds allowed working days';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 16),
            TextFormField(
              controller: _descController,
              readOnly: _submitting,
              textInputAction: TextInputAction.next,
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
              readOnly: _submitting,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Comments',
                hintText: 'Comments',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_submitting ? 'Creating…' : 'Create task'),
              ),
            ),
          ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: FlowHomeBackBar(
            onBack: _onFlowBack,
            onHome: _onFlowHome,
            enabled: !_submitting,
          ),
        ),
        if (_submitting)
          Positioned.fill(
            child: AbsorbPointer(
              child: Material(
                color: Colors.black26,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 20),
                      Text(
                        'Please wait...',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
