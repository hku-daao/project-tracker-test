import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/task.dart';
import '../../priority.dart';
import '../../services/backend_api.dart';
import '../../services/supabase_service.dart';
import '../../utils/copyable_snackbar.dart';
import '../../utils/home_navigation.dart';
import '../../widgets/flow_navigation_bar.dart';
import '../../utils/due_span_policy.dart';
import '../../utils/hk_time.dart';
import '../../utils/singular_workflow_guards.dart';

/// Warn before leaving [CreateSubtaskScreen] while a draft exists (back button / system back).
Future<bool> _confirmLeaveCreateSubtaskDraft(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved sub-task'),
      content: const Text(
        'Click Create sub-task to save. If you leave now, nothing will be saved.',
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

/// Create a sub-task under a singular [task] (creator only). Layout mirrors [CreateTaskScreen].
class CreateSubtaskScreen extends StatefulWidget {
  const CreateSubtaskScreen({
    super.key,
    required this.taskId,
    this.openedFromOverview = false,
    this.openedFromProjectDetail = false,
  });

  final String taskId;
  final bool openedFromOverview;
  final bool openedFromProjectDetail;

  @override
  State<CreateSubtaskScreen> createState() => _CreateSubtaskScreenState();
}

class _CreateSubtaskScreenState extends State<CreateSubtaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _commentController = TextEditingController();
  final _changeDueReasonController = TextEditingController();

  int _priority = priorityStandard;
  late DateTime _anchorStartDate;
  late DateTime _startDate;
  DateTime? _endDate;
  String? _picKey;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _anchorStartDate = HkTime.todayDateOnlyHk();
    _startDate = _anchorStartDate;
    _endDate = _defaultDueForPriority(_priority);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppState>().setCreateSubtaskDraftChecker(_hasUnsavedDraft);
      final task = context.read<AppState>().taskById(widget.taskId);
      if (task == null) return;
      final ids = task.assigneeIds;
      if (ids.isEmpty) return;
      final pic = task.pic?.trim();
      final picInList =
          pic != null && pic.isNotEmpty && ids.contains(pic) ? pic : null;
      if (ids.length == 1) {
        setState(() => _picKey = ids.first);
      } else {
        setState(() => _picKey = picInList ?? ids.first);
      }
    });
  }

  @override
  void dispose() {
    context.read<AppState>().setCreateSubtaskDraftChecker(null);
    _nameController.dispose();
    _descController.dispose();
    _commentController.dispose();
    _changeDueReasonController.dispose();
    super.dispose();
  }

  /// True if the user changed anything from the empty defaults (mirrors [CreateTaskScreen._hasUnsavedDraft]).
  bool _hasUnsavedDraft() {
    if (_submitting) return false;
    if (_nameController.text.trim().isNotEmpty) return true;
    if (_descController.text.trim().isNotEmpty) return true;
    if (_commentController.text.trim().isNotEmpty) return true;
    if (_priority != priorityStandard) return true;
    if (_dateOnlyCompare(_startDate, _anchorStartDate) != 0) return true;
    final expectedDue = _defaultDueForPriority(_priority);
    if (_endDate != null && _dateOnlyCompare(_endDate!, expectedDue) != 0) {
      return true;
    }
    if (_changeDueReasonController.text.trim().isNotEmpty) return true;
    return false;
  }

  bool _needsChangeDueReason() {
    return dueDateExceedsPolicyForPriority(
      _startDate,
      _endDate,
      _priority,
    );
  }

  Future<void> _handlePopRequest() async {
    if (!_hasUnsavedDraft()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final leave = await _confirmLeaveCreateSubtaskDraft(context);
    if (mounted && leave) Navigator.of(context).pop();
  }

  Future<void> _flowHome() async {
    if (_submitting) return;
    if (_hasUnsavedDraft()) {
      final leave = await _confirmLeaveCreateSubtaskDraft(context);
      if (!mounted || !leave) return;
    }
    await navigateToPinnedHomeFromDrawer(context);
  }

  Future<void> _flowBack() async {
    await _handlePopRequest();
  }

  DateTime _defaultDueForPriority(int priority) {
    final workingDaysAfter = priority == priorityUrgent ? 1 : 3;
    return HkTime.addWorkingDaysAfter(_startDate, workingDaysAfter);
  }

  static int _dateOnlyCompare(DateTime a, DateTime b) {
    final da = DateTime(a.year, a.month, a.day);
    final db = DateTime(b.year, b.month, b.day);
    return da.compareTo(db);
  }

  String _labelForKey(String id, AppState state) {
    return state.assigneeById(id)?.name ?? id;
  }

  Future<void> _submit(AppState state, Task task) async {
    if (!_formKey.currentState!.validate()) return;
    if (!task.isSingularTableRow) {
      showCopyableSnackBar(context, 'Sub-tasks are only for cloud tasks');
      return;
    }
    if (singularTaskStatusIsCompleted(task)) {
      showCopyableSnackBar(
        context,
        'Cannot create sub-tasks while the task is completed.',
        backgroundColor: Colors.orange,
      );
      return;
    }
    final assigneeIds = task.assigneeIds;
    if (assigneeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text('Parent task has no assignees'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final picK = _picKey ??
        (assigneeIds.length == 1 ? assigneeIds.first : null);
    if (picK == null || picK.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text('Select a Sub-task PIC'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (!task.assigneeIds.contains(picK)) {
      showCopyableSnackBar(context, 'PIC must be a task assignee');
      return;
    }
    final due = _endDate;
    if (due != null && _dateOnlyCompare(due, _startDate) < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text('Due date cannot be before start date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final needsDueReason = dueDateExceedsPolicyForPriority(
      _startDate,
      due,
      _priority,
    );
    if (needsDueReason && _changeDueReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(duration: const Duration(seconds: 4), content: Text(
            'Enter a reason when the due date is beyond the allowed working days for this priority',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final slots = <String?>[];
      for (final aid in assigneeIds.take(10)) {
        final u = await SupabaseService.staffRowIdForAssigneeKey(aid);
        if (u == null || u.isEmpty) {
          showCopyableSnackBar(
            context,
            'Could not resolve staff id for task assignee',
            backgroundColor: Colors.orange,
          );
          return;
        }
        slots.add(u);
      }
      while (slots.length < 10) {
        slots.add(null);
      }
      final picUuid = await SupabaseService.staffRowIdForAssigneeKey(picK);
      if (picUuid == null || picUuid.isEmpty) {
        showCopyableSnackBar(
          context,
          'Could not resolve staff id for PIC',
          backgroundColor: Colors.orange,
        );
        return;
      }
      final ins = await SupabaseService.insertSubtaskRow(
        taskId: widget.taskId,
        subtaskName: _nameController.text.trim(),
        description: _descController.text.trim(),
        priorityDisplay: priorityToDisplayName(_priority),
        startDate: _startDate,
        dueDate: due,
        assigneeStaffUuids: slots,
        picStaffUuid: picUuid,
        creatorStaffLookupKey: state.userStaffAppId,
        initialComment: _commentController.text.trim(),
        changeDueReason:
            needsDueReason ? _changeDueReasonController.text.trim() : null,
      );
      if (ins.error != null || ins.subtaskId == null) {
        showCopyableSnackBar(
          context,
          ins.error ?? 'Create failed',
          backgroundColor: Colors.orange,
        );
        return;
      }
      try {
        final token = await FirebaseAuth.instance.currentUser?.getIdToken();
        if (token != null) {
          final ne = await BackendApi().notifySubtaskAssigned(
            idToken: token,
            subtaskId: ins.subtaskId!,
          );
          if (ne != null && mounted) {
            final short = ne.length > 120 ? '${ne.substring(0, 120)}…' : ne;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Notification: $short'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: const Text('Sub-task is created'),
          backgroundColor: Colors.green,
        ),
      );
      SupabaseService.invalidateSubtasksCacheForTask(widget.taskId);
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final task = state.taskById(widget.taskId);

    if (task == null || !task.isSingularTableRow) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create sub-task')),
        body: const Center(child: Text('Task not found')),
      );
    }

    final assigneeIds = task.assigneeIds;
    final multi = assigneeIds.length > 1;
    final taskAssigneeNames = assigneeIds
        .map((id) => _labelForKey(id, state))
        .join(', ');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handlePopRequest();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Create sub-task'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Stack(
        children: [
          AbsorbPointer(
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
                      Text(
                        'Project: ${task.projectName?.trim().isNotEmpty == true ? task.projectName!.trim() : '—'}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Parent: ${task.name}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Assignee(s): ${taskAssigneeNames.isNotEmpty ? taskAssigneeNames : "—"}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      if (multi) ...[
                        DropdownButtonFormField<String>(
                          value: _picKey != null && assigneeIds.contains(_picKey)
                              ? _picKey
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Sub-task PIC',
                            border: OutlineInputBorder(),
                          ),
                          items: assigneeIds
                              .map(
                                (id) => DropdownMenuItem(
                                  value: id,
                                  child: Text(_labelForKey(id, state)),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _picKey = v),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Sub-task name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Priority',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: priorityOptions.map((p) {
                          final selected = _priority == p;
                          return FilterChip(
                            label: Text(priorityToDisplayName(p)),
                            selected: selected,
                            onSelected: _submitting
                                ? null
                                : (v) {
                                    if (!v) return;
                                    setState(() {
                                      _priority = p;
                                      _endDate = _defaultDueForPriority(p);
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Start date',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _submitting
                                ? null
                                : () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: _startDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 365 * 10),
                                      ),
                                    );
                                    if (d != null) {
                                      setState(() {
                                        _startDate = d;
                                        _endDate = _defaultDueForPriority(
                                          _priority,
                                        );
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.calendar_today),
                            label: const Text('Pick'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            'Due date',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '*',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _endDate != null
                                ? '${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}'
                                : 'Not set',
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: _submitting
                                ? null
                                : () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      initialDate: _endDate ??
                                          HkTime.addWorkingDaysAfter(
                                            _startDate,
                                            1,
                                          ),
                                      firstDate: _startDate,
                                      lastDate: DateTime.now().add(
                                        const Duration(days: 365 * 10),
                                      ),
                                    );
                                    if (d != null) {
                                      setState(() => _endDate = d);
                                    }
                                  },
                            icon: const Icon(Icons.calendar_today),
                            label: const Text('Pick'),
                          ),
                        ],
                      ),
                      if (_needsChangeDueReason()) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _changeDueReasonController,
                          readOnly: _submitting,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Reason',
                            hintText: 'Extend timeline reason',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                          validator: (v) {
                            if (!_needsChangeDueReason()) return null;
                            if (v == null || v.trim().isEmpty) {
                              return 'Required when due date exceeds allowed working days';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 4,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _commentController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Comment',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed:
                            !SupabaseConfig.isConfigured || _submitting
                                ? null
                                : () => _submit(state, task),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _submitting ? 'Creating…' : 'Create sub-task',
                          ),
                        ),
                      ),
                    ],
                    ),
                  ),
                ),
              ),
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
    );
  }
}
