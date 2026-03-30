/// Row from `public."comment"` with resolved staff display name for UI.
class SingularCommentRowDisplay {
  final String id;
  final String description;
  final String status;
  /// `staff.id` uuid from `create_by` (for ownership checks).
  final String? createByStaffId;
  final String displayStaffName;
  final DateTime? createTimestampUtc;
  final DateTime? updateTimestampUtc;

  const SingularCommentRowDisplay({
    required this.id,
    required this.description,
    required this.status,
    this.createByStaffId,
    required this.displayStaffName,
    this.createTimestampUtc,
    this.updateTimestampUtc,
  });

  bool get isDeleted => status.trim().toLowerCase() == 'deleted';
}
