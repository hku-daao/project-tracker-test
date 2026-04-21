import 'package:flutter/material.dart';

import '../utils/subtask_list_sort.dart';
import 'subtask_meta_line.dart';

/// Popup chip: Ascending / Descending / Clear — matches landing [TaskListCard] sub-task sort.
class SubtaskSortColumnChip extends StatelessWidget {
  const SubtaskSortColumnChip({
    super.key,
    required this.column,
    required this.active,
    required this.ascending,
    required this.onMenuSelected,
  });

  final SubtaskListSortColumn column;
  final bool active;
  final bool ascending;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipLabelStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
      fontSize: kLandingListCardFontSize,
      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        tooltip: 'Sort by ${subtaskListSortColumnLabel(column)}',
        onSelected: onMenuSelected,
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'asc', child: Text('Ascending')),
          const PopupMenuItem(value: 'desc', child: Text('Descending')),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'clear',
            enabled: active,
            child: const Text('Clear sort'),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                subtaskListSortColumnLabel(column),
                maxLines: 1,
                softWrap: false,
                style: chipLabelStyle,
              ),
              if (active) ...[
                const SizedBox(width: 4),
                Icon(
                  ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
