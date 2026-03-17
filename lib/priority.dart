/// Priority levels: 1 = Standard, 2 = Urgent (two levels only).
const Map<int, String> priorityDisplayNames = {
  1: 'Standard',
  2: 'Urgent',
};

/// Order for UI: Urgent, Standard.
const List<int> priorityOptions = [2, 1];

String priorityToDisplayName(int priority) {
  return priorityDisplayNames[priority.clamp(1, 2)] ?? 'Standard';
}

/// Urgent = 2, Standard = 1.
int get priorityUrgent => 2;
int get priorityStandard => 1;
