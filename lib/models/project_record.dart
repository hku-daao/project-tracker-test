/// Row from `public.project` (assignee slots store `staff.id` uuid strings).
class ProjectRecord {
  const ProjectRecord({
    required this.id,
    required this.name,
    required this.assigneeStaffUuids,
    this.assigneeStaffDisplayNames = const [],
    this.picStaffUuids = const [],
    this.picStaffDisplayNames = const [],
    required this.description,
    this.startDate,
    this.endDate,
    required this.status,
    this.createByStaffUuid,
    this.createByDisplayName,
    this.createDate,
    this.updateByStaffUuid,
    this.updateByDisplayName,
    this.updateDate,
    this.pauseStatus = 'Not Paused',
  });

  final String id;
  final String name;

  /// Ordered non-empty `staff.id` values from assignee_01...assignee_20.
  final List<String> assigneeStaffUuids;

  /// Resolved assignee names (parallel to [assigneeStaffUuids] when known at fetch).
  final List<String> assigneeStaffDisplayNames;

  /// Ordered non-empty `staff.id` values from pic_01...pic_20 (PICs ⊆ assignees).
  final List<String> picStaffUuids;

  /// Resolved PIC names (parallel to [picStaffUuids] when known at fetch).
  final List<String> picStaffDisplayNames;

  final String description;
  final DateTime? startDate;
  final DateTime? endDate;

  /// `Not started` | `In progress` | `Completed` | `Deleted`
  final String status;

  final String? createByStaffUuid;
  final String? createByDisplayName;
  final DateTime? createDate;

  final String? updateByStaffUuid;
  final String? updateByDisplayName;
  final DateTime? updateDate;

  /// `Paused` | `Not Paused`.
  final String pauseStatus;

  bool get isPaused => pauseStatus.trim().toLowerCase() == 'paused';

  /// True if [staffRowUuid] is project creator, assignee slot, or PIC.
  bool staffMayLinkTasks(String staffRowUuid) {
    final m = staffRowUuid.trim();
    if (m.isEmpty) return false;
    final cb = createByStaffUuid?.trim();
    if (cb != null && cb.isNotEmpty && cb == m) return true;
    for (final u in assigneeStaffUuids) {
      if (u.trim() == m) return true;
    }
    for (final u in picStaffUuids) {
      if (u.trim() == m) return true;
    }
    return false;
  }

  /// Resolved assignee keys (`staff.app_id`) aligned with [assigneeStaffUuids].
  List<String> assigneeKeys(Map<String, String> staffUuidToAppId) {
    final out = <String>[];
    for (final u in assigneeStaffUuids) {
      final k = staffUuidToAppId[u] ?? u;
      if (k.isNotEmpty) out.add(k);
    }
    return out;
  }
}
