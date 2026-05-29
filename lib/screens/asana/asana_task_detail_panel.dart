import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/singular_comment.dart';
import '../../models/singular_subtask.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../../utils/holiday_date_picker.dart';
import '../../utils/singular_workflow_guards.dart';
import '../../utils/attachment_url_launch.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_attachment_draft_tile.dart';
import 'asana_attachment_menu.dart';
import 'asana_blocking_loading_overlay.dart';
import '../../widgets/task_list_card.dart';
import 'asana_task_ai_assistant.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_subtask_list.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';
import 'asana_filter_widgets.dart';
import 'asana_value_chips.dart';

class AsanaTaskDetailPanel extends StatefulWidget {
  const AsanaTaskDetailPanel({
    super.key,
    this.taskId,
    this.createMode = false,
    required this.palette,
    required this.onClose,
    this.refreshToken = 0,
    this.onPushCreateSubtask,
    this.onPushSubtask,
    this.onCreated,
  }) : assert(createMode || taskId != null);

  final String? taskId;
  final bool createMode;
  final AsanaLandingPalette palette;
  final int refreshToken;
  final VoidCallback onClose;
  final VoidCallback? onPushCreateSubtask;
  final void Function(String subtaskId)? onPushSubtask;
  final void Function(String taskId)? onCreated;

  @override
  State<AsanaTaskDetailPanel> createState() => _AsanaTaskDetailPanelState();
}

class _AttachmentDraft {
  _AttachmentDraft({
    this.id,
    String? url,
    String? desc,
    this.pendingBytes,
    this.pendingFilename,
    this.isWebsiteLink = false,
  })  : urlController = TextEditingController(text: url ?? ''),
        descController = TextEditingController(text: desc ?? '');

  final String? id;
  final TextEditingController urlController;
  final TextEditingController descController;
  Uint8List? pendingBytes;
  String? pendingFilename;
  bool isWebsiteLink;

  bool get isPendingFile =>
      pendingBytes != null && pendingBytes!.isNotEmpty;

  void dispose() {
    urlController.dispose();
    descController.dispose();
  }
}

