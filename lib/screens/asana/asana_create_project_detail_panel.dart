import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/staff_for_assignment.dart';
import '../../services/backend_api.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/attachment_file_pick.dart';
import '../../utils/attachment_url_launch.dart';
import '../../utils/hk_time.dart';
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
import 'asana_task_ai_assistant.dart';

class _CreateProjectAttachmentDraft {
  _CreateProjectAttachmentDraft({
    String? url,
    String? desc,
    this.mimeType,
    this.isWebsiteLink = false,
  }) : urlController = TextEditingController(text: url ?? ''),
       descController = TextEditingController(text: desc ?? '');

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

class _CreateProjectInlineImageDraft {
  _CreateProjectInlineImageDraft({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.bytes,
    required this.label,
    required this.mimeType,
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
  final _commentController = TextEditingController();
  final List<_CreateProjectAttachmentDraft> _attachments = [];
  final List<_CreateProjectInlineImageDraft> _pendingInlineImageAdds = [];
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
  final ValueNotifier<AsanaAssigneePickerSnapshot> _picSnapshot = ValueNotifier(
    const AsanaAssigneePickerSnapshot(loading: true),
  );
  final LayerLink _assigneeAnchorLink = LayerLink();
  final LayerLink _picAnchorLink = LayerLink();
  final LayerLink _statusAnchorLink = LayerLink();
  final LayerLink _attachmentAddAnchorLink = LayerLink();
  final GlobalKey _detailPopupWidthAlignKey = GlobalKey();
  int _anchoredPickerReopenBlockedUntilMs = 0;
  AsanaTaskAiController? _projectAi;

  @override
  void initState() {
    super.initState();
    _loadAssigneePicker();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    for (final attachment in _attachments) {
      attachment.dispose();
    }
    _assigneeSnapshot.dispose();
    _picSnapshot.dispose();
    _projectAi?.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
  }

  bool get _canOpenAnchoredPicker =>
      DateTime.now().millisecondsSinceEpoch >
      _anchoredPickerReopenBlockedUntilMs;

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
      status: _draftStatus,
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
          _CreateProjectAttachmentDraft(
            url: url,
            desc: desc,
            isWebsiteLink: true,
          ),
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
          entityId: null,
          staffId: state.userStaffId,
          staffDisplayName: _labelForAssigneeId(
            state.userStaffAppId ?? '',
            state,
          ),
          actionType: 'create',
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
    if (mounted && _saving) setState(() => _saving = false);
    return showAsanaInfoDialog(
      context: context,
      title: title,
      content: content,
      palette: widget.palette,
    );
  }

  bool _draftShowsAsWebsiteLink(_CreateProjectAttachmentDraft draft) {
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

  bool _attachmentDraftIsImage(_CreateProjectAttachmentDraft draft) {
    final mime = draft.mimeType?.toLowerCase().trim() ?? '';
    if (mime.startsWith('image/')) return true;
    final name = draft.pendingFilename?.trim().isNotEmpty == true
        ? draft.pendingFilename!.trim()
        : draft.descController.text.trim();
    return _attachmentMimeTypeFromName(name) != null;
  }

  bool _shouldAttemptAttachmentImagePreview(
    _CreateProjectAttachmentDraft draft,
  ) {
    return _attachmentDraftIsImage(draft);
  }

  List<String?> _projectAttachmentAclKeys(AppState state) {
    return [state.userStaffAppId, ..._picAssigneeIds, ..._assigneeIds];
  }

  Future<void> _addFileAttachment() async {
    final picked = await _withBlockingLoading(
      FirebaseAttachmentUploadService.pickFilesForUpload,
    );
    if (!mounted) return;
    if (picked?.error != null) {
      await _showInfo('Attachment upload failed', picked!.error!);
      return;
    }
    final files = picked?.files ?? const <({Uint8List bytes, String label})>[];
    if (files.isEmpty) return;
    setState(() {
      for (final file in files) {
        final draft = _CreateProjectAttachmentDraft(
          desc: file.label,
          mimeType: _attachmentMimeTypeFromName(file.label),
        );
        draft.pendingBytes = file.bytes;
        draft.pendingFilename = file.label;
        _attachments.add(draft);
      }
    });
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
        _CreateProjectAttachmentDraft(
          url: result.url,
          desc: result.description,
          isWebsiteLink: true,
        ),
      );
    });
  }

  void _removeAttachmentDraft(_CreateProjectAttachmentDraft draft) {
    setState(() {
      draft.dispose();
      _attachments.remove(draft);
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
        _CreateProjectInlineImageDraft(
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
      _pendingInlineImageAdds.removeWhere((draft) => draft.id == image.id);
    });
  }

  List<InlineImagePreviewItem> _inlinePreviewItems({
    required String entityType,
    required String entityId,
  }) {
    return _pendingInlineImageAdds
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
        )
        .toList();
  }

