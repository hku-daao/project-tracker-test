import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/singular_comment.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../services/backend_api.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/attachment_file_pick.dart';
import '../../utils/attachment_url_launch.dart';
import '../../utils/hk_time.dart';
import '../app_bootstrap.dart';
import '../asana_landing_screen.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_attachment_draft_tile.dart';
import 'asana_attachment_menu.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_inline_image_widgets.dart';
import 'asana_project_ai_assistant.dart';
import 'asana_project_filter.dart';
import 'asana_task_ai_assistant.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

class _ProjectAttachmentDraft {
  _ProjectAttachmentDraft({
    this.id,
    String? url,
    String? desc,
    this.mimeType,
    this.isWebsiteLink = false,
  }) : urlController = TextEditingController(text: url ?? ''),
       descController = TextEditingController(text: desc ?? '');

  final String? id;
  final TextEditingController urlController;
  final TextEditingController descController;
  Uint8List? pendingBytes;
  String? pendingFilename;
  String? mimeType;
  bool isWebsiteLink;

  bool get isPendingFile => pendingBytes != null;

  void dispose() {
    urlController.dispose();
    descController.dispose();
  }
}

class _ProjectInlineImageDraft {
  _ProjectInlineImageDraft({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.bytes,
    required this.label,
    this.mimeType = 'image/*',
    this.sortOrder = 0,
  });

  final String id;
  final String entityType;
  final String entityId;
  final Uint8List bytes;
  final String label;
  final String mimeType;
  final int sortOrder;
}

/// Project slide — creator can edit all project fields (matches task slide layout).
class AsanaProjectDetailPanel extends StatefulWidget {
  const AsanaProjectDetailPanel({
    super.key,
    required this.projectId,
    required this.palette,
    required this.onClose,
    this.refreshToken = 0,
    this.onChanged,
    this.onPushCreateTask,
    this.onPushTask,
  });

  final String projectId;
  final AsanaLandingPalette palette;
  final int refreshToken;
  final VoidCallback onClose;
  final VoidCallback? onChanged;
  final VoidCallback? onPushCreateTask;
  final void Function(String taskId)? onPushTask;

  @override
  State<AsanaProjectDetailPanel> createState() =>
      _AsanaProjectDetailPanelState();
}