class _AsanaTaskDetailPanelState extends State<AsanaTaskDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _reasonController = TextEditingController();
  final _commentController = TextEditingController();

  List<SingularSubtask> _subtasks = [];
  List<SingularCommentRowDisplay> _comments = [];
  final Map<String, TextEditingController> _postedCommentControllers = {};
  final Map<String, String> _postedCommentSavedText = {};
  String? _savingPostedCommentId;
  final List<_AttachmentDraft> _attachments = [];

  bool _loadingExtras = true;
  bool _saving = false;
  String? _myStaffUuid;

  int _localPriority = priorityStandard;
  DateTime? _startDate;
  DateTime? _dueDate;
  String? _selectedProjectId;
  List<ProjectRecord> _myProjects = [];

  Set<String> _holidaySkipYmd = {};
  DateTime _anchorCreateDate = HkTime.todayDateOnlyHk();
  final Set<String> _selectedAssigneeIds = {};
  String? _picAssigneeId;
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  bool _assigneePickerLoading = false;
  String? _assigneePickerError;
  final ValueNotifier<AsanaAssigneePickerSnapshot> _assigneeSnapshot =
      ValueNotifier(const AsanaAssigneePickerSnapshot(loading: true));
  final LayerLink _projectAnchorLink = LayerLink();
  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _priorityAnchorLink = LayerLink();
  final LayerLink _attachmentAddAnchorLink = LayerLink();
  /// Value-column width/left for anchored menus (assignee field row).
  final GlobalKey _detailPopupWidthAlignKey = GlobalKey();
  List<AsanaAnchoredOption<String>> _projectMenuOptions = [];
  int _anchoredPickerReopenBlockedUntilMs = 0;

  AsanaTaskAiController? _taskAi;
  AsanaTaskAiController? _commentAi;
  bool _taskAiCanSuggestAssignees = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant AsanaTaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId ||
        oldWidget.createMode != widget.createMode) {
      if (widget.createMode) {
        _resetCreateDraft();
      } else {
        _syncFromTask();
      }
      _bootstrap();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadSubtasks();
    }
  }

  @override
  void dispose() {
    AsanaBlockingLoadingOverlay.hideAll();
    _assigneeSnapshot.dispose();
    _nameController.dispose();
    _descController.dispose();
    _reasonController.dispose();
    _commentController.dispose();
    _disposePostedCommentControllers();
    _taskAi?.dispose();
    _commentAi?.dispose();
    _clearAttachments();
    super.dispose();
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

  Future<T?> _withBlockingLoading<T>(Future<T?> Function() action) async {
    if (!mounted) return null;
    AsanaBlockingLoadingOverlay.show(context);
    try {
      return await action();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
    }
  }

  Future<void> _showInfo(String title, String content) {
    return showAsanaInfoDialog(
      context: context,
      title: title,
      content: content,
      palette: widget.palette,
    );
  }

  Future<void> _removeAttachmentDraft(_AttachmentDraft e) async {
    final persistedId = e.id?.trim();
    if (persistedId != null &&
        persistedId.isNotEmpty &&
        !widget.createMode &&
        SupabaseConfig.isConfigured) {
      final err = await SupabaseService.deleteAttachmentById(persistedId);
      if (!mounted) return;
      if (err != null) {
        await _showInfo('Could not remove attachment', err);
        return;
      }
    }
    setState(() {
      e.dispose();
      _attachments.remove(e);
    });
  }

  bool _draftShowsAsWebsiteLink(_AttachmentDraft e) {
    if (e.isPendingFile) return false;
    if (e.isWebsiteLink) return true;
    final url = e.urlController.text.trim();
    return url.isNotEmpty && !isAppFirebaseStorageAttachmentUrl(url);
  }

  Future<void> _editAttachmentLink(
    BuildContext anchorContext,
    _AttachmentDraft e,
  ) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    final widthAlignContext =
        _detailPopupWidthAlignKey.currentContext ?? anchorContext;
    final updated = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: widthAlignContext,
      initialUrl: e.urlController.text,
      initialDescription: e.descController.text,
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || updated == null) return;
    setState(() {
      e.urlController.text = updated.url;
      e.descController.text = updated.description;
      e.isWebsiteLink = true;
    });
  }

  void _clearAttachments() {
    for (final a in _attachments) {
      a.dispose();
    }
    _attachments.clear();
  }

  void _resetCreateDraft() {
    _nameController.clear();
    _descController.clear();
    _reasonController.clear();
    _commentController.clear();
    _localPriority = priorityStandard;
    _selectedProjectId = null;
    _selectedAssigneeIds.clear();
    _picAssigneeId = null;
    _subtasks = [];
    _comments = [];
    _disposePostedCommentControllers();
    _clearAttachments();
    final today = HkTime.todayDateOnlyHk();
    _anchorCreateDate =
        HkTime.firstBusinessDayOnOrAfter(today, _holidaySkipYmd);
    _startDate = _anchorCreateDate;
    _dueDate = _defaultDueForPriority(_localPriority);
  }

  DateTime _defaultDueForPriority(int priority) {
    final days = priority == priorityUrgent ? 1 : 3;
    return HkTime.addBusinessDaysAfter(
      _anchorCreateDate,
      days,
      _holidaySkipYmd,
    );
  }

  Future<void> _loadCalendarHolidaysForCreate() async {
    Set<String> skip = {};
    if (SupabaseConfig.isConfigured) {
      try {
        final rows = await SupabaseService.fetchCalendarHolidaysBetween(
          kHolidayPickerWideFirstDate,
          kHolidayPickerWideLastDate,
        );
        skip = HkTime.holidaySkipYmdFromCalendarRows(rows);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _holidaySkipYmd = skip;
      _anchorCreateDate = HkTime.firstBusinessDayOnOrAfter(
        HkTime.todayDateOnlyHk(),
        _holidaySkipYmd,
      );
      _startDate = _anchorCreateDate;
      _dueDate = _defaultDueForPriority(_localPriority);
    });
  }

  void _publishAssigneeSnapshot() {
    _assigneeSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForRole(),
      staff: List<StaffForAssignment>.from(_pickerStaff),
      error: _assigneePickerError,
    );
  }

  Future<void> _loadAssigneePicker() async {
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
        _pickerStaff = data.staff;
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
    if (_selectedAssigneeIds.isEmpty) {
      _picAssigneeId = null;
      return;
    }
    if (_selectedAssigneeIds.length == 1) {
      _picAssigneeId = _selectedAssigneeIds.first;
      return;
    }
    // Multiple assignees: keep PIC only if still among assignees.
    if (_picAssigneeId != null &&
        !_selectedAssigneeIds.contains(_picAssigneeId)) {
      _picAssigneeId = null;
    }
  }

  String _labelForAssigneeId(String id, AppState state) {
    for (final s in _pickerStaff) {
      if (s.assigneeId == id) return s.name;
    }
    return state.assigneeById(id)?.name ?? id;
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch > _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  void _rebuildProjectMenuOptions() {
    _projectMenuOptions = [
      const AsanaAnchoredOption(value: '', label: '— No project —'),
      ..._myProjects.map(
        (p) => AsanaAnchoredOption(
          value: p.id,
          label: p.name.trim().isEmpty ? p.id : p.name.trim(),
        ),
      ),
    ];
  }

  List<({String id, String name})> _assigneeRowsForDisplay(AppState state) {
    final rows = _selectedAssigneeIds
        .map((id) => (id: id, name: _labelForAssigneeId(id, state)))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  void _removeAssignee(String assigneeId) {
    setState(() {
      _selectedAssigneeIds.remove(assigneeId);
      _syncPicAfterAssigneesChange();
    });
  }

  Future<void> _pickAssignees(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    await showAsanaAssigneePicker(
      anchorLink: _assigneeAnchorLink,
      anchorContext: anchorContext,
      snapshot: _assigneeSnapshot,
      selectedIds: _selectedAssigneeIds,
      whenClosed: _blockAnchoredPickerReopen,
      onSelectionChanged: (s) {
        if (!mounted) return;
        setState(() {
          _selectedAssigneeIds
            ..clear()
            ..addAll(s);
          _syncPicAfterAssigneesChange();
        });
      },
    );
  }

  Future<void> _pickPic(BuildContext anchorContext, AppState state) async {
    if (!_canOpenAnchoredPicker) return;
    final ids = _selectedAssigneeIds.toList()
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
      setState(() => _picAssigneeId = choice);
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _loadingExtras = true);
    if (widget.createMode) {
      _resetCreateDraft();
    } else {
      _syncFromTask();
    }
    final lk = context.read<AppState>().userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty) {
      _myStaffUuid = await SupabaseService.staffRowIdForAssigneeKey(lk);
    }
    final loads = <Future<void>>[
      _loadProjectsIfCreator(),
    ];
    if (widget.createMode) {
      loads.add(_loadCalendarHolidaysForCreate());
      _loadAssigneePicker();
    } else {
      loads.addAll([
        _loadSubtasks(),
        _loadComments(),
        _loadAttachments(),
      ]);
      _loadAssigneePicker();
    }
    await Future.wait(loads);
    if (mounted) setState(() => _loadingExtras = false);
  }

  void _syncFromTask() {
    final id = widget.taskId;
    if (id == null) return;
    final task = context.read<AppState>().taskById(id);
    if (task == null) return;
    _nameController.text = task.name;
    _descController.text = task.description;
    _reasonController.text = task.changeDueReason ?? '';
    _localPriority = task.priority;
    _startDate = task.startDate;
    _dueDate = task.endDate;
    _selectedProjectId = task.projectId;
    _selectedAssigneeIds
      ..clear()
      ..addAll(task.assigneeIds);
    final pic = task.pic?.trim() ?? '';
    _picAssigneeId = pic.isEmpty ? null : pic;
    _syncPicAfterAssigneesChange();
  }

  Future<void> _loadSubtasks() async {
    final id = widget.taskId;
    if (id == null || !SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchSubtasksForTask(id);
      if (mounted) setState(() => _subtasks = list.where((s) => !s.isDeleted).toList());
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    final id = widget.taskId;
    if (id == null || !SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchSingularCommentsForTask(id);
      if (mounted) {
        setState(() {
          _comments = list;
          _syncPostedCommentControllers();
        });
      }
    } catch (_) {}
  }

  void _disposePostedCommentControllers() {
    for (final c in _postedCommentControllers.values) {
      c.dispose();
    }
    _postedCommentControllers.clear();
    _postedCommentSavedText.clear();
  }

  void _syncPostedCommentControllers() {
    final ids = _comments.map((c) => c.id).toSet();
    for (final id in _postedCommentControllers.keys.toList()) {
      if (!ids.contains(id)) {
        _postedCommentControllers[id]!.dispose();
        _postedCommentControllers.remove(id);
        _postedCommentSavedText.remove(id);
      }
    }
    for (final c in _comments) {
      if (!_postedCommentControllers.containsKey(c.id)) {
        _postedCommentControllers[c.id] =
            TextEditingController(text: c.description);
        _postedCommentSavedText[c.id] = c.description;
      } else {
        final ctrl = _postedCommentControllers[c.id]!;
        final saved = _postedCommentSavedText[c.id] ?? '';
        if (ctrl.text == saved && ctrl.text != c.description) {
          ctrl.text = c.description;
          _postedCommentSavedText[c.id] = c.description;
        }
      }
    }
  }

  Future<void> _savePostedCommentOnBlur(SingularCommentRowDisplay c) async {
    if (_savingPostedCommentId == c.id) return;
    final ctrl = _postedCommentControllers[c.id];
    if (ctrl == null) return;

    final newBody = ctrl.text.trim();
    final saved = (_postedCommentSavedText[c.id] ?? c.description).trim();
    if (newBody == saved) return;

    if (newBody.isEmpty) {
      ctrl.text = saved;
      await _showInfo('Comment required', 'Comment cannot be empty.');
      return;
    }

    final state = context.read<AppState>();
    _savingPostedCommentId = c.id;
    final err = await SupabaseService.updateSingularCommentRow(
      commentId: c.id,
      description: newBody,
      updaterStaffLookupKey: state.userStaffAppId,
    );
    _savingPostedCommentId = null;
    if (!mounted) return;
    if (err != null) {
      ctrl.text = saved;
      await _showInfo('Could not update comment', err);
      return;
    }
    _postedCommentSavedText[c.id] = newBody;
    await _loadComments();
  }

  Future<void> _loadAttachments() async {
    final id = widget.taskId;
    if (id == null || !SupabaseConfig.isConfigured) return;
    try {
      final rows = await SupabaseService.fetchAttachmentsForTask(id);
      if (!mounted) return;
      setState(() {
        _clearAttachments();
        for (final r in rows) {
          final content = r.content?.trim() ?? '';
          _attachments.add(
            _AttachmentDraft(
              id: r.id,
              url: r.content,
              desc: r.description,
              isWebsiteLink: content.isNotEmpty &&
                  !isAppFirebaseStorageAttachmentUrl(content),
            ),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _loadProjectsIfCreator() async {
    final state = context.read<AppState>();
    final task =
        widget.createMode ? null : state.taskById(widget.taskId ?? '');
    if (!widget.createMode && (task == null || !_isCreator(state, task))) {
      return;
    }
    final me = _myStaffUuid;
    if (me == null || me.isEmpty || !SupabaseConfig.isConfigured) return;
    try {
      final all = await SupabaseService.fetchAllProjectsFromSupabase();
      bool eligible(ProjectRecord p) {
        final s = p.status.trim();
        return s == 'Not started' || s == 'In progress';
      }

      final linkable = all
          .where((p) => p.staffMayLinkTasks(me))
          .where(eligible)
          .toList();
      final pid = task?.projectId?.trim();
      if (pid != null &&
          pid.isNotEmpty &&
          !linkable.any((p) => p.id == pid)) {
        final extra = await SupabaseService.fetchProjectById(pid);
        if (extra != null) linkable.add(extra);
      }
      linkable.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (mounted) {
        setState(() {
          _myProjects = linkable;
          _rebuildProjectMenuOptions();
        });
      }
    } catch (_) {}
  }

  static bool _uuidEquals(String? a, String? b) {
    final x = a?.trim().toLowerCase() ?? '';
    final y = b?.trim().toLowerCase() ?? '';
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  bool _isCreator(AppState state, Task task) {
    final mine = state.userStaffAppId?.trim();
    final cb = task.createByAssigneeKey?.trim();
    if (mine != null && mine.isNotEmpty && cb != null && cb.isNotEmpty && mine == cb) {
      return true;
    }
    return _uuidEquals(_myStaffUuid, task.createByAssigneeKey);
  }

  bool _isTaskAssignee(AppState state, Task task) {
    final mine = state.userStaffAppId?.trim();
    if (mine != null && mine.isNotEmpty && task.assigneeIds.contains(mine)) {
      return true;
    }
    for (final id in task.assigneeIds) {
      if (_uuidEquals(id, _myStaffUuid)) return true;
    }
    return false;
  }

  bool _isPic(AppState state, Task task) {
    final p = task.pic?.trim();
    if (p == null || p.isEmpty) return false;
    final mine = state.userStaffAppId?.trim();
    if (mine != null && mine.isNotEmpty && mine == p) return true;
    return _uuidEquals(p, _myStaffUuid);
  }

  bool _taskDeleted(Task task) =>
      (task.dbStatus ?? '').trim().toLowerCase() == 'deleted';

  bool _canEditMetadata(AppState state, Task task) =>
      _isCreator(state, task) && !_taskDeleted(task);

  bool _canWriteComments(AppState state, Task task) =>
      (_isCreator(state, task) || _isTaskAssignee(state, task)) &&
      !_taskDeleted(task);

  bool _canEditAttachments(AppState state, Task task) =>
      !_taskDeleted(task) && (_isCreator(state, task) || _isPic(state, task));

  String _nameFor(AppState state, String? key) {
    final k = key?.trim();
    if (k == null || k.isEmpty) return '';
    return state.assigneeById(k)?.name ?? k;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  String _formatDateTime(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy HH:mm');
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

  String _namesFor(AppState state, Iterable<String> ids) {
    return ids
        .map((id) => _nameFor(state, id))
        .where((name) => name.trim().isNotEmpty)
        .join(', ');
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

  List<Map<String, String>> _taskChangesForEmail(
    AppState state,
    Task task,
    List<String> assigneeIds,
  ) {
    final changes = <Map<String, String>>[];
    _addChange(changes, 'taskName', task.name, _nameController.text.trim());
    _addChange(
      changes,
      'description',
      task.description,
      _descController.text.trim(),
    );
    _addChange(
      changes,
      'assignees',
      _namesFor(state, task.assigneeIds),
      _namesFor(state, assigneeIds),
    );
    _addChange(
      changes,
      'priority',
      priorityToDisplayName(task.priority),
      priorityToDisplayName(_localPriority),
    );
    _addChange(
      changes,
      'startDate',
      _formatDate(task.startDate),
      _formatDate(_startDate),
    );
    _addChange(
      changes,
      'dueDate',
      _formatDate(task.endDate),
      _formatDate(_dueDate),
    );
    return changes;
  }

  /// Posted time on task comments (HK, 24h — matches legacy task detail).
  String _formatCommentPostedTs(DateTime? stored) {
    if (stored == null) return '';
    return HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm');
  }

  bool _isOwnComment(SingularCommentRowDisplay c) =>
      !c.isDeleted && _uuidEquals(c.createByStaffId, _myStaffUuid);

  DateTime? _commentDisplayTimestamp(SingularCommentRowDisplay c) {
    final created = c.createTimestampUtc;
    final updated = c.updateTimestampUtc;
    if (updated != null &&
        created != null &&
        updated.isAfter(created)) {
      return updated;
    }
    return created ?? updated;
  }

  Widget _buildCommentDisplayTile(
    BuildContext context,
    SingularCommentRowDisplay c,
  ) {
    if (_isOwnComment(c) && !_postedCommentControllers.containsKey(c.id)) {
      _postedCommentControllers[c.id] =
          TextEditingController(text: c.description);
      _postedCommentSavedText[c.id] = c.description;
    }

    final deleted = c.isDeleted;
    final canEdit = _isOwnComment(c);
    final postedAt = _commentDisplayTimestamp(c);
    final edited = c.updateTimestampUtc != null &&
        c.createTimestampUtc != null &&
        c.updateTimestampUtc!.isAfter(c.createTimestampUtc!);
    final body = canEdit
        ? Focus(
            onFocusChange: (hasFocus) {
              if (!hasFocus) _savePostedCommentOnBlur(c);
            },
            child: AsanaHoverTextField(
              controller: _postedCommentControllers[c.id]!,
              canEdit: true,
              readOnly: _saving || _savingPostedCommentId == c.id,
              maxLines: 8,
              minLines: 2,
              style: asanaDetailMultilineValueStyle(context).copyWith(
                color: kAsanaTextPrimary,
              ),
            ),
          )
        : Text(
            c.description,
            style: asanaDetailMultilineValueStyle(context).copyWith(
              color: deleted ? kAsanaTextSecondary : kAsanaTextPrimary,
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.displayStaffName,
            style: asanaDetailLabelStyle(context),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: deleted ? const Color(0xFFF9FAFB) : Colors.white,
              border: Border.all(color: const Color(0xFFEDEAE9)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                body,
                if (postedAt != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      edited
                          ? 'Edited ${_formatCommentPostedTs(postedAt)}'
                          : _formatCommentPostedTs(postedAt),
                      style: asanaDetailLabelStyle(context).copyWith(
                        fontWeight: FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
      if (widget.createMode) {
        _dueDate = _defaultDueForPriority(choice);
      }
    });
  }

  Future<void> _pickProject(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    if (_projectMenuOptions.isEmpty && _myProjects.isNotEmpty) {
      _rebuildProjectMenuOptions();
    }
    if (_projectMenuOptions.isEmpty) {
      if (_myProjects.isEmpty) {
        await _showInfo('Projects still loading', 'Please try again in a moment.');
        _loadProjectsIfCreator();
      }
      return;
    }
    final choice = await showAsanaAnchoredOptionMenu<String>(
      anchorLink: _projectAnchorLink,
      anchorContext: anchorContext,
      onClosed: _blockAnchoredPickerReopen,
      options: _projectMenuOptions,
    );
    if (!mounted || choice == null) return;
    setState(() => _selectedProjectId = choice.isEmpty ? null : choice);
  }

  List<String?> _createAttachmentAclKeys(AppState state, String picKey) {
    return [
      state.userStaffAppId,
      picKey,
      ..._selectedAssigneeIds,
    ];
  }

  Future<void> _showAttachmentSourceMenu(
    BuildContext anchorContext, {
    Task? task,
  }) async {
    if (!_canOpenAnchoredPicker) return;
    final widthAlignContext =
        _detailPopupWidthAlignKey.currentContext ?? anchorContext;
    final result = await showAsanaAnchoredAttachmentMenu(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: widthAlignContext,
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || result == null) return;
    if (result is AsanaAttachmentUploadFile) {
      if (task != null) {
        final state = context.read<AppState>();
        final picKey = _picAssigneeId ?? task.pic ?? '';
        final r = await _withBlockingLoading(
          () => FirebaseAttachmentUploadService.pickUploadForTask(
            task.id,
            aclStaffKeys: _createAttachmentAclKeys(state, picKey),
          ),
        );
        if (!mounted) return;
        if (r?.error != null) {
          await _showInfo('Attachment upload failed', r!.error!);
          return;
        }
        if (r?.url == null) return;
        setState(() {
          _attachments.add(_AttachmentDraft(url: r!.url, desc: r.label));
        });
      } else {
        final picked = await _withBlockingLoading(
          FirebaseAttachmentUploadService.pickFileForUpload,
        );
        if (!mounted) return;
        if (picked?.error != null) {
          await _showInfo('Attachment upload failed', picked!.error!);
          return;
        }
        if (picked?.bytes == null) return;
        setState(() {
          _attachments.add(
            _AttachmentDraft(
              pendingBytes: picked!.bytes,
              pendingFilename: picked.label,
              desc: picked.label,
            ),
          );
        });
      }
    } else if (result is AsanaAttachmentWebsiteLink) {
      setState(() {
        _attachments.add(
          _AttachmentDraft(
            url: result.url,
            desc: result.description,
            isWebsiteLink: true,
          ),
        );
      });
    }
  }

  Future<bool> _validateAssigneesAndPic() async {
    if (_selectedAssigneeIds.isEmpty) {
      await _showInfo('Assignee required', 'Select at least one assignee.');
      return false;
    }
    if (_selectedAssigneeIds.length > 1 &&
        (_picAssigneeId == null ||
            !_selectedAssigneeIds.contains(_picAssigneeId))) {
      await _showInfo('PIC required', 'Choose a PIC from the assignees.');
      return false;
    }
    return true;
  }

  String _resolvePicKeyForSave() {
    if (_selectedAssigneeIds.length == 1) {
      return _selectedAssigneeIds.first;
    }
    return _picAssigneeId!;
  }

  List<Widget> _buildAssigneePicSection(
    BuildContext context,
    AppState state, {
    required bool canEditAssignees,
    required String creatorLabel,
    String readOnlyAssigneesText = '',
    String readOnlyPicText = '',
    bool showAiSuggestions = false,
  }) {
    return [
      AsanaDetailTwoColumnRow(
        label: 'Creator',
        child: AsanaDetailPlainValue(text: creatorLabel),
      ),
      AsanaDetailTwoColumnRow(
        label: 'Assignees',
        child: KeyedSubtree(
          key: _detailPopupWidthAlignKey,
          child: canEditAssignees
              ? AsanaAssigneeFieldValue(
                  anchorLink: _assigneeAnchorLink,
                  assignees: _assigneeRowsForDisplay(state),
                  canEdit: !_saving,
                  onOpenPicker: _pickAssignees,
                  onRemove: _removeAssignee,
                )
              : AsanaDetailPlainValue(text: readOnlyAssigneesText),
        ),
      ),
      if (showAiSuggestions)
        _aiSuggestions(AsanaTaskAiFieldKey.assignees),
      AsanaDetailTwoColumnRow(
        label: 'PIC',
        child: canEditAssignees
            ? (_selectedAssigneeIds.length > 1
                ? AsanaHoverTapValue(
                    anchorLink: _picAnchorLink,
                    value: _picAssigneeId != null
                        ? _labelForAssigneeId(_picAssigneeId!, state)
                        : '',
                    canEdit: !_saving,
                    emptyPlaceholder: 'Choose person in charge',
                    onTap: (ctx) => _pickPic(ctx, state),
                  )
                : AsanaDetailPlainValue(
                    text: _selectedAssigneeIds.length == 1
                        ? _labelForAssigneeId(
                            _selectedAssigneeIds.first,
                            state,
                          )
                        : '',
                  ))
            : AsanaDetailPlainValue(text: readOnlyPicText),
      ),
      if (showAiSuggestions)
        _aiSuggestions(AsanaTaskAiFieldKey.pic),
    ];
  }

  Future<String?> _uploadPendingCreateAttachments(
    String taskId,
    AppState state,
    String picKey,
  ) async {
    for (final draft in _attachments) {
      if (!draft.isPendingFile) continue;
      final r = await FirebaseAttachmentUploadService.uploadBytesForTask(
        taskId,
        bytes: draft.pendingBytes!,
        originalFilename: draft.pendingFilename ?? 'attachment',
        aclStaffKeys: _createAttachmentAclKeys(state, picKey),
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

  Future<void> _createTask(AppState state) async {
    if (!SupabaseConfig.isConfigured) {
      await _showInfo('Supabase not configured', 'Please configure Supabase before continuing.');
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await _showInfo('Task name required', 'Please fill in the task name before continuing.');
      return;
    }
    if (!await _validateAssigneesAndPic()) return;
    if (!mounted) return;
    final directorIds = _selectedAssigneeIds.toList();
    final picKey = _resolvePicKeyForSave();
    if (_needsChangeDueReason() && _reasonController.text.trim().isEmpty) {
      await showAsanaConfirmDialog(
        context: context,
        title: 'Reason required',
        content:
            'Please explain why this task needs more time than expected before continuing.',
        confirmText: 'OK',
        palette: widget.palette,
      );
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _startDate!.isAfter(_dueDate!)) {
      await _showInfo('Invalid date range', 'Start date cannot be after due date.');
      return;
    }
    _taskAi?.clearAllSuggestions();
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final slots =
          await SupabaseService.assigneeSlotsForTask(directorIds);
      final ins = await SupabaseService.insertTaskTableRow(
        taskName: name,
        assignees: slots,
        description: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        priority: priorityToDisplayName(_localPriority),
        startDate: _startDate,
        dueDate: _dueDate,
        creatorStaffLookupKey: state.userStaffAppId,
        picStaffLookupKey: picKey,
        changeDueReason:
            _needsChangeDueReason() ? _reasonController.text.trim() : null,
        projectId: _selectedProjectId,
      );
      if (ins.error != null && mounted) {
        await _showInfo('Could not create task', ins.error!);
        return;
      }
      final newId = ins.taskId;
      if (newId == null || newId.isEmpty) return;
      final uploadErr = await _uploadPendingCreateAttachments(
        newId,
        state,
        picKey,
      );
      if (uploadErr != null && mounted) {
        await _showInfo('Attachment upload failed', uploadErr);
        return;
      }
      final comment = _commentController.text.trim();
      if (comment.isNotEmpty) {
        await SupabaseService.insertSingularCommentRow(
          taskId: newId,
          description: comment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
      }
      if (_attachments.isNotEmpty) {
        await SupabaseService.replaceAttachmentsForTask(
          taskId: newId,
          rows: _attachmentPayload(),
        );
      }
      final model = await SupabaseService.fetchSingularTaskModelById(newId);
      if (model != null) {
        state.upsertTask(model);
      }
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) {
        debugPrint(
          'notifyTaskAssigned: skipped - Firebase ID token is null',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Task saved. Assignment email was not sent (sign-in token missing).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        final notifyErr = await BackendApi().notifyTaskAssigned(
          idToken: token,
          taskId: newId,
        );
        if (notifyErr != null) {
          debugPrint('notifyTaskAssigned: $notifyErr');
          if (mounted) {
            final short = notifyErr.length > 160
                ? '${notifyErr.substring(0, 160)}...'
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
      if (mounted) widget.onCreated?.call(newId);
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _save(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      await _showInfo('Supabase not configured', 'Please configure Supabase before continuing.');
      return;
    }
    if (!_canEditMetadata(state, task)) {
      if (_isPic(state, task)) {
        await _saveAttachmentsOnly(state, task);
        return;
      }
      await _postCommentOnly(state, task);
      return;
    }
    if (_needsChangeDueReason() && _reasonController.text.trim().isEmpty) {
      await showAsanaConfirmDialog(
        context: context,
        title: 'Reason required',
        content:
            'Please explain why this task needs more time than expected before continuing.',
        confirmText: 'OK',
        palette: widget.palette,
      );
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _startDate!.isAfter(_dueDate!)) {
      await _showInfo('Invalid date range', 'Start date cannot be after due date.');
      return;
    }
    if (_isCreator(state, task) && !await _validateAssigneesAndPic()) return;
    if (!mounted) return;
    _taskAi?.clearAllSuggestions();
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final directorIds = _isCreator(state, task)
          ? _selectedAssigneeIds.toList()
          : List<String>.from(task.assigneeIds);
      final slots = await SupabaseService.assigneeSlotsForTask(directorIds);
      final picKey = _isCreator(state, task)
          ? _resolvePicKeyForSave()
          : task.pic;
      final selProj = _selectedProjectId?.trim();
      final curProj = task.projectId?.trim();
      final clearProject = (selProj == null || selProj.isEmpty) &&
          curProj != null &&
          curProj.isNotEmpty;

      final changesForEmail = _taskChangesForEmail(state, task, directorIds);
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        taskName: _nameController.text.trim(),
        description: _descController.text.trim(),
        priority: priorityToDisplayName(_localPriority),
        assigneeSlots: slots,
        startDate: _startDate,
        dueDate: _dueDate,
        clearStartDate: _startDate == null,
        clearDueDate: _dueDate == null,
        updateByStaffLookupKey: state.userStaffAppId,
        picStaffLookupKey: picKey,
        updateChangeDueReason: true,
        changeDueReason:
            _needsChangeDueReason() ? _reasonController.text.trim() : null,
        clearProjectId: clearProject,
        projectId: !clearProject && selProj != null && selProj.isNotEmpty
            ? selProj
            : null,
      );
      if (err != null && mounted) {
        await _showInfo('Could not update task', err);
        return;
      }
      if (_canEditAttachments(state, task)) {
        final errA = await SupabaseService.replaceAttachmentsForTask(
          taskId: task.id,
          rows: _attachmentPayload(),
        );
        if (errA != null && mounted) {
          await _showInfo('Task saved, attachments failed', errA);
        } else {
          await _loadAttachments();
        }
      }
      final comment = _commentController.text.trim();
      String? commentId;
      if (comment.isNotEmpty) {
        final c = await SupabaseService.insertSingularCommentRow(
          taskId: task.id,
          description: comment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (c.error == null) {
          commentId = c.commentId;
          _commentController.clear();
          await _loadComments();
        }
      }
      if (!mounted) return;
      final updated = _buildUpdatedTask(task, clearProject: clearProject);
      state.replaceTask(updated);
      SupabaseService.invalidateSubtasksCacheForTask(task.id);
      await _loadSubtasks();
      await _notifyEmail(
        'Task update email',
        (token) => BackendApi().notifyTaskUpdated(
          idToken: token,
          taskId: task.id,
          changes: changesForEmail,
          commentAddedText: comment,
          taskCommentId: commentId,
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _saveAttachmentsOnly(AppState state, Task task) async {
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.replaceAttachmentsForTask(
        taskId: task.id,
        rows: _attachmentPayload(),
      );
      if (err != null && mounted) {
        await _showInfo('Could not save attachments', err);
      } else {
        await _loadAttachments();
      }
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _postCommentOnly(AppState state, Task task) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final c = await SupabaseService.insertSingularCommentRow(
        taskId: task.id,
        description: text,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (c.error != null && mounted) {
        await _showInfo('Could not add comment', c.error!);
        return;
      }
      _commentController.clear();
      await _loadComments();
      await _notifyEmail(
        'Task comment email',
        (token) => BackendApi().notifyTaskCommentAdded(
          idToken: token,
          commentId: c.commentId ?? '',
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  bool _canMarkComplete(Task task) {
    final db = task.dbStatus?.trim() ?? '';
    if (db == 'Deleted') return false;
    if (task.status == TaskStatus.done || db == 'Completed') return false;
    if (task.submission?.trim() == 'Submitted') return false;
    return true;
  }

  Future<void> _markCompleted(AppState state, Task task) async {
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final completedAt = task.submitDate ?? DateTime.now().toUtc();
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Completed',
        submission: 'Accepted',
        updateByStaffLookupKey: state.userStaffAppId,
        completionDateAt: completedAt,
      );
      if (err != null && mounted) {
        await _showInfo('Could not mark task completed', err);
        return;
      }
      state.replaceTask(
        task.copyWith(
          dbStatus: 'Completed',
          status: TaskStatus.done,
          submission: 'Accepted',
          completionDate: completedAt,
        ),
      );
      if (task.submission?.trim() == 'Submitted') {
        await _notifyEmail(
          'Task accepted email',
          (token) => BackendApi().notifyTaskAccepted(
            idToken: token,
            taskId: task.id,
          ),
        );
      }
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _submitTask(AppState state, Task task) async {
    if (_subtasks.any(subtaskPreventsParentTaskSubmission)) {
      await _showInfo('Sub-tasks incomplete', 'Complete all sub-tasks before submitting.');
      return;
    }
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        submission: 'Submitted',
        updateByStaffLookupKey: state.userStaffAppId,
        stampSubmitDateNow: true,
      );
      if (err != null && mounted) {
        await _showInfo('Could not submit task', err);
        return;
      }
      state.replaceTask(
        task.copyWith(submission: 'Submitted', submitDate: DateTime.now().toUtc()),
      );
      await _notifyEmail(
        'Task submission email',
        (token) => BackendApi().notifyTaskSubmission(
          idToken: token,
          taskId: task.id,
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _acceptTask(AppState state, Task task) async {
    await _markCompleted(state, task);
  }

  Future<void> _returnTask(AppState state, Task task) async {
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        submission: 'Returned',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        await _showInfo('Could not return task', err);
        return;
      }
      state.replaceTask(task.copyWith(submission: 'Returned'));
      await _notifyEmail(
        'Task returned email',
        (token) => BackendApi().notifyTaskReturned(
          idToken: token,
          taskId: task.id,
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  bool _canUndoAcceptOrReturn(Task task) {
    if ((task.dbStatus ?? '').trim().toLowerCase() == 'deleted') return false;
    final s = task.submission?.trim().toLowerCase() ?? '';
    return s == 'accepted' || s == 'returned';
  }

  Future<void> _undoAcceptOrReturn(AppState state, Task task) async {
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Incomplete',
        submission: 'Pending',
        updateByStaffLookupKey: state.userStaffAppId,
        clearCompletionDate: true,
      );
      if (err != null && mounted) {
        await _showInfo('Could not undo task status', err);
        return;
      }
      state.replaceTask(
        task.copyWith(
          dbStatus: 'Incomplete',
          status: TaskStatus.todo,
          submission: 'Pending',
          clearCompletionDate: true,
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _undoDeleted(AppState state, Task task) async {
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Incomplete',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        await _showInfo('Could not restore task', err);
        return;
      }
      state.replaceTask(
        task.copyWith(dbStatus: 'Incomplete', status: TaskStatus.todo),
      );
      await _loadSubtasks();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _deleteTask(AppState state, Task task) async {
    final go = await showAsanaConfirmDialog(
      context: context,
      title: 'Delete task?',
      content: 'This marks the task as deleted.',
      confirmText: 'Delete',
      isDestructive: true,
      palette: widget.palette,
    );
    if (go != true || !mounted) return;
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Deleted',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        await _showInfo('Could not delete task', err);
        return;
      }
      await SupabaseService.markSubtasksDeletedForParentTask(
        taskId: task.id,
        updateByStaffLookupKey: state.userStaffAppId,
      );
      state.replaceTask(task.copyWith(dbStatus: 'Deleted'));
      await _loadSubtasks();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Task _buildUpdatedTask(Task task, {required bool clearProject}) {
    String? projectName = task.projectName;
    final selProj = _selectedProjectId?.trim();
    if (clearProject) {
      projectName = null;
    } else if (selProj != null && selProj.isNotEmpty) {
      for (final p in _myProjects) {
        if (p.id == selProj) {
          projectName = p.name.trim();
          break;
        }
      }
    }
    return task.copyWith(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      priority: _localPriority,
      startDate: _startDate,
      endDate: _dueDate,
      projectId: clearProject ? null : _selectedProjectId,
      projectName: projectName,
      clearProject: clearProject,
      changeDueReason:
          _needsChangeDueReason() ? _reasonController.text.trim() : null,
      updateDate: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
  }

  List<({String? content, String? description})> _attachmentPayload() {
    return _attachments
        .map(
          (e) => (
            content: e.urlController.text.trim().isEmpty
                ? null
                : e.urlController.text.trim(),
            description: e.descController.text.trim().isEmpty
                ? null
                : e.descController.text.trim(),
          ),
        )
        .where((r) => (r.content ?? '').isNotEmpty)
        .toList();
  }

  Widget _attachmentDraftTile(
    BuildContext context,
    _AttachmentDraft e, {
    required bool createMode,
    BuildContext? editAnchorContext,
  }) {
    if (e.isPendingFile) {
      final name = e.pendingFilename?.trim().isNotEmpty == true
          ? e.pendingFilename!.trim()
          : 'File';
      return AsanaAttachmentDraftTile(
        isWebsiteLink: false,
        title: name,
        subtitle: createMode
            ? 'Uploads when you create the task'
            : 'Uploads when you save',
        enabled: !_saving,
        onRemove: () => _removeAttachmentDraft(e),
      );
    }
    final url = e.urlController.text.trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final desc = e.descController.text.trim();
    final isLink = _draftShowsAsWebsiteLink(e);
    final title = desc.isNotEmpty ? desc : url;
    return AsanaAttachmentDraftTile(
      isWebsiteLink: isLink,
      title: title,
      url: isLink ? url : null,
      enabled: !_saving,
      onRemove: () => _removeAttachmentDraft(e),
      onEditLink: isLink && editAnchorContext != null
          ? () => _editAttachmentLink(editAnchorContext, e)
          : null,
      onOpenFile: !isLink
          ? () => openAttachmentUrl(context, url, displayFileName: title)
          : null,
    );
  }

  String _creatorDisplayName(AppState state) {
    final id = state.userStaffAppId?.trim();
    if (id == null || id.isEmpty) return '';
    return _nameFor(state, id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final chrome = AsanaSlideChrome(widget.palette);
    if (!widget.createMode) {
      final task = state.taskById(widget.taskId ?? '');
      if (task == null) {
        return SizedBox.expand(
          child: ColoredBox(
            color: chrome.body,
            child: const Center(child: Text('Task not found')),
          ),
        );
      }
      return _buildTaskBody(context, state, task, chrome);
    }
    return _buildCreateBody(context, state, chrome);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<({String url, String description})> _websiteAttachmentsForAi() {
    return _attachments
        .where((a) => a.isWebsiteLink)
        .map(
          (a) => (
            url: a.urlController.text.trim(),
            description: a.descController.text.trim(),
          ),
        )
        .where((w) => w.url.isNotEmpty)
        .toList();
  }

  AsanaTaskAiFormSnapshot _aiFormSnapshot(
    AppState state, {
    required bool canSuggestAssignees,
  }) {
    final assigneesLabel = _selectedAssigneeIds
        .map((id) => _labelForAssigneeId(id, state))
        .where((n) => n.isNotEmpty)
        .join(', ');
    final picLabel = _picAssigneeId != null
        ? _labelForAssigneeId(_picAssigneeId!, state)
        : '';
    return AsanaTaskAiFormSnapshot(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      commentDraft: _commentController.text.trim(),
      projectLabel: _projectLabelForDraft(),
      assigneesLabel: assigneesLabel,
      picLabel: picLabel,
      priority: _localPriority,
      startDate: _startDate,
      dueDate: _dueDate,
      projects: _myProjects
          .map((p) => (id: p.id, name: p.name.trim()))
          .where((p) => p.name.isNotEmpty)
          .toList(),
      staff: _pickerStaff
          .map((s) => (id: s.assigneeId, name: s.name.trim()))
          .where((s) => s.name.isNotEmpty)
          .toList(),
      canSuggestProject: _myProjects.isNotEmpty,
      canSuggestAssignees: canSuggestAssignees,
      selectedAssigneeIds: Set<String>.from(_selectedAssigneeIds),
      selectedProjectId: _selectedProjectId,
      picAssigneeId: _picAssigneeId,
      websiteAttachments: _websiteAttachmentsForAi(),
    );
  }

  AsanaTaskAiApply _aiApplyHandlers() {
    return AsanaTaskAiApply(
      applyName: (v) => setState(() => _nameController.text = v),
      applyDescription: (v) => setState(() => _descController.text = v),
      applyProject: (id) => setState(() => _selectedProjectId = id),
      applyAssignees: (ids) => setState(() {
        _selectedAssigneeIds
          ..clear()
          ..addAll(ids);
        _syncPicAfterAssigneesChange();
      }),
      applyPic: (id) => setState(() => _picAssigneeId = id),
      applyPriority: (p) => setState(() => _localPriority = p),
      applyStartDate: (d) => setState(() => _startDate = _dateOnly(d)),
      applyDueDate: (d) => setState(() => _dueDate = _dateOnly(d)),
      applyWebsiteLink: (url, desc) => setState(() {
        _attachments.add(
          _AttachmentDraft(
            url: url,
            desc: desc,
            isWebsiteLink: true,
          ),
        );
      }),
      applyComment: (v) => setState(() => _commentController.text = v),
    );
  }

  void _ensureTaskAi(AppState state, {required bool canSuggestAssignees}) {
    _taskAiCanSuggestAssignees = canSuggestAssignees;
    _taskAi ??= AsanaTaskAiController(
      mode: AsanaTaskAiAssistantMode.taskFields,
      readOnly: () => _saving,
      formSnapshot: () => _aiFormSnapshot(
        state,
        canSuggestAssignees: _taskAiCanSuggestAssignees,
      ),
      apply: _aiApplyHandlers(),
    );
  }

  void _ensureCommentAi(Task task) {
    _commentAi ??= AsanaTaskAiController(
      mode: AsanaTaskAiAssistantMode.commentOnly,
      readOnly: () => _saving,
      commentSnapshot: () => AsanaCommentAiFormSnapshot(
        taskName: task.name.trim().isNotEmpty
            ? task.name.trim()
            : _nameController.text.trim(),
        currentComment: _commentController.text,
        websiteAttachments: _websiteAttachmentsForAi(),
      ),
      onApplyComment: (v) => setState(() => _commentController.text = v),
      onApplyWebsiteLink: _applyWebsiteLinkFromAi,
    );
  }

  void _applyWebsiteLinkFromAi(String url, String desc) {
    setState(() {
      _attachments.add(_AttachmentDraft(
        id: 'ai_${DateTime.now().millisecondsSinceEpoch}',
        url: url,
        desc: desc,
        isWebsiteLink: true,
      ));
    });
  }

  Widget? _buildSlideFooterStack({
    required AsanaSlideChrome chrome,
    required Widget? actionBar,
    AsanaTaskAiController? aiController,
  }) {
    if (aiController == null && actionBar == null) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (aiController != null)
          AsanaTaskAiDock(
            controller: aiController,
            palette: widget.palette,
            footerBorder: chrome.footerBorder,
          ),
        if (actionBar != null)
          AsanaDetailSlideFooter(
            backgroundColor: chrome.footer,
            borderColor: chrome.footerBorder,
            child: actionBar,
          ),
      ],
    );
  }

  Widget _aiSuggestions(
    AsanaTaskAiFieldKey key, {
    AsanaTaskAiController? controller,
  }) {
    final c = controller ?? _taskAi;
    if (c == null) return const SizedBox.shrink();
    return AsanaTaskAiInlineSuggestions(
      controller: c,
      fieldKey: key,
      palette: widget.palette,
    );
  }

  Widget _buildCreateBody(
    BuildContext context,
    AppState state,
    AsanaSlideChrome chrome,
  ) {
    const canEdit = true;
    _ensureTaskAi(state, canSuggestAssignees: true);
    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: _buildSlideFooterStack(
        chrome: chrome,
        aiController: _taskAi,
        actionBar: _ActionBar(
          createMode: true,
          saving: _saving,
          palette: widget.palette,
          onPrimary: () => _createTask(state),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsanaDetailLabelValue(
            label: 'Name',
            child: AsanaHoverTextField(
              controller: _nameController,
              canEdit: canEdit,
              readOnly: _saving,
              showOutline: true,
              maxLines: 3,
              minLines: 1,
              hintText: 'Please fill in task name',
              style: asanaDetailValueStyle(context),
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.taskName),
          AsanaDetailLabelValue(
            label: 'Description',
            child: AsanaHoverTextField(
              controller: _descController,
              canEdit: canEdit,
              readOnly: _saving,
              showOutline: true,
              maxLines: 8,
              minLines: 3,
              hintText: 'Please fill in task description',
              style: asanaDetailMultilineValueStyle(context),
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.description),
          AsanaDetailTwoColumnRow(
            label: 'Project',
            child: _myProjects.isNotEmpty
                ? AsanaHoverTapValue(
                    anchorLink: _projectAnchorLink,
                    value: _projectLabelForDraft(),
                    canEdit: true,
                    emptyPlaceholder: 'Select project (optional)',
                    onTap: _pickProject,
                  )
                : const AsanaDetailPlainValue(text: ''),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.project),
          ..._buildAssigneePicSection(
            context,
            state,
            canEditAssignees: true,
            creatorLabel: _creatorDisplayName(state),
            showAiSuggestions: true,
          ),
          AsanaDetailTwoColumnRow(
            label: 'Priority',
            child: Builder(
              builder: (anchorContext) => CompositedTransformTarget(
                link: _priorityAnchorLink,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _saving
                          ? null
                          : () => _pickPriority(anchorContext),
                      child: AsanaPriorityChip(priority: _localPriority),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.priority),
          const AsanaDetailTwoColumnRow(
            label: 'Status',
            child: AsanaDetailStatusPill(status: 'Incomplete'),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Start date',
            child: AsanaHoverTapValue(
              value: _formatDate(_startDate),
              canEdit: true,
              emptyPlaceholder: 'Today',
              onTap: _saving ? null : _pickStartDueRange,
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.startDate),
          AsanaDetailTwoColumnRow(
            label: 'Due date',
            child: AsanaHoverTapValue(
              value: _formatDate(_dueDate),
              canEdit: true,
              onTap: _saving ? null : _pickStartDueRange,
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
          if (_needsChangeDueReason())
            AsanaDetailLabelValue(
              label: 'Reason',
              child: AsanaHoverTextField(
                controller: _reasonController,
                canEdit: true,
                readOnly: _saving,
                showOutline: true,
                maxLines: 4,
                minLines: 2,
                hintText: 'Required for this due date span',
                style: asanaDetailMultilineValueStyle(context),
              ),
            ),
          const AsanaDetailTwoColumnRow(
            label: 'Submission',
            child: AsanaDetailSubmissionPill(submission: 'Pending'),
          ),
          AsanaDetailSectionHeader(
            title: 'Attachments',
            showAddButton: true,
            addTooltip: 'Add attachment',
            addAnchorLink: _attachmentAddAnchorLink,
            onAdd: (ctx) => _showAttachmentSourceMenu(ctx),
            addEnabled: !_saving,
          ),
          ..._attachments.map(
            (e) => _attachmentDraftTile(
              context,
              e,
              createMode: true,
              editAnchorContext: context,
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.websiteLink),
          AsanaDetailLabelValue(
            label: 'Comments',
            child: AsanaHoverTextField(
              controller: _commentController,
              canEdit: canEdit,
              readOnly: _saving,
              showOutline: true,
              maxLines: 4,
              minLines: 2,
              hintText: 'Optional comment',
              style: asanaDetailMultilineValueStyle(context),
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.comment),
        ],
      ),
    );
  }

  Widget _buildTaskBody(
    BuildContext context,
    AppState state,
    Task task,
    AsanaSlideChrome chrome,
  ) {
    final canEdit = _canEditMetadata(state, task);
    final tc = widget.palette.tableColors;

    final showActionFooter = _ActionBar.hasVisibleActions(
      createMode: false,
      task: task,
      isCreator: _isCreator(state, task),
      isPic: _isPic(state, task),
      isAssigneeOnly: _isTaskAssignee(state, task) &&
          !_isCreator(state, task) &&
          !_isPic(state, task),
      canDelete: _isCreator(state, task),
      canMarkComplete: _canMarkComplete(task),
      canUndoAcceptOrReturn: _canUndoAcceptOrReturn(task),
    );

    final showCommentAi =
        _canWriteComments(state, task) && !canEdit;
    if (canEdit) {
      _ensureTaskAi(
        state,
        canSuggestAssignees: _isCreator(state, task),
      );
    }
    if (showCommentAi) {
      _ensureCommentAi(task);
    }
    final aiController = canEdit
        ? _taskAi
        : (showCommentAi ? _commentAi : null);
    final actionBar = showActionFooter
        ? _ActionBar(
            createMode: false,
            saving: _saving,
            palette: widget.palette,
            state: state,
            task: task,
            isCreator: _isCreator(state, task),
            isPic: _isPic(state, task),
            isAssigneeOnly: _isTaskAssignee(state, task) &&
                !_isCreator(state, task) &&
                !_isPic(state, task),
            canDelete: _isCreator(state, task),
            onUpdate: () => _save(state, task),
            onMarkComplete: () => _markCompleted(state, task),
            onSubmit: () => _submitTask(state, task),
            onAccept: () => _acceptTask(state, task),
            onReturn: () => _returnTask(state, task),
            onDelete: () => _deleteTask(state, task),
            onUndoAcceptOrReturn: () => _undoAcceptOrReturn(state, task),
            onUndoDeleted: () => _undoDeleted(state, task),
            canMarkComplete: _canMarkComplete(task),
            canUndoAcceptOrReturn: _canUndoAcceptOrReturn(task),
          )
        : null;

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: _buildSlideFooterStack(
        chrome: chrome,
        aiController: aiController,
        actionBar: actionBar,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AsanaHoverTextField(
                    controller: _nameController,
                    canEdit: canEdit,
                    readOnly: _saving,
                    maxLines: 6,
                    minLines: 1,
                    style: asanaDetailTitleStyle(context),
                  ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.taskName),
                  const SizedBox(height: 12),
                  AsanaDetailLabelValue(
                    label: 'Description',
                    child: AsanaHoverTextField(
                      controller: _descController,
                      canEdit: canEdit,
                      readOnly: _saving,
                      maxLines: 8,
                      minLines: 2,
                        hintText: 'Please fill in task description',
                      style: asanaDetailMultilineValueStyle(context),
                    ),
                  ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.description),
                  AsanaDetailTwoColumnRow(
                    label: 'Project',
                    child: canEdit && _myProjects.isNotEmpty
                        ? AsanaHoverTapValue(
                            anchorLink: _projectAnchorLink,
                            value: _projectLabel(task),
                            canEdit: true,
                            emptyPlaceholder: 'Select project (optional)',
                            onTap: _pickProject,
                          )
                        : AsanaDetailPlainValue(
                            text: task.projectName?.trim() ?? '',
                          ),
                  ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.project),
                  ..._buildAssigneePicSection(
                    context,
                    state,
                    canEditAssignees: canEdit && _isCreator(state, task),
                    creatorLabel: task.createByStaffName?.trim() ?? '',
                    readOnlyAssigneesText: task.assigneeIds
                        .map((id) => _nameFor(state, id))
                        .where((n) => n.isNotEmpty)
                        .join(', '),
                    readOnlyPicText: _nameFor(state, task.pic),
                    showAiSuggestions: canEdit,
                  ),
                  AsanaDetailSectionHeader(
                    title: 'Sub-tasks',
                    showAddButton: true,
                    addTooltip: 'Create sub-task',
                    onAdd: widget.onPushCreateSubtask != null
                        ? (_) => widget.onPushCreateSubtask!()
                        : null,
                    addEnabled: canEdit &&
                        !singularTaskStatusIsCompleted(task) &&
                        !_saving &&
                        widget.onPushCreateSubtask != null,
                  ),
                  if (_subtasks.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return AsanaDetailSubtaskList(
                          viewportWidth: constraints.maxWidth,
                          subtasks: _subtasks,
                          tableColors: tc,
                          appState: state,
                          nameAndDueOnly: true,
                          onOpenSubtask: widget.onPushSubtask,
                        );
                      },
                    ),
                  if (_subtasks.isNotEmpty) const SizedBox(height: 8),
                  AsanaDetailTwoColumnRow(
                    label: 'Priority',
                    child: Builder(
                      builder: (anchorContext) => CompositedTransformTarget(
                        link: _priorityAnchorLink,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: canEdit
                              ? MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: _saving
                                        ? null
                                        : () => _pickPriority(anchorContext),
                                    child: AsanaPriorityChip(
                                      priority: _localPriority,
                                    ),
                                  ),
                                )
                              : AsanaPriorityChip(priority: task.priority),
                        ),
                      ),
                    ),
                  ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.priority),
                  AsanaDetailTwoColumnRow(
                    label: 'Status',
                    child: AsanaDetailStatusPill(
                      status: TaskListCard.statusLabel(task),
                    ),
                  ),
                  AsanaDetailTwoColumnRow(
                    label: 'Start date',
                    child: AsanaHoverTapValue(
                      value: _formatDate(_startDate),
                      canEdit: canEdit,
                      onTap: _saving ? null : _pickStartDueRange,
                    ),
                  ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.startDate),
                  AsanaDetailTwoColumnRow(
                    label: 'Due date',
                    child: AsanaHoverTapValue(
                      value: _formatDate(_dueDate),
                      canEdit: canEdit,
                      onTap: _saving ? null : _pickStartDueRange,
                    ),
                  ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
                  if (_needsChangeDueReason() ||
                      (task.changeDueReason ?? '').trim().isNotEmpty)
                    AsanaDetailLabelValue(
                      label: 'Reason',
                      child: AsanaHoverTextField(
                        controller: _reasonController,
                        canEdit: canEdit,
                        readOnly: _saving,
                        maxLines: 4,
                        minLines: 2,
                        style: asanaDetailMultilineValueStyle(context),
                      ),
                    ),
                  AsanaDetailTwoColumnRow(
                    label: 'Submission',
                    child: AsanaDetailSubmissionPill(submission: task.submission),
                  ),
                  if ((task.updateByStaffName ?? '').trim().isNotEmpty)
                    AsanaDetailTwoColumnRow(
                      label: 'Last updated by',
                      child: AsanaDetailPlainValue(
                        text: task.updateByStaffName!.trim(),
                      ),
                    ),
                  if (task.lastUpdated != null)
                    AsanaDetailTwoColumnRow(
                      label: 'Last updated',
                      child: AsanaDetailPlainValue(
                        text: _formatDateTime(task.lastUpdated),
                      ),
                    ),
                  AsanaDetailSectionHeader(
                    title: 'Attachments',
                    showAddButton: true,
                    addTooltip: 'Add attachment',
                    addAnchorLink: _attachmentAddAnchorLink,
                    onAdd: (ctx) =>
                        _showAttachmentSourceMenu(ctx, task: task),
                    addEnabled: _canEditAttachments(state, task) && !_saving,
                  ),
                  if (_loadingExtras)
                    const LinearProgressIndicator()
                  else if (_attachments.isEmpty)
                    const SizedBox(height: 4)
                  else
                    Builder(
                      builder: (attachmentCtx) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _attachments
                            .map(
                              (e) => _attachmentDraftTile(
                                context,
                                e,
                                createMode: false,
                                editAnchorContext: attachmentCtx,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (canEdit)
                    _aiSuggestions(AsanaTaskAiFieldKey.websiteLink)
                  else if (showCommentAi)
                    _aiSuggestions(
                      AsanaTaskAiFieldKey.websiteLink,
                      controller: _commentAi,
                    ),
                  AsanaDetailLabelValue(
                    label: 'Comments',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_canWriteComments(state, task)) ...[
                          AsanaHoverTextField(
                            controller: _commentController,
                            canEdit: true,
                            readOnly: _saving,
                            maxLines: 4,
                            minLines: 2,
                            style: asanaDetailMultilineValueStyle(context),
                          ),
                          if (canEdit)
                            _aiSuggestions(AsanaTaskAiFieldKey.comment)
                          else if (showCommentAi)
                            _aiSuggestions(
                              AsanaTaskAiFieldKey.comment,
                              controller: _commentAi,
                            ),
                        ],
                        if (_comments.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ..._comments.map(
                            (c) => _buildCommentDisplayTile(context, c),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
    );
  }

  String _projectLabelForDraft() {
    final id = _selectedProjectId?.trim();
    if (id == null || id.isEmpty) return '';
    final hit = _myProjects.where((p) => p.id == id).toList();
    if (hit.isNotEmpty) return hit.first.name.trim();
    return id;
  }

  String _projectLabel(Task task) {
    final draft = _projectLabelForDraft();
    if (draft.isNotEmpty) return draft;
    return task.projectName?.trim() ?? '';
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.createMode,
    required this.saving,
    required this.palette,
    this.onPrimary,
    this.state,
    this.task,
    this.isCreator = false,
    this.isPic = false,
    this.isAssigneeOnly = false,
    this.canDelete = false,
    this.onUpdate,
    this.onMarkComplete,
    this.onSubmit,
    this.onAccept,
    this.onReturn,
    this.onDelete,
    this.onUndoAcceptOrReturn,
    this.onUndoDeleted,
    this.canMarkComplete = false,
    this.canUndoAcceptOrReturn = false,
  });

  final bool createMode;
  final bool saving;
  final AsanaLandingPalette palette;
  final VoidCallback? onPrimary;
  final AppState? state;
  final Task? task;
  final bool isCreator;
  final bool isPic;
  final bool isAssigneeOnly;
  final bool canDelete;
  final VoidCallback? onUpdate;
  final VoidCallback? onMarkComplete;
  final VoidCallback? onSubmit;
  final VoidCallback? onAccept;
  final VoidCallback? onReturn;
  final VoidCallback? onDelete;
  final VoidCallback? onUndoAcceptOrReturn;
  final VoidCallback? onUndoDeleted;
  final bool canMarkComplete;
  final bool canUndoAcceptOrReturn;

  /// Whether the slide footer should render (avoids an empty white bar).
  static bool hasVisibleActions({
    required bool createMode,
    Task? task,
    bool isCreator = false,
    bool isPic = false,
    bool isAssigneeOnly = false,
    bool canDelete = false,
    bool canMarkComplete = false,
    bool canUndoAcceptOrReturn = false,
  }) {
    if (createMode) return true;
    if (task == null) return false;
    final deleted = (task.dbStatus ?? '').trim().toLowerCase() == 'deleted';
    if (!deleted && (isCreator || isPic || isAssigneeOnly)) return true;
    if (!deleted && isCreator && canMarkComplete) return true;
    if (!deleted && isCreator && canUndoAcceptOrReturn) return true;
    if (!deleted && isPic && _canPicSubmit(task)) return true;
    if (!deleted &&
        isCreator &&
        task.submission?.trim() == 'Submitted') {
      return true;
    }
    if (canDelete) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (createMode) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            onPressed: saving ? null : onPrimary,
            style: AsanaTaskDetailActionStyles.createFilled(palette),
            child: Text(saving ? 'Creating…' : 'Create'),
          ),
        ],
      );
    }

    final t = task!;
    final deleted = (t.dbStatus ?? '').trim().toLowerCase() == 'deleted';
    final showUpdate =
        !deleted && (isCreator || isPic || isAssigneeOnly);
    final buttons = <Widget>[];

    if (showUpdate) {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onUpdate,
          style: AsanaTaskDetailActionStyles.updateFilled(palette),
          child: Text(saving ? 'Saving…' : 'Update'),
        ),
      );
    }
    if (!deleted && isCreator && canMarkComplete) {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onMarkComplete,
          style: AsanaTaskDetailActionStyles.successFilled(),
          child: const Text('Mark as Completed'),
        ),
      );
    }
    if (!deleted && isCreator && canUndoAcceptOrReturn) {
      buttons.add(
        OutlinedButton(
          onPressed: saving ? null : onUndoAcceptOrReturn,
          style: AsanaTaskDetailActionStyles.undoOutlined(palette),
          child: const Text('Undo'),
        ),
      );
    }
    if (!deleted && isPic && _canPicSubmit(t)) {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onSubmit,
          style: AsanaTaskDetailActionStyles.submitFilled(palette),
          child: const Text('Submit'),
        ),
      );
    }
    if (!deleted && isCreator && t.submission?.trim() == 'Submitted') {
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onAccept,
          style: AsanaTaskDetailActionStyles.successFilled(),
          child: const Text('Accept'),
        ),
      );
      buttons.add(
        FilledButton(
          onPressed: saving ? null : onReturn,
          style: AsanaTaskDetailActionStyles.returnFilled(),
          child: const Text('Return'),
        ),
      );
    }
    if (canDelete) {
      if (deleted) {
        buttons.add(
          OutlinedButton(
            onPressed: saving ? null : onUndoDeleted,
            style: AsanaTaskDetailActionStyles.undoOutlined(palette),
            child: const Text('Undo'),
          ),
        );
      } else {
        buttons.add(
          FilledButton(
            onPressed: saving ? null : onDelete,
            style: AsanaTaskDetailActionStyles.deleteFilled(),
            child: const Text('Delete'),
          ),
        );
      }
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: buttons,
      ),
    );
  }

  static bool _canPicSubmit(Task task) {
    final s = task.submission?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return true;
    if (s == 'returned') return true;
    return s != 'submitted' && s != 'accepted';
  }
}
