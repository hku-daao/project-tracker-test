import 'package:flutter/material.dart';

import '../models/singular_subtask.dart';
import 'subtask_meta_line.dart';
import 'task_list_card.dart';

/// List row matching the sub-task [Card] on [TaskDetailScreen].
class SingularSubtaskRowCard extends StatelessWidget {
  const SingularSubtaskRowCard({
    super.key,
    required this.subtask,
    required this.resolveName,
    this.onTap,
    /// Matches [TaskListCard] outer spacing when aligned as sibling rows (e.g. Customized page).
    this.cardMargin = const EdgeInsets.only(bottom: 8),
    /// Same PIC team tint as [TaskListCard] when set.
    this.cardBackgroundColor,
    /// Customized: **Sub-task:** + name, **Parent:** line, **Creator:** line.
    this.showCustomizedLayout = false,
    this.parentTaskName,
    this.parentProjectName,
    /// Overview flat list: `yyyy-MM-dd` from sub-task update vs comment activity.
    this.overviewLastUpdatedYmd,
    /// Overview **All tasks & sub-tasks** tab: S badge; hide assignees and project lines.
    this.overviewAllTabStyling = false,
  });

  final SingularSubtask subtask;
  final String Function(String assigneeKey) resolveName;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry cardMargin;
  final Color? cardBackgroundColor;
  final bool showCustomizedLayout;
  final String? parentTaskName;
  final String? parentProjectName;
  final String? overviewLastUpdatedYmd;
  final bool overviewAllTabStyling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body14 = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: kLandingListCardFontSize);
    final titleStyle = body14.copyWith(fontWeight: FontWeight.bold);
    final secondaryStyle = body14.copyWith(fontWeight: FontWeight.w500);
    final s = subtask;
    final assigneeNamesLine = s.assigneeNamesDisplayLine(resolveName);
    final picLine = s.picDisplayName(resolveName);
    final creatorLine =
        (s.createByStaffName ?? '').trim().isEmpty ? '—' : s.createByStaffName!.trim();
    final subTag = (s.submission?.trim().toLowerCase() == 'pending')
        ? null
        : TaskListCard.buildSubmissionTag(s.submission);
    final showOverPreset = (s.changeDueReason ?? '').trim().isNotEmpty;

    final titleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: showCustomizedLayout
                  ? (overviewAllTabStyling
                      ? Text(
                          s.subtaskName,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        )
                      : Text.rich(
                          TextSpan(
                            style: body14,
                            children: [
                              const TextSpan(text: 'Sub-task: '),
                              TextSpan(
                                text: s.subtaskName,
                                style: titleStyle,
                              ),
                            ],
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ))
                  : Text(
                      s.subtaskName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
            ),
            if (subTag != null) ...[
              const SizedBox(width: 8),
              subTag,
            ],
          ],
        ),
        if (showCustomizedLayout &&
            (parentTaskName != null && parentTaskName!.trim().isNotEmpty)) ...[
          const SizedBox(height: 4),
          Text(
            'Parent: ${parentTaskName!.trim()}',
            style: secondaryStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (!overviewAllTabStyling &&
            showCustomizedLayout &&
            (parentProjectName != null &&
                parentProjectName!.trim().isNotEmpty)) ...[
          const SizedBox(height: 4),
          Text(
            'Project: ${parentProjectName!.trim()}',
            style: secondaryStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (showOverPreset) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TaskListCard.buildOverPresetTimelineTag(),
          ),
        ],
      ],
    );

    final subtitleColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!overviewAllTabStyling)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              'Assignee(s): $assigneeNamesLine',
              style: secondaryStyle,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            'PIC: $picLine',
            style: secondaryStyle,
          ),
        ),
        if (showCustomizedLayout)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Creator: $creatorLine',
              style: secondaryStyle,
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SubtaskMetaLine(
            subtask: s,
            overviewLastUpdatedYmd: overviewLastUpdatedYmd,
          ),
        ),
      ],
    );

    if (overviewAllTabStyling) {
      return Card(
        margin: cardMargin,
        color: cardBackgroundColor,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    'S',
                    style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSecondaryContainer,
                          fontSize: 13,
                        ) ??
                        TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      titleColumn,
                      const SizedBox(height: 4),
                      subtitleColumn,
                    ],
                  ),
                ),
                if (onTap != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 4, top: 4),
                    child: Icon(Icons.chevron_right),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      margin: cardMargin,
      color: cardBackgroundColor,
      child: ListTile(
        title: titleColumn,
        subtitle: subtitleColumn,
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