class _AsanaProjectDetailPanelState extends State<AsanaProjectDetailPanel> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentController = TextEditingController();

  ProjectRecord? _project;
  List<Task> _tasks = [];
  List<ProjectCommentRowDisplay> _comments = [];
  final Map<String, TextEditingController> _postedCommentControllers = {};
  final Map<String, String> _postedCommentSavedText = {};
  String? _savingPostedCommentId;
  final List<_ProjectAttachmentDraft> _attachments = [];
  List<InlineAttachmentRow> _descriptionInlineImages = [];
  Map<String, List<InlineAttachmentRow>> _commentInlineImages = {};
  final List<_ProjectInlineImageDraft> _pendingInlineImageAdds = [];
  final List<InlineAttachmentRow> _pendingInlineImageDeletes = [];
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
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot = ValueNotifier(
    const AsanaAssigneePickerSnapshot(loading: true),
  );

  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  final LayerLink _attachmentAddAnchorLink = LayerLink();
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
    if (oldWidget.projectId != widget.projectId) {
      _bootstrap();
    } else if (oldWidget.refreshToken != widget.refreshToken) {
      _loadProjectTasks();
    }
  }

  @override
  void dispose() {
    AsanaBlockingLoadingOverlay.hideAll();
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    for (final ctrl in _postedCommentControllers.values) {
      ctrl.dispose();
    }
    for (final attachment in _attachments) {
      attachment.dispose();
    }
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
      _loadProjectTasks(),
      _loadComments(),
      _loadAttachments(),
      _loadProjectDescriptionInlineImages(),
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

  Future<void> _loadProjectTasks() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchSingularTasksForProject(
        widget.projectId,
      );
      if (!mounted) return;
      setState(
        () => _tasks = list
            .where((t) => !_taskDeleted(t) && !t.isArchivedCompleted)
            .toList(),
      );
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchProjectComments(widget.projectId);
      if (!mounted) return;
      setState(() => _comments = list);
      await _loadCommentInlineImages(list);
    } catch (_) {}
  }

  Future<void> _loadProjectDescriptionInlineImages() async {
    if (!SupabaseConfig.isConfigured) return;
    final list = await SupabaseService.fetchInlineAttachments(
      entityType: 'project_description',
      entityId: widget.projectId,
    );
    if (mounted) setState(() => _descriptionInlineImages = list);
  }

  Future<void> _loadCommentInlineImages(
    List<ProjectCommentRowDisplay> comments,
  ) async {
    if (!SupabaseConfig.isConfigured || comments.isEmpty) return;
    final next = <String, List<InlineAttachmentRow>>{};
    for (final comment in comments) {
      final list = await SupabaseService.fetchInlineAttachments(
        entityType: 'project_comment',
        entityId: comment.id,
      );
      if (list.isNotEmpty) next[comment.id] = list;
    }
    if (mounted) setState(() => _commentInlineImages = next);
  }

  Future<void> _loadAttachments() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final files = await SupabaseService.fetchFileAttachments(
        entityType: 'project',
        entityId: widget.projectId,
      );
      final urls = await SupabaseService.fetchUrlAttachments(
        entityType: 'project',
        entityId: widget.projectId,
      );
      if (!mounted) return;
      setState(() {
        _clearAttachments();
        for (final r in files) {
          _attachments.add(
            _ProjectAttachmentDraft(
              id: r.id,
              url: r.url,
              desc: (r.description?.trim().isNotEmpty == true)
                  ? r.description
                  : r.filename,
              mimeType: r.mimeType,
            ),
          );
        }
        for (final r in urls) {
          _attachments.add(
            _ProjectAttachmentDraft(
              id: r.id,
              url: r.url,
              desc: r.label,
              isWebsiteLink: true,
            ),
          );
        }
      });
    } catch (_) {}
  }

  void _clearAttachments() {
    for (final a in _attachments) {
      a.dispose();
    }
    _attachments.clear();
  }

  void _clearInlineImageDrafts() {
    _pendingInlineImageAdds.clear();
    _pendingInlineImageDeletes.clear();
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
      DateTime.now().millisecondsSinceEpoch >
      _anchoredPickerReopenBlockedUntilMs;

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

  String _formatShortDate(DateTime? d) {
    if (d == null) return '—';
    final today = HkTime.todayDateOnlyHk();
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    return HkTime.formatInstantAsHk(d, 'MMM d');
  }

  bool _taskDeleted(Task t) {
    final s = (t.dbStatus ?? '').trim().toLowerCase();
    return s == 'deleted' || s == 'delete';
  }

  bool _taskCompleted(Task t) {
    final s = (t.dbStatus ?? '').trim().toLowerCase();
    return s == 'completed' || s == 'complete' || t.status == TaskStatus.done;
  }

  String _taskStatusLabel(Task t) {
    if ((_project?.isPaused ?? false) || t.isPaused) return 'Paused';
    final raw = t.dbStatus?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return taskStatusDisplayNames[t.status] ?? 'Incomplete';
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

  void _showEmailWarning(String label, String error) {
    if (error.trim().toLowerCase() == 'mailgun not configured') return;
    debugPrint('$label: $error');
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
    return ids.map((id) => _labelForAssigneeId(id, state)).join(', ');
  }

  List<Map<String, String>> _projectChangesForEmail(
    AppState state,
    ProjectRecord p,
  ) {
    final changes = <Map<String, String>>[];
    _addChange(changes, 'projectName', p.name, _nameController.text.trim());
    _addChange(
      changes,
      'description',
      p.description,
      _descController.text.trim(),
    );
    _addChange(
      changes,
      'assignees',
      AsanaProjectFilter.assigneesLine(p, state),
      _namesFor(state, _assigneeIds),
    );
    _addChange(
      changes,
      'pic',
      AsanaProjectFilter.picLine(p, state),
      _namesFor(state, _picAssigneeIds),
    );
    _addChange(changes, 'status', p.status, _effectiveStatus(p));
    _addChange(
      changes,
      'startDate',
      _formatDate(p.startDate),
      _formatDate(_startDate),
    );
    _addChange(
      changes,
      'endDate',
      _formatDate(p.endDate),
      _formatDate(_endDate),
    );
    return changes;
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
    await showAsanaAssigneePicker(
      anchorLink: _picAnchorLink,
      anchorContext: anchorContext,
      snapshot: _picSnapshot,
      selectedIds: _picAssigneeIds,
      whenClosed: _blockAnchoredPickerReopen,
      directListOnly: true,
      onSelectionChanged: (s) {
        if (!mounted) return;
        setState(() {
          _picAssigneeIds
            ..clear()
            ..addAll(s.where(_assigneeIds.contains));
        });
      },
    );
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

  String _effectiveStatus(ProjectRecord p) => (_draftStatus ?? p.status).trim();
  String _displayStatus(ProjectRecord p) =>
      p.isPaused ? 'Paused' : _effectiveStatus(p);

  bool _canMarkProjectComplete(ProjectRecord p) =>
      _isCreator(p) &&
      !p.isPaused &&
      _effectiveStatus(p) != 'Completed' &&
      _effectiveStatus(p) != 'Deleted';

  bool _canDeleteProject(ProjectRecord p) =>
      _isCreator(p) && _effectiveStatus(p) != 'Deleted';

  bool _canRestoreProject(ProjectRecord p) =>
      _isCreator(p) && _effectiveStatus(p) == 'Deleted';

  Future<void> _setProjectPause(
    AppState state,
    ProjectRecord p, {
    required bool paused,
  }) async {
    if (!_isCreator(p) || _effectiveStatus(p) == 'Deleted') return;
    if (p.isPaused == paused) return;
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        updatePauseStatus: true,
        pauseStatus: paused ? 'Paused' : 'Not Paused',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        await showAsanaInfoDialog(
          context: context,
          title: paused
              ? 'Could not pause project'
              : 'Could not resume project',
          content: err,
          palette: widget.palette,
        );
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      await _loadProject();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _confirmDeleteProject(AppState state) async {
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Delete project',
      content:
          'Delete "${_project?.name ?? 'this project'}"? It will be moved to the Deleted status.',
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
      await _loadProject();
      widget.onChanged?.call();
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  Future<void> _restoreDeletedProject(AppState state, ProjectRecord p) async {
    if (!_canRestoreProject(p)) return;
    _setSaving(true);
    AsanaBlockingLoadingOverlay.show(context);
    try {
      final err = await SupabaseService.updateProjectRow(
        projectId: widget.projectId,
        status: 'Not started',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not restore project',
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
    final picLabel = _picAssigneeIds
        .map((id) => _labelForAssigneeId(id, state))
        .join(', ');
    final staff = _pickerStaff
        .map((s) => (id: s.assigneeId, name: s.name.trim()))
        .where((s) => s.name.isNotEmpty)
        .toList();
    return AsanaProjectAiFormSnapshot(
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      commentDraft: stripInlineImageMarkers(_commentController.text),
      status: _effectiveStatus(_project!),
      startDate: _startDate,
      dueDate: _endDate,
      assigneesLabel: assigneesLabel,
      picLabel: picLabel,
      staff: staff,
      selectedAssigneeIds: Set<String>.from(_assigneeIds),
      selectedPicAssigneeIds: Set<String>.from(_picAssigneeIds),
      websiteAttachments: _websiteAttachmentsForAi(),
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
      applyComment: (v) => setState(() => _commentController.text = v),
      applyWebsiteLink: (url, desc) => setState(() {
        _attachments.add(
          _ProjectAttachmentDraft(url: url, desc: desc, isWebsiteLink: true),
        );
      }),
    );
  }

  void _ensureProjectAi() {
    _projectAi ??= AsanaTaskAiController(
      mode: AsanaTaskAiAssistantMode.projectFields,
      readOnly: () => _saving,
      auditContext: () {
        final state = context.read<AppState>();
        return AsanaAiAuditContext(
          entityType: 'project',
          entityId: widget.projectId,
          staffId: state.userStaffId,
          staffDisplayName: _labelForAssigneeId(
            state.userStaffAppId ?? '',
            state,
          ),
          actionType: 'update',
        );
      },
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
    AsanaBlockingLoadingOverlay.hideAll();
    if (mounted && _saving) {
      setState(() => _saving = false);
    }
    return showAsanaInfoDialog(
      context: context,
      title: title,
      content: content,
      palette: widget.palette,
    );
  }

  static bool _uuidEquals(String? a, String? b) {
    final x = a?.trim().toLowerCase() ?? '';
    final y = b?.trim().toLowerCase() ?? '';
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  bool _isOwnComment(ProjectCommentRowDisplay comment) =>
      !comment.isDeleted && _uuidEquals(comment.createByStaffId, _myStaffUuid);

  DateTime? _commentDisplayTimestamp(ProjectCommentRowDisplay comment) {
    final created = comment.createTimestampUtc;
    final updated = comment.updateTimestampUtc;
    if (updated != null && created != null && updated.isAfter(created)) {
      return updated;
    }
    return created ?? updated;
  }

  String _formatCommentPostedTs(DateTime? stored) {
    if (stored == null) return '';
    return HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm');
  }

  List<String?> _projectAttachmentAclKeys(AppState state, ProjectRecord p) {
    return [
      state.userStaffAppId,
      p.createByStaffUuid,
      ..._picAssigneeIds,
      ..._assigneeIds,
    ];
  }

  Future<void> _removeAttachmentDraft(_ProjectAttachmentDraft draft) async {
    final persistedId = draft.id?.trim();
    if (persistedId != null &&
        persistedId.isNotEmpty &&
        SupabaseConfig.isConfigured) {
      final isWebsiteLink = _draftShowsAsWebsiteLink(draft);
      if (!isWebsiteLink) {
        final storageErr =
            await FirebaseAttachmentUploadService.deleteUploadedObjectByUrl(
              draft.urlController.text.trim(),
            );
        if (!mounted) return;
        if (storageErr != null) {
          await _showInfo('Could not remove uploaded file', storageErr);
          return;
        }
      }
      final err = isWebsiteLink
          ? await SupabaseService.deleteUrlAttachmentById(persistedId)
          : await SupabaseService.deleteFileAttachmentById(persistedId);
      if (!mounted) return;
      if (err != null) {
        await _showInfo('Could not remove attachment', err);
        return;
      }
    }
    setState(() {
      draft.dispose();
      _attachments.remove(draft);
    });
  }

  bool _draftShowsAsWebsiteLink(_ProjectAttachmentDraft draft) {
    if (draft.isPendingFile) return false;
    if (draft.isWebsiteLink) return true;
    final url = draft.urlController.text.trim();
    return url.isNotEmpty && !isAppFirebaseStorageAttachmentUrl(url);
  }

  String? _attachmentMimeTypeFromName(String? name) {
    final n = name?.toLowerCase().trim() ?? '';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    return null;
  }

  bool _attachmentDraftIsImage(_ProjectAttachmentDraft draft) {
    final mime = draft.mimeType?.toLowerCase().trim() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = draft.pendingFilename?.trim().isNotEmpty == true
        ? draft.pendingFilename!.trim()
        : draft.descController.text.trim();
    if (_attachmentMimeTypeFromName(name) != null) return true;
    final rawUrl = draft.urlController.text.trim();
    final uri = Uri.tryParse(rawUrl);
    if (_attachmentMimeTypeFromName(uri?.path) != null) return true;
    final objectPath =
        FirebaseAttachmentUploadService.objectPathFromStorageDownloadUrl(
          rawUrl,
        );
    return _attachmentMimeTypeFromName(objectPath) != null;
  }

  bool _shouldAttemptAttachmentImagePreview(_ProjectAttachmentDraft draft) {
    if (_attachmentDraftIsImage(draft)) return true;
    return !draft.isPendingFile &&
        isAppFirebaseStorageAttachmentUrl(draft.urlController.text.trim());
  }

  Future<void> _editAttachmentLink(
    BuildContext anchorContext,
    _ProjectAttachmentDraft draft,
  ) async {
    if (!_canOpenAnchoredPicker || _saving) return;
    final widthAlignContext =
        _detailPopupWidthAlignKey.currentContext ?? anchorContext;
    final updated = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: widthAlignContext,
      initialUrl: draft.urlController.text,
      initialDescription: draft.descController.text,
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || updated == null) return;
    setState(() {
      draft.urlController.text = updated.url;
      draft.descController.text = updated.description;
      draft.isWebsiteLink = true;
    });
  }

  Future<void> _addFileAttachment(ProjectRecord p) async {
    final state = context.read<AppState>();
    final r = await _withBlockingLoading(
      () => FirebaseAttachmentUploadService.pickUploadFilesForProject(
        p.id,
        aclStaffKeys: _projectAttachmentAclKeys(state, p),
      ),
    );
    if (!mounted) return;
    if (r?.error != null) {
      await _showInfo('Attachment upload failed', r!.error!);
      return;
    }
    final files = r?.files ?? const <({String url, String label})>[];
    if (files.isEmpty) return;
    setState(() {
      for (final file in files) {
        _attachments.add(
          _ProjectAttachmentDraft(
            url: file.url,
            desc: file.label,
            mimeType: _attachmentMimeTypeFromName(file.label),
          ),
        );
      }
    });
  }

  Future<void> _addUrlAttachment(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker) return;
    final widthAlignContext =
        _detailPopupWidthAlignKey.currentContext ?? anchorContext;
    final result = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: widthAlignContext,
      initialUrl: '',
      initialDescription: '',
      onClosed: _blockAnchoredPickerReopen,
    );
    if (!mounted || result == null) return;
    setState(() {
      _attachments.add(
        _ProjectAttachmentDraft(
          url: result.url,
          desc: result.description,
          isWebsiteLink: true,
        ),
      );
    });
  }

  Future<void> _stageInlineImage({
    required String entityType,
    required String entityId,
  }) async {
    final picked = await _withBlockingLoading(pickOneFileWithBytes);
    if (!mounted || picked == null) return;
    if (picked.bytes.isEmpty) {
      await _showInfo(
        'Inline image upload failed',
        'Could not read file data.',
      );
      return;
    }
    final label = picked.name.trim().isNotEmpty ? picked.name.trim() : 'image';
    final id = 'draft_${DateTime.now().microsecondsSinceEpoch}';
    setState(
      () => _pendingInlineImageAdds.add(
        _ProjectInlineImageDraft(
          id: id,
          entityType: entityType,
          entityId: entityId,
          bytes: picked.bytes,
          label: label,
          mimeType: 'image/*',
          sortOrder: _pendingInlineImageAdds
              .where(
                (draft) =>
                    draft.entityType == entityType &&
                    draft.entityId == entityId,
              )
              .length,
        ),
      ),
    );
  }

  void _removeInlineImagePreview(InlineImagePreviewItem image) {
    setState(() {
      final saved = image.inlineAttachment;
      if (saved != null) {
        if (!_pendingInlineImageDeletes.any((row) => row.id == saved.id)) {
          _pendingInlineImageDeletes.add(saved);
        }
      } else {
        _pendingInlineImageAdds.removeWhere((draft) => draft.id == image.id);
      }
    });
  }

  bool _canRemoveInlineAttachment(InlineAttachmentRow row) {
    return FirebaseAttachmentUploadService.storageDownloadUrlBelongsToCurrentUser(
      row.url,
    );
  }

  List<InlineImagePreviewItem> _inlinePreviewItems({
    required String entityType,
    required String entityId,
    required List<InlineAttachmentRow> saved,
  }) {
    final deletedIds = _pendingInlineImageDeletes.map((row) => row.id).toSet();
    final savedItems = saved
        .where((row) => !deletedIds.contains(row.id))
        .map(
          (row) => InlineImagePreviewItem(
            id: row.id,
            inlineAttachment: row,
            url: row.url,
            description: row.description,
            mimeType: row.mimeType,
            canRemove: _canRemoveInlineAttachment(row),
          ),
        );
    final draftItems = _pendingInlineImageAdds
        .where(
          (draft) =>
              draft.entityType == entityType && draft.entityId == entityId,
        )
        .map(
          (draft) => InlineImagePreviewItem(
            id: draft.id,
            bytes: draft.bytes,
            description: draft.label,
            mimeType: draft.mimeType,
            canRemove: true,
          ),
        );
    return [...savedItems, ...draftItems];
  }

  Future<String?> _commitPendingInlineImages({
    required ProjectRecord project,
    required AppState state,
    Map<String, String> entityIdOverrides = const {},
  }) async {
    for (final draft in List<_ProjectInlineImageDraft>.from(
      _pendingInlineImageAdds,
    )) {
      final resolvedEntityId =
          entityIdOverrides[draft.entityId] ?? draft.entityId;
      if (resolvedEntityId.trim().isEmpty || resolvedEntityId == 'draft') {
        continue;
      }
      final upload =
          await FirebaseAttachmentUploadService.uploadBytesForProject(
            project.id,
            bytes: draft.bytes,
            originalFilename: draft.label,
            aclStaffKeys: _projectAttachmentAclKeys(state, project),
          );
      if (upload.error != null) return upload.error;
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return 'Inline image upload did not return a download link.';
      }
      final ins = await SupabaseService.insertInlineAttachment(
        entityType: draft.entityType,
        entityId: resolvedEntityId,
        url: url,
        description: upload.label ?? draft.label,
        mimeType: draft.mimeType,
        creatorStaffLookupKey: state.userStaffAppId,
        sortOrder: draft.sortOrder,
      );
      if (ins.error != null) return ins.error;
    }
    for (final row in List<InlineAttachmentRow>.from(
      _pendingInlineImageDeletes,
    )) {
      final deleteErr =
          await FirebaseAttachmentUploadService.deleteUploadedObjectByUrl(
            row.url,
          );
      if (deleteErr != null) return deleteErr;
      final markErr = await SupabaseService.markInlineAttachmentDeleted(row.id);
      if (markErr != null) return markErr;
      if (row.entityType == 'project_comment') {
        final touchErr = await SupabaseService.touchProjectCommentRow(
          commentId: row.entityId,
          updaterStaffLookupKey: state.userStaffAppId,
        );
        if (touchErr != null) return touchErr;
      }
    }
    _clearInlineImageDrafts();
    return null;
  }

  List<({String? id, String? url, String? filename, String? description})>
  _fileAttachmentPayload() {
    return _attachments
        .where((a) => !a.isPendingFile && !_draftShowsAsWebsiteLink(a))
        .map((a) {
          final url = a.urlController.text.trim();
          final desc = a.descController.text.trim();
          return (
            id: a.id,
            url: url.isEmpty ? null : url,
            filename: desc.isEmpty ? null : desc,
            description: desc.isEmpty ? null : desc,
          );
        })
        .where((r) => (r.url ?? '').isNotEmpty)
        .toList();
  }

  List<({String? id, String? url, String? label})> _urlAttachmentPayload() {
    return _attachments
        .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
        .map((a) {
          final url = a.urlController.text.trim();
          final desc = a.descController.text.trim();
          return (
            id: a.id,
            url: url.isEmpty ? null : url,
            label: desc.isEmpty ? url : desc,
          );
        })
        .where((r) => (r.url ?? '').isNotEmpty)
        .toList();
  }

  Future<String?> _replaceProjectAttachments() async {
    final fileErr = await SupabaseService.replaceFileAttachments(
      entityType: 'project',
      entityId: widget.projectId,
      rows: _fileAttachmentPayload(),
    );
    if (fileErr != null) return fileErr;
    return SupabaseService.replaceUrlAttachments(
      entityType: 'project',
      entityId: widget.projectId,
      rows: _urlAttachmentPayload(),
    );
  }

  List<_ProjectAttachmentDraft> get _fileAttachments => _attachments
      .where((a) => a.isPendingFile || !_draftShowsAsWebsiteLink(a))
      .toList();

  List<_ProjectAttachmentDraft> get _urlAttachments => _attachments
      .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
      .toList();

  List<({String url, String description})> _websiteAttachmentsForAi() {
    return _attachments
        .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
        .map(
          (a) => (
            url: a.urlController.text.trim(),
            description: a.descController.text.trim(),
          ),
        )
        .where((a) => a.url.isNotEmpty)
        .toList();
  }

  Future<void> _savePostedCommentOnBlur(
    ProjectCommentRowDisplay comment,
  ) async {
    if (_savingPostedCommentId == comment.id) return;
    final ctrl = _postedCommentControllers[comment.id];
    if (ctrl == null) return;
    final newBody = stripInlineImageMarkers(ctrl.text);
    final saved = stripInlineImageMarkers(
      _postedCommentSavedText[comment.id] ?? comment.description,
    );
    if (newBody == saved) return;
    if (newBody.isEmpty) {
      ctrl.text = saved;
      await _showInfo('Comment required', 'Comment cannot be empty.');
      return;
    }
    final state = context.read<AppState>();
    _savingPostedCommentId = comment.id;
    final err = await SupabaseService.updateProjectCommentRow(
      commentId: comment.id,
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
    _postedCommentSavedText[comment.id] = newBody;
    await _loadComments();
  }

  Future<bool> _saveDirtyPostedComments(AppState state) async {
    for (final comment in _comments) {
      if (!_isOwnComment(comment)) continue;
      final ctrl = _postedCommentControllers[comment.id];
      if (ctrl == null) continue;
      final newBody = stripInlineImageMarkers(ctrl.text);
      final saved = stripInlineImageMarkers(
        _postedCommentSavedText[comment.id] ?? comment.description,
      );
      if (newBody == saved) continue;
      if (newBody.isEmpty) {
        ctrl.text = saved;
        await _showInfo('Comment required', 'Comment cannot be empty.');
        return false;
      }
      _savingPostedCommentId = comment.id;
      final err = await SupabaseService.updateProjectCommentRow(
        commentId: comment.id,
        description: newBody,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      _savingPostedCommentId = null;
      if (!mounted) return false;
      if (err != null) {
        ctrl.text = saved;
        await _showInfo('Could not update comment', err);
        return false;
      }
      _postedCommentSavedText[comment.id] = newBody;
    }
    return true;
  }

  Future<String?> _postDraftCommentWithoutOverlay(AppState state) async {
    final text = stripInlineImageMarkers(_commentController.text);
    final hasInlineDraft = _pendingInlineImageAdds.any(
      (draft) =>
          draft.entityType == 'project_comment' && draft.entityId == 'draft',
    );
    if (text.isEmpty && !hasInlineDraft) return null;
    final c = await SupabaseService.insertProjectCommentRow(
      projectId: widget.projectId,
      description: text.isNotEmpty ? text : inlineImageOnlyCommentPlaceholder,
      creatorStaffLookupKey: state.userStaffAppId,
    );
    if (c.error != null) {
      await _showInfo('Could not add comment', c.error!);
      return null;
    }
    final commentId = c.commentId;
    if (commentId == null || commentId.isEmpty) {
      await _showInfo(
        'Could not add comment',
        'The comment was not saved because Supabase did not return a comment id.',
      );
      return null;
    }
    _commentController.clear();
    return commentId;
  }

  Future<void> _deletePostedComment(ProjectCommentRowDisplay comment) async {
    if (!_isOwnComment(comment) || _saving) return;
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Remove comment',
      content: 'Remove this comment?',
      confirmText: 'Remove',
      isDestructive: true,
      palette: widget.palette,
    );
    if (ok != true || !mounted) return;
    final state = context.read<AppState>();
    _setSaving(true);
    try {
      final err = await SupabaseService.softDeleteProjectCommentRow(
        commentId: comment.id,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (err != null && mounted) {
        await _showInfo('Could not remove comment', err);
        return;
      }
      _postedCommentControllers.remove(comment.id)?.dispose();
      _postedCommentSavedText.remove(comment.id);
      await _loadComments();
    } finally {
      if (mounted) _setSaving(false);
    }
  }

  Widget _attachmentFieldLabel({
    required String label,
    required bool showAdd,
    required bool enabled,
    required String tooltip,
    required void Function(BuildContext buttonContext)? onAdd,
    LayerLink? anchorLink,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(label, style: asanaDetailLabelStyle(context))),
        if (showAdd) ...[
          const SizedBox(width: 8),
          AsanaDetailCircleAddButton(
            onTap: onAdd,
            enabled: enabled,
            tooltip: tooltip,
            size: 22,
            anchorLink: anchorLink,
          ),
        ],
      ],
    );
  }

  Widget _attachmentValueList(
    BuildContext context,
    List<_ProjectAttachmentDraft> attachments, {
    required bool allowRemove,
    BuildContext? editAnchorContext,
  }) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final imageAttachments = attachments
        .where(
          (e) => !_draftShowsAsWebsiteLink(e) && _attachmentDraftIsImage(e),
        )
        .toList();
    final otherAttachments = attachments
        .where(
          (e) => _draftShowsAsWebsiteLink(e) || !_attachmentDraftIsImage(e),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (imageAttachments.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              bottom: otherAttachments.isNotEmpty ? 8 : 0,
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: imageAttachments
                  .map(
                    (e) => _attachmentDraftTile(
                      context,
                      e,
                      allowRemove: allowRemove,
                      editAnchorContext: editAnchorContext,
                    ),
                  )
                  .toList(),
            ),
          ),
        ...otherAttachments.map(
          (e) => _attachmentDraftTile(
            context,
            e,
            allowRemove: allowRemove,
            editAnchorContext: editAnchorContext,
          ),
        ),
      ],
    );
  }

  Widget _attachmentTwoColumnRow({
    required String label,
    required List<_ProjectAttachmentDraft> attachments,
    required bool showAdd,
    required bool addEnabled,
    required String addTooltip,
    required void Function(BuildContext buttonContext)? onAdd,
    LayerLink? addAnchorLink,
    bool allowRemove = true,
    BuildContext? editAnchorContext,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: MediaQuery.sizeOf(context).width < 600
                ? kAsanaDetailLabelColumnWidth / 2
                : kAsanaDetailLabelColumnWidth,
            child: _attachmentFieldLabel(
              label: label,
              showAdd: showAdd,
              enabled: addEnabled,
              tooltip: addTooltip,
              onAdd: onAdd,
              anchorLink: addAnchorLink,
            ),
          ),
          Expanded(
            child: _attachmentValueList(
              context,
              attachments,
              allowRemove: allowRemove,
              editAnchorContext: editAnchorContext,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentDraftTile(
    BuildContext context,
    _ProjectAttachmentDraft draft, {
    required bool allowRemove,
    BuildContext? editAnchorContext,
  }) {
    if (draft.isPendingFile) {
      final name = draft.pendingFilename?.trim().isNotEmpty == true
          ? draft.pendingFilename!.trim()
          : 'File';
      return AsanaAttachmentDraftTile(
        isWebsiteLink: false,
        title: name,
        subtitle: 'Uploads when you save',
        enabled: !_saving,
        onRemove: allowRemove ? () => _removeAttachmentDraft(draft) : null,
        imageBytes: draft.pendingBytes,
        mimeType: draft.mimeType,
        showImagePreview: _shouldAttemptAttachmentImagePreview(draft),
      );
    }
    final url = draft.urlController.text.trim();
    if (url.isEmpty) return const SizedBox.shrink();
    final desc = draft.descController.text.trim();
    final isLink = _draftShowsAsWebsiteLink(draft);
    final title = desc.isNotEmpty ? desc : url;
    final canRemove =
        allowRemove &&
        (isLink ||
            FirebaseAttachmentUploadService.storageDownloadUrlBelongsToCurrentUser(
              url,
            ));
    return AsanaAttachmentDraftTile(
      isWebsiteLink: isLink,
      title: title,
      url: url,
      enabled: !_saving,
      onRemove: canRemove ? () => _removeAttachmentDraft(draft) : null,
      onEditLink: isLink && editAnchorContext != null
          ? () => _editAttachmentLink(editAnchorContext, draft)
          : null,
      onDownload: !isLink
          ? () => openAttachmentUrl(context, url, displayFileName: title)
          : null,
      imageBytes: draft.pendingBytes,
      mimeType: draft.mimeType,
      showImagePreview: !isLink && _attachmentDraftIsImage(draft),
    );
  }

  Widget _buildCommentDisplayTile(ProjectCommentRowDisplay comment) {
    if (_isOwnComment(comment) &&
        !_postedCommentControllers.containsKey(comment.id)) {
      final cleaned = stripInlineImageMarkers(comment.description);
      _postedCommentControllers[comment.id] = TextEditingController(
        text: cleaned,
      );
      _postedCommentSavedText[comment.id] = cleaned;
    }
    final deleted = comment.isDeleted;
    final canEdit = _isOwnComment(comment);
    final postedAt = _commentDisplayTimestamp(comment);
    final edited =
        comment.updateTimestampUtc != null &&
        comment.createTimestampUtc != null &&
        comment.updateTimestampUtc!.isAfter(comment.createTimestampUtc!);
    final body = canEdit
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                onFocusChange: (hasFocus) {
                  if (!hasFocus) _savePostedCommentOnBlur(comment);
                },
                child: AsanaHoverTextField(
                  controller: _postedCommentControllers[comment.id]!,
                  canEdit: true,
                  readOnly: _saving || _savingPostedCommentId == comment.id,
                  maxLines: 8,
                  minLines: 2,
                  style: asanaDetailMultilineValueStyle(context),
                ),
              ),
              InlineImageToolbar(
                enabled: !_saving,
                onAdd: () => _stageInlineImage(
                  entityType: 'project_comment',
                  entityId: comment.id,
                ),
              ),
              InlineImagePreviewList(
                images: _inlinePreviewItems(
                  entityType: 'project_comment',
                  entityId: comment.id,
                  saved: _commentInlineImages[comment.id] ?? const [],
                ),
                onRemove: _removeInlineImagePreview,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _deletePostedComment(comment),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Remove'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFC62828),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                stripInlineImageMarkers(comment.description),
                style: asanaDetailMultilineValueStyle(context).copyWith(
                  color: deleted ? kAsanaTextSecondary : kAsanaTextPrimary,
                ),
              ),
              InlineImagePreviewList(
                images: _inlinePreviewItems(
                  entityType: 'project_comment',
                  entityId: comment.id,
                  saved: _commentInlineImages[comment.id] ?? const [],
                ),
              ),
            ],
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(comment.displayStaffName, style: asanaDetailLabelStyle(context)),
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
                      '${edited ? 'Edited' : 'Posted'} ${_formatCommentPostedTs(postedAt)}',
                      style: asanaDetailLabelStyle(
                        context,
                      ).copyWith(fontSize: 11),
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

  Widget? _buildSlideFooter({
    required AsanaSlideChrome chrome,
    required bool canEdit,
    required ProjectRecord p,
    required AppState state,
  }) {
    if (!canEdit) return null;
    final mobileButtons = AsanaTaskDetailActionStyles.isMobile(context);
    final deleted = _effectiveStatus(p) == 'Deleted';
    final buttons = <Widget>[];
    if (!deleted) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _save(state, p),
          style: AsanaTaskDetailActionStyles.updateFilled(
            widget.palette,
            context: context,
          ),
          child: Text(_saving ? 'Saving' : 'Update'),
        ),
      );
    }
    if (_canMarkProjectComplete(p)) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _markCompleted(state, p),
          style: AsanaTaskDetailActionStyles.successFilled(context: context),
          child: Text(mobileButtons ? 'Complete' : 'Mark as Completed'),
        ),
      );
    }
    if (!deleted &&
        _isCreator(p) &&
        !p.isPaused &&
        _effectiveStatus(p) != 'Completed') {
      buttons.add(
        OutlinedButton(
          onPressed: _saving
              ? null
              : () => _setProjectPause(state, p, paused: true),
          style: AsanaTaskDetailActionStyles.pauseOutlined(context: context),
          child: const Text('Pause'),
        ),
      );
    }
    if (!deleted && _isCreator(p) && p.isPaused) {
      buttons.add(
        OutlinedButton(
          onPressed: _saving
              ? null
              : () => _setProjectPause(state, p, paused: false),
          style: AsanaTaskDetailActionStyles.resumeOutlined(context: context),
          child: const Text('Resume'),
        ),
      );
    }
    if (_canRestoreProject(p)) {
      buttons.add(
        OutlinedButton(
          onPressed: _saving ? null : () => _restoreDeletedProject(state, p),
          style: AsanaTaskDetailActionStyles.undoOutlined(
            widget.palette,
            context: context,
          ),
          child: Text(mobileButtons ? 'Restore' : 'Restore to Not started'),
        ),
      );
    }
    if (_canDeleteProject(p)) {
      buttons.add(
        FilledButton(
          onPressed: _saving ? null : () => _confirmDeleteProject(state),
          style: AsanaTaskDetailActionStyles.deleteFilled(context: context),
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
    if (_assigneeIds.length > 20) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Too many assignees',
        content: 'Select no more than 20 assignees.',
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
    if (_picAssigneeIds.length > 20) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Too many PICs',
        content: 'Select no more than 20 PICs.',
        palette: widget.palette,
      );
      return;
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
    final status = _effectiveStatus(p);

    _setSaving(true);
    try {
      final slots = await SupabaseService.assigneeSlotsForProject(
        _assigneeIds.toList(),
      );
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
      final changesForEmail = _projectChangesForEmail(state, p);
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
        status: status,
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
      if (!await _saveDirtyPostedComments(state)) return;
      final hasDraftComment =
          stripInlineImageMarkers(_commentController.text).isNotEmpty ||
          _pendingInlineImageAdds.any(
            (draft) =>
                draft.entityType == 'project_comment' &&
                draft.entityId == 'draft',
          );
      final draftCommentId = await _postDraftCommentWithoutOverlay(state);
      if (hasDraftComment && draftCommentId == null) return;
      final inlineErr = await _commitPendingInlineImages(
        project: p,
        state: state,
        entityIdOverrides: draftCommentId == null
            ? const {}
            : {'draft': draftCommentId},
      );
      if (inlineErr != null && mounted) {
        await _showInfo('Could not save inline image', inlineErr);
        return;
      }
      final attachmentErr = await _replaceProjectAttachments();
      if (attachmentErr != null && mounted) {
        await _showInfo('Could not save attachments', attachmentErr);
        return;
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (mounted) state.applyProjects(projects);
      await _loadProject();
      await _loadComments();
      await _loadAttachments();
      await _loadProjectDescriptionInlineImages();
      _projectAi?.clearAllSuggestions();
      widget.onChanged?.call();
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
      await _notifyEmail(
        'Project update email',
        (token) => BackendApi().notifyProjectUpdated(
          idToken: token,
          projectId: widget.projectId,
          changes: changesForEmail,
        ),
      );
    } finally {
      AsanaBlockingLoadingOverlay.hide();
      if (mounted) _setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = AsanaSlideChrome(widget.palette);
    if (_loading) {
      return const StartupLoadingView(label: 'Loading');
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _descController,
                  canEdit: canEdit,
                  readOnly: _saving,
                  maxLines: 8,
                  minLines: 2,
                  style: asanaDetailMultilineValueStyle(context),
                  hintText: 'Please fill in project description',
                ),
                if (canEdit)
                  InlineImageToolbar(
                    enabled: !_saving,
                    onAdd: () => _stageInlineImage(
                      entityType: 'project_description',
                      entityId: widget.projectId,
                    ),
                  ),
                InlineImagePreviewList(
                  images: _inlinePreviewItems(
                    entityType: 'project_description',
                    entityId: widget.projectId,
                    saved: _descriptionInlineImages,
                  ),
                  onRemove: canEdit ? _removeInlineImagePreview : null,
                ),
              ],
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
          AsanaDetailSectionHeader(
            title: 'Tasks',
            showAddButton: true,
            addTooltip: 'Create task',
            onAdd: widget.onPushCreateTask == null
                ? null
                : (_) => widget.onPushCreateTask!(),
            addEnabled: !_saving && widget.onPushCreateTask != null,
          ),
          if (_tasks.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                return _ProjectDetailTaskList(
                  tasks: _tasks,
                  viewportWidth: constraints.maxWidth,
                  tableColors: widget.palette.tableColors,
                  formatDue: _formatShortDate,
                  statusLabel: _taskStatusLabel,
                  isCompleted: _taskCompleted,
                  isDeleted: _taskDeleted,
                  onOpenTask: widget.onPushTask,
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'No tasks yet',
                style: asanaDetailValueStyle(
                  context,
                ).copyWith(color: kAsanaTextSecondary),
              ),
            ),
          AsanaDetailTwoColumnRow(
            label: 'Status',
            child: canEdit
                ? Builder(
                    builder: (anchorContext) => CompositedTransformTarget(
                      link: _statusAnchorLink,
                      child: MouseRegion(
                        cursor: _saving || p.isPaused
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _saving || p.isPaused
                              ? null
                              : () => _pickStatus(anchorContext),
                          child: AsanaDetailStatusPill(
                            status: _displayStatus(p),
                          ),
                        ),
                      ),
                    ),
                  )
                : AsanaDetailStatusPill(status: _displayStatus(p)),
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
          Builder(
            builder: (anchorContext) => _attachmentTwoColumnRow(
              label: 'Files',
              attachments: _fileAttachments,
              showAdd: canEdit,
              addEnabled: canEdit && !_saving,
              addTooltip: 'Add file',
              onAdd: canEdit ? (_) => _addFileAttachment(p) : null,
              allowRemove: canEdit,
            ),
          ),
          Builder(
            builder: (anchorContext) => _attachmentTwoColumnRow(
              label: 'Links',
              attachments: _urlAttachments,
              showAdd: canEdit,
              addEnabled: canEdit && !_saving,
              addTooltip: 'Add website link',
              onAdd: canEdit ? _addUrlAttachment : null,
              addAnchorLink: _attachmentAddAnchorLink,
              allowRemove: canEdit,
              editAnchorContext: anchorContext,
            ),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.websiteLink),
          if ((p.updateByDisplayName ?? '').trim().isNotEmpty)
            AsanaDetailTwoColumnRow(
              label: 'Last updated by',
              child: AsanaDetailPlainValue(text: p.updateByDisplayName!.trim()),
            ),
          if (p.updateDate != null)
            AsanaDetailTwoColumnRow(
              label: 'Last updated',
              child: AsanaDetailPlainValue(text: _formatDate(p.updateDate)),
            ),
          AsanaDetailLabelValue(
            label: 'Comments',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final comment in _comments)
                  _buildCommentDisplayTile(comment),
                if (canEdit) ...[
                  AsanaHoverTextField(
                    controller: _commentController,
                    canEdit: true,
                    readOnly: _saving,
                    maxLines: 5,
                    minLines: 2,
                    style: asanaDetailMultilineValueStyle(context),
                  ),
                  InlineImageToolbar(
                    enabled: !_saving,
                    onAdd: () => _stageInlineImage(
                      entityType: 'project_comment',
                      entityId: 'draft',
                    ),
                  ),
                  InlineImagePreviewList(
                    images: _inlinePreviewItems(
                      entityType: 'project_comment',
                      entityId: 'draft',
                      saved: const [],
                    ),
                    onRemove: _removeInlineImagePreview,
                  ),
                ],
              ],
            ),
          ),
          if (canEdit) _aiSuggestions(AsanaTaskAiFieldKey.comment),
        ],
      ),
    );
  }
}

