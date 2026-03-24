/// Result of revamp step 1: staff row + optional team (by email login).
class StaffTeamLookupResult {
  const StaffTeamLookupResult({
    required this.loginEmail,
    this.appId,
    this.staffTeamIdRaw,
    this.teamName,
    this.staffEmailFromDb,
    this.errorMessage,
  });

  final String loginEmail;
  final String? appId;
  /// Value from `staff.team_id` (may match `team.id` or `team.app_id`).
  final String? staffTeamIdRaw;
  final String? teamName;
  /// `staff.email` from the matched row (for verification vs login email).
  final String? staffEmailFromDb;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null && appId != null;

  /// Plain text for clipboard / selection.
  String get copyableSummary {
    final buf = StringBuffer()
      ..writeln('Login email: $loginEmail')
      ..writeln('staff.email (DB): ${staffEmailFromDb ?? "(null)"}')
      ..writeln('staff.app_id: ${appId ?? "(null)"}')
      ..writeln('staff.team_id: ${staffTeamIdRaw ?? "(null)"}')
      ..writeln('team name: ${teamName ?? "(null)"}');
    if (errorMessage != null) {
      buf.writeln('Lookup error: $errorMessage');
    }
    return buf.toString().trim();
  }
}
