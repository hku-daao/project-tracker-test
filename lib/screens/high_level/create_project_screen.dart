import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/staff_for_assignment.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/hk_time.dart';
import '../../utils/home_navigation.dart';
import '../../widgets/flow_navigation_bar.dart';
import '../../widgets/staff_assignee_picker_panel.dart';
import 'project_detail_screen.dart';

Future<bool> _confirmLeaveCreateProjectDraft(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved project'),
      content: const Text(
        'Press Create project to save. If you leave now, nothing will be saved.',
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

/// Create flow opened from landing (`openedFromOverview == false`) or Overview.
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key, this.openedFromOverview = false});

  final bool openedFromOverview;

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final Set<String> _selectedAssigneeIds = {};
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _pickerLoading = false;
  String? _pickerError;
  final Map<String, String> _staffAssigneeToTeamId = {};
  DateTime? _startDate;
  DateTime? _endDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _startDate = HkTime.todayDateOnlyHk();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPicker());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadPicker() async {
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
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickerLoading = false;
        _pickerError = e.toString();
      });
    }
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

  String _inferTeamIdFromSupabasePick(List<String> directorIds) {
    if (directorIds.isEmpty) return '';
    final staffPool = _pickerStaffForRole();
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

  Future<void> _submit(AppState state) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedAssigneeIds.isEmpty) {
      showCopyableSnackBar(context, 'Select at least one assignee',
          backgroundColor: Colors.orange);
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    final directorIds = _selectedAssigneeIds.toList();
    final teamId = _inferTeamIdFromSupabasePick(directorIds);
    if (teamId.isEmpty) {
      showCopyableSnackBar(
        context,
        'Could not resolve team for assignees — pick teammates from the roster',
        backgroundColor: Colors.orange,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final slots = await SupabaseService.assigneeSlotsForTask(directorIds);
      final ins = await SupabaseService.insertProjectRow(
        name: _nameController.text.trim(),
        assignees: slots,
        description: _descController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        status: 'Not started',
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (ins.error != null || ins.projectId == null) {
        showCopyableSnackBar(
          context,
          ins.error ?? 'Could not create project',
          backgroundColor: Colors.orange,
        );
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        final data = await SupabaseService.fetchTasksFromSupabase();
        if (data != null && mounted) {
          state.applyTasksFromSupabase(data);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (ctx) => ProjectDetailScreen(
            projectId: ins.projectId!,
            openedFromLanding: !widget.openedFromOverview,
            openedFromOverview: widget.openedFromOverview,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _hasUnsavedDraft() {
    if (_nameController.text.trim().isNotEmpty) return true;
    if (_descController.text.trim().isNotEmpty) return true;
    if (_selectedAssigneeIds.isNotEmpty) return true;
    return false;
  }

  Future<void> _flowHome() async {
    if (_submitting) return;
    if (_hasUnsavedDraft()) {
      final leave = await _confirmLeaveCreateProjectDraft(context);
      if (!mounted || !leave) return;
    }
    await navigateToPinnedHomeFromDrawer(context);
  }

  Future<void> _flowBack() async {
    if (_submitting) return;
    if (_hasUnsavedDraft()) {
      final leave = await _confirmLeaveCreateProjectDraft(context);
      if (!mounted || !leave) return;
    }
    if (!mounted) return;
    if (widget.openedFromOverview) {
      Navigator.of(context).popUntil((route) {
        final n = route.settings.name;
        return n == kOverviewDashboardRouteName || route.isFirst;
      });
    } else {
      navigateToHomeTasksTab(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pickerStaff = _pickerStaffForRole();
    final pickerTeams = _pickerTeamsForRole();
    final usePicker =
        SupabaseConfig.isConfigured && pickerStaff.isNotEmpty && !_pickerLoading;

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
                if (usePicker)
                  StaffAssigneePickerPanel(
                    teams: pickerTeams,
                    staff: pickerStaff,
                    selectedIds: _selectedAssigneeIds,
                    onSelectionChanged: (s) => setState(() {
                      _selectedAssigneeIds
                        ..clear()
                        ..addAll(s);
                    }),
                  )
                else if (!SupabaseConfig.isConfigured)
                  const Text(
                    'Supabase not configured — cannot load assignees.',
                    style: TextStyle(color: Colors.orange),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Project',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descController,
                  textInputAction: TextInputAction.next,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Start date', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _startDate != null
                          ? DateFormat('yyyy-MM-dd').format(_startDate!)
                          : '—',
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: _submitting
                          ? null
                          : () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _startDate ?? HkTime.todayDateOnlyHk(),
                                firstDate: DateTime(2020),
                                lastDate:
                                    DateTime.now().add(const Duration(days: 365 * 10)),
                              );
                              if (d != null) setState(() => _startDate = d);
                            },
                      icon: const Icon(Icons.calendar_today),
                      label: const Text('Pick'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('End date', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _endDate != null
                          ? DateFormat('yyyy-MM-dd').format(_endDate!)
                          : '—',
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: _submitting
                          ? null
                          : () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate:
                                    _endDate ?? _startDate ?? HkTime.todayDateOnlyHk(),
                                firstDate: DateTime(2020),
                                lastDate:
                                    DateTime.now().add(const Duration(days: 365 * 10)),
                              );
                              if (d != null) setState(() => _endDate = d);
                            },
                      icon: const Icon(Icons.event),
                      label: const Text('Pick'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : () => _submit(state),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_submitting ? 'Creating…' : 'Create project'),
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
            onBack: () {
              _flowBack();
            },
            onHome: () {
              _flowHome();
            },
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