class _ProjectDetailTaskList extends StatelessWidget {
  const _ProjectDetailTaskList({
    required this.tasks,
    required this.viewportWidth,
    required this.tableColors,
    required this.formatDue,
    required this.statusLabel,
    required this.isCompleted,
    required this.isDeleted,
    this.onOpenTask,
  });

  final List<Task> tasks;
  final double viewportWidth;
  final AsanaTableColors tableColors;
  final String Function(DateTime? date) formatDue;
  final String Function(Task task) statusLabel;
  final bool Function(Task task) isCompleted;
  final bool Function(Task task) isDeleted;
  final void Function(String taskId)? onOpenTask;

  @override
  Widget build(BuildContext context) {
    final compactMobile = viewportWidth < 600;
    final tableWidth = compactMobile
        ? viewportWidth
        : viewportWidth.clamp(360.0, double.infinity);
    final dueCol = compactMobile ? 56.0 : 69.0;
    final statusCol = compactMobile ? 48.0 : 108.0;
    final submissionCol = compactMobile ? 48.0 : 90.72;
    final textGap = compactMobile ? 8.0 : kAsanaTextColumnGap;
    final minNameCol = compactMobile ? 48.0 : 120.0;
    final nameCol =
        (tableWidth - 24 - textGap - dueCol - statusCol - submissionCol).clamp(
          minNameCol,
          double.infinity,
        );
    final header = asanaTableHeaderStyle(context);

    Widget table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              SizedBox(
                width: nameCol,
                child: Text('Task Name', style: header),
              ),
              SizedBox(width: textGap),
              asanaTableHeaderLabel(
                width: dueCol,
                label: compactMobile ? 'Due' : 'Due Date',
                style: header,
                rowHeight: 24,
              ),
              asanaTableHeaderLabel(
                width: statusCol,
                label: compactMobile ? 'Sta' : 'Status',
                style: header,
                rowHeight: 24,
              ),
              asanaTableHeaderLabel(
                width: submissionCol,
                label: compactMobile ? 'Sub' : 'Submission',
                style: header,
                rowHeight: 24,
              ),
            ],
          ),
        ),
        ...tasks.map((task) {
          final completed = isCompleted(task);
          final status = statusLabel(task);
          final rowStyle = asanaTableRowValueStyle(
            context,
            completed: completed,
          );
          final nameStyle = asanaTableRowNameStyle(
            context,
            completed: completed,
            isSubtask: true,
          );
          final name = task.name.trim().isEmpty
              ? '(Unnamed task)'
              : task.name.trim();
          return Material(
            color: tableColors.subtaskRow,
            child: InkWell(
              onTap: onOpenTask == null ? null : () => onOpenTask!(task.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: nameCol,
                      child: Text(
                        name,
                        style: nameStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: textGap),
                    SizedBox(
                      width: dueCol,
                      child: Text(
                        formatDue(task.endDate),
                        style: rowStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: statusCol,
                      child: AsanaTableCellChip(
                        child: AsanaStatusChip(
                          status: status,
                          displayLabel: compactMobile
                              ? _mobileStatusLabel(status)
                              : null,
                          fontSize: compactMobile
                              ? 12
                              : kAsanaTableChipFontSize,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: submissionCol,
                      child: AsanaTableCellChip(
                        child: AsanaSubmissionChip(
                          submission: task.submission,
                          displayLabel: compactMobile
                              ? _mobileSubmissionLabel(task.submission)
                              : null,
                          fontSize: compactMobile
                              ? 12
                              : kAsanaTableChipFontSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );

    if (viewportWidth < tableWidth) {
      table = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(width: tableWidth, child: table),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: table),
    );
  }

  static String _mobileStatusLabel(String raw) {
    final s = raw.trim().toLowerCase();
    if (s == 'completed' || s == 'complete') return 'COM';
    if (s == 'deleted' || s == 'delete') return 'DEL';
    if (s == 'not started') return 'NST';
    if (s == 'in progress') return 'INP';
    if (s.isEmpty || s == 'incomplete') return 'INC';
    final trimmed = raw.trim();
    return trimmed.length <= 3
        ? trimmed.toUpperCase()
        : trimmed.substring(0, 3).toUpperCase();
  }

  static String? _mobileSubmissionLabel(String? raw) {
    final s = raw?.trim().toLowerCase() ?? '';
    if (s.isEmpty || s == 'pending') return 'PEN';
    if (s == 'submitted') return 'SUB';
    if (s == 'accepted') return 'ACC';
    if (s == 'returned') return 'RET';
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= 3
        ? trimmed.toUpperCase()
        : trimmed.substring(0, 3).toUpperCase();
  }
}
