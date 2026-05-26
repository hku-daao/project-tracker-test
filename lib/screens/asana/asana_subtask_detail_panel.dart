import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/supabase_config.dart';
import '../../models/singular_subtask.dart';
import '../../priority.dart';
import '../../services/supabase_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';

/// Asana slide panel for a sub-task (read-focused, Inter styling).
class AsanaSubtaskDetailPanel extends StatefulWidget {
  const AsanaSubtaskDetailPanel({
    super.key,
    required this.subtaskId,
    required this.palette,
  });

  final String subtaskId;
  final AsanaLandingPalette palette;

  @override
  State<AsanaSubtaskDetailPanel> createState() => _AsanaSubtaskDetailPanelState();
}

class _AsanaSubtaskDetailPanelState extends State<AsanaSubtaskDetailPanel> {
  SingularSubtask? _subtask;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AsanaSubtaskDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subtaskId != widget.subtaskId) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    if (SupabaseConfig.isConfigured) {
      final row = await SupabaseService.fetchSubtaskById(widget.subtaskId);
      if (mounted) setState(() => _subtask = row);
    }
    if (mounted) setState(() => _loading = false);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.expand(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final s = _subtask;
    if (s == null) {
      return const SizedBox.expand(
        child: Center(child: Text('Sub-task not found')),
      );
    }
    final state = context.watch<AppState>();
    final parent = state.taskById(s.taskId);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.subtaskName.trim().isEmpty ? '(Unnamed sub-task)' : s.subtaskName.trim(),
            style: asanaDetailTitleStyle(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          AsanaDetailLabelValue(
            label: 'Description',
            child: Text(
              s.description.trim(),
              style: asanaDetailMultilineValueStyle(context),
            ),
          ),
          if (parent != null)
            AsanaDetailTwoColumnRow(
              label: 'Parent task',
              child: AsanaDetailPlainValue(text: parent.name.trim()),
            ),
          AsanaDetailTwoColumnRow(
            label: 'Creator',
            child: AsanaDetailPlainValue(text: s.createByStaffName?.trim() ?? ''),
          ),
          AsanaDetailTwoColumnRow(
            label: 'PIC',
            child: AsanaDetailPlainValue(
              text: s.picDisplayName((k) => _nameFor(state, k)),
            ),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Assignees',
            child: AsanaDetailPlainValue(
              text: s.assigneeIds
                  .map((id) => _nameFor(state, id))
                  .where((n) => n.isNotEmpty)
                  .join(', '),
            ),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Priority',
            child: AsanaDetailPlainValue(text: priorityToDisplayName(s.priority)),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Status',
            child: AsanaDetailStatusPill(status: s.status),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Start date',
            child: AsanaDetailPlainValue(text: _date(s.startDate)),
          ),
          AsanaDetailTwoColumnRow(
            label: 'Due date',
            child: AsanaDetailPlainValue(text: _date(s.dueDate)),
          ),
          if ((s.changeDueReason ?? '').trim().isNotEmpty)
            AsanaDetailLabelValue(
              label: 'Reason',
              child: AsanaDetailPlainValue(text: s.changeDueReason!.trim()),
            ),
          AsanaDetailTwoColumnRow(
            label: 'Submission',
            child: AsanaDetailSubmissionPill(submission: s.submission),
          ),
          if ((s.updateByStaffName ?? '').trim().isNotEmpty)
            AsanaDetailTwoColumnRow(
              label: 'Last updated by',
              child: AsanaDetailPlainValue(text: s.updateByStaffName!.trim()),
            ),
          if (s.lastUpdated != null)
            AsanaDetailTwoColumnRow(
              label: 'Last updated',
              child: AsanaDetailPlainValue(
                text: HkTime.formatInstantAsHk(s.lastUpdated, 'MMM d, yyyy HH:mm'),
              ),
            ),
        ],
      ),
    );
  }
}
