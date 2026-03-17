/// A team with hierarchy: Directors (supervisor level) and Responsible Officers (executive level).
class Team {
  final String id;
  final String name;
  /// Director-level assignees (e.g. Alumni: Monica Wong; Fundraising: May Wong, Olive Wong, Janice Chan).
  final List<String> directorIds;
  /// Responsible Officers (executive level). To be provided per team; empty placeholder until then.
  final List<String> officerIds;

  const Team({
    required this.id,
    required this.name,
    required this.directorIds,
    required this.officerIds,
  });

  /// All member IDs (directors + officers) for backward compatibility.
  List<String> get assigneeIds => [...directorIds, ...officerIds];
}
