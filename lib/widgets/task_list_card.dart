import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/task.dart';
import '../priority.dart';
import '../services/supabase_service.dart';
import '../screens/task_detail_screen.dart';

/// PIC team colour definition (`staff.team_id` / `team.team_id` business keys).
class PicTeamColorEntry {
  const PicTeamColorEntry({
    required this.teamKey,
    required this.color,
    required this.legendLabel,
  });

  final String teamKey;
  final Color color;
  final String legendLabel;
}

/// Ordered list for [TaskListCard.cardColorForPicTeam] and [PicTeamColorLegend].
const List<PicTeamColorEntry> kPicTeamColorEntries = [
  PicTeamColorEntry(
    teamKey: 'advancement_intel',
    color: Color(0xFFFFFBE8),
    legendLabel: 'Advancement Intelligence',
  ),
  PicTeamColorEntry(
    teamKey: 'president_office',
    color: Color(0xFFFEE8FF),
    legendLabel: 'President Office',
  ),
  PicTeamColorEntry(
    teamKey: 'fundraising',
    color: Color(0xFFE8FDFF),
    legendLabel: 'Fundraising',
  ),
  PicTeamColorEntry(
    teamKey: 'alumni',
    color: Color(0xFFEEFFD4),
    legendLabel: 'Alumni',
  ),
  PicTeamColorEntry(
    teamKey: 'admin_team',
    color: Color(0xFFFFE9E3),
    legendLabel: 'Admin',
  ),
];

/// Legend for Home / Tasks: explains PIC team background colours on [TaskListCard].
class PicTeamColorLegend extends StatelessWidget {
  const PicTeamColorLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Task background colour reflects the PIC’s team.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          children: [
            for (final e in kPicTeamColorEntries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: e.color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.35),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    e.legendLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Task row for list tabs: name, assignees, status, start/due dates (matches singular + legacy tasks).
class TaskListCard extends StatelessWidget {
  const TaskListCard({super.key, required this.task});

  final Task task;

  /// Background tint from PIC's [`staff.team_id`] / [`team.team_id`] (home / initiative task lists).
  static Color? cardColorForPicTeam(String? teamBusinessId) {
    final t = teamBusinessId?.trim().toLowerCase();
    if (t == null || t.isEmpty) return null;
    for (final e in kPicTeamColorEntries) {
      if (e.teamKey == t) return e.color;
    }
    return null;
  }

  static String statusLabel(Task t) {
    if (t.isSingularTableRow) {
      final raw = t.dbStatus?.trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return taskStatusDisplayNames[t.status] ?? '';
  }

  static bool _isSubmissionSubmitted(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'submitted';
  }

  static bool _isSubmissionAccepted(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'accepted';
  }

  static bool _isSubmissionReturned(Task t) {
    final s = t.submission?.trim().toLowerCase() ?? '';
    return s == 'returned';
  }

  static const Color _kAcceptedTagColor = Color(0xFF298A00);
  static const Color _kReturnedTagColor = Color(0xFF0B0094);

  static Widget _submissionBadge(String label, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Same colours as the submission chips on the home task list ([_submissionBadge]).
  /// Returns `null` if [submission] is empty.
  static Widget? buildSubmissionTag(String? submission) {
    final raw = submission?.trim() ?? '';
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == 'submitted') {
      return _submissionBadge('Submitted', Colors.red);
    }
    if (lower == 'accepted') {
      return _submissionBadge('Accepted', _kAcceptedTagColor);
    }
    if (lower == 'returned') {
      return _submissionBadge('Returned', _kReturnedTagColor);
    }
    if (lower == 'pending') {
      return _submissionBadge('Pending', Colors.grey.shade700);
    }
    return _submissionBadge(raw, Colors.grey.shade600);
  }

  static const Color _kOverPresetTimelineColor = Color(0xFFFFCD05);

  /// Tag when extend-timeline reason exists (list cards; no raw reason text).
  static Widget buildOverPresetTimelineTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _kOverPresetTimelineColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Over preset timeline',
        style: TextStyle(
          color: Color(0xFF1A1A1A),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final t = task;
    final picKey = t.pic?.trim();
    final nameLookupKeys = <String>{
      ...t.assigneeIds,
      if (picKey != null && picKey.isNotEmpty) picKey,
    }.toList();
    return FutureBuilder<(Map<String, String>, String?)>(
      future: () async {
        final names = await SupabaseService.staffDisplayNamesForKeys(nameLookupKeys);
        final picTeam =
            await SupabaseService.fetchStaffTeamBusinessIdForAssigneeKey(picKey);
        return (names, picTeam);
      }(),
      builder: (context, snapshot) {
        final nameMap = snapshot.data?.$1 ?? {};
        final picTeamId = snapshot.data?.$2;
        final officerNames = t.assigneeIds
            .map((id) => nameMap[id] ?? state.assigneeById(id)?.name ?? id)
            .toList()
          ..sort();
        final showPicLine = t.assigneeIds.length > 1 &&
            picKey != null &&
            picKey.isNotEmpty;
        final pk = picKey;
        final cardTint = cardColorForPicTeam(picTeamId);
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: cardTint,
          child: ListTile(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        t.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_isSubmissionSubmitted(t)) ...[
                      const SizedBox(width: 8),
                      _submissionBadge('Submitted', Colors.red),
                    ],
                    if (_isSubmissionAccepted(t)) ...[
                      const SizedBox(width: 8),
                      _submissionBadge('Accepted', _kAcceptedTagColor),
                    ],
                    if (_isSubmissionReturned(t)) ...[
                      const SizedBox(width: 8),
                      _submissionBadge('Returned', _kReturnedTagColor),
                    ],
                  ],
                ),
                if ((t.changeDueReason ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: buildOverPresetTimelineTag(),
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (officerNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Assignee(s): ${officerNames.join(', ')}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                if (showPicLine && pk != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'PIC: ${nameMap[pk] ?? state.assigneeById(pk)?.name ?? pk}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ),
                if (t.createByStaffName != null &&
                    t.createByStaffName!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Creator: ${t.createByStaffName!.trim()}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                Text(
                  '${priorityToDisplayName(t.priority)} · ${statusLabel(t)}'
                  '${t.startDate != null ? ' · Start ${DateFormat.yMMMd().format(t.startDate!)}' : ''}'
                  '${t.endDate != null ? ' · Due ${DateFormat.yMMMd().format(t.endDate!)}' : ''}',
                ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TaskDetailScreen(taskId: t.id),
              ),
            ),
          ),
        );
      },
    );
  }
}
