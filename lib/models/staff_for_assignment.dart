/// Row from `team` for assignee filtering (join key: [teamId] == [StaffForAssignment.teamId]).
class TeamOptionRow {
  const TeamOptionRow({
    required this.teamId,
    required this.teamName,
  });

  final String teamId;
  final String teamName;
}

/// Minimal row for picking staff by primary key (`staff.id`).
class StaffListRow {
  const StaffListRow({required this.id, required this.name});

  final String id;
  final String name;
}

/// Result of loading `team` + `staff` for the assignee picker (join: `staff.team_id` = `team.team_id`).
class StaffAssigneePickerData {
  const StaffAssigneePickerData({
    required this.teams,
    required this.staff,
  });

  final List<TeamOptionRow> teams;
  final List<StaffForAssignment> staff;
}

/// Staff row for multi-select assignee UI (`staff` joined to `team` via `team_id`).
class StaffForAssignment {
  const StaffForAssignment({
    required this.assigneeId,
    required this.name,
    this.teamId,
  });

  /// Prefer `staff.app_id`; falls back to `staff.id` string when app_id is null.
  final String assigneeId;
  final String name;
  final String? teamId;
}
