import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/project_record.dart';
import '../../models/singular_subtask.dart';
import '../../models/staff_for_assignment.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/backend_api.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../../utils/attachment_url_launch.dart';
import '../../utils/attachment_file_pick.dart';
import '../asana_landing_screen.dart';
import 'asana_attachment_draft_tile.dart';
import 'asana_attachment_menu.dart';
import 'asana_assignee_field.dart';
import 'asana_assignee_picker.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_filter_widgets.dart';
import 'asana_inline_image_widgets.dart';
import 'asana_task_ai_assistant.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

class _SubtaskAttachmentDraft {
  _SubtaskAttachmentDraft({
    this.id,
    String? url,
    String? desc,
    this.pendingBytes,
    this.pendingFilename,
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

class _SubtaskInlineImageDraft {
  _SubtaskInlineImageDraft({
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

class _SubtaskCommentDisplayTile extends StatelessWidget {
  const _SubtaskCommentDisplayTile({
    required this.comment,
    required this.inlineImages,
    required this.canAddInlineImage,
    required this.inlineImageEnabled,
    required this.onAddInlineImage,
    required this.onRemoveInlineImage,
  });

  final SubtaskCommentRowDisplay comment;
  final List<InlineImagePreviewItem> inlineImages;
  final bool canAddInlineImage;
  final bool inlineImageEnabled;
  final VoidCallback onAddInlineImage;
  final void Function(InlineImagePreviewItem image) onRemoveInlineImage;

  DateTime? get _displayTimestamp {
    final created = comment.createTimestampUtc;
    final updated = comment.updateTimestampUtc;
    if (updated != null && created != null && updated.isAfter(created)) {
      return updated;
    }
    return created ?? updated;
  }

  @override
  Widget build(BuildContext context) {
    final deleted = comment.isDeleted;
    final timestamp = _displayTimestamp;
    final edited =
        comment.updateTimestampUtc != null &&
        comment.createTimestampUtc != null &&
        comment.updateTimestampUtc!.isAfter(comment.createTimestampUtc!);
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
                Text(
                  stripInlineImageMarkers(comment.description),
                  style: asanaDetailMultilineValueStyle(context).copyWith(
                    color: deleted ? kAsanaTextSecondary : kAsanaTextPrimary,
                  ),
                ),
                if (canAddInlineImage)
                  InlineImageToolbar(
                    enabled: inlineImageEnabled,
                    onAdd: onAddInlineImage,
                  ),
                InlineImagePreviewList(
                  images: inlineImages,
                  onRemove: onRemoveInlineImage,
                ),
                if (timestamp != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      edited
                          ? 'Edited ${HkTime.formatInstantAsHk(timestamp, 'yyyy-MM-dd HH:mm')}'
                          : HkTime.formatInstantAsHk(
                              timestamp,
                              'yyyy-MM-dd HH:mm',
                            ),
                      style: asanaDetailLabelStyle(
                        context,
                      ).copyWith(fontWeight: FontWeight.normal, fontSize: 11),
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
  State<AsanaSubtaskDetailPanel> createState() =>
      _AsanaSubtaskDetailPanelState();
}

class _AsanaSubtaskDetailPanelState extends State<AsanaSubtaskDetailPanel> {
  SingularSubtask? _subtask;
  Task? _parentTask;
  ProjectRecord? _parentProject;
  bool _loading = true;
  bool _saving = false;
  bool _createdInPlace = false;

  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _reasonController = TextEditingController();
  final _commentController = TextEditingController();
  final List<_SubtaskAttachmentDraft> _attachments = [];
  List<SubtaskCommentRowDisplay> _comments = [];
  final Map<String, TextEditingController> _postedCommentControllers = {};
  final Map<String, String> _postedCommentSavedText = {};
  String? _savingPostedCommentId;
  List<InlineAttachmentRow> _descriptionInlineImages = [];
  Map<String, List<InlineAttachmentRow>> _commentInlineImages = {};
  final List<_SubtaskInlineImageDraft> _pendingInlineImageAdds = [];
  final List<InlineAttachmentRow> _pendingInlineImageDeletes = [];

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
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot = ValueNotifier(
    const AsanaAssigneePickerSnapshot(loading: true),
  );

  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _priorityAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  final LayerLink _attachmentAddAnchorLink = LayerLink();
  final GlobalKey _detailPopupWidthAlignKey = GlobalKey();
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
          _loadParentContext(widget.parentTaskId);
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
    if (oldWidget.subtaskId != widget.subtaskId ||
        oldWidget.createMode != widget.createMode) {
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
    _comments = [];
    _descriptionInlineImages = [];
    _commentInlineImages = {};
    _clearInlineImageDrafts();
    _assigneeIds.clear();
    _picAssigneeId = null;
    _localPriority = priorityStandard;
    _draftStatus = 'Incomplete';
    final today = HkTime.todayDateOnlyHk();
    _anchorCreateDate = HkTime.firstBusinessDayOnOrAfter(
      today,
      _holidaySkipYmd,
    );
    _startDate = _anchorCreateDate;
    _dueDate = _defaultDueForPriority(_localPriority);
    _subtask = null;
    _loading = false;
  }

  DateTime _defaultDueForPriority(int priority) {
    final days = priority == priorityUrgent ? 1 : 3;
    return HkTime.addBusinessDaysAfter(
      _anchorCreateDate,
      days,
      _holidaySkipYmd,
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

  void _notifyParentTaskOfSubtaskChange() {
    final taskId = (_subtask?.taskId ?? widget.parentTaskId ?? '').trim();
    if (taskId.isNotEmpty) {
      SupabaseService.invalidateSubtasksCacheForTask(taskId);
    }
    widget.onChanged?.call();
  }

  @override
  void dispose() {
    AsanaBlockingLoadingOverlay.hideAll();
    _nameController.dispose();
    _descController.dispose();
    _reasonController.dispose();
    _commentController.dispose();
    _disposePostedCommentControllers();
    _clearAttachments();
    _subtaskAi?.dispose();
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
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
            _descController.text = stripInlineImageMarkers(
              row?.description ?? '',
            );
            _reasonController.text = row?.changeDueReason ?? '';
            _assigneeIds.clear();
            if (row != null)
              _assigneeIds.addAll(row.assigneeIds.where((e) => e.isNotEmpty));
            _picAssigneeId = row?.pic;
            if (_picAssigneeId?.isEmpty == true) _picAssigneeId = null;
            _localPriority = row?.priority ?? priorityStandard;
            _startDate = row?.startDate;
            _dueDate = row?.dueDate;
            _draftStatus = row?.status;
          });
          await _loadParentContext(row?.taskId);
          _loadAssigneeStaff();
          _loadAttachments(row);
          _loadComments(row);
          _loadSubtaskDescriptionInlineImages(row);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _loadAttachments(SingularSubtask? row) async {
    if (row == null || !SupabaseConfig.isConfigured) return;
    try {
      final files = await SupabaseService.fetchFileAttachments(
        entityType: 'subtask',
        entityId: row.id,
      );
      final urls = await SupabaseService.fetchUrlAttachments(
        entityType: 'subtask',
        entityId: row.id,
      );
      if (!mounted) return;
      setState(() {
        _clearAttachments();
        for (final r in files) {
          _attachments.add(
            _SubtaskAttachmentDraft(
              id: r.id,
              url: r.url,
              desc: (r.description?.trim().isNotEmpty == true)
                  ? r.description
                  : r.filename,
              mimeType: r.mimeType,
              isWebsiteLink: false,
            ),
          );
        }
        for (final r in urls) {
          _attachments.add(
            _SubtaskAttachmentDraft(
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

  Future<void> _loadComments(SingularSubtask? row) async {
    if (row == null || !SupabaseConfig.isConfigured) return;
    try {
      final list = await SupabaseService.fetchSubtaskComments(row.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _syncPostedCommentControllers();
      });
      await _loadCommentInlineImages(list);
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
        final cleaned = stripInlineImageMarkers(c.description);
        _postedCommentControllers[c.id] = TextEditingController(text: cleaned);
        _postedCommentSavedText[c.id] = cleaned;
      } else {
        final ctrl = _postedCommentControllers[c.id]!;
        final saved = _postedCommentSavedText[c.id] ?? '';
        final cleaned = stripInlineImageMarkers(c.description);
        if (ctrl.text == saved && ctrl.text != cleaned) {
          ctrl.text = cleaned;
          _postedCommentSavedText[c.id] = cleaned;
        }
      }
    }
  }

  Future<void> _loadSubtaskDescriptionInlineImages(SingularSubtask? row) async {
    if (row == null || !SupabaseConfig.isConfigured) {
      if (mounted) setState(() => _descriptionInlineImages = []);
      return;
    }
    final list = await SupabaseService.fetchInlineAttachments(
      entityType: 'subtask_description',
      entityId: row.id,
    );
    if (mounted) setState(() => _descriptionInlineImages = list);
  }

  Future<void> _loadCommentInlineImages(
    List<SubtaskCommentRowDisplay> comments,
  ) async {
    if (!SupabaseConfig.isConfigured || comments.isEmpty) {
      if (mounted) setState(() => _commentInlineImages = {});
      return;
    }
    final next = <String, List<InlineAttachmentRow>>{};
    for (final c in comments) {
      final list = await SupabaseService.fetchInlineAttachments(
        entityType: 'subtask_comment',
        entityId: c.id,
      );
      if (list.isNotEmpty) next[c.id] = list;
    }
    if (mounted) setState(() => _commentInlineImages = next);
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

  Widget _buildCommentDisplayTile(
    AppState state,
    SubtaskCommentRowDisplay comment,
    SingularSubtask? subtask,
  ) {
    final inlineImages = _inlinePreviewItems(
      entityType: 'subtask_comment',
      entityId: comment.id,
      saved: _commentInlineImages[comment.id] ?? const [],
    );
    final ownComment = _isOwnComment(state, comment);
    if (ownComment && !_postedCommentControllers.containsKey(comment.id)) {
      final cleaned = stripInlineImageMarkers(comment.description);
      _postedCommentControllers[comment.id] = TextEditingController(
        text: cleaned,
      );
      _postedCommentSavedText[comment.id] = cleaned;
    }
    if (ownComment) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              onFocusChange: (hasFocus) {
                if (!hasFocus) {
                  _savePostedCommentOnBlur(state, comment);
                }
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
              enabled: !_saving && subtask != null,
              onAdd: subtask == null
                  ? () {}
                  : () => _addExistingCommentInlineImage(subtask, comment),
            ),
            InlineImagePreviewList(
              images: inlineImages,
              onRemove: _removeInlineImagePreview,
            ),
          ],
        ),
      );
    }
    return _SubtaskCommentDisplayTile(
      comment: comment,
      inlineImages: inlineImages,
      canAddInlineImage: false,
      inlineImageEnabled: !_saving,
      onAddInlineImage: () {},
      onRemoveInlineImage: _removeInlineImagePreview,
    );
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

  void _notifyEmailInBackground(
    String label,
    Future<String?> Function(String idToken) send,
  ) {
    unawaited(_notifyEmail(label, send));
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
    _addChange(
      changes,
      'subtaskName',
      s.subtaskName,
      _nameController.text.trim(),
    );
    _addChange(
      changes,
      'description',
      s.description,
      stripInlineImageMarkers(_descController.text),
    );
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
    return _matchesCurrentStaff(state, s.createByStaffId);
  }

  bool _isPic(AppState state, SingularSubtask s) {
    return _matchesCurrentStaff(state, s.pic);
  }

  bool _isAssignee(AppState state, SingularSubtask s) {
    return s.assigneeIds.any((id) => _matchesCurrentStaff(state, id));
  }

  bool _matchesCurrentStaff(AppState state, String? staffKey) {
    final key = staffKey?.trim();
    if (key == null || key.isEmpty) return false;
    final myAppId = state.userStaffAppId?.trim();
    if (myAppId != null && myAppId.isNotEmpty && myAppId == key) return true;
    final myUuid = state.userStaffId?.trim();
    return myUuid != null && myUuid.isNotEmpty && myUuid == key;
  }

  bool _isOwnComment(AppState state, SubtaskCommentRowDisplay comment) {
    return !comment.isDeleted &&
        _matchesCurrentStaff(state, comment.createByStaffId);
  }

  Future<void> _savePostedCommentOnBlur(
    AppState state,
    SubtaskCommentRowDisplay comment,
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
      await showAsanaInfoDialog(
        context: context,
        title: 'Comment required',
        content: 'Comment cannot be empty.',
        palette: widget.palette,
      );
      return;
    }

    _savingPostedCommentId = comment.id;
    final err = await SupabaseService.updateSubtaskCommentRow(
      commentId: comment.id,
      description: newBody,
      updaterStaffLookupKey: state.userStaffAppId,
    );
    _savingPostedCommentId = null;
    if (!mounted) return;
    if (err != null) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Could not update comment',
        content: err,
        palette: widget.palette,
      );
      return;
    }
    _postedCommentSavedText[comment.id] = newBody;
    await _loadComments(_subtask);
  }

  Future<bool> _saveDirtyPostedComments(AppState state) async {
    for (final comment in _comments) {
      if (!_isOwnComment(state, comment)) continue;
      final ctrl = _postedCommentControllers[comment.id];
      if (ctrl == null) continue;

      final newBody = stripInlineImageMarkers(ctrl.text);
      final saved = stripInlineImageMarkers(
        _postedCommentSavedText[comment.id] ?? comment.description,
      );
      if (newBody == saved) continue;

      if (newBody.isEmpty) {
        ctrl.text = saved;
        await showAsanaInfoDialog(
          context: context,
          title: 'Comment required',
          content: 'Comment cannot be empty.',
          palette: widget.palette,
        );
        return false;
      }

      _savingPostedCommentId = comment.id;
      final err = await SupabaseService.updateSubtaskCommentRow(
        commentId: comment.id,
        description: newBody,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      _savingPostedCommentId = null;
      if (!mounted) return false;
      if (err != null) {
        ctrl.text = saved;
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not update comment',
          content: err,
          palette: widget.palette,
        );
        return false;
      }
      _postedCommentSavedText[comment.id] = newBody;
    }
    return true;
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
      projectStaff: _projectAssigneeStaff(),
      hasProjectTeam: _parentProject != null,
      error: _assigneePickerError,
    );
    _picSnapshot.value = AsanaAssigneePickerSnapshot(
      loading: _assigneePickerLoading,
      teams: _pickerTeamsForRole(),
      staff: _pickerStaff
          .where((s) => _assigneeIds.contains(s.assigneeId))
          .toList(),
      error: _assigneePickerError,
    );
  }

  Future<void> _loadParentContext(String? taskId) async {
    final id = taskId?.trim();
    if (id == null || id.isEmpty || !SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _parentTask = null;
          _parentProject = null;
        });
        _publishAssigneeSnapshot();
      }
      return;
    }
    Task? parent = context.read<AppState>().taskById(id);
    parent ??= await SupabaseService.fetchSingularTaskModelById(id);
    final projectId = parent?.projectId?.trim();
    if (projectId == null ||
        projectId.isEmpty ||
        !SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _parentTask = parent;
          _parentProject = null;
        });
        _publishAssigneeSnapshot();
      }
      return;
    }
    try {
      final project = await SupabaseService.fetchProjectById(projectId);
      if (mounted) {
        setState(() {
          _parentTask = parent;
          _parentProject = project;
        });
        _publishAssigneeSnapshot();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _parentTask = parent;
          _parentProject = null;
        });
        _publishAssigneeSnapshot();
      }
    }
  }