  Future<String?> _uploadPendingFileAttachments(
    String projectId,
    AppState state,
  ) async {
    for (final draft in _attachments) {
      if (!draft.isPendingFile) continue;
      final upload =
          await FirebaseAttachmentUploadService.uploadBytesForProject(
            projectId,
            bytes: draft.pendingBytes!,
            originalFilename: draft.pendingFilename ?? 'attachment',
            aclStaffKeys: _projectAttachmentAclKeys(state),
          );
      if (upload.error != null) return upload.error;
      final url = upload.url?.trim();
      if (url == null || url.isEmpty) {
        return 'File upload did not return a download link.';
      }
      draft.urlController.text = url;
      draft.mimeType = _attachmentMimeTypeFromName(
        draft.pendingFilename ?? draft.descController.text,
      );
      if (draft.descController.text.trim().isEmpty) {
        draft.descController.text =
            upload.label?.trim() ?? draft.pendingFilename ?? 'attachment';
      }
      draft.pendingBytes = null;
      draft.pendingFilename = null;
    }
    return null;
  }

  Future<String?> _commitPendingInlineImages({
    required String projectId,
    required AppState state,
    Map<String, String> entityIdOverrides = const {},
  }) async {
    for (final draft in List<_CreateProjectInlineImageDraft>.from(
      _pendingInlineImageAdds,
    )) {
      final resolvedEntityId =
          entityIdOverrides[draft.entityId] ?? draft.entityId;
      if (resolvedEntityId.trim().isEmpty || resolvedEntityId == 'draft') {
        continue;
      }
      final upload =
          await FirebaseAttachmentUploadService.uploadBytesForProject(
            projectId,
            bytes: draft.bytes,
            originalFilename: draft.label,
            aclStaffKeys: _projectAttachmentAclKeys(state),
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
    _pendingInlineImageAdds.clear();
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
            id: null,
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
            id: null,
            url: url.isEmpty ? null : url,
            label: desc.isEmpty ? url : desc,
          );
        })
        .where((r) => (r.url ?? '').isNotEmpty)
        .toList();
  }

  Future<String?> _replaceProjectAttachments(String projectId) async {
    final fileErr = await SupabaseService.replaceFileAttachments(
      entityType: 'project',
      entityId: projectId,
      rows: _fileAttachmentPayload(),
    );
    if (fileErr != null) return fileErr;
    return SupabaseService.replaceUrlAttachments(
      entityType: 'project',
      entityId: projectId,
      rows: _urlAttachmentPayload(),
    );
  }

  List<_CreateProjectAttachmentDraft> get _fileAttachments => _attachments
      .where((a) => a.isPendingFile || !_draftShowsAsWebsiteLink(a))
      .toList();

  List<_CreateProjectAttachmentDraft> get _urlAttachments => _attachments
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

  Future<void> _editAttachmentLink(
    BuildContext anchorContext,
    _CreateProjectAttachmentDraft draft,
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

  Widget _attachmentTwoColumnRow({
    required String label,
    required List<_CreateProjectAttachmentDraft> attachments,
    required String addTooltip,
    required void Function(BuildContext buttonContext) onAdd,
    LayerLink? addAnchorLink,
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label, style: asanaDetailLabelStyle(context)),
                ),
                const SizedBox(width: 8),
                AsanaDetailCircleAddButton(
                  onTap: onAdd,
                  enabled: !_saving,
                  tooltip: addTooltip,
                  size: 22,
                  anchorLink: addAnchorLink,
                ),
              ],
            ),
          ),
          Expanded(
            child: _attachmentValueList(
              attachments,
              editAnchorContext: editAnchorContext,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentValueList(
    List<_CreateProjectAttachmentDraft> attachments, {
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
              children: imageAttachments.map(_attachmentDraftTile).toList(),
            ),
          ),
        ...otherAttachments.map(
          (draft) =>
              _attachmentDraftTile(draft, editAnchorContext: editAnchorContext),
        ),
      ],
    );
  }

  Widget _attachmentDraftTile(
    _CreateProjectAttachmentDraft draft, {
    BuildContext? editAnchorContext,
  }) {
    if (draft.isPendingFile) {
      final name = draft.pendingFilename?.trim().isNotEmpty == true
          ? draft.pendingFilename!.trim()
          : 'File';
      return AsanaAttachmentDraftTile(
        isWebsiteLink: false,
        title: name,
        subtitle: 'Uploads when you create the project',
        enabled: !_saving,
        onRemove: () => _removeAttachmentDraft(draft),
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
    return AsanaAttachmentDraftTile(
      isWebsiteLink: isLink,
      title: title,
      url: url,
      enabled: !_saving,
      onRemove: () => _removeAttachmentDraft(draft),
      onEditLink: isLink && editAnchorContext != null
          ? () => _editAttachmentLink(editAnchorContext, draft)
          : null,
      imageBytes: draft.pendingBytes,
      mimeType: draft.mimeType,
      showImagePreview: !isLink && _attachmentDraftIsImage(draft),
    );
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
    await AsanaBlockingLoadingOverlay.showAfterFrame(context);
    try {
      final slots = await SupabaseService.assigneeSlotsForProject(
        _assigneeIds.toList(),
      );
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
        await _showInfo('Could not create project', ins.error!);
        return;
      }
      final newId = ins.projectId;
      if (newId != null && newId.isNotEmpty) {
        _projectAi?.attachCreatedEntityId(newId);
        final commentText = stripInlineImageMarkers(_commentController.text);
        final hasDraftComment =
            commentText.isNotEmpty ||
            _pendingInlineImageAdds.any(
              (draft) =>
                  draft.entityType == 'project_comment' &&
                  draft.entityId == 'draft',
            );
        String? draftCommentId;
        if (hasDraftComment) {
          final comment = await SupabaseService.insertProjectCommentRow(
            projectId: newId,
            description: commentText.isNotEmpty
                ? commentText
                : inlineImageOnlyCommentPlaceholder,
            creatorStaffLookupKey: state.userStaffAppId,
          );
          if (comment.error != null) {
            await _showInfo('Could not add comment', comment.error!);
            return;
          }
          draftCommentId = comment.commentId;
          if (draftCommentId == null || draftCommentId.isEmpty) {
            await _showInfo(
              'Could not add comment',
              'The comment was not saved because Supabase did not return a comment id.',
            );
            return;
          }
        }
        final inlineErr = await _commitPendingInlineImages(
          projectId: newId,
          state: state,
          entityIdOverrides: draftCommentId == null
              ? {'draft_description': newId}
              : {'draft_description': newId, 'draft': draftCommentId},
        );
        if (inlineErr != null) {
          await _showInfo('Could not save inline image', inlineErr);
          return;
        }
        final uploadErr = await _uploadPendingFileAttachments(newId, state);
        if (uploadErr != null) {
          await _showInfo('Attachment upload failed', uploadErr);
          return;
        }
        final attachmentErr = await _replaceProjectAttachments(newId);
        if (attachmentErr != null) {
          await _showInfo('Could not save attachments', attachmentErr);
          return;
        }
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
    _ensureProjectAi();
    final creatorName = () {
      final id = state.userStaffAppId?.trim();
      if (id == null || id.isEmpty) return '';
      return state.assigneeById(id)?.name.trim() ?? id;
    }();

    return AsanaDetailSlideScaffold(
      backgroundColor: chrome.body,
      footer: Column(
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
        ],
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
          _aiSuggestions(AsanaTaskAiFieldKey.taskName),
          const SizedBox(height: 12),
          AsanaDetailLabelValue(
            label: 'Description',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AsanaHoverTextField(
                  controller: _descController,
                  canEdit: true,
                  readOnly: _saving,
                  maxLines: 8,
                  minLines: 2,
                  style: asanaDetailMultilineValueStyle(context),
                  hintText: 'Please fill in project description',
                ),
                InlineImageToolbar(
                  enabled: !_saving,
                  onAdd: () => _stageInlineImage(
                    entityType: 'project_description',
                    entityId: 'draft_description',
                  ),
                ),
                InlineImagePreviewList(
                  images: _inlinePreviewItems(
                    entityType: 'project_description',
                    entityId: 'draft_description',
                  ),
                  onRemove: _removeInlineImagePreview,
                ),
              ],
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.description),
          AsanaDetailTwoColumnRow(
            label: 'Creator',
            child: AsanaDetailPlainValue(text: creatorName),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Assignees',
            child: KeyedSubtree(
              key: _detailPopupWidthAlignKey,
              child: AsanaAssigneeFieldValue(
                anchorLink: _assigneeAnchorLink,
                assignees: _rowsForIds(_assigneeIds, state),
                canEdit: !_saving,
                onOpenPicker: _pickAssignees,
                onRemove: _removeAssignee,
              ),
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.assignees),
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
          _aiSuggestions(AsanaTaskAiFieldKey.pic),
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
                    onTap: _saving ? null : () => _pickStatus(anchorContext),
                    child: AsanaDetailStatusPill(status: _draftStatus),
                  ),
                ),
              ),
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.projectStatus),
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
          _aiSuggestions(AsanaTaskAiFieldKey.startDate),
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
          _aiSuggestions(AsanaTaskAiFieldKey.dueDate),
          Builder(
            builder: (anchorContext) => _attachmentTwoColumnRow(
              label: 'Files',
              attachments: _fileAttachments,
              addTooltip: 'Add file',
              onAdd: (_) => _addFileAttachment(),
            ),
          ),
          Builder(
            builder: (anchorContext) => _attachmentTwoColumnRow(
              label: 'Links',
              attachments: _urlAttachments,
              addTooltip: 'Add website link',
              onAdd: _addUrlAttachment,
              addAnchorLink: _attachmentAddAnchorLink,
              editAnchorContext: anchorContext,
            ),
          ),
          _aiSuggestions(AsanaTaskAiFieldKey.websiteLink),
          AsanaDetailLabelValue(
            label: 'Comments',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
