/// Represents a reminder that would be sent to Directors (for display/scheduling).
class PendingReminder {
  final String itemName;
  final List<String> recipientNames;
  final String reminderType; // 'Urgent (daily)' or 'Standard (2 days before due)'
  final bool isInitiative;

  const PendingReminder({
    required this.itemName,
    required this.recipientNames,
    required this.reminderType,
    this.isInitiative = true,
  });
}
