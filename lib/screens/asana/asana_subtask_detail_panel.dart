import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/singular_subtask.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/backend_api.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../app_bootstrap.dart';
import '../asana_landing_screen.dart';
import 'asana_attachment_draft_tile.dart';
import 'asana_attachment_menu.dart';
import 'asana_anchored_overlay.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_task_ai_assistant.dart';
import 'asana_value_chips.dart';

class _SubtaskAttachmentDraft {
  _SubtaskAttachmentDraft({
    this.id,
    String? url,
    String? desc,
    this.pendingBytes,
    this.pendingFilename,
  })  : urlController = TextEditingController(text: url ?? ''),
        descController = TextEditingController(text: desc ?? '');

  final String? id;
  final TextEditingController urlController;
  final TextEditingController descController;
  Uint8List? pendingBytes;
  String? pendingFilename;

  bool get isPendingFile => pendingBytes != null && pendingBytes!.isNotEmpty;

  void dispose() {
    urlController.dispose();
    descController.dispose();
  }
}

class AsanaSubtaskDetailPanel extends StatefulWidget {
  const AsanaSubtaskDetailPanel({
    super.key,
    this.subtaskId,
    this.createMode = false,
    this.parentTaskId,
    required this.palette,
    this.onClose,
    this.onCreated,
    this.onChanged,
  }) : assert(createMode ? parentTaskId != null : subtaskId != null);

  final String? subtaskId;
  final bool createMode;
  final String? parentTaskId;
  final AsanaLandingPalette palette;
  final VoidCallback? onClose;
  final void Function(String subtaskId)? onCreated;
  final VoidCallback? onChanged;

  @override
  State<AsanaSubtaskDetailPanel> createState() => _AsanaSubtaskDetailPanelState();
}

class _AsanaSubtaskDetailPanelState extends State<AsanaSubtaskDetailPanel> {
  SingularSubtask? _subtask;
  Task? _parentTask;
  bool _loading = true;
  bool _saving = false;
  bool _createdInPlace = false;

  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _reasonController = TextEditingController();
  final _commentController = TextEditingController();
  final List<_SubtaskAttachmentDraft> _attachments = [];

  final Set<String> _assigneeIds = {};
  String? _picAssigneeId;
  int _localPriority = priorityStandard;
  DateTime? _startDate;
  DateTime? _dueDate;
  String? _draftStatus;
  DateTime _anchorCreateDate = HkTime.todayDateOnlyHk();
  
