import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/singular_subtask.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/backend_api.dart';
import '../../services/firebase_attachment_upload_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/attachment_save_reminder_snackbar.dart';
import '../../utils/attachment_upload_loading_overlay.dart';
import '../../utils/home_navigation.dart';
import '../../widgets/flow_bottom_nav_four.dart';
import '../../widgets/flow_navigation_bar.dart';
import '../../utils/attachment_url_launch.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../../web_deep_link.dart';
import '../../widgets/attachment_add_link_dialog.dart';
import '../../widgets/attachment_edit_dialog.dart';
import '../../widgets/attachment_source_bottom_sheet.dart';
import '../../widgets/outlook_attachment_chip.dart';
import 'project_detail_screen.dart';
import '../task_detail_screen.dart';

class _SubtaskAttachmentEntry {
  _SubtaskAttachmentEntry({this.id, String? url, String? desc})
      : urlController = TextEditingController(text: url ?? ''),
        descController = TextEditingController(text: desc ?? '');
  final String? id;
  final TextEditingController urlController;
  final TextEditingController descController;

  void dispose() {
    urlController.dispose();
    descController.dispose();
  }
}

/// Detail view for a row in `public.subtask`.
class SubtaskDetailScreen extends StatefulWidget {
  const SubtaskDetailScreen({
    super.key,
    required this.subtaskId,
    this.replaceWithParentTaskOnBack = false,
    this.openedFromOverview = false,
    this.openedFromProjectDetail = false,
    this.openedFromProjectDashboard = false,
    this.onParentTaskListRefresh,
  });

  final String subtaskId;

  /// When true (e.g. opened from the landing task list without [TaskDetailScreen] underneath),
  /// **Back to task** opens the parent [TaskDetailScreen] via [Navigator.pushReplacement] instead of [pop].
  final bool replaceWithParentTaskOnBack;

  /// Pushed from Overview vs other lists.
  final bool openedFromOverview;

  /// Under [ProjectDetailScreen] flow — **Back to project** below Delete.
  final bool openedFromProjectDetail;

  /// Opened from task detail when parent task was reached from Project dashboard flow.
  final bool openedFromProjectDashboard;

  /// After delete/undo writes succeed — refresh parent [TaskDetailScreen] sub-task lists.
  final Future<void> Function()? onParentTaskListRefresh;

  @override
  State<SubtaskDetailScreen> createState() => _SubtaskDetailScreenState();
}

class _SubtaskDetailScreenState extends State<SubtaskDetailScreen> {
  static const Color _selGreen = Color(0xFF1B5E20);

  SingularSubtask? _sub;
  Task? _parentTask;
  String? _myStaffUuid;
  bool _director = false;
  bool _loading = true;
  bool _saving = false;

  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final List<_SubtaskAttachmentEntry> _subtaskAttachments = [];
  final _commentController = TextEditingController();
  final _changeDueReasonController = TextEditingController();
  final _editCommentController = TextEditingController();

  /// Non-null while inline-editing a [SubtaskCommentRowDisplay] by id.
  String? _editingCommentId;

  List<SubtaskCommentRowDisplay> _comments = [];
  String? _resolvedPicStaffUuid;

  /// Last loaded [SingularSubtask.pic] as an assignee key (for dirty check).
  String? _picAssigneeKeyResolved;

  /// Edited PIC assignee key; saved with **Update** (not on dropdown change).
  String? _picEditKey;
  int _editPriority = priorityStandard;
  DateTime? _editStart;
  DateTime? _editDue;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      syncWebLocationForSubtaskDetail(widget.subtaskId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (kIsWeb) {
      clearWebSubtaskDetailFromLocation(parentTaskId: _sub?.taskId);
    }
    _nameController.dispose();
    _descController.dispose();
    _clearSubtaskAttachments();
    _commentController.dispose();
    _changeDueReasonController.dispose();
    _editCommentController.dispose();
    super.dispose();
  }

  void _clearSubtaskAttachments() {
    for (final e in _subtaskAttachments) {
      e.dispose();
    }
    _subtaskAttachments.clear();
  }

