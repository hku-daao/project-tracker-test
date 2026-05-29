import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/staff_for_assignment.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';

/// New project slide — empty fields, Create in footer.
class AsanaCreateProjectDetailPanel extends StatefulWidget {
  const AsanaCreateProjectDetailPanel({
    super.key,
    required this.palette,
    required this.onClose,
    this.onCreated,
  });

  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final void Function(String projectId)? onCreated;

  @override
  State<AsanaCreateProjectDetailPanel> createState() =>
      _AsanaCreateProjectDetailPanelState();
}

class _AsanaCreateProjectDetailPanelState
    extends State<AsanaCreateProjectDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _draftStatus = 'Not started';
  bool _saving = false;
  bool _assigneePickerLoading = false;
  String? _assigneePickerError;
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  final Set<String> _assigneeIds = {};
  final Set<String> _picAssigneeIds = {};
  final ValueNotifier<AsanaAssigneePickerSnapshot> _assigneeSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));
  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  int _anchoredPickerReopenBlockedUntilMs = 0;

  @override
  void initState() {
    super.initState();
    _loadAssigneePicker();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch > _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  Future<void> _loadAssigneePicker() async {
    if (!SupabaseConfig.isConfigured) {
      _assigneePickerLoading = false;
      _assigneePickerError = 'Supabase not configured';
      _pickerTeams = [];
      _pickerStaff = [];
      _publishAssigneeSnapshots();
      if (mounted) setState(() {});
      return;
    }
    _assigneePickerLoading = true;
    _assigneePickerError = null;
    _publishAssigneeSnapshots();
    if (mounted) setState(() {});
    try {
      final data = await SupabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      _assigneePickerLoading = false;
      _pickerTeams = data?.teams ?? [];
      _pickerStaff = data?.staff ?? [];
      _publishAssigneeSnapshots();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _assigneePickerLoading = false;
      _assigneePickerError = e.toString();
      _pickerTeams = [];
      _pickerStaff = [];
      _publishAssigneeSnapshots();
      setState(() {});
    }
  }

  void _publishAssigneeSnapshots() {
    _assigneeSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForStaff(_pickerStaff),
      staff: List<StaffForAssignment>.from(_pickerStaff),
      error: _assigneePickerError,
    );
    final picStaff = _pickerStaff
        .where((s) => _assigneeIds.contains(s.assigneeId))
        .toList();
    _picSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForStaff(picStaff),
      staff: picStaff,
      error: _assigneePickerError,
    );
  }

  List<TeamOptionRow> _pickerTeamsForStaff(List<StaffForAssignment> staff) {
    final teamIds = staff
        .map((s) => s.teamId)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    if (teamIds.isEmpty) return List<TeamOptionRow>.from(_pickerTeams);
    return _pickerTeams.where((t) => teamIds.contains(t.teamId)).toList();
  }

  String _labelForAssigneeId(String id, AppState state) {
    for (final s in _pickerStaff) {
      if (s.assigneeId == id) return s.name.trim();
    }
    final a = state.assigneeById(id);
    if (a != null && a.name.trim().isNotEmpty) return a.name.trim();
    return id;
  }

  List<({String id, String name})> _rowsForIds(Set<String> ids, AppState state) {
    return ids
        .map((id) => (id: id, name: _labelForAssigneeId(id, state)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _showEmailWarning(String label, String error) {
    debugPrint('$label: $error');
    if (!mounted) return;
    final short = error.length > 160 ? '${error.substring(0, 160)}...' : error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: $short'),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _notifyEmail(
    String label,
    Future<String?> Function(String idToken) send,
  ) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        _showEmailWarning(label, 'sign-in token missing');
        return;
      }
      final err = await send(token);
      if (err != null) _showEmailWarning(label, err);
    } catch (e) {
      _showEmailWarning(label, e.toString());
    }
  }

  void _syncPicAfterAssigneesChange() {
    _picAssigneeIds.removeWhere((id) => !_assigneeIds.contains(id));
    if (_assigneeIds.length == 1) _picAssigneeIds.add(_assigneeIds.first);
    _publishAssigneeSnapshots();
  }

  void _removeAssignee(String assigneeId) {
    setState(() {
      _assigneeIds.remove(assigneeId);
      _syncPicAfterAssigneesChange();
    });
  }

  void _removePic(String assigneeId) {
    setState(() => _picAssigneeIds.remove(assigneeId));
  }

  Future<void> _pickAssignees(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    await showAsanaAssigneePicker(
      anchorLink: _assigneeAnchorLink,
      anchorContext: anchorContext,
      snapshot: _assigneeSnapshot,
      selectedIds: _assigneeIds,
      whenClosed: _blockAnchoredPickerReopen,
      onSelectionChanged: (s) {
        if (!mounted) return;
        setState(() {
          _assigneeIds
            ..clear()
            ..addAll(s);
          _syncPicAfterAssigneesChange();
        });
      },
    );
  }

  Future<void> _pickPics(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    if (_assigneeIds.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Assignees required',
        content: 'Select assignees first.',
        palette: widget.palette,
      );
      return;
    }
    final state = context.read<AppState>();
    final ids = _assigneeIds.toList()
      ..sort(
        (a, b) => _labelForAssigneeId(a, state)
            .compareTo(_labelForAssigneeId(b, state)),
      );
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _picAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: ids
          .map(
            (id) => AsanaAnchoredOption(
              value: id,
              label: _labelForAssigneeId(id, state),
            ),
          )
          .toList(),
    );
    if (choice != null && mounted) {
      setState(() => _picAssigneeIds.add(choice));
    }
  }

  Future<void> _pickStartDate(BuildContext anchorContext) async {
    final picked = await showAsanaAnchoredSingleDatePicker(
      anchorContext: anchorContext,
      initialDate: _startDate,
      helpText: 'Start date',
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = picked);
  }

  Future<void> _pickDueDate(BuildContext anchorContext) async {
    final picked = await showAsanaAnchoredSingleDatePicker(
      anchorContext: anchorContext,
      initialDate: _endDate,
      helpText: 'Due date',
    );
    if (picked == null || !mounted) return;
    setState(() => _endDate = picked);
  }

  Future<void> _pickStatus(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    const options = [
      AsanaAnchoredOption(value: 'Not started', label: 'Not started'),
      AsanaAnchoredOption(value: 'In progress', label: 'In progress'),
      AsanaAnchoredOption(value: 'Completed', label: 'Completed'),
    ];
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _statusAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: options,
    );
    if (choice != null && mounted) {
      setState(() => _draftStatus = choice);
    }
  }

  Future<void> _create(AppState state) async {
    if (!SupabaseConfig.isConfigured) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Supabase not configured',
        content: 'Please configure Supabase before continuing.',
        palette: widget.palette,
      );
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Project name required',
        content: 'Please fill in the project name before continuing.',
        palette: widget.palette,
      );
      return;
    }
    if (_assigneeIds.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Assignee required',
        content: 'Select at least one assignee.',
        palette: widget.palette,
      );
      return;
    }
    if (_picAssigneeIds.isEmpty) {
      if (_assigneeIds.length == 1) {
        _picAssigneeIds.add(_assigneeIds.first);
      } else {
        await showAsanaInfoDialog(
          context: context,
          title: 'PIC required',
          content: 'Select at least one PIC from assignees.',
          palette: widget.palette,
        );
        return;
      }
    }
    if (_startDate != null &&
        _endDate != null &&
        _startDate!.isAfter(_endDate!)) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Invalid date range',
        content: 'Start date cannot be after due date.',
        palette: widget.palette,
      );
      return;
    }
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final slots =
          await SupabaseService.assigneeSlotsForTask(_assigneeIds.toList());
      final picUuids = <String>[];
      for (final key in _picAssigneeIds) {
        final u = await SupabaseService.resolveStaffRowIdForAssigneeKey(key);
        if (u != null && u.trim().isNotEmpty) picUuids.add(u.trim());
      }
      final ins = await SupabaseService.insertProjectRow(
        name: name,
        assignees: slots,
        picStaffUuids: picUuids,
        description: _descController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        status: _draftStatus,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (ins.error != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not create project',
          content: ins.error!,
          palette: widget.palette,
        );
        return;
      }
      final newId = ins.projectId;
      if (newId != null && newId.isNotEmpty) {
        final p = await SupabaseService.fetchProjectById(newId);
        if (p != null) state.upsertProject(p);
        await _notifyEmail(
          'Project assignment email',
          (token) => BackendApi().notifyProjectAssigned(
            idToken: token,
            projectId: newId,
          ),
        );
        widget.onCreated?.call(newId);
      }
      if (mounted) widget.onClose();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chrome = AsanaSlideChrome(widget.palette);
    final creatorName = () {
      final id = state.userStaffAppId?.trim();
      if (id == null || id.isEmpty) return '';
      return state.assigneeById(id)?.name.trim() ?? id;
    }();

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: AsanaDetailSlideFooter(
        backgroundColor: chrome.footer,
        borderColor: chrome.footerBorder,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton(
              onPressed: _saving ? null : () => _create(state),
              style: FilledButton.styleFrom(
                backgroundColor: widget.palette.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(_saving ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                AsanaHoverTextField(
                  controller: _nameController,
                  canEdit: true,
                  readOnly: _saving,
                  maxLines: 3,
                  minLines: 1,
                  style: asanaDetailTitleStyle(context),
                  hintText: 'Please fill in project name',
                ),
                const SizedBox(height: 12),
                AsanaDetailLabelValue(
                  label: 'Description',
                  child: AsanaHoverTextField(
                    controller: _descController,
                    canEdit: true,
                    readOnly: _saving,
                    maxLines: 8,
                    minLines: 2,
                    style: asanaDetailMultilineValueStyle(context),
                    hintText: 'Please fill in project description',
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Creator',
                  child: AsanaDetailPlainValue(text: creatorName),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Assignees',
                  child: AsanaAssigneeFieldValue(
                    anchorLink: _assigneeAnchorLink,
                    assignees: _rowsForIds(_assigneeIds, state),
                    canEdit: !_saving,
                    onOpenPicker: _pickAssignees,
                    onRemove: _removeAssignee,
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'PIC',
                  child: AsanaAssigneeFieldValue(
                    anchorLink: _picAnchorLink,
                    assignees: _rowsForIds(_picAssigneeIds, state),
                    canEdit: !_saving && _assigneeIds.isNotEmpty,
                    emptyPlaceholder: _assigneeIds.isEmpty
                        ? 'Select assignees first'
                        : 'Select PIC(s)',
                    onOpenPicker: _pickPics,
                    onRemove: _removePic,
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Status',
                  child: Builder(
                    builder: (anchorContext) => CompositedTransformTarget(
                      link: _statusAnchorLink,
                      child: MouseRegion(
                        cursor: _saving
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap:
                              _saving ? null : () => _pickStatus(anchorContext),
                          child: AsanaDetailStatusPill(status: _draftStatus),
                        ),
                      ),
                    ),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Start date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_startDate),
                    canEdit: true,
                    emptyPlaceholder: '-',
                    onTap: _saving ? null : _pickStartDate,
                    onClear: _saving ? null : () => setState(() => _startDate = null),
                  ),
                ),
                AsanaDetailTwoColumnRow(
                  label: 'Due date',
                  child: AsanaHoverTapValue(
                    value: _formatDate(_endDate),
                    canEdit: true,
                    emptyPlaceholder: '-',
                    onTap: _saving ? null : _pickDueDate,
                    onClear: _saving ? null : () => setState(() => _endDate = null),
                  ),
                ),
              ],
            ),
    );
  }
}
