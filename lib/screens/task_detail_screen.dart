import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../config/supabase_config.dart';
import '../models/assignee.dart';
import '../models/task.dart';
import '../models/comment.dart';
import '../models/singular_comment.dart';
import '../models/singular_subtask.dart';
import 'high_level/create_subtask_screen.dart';
import 'high_level/subtask_detail_screen.dart';
import '../models/staff_for_assignment.dart';
import '../models/team.dart';
import '../priority.dart';
import '../services/backend_api.dart';
import '../services/firebase_attachment_upload_service.dart';
import '../services/supabase_service.dart';
import '../utils/attachment_save_reminder_snackbar.dart';
import '../utils/attachment_url_launch.dart';
import '../utils/copyable_snackbar.dart';
import '../utils/due_span_policy.dart';
import '../utils/hk_time.dart';
import '../utils/subtask_list_sort.dart';
import '../web_deep_link.dart';
import '../widgets/attachment_add_link_dialog.dart';
import '../widgets/attachment_edit_dialog.dart';
import '../widgets/attachment_source_bottom_sheet.dart';
import '../widgets/outlook_attachment_chip.dart';
import '../widgets/singular_subtask_row_card.dart';
import '../widgets/staff_assignee_picker_panel.dart';
import '../widgets/subtask_meta_line.dart';
import '../widgets/subtask_sort_column_chip.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  final String? commentAuthorAssigneeId;

  const TaskDetailScreen({
    super.key,
    required this.taskId,
    this.commentAuthorAssigneeId,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      syncWebLocationForTaskDetail(widget.taskId);
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      clearWebTaskDetailFromLocation();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final task = state.taskById(widget.taskId);
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('Task not found')),
      );
    }
    if (task.isSingularTableRow) {
      return SingularTaskDetailView(
        taskId: widget.taskId,
        commentAuthorAssigneeId: widget.commentAuthorAssigneeId,
      );
    }
    return _LegacyTaskDetailView(
      taskId: widget.taskId,
      commentAuthorAssigneeId: widget.commentAuthorAssigneeId,
    );
  }
}

class _TaskAttachmentEntry {
  _TaskAttachmentEntry({this.id, String? url, String? desc})
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

/// Supabase singular [`task`] row: editable fields, status actions, comments, Update.
class SingularTaskDetailView extends StatefulWidget {
  final String taskId;
  final String? commentAuthorAssigneeId;

  const SingularTaskDetailView({
    super.key,
    required this.taskId,
    this.commentAuthorAssigneeId,
  });

  @override
  State<SingularTaskDetailView> createState() => _SingularTaskDetailViewState();
}

class _SingularTaskDetailViewState extends State<SingularTaskDetailView> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentController = TextEditingController();
  final _changeDueReasonController = TextEditingController();
  final FocusNode _changeDueReasonFocusNode = FocusNode();
  final List<_TaskAttachmentEntry> _taskAttachments = [];

  /// Normalized attachment rows after load/reload — for “nothing changed” detection.
  List<({String c, String d})> _taskAttachmentBaseline = [];

  DateTime? _startDate;
  DateTime? _dueDate;
  int _localPriority = 1;
  String _localStatus = 'Incomplete';
  final Set<String> _selectedTeamIds = {};
  final Set<String> _selectedAssigneeIds = {};
  String? _picAssigneeId;
  List<TeamOptionRow> _pickerTeams = [];
  List<StaffForAssignment> _pickerStaff = [];
  final Map<String, String> _staffAssigneeToTeamId = {};
  bool _pickerLoading = false;
  String? _pickerError;
  bool _loadingStaff = true;
  bool _loadedForm = false;
  bool _saving = false;
  List<SingularCommentRowDisplay> _tableComments = [];
  bool _loadingTableComments = false;
  List<SingularSubtask> _subtasks = [];
  bool _loadingSubtasks = false;

  /// `null` = default: [SingularSubtask.createDate] descending (same as landing [TaskListCard]).
  SubtaskListSortColumn? _subtaskSortColumn;
  bool _subtaskSortAscending = true;

  String? _myStaffUuid;
  bool _myStaffUuidRequested = false;

  /// `task.create_by` (usually `staff.id` uuid); used with [_myStaffUuid] for delete rules.
  String? _taskCreateByStaffUuid;
  /// Raw `task.pic` from Supabase (`staff.id` uuid). Used so PIC checks work when [Task.pic] is `app_id`.
  String? _singularTaskPicStaffUuid;
  /// Resolved by comparing DB `task.pic` to [SupabaseService.staffRowIdForAssigneeKey] for the signed-in user.
  /// Null means user context was not ready yet — [_isPic] is used as fallback.
  bool? _resolvedIsPic;
  AppState? _appStateRef;
  bool _appListenerRegistered = false;
  bool _staffDirectorFlag = false;

