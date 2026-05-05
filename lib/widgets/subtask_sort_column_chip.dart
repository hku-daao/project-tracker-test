import 'package:flutter/material.dart';

import '../utils/subtask_list_sort.dart';

/// Dropdown + direction toggle for sub-task lists (landing task cards, task detail).
class SubtaskSortDropdown extends StatelessWidget {
  const SubtaskSortDropdown({
    super.key,
    required this.sortColumn,
    required this.ascending,
    required this.onSortColumnChanged,
    required this.onToggleAscending,
    required this.sortLabelStyle,
  });

  final SubtaskListSortColumn? sortColumn;
  final bool ascending;
  final ValueChanged<SubtaskListSortColumn?> onSortColumnChanged;
  final VoidCallback onToggleAscending;
  final TextStyle sortLabelStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasColumn = sortColumn != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text('Sort', style: sortLabelStyle),
        ),
        IntrinsicWidth(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasColumn
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: DropdownButton<SubtaskListSortColumn?>(
              value: sortColumn,
              isDense: true,
              isExpanded: false,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(8),
              style: theme.textTheme.labelLarge,
              items: [
                DropdownMenuItem<SubtaskListSortColumn?>(
                  value: null,
                  child: Text(
                    'Created date (default)',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: sortColumn == null
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
                for (final c in SubtaskListSortColumn.values)
                  DropdownMenuItem<SubtaskListSortColumn?>(
                    value: c,
                    child: Text(
                      subtaskListSortColumnLabel(c),
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight:
                            sortColumn == c ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
              onChanged: onSortColumnChanged,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Tooltip(
          message: sortColumn == null
              ? (ascending
                  ? 'Created date: oldest first — tap for newest first'
                  : 'Created date: newest first — tap for oldest first')
              : (ascending
                  ? 'Ascending — tap for descending'
                  : 'Descending — tap for ascending'),
          child: IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            icon: Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            onPressed: onToggleAscending,
          ),
        ),
      ],
    );
  }
}
