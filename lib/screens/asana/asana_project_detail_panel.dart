import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/staff_for_assignment.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_project_ai_assistant.dart';
import 'asana_project_filter.dart';
import 'asana_task_ai_assistant.dart';

/// Project slide — creator can edit all project fields (matches task slide layout).
class AsanaProjectDetailPanel extends StatefulWidget {
  const AsanaProjectDetailPanel({
    super.key,
    required this.projectId,
    required this.palette,
    required this.onClose,
    this.onChanged,
  });

  final String projectId;
  final AsanaLandingPalette palette;
  final VoidCallback onClose;
  final VoidCallback? onChanged;

  @override
  State<AsanaProjectDetailPanel> createState() => _AsanaProjectDetailPanelState();
}

class _AsanaProjectDetailPanelState extends State<AsanaProjectDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  ProjectRecord? _project;
  bool _loading = true;
  bool _saving = false;
  String? _myStaffUuid;

  DateTime? _startDate;
  DateTime? _endDate;
  String? _draftStatus;

  final Set<String> _assigneeIds = {};
  final Set<String> _picAssigneeIds = {};
  final Map<String, String> _assigneeDisplayNames = {};

  AsanaTaskAiController? _projectAi;

  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _assigneePickerLoading = false;
  String? _assigneePickerError;
  final ValueNotifier<AsanaAssigneePickerSnapshot> _assigneeSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));

  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  final GlobalKey _detailPopupWidthAlignKey = GlobalKey();
  int _anchoredPickerReopenBlockedUntilMs = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant AsanaProjectDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) _bootstrap();
  }

  @override
  void dispose() {
    AsanaBlockingLoadingOverlay.hideAll();
    _nameController.dispose();
    _descController.dispose();
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
    _projectAi?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    final lk = context.read<AppState>().userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty) {
      _myStaffUuid = await SupabaseService.staffRowIdForAssigneeKey(lk);
    }
    await Future.wait([
      _loadProject(),
      _loadAssigneePicker(),
    ]);
  }

  Future<void> _loadProject() async {
    if (!SupabaseConfig.isConfigured) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final p = await SupabaseService.fetchProjectById(widget.projectId);
    if (!mounted) return;
    if (p != null) {
      _nameController.text = p.name;
      _descController.text = p.description;
      _startDate = p.startDate;
      _endDate = p.endDate;
      _draftStatus = null;
      await _syncAssigneeKeysFromProject(p);
    }
    if (mounted) {
      setState(() {
        _project = p;
        _loading = false;
      });
    }
  }

  Future<void> _syncAssigneeKeysFromProject(ProjectRecord p) async {
    final keys = <String>{};
    final picKeys = <String>{};
    _assigneeDisplayNames.clear();
    for (var i = 0; i < p.assigneeStaffUuids.length; i++) {
      final u = p.assigneeStaffUuids[i];
      final key = await SupabaseService.assigneeListKeyFromStaffUuid(u);
      keys.add(key);
      if (i < p.assigneeStaffDisplayNames.length) {
        final name = p.assigneeStaffDisplayNames[i].trim();
        if (name.isNotEmpty) _assigneeDisplayNames[key] = name;
      }
    }
    for (final u in p.picStaffUuids) {
      picKeys.add(await SupabaseService.assigneeListKeyFromStaffUuid(u));
    }
    if (!mounted) return;
    setState(() {
      _assigneeIds
        ..clear()
        ..addAll(keys);
      _picAssigneeIds
        ..clear()
        ..addAll(picKeys);
    });
    _syncPicAfterAssigneesChange();
    _publishPicSnapshot();
  }

  void _setSaving(bool saving) {
    if (!mounted) return;
    if (_saving == saving) return;
    setState(() => _saving = saving);
    if (saving) {
      AsanaBlockingLoadingOverlay.show(context);
    } else {
      AsanaBlockingLoadingOverlay.hide();
    }
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch > _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  bool _isCreator(ProjectRecord p) {
    final me = _myStaffUuid?.trim();
    final cb = p.createByStaffUuid?.trim();
    if (me == null || me.isEmpty || cb == null || cb.isEmpty) return false;
    return me == cb;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  String _labelForAssigneeId(String id, AppState state) {
    final stored = _assigneeDisplayNames[id]?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    for (final s in _pickerStaff) {
      if (s.assigneeId == id) return s.name.trim();
    }
    final a = state.assigneeById(id);
    if (a != null && a.name.trim().isNotEmpty) return a.name.trim();
    return id;
  }

  List<({String id, String name})> _rowsForIds(
    Set<String> ids,
    AppState state,
  ) {
    return ids
        .map((id) => (id: id, name: _labelForAssigneeId(id, state)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _publishAssigneeSnapshot() {
    _assigneeSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForStaff(_pickerStaff),
      staff: List<StaffForAssignment>.from(_pickerStaff),
      error: _assigneePickerError,
    );
  }

  void _publishPicSnapshot() {
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

  Future<void> _loadAssigneePicker() async {
    if (!SupabaseConfig.isConfigured) {
      _assigneePickerLoading = false;
      _assigneePickerError = 'Supabase not configured';
      _pickerTeams = [];
      _pickerStaff = [];
      _publishAssigneeSnapshot();
      _publishPicSnapshot();
      if (mounted) setState(() {});
      return;
    }
    _assigneePickerLoading = true;
    _assigneePickerError = null;
    _publishAssigneeSnapshot();
    _publishPicSnapshot();
    if (mounted) setState(() {});
    try {
      final data = await SupabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      _assigneePickerLoading = false;
      if (data != null) {
        _pickerTeams = data.teams;
        _pickerStaff = data.staff;
      } else {
        _pickerTeams = [];
        _pickerStaff = [];
      }
      _publishAssigneeSnapshot();
      _publishPicSnapshot();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _assigneePickerLoading = false;
      _assigneePickerError = e.toString();
      _pickerTeams = [];
      _pickerStaff = [];
      _publishAssigneeSnapshot();
      _publishPicSnapshot();
      setState(() {});
    }
  }

  void _syncPicAfterAssigneesChange() {
    _picAssigneeIds.removeWhere((id) => !_assigneeIds.contains(id));
    if (_assigneeIds.length == 1) {
      _picAssigneeIds.add(_assigneeIds.first);
    }
    _publishPicSnapshot();
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
    if (!_canOpenAnchoredPicker || _saving) return;
    final picked = await showAsanaAnchoredSingleDatePicker(
      anchorContext: anchorContext,
      initialDate: _startDate,
      helpText: 'Start date',
    );
    if (picked == null || !mounted) return;
    setState(() => _startDate = picked);
  }

  Future<void> _pickDueDate(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
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

  String _effectiveStatus(ProjectRecord p) =>
      (_draftStatus ?? p.status).trim();

  bool _canMarkProjectComplete(ProjectRecord p) =>
      _isCreator(p) && _effectiveStatus(p) != 'Completed' && _effectiveStatus(p) != 'Deleted';

  bool _canDeleteProject(ProjectRecord p) =>
      _isCreator(p) && _effectiveStatus(p) != 'Deleted';

  Future<void> _confirmDeleteProject(AppState state) async {
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Delete project',
      content: 'Delete "${_project?.name ?? 'this project'}"? It will be moved to the Deleted status.',
      confirmText: 'Delete',
      isDestructive: true,
      palette: widget.palette,
    );
    if (ok != true) return;
    if (!mounted) return;
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      debugPrint(
        'PROJECT_DELETE_ATTEMPT projectId=${widget.projectId} '
        'userStaffAppId=${state.userStaffAppId}',
      );
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        status: 'Deleted',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      debugPrint('PROJECT_DELETE_STATUS_DELETED_RESULT err=$err');
      if (!mounted) return;
      if (err != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not delete project',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      widget.onChanged?.call();
      if (mounted) {
        widget.onClose();
      }
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _markCompleted(AppState state, ProjectRecord p) async {
    if (!_canMarkProjectComplete(p)) return;
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        status: 'Completed',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not complete project',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      await _loadProject();
      _projectAi?.clearAllSuggestions();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  AsanaProjectAiFormSnapshot _aiFormSnapshot(AppState state) {
    final assigneesLabel = _assigneeIds
        .map((id) => _labelForAssigneeId(id, state))
        .join(', ');
    final picLabel =
        _picAssigneeIds.map((id) => _labelForAssigneeId(id, state)).join(', ');
    final staff = _pickerStaff
        .map((s) => (id: s.assigneeId, name: s.name.trim()))
        .where((s) => s.name.isNotEmpty)
        .toList();
    return AsanaProjectAiFormSnapshot(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      status: _effectiveStatus(_project!),
      startDate: _startDate,
      dueDate: _endDate,
      assigneesLabel: assigneesLabel,
      picLabel: picLabel,
      staff: staff,
      selectedAssigneeIds: Set<String>.from(_assigneeIds),
      selectedPicAssigneeIds: Set<String>.from(_picAssigneeIds),
    );
  }

  AsanaProjectAiApply _aiApplyHandlers() {
    return AsanaProjectAiApply(
      applyName: (v) => setState(() => _nameController.text = v),
      applyDescription: (v) => setState(() => _descController.text = v),
      applyAssignees: (ids) => setState(() {
        _assigneeIds
          ..clear()
          ..addAll(ids);
        _syncPicAfterAssigneesChange();
      }),
      applyPic: (ids) => setState(() {
        _picAssigneeIds
          ..clear()
          ..addAll(ids);
      }),
      applyStatus: (s) => setState(() => _draftStatus = s),
      applyStartDate: (d) => setState(() => _startDate = d),
      applyDueDate: (d) => setState(() => _endDate = d),
    );
  }

  void _ensureProjectAi() {
    _projectAi ??= AsanaTaskAiController(
      mode: AsanaTaskAiAssistantMode.projectFields,
      readOnly: () => _saving,
      projectSnapshot: () => _aiFormSnapshot(context.read<AppState>()),
      projectApply: _aiApplyHandlers(),
    );
  }

  Widget _aiSuggestions(AsanaTaskAiFieldKey key) {
    final c = _projectAi;
    if (c == null) return const SizedBox.shrink();
    return AsanaTaskAiInlineSuggestions(
      controller: c,
      fieldKey: key,
      palette: widget.palette,
    );
  }

  Widget? _buildSlideFooter({
    required AsanaSlideChrome chrome,
    required bool canEdit,
    required ProjectRecord p,
    required AppState state,
  }) {
    if (!canEdit) return null;
    final buttons = <Widget>[
      FilledButton(
        onPressed: _saving ? null : () => _save(state, p),
        style: AsanaTaskDetailActionStyles.updateFilled(widget.palette),
        child: Text(_saving ? 'Saving…' : 'Update'),
      ),
    ];
    if (_canMarkProjectComplete(p)) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _markCompleted(state, p),
          style: AsanaTaskDetailActionStyles.successFilled(),
          child: const Text('Mark as Completed'),
        ),
      );
    }
    if (_canDeleteProject(p)) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _confirmDeleteProject(state),
          style: AsanaTaskDetailActionStyles.deleteFilled(),
          child: const Text('Delete'),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_projectAi != null)
          AsanaTaskAiDock(
            controller: _projectAi!,
            palette: widget.palette,
            footerBorder: chrome.footerBorder,
          ),
        AsanaDetailSlideFooter(
          backgroundColor: chrome.footer,
          borderColor: chrome.footerBorder,
          child: Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: buttons,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save(AppState state, ProjectRecord p) async {
    if (!_isCreator(p)) return;
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
    for (final id in _picAssigneeIds) {
      if (!_assigneeIds.contains(id)) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Invalid PIC',
          content: 'Each PIC must be one of the project assignees.',
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

    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final slots =
          await SupabaseService.assigneeSlotsForTask(_assigneeIds.toList());
      final picUuids = <String>[];
      for (final key in _picAssigneeIds) {
        final u = await SupabaseService.resolveStaffRowIdForAssigneeKey(key);
        if (u != null && u.trim().isNotEmpty) picUuids.add(u.trim());
      }
      if (picUuids.isEmpty) {
        if (!mounted) return;
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not resolve PIC',
          content: 'Could not resolve PIC staff ids.',
          palette: widget.palette,
        );
        return;
      }
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        name: name,
        description: _descController.text.trim(),
        assigneeSlots: slots,
        picStaffUuids: picUuids,
        startDate: _startDate,
        endDate: _endDate,
        clearStartDate: _startDate == null,
        clearEndDate: _endDate == null,
        status: _effectiveStatus(p),
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not update project',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      await _loadProject();
      _projectAi?.clearAllSuggestions();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(widget.palette);
    if (_loading) {
      return ColoredBox(
        color: chrome.body,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final p = _project;
    if (p == null) {
      return ColoredBox(
        color: chrome.body,
        child: const Center(child: Text('Project not found')),
      );
    }

    final state = context.watch<AppState>();
    final canEdit = _isCreator(p);
    if (canEdit) _ensureProjectAi();
    final creatorLabel = (p.createByDisplayName ?? '').trim().isNotEmpty
        ? p.createByDisplayName!.trim()
        : AsanaProjectFilter.creatorLine(p, state);
    final assigneesReadOnly = AsanaProjectFilter.assigneesLine(p, state);
    final picReadOnly = AsanaProjectFilter.picLine(p, state);

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: _buildSlideFooter(
        chrome: chrome,
        canEdit: canEdit,
        p: p,
        state: state,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsanaHoverTextField(
            controller: _nameController,
            canEdit: canEdit,
            readOnly: _saving,
            maxLines: 3,
            minLines: 1,
            style: asanaDetailTitleStyle(context),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.taskName),
          const SizedBox(height: 12),
          AsanaDetailLabelValue(
            label: 'Description',
            child: AsanaHoverTextField(
              controller: _descController,
              canEdit: canEdit,
              readOnly: _saving,
              maxLines: 8,
              minLines: 2,
              style: asanaDetailMultilineValueStyle(context),
              hintText: 'Please fill in project description',
            ),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.description),
          AsanaDetailTwoColumnRow(
            label: 'Creator',
            child: AsanaDetailPlainValue(text: creatorLabel),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Assignees',
            child: KeyedSubtree(
              key: _detailPopupWidthAlignKey,
              child: canEdit
                  ? AsanaAssigneeFieldValue(
                      anchorLink: _assigneeAnchorLink,
                      assignees: _rowsForIds(_assigneeIds, state),
                      canEdit: !_saving,
                      onOpenPicker: _pickAssignees,
                      onRemove: _removeAssignee,
                    )
                  : AsanaDetailPlainValue(text: assigneesReadOnly),
            ),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.assignees),
          AsanaDetailTwoColumnRow(
            label: 'PIC',
            child: canEdit
                ? AsanaAssigneeFieldValue(
                    anchorLink: _picAnchorLink,
                    assignees: _rowsForIds(_picAssigneeIds, state),
                    canEdit: !_saving && _assigneeIds.isNotEmpty,
                    emptyPlaceholder: _assigneeIds.isEmpty
                        ? 'Select assignees first'
                        : 'Select PIC(s)',
                    onOpenPicker: _pickPics,
                    onRemove: _removePic,
                  )
                : AsanaDetailPlainValue(text: picReadOnly),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.pic),
          AsanaDetailTwoColumnRow(
            label: 'Status',
            child: canEdit
                ? CompositedTransformTarget(
                    link: _statusAnchorLink,
                    child: MouseRegion(
                      cursor: _saving
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _saving
                            ? null
                            : () => _pickStatus(context),
                        child: AsanaDetailStatusPill(status: _effectiveStatus(p)),
                      ),
                    ),
                  )
                : AsanaDetailStatusPill(status: _effectiveStatus(p)),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.projectStatus),
          AsanaDetailTwoColumnRow(
            label: 'Start date',
            child: AsanaHoverTapValue(
              value: _formatDate(_startDate),
              canEdit: canEdit && !_saving,
              emptyPlaceholder: '-',
              onTap: canEdit && !_saving ? _pickStartDate : null,
              onClear: canEdit && !_saving
                  ? () => setState(() => _startDate = null)
                  : null,
            ),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.startDate),
          AsanaDetailTwoColumnRow(
            label: 'Due date',
            child: AsanaHoverTapValue(
              value: _formatDate(_endDate),
              canEdit: canEdit && !_saving,
              emptyPlaceholder: '-',
              onTap: canEdit && !_saving ? _pickDueDate : null,
              onClear: canEdit && !_saving
                  ? () => setState(() => _endDate = null)
                  : null,
            ),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
          if ((p.updateByDisplayName ?? '').trim().isNotEmpty)
            AsanaDetailTwoColumnRow(
              label: 'Last updated by',
              child: AsanaDetailPlainValue(
                text: p.updateByDisplayName!.trim(),
              ),
            ),
          if (p.updateDate != null)
            AsanaDetailTwoColumnRow(
              label: 'Last updated',
              child: AsanaDetailPlainValue(text: _formatDate(p.updateDate)),
            ),
        ],
      ),
    );
  }
}