  static const int _maxAssignees = 10;
  static const Color _selGreen = Color(0xFF1B5E20);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!_appListenerRegistered) {
      _appListenerRegistered = true;
      _appStateRef = app;
      app.addListener(_onAppStateChangedForPic);
    }
    if (_myStaffUuidRequested) return;
    final lk = context.read<AppState>().userStaffAppId?.trim();
    if (lk == null || lk.isEmpty) return;
    _myStaffUuidRequested = true;
    SupabaseService.staffRowIdForAssigneeKey(lk).then((id) async {
      if (!mounted) return;
      setState(() => _myStaffUuid = id);
      final a = _appStateRef;
      if (a != null) await _refreshResolvedPic(a);
      if (id == null || id.isEmpty) return;
      final dir = await SupabaseService.fetchStaffDirectorByStaffUuid(id);
      if (mounted) setState(() => _staffDirectorFlag = dir);
    });
  }

  void _onAppStateChangedForPic() {
    final a = _appStateRef;
    if (a == null || !mounted) return;
    final lk = a.userStaffAppId?.trim();
    if (lk != null && lk.isNotEmpty && !_myStaffUuidRequested) {
      _myStaffUuidRequested = true;
      SupabaseService.staffRowIdForAssigneeKey(lk).then((id) async {
        if (!mounted) return;
        setState(() => _myStaffUuid = id);
        await _refreshResolvedPic(a);
        if (id == null || id.isEmpty) return;
        final dir = await SupabaseService.fetchStaffDirectorByStaffUuid(id);
        if (mounted) setState(() => _staffDirectorFlag = dir);
      });
    }
    _refreshResolvedPic(a);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = context.read<AppState>();
      await _ensureLoaded(state);
      if (mounted) await _refreshResolvedPic(state);
      if (mounted) await _loadTableComments();
      if (mounted) await _loadSubtasks();
    });
  }

  @override
  void didUpdateWidget(covariant SingularTaskDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId) {
      _subtaskSortColumn = null;
      _subtaskSortAscending = true;
    }
  }

  void _onSubtaskSortMenu(SubtaskListSortColumn column, String v) {
    setState(() {
      if (v == 'clear') {
        if (_subtaskSortColumn == column) {
          _subtaskSortColumn = null;
          _subtaskSortAscending = true;
        }
      } else if (v == 'asc') {
        _subtaskSortColumn = column;
        _subtaskSortAscending = true;
      } else if (v == 'desc') {
        _subtaskSortColumn = column;
        _subtaskSortAscending = false;
      }
    });
  }

  Future<void> _loadSubtasks() async {
    if (!SupabaseConfig.isConfigured) {
      if (mounted) setState(() => _subtasks = []);
      return;
    }
    setState(() => _loadingSubtasks = true);
    final list = await SupabaseService.fetchSubtasksForTask(widget.taskId);
    if (!mounted) return;
    setState(() {
      _subtasks = list;
      _loadingSubtasks = false;
    });
  }

  Future<void> _loadTableComments() async {
    if (!SupabaseConfig.isConfigured) {
      if (mounted) setState(() => _tableComments = []);
      return;
    }
    setState(() => _loadingTableComments = true);
    final list = await SupabaseService.fetchSingularCommentsForTask(
      widget.taskId,
    );
    if (!mounted) return;
    setState(() {
      _tableComments = list;
      _loadingTableComments = false;
    });
  }

  /// Posted time on singular task comments (`yyyy-MM-dd HH:mm`, HK UTC+8, 24h).
  String _formatCommentPostedTs(DateTime? stored) {
    if (stored == null) return '—';
    return HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm');
  }

  /// Display line: `Last updated: yyyy-MM-dd HH:mm` (HK wall clock, UTC+8, 24h).
  String _formatCommentLastUpdatedLine(DateTime? stored) {
    if (stored == null) return 'Last updated: —';
    return 'Last updated: ${HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm')}';
  }

  bool _isOwnSingularComment(SingularCommentRowDisplay c) {
    final mine = _myStaffUuid?.trim();
    final cb = c.createByStaffId?.trim();
    if (mine == null || mine.isEmpty || cb == null || cb.isEmpty) {
      return false;
    }
    return mine == cb;
  }

  static bool _uuidEquals(String? a, String? b) {
    final x = a?.trim().toLowerCase() ?? '';
    final y = b?.trim().toLowerCase() ?? '';
    if (x.isEmpty || y.isEmpty) return false;
    return x == y;
  }

  /// [Task.pic] is usually `staff.app_id`; if the staff map missed the row it stays the raw uuid.
  /// [_singularTaskPicStaffUuid] is always the DB `task.pic` uuid when the row was loaded.
  bool _isPic(AppState state, Task task) {
    final mineApp = state.userStaffAppId?.trim();
    final p = task.pic?.trim();
    if (mineApp != null &&
        mineApp.isNotEmpty &&
        p != null &&
        p.isNotEmpty &&
        mineApp == p) {
      return true;
    }
    final picUuid = _singularTaskPicStaffUuid?.trim();
    final uuidCandidates = <String?>[
      picUuid,
      p,
    ];
    for (final u in uuidCandidates) {
      if (u == null || u.isEmpty) continue;
      final mineUuid = state.userStaffId?.trim();
      if (mineUuid != null &&
          mineUuid.isNotEmpty &&
          _uuidEquals(mineUuid, u)) {
        return true;
      }
      final asyncUuid = _myStaffUuid?.trim();
      if (asyncUuid != null &&
          asyncUuid.isNotEmpty &&
          _uuidEquals(asyncUuid, u)) {
        return true;
      }
    }
    return false;
  }

  /// True if the current user is the task PIC. [_resolvedIsPic] can be false
  /// when UUID resolution lags; [_isPic] still matches app_id / staff uuid.
  bool _isPicEffective(AppState state, Task task) {
    if (_isPic(state, task)) return true;
    return _resolvedIsPic == true;
  }

  /// Sets [_resolvedIsPic] by comparing DB `task.pic` uuid to the signed-in staff uuid.
  Future<void> _refreshResolvedPic(AppState state) async {
    if (!SupabaseConfig.isConfigured || !_loadedForm) return;
    final picRaw = _singularTaskPicStaffUuid?.trim();
    if (picRaw == null || picRaw.isEmpty) {
      if (mounted && _resolvedIsPic != false) {
        setState(() => _resolvedIsPic = false);
      }
      return;
    }
    final lk = state.userStaffAppId?.trim();
    final sid = state.userStaffId?.trim();
    bool? next;
    if (lk != null && lk.isNotEmpty) {
      final myUuid = await SupabaseService.staffRowIdForAssigneeKey(lk);
      next = myUuid != null && _uuidEquals(myUuid, picRaw);
    } else if (sid != null && sid.isNotEmpty) {
      next = _uuidEquals(sid, picRaw);
    } else {
      final asyncUuid = _myStaffUuid?.trim();
      if (asyncUuid != null && asyncUuid.isNotEmpty) {
        next = _uuidEquals(asyncUuid, picRaw);
      } else {
        next = null;
      }
    }
    if (!mounted) return;
    if (_resolvedIsPic != next) {
      setState(() => _resolvedIsPic = next);
    }
  }

  bool _isCreator(AppState state, Task task) {
    final mine = state.userStaffAppId?.trim();
    final cb = task.createByAssigneeKey?.trim();
    if (mine != null &&
        mine.isNotEmpty &&
        cb != null &&
        cb.isNotEmpty &&
        mine == cb) {
      return true;
    }
    return _uuidEquals(_myStaffUuid, _taskCreateByStaffUuid);
  }

  /// `task.assignee_XX` / [Task.assigneeIds] includes the current user.
  bool _isTaskAssignee(AppState state, Task task) {
    final mine = state.userStaffAppId?.trim();
    if (mine != null && mine.isNotEmpty && task.assigneeIds.contains(mine)) {
      return true;
    }
    final uid = _myStaffUuid?.trim();
    if (uid == null || uid.isEmpty) return false;
    for (final id in task.assigneeIds) {
      if (_uuidEquals(id, uid)) return true;
    }
    return false;
  }

  /// Assignee who is not [task.create_by] — may add comments only (not task fields).
  bool _isAssigneeOnlyNotCreator(AppState state, Task task) =>
      _isTaskAssignee(state, task) && !_isCreator(state, task);

  /// Assignee who is not the PIC — uses the comment-only [Update] (PIC uses main [Update] for attachments).
  bool _isCommentOnlyAssignee(AppState state, Task task) =>
      _isAssigneeOnlyNotCreator(state, task) && !_isPicEffective(state, task);

  /// Name, description, assignees, PIC, priority, start/due — creator only.
  bool _canEditSingularTaskMetadata(AppState state, Task task) =>
      _isCreator(state, task);

  /// May use the comment box (creator or any assignee).
  bool _canWriteComments(AppState state, Task task) =>
      _isCreator(state, task) || _isTaskAssignee(state, task);

  /// PIC may submit until status is [Submitted]; [Returned] allows resubmit.
  static bool _canPicSubmit(Task task) {
    final s = task.submission?.trim() ?? '';
    if (s.isEmpty) return true;
    final lower = s.toLowerCase();
    if (lower == 'returned') return true;
    if (lower == 'submitted' || lower == 'accepted') return false;
    return true;
  }

  /// Task soft-delete and comment soft-delete: creator or `staff.director`.
  bool _canMarkTaskDeleted(AppState state) {
    if (_staffDirectorFlag) return true;
    final mine = state.userStaffAppId?.trim();
    final t = state.taskById(widget.taskId);
    final cbKey = t?.createByAssigneeKey?.trim();
    if (mine != null &&
        mine.isNotEmpty &&
        cbKey != null &&
        cbKey.isNotEmpty &&
        mine == cbKey) {
      return true;
    }
    return _uuidEquals(_myStaffUuid, _taskCreateByStaffUuid);
  }

  Future<void> _editSingularComment(SingularCommentRowDisplay c) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: c.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit comment'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Comment',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newBody = controller.text.trim();
    controller.dispose();
    if (ok != true || !mounted) return;
    final err = await SupabaseService.updateSingularCommentRow(
      commentId: c.id,
      description: newBody,
      updaterStaffLookupKey: state.userStaffAppId,
    );
    if (!mounted) return;
    if (err != null) {
      showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
      return;
    }
    await _loadTableComments();
  }

  Future<void> _confirmDeleteSingularComment(
    SingularCommentRowDisplay c,
  ) async {
    final state = context.read<AppState>();
    if (!_canMarkTaskDeleted(state)) {
      showCopyableSnackBar(
        context,
        'Only the task creator or a director can delete comments',
        backgroundColor: Colors.orange,
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text(
          'This comment will be marked as deleted and stay visible at the bottom of the list.',
        ),
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
    final err = await SupabaseService.softDeleteSingularCommentRow(
      commentId: c.id,
      updaterStaffLookupKey: state.userStaffAppId,
    );
    if (!mounted) return;
    if (err != null) {
      showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
      return;
    }
    await _loadTableComments();
  }

  /// Divider between active comments and soft-deleted comments at the bottom.
  Widget _deletedCommentsSectionLabel(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: theme.dividerColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Deleted comments',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: theme.dividerColor)),
        ],
      ),
    );
  }

  List<Widget> _singularCommentTiles(BuildContext context, AppState state) {
    final active = _tableComments
        .where((c) => !c.isDeleted)
        .toList(growable: false);
    final deleted = _tableComments
        .where((c) => c.isDeleted)
        .toList(growable: false);
    final tiles = <Widget>[
      ...active.map((c) => _buildSingularCommentTile(context, state, c)),
    ];
    if (deleted.isEmpty) return tiles;
    if (active.isNotEmpty) {
      tiles.add(_deletedCommentsSectionLabel(context));
    } else {
      tiles.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Deleted comments',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    tiles.addAll(
      deleted.map((c) => _buildSingularCommentTile(context, state, c)),
    );
    return tiles;
  }

  Widget _buildSingularCommentTile(
    BuildContext context,
    AppState state,
    SingularCommentRowDisplay c,
  ) {
    final theme = Theme.of(context);
    final isDeleted = c.isDeleted;
    final grey = Colors.grey.shade600;
    final showEdit = !isDeleted && _isOwnSingularComment(c) && !_saving;
    final showDelete = !isDeleted && _canMarkTaskDeleted(state) && !_saving;
    final subtitleChildren = <Widget>[
      Text(
        '${c.displayStaffName} · ${_formatCommentPostedTs(c.createTimestampUtc)}',
        style: theme.textTheme.bodySmall,
      ),
    ];
    if (c.updateTimestampUtc != null) {
      subtitleChildren.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _formatCommentLastUpdatedLine(c.updateTimestampUtc),
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
                      onPressed: () => _editSingularComment(c),
                    ),
                  if (showDelete)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline, size: 22),
                      onPressed: () => _confirmDeleteSingularComment(c),
                    ),
                ],
              )
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _appStateRef?.removeListener(_onAppStateChangedForPic);
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    _changeDueReasonController.dispose();
    _changeDueReasonFocusNode.dispose();
    _clearTaskAttachments();
    super.dispose();
  }

  void _clearTaskAttachments() {
    for (final e in _taskAttachments) {
      e.dispose();
    }
    _taskAttachments.clear();
  }

  Future<void> _reloadTaskAttachmentsFromDb() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      final rows = await SupabaseService.fetchAttachmentsForTask(widget.taskId);
      if (!mounted) return;
      setState(() {
        _clearTaskAttachments();
        for (final r in rows) {
          _taskAttachments.add(
            _TaskAttachmentEntry(
              id: r.id,
              url: r.content,
              desc: r.description,
            ),
          );
        }
      });
      _captureTaskAttachmentBaseline();
    } catch (e, st) {
      debugPrint('reload task attachments: $e\n$st');
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Could not reload attachments: $e',
          backgroundColor: Colors.orange,
        );
      }
    }
  }

  void _removeTaskAttachmentRow(int index) {
    setState(() {
      _taskAttachments[index].dispose();
      _taskAttachments.removeAt(index);
    });
  }

  List<String?> _singularTaskAttachmentAclKeys(Task task) => [
    task.createByAssigneeKey,
    task.pic,
    ...task.assigneeIds,
  ];

  Future<void> _addTaskAttachmentFromDevice() async {
    final task = context.read<AppState>().taskById(widget.taskId);
    if (task == null) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Task is not loaded yet; try again in a moment.',
          backgroundColor: Colors.orange,
        );
      }
      return;
    }
    final r = await FirebaseAttachmentUploadService.pickUploadForTask(
      widget.taskId,
      aclStaffKeys: _singularTaskAttachmentAclKeys(task),
    );
    if (!mounted) return;
    if (r.error != null && r.error!.isNotEmpty) {
      showCopyableSnackBar(context, r.error!, backgroundColor: Colors.orange);
      return;
    }
    if (r.url == null) return;
    if (!mounted) return;
    setState(() {
      _taskAttachments.add(
        _TaskAttachmentEntry(
          url: r.url,
          desc: (r.label ?? '').trim(),
        ),
      );
    });
    if (mounted) {
      showAttachmentSaveReminderSnackBar(context);
    }
  }

  Future<void> _addTaskAttachmentFromLink() async {
    final result = await showAttachmentAddLinkDialog(context);
    if (!mounted || result == null) return;
    setState(() {
      _taskAttachments.add(
        _TaskAttachmentEntry(
          url: result.url,
          desc: result.description,
        ),
      );
    });
    if (mounted) {
      showAttachmentSaveReminderSnackBar(context);
    }
  }

  Future<void> _editTaskAttachment(int index) async {
    final e = _taskAttachments[index];
    final r = await showAttachmentEditDialog(
      context,
      initialDescription: e.descController.text,
      initialUrl: e.urlController.text,
      pickReplaceFromDevice: () {
        final task = context.read<AppState>().taskById(widget.taskId);
        if (task == null) {
          return Future.value((
            url: null,
            label: null,
            error: 'Task is not loaded yet; try again in a moment.',
          ));
        }
        return FirebaseAttachmentUploadService.pickUploadForTask(
          widget.taskId,
          aclStaffKeys: _singularTaskAttachmentAclKeys(task),
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

  List<({String? content, String? description})> _taskAttachmentPayload() {
    return _taskAttachments
        .map(
          (e) => (
            content: e.urlController.text,
            description: e.descController.text,
          ),
        )
        .toList();
  }

  void _captureTaskAttachmentBaseline() {
    _taskAttachmentBaseline = _taskAttachments
        .map(
          (e) => (
            c: e.urlController.text.trim(),
            d: e.descController.text.trim(),
          ),
        )
        .toList();
  }

  bool _taskAttachmentsDirty() {
    final cur = _taskAttachments
        .map(
          (e) => (
            c: e.urlController.text.trim(),
            d: e.descController.text.trim(),
          ),
        )
        .toList();
    if (cur.length != _taskAttachmentBaseline.length) return true;
    for (var i = 0; i < cur.length; i++) {
      if (cur[i].c != _taskAttachmentBaseline[i].c ||
          cur[i].d != _taskAttachmentBaseline[i].d) {
        return true;
      }
    }
    return false;
  }

  static bool _dateOnlyEqual(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _assigneeSetsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final sa = Set<String>.from(a);
    final sb = Set<String>.from(b);
    return sa.length == sb.length && sa.containsAll(sb);
  }

  /// True if task fields or attachments differ from [task] (excluding pending comment).
  bool _taskCoreOrAttachmentsChanged(
    Task task,
    List<String> directorIdsSorted,
    String picKey,
  ) {
    if (_nameController.text.trim() != task.name.trim()) return true;
    if (_descController.text.trim() != task.description.trim()) return true;
    if (_localPriority != task.priority) return true;
    if (!_assigneeSetsEqual(directorIdsSorted, task.assigneeIds)) return true;
    final pNew = picKey.trim();
    final pOld = (task.pic ?? '').trim();
    if (pNew != pOld) return true;
    if (!_dateOnlyEqual(_startDate, task.startDate)) return true;
    if (!_dateOnlyEqual(_dueDate, task.endDate)) return true;
    final curR = _changeDueReasonController.text.trim();
    final oldR = (task.changeDueReason ?? '').trim();
    if (curR != oldR) return true;
    if (_taskAttachmentsDirty()) return true;
    return false;
  }

  static String _formatYmdForNotify(DateTime d) {
    return DateFormat('yyyy-MM-dd').format(DateTime(d.year, d.month, d.day));
  }

  String _assigneeNamesCsvForNotify(AppState state, List<String> assigneeIds) {
    if (assigneeIds.isEmpty) return '—';
    return assigneeIds
        .map((id) => (state.assigneeById(id)?.name ?? id).trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  /// Field keys must match the backend allow-list for task-updated emails.
  List<Map<String, String>> _buildTaskUpdateNotifyChanges({
    required Task task,
    required AppState state,
    required List<String> newAssigneeIds,
    required int newPriority,
    required DateTime? newStart,
    required DateTime? newDue,
    required String newName,
    required String newDesc,
  }) {
    final out = <Map<String, String>>[];
    if (task.name.trim() != newName.trim()) {
      out.add({'field': 'taskName', 'value': newName.trim()});
    }
    if (task.description.trim() != newDesc.trim()) {
      out.add({'field': 'description', 'value': newDesc.trim()});
    }
    if (!_assigneeSetsEqual(List<String>.from(task.assigneeIds), newAssigneeIds)) {
      out.add({
        'field': 'assignees',
        'value': _assigneeNamesCsvForNotify(state, newAssigneeIds),
      });
    }
    if (task.priority != newPriority) {
      out.add({
        'field': 'priority',
        'value': priorityToDisplayName(newPriority),
      });
    }
    if (!_dateOnlyEqual(task.startDate, newStart)) {
      out.add({
        'field': 'startDate',
        'value': newStart == null ? '—' : _formatYmdForNotify(newStart),
      });
    }
    if (!_dateOnlyEqual(task.endDate, newDue)) {
      out.add({
        'field': 'dueDate',
        'value': newDue == null ? '—' : _formatYmdForNotify(newDue),
      });
    }
    return out;
  }

  String? _firstTaskAttachmentUrl() {
    for (final e in _taskAttachments) {
      final u = e.urlController.text.trim();
      if (u.isNotEmpty) return u;
    }
    return null;
  }

  /// [stored] is `task.update_date` from DB; display in Hong Kong (UTC+8).
  String _lastUpdatedLine(DateTime? stored) {
    if (stored == null) return 'Last updated: —';
    return 'Last updated: ${HkTime.formatInstantAsHk(stored, 'yyyy-MM-dd HH:mm')}';
  }

  static int _dateOnlyCompare(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return da.compareTo(db);
  }

  /// True when the selected start→due span exceeds the Standard / URGENT working-day cap.
  /// (No bypass via sub-tasks: if dates exceed policy, a reason is required before **Update**.)
  bool _needsChangeDueReason() {
    return dueDateExceedsPolicyForPriority(
      _startDate,
      _dueDate,
      _localPriority,
    );
  }

  /// Display for `task.create_by` (resolved name when available).
  String _taskCreatorDisplayLine(Task task, AppState state) {
    final n = task.createByStaffName?.trim();
    if (n != null && n.isNotEmpty) return n;
    final k = task.createByAssigneeKey?.trim();
    if (k != null && k.isNotEmpty) {
      return state.assigneeById(k)?.name ?? k;
    }
    return '—';
  }

  /// Read-only assignee names for non-creator view (prefers [StaffForAssignment.name] via [_labelForAssigneeId]).
  String _singularTaskAssigneesDisplayLine(Task task, AppState state) {
    if (task.assigneeIds.isEmpty) return '—';
    final names = task.assigneeIds
        .map((id) => _labelForAssigneeId(id, state).trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (names.isEmpty) return '—';
    return names.join(', ');
  }

  /// Read-only PIC label for non-creator view ([task.pic] resolved like assignees).
  String _singularTaskPicDisplayLine(Task task, AppState state) {
    final raw = task.pic?.trim();
    if (raw == null || raw.isEmpty) return '—';
    final n = _labelForAssigneeId(raw, state).trim();
    return n.isEmpty ? '—' : n;
  }

  String _normalizeLocalStatus(String? db) {
    if (db == null || db.trim().isEmpty) return 'Incomplete';
    final l = db.trim().toLowerCase();
    if (l == 'complete' || l == 'completed') return 'Completed';
    if (l == 'incomplete') return 'Incomplete';
    if (l == 'delete' || l == 'deleted') return 'Deleted';
    return 'Incomplete';
  }

  int _priorityFromRow(dynamic p) {
    if (p is num) return p.toInt().clamp(1, 2);
    final s = p?.toString().trim().toLowerCase() ?? '';
    if (s.contains('urgent') || s == '2') return 2;
    return 1;
  }

  Widget _toggleButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
    String? disabledMessage,
  }) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Material(
          color: selected ? _selGreen : Colors.white,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: enabled
                ? onTap
                : () {
                    showCopyableSnackBar(
                      context,
                      disabledMessage ??
                          'You do not have permission for this action',
                    );
                  },
            borderRadius: BorderRadius.circular(8),
            child: Container(
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
            ),
          ),
        ),
      ),
    );
  }

  List<AssignableStaffEntry> get _serverAssignable =>
      context.read<AppState>().assignableStaffFromServer;

  /// Full Supabase picker staff list (not restricted by subordinate relationships).
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

  List<Assignee> _assigneesForSelectedTeams() {
    if (_selectedTeamIds.isEmpty) return [];
    return context.read<AppState>().getAssigneesForTeams(
      _selectedTeamIds.toList(),
    );
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

  Widget _buildPicSection(BuildContext context, AppState state) {
    final ids = _selectedAssigneeIds.toList()
      ..sort(
        (a, b) => _labelForAssigneeId(
          a,
          state,
        ).compareTo(_labelForAssigneeId(b, state)),
      );
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
          onChanged: _saving ? null : (v) => setState(() => _picAssigneeId = v),
          validator: (v) =>
              v == null || v.isEmpty ? 'Choose a PIC from the assignees' : null,
        ),
      ],
    );
  }

  Future<void> _ensureLoaded(AppState state) async {
    final task = state.taskById(widget.taskId);
    if (task == null) return;

    if (!_loadedForm) {
      _nameController.text = task.name;
      _descController.text = task.description;
      _startDate = task.startDate;
      _dueDate = task.endDate;
      _changeDueReasonController.text = task.changeDueReason ?? '';
      _localPriority = task.priority.clamp(1, 2);
      _localStatus = _normalizeLocalStatus(task.dbStatus);
    }

    if (!SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() {
          _loadingStaff = false;
          _loadedForm = true;
        });
        _captureTaskAttachmentBaseline();
      }
      return;
    }

    if (_loadedForm) return;

    setState(() {
      _pickerLoading = true;
      _pickerError = null;
    });

    try {
      final data = await SupabaseService.fetchStaffAssigneePickerData();
      final row = await SupabaseService.fetchSingularTaskById(widget.taskId);
      List<TaskAttachmentRow> attachmentRows = [];
      try {
        attachmentRows =
            await SupabaseService.fetchAttachmentsForTask(widget.taskId);
      } catch (e, st) {
        debugPrint('task attachments initial load: $e\n$st');
        attachmentRows = [];
      }
      final selectedAppIds = <String>{};
      if (row != null) {
        for (var i = 1; i <= 10; i++) {
          final key = 'assignee_${i.toString().padLeft(2, '0')}';
          final raw = row[key];
          if (raw != null && raw.toString().trim().isNotEmpty) {
            final uuid = raw.toString().trim();
            final appKey = await SupabaseService.assigneeListKeyFromStaffUuid(
              uuid,
            );
            selectedAppIds.add(appKey);
          }
        }
      } else {
        selectedAppIds.addAll(task.assigneeIds);
      }

      final teamIds = <String>{};
      if (data != null) {
        _pickerTeams = data.teams;
        _pickerStaff = data.staff;
        _staffAssigneeToTeamId.clear();
        for (final s in data.staff) {
          if (s.teamId != null && s.teamId!.isNotEmpty) {
            _staffAssigneeToTeamId[s.assigneeId] = s.teamId!;
          }
        }
        for (final id in selectedAppIds) {
          final tid = _staffAssigneeToTeamId[id];
          if (tid != null && tid.isNotEmpty) teamIds.add(tid);
        }
      } else {
        _pickerTeams = [];
        _pickerStaff = [];
        _staffAssigneeToTeamId.clear();
      }

      if (!mounted) return;

      final picRawForResolved = row?['pic']?.toString().trim();
      bool? resolvedIsPic;
      if (picRawForResolved != null && picRawForResolved.isNotEmpty) {
        final lk = state.userStaffAppId?.trim();
        final sid = state.userStaffId?.trim();
        if (lk != null && lk.isNotEmpty) {
          final myUuid = await SupabaseService.staffRowIdForAssigneeKey(lk);
          resolvedIsPic =
              myUuid != null && _uuidEquals(myUuid, picRawForResolved);
        } else if (sid != null && sid.isNotEmpty) {
          resolvedIsPic = _uuidEquals(sid, picRawForResolved);
        } else {
          resolvedIsPic = null;
        }
      } else {
        resolvedIsPic = false;
      }

      if (!mounted) return;
      _clearTaskAttachments();
      setState(() {
        for (final r in attachmentRows) {
          _taskAttachments.add(
            _TaskAttachmentEntry(
              id: r.id,
              url: r.content,
              desc: r.description,
            ),
          );
        }
        _selectedAssigneeIds
          ..clear()
          ..addAll(selectedAppIds);
        _selectedTeamIds
          ..clear()
          ..addAll(teamIds);
        _picAssigneeId = task.pic;
        if (_selectedAssigneeIds.length == 1) {
          _picAssigneeId = _selectedAssigneeIds.first;
        } else if (_selectedAssigneeIds.length > 1) {
          if (_picAssigneeId == null ||
              !_selectedAssigneeIds.contains(_picAssigneeId)) {
            _picAssigneeId = null;
          }
        } else {
          _picAssigneeId = null;
        }
        if (row != null) {
          _localPriority = _priorityFromRow(row['priority']);
          _localStatus = _normalizeLocalStatus(row['status']?.toString());
          _taskCreateByStaffUuid = row['create_by']?.toString().trim();
          _singularTaskPicStaffUuid = row['pic']?.toString().trim();
          _changeDueReasonController.text =
              row['change_due_reason']?.toString() ?? '';
        } else {
          _singularTaskPicStaffUuid = null;
        }
        _resolvedIsPic = resolvedIsPic;
        _pickerLoading = false;
        _loadingStaff = false;
        _loadedForm = true;
      });
      _captureTaskAttachmentBaseline();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pickerError = e.toString();
        _pickerLoading = false;
        _loadingStaff = false;
        _loadedForm = true;
      });
      _captureTaskAttachmentBaseline();
    }
  }

  /// Saves non-empty [_commentController] as an active `comment` row. Clears the field on success.
  /// Returns `false` if an insert was attempted and failed (snackbar shown). Empty text returns `true`.
  Future<bool> _insertPendingCommentFromController(
    AppState state,
    Task task, {
    String commentSaveErrorPrefix = 'Task updated, but comment was not saved:',
    bool suppressNotificationEmail = false,
  }) async {
    final commentBody = _commentController.text.trim();
    if (commentBody.isEmpty) return true;
    final cResult = await SupabaseService.insertSingularCommentRow(
      taskId: task.id,
      description: commentBody,
      status: 'Active',
      creatorStaffLookupKey: state.userStaffAppId,
    );
    if (cResult.error != null) {
      if (mounted) {
        showCopyableSnackBar(
          context,
          '$commentSaveErrorPrefix ${cResult.error}',
          backgroundColor: Colors.orange,
        );
      }
      return false;
    }
    if (!mounted) return false;
    _commentController.clear();
    await _loadTableComments();
    final newCommentId = cResult.commentId?.trim();
    if (newCommentId != null &&
        newCommentId.isNotEmpty &&
        !suppressNotificationEmail) {
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final notifyErr = await BackendApi().notifyTaskCommentAdded(
            idToken: token,
            commentId: newCommentId,
          );
          if (notifyErr != null && mounted) {
            showCopyableSnackBar(
              context,
              'Comment email: $notifyErr',
              backgroundColor: Colors.orange,
            );
          }
        } else if (mounted) {
          showCopyableSnackBar(
            context,
            'Comment saved; notify email skipped (no sign-in token)',
            backgroundColor: Colors.orange,
          );
        }
      } catch (e) {
        if (mounted) {
          showCopyableSnackBar(
            context,
            'Comment email failed: $e',
            backgroundColor: Colors.orange,
          );
        }
      }
    }
    return true;
  }

  /// Assignees who are not the creator post comments without using **Update**.
  Future<void> _postCommentOnly(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    if (!_canWriteComments(state, task)) return;
    if (_isCreator(state, task)) {
      showCopyableSnackBar(
        context,
        'Use Update to save your comment with the task',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_commentController.text.trim().isEmpty) {
      showCopyableSnackBar(
        context,
        'Nothing is updated',
        backgroundColor: Colors.orange,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final ok = await _insertPendingCommentFromController(
        state,
        task,
        commentSaveErrorPrefix: 'Comment was not saved:',
      );
      if (!mounted) return;
      if (ok) {
        showCopyableSnackBar(
          context,
          'Task is updated',
          backgroundColor: Colors.green,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTaskFields(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (!_isCreator(state, task)) {
      showCopyableSnackBar(
        context,
        'Only the task creator can update assignees, PIC, dates, and other task details',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }
    if (_startDate != null &&
        _dueDate != null &&
        _dateOnlyCompare(_startDate!, _dueDate!) > 0) {
      showCopyableSnackBar(
        context,
        'Start date cannot be after due date',
        backgroundColor: Colors.orange,
      );
      return;
    }
    final needsDueReason = _needsChangeDueReason();
    if (needsDueReason && _changeDueReasonController.text.trim().isEmpty) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _changeDueReasonFocusNode.requestFocus();
        });
      }
      showCopyableSnackBar(
        context,
        'Enter a reason when the start/due span exceeds the allowed working days for this priority',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (_saving) return;

    final useServer = state.assignableStaffFromServer.isNotEmpty;
    final pickerStaffForRole = _pickerStaffForRole();
    final useSupabasePicker =
        SupabaseConfig.isConfigured && pickerStaffForRole.isNotEmpty;

    late final List<String> directorIds;
    if (SupabaseConfig.isConfigured && useSupabasePicker) {
      if (_selectedAssigneeIds.isEmpty) {
        showCopyableSnackBar(context, 'Select at least one assignee');
        return;
      }
      directorIds = _selectedAssigneeIds.toList();
    } else if (useServer) {
      if (_selectedAssigneeIds.isEmpty) {
        showCopyableSnackBar(context, 'Select at least one assignee');
        return;
      }
      directorIds = _selectedAssigneeIds.toList();
    } else if (_selectedTeamIds.isNotEmpty && _selectedAssigneeIds.isNotEmpty) {
      directorIds = _selectedAssigneeIds.toList();
    } else {
      final self = state.userStaffAppId;
      if (self == null || self.isEmpty) {
        showCopyableSnackBar(
          context,
          'Select team(s) and assignees, or configure Supabase',
        );
        return;
      }
      directorIds = [self];
    }

    if (directorIds.length > _maxAssignees) {
      showCopyableSnackBar(
        context,
        'At most $_maxAssignees assignees',
      );
      return;
    }

    final String picKey;
    if (directorIds.length == 1) {
      picKey = directorIds.first;
    } else {
      if (_picAssigneeId == null || !directorIds.contains(_picAssigneeId)) {
        showCopyableSnackBar(
          context,
          'Select a PIC (person in charge) from the assignees',
          backgroundColor: Colors.orange,
        );
        return;
      }
      picKey = _picAssigneeId!;
    }

    final sortedForCompare = [...directorIds]
      ..sort(
        (a, b) => _labelForAssigneeId(
          a,
          state,
        ).compareTo(_labelForAssigneeId(b, state)),
      );
    final takeForCompare = sortedForCompare.take(_maxAssignees).toList();
    final pendingComment = _commentController.text.trim().isNotEmpty;
    if (!pendingComment &&
        !_taskCoreOrAttachmentsChanged(task, takeForCompare, picKey)) {
      showCopyableSnackBar(context, 'Nothing is updated');
      return;
    }

    setState(() => _saving = true);
    try {
      final sorted = sortedForCompare;
      final take = sorted.take(_maxAssignees).toList();
      final slots = await SupabaseService.assigneeSlotsForTask(take);
      final assigneeIdsForState = List<String>.from(take);

      final priorityLabel = priorityToDisplayName(_localPriority);

      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        taskName: _nameController.text.trim(),
        description: _descController.text.trim(),
        priority: priorityLabel,
        assigneeSlots: slots,
        startDate: _startDate,
        dueDate: _dueDate,
        clearStartDate: _startDate == null,
        clearDueDate: _dueDate == null,
        updateByStaffLookupKey: state.userStaffAppId,
        picStaffLookupKey: picKey,
        updateChangeDueReason: true,
        changeDueReason:
            needsDueReason ? _changeDueReasonController.text.trim() : null,
      );
      if (!mounted) return;

      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }

      if (_isCreator(state, task) || _isPicEffective(state, task)) {
        final errAttach = await SupabaseService.replaceAttachmentsForTask(
          taskId: task.id,
          rows: _taskAttachmentPayload(),
        );
        if (errAttach != null && mounted) {
          showCopyableSnackBar(
            context,
            'Task updated, but attachment was not saved: $errAttach',
            backgroundColor: Colors.orange,
          );
        } else if (errAttach == null && mounted) {
          await _reloadTaskAttachmentsFromDb();
        }
      }

      final pendingCommentSnap = _commentController.text.trim();
      final changesForEmail = _buildTaskUpdateNotifyChanges(
        task: task,
        state: state,
        newAssigneeIds: assigneeIdsForState,
        newPriority: _localPriority,
        newStart: _startDate,
        newDue: _dueDate,
        newName: _nameController.text,
        newDesc: _descController.text,
      );

      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (!mounted) return;

      final commentInsertedOk = await _insertPendingCommentFromController(
        state,
        task,
        suppressNotificationEmail: token != null,
      );
      if (!mounted) return;

      final String? commentForEmail =
          pendingCommentSnap.isNotEmpty && commentInsertedOk
              ? pendingCommentSnap
              : null;

      if (token != null) {
        try {
          final notifyErr = await BackendApi().notifyTaskUpdated(
            idToken: token,
            taskId: task.id,
            changes: changesForEmail,
            commentAddedText: commentForEmail,
          );
          if (notifyErr != null && mounted) {
            showCopyableSnackBar(
              context,
              'Task saved; update email: $notifyErr',
              backgroundColor: Colors.orange,
            );
          }
        } catch (e) {
          if (mounted) {
            showCopyableSnackBar(
              context,
              'Update email failed: $e',
              backgroundColor: Colors.orange,
            );
          }
        }
      }
      if (!mounted) return;

      final lk = state.userStaffAppId?.trim();
      String? updaterName;
      if (lk != null && lk.isNotEmpty) {
        updaterName =
            state.assigneeById(lk)?.name ??
            await SupabaseService.staffDisplayNameForKey(lk);
      }
      if (!mounted) return;

      state.replaceTask(
        task.copyWith(
          name: _nameController.text.trim(),
          description: _descController.text.trim(),
          assigneeIds: assigneeIdsForState,
          priority: _localPriority,
          startDate: _startDate,
          endDate: _dueDate,
          dbStatus: task.dbStatus,
          status: task.status,
          submission: task.submission,
          updateByStaffName: updaterName,
          updateDate: DateTime.now(),
          pic: picKey,
          changeDueReason:
              needsDueReason ? _changeDueReasonController.text.trim() : null,
        ),
      );
      showCopyableSnackBar(
        context,
        'Task is updated',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// PIC (not task creator): save attachment rows and/or a new comment (same as creator [Update] for comments).
  Future<void> _saveTaskAttachmentsOnly(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    if (!_isPicEffective(state, task) || _isCreator(state, task)) {
      return;
    }
    final pendingComment = _commentController.text.trim().isNotEmpty;
    final attachmentsDirty = _taskAttachmentsDirty();
    if (!pendingComment && !attachmentsDirty) {
      showCopyableSnackBar(context, 'Nothing is updated');
      return;
    }
    setState(() => _saving = true);
    try {
      if (attachmentsDirty) {
        final errAttach = await SupabaseService.replaceAttachmentsForTask(
          taskId: task.id,
          rows: _taskAttachmentPayload(),
        );
        if (errAttach != null && mounted) {
          showCopyableSnackBar(
            context,
            errAttach,
            backgroundColor: Colors.orange,
          );
          return;
        }
        if (mounted) await _reloadTaskAttachmentsFromDb();
      }
      if (pendingComment) {
        final commentOk = await _insertPendingCommentFromController(
          state,
          task,
          commentSaveErrorPrefix: 'Comment was not saved:',
        );
        if (!commentOk) return;
      }
      if (mounted) {
        showCopyableSnackBar(
          context,
          'Task is updated',
          backgroundColor: Colors.green,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitForReview(AppState state, Task task) async {
    final link = _firstTaskAttachmentUrl()?.trim() ?? '';
    final subComment = _commentController.text.trim();
    if (link.isEmpty && subComment.isEmpty) {
      showCopyableSnackBar(
        context,
        'Add a hyperlink in Attachment and/or a comment above before submitting',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final errAttach = await SupabaseService.replaceAttachmentsForTask(
        taskId: task.id,
        rows: _taskAttachmentPayload(),
      );
      if (errAttach != null) {
        if (mounted) {
          showCopyableSnackBar(
            context,
            errAttach,
            backgroundColor: Colors.orange,
          );
        }
        return;
      }
      if (mounted) await _reloadTaskAttachmentsFromDb();
      if (subComment.isNotEmpty) {
        final c = await SupabaseService.insertSingularCommentRow(
          taskId: task.id,
          description: subComment,
          creatorStaffLookupKey: state.userStaffAppId,
        );
        if (c.error != null) {
          if (mounted) {
            showCopyableSnackBar(
              context,
              c.error!,
              backgroundColor: Colors.orange,
            );
          }
          return;
        }
        await _loadTableComments();
      }
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        submission: 'Submitted',
        updateByStaffLookupKey: state.userStaffAppId,
        stampSubmitDateNow: true,
      );
      if (err != null) {
        if (mounted) {
          showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        }
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifyTaskSubmission(
            idToken: token,
            taskId: task.id,
          );
          if (ne != null && mounted) {
            showCopyableSnackBar(
              context,
              'Submitted; email: $ne',
              backgroundColor: Colors.orange,
            );
          }
        }
      } catch (_) {}
      if (!mounted) return;
      if (subComment.isNotEmpty) {
        setState(() {
          _commentController.clear();
        });
      }
      state.replaceTask(
        task.copyWith(
          submission: 'Submitted',
          submitDate: DateTime.now().toUtc(),
          updateDate: DateTime.now(),
        ),
      );
      showCopyableSnackBar(
        context,
        'Submission sent',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _acceptSubmission(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final commentOk = await _insertPendingCommentFromController(
        state,
        task,
        commentSaveErrorPrefix: 'Comment was not saved:',
      );
      if (!commentOk) return;

      final completedAt = task.submitDate ?? DateTime.now().toUtc();
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Completed',
        submission: 'Accepted',
        updateByStaffLookupKey: state.userStaffAppId,
        completionDateAt: completedAt,
      );
      if (err != null) {
        if (mounted) {
          showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        }
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifyTaskAccepted(
            idToken: token,
            taskId: task.id,
          );
          if (ne != null && mounted) {
            showCopyableSnackBar(
              context,
              'Accept email: $ne',
              backgroundColor: Colors.orange,
            );
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _localStatus = 'Completed');
      state.replaceTask(
        task.copyWith(
          dbStatus: 'Completed',
          status: TaskStatus.done,
          submission: 'Accepted',
          completionDate: completedAt,
          updateDate: DateTime.now(),
        ),
      );
      showCopyableSnackBar(
        context,
        'Task accepted',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _returnSubmission(AppState state, Task task) async {
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final commentOk = await _insertPendingCommentFromController(
        state,
        task,
        commentSaveErrorPrefix: 'Comment was not saved:',
      );
      if (!commentOk) return;

      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Incomplete',
        submission: 'Returned',
        updateByStaffLookupKey: state.userStaffAppId,
        clearCompletionDate: true,
      );
      if (err != null) {
        if (mounted) {
          showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        }
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifyTaskReturned(
            idToken: token,
            taskId: task.id,
          );
          if (ne != null && mounted) {
            showCopyableSnackBar(
              context,
              'Return email: $ne',
              backgroundColor: Colors.orange,
            );
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => _localStatus = 'Incomplete');
      state.replaceTask(
        task.copyWith(
          dbStatus: 'Incomplete',
          status: TaskStatus.todo,
          submission: 'Returned',
          clearCompletionDate: true,
          updateDate: DateTime.now(),
        ),
      );
      showCopyableSnackBar(
        context,
        'Task returned to PIC',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmMarkSingularTaskDeleted(
    AppState state,
    Task task,
  ) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm to delete task'),
        content: Text('“${task.name}” will be deleted.'),
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
    if (!SupabaseConfig.isConfigured) {
      showCopyableSnackBar(context, 'Supabase not configured');
      return;
    }
    setState(() => _saving = true);
    try {
      final err = await SupabaseService.updateSingularTaskRow(
        taskId: task.id,
        status: 'Deleted',
        updateByStaffLookupKey: state.userStaffAppId,
      );
      if (!mounted) return;
      if (err != null) {
        showCopyableSnackBar(context, err, backgroundColor: Colors.orange);
        return;
      }
      setState(() => _localStatus = 'Deleted');
      state.replaceTask(
        task.copyWith(dbStatus: 'Deleted', status: TaskStatus.todo),
      );
      showCopyableSnackBar(
        context,
        'Task marked as deleted',
        backgroundColor: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickStartDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _startDate ?? _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (d == null || !mounted) return;
    if (_dueDate != null && _dateOnlyCompare(d, _dueDate!) > 0) {
      showCopyableSnackBar(
        context,
        'Start date cannot be after due date',
        backgroundColor: Colors.orange,
      );
      return;
    }
    setState(() => _startDate = d);
  }

  Future<void> _pickDueDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (d == null || !mounted) return;
    if (_startDate != null && _dateOnlyCompare(_startDate!, d) > 0) {
      showCopyableSnackBar(
        context,
        'Due date cannot be before start date',
        backgroundColor: Colors.orange,
      );
      return;
    }
    setState(() => _dueDate = d);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final task = state.taskById(widget.taskId);
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('Task not found')),
      );
    }

    final useServer = state.assignableStaffFromServer.isNotEmpty;
    List<AssignableStaffEntry> serverAssigneesFiltered = [];
    if (useServer) {
      var base = List<AssignableStaffEntry>.from(
        state.assignableStaffFromServer,
      );
      if (_selectedTeamIds.isNotEmpty) {
        base = base
            .where(
              (e) =>
                  e.teamAppId != null && _selectedTeamIds.contains(e.teamAppId),
            )
            .toList();
      }
      serverAssigneesFiltered = base;
    }
    final assignees = _assigneesForSelectedTeams();
    final pickerStaffForRole = _pickerStaffForRole();
    final pickerTeamsForRole = _pickerTeamsForRole();
    final useSupabasePicker =
        SupabaseConfig.isConfigured && pickerStaffForRole.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(task.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: _saving,
            child: Opacity(
              opacity: _saving ? 0.55 : 1,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Task creator: ${_taskCreatorDisplayLine(task, state)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_isCreator(state, task)) ...[
                                    TextField(
                                      controller: _nameController,
                                      readOnly: _saving ||
                                          !_canEditSingularTaskMetadata(
                                            state,
                                            task,
                                          ),
                                      enableInteractiveSelection:
                                          _isCreator(state, task) ||
                                              _isTaskAssignee(state, task),
                                      decoration: const InputDecoration(
                                        labelText: 'Task name',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _descController,
                                      readOnly: _saving ||
                                          !_canEditSingularTaskMetadata(
                                            state,
                                            task,
                                          ),
                                      enableInteractiveSelection:
                                          _isCreator(state, task) ||
                                              _isTaskAssignee(state, task),
                                      decoration: const InputDecoration(
                                        labelText: 'Description',
                                        border: OutlineInputBorder(),
                                        alignLabelWithHint: true,
                                      ),
                                      maxLines: 4,
                                    ),
                                  ] else ...[
                                    Text(
                                      'Task assignee(s): ${_singularTaskAssigneesDisplayLine(task, state)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'PIC: ${_singularTaskPicDisplayLine(task, state)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _nameController,
                                      readOnly: true,
                                      enableInteractiveSelection:
                                          _isTaskAssignee(state, task),
                                      decoration: const InputDecoration(
                                        labelText: 'Task name',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: _descController,
                                      readOnly: true,
                                      enableInteractiveSelection:
                                          _isTaskAssignee(state, task),
                                      decoration: const InputDecoration(
                                        labelText: 'Description',
                                        border: OutlineInputBorder(),
                                        alignLabelWithHint: true,
                                      ),
                                      maxLines: 4,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            AbsorbPointer(
                              absorbing:
                                  !_canEditSingularTaskMetadata(state, task),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                              if (_canEditSingularTaskMetadata(state, task)) ...[
                              if (!SupabaseConfig.isConfigured) ...[
                                Text(
                                  'Assignees',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  task.assigneeIds.isEmpty
                                      ? '—'
                                      : task.assigneeIds
                                            .map(
                                              (id) =>
                                                  state
                                                      .assigneeById(id)
                                                      ?.name ??
                                                  id,
                                            )
                                            .join(', '),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 16),
                              ] else ...[
                                if (_pickerLoading) ...[
                                  const LinearProgressIndicator(),
                                  const SizedBox(height: 8),
                                ],
                                if (_pickerError != null && !_pickerLoading)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      _pickerError!,
                                      style: TextStyle(
                                        color: Colors.orange.shade800,
                                        fontSize: 12,
                                      ),
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
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Builder(
                                    builder: (context) {
                                      final teams = state.teams;
                                      if (teams.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(
                                            'No teams found in database.',
                                            style: TextStyle(
                                              color: Colors.orange.shade700,
                                              fontSize: 12,
                                            ),
                                          ),
                                        );
                                      }
                                      return Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: teams.map((Team t) {
                                          final selected = _selectedTeamIds
                                              .contains(t.id);
                                          return FilterChip(
                                            label: Text(t.name),
                                            selected: selected,
                                            onSelected: _saving
                                                ? null
                                                : (v) {
                                                    setState(() {
                                                      if (v) {
                                                        _selectedTeamIds.add(
                                                          t.id,
                                                        );
                                                      } else {
                                                        _selectedTeamIds.remove(
                                                          t.id,
                                                        );
                                                        _selectedAssigneeIds.removeWhere((
                                                          id,
                                                        ) {
                                                          final assignee =
                                                              _serverAssignable.firstWhere(
                                                                (e) =>
                                                                    e.staffAppId ==
                                                                    id,
                                                                orElse: () =>
                                                                    const AssignableStaffEntry(
                                                                      staffAppId:
                                                                          '',
                                                                      staffName:
                                                                          '',
                                                                      teamAppId:
                                                                          null,
                                                                      teamName:
                                                                          null,
                                                                    ),
                                                              );
                                                          return assignee
                                                                      .teamAppId ==
                                                                  t.id &&
                                                              !_selectedTeamIds.any((
                                                                tid,
                                                              ) {
                                                                final other = _serverAssignable.firstWhere(
                                                                  (e) =>
                                                                      e.staffAppId ==
                                                                      id,
                                                                  orElse: () => const AssignableStaffEntry(
                                                                    staffAppId:
                                                                        '',
                                                                    staffName:
                                                                        '',
                                                                    teamAppId:
                                                                        null,
                                                                    teamName:
                                                                        null,
                                                                  ),
                                                                );
                                                                return other
                                                                        .teamAppId ==
                                                                    tid;
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
                              if (SupabaseConfig.isConfigured &&
                                  !useSupabasePicker) ...[
                                Text(
                                  useServer
                                      ? 'Assignees (multiple)'
                                      : 'Directors & Responsible Officers (multiple)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (useServer) ...[
                                  if (serverAssigneesFiltered.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        'No assignable staff found for the selected team(s).',
                                        style: TextStyle(
                                          color: Colors.orange.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    )
                                  else
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: serverAssigneesFiltered.map((
                                        e,
                                      ) {
                                        final selected = _selectedAssigneeIds
                                            .contains(e.staffAppId);
                                        return FilterChip(
                                          label: Text(e.staffName),
                                          selected: selected,
                                          onSelected: _saving
                                              ? null
                                              : (v) {
                                                  setState(() {
                                                    if (v) {
                                                      _selectedAssigneeIds.add(
                                                        e.staffAppId,
                                                      );
                                                      if (e.teamAppId != null) {
                                                        _selectedTeamIds.add(
                                                          e.teamAppId!,
                                                        );
                                                      }
                                                    } else {
                                                      _selectedAssigneeIds
                                                          .remove(e.staffAppId);
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
                                        final selected = _selectedAssigneeIds
                                            .contains(a.id);
                                        final isDirector = state.isDirector(
                                          a.id,
                                        );
                                        return FilterChip(
                                          label: Text(a.name),
                                          selected: selected,
                                          backgroundColor: isDirector
                                              ? Colors.lightBlue.shade100
                                              : Colors.purple.shade100,
                                          onSelected: _saving
                                              ? null
                                              : (v) {
                                                  setState(() {
                                                    if (v) {
                                                      _selectedAssigneeIds.add(
                                                        a.id,
                                                      );
                                                    } else {
                                                      _selectedAssigneeIds
                                                          .remove(a.id);
                                                    }
                                                    _syncPicAfterAssigneesChange();
                                                  });
                                                },
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ],
                              if (SupabaseConfig.isConfigured &&
                                  _selectedAssigneeIds.length > 1) ...[
                                const SizedBox(height: 16),
                                _buildPicSection(context, state),
                              ],
                              if (_loadingStaff && SupabaseConfig.isConfigured)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Text(
                                'Priority',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _toggleButton(
                                    label: 'Standard',
                                    selected: _localPriority == 1,
                                    enabled: _canEditSingularTaskMetadata(
                                      state,
                                      task,
                                    ),
                                    onTap: () =>
                                        setState(() => _localPriority = 1),
                                  ),
                                  const SizedBox(width: 12),
                                  _toggleButton(
                                    label: 'URGENT',
                                    selected: _localPriority == 2,
                                    enabled: _canEditSingularTaskMetadata(
                                      state,
                                      task,
                                    ),
                                    onTap: () =>
                                        setState(() => _localPriority = 2),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _startDate == null
                                          ? 'Start date: not set'
                                          : 'Start: ${DateFormat('yyyy-MM-dd').format(_startDate!)}',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed:
                                        (_saving ||
                                                !_canEditSingularTaskMetadata(
                                                  state,
                                                  task,
                                                ))
                                            ? null
                                            : _pickStartDate,
                                    icon: const Icon(Icons.calendar_today),
                                    label: const Text('Pick'),
                                  ),
                                  if (_startDate != null)
                                    TextButton(
                                      onPressed:
                                        (_saving ||
                                                !_canEditSingularTaskMetadata(
                                                  state,
                                                  task,
                                                ))
                                            ? null
                                            : () => setState(
                                                () => _startDate = null,
                                              ),
                                      child: const Text('Clear'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _dueDate == null
                                          ? 'Due date: not set'
                                          : 'Due: ${DateFormat('yyyy-MM-dd').format(_dueDate!)}',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed:
                                        (_saving ||
                                                !_canEditSingularTaskMetadata(
                                                  state,
                                                  task,
                                                ))
                                            ? null
                                            : _pickDueDate,
                                    icon: const Icon(Icons.event),
                                    label: const Text('Pick'),
                                  ),
                                  if (_dueDate != null)
                                    TextButton(
                                      onPressed:
                                        (_saving ||
                                                !_canEditSingularTaskMetadata(
                                                  state,
                                                  task,
                                                ))
                                            ? null
                                            : () =>
                                                setState(() => _dueDate = null),
                                      child: const Text('Clear'),
                                    ),
                                ],
                              ),
                              if (_canEditSingularTaskMetadata(state, task)) ...[
                                if (_needsChangeDueReason()) ...[
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: _changeDueReasonController,
                                    focusNode: _changeDueReasonFocusNode,
                                    readOnly: _saving,
                                    decoration: const InputDecoration(
                                      labelText: 'Reason',
                                      hintText: 'Extend timeline reason',
                                      border: OutlineInputBorder(),
                                      alignLabelWithHint: true,
                                    ),
                                    maxLines: 3,
                                  ),
                                ],
                              ] else if ((task.changeDueReason ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Reason: ${task.changeDueReason}',
                                  style: Theme.of(context).textTheme.bodyMedium,
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
                                'Task status: $_localStatus',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Submission: ${task.submission?.trim().isNotEmpty == true ? task.submission!.trim() : '—'}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (task.submitDate != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Submission date: ${HkTime.formatInstantAsHk(task.submitDate!, 'yyyy-MM-dd')}',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                              if (task.completionDate != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Completion date: ${HkTime.formatInstantAsHk(task.completionDate!, 'yyyy-MM-dd')}',
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
                                'Last updated by: ${task.updateByStaffName ?? '—'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _lastUpdatedLine(task.updateDate),
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
                    ],
                  ),
                ),
                      const SizedBox(height: 24),
                      Text(
                        'Attachment',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (_isCreator(state, task) ||
                          _isPicEffective(state, task))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.add_link_outlined),
                            label: const Text('Add attachment'),
                            onPressed: (_saving ||
                                    !(_isCreator(state, task) ||
                                        _isPicEffective(state, task)))
                                ? null
                                : () {
                                    showAttachmentSourceBottomSheet(
                                      context: context,
                                      onPickFromDevice: () {
                                        if (!mounted) return;
                                        _addTaskAttachmentFromDevice();
                                      },
                                      onPickFromLink: () {
                                        if (!mounted) return;
                                        _addTaskAttachmentFromLink();
                                      },
                                    );
                                  },
                          ),
                        ),
                      const SizedBox(height: 8),
                      ...List.generate(_taskAttachments.length, (i) {
                        final e = _taskAttachments[i];
                        final canEdit = _isCreator(state, task) ||
                            _isPicEffective(state, task);
                        final hasLink =
                            e.urlController.text.trim().isNotEmpty;
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
                                        : () => _editTaskAttachment(i),
                                    child: const Text('Edit'),
                                  ),
                                  TextButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _removeTaskAttachmentRow(i),
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
                                        TextField(
                                          controller: e.descController,
                                          readOnly: _saving || !canEdit,
                                          decoration: const InputDecoration(
                                            labelText:
                                                'Attachment description',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (canEdit)
                                          TextField(
                                            controller: e.urlController,
                                            readOnly: _saving,
                                            decoration: InputDecoration(
                                              labelText: 'Attachment link',
                                              hintText: 'https://…',
                                              border:
                                                  const OutlineInputBorder(),
                                              isDense: true,
                                              suffixIcon: IconButton(
                                                icon: const Icon(
                                                  Icons.open_in_new_outlined,
                                                  size: 20,
                                                ),
                                                tooltip: 'Open link',
                                                onPressed: () {
                                                  final u = e
                                                      .urlController.text
                                                      .trim();
                                                  if (u.isEmpty) {
                                                    showCopyableSnackBar(
                                                      context,
                                                      'Enter a link first',
                                                    );
                                                    return;
                                                  }
                                                  openAttachmentUrl(
                                                    context,
                                                    u,
                                                  );
                                                },
                                              ),
                                            ),
                                          )
                                        else ...[
                                          InputDecorator(
                                            decoration: const InputDecoration(
                                              labelText:
                                                  'Attachment description',
                                              border: OutlineInputBorder(),
                                              isDense: true,
                                            ),
                                            child: Text(
                                              e.descController.text
                                                      .trim()
                                                      .isEmpty
                                                  ? '—'
                                                  : e.descController.text,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
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
                                          : () => _editTaskAttachment(i),
                                      child: const Text('Edit'),
                                    ),
                                    TextButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _removeTaskAttachmentRow(i),
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
                        'Sub-tasks',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_isCreator(state, task)) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () async {
                                    final created = await Navigator.of(
                                      context,
                                    ).push<bool>(
                                      MaterialPageRoute<bool>(
                                        builder: (_) => CreateSubtaskScreen(
                                          taskId: widget.taskId,
                                        ),
                                      ),
                                    );
                                    if (created == true && mounted) {
                                      await _loadSubtasks();
                                    }
                                  },
                            icon: const Icon(Icons.add_task_outlined),
                            label: const Text('Create sub-task'),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_loadingSubtasks)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_subtasks.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Text(
                                        'Sort',
                                        style: (Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium ??
                                                const TextStyle())
                                            .copyWith(
                                          fontSize: kLandingListCardFontSize,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    for (final col
                                        in SubtaskListSortColumn.values)
                                      SubtaskSortColumnChip(
                                        column: col,
                                        active: _subtaskSortColumn == col,
                                        ascending: _subtaskSortAscending,
                                        onMenuSelected: (v) =>
                                            _onSubtaskSortMenu(col, v),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ...SubtaskListSort.sort(
                          _subtasks,
                          resolveName: (id) =>
                              state.assigneeById(id)?.name ?? id,
                          activeColumn: _subtaskSortColumn,
                          ascending: _subtaskSortAscending,
                        ).map(
                          (s) {
                            return SingularSubtaskRowCard(
                              subtask: s,
                              resolveName: (id) =>
                                  state.assigneeById(id)?.name ?? id,
                              onTap: () async {
                                final changed =
                                    await Navigator.of(context).push<bool>(
                                  MaterialPageRoute<bool>(
                                    builder: (_) => SubtaskDetailScreen(
                                      subtaskId: s.id,
                                    ),
                                  ),
                                );
                                if (changed == true && mounted) {
                                  await _loadSubtasks();
                                }
                              },
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Comments',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        readOnly: _saving || !_canWriteComments(state, task),
                        textAlignVertical: TextAlignVertical.top,
                        minLines: 3,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: _canWriteComments(state, task)
                              ? 'Comments'
                              : 'Only task creator and task assignees can add comments',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.all(12),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingTableComments)
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ..._singularCommentTiles(context, state),
                      const SizedBox(height: 24),
                      if (_isCreator(state, task) ||
                          _isPicEffective(state, task))
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () async {
                                  if (_isCreator(state, task)) {
                                    await _saveTaskFields(state, task);
                                  } else {
                                    await _saveTaskAttachmentsOnly(
                                      state,
                                      task,
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(_saving ? 'Saving…' : 'Update'),
                        ),
                      if (_isCommentOnlyAssignee(state, task)) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _postCommentOnly(state, task),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(_saving ? 'Saving…' : 'Update'),
                        ),
                      ],
                      if (_isPicEffective(state, task) &&
                          _canPicSubmit(task)) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => _submitForReview(state, task),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
                      if (_isCreator(state, task) &&
                          (task.submission?.trim() == 'Submitted')) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _acceptSubmission(state, task),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  backgroundColor: const Color(0xFF298A00),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Accept'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving
                                    ? null
                                    : () => _returnSubmission(state, task),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  backgroundColor: const Color(0xFF0B0094),
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Return'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (_canMarkTaskDeleted(state))
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _confirmMarkSingularTaskDeleted(
                                  state,
                                  task,
                                ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            foregroundColor: Colors.red.shade800,
                          ),
                        ),
                      const SizedBox(height: 24),
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () {
                                Navigator.of(context).popUntil(
                                  (route) => route.isFirst,
                                );
                              },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back to home'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_saving)
            Positioned.fill(
              child: IgnorePointer(
                child: Material(
                  color: Colors.black.withOpacity(0.12),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Legacy [`tasks`] table row UI (Planner-style).
class _LegacyTaskDetailView extends StatefulWidget {
  final String taskId;
  final String? commentAuthorAssigneeId;

  const _LegacyTaskDetailView({
    required this.taskId,
    this.commentAuthorAssigneeId,
  });

  @override
  State<_LegacyTaskDetailView> createState() => _LegacyTaskDetailViewState();
}

class _LegacyTaskDetailViewState extends State<_LegacyTaskDetailView> {
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final task = state.taskById(widget.taskId);
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('Task not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(task.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _Chip(label: priorityToDisplayName(task.priority)),
                        if (task.teamId == null)
                          _Chip(label: '${task.progressPercent}%'),
                        _Chip(
                          label:
                              taskStatusDisplayNames[task.status] ?? 'Unknown',
                          color: _statusColor(task.status),
                        ),
                        if (task.startDate != null)
                          _Chip(
                            label:
                                'Start ${DateFormat('yyyy-MM-dd').format(task.startDate!)}',
                          ),
                        if (task.endDate != null)
                          _Chip(
                            label:
                                'End ${DateFormat('yyyy-MM-dd').format(task.endDate!)}',
                            color: task.isOverdue ? Colors.red.shade100 : null,
                          ),
                        if (task.assigneeIds.isNotEmpty)
                          ...task.assigneeIds.map((id) {
                            final a = state.assigneeById(id);
                            return _Chip(label: a?.name ?? id);
                          }),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: TaskStatus.values.map((s) {
                final selected = task.status == s;
                return FilterChip(
                  label: Text(taskStatusDisplayNames[s]!),
                  selected: selected,
                  onSelected: (_) => state.updateTaskStatus(widget.taskId, s),
                );
              }).toList(),
            ),
            if (task.teamId != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _confirmDeleteTask(context, state, task),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete task'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (task.teamId == null) ...[
              const SizedBox(height: 16),
              const Text(
                'Progress & milestones',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: task.progressPercent / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Slider(
                value: task.progressPercent.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                label: '${task.progressPercent}%',
                onChanged: (v) {
                  state.updateTaskProgress(widget.taskId, v.round());
                },
              ),
              if (task.milestones.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...task.milestones.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: m.progressPercent / 100,
                            backgroundColor: Colors.grey.shade300,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${m.label} ${m.progressPercent}%'),
                      ],
                    ),
                  ),
                ),
              ],
              ElevatedButton.icon(
                onPressed: () => _showAddMilestone(context, state),
                icon: const Icon(Icons.add),
                label: const Text('Add milestone'),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Comments / progress updates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: const InputDecoration(
                hintText: 'Add a comment or progress update...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _addComment(context, state, task),
              child: const Text('Update'),
            ),
            const SizedBox(height: 16),
            ...task.comments.map((c) {
              final canEdit =
                  DateTime.now().difference(c.createdAt) <
                  const Duration(hours: 1);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: SelectableText(c.body),
                  subtitle: Text(
                    '${c.authorName} · ${DateFormat.yMMMd().add_Hm().format(c.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: canEdit
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  _editCommentLegacy(context, state, c),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  _deleteCommentLegacy(context, state, c),
                              tooltip: 'Delete',
                            ),
                          ],
                        )
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteTask(BuildContext context, AppState state, Task task) {
    final deletedByName = task.assigneeIds.isNotEmpty
        ? (state.assigneeById(task.assigneeIds.first)?.name ??
              'Responsible Officer')
        : 'Director';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task'),
        content: Text(
          'Delete "${task.name}"? It will be moved to the deleted tasks audit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              state.deleteTask(task.id, deletedByName);
              Navigator.pop(ctx);
              Navigator.pop(context);
              showCopyableSnackBar(context, 'Task deleted');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addComment(BuildContext context, AppState state, Task task) {
    final body = _commentController.text.trim();
    if (body.isEmpty) return;
    if (task.assigneeIds.isEmpty) return;
    final authorId = widget.commentAuthorAssigneeId ?? task.assigneeIds.first;
    if (!task.assigneeIds.contains(authorId)) return;
    final author = state.assigneeById(authorId);
    state.addComment(
      taskId: widget.taskId,
      authorId: authorId,
      authorName: author?.name ?? authorId,
      body: body,
    );
    _commentController.clear();
    showCopyableSnackBar(context, 'Comment added');
  }

  void _showAddMilestone(BuildContext context, AppState state) {
    final labelController = TextEditingController();
    int percent = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add milestone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 16),
              Text('Progress: $percent%'),
              Slider(
                value: percent.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                onChanged: (v) => setDialogState(() => percent = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (labelController.text.trim().isEmpty) return;
                state.addMilestone(
                  taskId: widget.taskId,
                  label: labelController.text.trim(),
                  progressPercent: percent,
                );
                Navigator.pop(ctx);
                showCopyableSnackBar(context, 'Milestone added');
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _editCommentLegacy(BuildContext context, AppState state, TaskComment c) {
    final controller = TextEditingController(text: c.body);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit update/ comment'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newBody = controller.text.trim();
              if (newBody.isNotEmpty) state.updateComment(c.id, newBody);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteCommentLegacy(
    BuildContext context,
    AppState state,
    TaskComment c,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete update/ comment'),
        content: const Text('Remove this update/ comment?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              state.deleteComment(c.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Color? _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.todo:
        return Colors.grey.shade200;
      case TaskStatus.inProgress:
        return Colors.blue.shade100;
      case TaskStatus.done:
        return Colors.green.shade100;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;

  const _Chip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), backgroundColor: color);
  }
}