  List<StaffForAssignment> _projectAssigneeStaff() {
    final project = _parentProject;
    if (project == null || project.assigneeStaffUuids.isEmpty) {
      return const [];
    }
    final allowed = project.assigneeStaffUuids.map((u) => u.trim()).toSet();
    return _pickerStaff
        .where(
          (s) =>
              allowed.contains(s.staffUuid?.trim()) ||
              allowed.contains(s.assigneeId.trim()),
        )
        .toList();
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
    } else if (_picAssigneeId != null &&
        !_assigneeIds.contains(_picAssigneeId)) {
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

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch >
      _anchoredPickerReopenBlockedUntilMs;

  void _blockAnchoredPickerReopen() {
    _anchoredPickerReopenBlockedUntilMs =
        DateTime.now().millisecondsSinceEpoch + 400;
  }

  List<({String id, String name})> _assigneeRowsForDisplay(AppState state) {
    final rows =
        _assigneeIds
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

  Future<void> _pickPic(BuildContext anchorContext, AppState state) async {
    if (!_canOpenAnchoredPicker) return;
    final ids = _picMenuAssigneeIds(state);
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

  List<String> _picMenuAssigneeIds(AppState state) {
    final projectPicKeys =
        _parentProject?.picStaffUuids
            .map((u) => u.trim())
            .where((u) => u.isNotEmpty)
            .toSet() ??
        const <String>{};
    final ids = _assigneeIds.toList();
    ids.sort((a, b) {
      final aProjectPic = _staffKeyMatchesProjectKeys(a, projectPicKeys);
      final bProjectPic = _staffKeyMatchesProjectKeys(b, projectPicKeys);
      if (aProjectPic != bProjectPic) return aProjectPic ? -1 : 1;
      return _labelForAssigneeId(
        a,
        state,
      ).compareTo(_labelForAssigneeId(b, state));
    });
    return ids;
  }

  bool _staffKeyMatchesProjectKeys(String staffKey, Set<String> projectKeys) {
    final key = staffKey.trim();
    if (key.isEmpty || projectKeys.isEmpty) return false;
    if (projectKeys.contains(key)) return true;
    for (final staff in _pickerStaff) {
      if (staff.assigneeId.trim() == key) {
        final uuid = staff.staffUuid?.trim();
        return uuid != null && projectKeys.contains(uuid);
      }
    }
    return false;
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
            (p) =>
                AsanaAnchoredOption(value: p, label: priorityToDisplayName(p)),
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
        .where(_draftShowsAsWebsiteLink)
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
        description: stripInlineImageMarkers(_descController.text),
        currentComment: _commentController.text.trim(),
        assigneesLabel: _assigneeRowsForDisplay(
          state,
        ).map((a) => a.name).where((n) => n.isNotEmpty).join(', '),
        picLabel: _picAssigneeId == null
            ? ''
            : _labelForAssigneeId(_picAssigneeId!, state),
        priority: _localPriority,
        startDate: _startDate,
        dueDate: _dueDate,
        canEditName: _effectiveCreateMode || _isCreator(state),
        canEditReason: _effectiveCreateMode || _isCreator(state),
        reason: _reasonController.text.trim(),
        parentTaskContext: _buildParentContext(p, state),
        staff: _pickerStaff
            .map((s) => (id: s.assigneeId, name: s.name.trim()))
            .where((s) => s.name.isNotEmpty)
            .toList(),
        canSuggestAssignees: _effectiveCreateMode || _isCreator(state),
        selectedAssigneeIds: Set<String>.from(_assigneeIds),
        picAssigneeId: _picAssigneeId,
        websiteAttachments: _websiteAttachmentsForAi(),
      ),
      onApplySubtaskName: (v) => setState(() => _nameController.text = v),
      onApplySubtaskDescription: (v) =>
          setState(() => _descController.text = v),
      onApplySubtaskAssignees: (ids) => setState(() {
        _assigneeIds
          ..clear()
          ..addAll(ids);
        _syncPicAfterAssigneesChange();
      }),
      onApplySubtaskPic: (id) => setState(() => _picAssigneeId = id),
      onApplySubtaskPriority: (p) => setState(() => _localPriority = p),
      onApplySubtaskStartDate: (d) =>
          setState(() => _startDate = DateTime(d.year, d.month, d.day)),
      onApplySubtaskDueDate: (d) =>
          setState(() => _dueDate = DateTime(d.year, d.month, d.day)),
      onApplyReason: (v) => setState(() => _reasonController.text = v),
      onApplyComment: (v) => setState(() => _commentController.text = v),
      onApplyWebsiteLink: _applyWebsiteLinkFromAi,
    );
  }

  void _applyWebsiteLinkFromAi(String url, String desc) {
    setState(() {
      _attachments.add(
        _SubtaskAttachmentDraft(url: url, desc: desc, isWebsiteLink: true),
      );
    });
  }

  bool _draftShowsAsWebsiteLink(_SubtaskAttachmentDraft draft) {
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

  bool _attachmentDraftIsImage(_SubtaskAttachmentDraft draft) {
    final mime = draft.mimeType?.toLowerCase().trim() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = draft.pendingFilename?.trim().isNotEmpty == true
        ? draft.pendingFilename!.trim()
        : draft.descController.text.trim();
    if (_attachmentMimeTypeFromName(name) != null) return true;
    final rawUrl = draft.urlController.text.trim();
    final uri = Uri.tryParse(rawUrl);
    final urlPath = uri?.path;
    if (_attachmentMimeTypeFromName(urlPath) != null) return true;
    final objectPath = _firebaseStorageObjectPathFromUrl(rawUrl);
    return _attachmentMimeTypeFromName(objectPath) != null;
  }

  bool _shouldAttemptAttachmentImagePreview(_SubtaskAttachmentDraft draft) {
    if (_attachmentDraftIsImage(draft)) return true;
    return !draft.isPendingFile &&
        isAppFirebaseStorageAttachmentUrl(draft.urlController.text.trim());
  }

  String? _firebaseStorageObjectPathFromUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.host.toLowerCase() == 'storage.googleapis.com') {
      final segments = uri.pathSegments;
      if (segments.length < 2) return null;
      return segments.skip(1).join('/');
    }
    final i = uri.path.indexOf('/o/');
    if (i < 0) return null;
    final encoded = uri.path.substring(i + 3);
    if (encoded.isEmpty) return null;
    try {
      return Uri.decodeComponent(encoded);
    } catch (_) {
      return null;
    }
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

  Future<String?> _replaceSubtaskFileAndUrlAttachments(String subtaskId) async {
    final fileErr = await SupabaseService.replaceFileAttachments(
      entityType: 'subtask',
      entityId: subtaskId,
      rows: _fileAttachmentPayload(),
    );
    if (fileErr != null) return fileErr;
    return SupabaseService.replaceUrlAttachments(
      entityType: 'subtask',
      entityId: subtaskId,
      rows: _urlAttachmentPayload(),
    );
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
    await AsanaBlockingLoadingOverlay.showAfterFrame(context);
    try {
      if (_effectiveCreateMode) {
        final commentText = stripInlineImageMarkers(_commentController.text);
        final ins = await SupabaseService.insertSubtaskRow(
          taskId: widget.parentTaskId!,
          subtaskName: newName,
          description: stripInlineImageMarkers(_descController.text),
          priorityDisplay: priorityToDisplayName(_localPriority),
          startDate: _startDate,
          dueDate: _dueDate,
          assigneeStaffUuids: _assigneeIds.toList(),
          picStaffUuid: _picAssigneeId ?? '',
          creatorStaffLookupKey: state.userStaffAppId,
          initialComment: _hasPendingInlineImages('subtask_comment', 'draft')
              ? null
              : (commentText.isNotEmpty ? commentText : null),
          changeDueReason: _needsChangeDueReason()
              ? _reasonController.text.trim()
              : null,
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
          final uploadErr = await _uploadPendingCreateAttachments(
            newSubtaskId,
            state,
          );
          if (uploadErr != null && mounted) {
            await showAsanaInfoDialog(
              context: context,
              title: 'Attachment upload failed',
              content: uploadErr,
              palette: widget.palette,
            );
            return;
          }
          final created = await SupabaseService.fetchSubtaskById(newSubtaskId);
          String? draftCommentId;
          if (commentText.isNotEmpty ||
              _hasPendingInlineImages('subtask_comment', 'draft')) {
            final comment = await SupabaseService.insertSubtaskCommentRow(
              subtaskId: newSubtaskId,
              description: commentText.isNotEmpty
                  ? commentText
                  : inlineImageOnlyCommentPlaceholder,
              creatorStaffLookupKey: state.userStaffAppId,
            );
            if (comment.error != null && mounted) {
              await showAsanaInfoDialog(
                context: context,
                title: 'Could not add comment',
                content: comment.error!,
                palette: widget.palette,
              );
              return;
            }
            draftCommentId = comment.commentId;
          }
          if (created != null) {
            final inlineErr = await _commitPendingInlineImages(
              subtask: created,
              state: state,
              entityIdOverrides: {
                'draft_description': newSubtaskId,
                newSubtaskId: newSubtaskId,
                if (draftCommentId != null) 'draft': draftCommentId,
              },
            );
            if (inlineErr != null && mounted) {
              await showAsanaInfoDialog(
                context: context,
                title: 'Could not save inline image',
                content: inlineErr,
                palette: widget.palette,
              );
              return;
            }
          }
        }
        if (newSubtaskId != null &&
            newSubtaskId.isNotEmpty &&
            _attachments.isNotEmpty) {
          final attErr = await _replaceSubtaskFileAndUrlAttachments(
            newSubtaskId,
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
                _descController.text = stripInlineImageMarkers(row.description);
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
          description: stripInlineImageMarkers(_descController.text),
          priorityDisplay: priorityToDisplayName(_localPriority),
          status: _draftStatus,
          clearStartDate: _startDate == null,
          startDate: _startDate,
          clearDueDate: _dueDate == null,
          dueDate: _dueDate,
          assigneeSlots: _assigneeIds.toList(),
          picStaffLookupKey: _picAssigneeId ?? '',
          updateChangeDueReason: true,
          changeDueReason: _needsChangeDueReason()
              ? _reasonController.text.trim()
              : null,
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

      final commentText = stripInlineImageMarkers(_commentController.text);
      String? commentId;
      if (!await _saveDirtyPostedComments(state)) return;
      if (commentText.isNotEmpty ||
          _hasPendingInlineImages('subtask_comment', 'draft')) {
        final ins = await SupabaseService.insertSubtaskCommentRow(
          subtaskId: s!.id,
          description: commentText.isNotEmpty
              ? commentText
              : inlineImageOnlyCommentPlaceholder,
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
          if (commentId == null || commentId.isEmpty) {
            await showAsanaInfoDialog(
              context: context,
              title: 'Could not add comment',
              content:
                  'The comment was not saved because Supabase did not return a comment id.',
              palette: widget.palette,
            );
            return;
          }
          _commentController.clear();
          await _loadComments(s);
        }
      }
      final inlineErr = await _commitPendingInlineImages(
        subtask: s!,
        state: state,
        entityIdOverrides: commentId == null ? const {} : {'draft': commentId},
      );
      if (inlineErr != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not save inline image',
          content: inlineErr,
          palette: widget.palette,
        );
        return;
      }
      if (isCreator) {
        final attErr = await _replaceSubtaskFileAndUrlAttachments(s!.id);
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
      _notifyParentTaskOfSubtaskChange();
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
      final inlineErr = await _commitPendingInlineImages(
        subtask: s,
        state: state,
      );
      if (inlineErr != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not save inline image',
          content: inlineErr,
          palette: widget.palette,
        );
        return;
      }
      _notifyParentTaskOfSubtaskChange();
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
        (token) =>
            BackendApi().notifySubtaskAccepted(idToken: token, subtaskId: s.id),
      );
    }
  }

  Future<void> _submitSubtask(AppState state, SingularSubtask s) async {
    final commentText = stripInlineImageMarkers(_commentController.text);
    if (_attachments.isEmpty &&
        commentText.isEmpty &&
        !_hasPendingInlineImages('subtask_comment', 'draft') &&
        _pendingInlineImageDeletes.isEmpty) {
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
      final attErr = await _replaceSubtaskFileAndUrlAttachments(s.id);
      if (attErr != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not save attachments',
          content: attErr,
          palette: widget.palette,
        );
        return;
      }
      String? commentId;
      if (commentText.isNotEmpty ||
          _hasPendingInlineImages('subtask_comment', 'draft')) {
        final ins = await SupabaseService.insertSubtaskCommentRow(
          subtaskId: s.id,
          description: commentText.isNotEmpty
              ? commentText
              : inlineImageOnlyCommentPlaceholder,
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
        commentId = ins.commentId;
        if (commentId == null || commentId.isEmpty) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not add comment',
            content:
                'The comment was not saved because Supabase did not return a comment id.',
            palette: widget.palette,
          );
          return;
        }
        final inlineErr = await _commitPendingInlineImages(
          subtask: s,
          state: state,
          entityIdOverrides: {'draft': commentId},
        );
        if (inlineErr != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not save inline image',
            content: inlineErr,
            palette: widget.palette,
          );
          return;
        }
        _commentController.clear();
        await _loadComments(s);
      }
      if (commentId == null) {
        final inlineErr = await _commitPendingInlineImages(
          subtask: s,
          state: state,
        );
        if (inlineErr != null && mounted) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not save inline image',
            content: inlineErr,
            palette: widget.palette,
          );
          return;
        }
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
      final inlineErr = await _commitPendingInlineImages(
        subtask: s,
        state: state,
      );
      if (inlineErr != null && mounted) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not save inline image',
          content: inlineErr,
          palette: widget.palette,
        );
        return;
      }
      _subtaskAi?.clearAllSuggestions();
      await _load();
      _notifyParentTaskOfSubtaskChange();
      _notifyEmailInBackground(
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
      (token) =>
          BackendApi().notifySubtaskReturned(idToken: token, subtaskId: s.id),
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
      _notifyParentTaskOfSubtaskChange();
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

  Future<void> _addFileAttachment() async {
    if (widget.createMode) {
      final picked = await _withBlockingLoading(
        FirebaseAttachmentUploadService.pickFilesForUpload,
      );
      if (!mounted) return;
      if (picked?.error != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Attachment upload failed',
          content: picked!.error!,
          palette: widget.palette,
        );
        return;
      }
      final files =
          picked?.files ?? const <({Uint8List bytes, String label})>[];
      if (files.isEmpty) return;
      setState(() {
        for (final file in files) {
          _attachments.add(
            _SubtaskAttachmentDraft(
              pendingBytes: file.bytes,
              pendingFilename: file.label,
              desc: file.label,
              mimeType: _attachmentMimeTypeFromName(file.label),
            ),
          );
        }
      });
    } else {
      final s = _subtask;
      if (s == null) return;
      final state = context.read<AppState>();
      final r = await _withBlockingLoading(
        () => FirebaseAttachmentUploadService.pickUploadFilesForSubtask(
          s.id,
          aclStaffKeys: _subtaskAttachmentAclKeys(state),
        ),
      );
      if (!mounted) return;
      if (r?.error != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Attachment upload failed',
          content: r!.error!,
          palette: widget.palette,
        );
        return;
      }
      final files = r?.files ?? const <({String url, String label})>[];
      if (files.isEmpty) return;
      setState(() {
        for (final file in files) {
          _attachments.add(
            _SubtaskAttachmentDraft(
              url: file.url,
              desc: file.label,
              mimeType: _attachmentMimeTypeFromName(file.label),
            ),
          );
        }
      });
    }
  }

  Future<void> _addUrlAttachment(BuildContext anchorContext) async {
    if (!_canOpenAnchoredPicker || _saving) return;
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
        _SubtaskAttachmentDraft(
          url: result.url,
          desc: result.description,
          isWebsiteLink: true,
        ),
      );
    });
  }

  Future<void> _addSubtaskDescriptionInlineImage(
    SingularSubtask subtask,
  ) async {
    await _stageInlineImage(
      entityType: 'subtask_description',
      entityId: subtask.id,
    );
  }

  Future<void> _addDraftSubtaskDescriptionInlineImage() async {
    await _stageInlineImage(
      entityType: 'subtask_description',
      entityId: 'draft_description',
    );
  }

  Future<void> _addExistingCommentInlineImage(
    SingularSubtask subtask,
    SubtaskCommentRowDisplay comment,
  ) async {
    await _stageInlineImage(
      entityType: 'subtask_comment',
      entityId: comment.id,
    );
  }

  Future<void> _addDraftCommentInlineImage() async {
    await _stageInlineImage(entityType: 'subtask_comment', entityId: 'draft');
  }

  Future<void> _stageInlineImage({
    required String entityType,
    required String entityId,
  }) async {
    final picked = await _withBlockingLoading(pickOneFileWithBytes);
    if (!mounted || picked == null) return;
    if (picked.bytes.isEmpty) {
      await showAsanaInfoDialog(
        context: context,
        title: 'Inline image upload failed',
        content: 'Could not read file data.',
        palette: widget.palette,
      );
      return;
    }
    final label = picked.name.trim().isNotEmpty ? picked.name.trim() : 'image';
    setState(
      () => _pendingInlineImageAdds.add(
        _SubtaskInlineImageDraft(
          id: 'draft_${DateTime.now().microsecondsSinceEpoch}',
          entityType: entityType,
          entityId: entityId,
          bytes: picked.bytes,
          label: label,
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

  bool _hasPendingInlineImages(String entityType, String entityId) {
    return _pendingInlineImageAdds.any(
      (draft) => draft.entityType == entityType && draft.entityId == entityId,
    );
  }

  Future<String?> _commitPendingInlineImages({
    required SingularSubtask subtask,
    required AppState state,
    Map<String, String> entityIdOverrides = const {},
  }) async {
    for (final draft in List<_SubtaskInlineImageDraft>.from(
      _pendingInlineImageAdds,
    )) {
      final resolvedEntityId =
          entityIdOverrides[draft.entityId] ?? draft.entityId;
      if (resolvedEntityId.trim().isEmpty || resolvedEntityId == 'draft') {
        continue;
      }
      final upload =
          await FirebaseAttachmentUploadService.uploadBytesForSubtask(
            subtask.id,
            bytes: draft.bytes,
            originalFilename: draft.label,
            aclStaffKeys: _subtaskAttachmentAclKeys(state),
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
      if (row.entityType == 'subtask_comment') {
        final touchErr = await SupabaseService.touchSubtaskCommentRow(
          commentId: row.entityId,
          updaterStaffLookupKey: state.userStaffAppId,
        );
        if (touchErr != null) return touchErr;
      }
    }
    _clearInlineImageDrafts();
    return null;
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
      draft.mimeType = _attachmentMimeTypeFromName(
        draft.pendingFilename ?? draft.descController.text,
      );
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
    if (!_canOpenAnchoredPicker || _saving) return;
    final widthAlignContext =
        _detailPopupWidthAlignKey.currentContext ?? anchorContext;
    final result = await showAsanaAnchoredLinkEditor(
      anchorLink: _attachmentAddAnchorLink,
      anchorContext: anchorContext,
      widthAlignContext: widthAlignContext,
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

  Future<void> _removeAttachment(_SubtaskAttachmentDraft draft) async {
    final persistedId = draft.id?.trim();
    if (persistedId != null &&
        persistedId.isNotEmpty &&
        !_effectiveCreateMode &&
        SupabaseConfig.isConfigured) {
      final isWebsiteLink = _draftShowsAsWebsiteLink(draft);
      if (!isWebsiteLink) {
        final storageErr =
            await FirebaseAttachmentUploadService.deleteUploadedObjectByUrl(
              draft.urlController.text.trim(),
            );
        if (!mounted) return;
        if (storageErr != null) {
          await showAsanaInfoDialog(
            context: context,
            title: 'Could not remove uploaded file',
            content: storageErr,
            palette: widget.palette,
          );
          return;
        }
      }
      final err = isWebsiteLink
          ? await SupabaseService.deleteUrlAttachmentById(persistedId)
          : await SupabaseService.deleteFileAttachmentById(persistedId);
      if (!mounted) return;
      if (err != null) {
        await showAsanaInfoDialog(
          context: context,
          title: 'Could not remove attachment',
          content: err,
          palette: widget.palette,
        );
        return;
      }
    }
    setState(() {
      _attachments.remove(draft);
      draft.dispose();
    });
  }

  List<_SubtaskAttachmentDraft> get _fileAttachments => _attachments
      .where((a) => a.isPendingFile || !_draftShowsAsWebsiteLink(a))
      .toList();

  List<_SubtaskAttachmentDraft> get _urlAttachments => _attachments
      .where((a) => !a.isPendingFile && _draftShowsAsWebsiteLink(a))
      .toList();

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
    List<_SubtaskAttachmentDraft> attachments,
    bool allowRemove, {
    required bool createMode,
    BuildContext? editAnchorContext,
  }) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final imageAttachments = attachments
        .where(
          (draft) =>
              !_draftShowsAsWebsiteLink(draft) &&
              _attachmentDraftIsImage(draft),
        )
        .toList();
    final otherAttachments = attachments
        .where(
          (draft) =>
              _draftShowsAsWebsiteLink(draft) ||
              !_attachmentDraftIsImage(draft),
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
                    (a) => _attachmentTile(
                      context,
                      a,
                      createMode: createMode,
                      allowRemove: allowRemove,
                      editAnchorContext: editAnchorContext,
                    ),
                  )
                  .toList(),
            ),
          ),
        ...otherAttachments.map(
          (a) => _attachmentTile(
            context,
            a,
            createMode: createMode,
            allowRemove: allowRemove,
            editAnchorContext: editAnchorContext,
          ),
        ),
      ],
    );
  }

  Widget _attachmentTwoColumnRow({
    required String label,
    required List<_SubtaskAttachmentDraft> attachments,
    required bool createMode,
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
              allowRemove,
              createMode: createMode,
              editAnchorContext: editAnchorContext,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentTile(
    BuildContext context,
    _SubtaskAttachmentDraft draft, {
    required bool createMode,
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
        subtitle: createMode
            ? 'Uploads when you create the sub-task'
            : 'Uploads when you save',
        enabled: !_saving,
        onRemove: allowRemove ? () => _removeAttachment(draft) : null,
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
      onRemove: canRemove ? () => _removeAttachment(draft) : null,
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
    if (_loading && !_saving) {
      return AsanaDetailSlideScaffold(
        backgroundColor: chrome.body,
        body: const SizedBox.shrink(),
      );
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
    _parentTask =
        state.taskById(widget.parentTaskId ?? s?.taskId ?? '') ?? _parentTask;
    final parent = _parentTask;
    final canEditAttachments =
        _effectiveCreateMode ||
        (s != null && !s.isDeleted && (isCreator || isPic || isAssigneeOnly));
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
              s?.subtaskName.trim().isEmpty ?? true
                  ? '(Unnamed sub-task)'
                  : s!.subtaskName.trim(),
              style: asanaDetailTitleStyle(context),
            ),
          const SizedBox(height: 12),
          AsanaDetailLabelValue(
            label: 'Description',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _descController,
                  canEdit: isCreator,
                  readOnly: _saving,
                  maxLines: 8,
                  minLines: 2,
                  style: asanaDetailMultilineValueStyle(context),
                  hintText: 'Please fill in sub-task description',
                ),
                if (_effectiveCreateMode)
                  InlineImageToolbar(
                    enabled: !_saving,
                    onAdd: _addDraftSubtaskDescriptionInlineImage,
                  )
                else if (isCreator && s != null)
                  InlineImageToolbar(
                    enabled: !_saving,
                    onAdd: () => _addSubtaskDescriptionInlineImage(s),
                  ),
                InlineImagePreviewList(
                  images: _inlinePreviewItems(
                    entityType: 'subtask_description',
                    entityId: _effectiveCreateMode
                        ? 'draft_description'
                        : (s?.id ?? ''),
                    saved: _descriptionInlineImages,
                  ),
                  onRemove: _removeInlineImagePreview,
                ),
              ],
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
            child: KeyedSubtree(
              key: _detailPopupWidthAlignKey,
              child: Builder(
                builder: (anchorContext) => CompositedTransformTarget(
                  link: _assigneeAnchorLink,
                  child: isCreator
                      ? AsanaAssigneeFieldValue(
                          assignees: _assigneeRowsForDisplay(state),
                          canEdit: true,
                          onOpenPicker: _saving
                              ? null
                              : (_) => _pickAssignees(anchorContext),
                          onRemove: _saving ? null : _removeAssignee,
                        )
                      : AsanaDetailPlainValue(
                          text:
                              s?.assigneeIds
                                  .map((id) => _nameFor(state, id))
                                  .where((n) => n.isNotEmpty)
                                  .join(', ') ??
                              '',
                        ),
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
                            ? [
                                (
                                  id: _picAssigneeId!,
                                  name: _labelForAssigneeId(
                                    _picAssigneeId!,
                                    state,
                                  ),
                                ),
                              ]
                            : [],
                        canEdit: _assigneeIds.isNotEmpty,
                        emptyPlaceholder: 'Select assignees first',
                        showAddButtonWhenNotEmpty: false,
                        onOpenPicker: _saving || _assigneeIds.isEmpty
                            ? null
                            : (_) => _pickPic(anchorContext, state),
                        onRemove: _saving ? null : _removePic,
                      )
                    : AsanaDetailPlainValue(
                        text:
                            s?.picDisplayName((k) => _nameFor(state, k)) ?? '',
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
                          onTap: _saving
                              ? null
                              : () => _pickStatus(anchorContext),
                          child: AsanaDetailStatusPill(
                            status: _draftStatus ?? s?.status ?? 'Todo',
                          ),
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
                onTap: _saving
                    ? null
                    : (_) => _pickStartDueRange(anchorContext),
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
                onTap: _saving
                    ? null
                    : (_) => _pickStartDueRange(anchorContext),
              ),
            ),
          ),
          if (isCreator) _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
          if (isCreator &&
              (_needsChangeDueReason() ||
                  _reasonController.text.trim().isNotEmpty))
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
          _attachmentTwoColumnRow(
            label: 'Files',
            attachments: _fileAttachments,
            createMode: _effectiveCreateMode,
            showAdd: true,
            addEnabled: canEditAttachments && !_saving,
            addTooltip: 'Add file',
            onAdd: (_) => _addFileAttachment(),
            allowRemove: canEditAttachments,
          ),
          Builder(
            builder: (attachmentCtx) => _attachmentTwoColumnRow(
              label: 'Links',
              attachments: _urlAttachments,
              createMode: _effectiveCreateMode,
              showAdd: true,
              addEnabled: canEditAttachments && !_saving,
              addTooltip: 'Add link',
              addAnchorLink: _attachmentAddAnchorLink,
              onAdd: _addUrlAttachment,
              allowRemove: canEditAttachments,
              editAnchorContext: attachmentCtx,
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.websiteLink),
          if (!_effectiveCreateMode) ...[
            if ((s?.updateByStaffName ?? '').trim().isNotEmpty)
              AsanaDetailTwoColumnRow(
                label: 'Last updated by',
                child: AsanaDetailPlainValue(
                  text: s!.updateByStaffName!.trim(),
                ),
              ),
            if (s?.lastUpdated != null)
              AsanaDetailTwoColumnRow(
                label: 'Last updated',
                child: AsanaDetailPlainValue(
                  text: HkTime.formatInstantAsHk(
                    s!.lastUpdated,
                    'MMM d, yyyy HH:mm',
                  ),
                ),
              ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          AsanaDetailSectionHeader(title: 'Comments', showAddButton: false),
          if (!_effectiveCreateMode && _comments.isNotEmpty) ...[
            for (final c in _comments) _buildCommentDisplayTile(state, c, s),
            const SizedBox(height: 8),
          ],
          AsanaDetailLabelValue(
            label: 'New comment',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _commentController,
                  canEdit: true,
                  readOnly: _saving,
                  maxLines: 8,
                  minLines: 2,
                  hintText: 'Ask a question or post an update...',
                ),
                InlineImageToolbar(
                  enabled: !_saving,
                  onAdd: _addDraftCommentInlineImage,
                ),
                InlineImagePreviewList(
                  images: _inlinePreviewItems(
                    entityType: 'subtask_comment',
                    entityId: 'draft',
                    saved: const [],
                  ),
                  onRemove: _removeInlineImagePreview,
                ),
              ],
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.comment),
        ],
      ),
    );
  }
}