  bool _assigneePickerLoading = false;
  String? _assigneePickerError;
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  final ValueNotifier<AsanaAssigneePickerSnapshot> _assigneeSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));

  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _priorityAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  final LayerLink _attachmentAddAnchorLink = LayerLink();
  int _anchoredPickerReopenBlockedUntilMs = 0;
  Set<String> _holidaySkipYmd = {};

  AsanaTaskAiController? _subtaskAi;

  bool get _effectiveCreateMode => widget.createMode && !_createdInPlace;

  @override
  void initState() {
    super.initState();
    if (_effectiveCreateMode) {
      _loadHolidaysOnly().then((_) {
        if (mounted) {
          setState(() {
            _resetCreateDraft();
          });
          _loadAssigneeStaff();
        }
      });
    } else {
      _load();
    }
  }

  Future<void> _loadHolidaysOnly() async {
    if (SupabaseConfig.isConfigured) {
      try {
        final rows = await SupabaseService.fetchCalendarHolidaysBetween(
          HkTime.todayDateOnlyHk().subtract(const Duration(days: 30)),
          HkTime.todayDateOnlyHk().add(const Duration(days: 365)),
        );
        _holidaySkipYmd = HkTime.holidaySkipYmdFromCalendarRows(rows);
      } catch (_) {}
    }
  }

  @override
  void didUpdateWidget(covariant AsanaSubtaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtaskId != widget.subtaskId || oldWidget.createMode != widget.createMode) {
      if (_effectiveCreateMode) {
        _createdInPlace = false;
        _resetCreateDraft();
        _loadAssigneeStaff();
      } else {
        _load();
      }
    }
  }

  void _resetCreateDraft() {
    _nameController.clear();
    _descController.clear();
    _reasonController.clear();
    _commentController.clear();
    _clearAttachments();
    _assigneeIds.clear();
    _picAssigneeId = null;
    _localPriority = priorityStandard;
    _draftStatus = 'Incomplete';
    final today = HkTime.todayDateOnlyHk();
    _anchorCreateDate = HkTime.firstBusinessDayOnOrAfter(today, _holidaySkipYmd);
    _startDate = _anchorCreateDate;
    _dueDate = _defaultDueForPriority(_localPriority);
    _subtask = null;
    _loading = false;
  }

  DateTime _defaultDueForPriority(int priority) {
    final days = priority == priorityUrgent ? 1 : 3;
    return HkTime.addBusinessDaysAfter(_anchorCreateDate, days, _holidaySkipYmd);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _reasonController.dispose();
    _commentController.dispose();
    _clearAttachments();
    _subtaskAi?.dispose();
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (SupabaseConfig.isConfigured) {
      try {
        final rows = await SupabaseService.fetchCalendarHolidaysBetween(
          HkTime.todayDateOnlyHk().subtract(const Duration(days: 30)),
          HkTime.todayDateOnlyHk().add(const Duration(days: 365)),
        );
        _holidaySkipYmd = HkTime.holidaySkipYmdFromCalendarRows(rows);
      } catch (_) {}
      
      final row = await SupabaseService.fetchSubtaskById(widget.subtaskId!);
      if (mounted) {
        setState(() {
          _subtask = row;
          _nameController.text = row?.subtaskName ?? '';
          _descController.text = row?.description ?? '';
          _reasonController.text = row?.changeDueReason ?? '';
          _assigneeIds.clear();
          if (row != null) _assigneeIds.addAll(row.assigneeIds.where((e) => e.isNotEmpty));
          _picAssigneeId = row?.pic;
          if (_picAssigneeId?.isEmpty == true) _picAssigneeId = null;
          _localPriority = row?.priority ?? priorityStandard;
          _startDate = row?.startDate;
          _dueDate = row?.dueDate;
          _draftStatus = row?.status;
        });
        _loadAssigneeStaff();
        _loadAttachments(row);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _clearAttachments() {
    for (final a in _attachments) {
      a.dispose();
    }
    _attachments.clear();
  }

  Future<void> _loadAttachments(SingularSubtask? row) async {
    if (row == null || !SupabaseConfig.isConfigured) return;
    try {
      final rows = await SupabaseService.fetchSubtaskAttachments(row.id);
      if (!mounted) return;
      setState(() {
        _clearAttachments();
        for (final r in rows) {
          _attachments.add(
            _SubtaskAttachmentDraft(
              id: r.id,
              url: r.content,
              desc: r.description,
            ),
          );
        }
      });
    } catch (_) {}
  }

  String _nameFor(AppState state, String? key) {
    final k = key?.trim();
    if (k == null || k.isEmpty) return '';
    return state.assigneeById(k)?.name ?? k;
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
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

  void _addChange(
    List<Map<String, String>> changes,
    String field,
    String oldValue,
    String newValue,
  ) {
    if (oldValue.trim() == newValue.trim()) return;
    changes.add({'field': field, 'value': newValue});
  }

  String _namesFor(AppState state, Iterable<String> ids) {
    return ids
        .map((id) => _nameFor(state, id))
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
  }

  List<Map<String, String>> _subtaskChangesForEmail(
    AppState state,
    SingularSubtask s,
  ) {
    final changes = <Map<String, String>>[];
    _addChange(changes, 'subtaskName', s.subtaskName, _nameController.text.trim());
    _addChange(changes, 'description', s.description, _descController.text.trim());
    _addChange(
      changes,
      'assignees',
      _namesFor(state, s.assigneeIds),
      _namesFor(state, _assigneeIds),
    );
    _addChange(
      changes,
      'priority',
      priorityToDisplayName(s.priority),
      priorityToDisplayName(_localPriority),
    );
    _addChange(changes, 'startDate', _date(s.startDate), _date(_startDate));
    _addChange(changes, 'dueDate', _date(s.dueDate), _date(_dueDate));
    return changes;
  }

  bool _isCreator(AppState state) {
    if (_effectiveCreateMode) return true;
    final s = _subtask;
    if (s == null) return false;
    final myUuid = state.userStaffId?.trim();
    if (myUuid == null || myUuid.isEmpty) return false;
    return s.createByStaffId?.trim() == myUuid;
  }

  bool _isPic(AppState state, SingularSubtask s) {
    final mine = state.userStaffAppId?.trim();
    final pic = s.pic?.trim();
    return mine != null && mine.isNotEmpty && pic != null && mine == pic;
  }

  bool _isAssignee(AppState state, SingularSubtask s) {
    final mine = state.userStaffAppId?.trim();
    return mine != null && mine.isNotEmpty && s.assigneeIds.contains(mine);
  }

  bool _canMarkComplete(SingularSubtask s) {
    if (s.isDeleted) return false;
    if (s.status.trim().toLowerCase() == 'completed') return false;
    if (s.submission?.trim().toLowerCase() == 'submitted') return false;
    return true;
  }

  bool _canUndoAcceptOrReturn(SingularSubtask s) {
    if (s.isDeleted) return false;
    final submission = s.submission?.trim().toLowerCase() ?? '';
    return submission == 'accepted' || submission == 'returned';
  }

  bool _canPicSubmit(SingularSubtask s) {
    if (s.isDeleted) return false;
    final submission = s.submission?.trim().toLowerCase() ?? '';
    if (submission.isEmpty || submission == 'pending') return true;
    if (submission == 'returned') return true;
    return submission != 'submitted' && submission != 'accepted';
  }

  void _publishAssigneeSnapshot() {
    _assigneeSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForRole(),
      staff: List<StaffForAssignment>.from(_pickerStaff),
      error: _assigneePickerError,
    );
    _picSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForRole(),
      staff: _pickerStaff.where((s) => _assigneeIds.contains(s.assigneeId)).toList(),
      error: _assigneePickerError,
    );
  }

  Future<void> _loadAssigneeStaff() async {
    if (!SupabaseConfig.isConfigured) {
      _assigneePickerLoading = false;
      _assigneePickerError = 'Supabase not configured';
      _pickerTeams = [];
      _pickerStaff = [];
      _publishAssigneeSnapshot();
      if (mounted) setState(() {});
      return;
    }
    _assigneePickerLoading = true;
    _assigneePickerError = null;
    _publishAssigneeSnapshot();
    if (mounted) setState(() {});
    try {
      final data = await SupabaseService.fetchStaffAssigneePickerData();
      if (!mounted) return;
      _assigneePickerLoading = false;
      if (data != null) {
        _pickerTeams = data.teams;
        final parentAssignees = Set<String>.from(
          _parentTask?.assigneeIds ?? const <String>[],
        );
        _pickerStaff = parentAssignees.isEmpty
            ? data.staff
            : data.staff
                .where((s) => parentAssignees.contains(s.assigneeId))
                .toList();
      } else {
        _pickerTeams = [];
        _pickerStaff = [];
      }
      _publishAssigneeSnapshot();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _assigneePickerLoading = false;
      _assigneePickerError = e.toString();
      _pickerTeams = [];
      _pickerStaff = [];
      _publishAssigneeSnapshot();
      setState(() {});
    }
  }

  List<TeamOptionRow> _pickerTeamsForRole() {
    final teamIds = _pickerStaff
        .map((s) => s.teamId)
        .whereType<String>()
        .where((t) => t.isNotEmpty)
        .toSet();
    if (teamIds.isEmpty) return List<TeamOptionRow>.from(_pickerTeams);
    return _pickerTeams.where((t) => teamIds.contains(t.teamId)).toList();
  }

  void _syncPicAfterAssigneesChange() {
    if (_assigneeIds.isEmpty) {
      _picAssigneeId = null;
    } else if (_assigneeIds.length == 1) {
      _picAssigneeId = _assigneeIds.first;
    } else if (_picAssigneeId != null && !_assigneeIds.contains(_picAssigneeId)) {
      _picAssigneeId = null;
    }
    _publishAssigneeSnapshot();
  }

  String _labelForAssigneeId(String id, AppState state) {
    for (final s in _pickerStaff) {
      if (s.assigneeId == id) return s.name;
    }
    return state.assigneeById(id)?.name ?? id;
  }

  List<AsanaFilterCheckboxOption> _parentAssigneeOptions(AppState state) {
    final ids = _parentTask?.assigneeIds ?? const <String>[];
    return [
      for (final id in ids)
        AsanaFilterCheckboxOption(
          key: id,
          label: state.assigneeById(id)?.name ?? id,
        ),
    ]..sort((a, b) => a.label.compareTo(b.label));
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch > _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  List<({String id, String name})> _assigneeRowsForDisplay(AppState state) {
    final rows = _assigneeIds
        .map((id) => (id: id, name: _labelForAssigneeId(id, state)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  void _removeAssignee(String assigneeId) {
    setState(() {
      _assigneeIds.remove(assigneeId);
      _syncPicAfterAssigneesChange();
    });
  }

  void _removePic(String assigneeId) {
    setState(() => _picAssigneeId = null);
  }

  Future<void> _pickAssignees(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    final options = _parentAssigneeOptions(context.read<AppState>());
    if (options.isNotEmpty) {
      final selection = await showParentAssigneeGridMenu(
        anchorLink: _assigneeAnchorLink,
        anchorContext: anchorContext,
        options: options,
        initialSelection: _assigneeIds,
      );
      _blockAnchoredPickerReopen();
      if (!mounted || selection == null) return;
      setState(() {
        _assigneeIds
          ..clear()
          ..addAll(selection.where((id) => options.any((o) => o.key == id)));
        _syncPicAfterAssigneesChange();
      });
      return;
    }
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

  Future<Set<String>?> showParentAssigneeGridMenu({
    required LayerLink anchorLink,
    required BuildContext anchorContext,
    required List<AsanaFilterCheckboxOption> options,
    required Set<String> initialSelection,
  }) async {
    Set<String>? picked;
    final width = MediaQuery.sizeOf(anchorContext).width >= 900 ? 420.0 : 320.0;
    await showAsanaAnchoredOverlay(
      anchorLink: anchorLink,
      anchorContext: anchorContext,
      panelWidth: width,
      whenClosed: _blockAnchoredPickerReopen,
      builder: (ctx, close) => _ParentAssigneeGridMenu(
        options: options,
        initialSelection: initialSelection,
        onDone: (selection) {
          picked = selection;
          close();
        },
      ),
    );
    return picked;
  }

  Future<void> _pickPic(BuildContext anchorContext, AppState state) async {
    if (!_canOpenAnchoredPicker) return;
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
    if (!mounted || choice == null) return;
    setState(() => _picAssigneeId = choice);
  }

  Future<void> _pickStartDueRange(BuildContext anchorContext) async {
    final picked = await showAsanaAnchoredDateRangePicker(
      anchorContext: anchorContext,
      start: _startDate,
      end: _dueDate,
      helpText: 'Start and due date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked.start;
      _dueDate = picked.end;
    });
  }

  Future<void> _pickPriority(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    final choice = await showAsanaAnchoredOptionMenu<int>(
      anchorLink: _priorityAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: priorityOptions
          .map(
            (p) => AsanaAnchoredOption(
              value: p,
              label: priorityToDisplayName(p),
            ),
          )
          .toList(),
    );
    if (choice == null || !mounted) return;
    setState(() {
      _localPriority = choice;
    });
  }

  bool _needsChangeDueReason() {
    if (_startDate == null || _dueDate == null) return false;
    return dueDateExceedsPolicyForPriority(
      _startDate,
      _dueDate,
      _localPriority,
      calendarHolidayYmdSkip: _holidaySkipYmd,
    );
  }

  Future<void> _pickStatus(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    const options = [
      AsanaAnchoredOption(value: 'Incomplete', label: 'Incomplete'),
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

  String _buildParentContext(Task? p, AppState state) {
    if (p == null) return '';
    return '''
Task: ${p.name.trim()}
Description: ${p.description.trim()}
Project: ${p.projectName?.trim() ?? '(none)'}
Assignees: ${p.assigneeIds.map((id) => _nameFor(state, id)).join(', ')}
PIC: ${_nameFor(state, p.pic)}
Status: ${p.dbStatus ?? 'Incomplete'}
Priority: ${priorityToDisplayName(p.priority)}
Start: ${_date(p.startDate)}
Due: ${_date(p.endDate)}
Allowable sub-task assignees: ${p.assigneeIds.map((id) => _nameFor(state, id)).join(', ')}
''';
  }

  List<({String url, String description})> _websiteAttachmentsForAi() {
    return _attachments
        .map(
          (a) => (
            url: a.urlController.text.trim(),
            description: a.descController.text.trim(),
          ),
        )
        .where((a) => a.url.isNotEmpty)
        .toList();
  }

  void _ensureSubtaskAi(AppState state) {
    if (!_effectiveCreateMode && _subtask == null) return;
    final p = _parentTask;
    
    _subtaskAi ??= AsanaTaskAiController(
      mode: AsanaTaskAiAssistantMode.subtaskFields,
      readOnly: () => _saving,
      auditContext: () => AsanaAiAuditContext(
        entityType: 'subtask',
        entityId: _effectiveCreateMode ? null : _subtask?.id,
        staffId: state.userStaffId,
        staffDisplayName: _nameFor(state, state.userStaffAppId),
        actionType: _effectiveCreateMode ? 'create' : 'update',
      ),
      subtaskSnapshot: () => AsanaSubtaskAiFormSnapshot(
        subtaskName: _nameController.text.trim(),
        currentComment: _commentController.text.trim(),
        canEditName: _effectiveCreateMode || _isCreator(state),
        canEditReason: _effectiveCreateMode || _isCreator(state),
        reason: _reasonController.text.trim(),
        parentTaskContext: _buildParentContext(p, state),
        websiteAttachments: _websiteAttachmentsForAi(),
      ),
      onApplySubtaskName: (v) => setState(() => _nameController.text = v),
      onApplyReason: (v) => setState(() => _reasonController.text = v),
      onApplyComment: (v) => setState(() => _commentController.text = v),
      onApplyWebsiteLink: _applyWebsiteLinkFromAi,
    );
  }

  void _applyWebsiteLinkFromAi(String url, String desc) {
    setState(() {
      _attachments.add(_SubtaskAttachmentDraft(url: url, desc: desc));
    });
  }

  List<({String? content, String? description})> _attachmentPayload() {
    return _attachments
        .map(
          (a) => (
            content: a.urlController.text.trim().isEmpty
                ? null
                : a.urlController.text.trim(),
            description: a.descController.text.trim().isEmpty
                ? null
                : a.descController.text.trim(),
          ),
        )
        .where((r) => (r.content ?? '').isNotEmpty)
        .toList();
  }

  Future<void> _save() async {
    final s = _subtask;
    if (!_effectiveCreateMode && s == null) return;
    final state = context.read<AppState>();
    
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Sub-task name required',
        content: 'Please fill in the sub-task name before continuing.',
        palette: widget.palette,
      );
      return;
    }
    if ((_effectiveCreateMode || _isCreator(state)) && _assigneeIds.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Assignee required',
        content: 'Select at least one assignee before continuing.',
        palette: widget.palette,
      );
      return;
    }
    if ((_effectiveCreateMode || _isCreator(state)) &&
        (_picAssigneeId == null || !_assigneeIds.contains(_picAssigneeId))) {
      await showAsanaInfoDialog(
        context: context,
        title: 'PIC required',
        content: 'Choose a PIC from the sub-task assignees before continuing.',
        palette: widget.palette,
      );
      return;
    }
    if (_needsChangeDueReason() && _reasonController.text.trim().isEmpty) {
      await showAsanaConfirmDialog(
        context: context,
        title: 'Reason required',
        content:
            'Please explain why this sub-task needs more time than expected before continuing.',
        confirmText: 'OK',
        palette: widget.palette,
      );
      return;
    }

    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      if (_effectiveCreateMode) {
        final commentText = _commentController.text.trim();
        final ins = await SupabaseService.insertSubtaskRow(
          taskId: widget.parentTaskId!,
          subtaskName: newName,
          description: _descController.text.trim(),
          priorityDisplay: priorityToDisplayName(_localPriority),
          startDate: _startDate,
          dueDate: _dueDate,
          assigneeStaffUuids: _assigneeIds.toList(),
          picStaffUuid: _picAssigneeId ?? '',
          creatorStaffLookupKey: state.userStaffAppId,
          initialComment: commentText.isNotEmpty ? commentText : null,
          changeDueReason: _needsChangeDueReason() ? _reasonController.text.trim() : null,
        );
        if (ins.error != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not create sub-task',
            content: ins.error!,
            palette: widget.palette,
          );
          return;
        }
        final newSubtaskId = ins.subtaskId;
        if (newSubtaskId != null && newSubtaskId.isNotEmpty) {
          _subtaskAi?.attachCreatedEntityId(newSubtaskId);
          final uploadErr =
              await _uploadPendingCreateAttachments(newSubtaskId, state);
          if (uploadErr != null && mounted) {
            await showAsanaInfoDialog(
              context: context,
              title: 'Attachment upload failed',
              content: uploadErr,
              palette: widget.palette,
            );
            return;
          }
        }
        if (newSubtaskId != null && newSubtaskId.isNotEmpty && _attachments.isNotEmpty) {
          final attErr = await SupabaseService.replaceSubtaskAttachments(
            subtaskId: newSubtaskId,
            taskId: widget.parentTaskId!,
            rows: _attachmentPayload(),
          );
          if (attErr != null && mounted) {
            await showAsanaInfoDialog(
              context: context,
              title: 'Could not save attachments',
              content: attErr,
              palette: widget.palette,
            );
            return;
          }
        }
        if (mounted) {
          if (newSubtaskId != null && newSubtaskId.isNotEmpty) {
            widget.onCreated?.call(newSubtaskId);
            await _notifyEmail(
              'Sub-task assignment email',
              (token) => BackendApi().notifySubtaskAssigned(
                idToken: token,
                subtaskId: newSubtaskId,
              ),
            );
            final row = await SupabaseService.fetchSubtaskById(newSubtaskId);
            if (!mounted) return;
            if (row != null) {
              _subtaskAi?.clearAllSuggestions();
              setState(() {
                _createdInPlace = true;
                _subtask = row;
                _loading = false;
                _nameController.text = row.subtaskName;
                _descController.text = row.description;
                _reasonController.text = row.changeDueReason ?? '';
                _draftStatus = row.status;
              });
              await _loadAttachments(row);
            }
          } else if (widget.onClose != null) {
            widget.onClose!();
          }
        }
        return;
      }

      final isCreator = _isCreator(state);
      final changesForEmail = isCreator
          ? _subtaskChangesForEmail(state, s!)
          : <Map<String, String>>[];
      if (isCreator) {
        final err = await SupabaseService.updateSubtaskRow(
          subtaskId: s!.id,
          subtaskName: newName,
          description: _descController.text.trim(),
          priorityDisplay: priorityToDisplayName(_localPriority),
          status: _draftStatus,
          clearStartDate: _startDate == null,
          startDate: _startDate,
          clearDueDate: _dueDate == null,
          dueDate: _dueDate,
          assigneeSlots: _assigneeIds.toList(),
          picStaffLookupKey: _picAssigneeId ?? '',
          updateChangeDueReason: true,
          changeDueReason: _needsChangeDueReason() ? _reasonController.text.trim() : null,
          updaterStaffLookupKey: state.userStaffAppId,
        );
        if (err != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not update sub-task',
            content: err,
            palette: widget.palette,
          );
          return;
        }
      }

      final commentText = _commentController.text.trim();
      String? commentId;
      if (commentText.isNotEmpty) {
        final ins = await SupabaseService.insertSubtaskCommentRow(
          subtaskId: s!.id,
          description: commentText,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (ins.error != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not add comment',
            content: ins.error!,
            palette: widget.palette,
          );
        } else {
          commentId = ins.commentId;
          _commentController.clear();
        }
      }
      if (isCreator) {
        final attErr = await SupabaseService.replaceSubtaskAttachments(
          subtaskId: s!.id,
          taskId: s.taskId,
          rows: _attachmentPayload(),
        );
        if (attErr != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not save attachments',
            content: attErr,
            palette: widget.palette,
          );
          return;
        }
      }
      
      _subtaskAi?.clearAllSuggestions();
      await _load();
      widget.onChanged?.call();
      if (isCreator) {
        await _notifyEmail(
          'Sub-task update email',
          (token) => BackendApi().notifySubtaskUpdated(
            idToken: token,
            subtaskId: s!.id,
            changes: changesForEmail,
            commentAddedText: commentText,
            subtaskCommentId: commentId,
          ),
        );
      } else if (commentId != null) {
        await _notifyEmail(
          'Sub-task comment email',
          (token) => BackendApi().notifySubtaskCommentAdded(
            idToken: token,
            commentId: commentId!,
          ),
        );
      }
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSubtask() async {
    final s = _subtask;
    if (s == null || !_isCreator(context.read<AppState>())) return;
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Delete sub-task?',
      content: 'This marks the sub-task as deleted.',
      confirmText: 'Delete',
      isDestructive: true,
      palette: widget.palette,
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.markSubtaskDeleted(
        subtaskId: s.id,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not delete sub-task',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      widget.onChanged?.call();
      if (mounted) widget.onClose?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markCompleted(AppState state, SingularSubtask s) async {
    await _setWorkflowState(
      state: state,
      subtask: s,
      status: 'Completed',
      submission: 'Accepted',
      completionDateAt: s.submitDate ?? DateTime.now().toUtc(),
      errorTitle: 'Could not mark sub-task completed',
    );
    if (s.submission?.trim() == 'Submitted') {
      await _notifyEmail(
        'Sub-task accepted email',
        (token) => BackendApi().notifySubtaskAccepted(
          idToken: token,
          subtaskId: s.id,
        ),
      );
    }
  }

  Future<void> _submitSubtask(AppState state, SingularSubtask s) async {
    final commentText = _commentController.text.trim();
    if (_attachments.isEmpty && commentText.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Submission content required',
        content: 'Add an attachment and/or comment before submitting.',
        palette: widget.palette,
      );
      return;
    }
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final attErr = await SupabaseService.replaceSubtaskAttachments(
        subtaskId: s.id,
        taskId: s.taskId,
        rows: _attachmentPayload(),
      );
      if (attErr != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not save attachments',
          content: attErr,
          palette: widget.palette,
        );
        return;
      }
      if (commentText.isNotEmpty) {
        final ins = await SupabaseService.insertSubtaskCommentRow(
          subtaskId: s.id,
          description: commentText,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (ins.error != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not add comment',
            content: ins.error!,
            palette: widget.palette,
          );
          return;
        }
        _commentController.clear();
      }
      final isCreator = _isCreator(state);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: s.id,
        submission: 'Submitted',
        updaterStaffLookupKey: isCreator ? state.userStaffAppId : null,
        stampSubmitDateNow: true,
        bumpSubtaskRowAuditFields: isCreator,
      );
      if (err != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not submit sub-task',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      _subtaskAi?.clearAllSuggestions();
      await _load();
      widget.onChanged?.call();
      await _notifyEmail(
        'Sub-task submission email',
        (token) => BackendApi().notifySubtaskSubmission(
          idToken: token,
          subtaskId: s.id,
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _returnSubtask(AppState state, SingularSubtask s) async {
    await _setWorkflowState(
      state: state,
      subtask: s,
      submission: 'Returned',
      errorTitle: 'Could not return sub-task',
    );
    await _notifyEmail(
      'Sub-task returned email',
      (token) => BackendApi().notifySubtaskReturned(
        idToken: token,
        subtaskId: s.id,
      ),
    );
  }

  Future<void> _undoAcceptOrReturn(AppState state, SingularSubtask s) async {
    await _setWorkflowState(
      state: state,
      subtask: s,
      status: 'Incomplete',
      submission: 'Pending',
      clearCompletionDate: true,
      errorTitle: 'Could not undo sub-task status',
    );
  }

  Future<void> _undoDeleted(AppState state, SingularSubtask s) async {
    await _setWorkflowState(
      state: state,
      subtask: s,
      status: 'Incomplete',
      errorTitle: 'Could not restore sub-task',
    );
  }

  Future<void> _setWorkflowState({
    required AppState state,
    required SingularSubtask subtask,
    String? status,
    String? submission,
    DateTime? completionDateAt,
    bool clearCompletionDate = false,
    required String errorTitle,
  }) async {
    setState(() => _saving = true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final isCreator = _isCreator(state);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: subtask.id,
        status: status,
        submission: submission,
        updaterStaffLookupKey: isCreator ? state.userStaffAppId : null,
        completionDateAt: completionDateAt,
        clearCompletionDate: clearCompletionDate,
        bumpSubtaskRowAuditFields: isCreator,
      );
      if (err != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: errorTitle,
          content: err,
          palette: widget.palette,
        );
        return;
      }
      _subtaskAi?.clearAllSuggestions();
      await _load();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _aiSuggestions(AsanaTaskAiFieldKey key) {
    final c = _subtaskAi;
    if (c == null) return const SizedBox.shrink();
    return AsanaTaskAiInlineSuggestions(
      controller: c,
      fieldKey: key,
      palette: widget.palette,
    );
  }

  Future<void> _showAttachmentMenu(BuildContext anchorContext) async {
    final result = await showAsanaAnchoredAttachmentMenu(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted) return;
    if (result is AsanaAttachmentUploadFile) {
      if (widget.createMode) {
        final picked = await FirebaseAttachmentUploadService.pickFileForUpload();
        if (!mounted) return;
        if (picked.error != null) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Attachment upload failed',
            content: picked.error!,
            palette: widget.palette,
          );
          return;
        }
        if (picked.bytes == null) return;
        setState(() {
          _attachments.add(
            _SubtaskAttachmentDraft(
              pendingBytes: picked.bytes,
              pendingFilename: picked.label,
              desc: picked.label,
            ),
          );
        });
      } else {
        final s = _subtask;
        if (s == null) return;
        final state = context.read<AppState>();
        final r = await FirebaseAttachmentUploadService.pickUploadForSubtask(
          s.id,
          aclStaffKeys: _subtaskAttachmentAclKeys(state),
        );
        if (!mounted) return;
        if (r.error != null) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Attachment upload failed',
            content: r.error!,
            palette: widget.palette,
          );
          return;
        }
        if (r.url == null) return;
        setState(() {
          _attachments.add(_SubtaskAttachmentDraft(url: r.url, desc: r.label));
        });
      }
    } else if (result is AsanaAttachmentWebsiteLink) {
      setState(() {
        _attachments.add(
          _SubtaskAttachmentDraft(
            url: result.url,
            desc: result.description,
          ),
        );
      });
    }
  }

  List<String?> _subtaskAttachmentAclKeys(AppState state) {
    return [
      state.userStaffAppId,
      _parentTask?.createByAssigneeKey,
      _picAssigneeId,
      ..._assigneeIds,
      ...?_parentTask?.assigneeIds,
    ];
  }

  Future<String?> _uploadPendingCreateAttachments(
    String subtaskId,
    AppState state,
  ) async {
    for (final draft in _attachments) {
      if (!draft.isPendingFile) continue;
      final r = await FirebaseAttachmentUploadService.uploadBytesForSubtask(
        subtaskId,
        bytes: draft.pendingBytes!,
        originalFilename: draft.pendingFilename ?? 'attachment',
        aclStaffKeys: _subtaskAttachmentAclKeys(state),
      );
      if (r.error != null) return r.error;
      if (r.url == null || r.url!.trim().isEmpty) {
        return 'File upload did not return a download link.';
      }
      draft.urlController.text = r.url!.trim();
      if (draft.descController.text.trim().isEmpty) {
        draft.descController.text =
            r.label?.trim() ?? draft.pendingFilename ?? 'attachment';
      }
      draft.pendingBytes = null;
      draft.pendingFilename = null;
    }
    return null;
  }

  Future<void> _editAttachmentLink(
    BuildContext anchorContext,
    _SubtaskAttachmentDraft draft,
  ) async {
    final result = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: anchorContext,
      initialUrl: draft.urlController.text,
      initialDescription: draft.descController.text,
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || result == null) return;
    setState(() {
      draft.urlController.text = result.url;
      draft.descController.text = result.description;
    });
  }

  void _removeAttachment(_SubtaskAttachmentDraft draft) {
    setState(() {
      _attachments.remove(draft);
      draft.dispose();
    });
  }

  Widget _attachmentTile(
    BuildContext context,
    _SubtaskAttachmentDraft draft,
  ) {
    if (draft.isPendingFile) {
      final name = draft.pendingFilename?.trim().isNotEmpty == true
          ? draft.pendingFilename!.trim()
          : 'File';
      return AsanaAttachmentDraftTile(
        isWebsiteLink: false,
        title: name,
        subtitle: _effectiveCreateMode
            ? 'Uploads when you create the sub-task'
            : 'Uploads when you save',
        enabled: !_saving,
        onRemove: () => _removeAttachment(draft),
      );
    }
    final url = draft.urlController.text.trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final desc = draft.descController.text.trim();
    return AsanaAttachmentDraftTile(
      isWebsiteLink: true,
      title: desc.isNotEmpty ? desc : url,
      url: url,
      enabled: !_saving,
      onRemove: () => _removeAttachment(draft),
      onEditLink: () => _editAttachmentLink(context, draft),
    );
  }

  List<Widget> _buildFooterButtons({
    required AppState state,
    required SingularSubtask? subtask,
    required bool isCreator,
    required bool isPic,
    required bool isAssigneeOnly,
  }) {
    if (_effectiveCreateMode) {
      return [
        FilledButton(
          onPressed: _saving ? null : _save,
          style: AsanaTaskDetailActionStyles.createFilled(
            widget.palette,
            context: context,
          ),
          child: Text(_saving ? 'Creating' : 'Create'),
        ),
      ];
    }
    final s = subtask;
    if (s == null) return const [];
    final deleted = s.isDeleted;
    final mobileButtons = AsanaTaskDetailActionStyles.isMobile(context);
    final buttons = <Widget>[];
    final showUpdate = !deleted && (isCreator || isPic || isAssigneeOnly);
    if (showUpdate) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : _save,
          style: AsanaTaskDetailActionStyles.updateFilled(
            widget.palette,
            context: context,
          ),
          child: Text(_saving ? 'Saving' : 'Update'),
        ),
      );
    }
    if (!deleted && isCreator && _canMarkComplete(s)) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _markCompleted(state, s),
          style: AsanaTaskDetailActionStyles.successFilled(context: context),
          child: Text(mobileButtons ? 'Complete' : 'Mark as Completed'),
        ),
      );
    }
    if (!deleted && isCreator && _canUndoAcceptOrReturn(s)) {
      buttons.add(
        OutlinedButton(
          onPressed: _saving ? null : () => _undoAcceptOrReturn(state, s),
          style: AsanaTaskDetailActionStyles.undoOutlined(
            widget.palette,
            context: context,
          ),
          child: const Text('Undo'),
        ),
      );
    }
    if (!deleted && isPic && _canPicSubmit(s)) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _submitSubtask(state, s),
          style: AsanaTaskDetailActionStyles.submitFilled(
            widget.palette,
            context: context,
          ),
          child: const Text('Submit'),
        ),
      );
    }
    if (!deleted && isCreator && s.submission?.trim() == 'Submitted') {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _markCompleted(state, s),
          style: AsanaTaskDetailActionStyles.successFilled(context: context),
          child: const Text('Accept'),
        ),
      );
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _returnSubtask(state, s),
          style: AsanaTaskDetailActionStyles.returnFilled(context: context),
          child: const Text('Return'),
        ),
      );
    }
    if (isCreator) {
      if (deleted) {
        buttons.add(
          OutlinedButton(
            onPressed: _saving ? null : () => _undoDeleted(state, s),
            style: AsanaTaskDetailActionStyles.undoOutlined(
              widget.palette,
              context: context,
            ),
            child: Text(mobileButtons ? 'Restore' : 'Restore to Incomplete'),
          ),
        );
      } else {
        buttons.add(
          FilledButton(
            onPressed: _saving ? null : _deleteSubtask,
            style: AsanaTaskDetailActionStyles.deleteFilled(context: context),
            child: const Text('Delete'),
          ),
        );
      }
    }
    return buttons;
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(widget.palette);
    if (_loading) {
      return const StartupLoadingView(label: 'Loading');
    }
    final s = _subtask;
    if (!_effectiveCreateMode && s == null) {
      return ColoredBox(
        color: chrome.body,
        child: const Center(child: Text('Sub-task not found')),
      );
    }
    final state = context.watch<AppState>();
    final isCreator = _effectiveCreateMode || _isCreator(state);
    final isPic = s != null && _isPic(state, s);
    final isAssigneeOnly =
        s != null && _isAssignee(state, s) && !isCreator && !isPic;
    _parentTask = state.taskById(widget.parentTaskId ?? s?.taskId ?? '');
    final parent = _parentTask;
    final footerButtons = _buildFooterButtons(
      state: state,
      subtask: s,
      isCreator: isCreator,
      isPic: isPic,
      isAssigneeOnly: isAssigneeOnly,
    );

    _ensureSubtaskAi(state);

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_subtaskAi != null)
            AsanaTaskAiDock(
              controller: _subtaskAi!,
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
                children: footerButtons,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCreator) ...[
            AsanaHoverTextField(
              controller: _nameController,
              canEdit: true,
              readOnly: _saving,
              maxLines: 6,
              minLines: 1,
              style: asanaDetailTitleStyle(context),
              hintText: 'Please fill in sub-task name',
            ),
            _aiSuggestions(AsanaTaskAiFieldKey.taskName),
          ] else
            Text(
              s?.subtaskName.trim().isEmpty ?? true ? '(Unnamed sub-task)' : s!.subtaskName.trim(),
              style: asanaDetailTitleStyle(context),
            ),
          const SizedBox(height: 12),
          AsanaDetailLabelValue(
            label: 'Description',
            child: AsanaHoverTextField(
              controller: _descController,
              canEdit: isCreator,
              readOnly: _saving,
              maxLines: 8,
              minLines: 2,
              style: asanaDetailMultilineValueStyle(context),
              hintText: 'Please fill in sub-task description',
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.description),
          if (parent != null)
            AsanaDetailTwoColumnRow(
              label: 'Parent Task',
              child: AsanaDetailPlainValue(text: parent.name.trim()),
            ),
          AsanaDetailTwoColumnRow(
            label: 'Creator',
            child: AsanaDetailPlainValue(
              text: _effectiveCreateMode
                  ? (parent?.createByStaffName?.trim() ?? '')
                  : (s?.createByStaffName?.trim() ?? ''),
            ),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Assignees',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _assigneeAnchorLink,
                child: isCreator
                    ? AsanaAssigneeFieldValue(
                        assignees: _assigneeRowsForDisplay(state),
                        canEdit: true,
                        onOpenPicker: _saving ? null : (_) => _pickAssignees(anchorContext),
                        onRemove: _saving ? null : _removeAssignee,
                      )
                    : AsanaDetailPlainValue(
                        text: s?.assigneeIds
                                .map((id) => _nameFor(state, id))
                                .where((n) => n.isNotEmpty)
                                .join(', ') ??
                            '',
                      ),
              ),
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.assignees),
          AsanaDetailTwoColumnRow(
            label: 'PIC',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _picAnchorLink,
                child: isCreator
                    ? AsanaAssigneeFieldValue(
                        assignees: _picAssigneeId != null
                            ? [(id: _picAssigneeId!, name: _labelForAssigneeId(_picAssigneeId!, state))]
                            : [],
                        canEdit: _assigneeIds.isNotEmpty,
                        showAddButtonWhenNotEmpty: false,
                        onOpenPicker: _saving || _assigneeIds.isEmpty
                            ? null
                            : (_) => _pickPic(anchorContext, state),
                        onRemove: _saving ? null : _removePic,
                      )
                    : AsanaDetailPlainValue(
                        text: s?.picDisplayName((k) => _nameFor(state, k)) ?? '',
                      ),
              ),
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.pic),
          AsanaDetailTwoColumnRow(
            label: 'Priority',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _priorityAnchorLink,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: isCreator
                      ? MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _saving
                                ? null
                                : () => _pickPriority(anchorContext),
                            child: AsanaPriorityChip(priority: _localPriority),
                          ),
                        )
                      : AsanaPriorityChip(
                          priority: s?.priority ?? priorityStandard,
                        ),
                ),
              ),
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.priority),
          AsanaDetailTwoColumnRow(
            label: 'Status',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _statusAnchorLink,
                child: isCreator
                    ? MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _saving ? null : () => _pickStatus(anchorContext),
                          child: AsanaDetailStatusPill(status: _draftStatus ?? s?.status ?? 'Todo'),
                        ),
                      )
                    : AsanaDetailStatusPill(status: s?.status ?? 'Todo'),
              ),
            ),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Start date',
            child: Builder(
              builder: (anchorContext) => AsanaHoverTapValue(
                value: _date(_startDate),
                canEdit: isCreator,
                onTap: _saving ? null : (_) => _pickStartDueRange(anchorContext),
              ),
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.startDate),
          AsanaDetailTwoColumnRow(
            label: 'Due date',
            child: Builder(
              builder: (anchorContext) => AsanaHoverTapValue(
                value: _date(_dueDate),
                canEdit: isCreator,
                onTap: _saving ? null : (_) => _pickStartDueRange(anchorContext),
              ),
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
          if (isCreator && (_needsChangeDueReason() || _reasonController.text.trim().isNotEmpty))
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaDetailLabelValue(
                  label: 'Reason',
                  child: AsanaHoverTextField(
                    controller: _reasonController,
                    canEdit: true,
                    readOnly: _saving,
                    maxLines: 4,
                    minLines: 2,
                    style: asanaDetailMultilineValueStyle(context),
                  ),
                ),
                _aiSuggestions(AsanaTaskAiFieldKey.reason),
              ],
            )
          else if (!isCreator && (s?.changeDueReason ?? '').trim().isNotEmpty)
            AsanaDetailLabelValue(
              label: 'Reason',
              child: AsanaDetailPlainValue(text: s!.changeDueReason!.trim()),
            ),
          AsanaDetailTwoColumnRow(
            label: 'Submission',
            child: AsanaDetailSubmissionPill(
              submission: _effectiveCreateMode ? 'Pending' : s?.submission,
            ),
          ),
          AsanaDetailSectionHeader(
            title: 'Attachments',
            showAddButton: true,
            addTooltip: 'Add attachment',
            addAnchorLink: _attachmentAddAnchorLink,
            onAdd: _saving ? null : _showAttachmentMenu,
          ),
          if (_attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No attachments yet',
                style: asanaDetailLabelStyle(context),
              ),
            )
          else
            Builder(
              builder: (attachmentContext) => Column(
                children: _attachments
                    .map((a) => _attachmentTile(attachmentContext, a))
                    .toList(),
              ),
            ),
          _aiSuggestions(AsanaTaskAiFieldKey.websiteLink),
          if (!_effectiveCreateMode) ...[
            if ((s?.updateByStaffName ?? '').trim().isNotEmpty)
              AsanaDetailTwoColumnRow(
                label: 'Last updated by',
                child: AsanaDetailPlainValue(text: s!.updateByStaffName!.trim()),
              ),
            if (s?.lastUpdated != null)
              AsanaDetailTwoColumnRow(
                label: 'Last updated',
                child: AsanaDetailPlainValue(
                  text: HkTime.formatInstantAsHk(s!.lastUpdated, 'MMM d, yyyy HH:mm'),
                ),
              ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          AsanaDetailSectionHeader(
            title: 'Comments',
            showAddButton: false,
          ),
          AsanaDetailLabelValue(
            label: 'New comment',
            child: AsanaHoverTextField(
              controller: _commentController,
              canEdit: true,
              readOnly: _saving,
              maxLines: 8,
              minLines: 2,
              hintText: 'Ask a question or post an update...',
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.comment),
        ],
      ),
    );
  }
}

class _ParentAssigneeGridMenu extends StatefulWidget {
  const _ParentAssigneeGridMenu({
    required this.options,
    required this.initialSelection,
    required this.onDone,
  });

  final List<AsanaFilterCheckboxOption> options;
  final Set<String> initialSelection;
  final void Function(Set<String>) onDone;

  @override
  State<_ParentAssigneeGridMenu> createState() => _ParentAssigneeGridMenuState();
}

class _ParentAssigneeGridMenuState extends State<_ParentAssigneeGridMenu> {
  late final Set<String> _selected = Set<String>.from(widget.initialSelection);

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 3 : 2;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFD1D5DB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Parent task assignees',
              style: asanaDetailValueStyle(context, weight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: columns,
              childAspectRatio: 3.6,
              shrinkWrap: true,
              mainAxisSpacing: 4,
              crossAxisSpacing: 6,
              children: [
                for (final option in widget.options)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _toggle(option.key),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _selected.contains(option.key),
                          onChanged: (_) => _toggle(option.key),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: asanaDetailValueStyle(context),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => widget.onDone(Set<String>.from(_selected)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE4E6EB),
                  foregroundColor: const Color(0xFF1F2937),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}