  void _onBackToTask() {
    if (_saving) return;
    final tid = _sub?.taskId;
    if (tid == null || tid.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    if (widget.replaceWithParentTaskOnBack) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TaskDetailScreen(
            taskId: tid,
            openedFromOverview: widget.openedFromOverview,
            openedFromProjectDashboard: widget.openedFromProjectDashboard,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  void _removeSubtaskAttachmentRow(int index) {
    setState(() {
      _subtaskAttachments[index].dispose();
      _subtaskAttachments.removeAt(index);
    });
  }

  List<String?> _singularSubtaskAttachmentAclKeys(SingularSubtask st) => [
    st.createByStaffId,
    st.pic,
    ...st.assigneeIds,
  ];

  Future<void> _addSubtaskAttachmentFromDevice() async {
    final st = _sub;
    if (st == null) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Sub-task is not loaded yet; try again in a moment.',
          backgroundColor: Colors.orange,
        );
      }
      return;
    }
    final r = await FirebaseAttachmentUploadService.pickUploadForSubtask(
      widget.subtaskId,
      aclStaffKeys: _singularSubtaskAttachmentAclKeys(st),
      onUploadPhaseStarted: () => showAttachmentUploadPleaseWait(context),
      onUploadPhaseEnded: () => hideAttachmentUploadPleaseWait(context),
    );
    if (!mounted) return;
    if (r.error != null && r.error!.isNotEmpty) {
      showCopyableSnackBar(
        context,
        r.error!,
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (r.url == null) return;
    setState(() {
      _subtaskAttachments.add(
        _SubtaskAttachmentEntry(
          url: r.url,
          desc: (r.label ?? '').trim(),
        ),
      );
    });
    if (mounted) {
      showAttachmentSaveReminderSnackBar(context);
    }
  }

  Future<void> _addSubtaskAttachmentFromLink() async {
    final result = await showAttachmentAddLinkDialog(context);
    if (!mounted || result == null) return;
    setState(() {
      _subtaskAttachments.add(
        _SubtaskAttachmentEntry(
          url: result.url,
          desc: result.description,
        ),
      );
    });
    if (mounted) {
      showAttachmentSaveReminderSnackBar(context);
    }
  }

  Future<void> _editSubtaskAttachment(int index) async {
    final e = _subtaskAttachments[index];
    final r = await showAttachmentEditDialog(
      context,
      initialDescription: e.descController.text,
      initialUrl: e.urlController.text,
      pickReplaceFromDevice: () {
        final st = _sub;
        if (st == null) {
          return Future.value((
            url: null,
            label: null,
            error: 'Sub-task is not loaded yet; try again in a moment.',
          ));
        }
        return FirebaseAttachmentUploadService.pickUploadForSubtask(
          widget.subtaskId,
          aclStaffKeys: _singularSubtaskAttachmentAclKeys(st),
          onUploadPhaseStarted: () => showAttachmentUploadPleaseWait(context),
          onUploadPhaseEnded: () => hideAttachmentUploadPleaseWait(context),
        );
      },
    );
    if (!mounted || r == null) return;
    setState(() {
      e.descController.text = r.description;
      e.urlController.text = r.url;
    });
    if (mounted) {
      showAttachmentSaveReminderSnackBar(context);
    }
  }

  List<({String? content, String? description})> _subtaskAttachmentPayload() {
    return _subtaskAttachments
        .map(
          (e) => (
            content: e.urlController.text,
            description: e.descController.text,
          ),
        )
        .toList();
  }

  String? _firstSubtaskAttachmentUrl() {
    for (final e in _subtaskAttachments) {
      final u = e.urlController.text.trim();
      if (u.isNotEmpty) return u;
    }
    return null;
  }

  /// Normalized rows after load — for “nothing changed” detection.
  List<({String c, String d})> _subtaskAttachmentBaseline = [];

  void _captureSubtaskAttachmentBaseline() {
    _subtaskAttachmentBaseline = _subtaskAttachments
        .map(
          (e) => (
            c: e.urlController.text.trim(),
            d: e.descController.text.trim(),
          ),
        )
        .toList();
  }

  bool _subtaskAttachmentsDirty() {
    final cur = _subtaskAttachments
        .map(
          (e) => (
            c: e.urlController.text.trim(),
            d: e.descController.text.trim(),
          ),
        )
        .toList();
    if (cur.length != _subtaskAttachmentBaseline.length) return true;
    for (var i = 0; i < cur.length; i++) {
      if (cur[i].c != _subtaskAttachmentBaseline[i].c ||
          cur[i].d != _subtaskAttachmentBaseline[i].d) {
        return true;
      }
    }
    return false;
  }

  static bool _subtaskDateOnlyEqual(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Creator path: metadata or attachments differ from loaded [st].
  bool _subtaskCreatorHasMetadataOrAttachmentChanges(
    AppState state,
    SingularSubtask st,
    Task parent,
  ) {
    if (_nameController.text.trim() != st.subtaskName.trim()) return true;
    if (_descController.text.trim() != st.description.trim()) return true;
    if (_editPriority != st.priority) return true;
    if (!_subtaskDateOnlyEqual(_editStart, st.startDate)) return true;
    if (!_subtaskDateOnlyEqual(_editDue, st.dueDate)) return true;
    final curR = _changeDueReasonController.text.trim();
    final oldR = (st.changeDueReason ?? '').trim();
    if (curR != oldR) return true;
    final multi = parent.assigneeIds.length > 1;
    final canPic = _canEditSubtaskPic(state, st, parent);
    final picDirty = canPic && multi && _picEditIsDirty(parent);
    if (picDirty) {
      final k = _picEditKey?.trim() ?? '';
      final existing = (st.pic ?? '').trim();
      if (k != existing) return true;
    }
    if (_subtaskAttachmentsDirty()) return true;
    return false;
  }

  bool _canEditSubtaskAttachments(AppState state, SingularSubtask st) =>
      !st.isDeleted &&
      (_isCreator(state, st) || _isPic(state, st) || _isAssignee(state, st));

  /// When [rebindAttachments] is false, existing attachment text fields are left unchanged
  /// (use after Update/Submit when rows were just written — avoids empty SELECT wiping the UI).
  Future<void> _load({bool rebindAttachments = true}) async {
    if (!SupabaseConfig.isConfigured) {
      setState(() => _loading = false);
      return;
    }
    final st = await SupabaseService.fetchSubtaskById(widget.subtaskId);
    final state = context.read<AppState>();
    Task? parent;
    if (st != null) {
      parent = await SupabaseService.fetchSingularTaskModelById(st.taskId) ??
          state.taskById(st.taskId);
    }
    String? myU;
    final lk = state.userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty) {
      myU = await SupabaseService.staffRowIdForAssigneeKey(lk);
      if (myU != null && myU.isNotEmpty) {
        final dir = await SupabaseService.fetchStaffDirectorByStaffUuid(myU);
        if (mounted) setState(() => _director = dir);
      }
    }
    List<SubtaskAttachmentRow> attRows = [];
    if (st != null) {
      if (rebindAttachments) {
        try {
          attRows = await SupabaseService.fetchSubtaskAttachments(st.id);
        } catch (e, stTrace) {
          debugPrint('subtask attachments load: $e\n$stTrace');
          attRows = [];
        }
      }
      final cm = await SupabaseService.fetchSubtaskComments(st.id);
      if (mounted) {
        setState(() {
          _comments = cm;
        });
      }
    }
    if (!mounted) return;
    String? picUuid;
    if (st?.pic != null && st!.pic!.trim().isNotEmpty) {
      picUuid = await SupabaseService.staffRowIdForAssigneeKey(st.pic!.trim());
    }
    if (!mounted) return;
    String? picKeyResolved;
    if (st != null && parent != null) {
      final p = st.pic?.trim();
      if (p != null && p.isNotEmpty) {
        for (final id in parent.assigneeIds) {
          if (id == p) {
            picKeyResolved = id;
            break;
          }
        }
        if (picKeyResolved == null && picUuid != null && picUuid.isNotEmpty) {
          for (final id in parent.assigneeIds) {
            final u = await SupabaseService.staffRowIdForAssigneeKey(id);
            if (_uuidEq(u, picUuid)) {
              picKeyResolved = id;
              break;
            }
          }
        }
      }
    }
    if (!mounted) return;
    if (rebindAttachments) {
      _clearSubtaskAttachments();
    }
    setState(() {
      _sub = st;
      _parentTask = parent;
      _myStaffUuid = myU;
      _resolvedPicStaffUuid = picUuid;
      _picAssigneeKeyResolved = picKeyResolved;
      _picEditKey = picKeyResolved;
      _loading = false;
      if (st != null) {
        _nameController.text = st.subtaskName;
        _descController.text = st.description;
        if (rebindAttachments) {
          for (final r in attRows) {
            _subtaskAttachments.add(
              _SubtaskAttachmentEntry(
                id: r.id,
                url: r.content,
                desc: r.description,
              ),
            );
          }
        }
        _editPriority = st.priority;
        _editStart = st.startDate;
        _editDue = st.dueDate;
        _changeDueReasonController.text = st.changeDueReason ?? '';
      }
    });
    if (mounted && st != null) {
      _captureSubtaskAttachmentBaseline();
    }
  }

  bool _needsChangeDueReason() {
    return dueDateExceedsPolicyForPriority(
      _editStart,
      _editDue,
      _editPriority,
    );
  }

  /// Display for `subtask.create_by` (resolved name when available).
  String _subtaskCreatorLabel(SingularSubtask st) {
    final n = st.createByStaffName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final id = st.createByStaffId?.trim();
    if (id != null && id.isNotEmpty) return id;
    return '—';
  }

  bool _uuidEq(String? a, String? b) {
    final x = a?.trim().toLowerCase() ?? '';
    final y = b?.trim().toLowerCase() ?? '';
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  bool _isCreator(AppState state, SingularSubtask st) {
    final cb = st.createByStaffId?.trim();
    return _uuidEq(_myStaffUuid, cb);
  }

  bool _isParentTaskCreator(AppState state, Task parent) {
    final mine = state.userStaffAppId?.trim();
    final cb = parent.createByAssigneeKey?.trim();
    return mine != null &&
        mine.isNotEmpty &&
        cb != null &&
        cb.isNotEmpty &&
        mine == cb;
  }

  /// Sub-task creator or parent task creator may set [SingularSubtask.pic] from task assignees.
  bool _canEditSubtaskPic(AppState state, SingularSubtask st, Task parent) =>
      _isCreator(state, st) || _isParentTaskCreator(state, parent);

  bool _picEditIsDirty(Task parent) {
    if (parent.assigneeIds.length <= 1) return false;
    final a = _picAssigneeKeyResolved?.trim() ?? '';
    final b = _picEditKey?.trim() ?? '';
    return a != b;
  }

  /// [stored] is `subtask.update_date`; display in Hong Kong (UTC+8).
  String _subtaskLastUpdatedLine(DateTime? stored) {
    if (stored == null) return 'Last updated: —';
    return 'Last updated: ${HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm')}';
  }

  /// Posted time for sub-task comments (matches [TaskDetailScreen._formatCommentPostedTs]).
  String _formatSubtaskCommentPostedTs(DateTime? stored) {
    if (stored == null) return '—';
    return HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm');
  }

  /// `Last updated: …` line (matches [TaskDetailScreen._formatCommentLastUpdatedLine]).
  String _formatSubtaskCommentLastUpdatedLine(DateTime? stored) {
    if (stored == null) return 'Last updated: —';
    return 'Last updated: ${HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm')}';
  }

  bool _isCommentAuthor(SubtaskCommentRowDisplay c) {
    final id = c.createByStaffId?.trim();
    if (id == null || id.isEmpty) return false;
    return _uuidEq(_myStaffUuid, id);
  }

  /// Dimmed when [enabled] is false; no tap target (read-only), same look as task detail opacity.
  Widget _priorityToggleButton({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _selGreen, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          color: selected ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Material(
          color: selected ? _selGreen : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: enabled
              ? InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: body,
                )
              : body,
        ),
      ),
    );
  }

  bool _isPic(AppState state, SingularSubtask st) {
    final p = st.pic?.trim();
    final mine = state.userStaffAppId?.trim();
    if (mine != null && p != null && mine == p) return true;
    final uid = _myStaffUuid?.trim();
    final picU = _resolvedPicStaffUuid?.trim();
    if (uid != null && picU != null && _uuidEq(uid, picU)) return true;
    return false;
  }

  bool _isAssignee(AppState state, SingularSubtask st) {
    final mine = state.userStaffAppId?.trim();
    if (mine != null && st.assigneeIds.contains(mine)) return true;
    final uid = _myStaffUuid?.trim();
    if (uid == null) return false;
    for (final id in st.assigneeIds) {
      if (_uuidEq(id, uid)) return true;
    }
    return false;
  }

  bool _canPicSubmit(SingularSubtask st) {
    final s = st.submission?.trim() ?? '';
    if (s.isEmpty || s.toLowerCase() == 'pending') return true;
    if (s.toLowerCase() == 'returned') return true;
    if (s.toLowerCase() == 'submitted' || s.toLowerCase() == 'accepted') {
      return false;
    }
    return true;
  }

  static bool _dateOnlyEqual(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static String _formatYmdNotify(DateTime d) {
    return DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));
  }

  /// Field keys must match the backend allow-list for sub-task-updated emails.
  List<Map<String, String>> _buildSubtaskUpdateNotifyChanges({
    required SingularSubtask st,
    required AppState state,
    required String newName,
    required String newDesc,
    required int newPriority,
    required DateTime? newStart,
    required DateTime? newDue,
  }) {
    final out = <Map<String, String>>[];
    if (st.subtaskName.trim() != newName.trim()) {
      out.add({'field': 'subtaskName', 'value': newName.trim()});
    }
    if (st.description.trim() != newDesc.trim()) {
      out.add({'field': 'description', 'value': newDesc.trim()});
    }
    if (st.priority != newPriority) {
      out.add({
        'field': 'priority',
        'value': priorityToDisplayName(newPriority),
      });
    }
    if (!_dateOnlyEqual(st.startDate, newStart)) {
      out.add({
        'field': 'startDate',
        'value': newStart == null ? '—' : _formatYmdNotify(newStart),
      });
    }
    if (!_dateOnlyEqual(st.dueDate, newDue)) {
      out.add({
        'field': 'dueDate',
        'value': newDue == null ? '—' : _formatYmdNotify(newDue),
      });
    }
    return out;
  }

  Future<void> _notifySubtaskCommentCreatorEmail(String commentId) async {
    final id = commentId.trim();
    if (id.isEmpty) return;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token != null) {
        final notifyErr = await BackendApi().notifySubtaskCommentAdded(
          idToken: token,
          commentId: id,
        );
        if (notifyErr != null && mounted) {
          final short = notifyErr.length > 120
              ? '${notifyErr.substring(0, 120)}…'
              : notifyErr;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sub-task comment email: $short'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 4),
            content: Text(
              'Comment saved; notify email skipped (no sign-in token)',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sub-task comment email failed: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Returns `(ok: true, commentId: id)` when a row was inserted.
  /// [suppressSuccessSnack] avoids a green snackbar (e.g. combined Update flow).
  ///
  /// After insert, notifies the sub-task creator via [BackendApi.notifySubtaskCommentAdded] when the
  /// poster is **not** the sub-task creator (server checks assignee on sub-task or parent task and
  /// skips self-mail).
  Future<({bool ok, String? commentId})> _postComment(
    AppState state,
    SingularSubtask st, {
    bool suppressSuccessSnack = false,
  }) async {
    if (!_isAssignee(state, st) && !_isCreator(state, st)) {
      return (ok: false, commentId: null);
    }
    final t = _commentController.text.trim();
    if (t.isEmpty) return (ok: false, commentId: null);
    setState(() => _saving = true);
    try {
      final ins = await SupabaseService.insertSubtaskCommentRow(
        subtaskId: st.id,
        description: t,
        creatorStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return (ok: false, commentId: null);
      if (ins.error != null) {
        showCopyableSnackBar(context, ins.error!, backgroundColor: Colors.orange);
        return (ok: false, commentId: null);
      }
      final newCommentId = ins.commentId?.trim();
      if (newCommentId != null &&
          newCommentId.isNotEmpty &&
          !_isCreator(state, st)) {
        await _notifySubtaskCommentCreatorEmail(newCommentId);
      }
      _commentController.clear();
      await _load(rebindAttachments: false);
      if (!suppressSuccessSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return (ok: true, commentId: newCommentId);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Returns `true` if sub-task rows were written. Use [suppressSuccessSnack] with a follow-up [willSaveCommentAfter] + combined snackbar from **Update**.
  Future<bool> _saveMetadata(
    AppState state,
    SingularSubtask st, {
    bool suppressSuccessSnack = false,
    bool willSaveCommentAfter = false,
  }) async {
    final parent = _parentTask;
    if (parent == null) return false;
    final creator = _isCreator(state, st);
    final canPic = _canEditSubtaskPic(state, st, parent);
    final multiTaskAssignees = parent.assigneeIds.length > 1;
    final picDirty =
        canPic && multiTaskAssignees && _picEditIsDirty(parent);
    if (!creator) {
      if (canPic && multiTaskAssignees && picDirty) {
        final key = _picEditKey?.trim();
        if (key == null ||
            key.isEmpty ||
            !parent.assigneeIds.contains(key)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(duration: const Duration(seconds: 4), content: Text('Choose a valid Sub-task PIC'),
              backgroundColor: Colors.orange,
            ),
          );
          return false;
        }
        setState(() => _saving = true);
        try {
          final err = await SupabaseService.updateSubtaskRow(
            subtaskId: st.id,
            picStaffLookupKey: key,
            bumpSubtaskRowAuditFields: false,
          );
          if (!mounted) return false;
          if (err != null) {
            showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
            return false;
          }
          final errA = await SupabaseService.replaceSubtaskAttachments(
            subtaskId: st.id,
            taskId: st.taskId,
            rows: _subtaskAttachmentPayload(),
          );
          if (!mounted) return false;
          if (errA != null) {
            showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
            return false;
          }
          if (!mounted) return false;
          await _load(rebindAttachments: false);
          if (!suppressSuccessSnack && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return true;
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      }
      if (_isPic(state, st)) {
        if (!_subtaskAttachmentsDirty()) {
          if (!willSaveCommentAfter) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(duration: const Duration(seconds: 4), content: Text('Nothing is updated')),
            );
          }
          return false;
        }
        setState(() => _saving = true);
        try {
          final errA = await SupabaseService.replaceSubtaskAttachments(
            subtaskId: st.id,
            taskId: st.taskId,
            rows: _subtaskAttachmentPayload(),
          );
          if (!mounted) return false;
          if (errA != null) {
            showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
            return false;
          }
          await _load(rebindAttachments: false);
          if (!suppressSuccessSnack && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return true;
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      }
      if (_isAssignee(state, st) && !_isPic(state, st)) {
        if (!_subtaskAttachmentsDirty()) {
          if (!willSaveCommentAfter) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(duration: const Duration(seconds: 4), content: Text('Nothing is updated')),
            );
          }
          return false;
        }
        setState(() => _saving = true);
        try {
          final errA = await SupabaseService.replaceSubtaskAttachments(
            subtaskId: st.id,
            taskId: st.taskId,
            rows: _subtaskAttachmentPayload(),
          );
          if (!mounted) return false;
          if (errA != null) {
            showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
            return false;
          }
          await _load(rebindAttachments: false);
          if (!suppressSuccessSnack && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return true;
        } finally {
          if (mounted) setState(() => _saving = false);
        }
      }
      if (canPic && multiTaskAssignees && !picDirty) {
        if (_canEditSubtaskAttachments(state, st) && _subtaskAttachmentsDirty()) {
          setState(() => _saving = true);
          try {
            final errA = await SupabaseService.replaceSubtaskAttachments(
              subtaskId: st.id,
              taskId: st.taskId,
              rows: _subtaskAttachmentPayload(),
            );
            if (!mounted) return false;
            if (errA != null) {
              showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
              return false;
            }
            await _load(rebindAttachments: false);
            if (!mounted) return false;
            if (!suppressSuccessSnack && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            return true;
          } finally {
            if (mounted) setState(() => _saving = false);
          }
        }
        if (!willSaveCommentAfter) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(duration: const Duration(seconds: 4), content: Text('Nothing is updated'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
      return false;
    }
    if (!_subtaskCreatorHasMetadataOrAttachmentChanges(state, st, parent)) {
      if (!willSaveCommentAfter) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text('Nothing is updated')),
        );
      }
      return false;
    }
    final picKey =
        picDirty && _picEditKey != null && parent.assigneeIds.contains(_picEditKey!)
        ? _picEditKey
        : null;
    setState(() => _saving = true);
    try {
      final errA = await SupabaseService.replaceSubtaskAttachments(
        subtaskId: st.id,
        taskId: st.taskId,
        rows: _subtaskAttachmentPayload(),
      );
      if (!mounted) return false;
      if (errA != null) {
        showCopyableSnackBar(context, errA, backgroundColor: Colors.orange);
        return false;
      }
      if (_editStart != null &&
          _editDue != null &&
          DateTime(_editDue!.year, _editDue!.month, _editDue!.day).isBefore(
            DateTime(
              _editStart!.year,
              _editStart!.month,
              _editStart!.day,
            ),
          )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(duration: const Duration(seconds: 4), content: Text('Due date cannot be before start date'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
      final needsDueReason = _needsChangeDueReason();
      if (needsDueReason && _changeDueReasonController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(duration: const Duration(seconds: 4), content: Text(
                'Enter a reason when the due date is beyond the allowed working days for this priority',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        subtaskName: _nameController.text.trim(),
        description: _descController.text.trim(),
        priorityDisplay: priorityToDisplayName(_editPriority),
        startDate: _editStart,
        clearStartDate: _editStart == null,
        dueDate: _editDue,
        clearDueDate: _editDue == null,
        picStaffLookupKey: picKey,
        updaterStaffLookupKey: state.userStaffAppId,
        updateChangeDueReason: true,
        changeDueReason:
            needsDueReason ? _changeDueReasonController.text.trim() : null,
      );
      if (!mounted) return false;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return false;
      }
      if (!mounted) return false;
      await _load(rebindAttachments: false);
      if (!suppressSuccessSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit(AppState state, SingularSubtask st) async {
    final link = _firstSubtaskAttachmentUrl()?.trim() ?? '';
    final c = _commentController.text.trim();
    if (link.isEmpty && c.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text(
            'Add attachment and/or comment before submitting',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final e = await SupabaseService.replaceSubtaskAttachments(
        subtaskId: st.id,
        taskId: st.taskId,
        rows: _subtaskAttachmentPayload(),
      );
      if (e != null && mounted) {
        showCopyableSnackBar(context, e, backgroundColor: Colors.orange);
        return;
      }
      if (c.isNotEmpty) {
        final ins = await SupabaseService.insertSubtaskCommentRow(
          subtaskId: st.id,
          description: c,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (ins.error != null && mounted) {
          showCopyableSnackBar(context, ins.error!, backgroundColor: Colors.orange);
          return;
        }
        final cid = ins.commentId?.trim();
        if (cid != null && cid.isNotEmpty && !_isCreator(state, st)) {
          await _notifySubtaskCommentCreatorEmail(cid);
        }
      }
      final subCreator = _isCreator(state, st);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        submission: 'Submitted',
        updaterStaffLookupKey:
            subCreator ? state.userStaffAppId : null,
        stampSubmitDateNow: true,
        bumpSubtaskRowAuditFields: subCreator,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifySubtaskSubmission(
            idToken: token,
            subtaskId: st.id,
          );
          if (ne != null && mounted) {
            final short = ne.length > 120 ? '${ne.substring(0, 120)}…' : ne;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Submitted; email: $short'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (_) {}
      _commentController.clear();
      await _load(rebindAttachments: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: const Text('Submitted'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _canCreatorMarkSubtaskComplete(SingularSubtask st) {
    if (st.isDeleted) return false;
    if (st.status.trim().toLowerCase() == 'completed') return false;
    if (st.submission?.trim().toLowerCase() == 'submitted') {
      return false;
    }
    return true;
  }

  /// Creator-only: set sub-task to Completed + submission Accepted (same as **Accept**).
  Future<void> _markSubtaskCompletedByCreator(
    AppState state,
    SingularSubtask st,
  ) async {
    await _accept(
      state,
      st,
      successMessage: 'Sub-task is completed',
    );
  }

  bool _canUndoAcceptOrReturnSubtask(SingularSubtask st) {
    if (st.isDeleted) return false;
    final s = st.submission?.trim().toLowerCase() ?? '';
    return s == 'accepted' || s == 'returned';
  }

  /// After **Accept** / **Return** / **Mark as Completed**: reset to Incomplete + Pending.
  Future<void> _undoAcceptOrReturn(AppState state, SingularSubtask st) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final subCreator = _isCreator(state, st);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        status: 'Incomplete',
        submission: 'Pending',
        updaterStaffLookupKey:
            subCreator ? state.userStaffAppId : null,
        clearCompletionDate: true,
        bumpSubtaskRowAuditFields: subCreator,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      SupabaseService.invalidateSubtasksCacheForTask(st.taskId);
      await _load(rebindAttachments: false);
      if (mounted) {
        final hook = widget.onParentTaskListRefresh;
        if (hook != null) await hook();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 4),
          content: Text('Submission reset to Pending'),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _accept(
    AppState state,
    SingularSubtask st, {
    String successMessage = 'Accepted',
  }) async {
    setState(() => _saving = true);
    try {
      final completedAt = st.submitDate ?? DateTime.now().toUtc();
      final subCreator = _isCreator(state, st);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        status: 'Completed',
        submission: 'Accepted',
        updaterStaffLookupKey:
            subCreator ? state.userStaffAppId : null,
        completionDateAt: completedAt,
        bumpSubtaskRowAuditFields: subCreator,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifySubtaskAccepted(
            idToken: token,
            subtaskId: st.id,
          );
          if (ne != null && mounted) {
            final short = ne.length > 120 ? '${ne.substring(0, 120)}…' : ne;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Accept email: $short'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (_) {}
      SupabaseService.invalidateSubtasksCacheForTask(st.taskId);
      await _load(rebindAttachments: false);
      if (mounted) {
        final hook = widget.onParentTaskListRefresh;
        if (hook != null) await hook();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text(successMessage),
          backgroundColor: Colors.green,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _return(AppState state, SingularSubtask st) async {
    setState(() => _saving = true);
    try {
      final subCreator = _isCreator(state, st);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        status: 'Incomplete',
        submission: 'Returned',
        updaterStaffLookupKey:
            subCreator ? state.userStaffAppId : null,
        clearCompletionDate: true,
        bumpSubtaskRowAuditFields: subCreator,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifySubtaskReturned(
            idToken: token,
            subtaskId: st.id,
          );
          if (ne != null && mounted) {
            final short = ne.length > 120 ? '${ne.substring(0, 120)}…' : ne;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Return email: $short'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (_) {}
      SupabaseService.invalidateSubtasksCacheForTask(st.taskId);
      await _load(rebindAttachments: false);
      if (mounted) {
        final hook = widget.onParentTaskListRefresh;
        if (hook != null) await hook();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text('Returned'), backgroundColor: Colors.green),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _startEditComment(SubtaskCommentRowDisplay c) {
    setState(() {
      _editingCommentId = c.id;
      _editCommentController.text = c.description;
    });
  }

  void _cancelCommentEdit() {
    setState(() {
      _editingCommentId = null;
      _editCommentController.clear();
    });
  }

  Future<void> _saveCommentEdit(
    AppState state,
    SingularSubtask st,
    SubtaskCommentRowDisplay c,
  ) async {
    final text = _editCommentController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: const Text('Comment cannot be empty'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!_isCommentAuthor(c)) return;
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.updateSubtaskCommentRow(
        commentId: c.id,
        description: text,
        updaterStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      _cancelCommentEdit();
      await _load(rebindAttachments: false);
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final notifyErr = await BackendApi().notifySubtaskCommentEdited(
            idToken: token,
            commentId: c.id,
          );
          if (notifyErr != null && mounted) {
            showCopyableSnackBar(
              context,
              'Sub-task comment edit email: $notifyErr',
              backgroundColor: Colors.orange,
            );
          }
        } else if (mounted) {
          showCopyableSnackBar(
            context,
            'Comment updated; notify email skipped (no sign-in token)',
            backgroundColor: Colors.orange,
          );
        }
      } catch (e) {
        if (mounted) {
          showCopyableSnackBar(
            context,
            'Sub-task comment edit email failed: $e',
            backgroundColor: Colors.orange,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteComment(
    AppState state,
    SingularSubtask st,
    SubtaskCommentRowDisplay c,
  ) async {
    if (!_isCreator(state, st)) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
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
    if (go != true || !mounted) return;
    final err = await SupabaseService.softDeleteSubtaskCommentRow(
      commentId: c.id,
      updaterStaffLookupKey: state.userStaffAppId,
    );
    if (!mounted) return;
    if (err != null) {
      showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
      return;
    }
    await _load(rebindAttachments: false);
  }

  /// Calls [BackendApi.notifySubtaskUpdated]. The API sends mail only when the sub-task **creator**
  /// (`create_by`) is the row updater; callers should invoke this from the creator **Update** path only.
  Future<void> _notifySubtaskUpdatedEmail(
    String subtaskId, {
    List<Map<String, String>>? changes,
    String? commentAddedText,
    String? subtaskCommentId,
  }) async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final err = await BackendApi().notifySubtaskUpdated(
        idToken: token,
        subtaskId: subtaskId,
        changes: changes,
        commentAddedText: commentAddedText,
        subtaskCommentId: subtaskCommentId,
      );
      if (err != null && mounted) {
        if (err == BackendApi.notifySubtaskUpdatedBackendNotDeployed) {
          showCopyableSnackBar(
            context,
            'Sub-task was saved. Notification email was not sent: the live API '
            'does not include POST /api/notify/subtask-updated yet. Redeploy the '
            'Project Tracker backend on Railway from the current repository '
            '(backend/server.js)',
            backgroundColor: Colors.blueGrey.shade700,
            duration: const Duration(seconds: 4),
          );
          return;
        }
        final short =
            err.length > 120 ? '${err.substring(0, 120)}…' : err;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sub-task update email: $short'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {}
  }

  Widget _buildCommentTile(
    BuildContext context,
    AppState state,
    SingularSubtask st,
    SubtaskCommentRowDisplay c,
  ) {
    final subtaskCreator = _isCreator(state, st);
    if (_editingCommentId == c.id) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _editCommentController,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: 12,
              minLines: 3,
              textAlignVertical: TextAlignVertical.top,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: 'Comment',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : _cancelCommentEdit,
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _saving
                      ? null
                      : () => _saveCommentEdit(state, st, c),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final isDeleted = c.isDeleted;
    final grey = Colors.grey.shade600;
    final showEdit = !isDeleted && _isCommentAuthor(c) && !_saving;
    final showDelete = !isDeleted && subtaskCreator && !_saving;
    final subtitleChildren = <Widget>[
      Text(
        '${c.displayStaffName} · ${_formatSubtaskCommentPostedTs(c.createTimestampUtc)}',
        style: theme.textTheme.bodySmall,
      ),
    ];
    if (c.updateTimestampUtc != null) {
      subtitleChildren.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _formatSubtaskCommentLastUpdatedLine(c.updateTimestampUtc),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isDeleted ? Colors.grey.shade100 : null,
      child: ListTile(
        isThreeLine: c.updateTimestampUtc != null,
        title: SelectableText(
          c.description,
          style: isDeleted
              ? theme.textTheme.bodyLarge?.copyWith(color: grey)
              : theme.textTheme.bodyLarge,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: subtitleChildren,
        ),
        trailing: (showEdit || showDelete)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showEdit)
                    IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit_outlined, size: 22),
                      onPressed: () => _startEditComment(c),
                    ),
                  if (showDelete)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 22),
                      onPressed: () => _deleteComment(state, st, c),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  Future<void> _deleteSubtask(AppState state, SingularSubtask st) async {
    if (!_isCreator(state, st) && !_director) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm to delete sub-task'),
        content: Text('“${st.subtaskName}” will be deleted.'),
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
    if (go != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final subCreator = _isCreator(state, st);
      final err = await SupabaseService.markSubtaskDeleted(
        subtaskId: st.id,
        updaterStaffLookupKey:
            subCreator ? state.userStaffAppId : null,
        bumpSubtaskRowAuditFields: subCreator,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      SupabaseService.invalidateSubtasksCacheForTask(st.taskId);
      await _load(rebindAttachments: false);
      if (!mounted) return;
      final hook = widget.onParentTaskListRefresh;
      if (hook != null) await hook();
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        'Sub-task marked as deleted',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _undoSubtaskDeleted(AppState state, SingularSubtask st) async {
    if (!_isCreator(state, st) && !_director) return;
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final subCreator = _isCreator(state, st);
      final err = await SupabaseService.updateSubtaskRow(
        subtaskId: st.id,
        status: 'Incomplete',
        updaterStaffLookupKey:
            subCreator ? state.userStaffAppId : null,
        bumpSubtaskRowAuditFields: subCreator,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      SupabaseService.invalidateSubtasksCacheForTask(st.taskId);
      await _load(rebindAttachments: false);
      if (!mounted) return;
      final hook = widget.onParentTaskListRefresh;
      if (hook != null) await hook();
      if (!mounted) return;
      showCopyableSnackBar(
        context,
        'Sub-task restored to Incomplete',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sub-task')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final st = _sub;
    final parent = _parentTask;
    if (st == null || parent == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sub-task')),
        body: const Center(child: Text('Sub-task not found')),
      );
    }

    final creator = _isCreator(state, st);
    final pic = _isPic(state, st);
    final assignee = _isAssignee(state, st);
    final canDel = creator || _director;
    final canSetPic = _canEditSubtaskPic(state, st, parent);
    final multiTaskAssignees = parent.assigneeIds.length > 1;
    final showPicDropdown =
        canSetPic && multiTaskAssignees && !st.isDeleted;
    final ymd = DateFormat('yyyy-MM-dd');
    final picDropdownValue =
        _picEditKey != null && parent.assigneeIds.contains(_picEditKey)
        ? _picEditKey
        : null;
    final hasLinkedProject =
        parent.projectId != null && parent.projectId!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Sub-task: ${st.subtaskName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving
              ? null
              : () {
                  if (kIsWeb) {
                    webHistoryBack();
                  } else {
                    Navigator.of(context).pop(true);
                  }
                },
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + kFlowNavBarScrollBottomPadding,
            ),
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Project: ${parent.projectName?.trim().isNotEmpty == true ? parent.projectName!.trim() : '—'}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Parent: ${parent.name}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sub-task creator: ${_subtaskCreatorLabel(st)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sub-task assignee(s): ${st.assigneeNamesDisplayLine(
                            (id) => state.assigneeById(id)?.name ?? id,
                          )}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'PIC: ${st.picDisplayName(
                            (id) => state.assigneeById(id)?.name ?? id,
                          )}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (showPicDropdown) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: picDropdownValue,
                            decoration: const InputDecoration(
                              labelText: 'Sub-task PIC',
                              border: OutlineInputBorder(),
                            ),
                            items: parent.assigneeIds
                                .map(
                                  (id) => DropdownMenuItem(
                                    value: id,
                                    child: Text(
                                      state.assigneeById(id)?.name ?? id,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: _saving
                                ? null
                                : (v) {
                                    if (v != null) {
                                      setState(() => _picEditKey = v);
                                    }
                                  },
                          ),
                        ],
                        if (canSetPic && parent.assigneeIds.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Add assignees on the parent task to choose a PIC.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (creator)
                          TextField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            readOnly: _saving || st.isDeleted,
                            enableInteractiveSelection: true,
                            decoration: const InputDecoration(
                              labelText: 'Sub-task name',
                              border: OutlineInputBorder(),
                            ),
                          )
                        else
                          TextField(
                            controller: _nameController,
                            textInputAction: TextInputAction.next,
                            readOnly: true,
                            enableInteractiveSelection: assignee,
                            decoration: const InputDecoration(
                              labelText: 'Sub-task name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (creator)
                          TextField(
                            controller: _descController,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            readOnly: _saving || st.isDeleted,
                            enableInteractiveSelection: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            minLines: 3,
                            maxLines: 12,
                          )
                        else
                          TextField(
                            controller: _descController,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            readOnly: true,
                            enableInteractiveSelection: assignee,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            minLines: 3,
                            maxLines: 12,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          'Priority',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _priorityToggleButton(
                              label: 'Standard',
                              selected: creator
                                  ? (_editPriority == priorityStandard)
                                  : (st.priority == priorityStandard),
                              enabled: creator && !_saving && !st.isDeleted,
                              onTap: () => setState(
                                () => _editPriority = priorityStandard,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _priorityToggleButton(
                              label: 'URGENT',
                              selected: creator
                                  ? (_editPriority == priorityUrgent)
                                  : (st.priority == priorityUrgent),
                              enabled: creator && !_saving && !st.isDeleted,
                              onTap: () => setState(
                                () => _editPriority = priorityUrgent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (creator && !st.isDeleted) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Start: ${_editStart != null ? ymd.format(_editStart!) : "—"}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _editStart ?? DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365 * 10),
                                          ),
                                        );
                                        if (d != null) {
                                          setState(() => _editStart = d);
                                        }
                                      },
                                child: const Text('Pick'),
                              ),
                              if (_editStart != null)
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _editStart = null),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Due: ${_editDue != null ? ymd.format(_editDue!) : "—"}',
                                ),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final start = _editStart;
                                        final d = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _editDue ?? DateTime.now(),
                                          firstDate: start ?? DateTime(2020),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365 * 10),
                                          ),
                                        );
                                        if (d != null) {
                                          setState(() => _editDue = d);
                                        }
                                      },
                                child: const Text('Pick'),
                              ),
                              if (_editDue != null)
                                TextButton(
                                  onPressed: _saving
                                      ? null
                                      : () => setState(() => _editDue = null),
                                  child: const Text('Clear'),
                                ),
                            ],
                          ),
                          if (_needsChangeDueReason()) ...[
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _changeDueReasonController,
                              readOnly: _saving,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Reason',
                                hintText: 'Extend timeline reason',
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                              maxLines: 3,
                            ),
                          ],
                        ] else ...[
                          if (st.startDate != null)
                            Text('Start: ${ymd.format(st.startDate!)}'),
                          if (st.dueDate != null)
                            Text('Due: ${ymd.format(st.dueDate!)}'),
                          if ((st.changeDueReason ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Reason: ${st.changeDueReason}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                        ],
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'Status',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sub-task status: ${st.status}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Submission: ${st.submission?.trim().isNotEmpty == true ? st.submission!.trim() : '—'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (st.submitDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Submission date: ${HkTime.formatInstantAsHk(st.submitDate!, 'yyyy-MM-dd')}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        if (st.completionDate != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Completion date: ${HkTime.formatInstantAsHk(st.completionDate!, 'yyyy-MM-dd')}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Last update by: ${st.updateByStaffName ?? '—'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _subtaskLastUpdatedLine(st.updateDate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Attachment',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (_canEditSubtaskAttachments(state, st))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add_link_outlined),
                      label: const Text('Add attachment'),
                      onPressed: _saving
                          ? null
                          : () {
                              showAttachmentSourceBottomSheet(
                                context: context,
                                onPickFromDevice: () {
                                  if (!mounted) return;
                                  _addSubtaskAttachmentFromDevice();
                                },
                                onPickFromLink: () {
                                  if (!mounted) return;
                                  _addSubtaskAttachmentFromLink();
                                },
                              );
                            },
                    ),
                  ),
                const SizedBox(height: 8),
                ...List.generate(_subtaskAttachments.length, (i) {
                  final e = _subtaskAttachments[i];
                  final canEdit = _canEditSubtaskAttachments(state, st);
                  final hasLink = e.urlController.text.trim().isNotEmpty;
                  final chipLabel = attachmentChipLabel(
                    e.descController.text,
                    e.urlController.text,
                  );
                  if (hasLink) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlookAttachmentChip(
                                label: chipLabel,
                                url: e.urlController.text.trim(),
                              ),
                            ),
                          ),
                          if (canEdit) ...[
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _editSubtaskAttachment(i),
                              child: const Text('Edit'),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => _removeSubtaskAttachmentRow(i),
                              child: const Text('Remove'),
                            ),
                          ],
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  canEdit
                                      ? TextField(
                                          controller: e.descController,
                                          textInputAction: TextInputAction.next,
                                          readOnly: _saving,
                                          enableInteractiveSelection: true,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Attachment description',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        )
                                      : InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Attachment description',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          child: SelectableText(
                                            e.descController.text.isEmpty
                                                ? '—'
                                                : e.descController.text,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ),
                                  const SizedBox(height: 8),
                                  if (canEdit)
                                    TextField(
                                      controller: e.urlController,
                                      textInputAction: TextInputAction.next,
                                      readOnly: _saving,
                                      enableInteractiveSelection: true,
                                      decoration: InputDecoration(
                                        labelText: 'Attachment link',
                                        hintText: 'https://…',
                                        border: const OutlineInputBorder(),
                                        isDense: true,
                                        suffixIcon: IconButton(
                                          icon: const Icon(
                                            Icons.open_in_new_outlined,
                                            size: 20,
                                          ),
                                          tooltip: 'Open link',
                                          onPressed: () {
                                            final u =
                                                e.urlController.text.trim();
                                            if (u.isEmpty) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(duration: const Duration(seconds: 4), content: Text(
                                                    'Enter a link first',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }
                                            openAttachmentUrl(
                                              context,
                                              u,
                                              displayFileName:
                                                  attachmentDisplayNameHint(
                                                e.descController.text,
                                                u,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      'No attachment link yet.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (canEdit)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _editSubtaskAttachment(i),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => _removeSubtaskAttachmentRow(i),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Text(
                  'Comments',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _commentController,
                  readOnly: _saving ||
                      st.isDeleted ||
                      !(assignee || creator),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  enableInteractiveSelection: true,
                  textAlignVertical: TextAlignVertical.top,
                  minLines: 3,
                  maxLines: 12,
                  decoration: InputDecoration(
                    hintText: (assignee || creator)
                        ? 'Comments'
                        : 'Only sub-task creator and sub-task assignees can add comments',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.all(12),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                ..._comments.map(
                  (c) => _buildCommentTile(context, state, st, c),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ||
                          st.isDeleted ||
                          (!creator &&
                              !assignee &&
                              !(canSetPic && multiTaskAssignees))
                      ? null
                      : () async {
                          final pendingCommentSnap =
                              _commentController.text.trim();
                          final hadComment = (assignee || creator) &&
                              pendingCommentSnap.isNotEmpty;
                          final changesForEmail = _buildSubtaskUpdateNotifyChanges(
                            st: st,
                            state: state,
                            newName: _nameController.text.trim(),
                            newDesc: _descController.text.trim(),
                            newPriority: _editPriority,
                            newStart: _editStart,
                            newDue: _editDue,
                          );
                          final metaOk = await _saveMetadata(
                            state,
                            st,
                            suppressSuccessSnack: true,
                            willSaveCommentAfter: hadComment,
                          );
                          var commentPost = (ok: false, commentId: null as String?);
                          if (hadComment) {
                            commentPost = await _postComment(
                              state,
                              st,
                              suppressSuccessSnack: true,
                            );
                          }
                          if (!mounted) return;
                          if (metaOk || commentPost.ok) {
                            // Row `update_by` / `update_date` are set only inside creator `_saveMetadata`
                            // → `updateSubtaskRow` (not for comment-only saves; each comment has its own time).
                            if (creator && (metaOk || commentPost.ok)) {
                              await _notifySubtaskUpdatedEmail(
                                st.id,
                                changes: metaOk ? changesForEmail : const [],
                                commentAddedText: commentPost.ok
                                    ? pendingCommentSnap
                                    : null,
                                subtaskCommentId: commentPost.commentId,
                              );
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(duration: const Duration(seconds: 4), content: Text('Sub-task is updated'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                  child: Text(_saving ? 'Saving…' : 'Update'),
                ),
                if (creator &&
                    !st.isDeleted &&
                    _canCreatorMarkSubtaskComplete(st)) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () => _markSubtaskCompletedByCreator(state, st),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF298A00),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Mark as Completed'),
                  ),
                ],
                if (creator && _canUndoAcceptOrReturnSubtask(st)) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => _undoAcceptOrReturn(state, st),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Undo'),
                  ),
                ],
                if (pic && !st.isDeleted && _canPicSubmit(st)) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _saving ? null : () => _submit(state, st),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSecondaryContainer,
                    ),
                    child: const Text('Submit'),
                  ),
                ],
                if (creator &&
                    !st.isDeleted &&
                    (st.submission?.trim().toLowerCase() == 'submitted')) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _accept(state, st),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF298A00),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Accept'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _return(state, st),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0B0094),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Return'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (canDel) ...[
                  const SizedBox(height: 12),
                  if (st.isDeleted)
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _undoSubtaskDeleted(state, st),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Undo'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _deleteSubtask(state, st),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ],
            ),
            ),
          ),
          if (_saving)
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  color: Colors.black.withOpacity(0.1),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: FlowBottomNavFour(
        onBack: _subtaskBarBack,
        mid1Label: 'Task',
        mid1Icon: const Icon(Icons.assignment_outlined, size: 18),
        onMid1: _barOpenParentTask,
        mid2Label: hasLinkedProject ? 'Project' : null,
        mid2Icon: hasLinkedProject
            ? const Icon(Icons.folder_outlined, size: 18)
            : null,
        onMid2: hasLinkedProject ? _barOpenProject : null,
        onHome: _subtaskFlowHome,
        enabled: !_saving,
      ),
    );
  }

  void _subtaskFlowBack() {
    if (_saving) return;
    _onBackToTask();
  }

  void _subtaskBarBack() {
    if (_saving) return;
    if (kIsWeb) {
      webHistoryBack();
    } else {
      _subtaskFlowBack();
    }
  }

  void _barOpenProject() {
    if (_saving) return;
    final pid = _parentTask?.projectId?.trim();
    if (pid == null || pid.isEmpty) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          'No project linked to this task.',
          backgroundColor: Colors.orange,
        );
      }
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ProjectDetailScreen(
          projectId: pid,
          openedFromLanding: false,
          openedFromOverview: widget.openedFromOverview,
        ),
      ),
    );
  }

  void _barOpenParentTask() {
    if (_saving) return;
    final tid = _parentTask?.id ?? _sub?.taskId;
    if (tid == null || tid.isEmpty) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Parent task is not available.',
          backgroundColor: Colors.orange,
        );
      }
      return;
    }
    final p = _parentTask;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TaskDetailScreen(
          taskId: tid,
          openedFromOverview: widget.openedFromOverview,
          openedFromProjectDetail: widget.openedFromProjectDetail,
          openedFromProjectDashboard: widget.openedFromProjectDashboard,
          projectIdForBack: p?.projectId,
        ),
      ),
    );
  }

  Future<void> _subtaskFlowHome() async {
    if (_saving) return;
    await navigateToPinnedHomeFromDrawer(context);
  }
}
