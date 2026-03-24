import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/staff_team_lookup.dart';

/// Revamp step 1: match logged-in email to [staff], then resolve [team] by
/// **staff.team_id = team.team_id** (same as `LEFT JOIN team ON …`).
///
/// Requires Supabase RLS to allow `anon` SELECT on `staff` and `team` (or use
/// authenticated role — adjust policies in Supabase).
class StaffTeamLookupService {
  StaffTeamLookupService._();

  static Future<StaffTeamLookupResult> lookupByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      return StaffTeamLookupResult(
        loginEmail: email,
        errorMessage: 'Empty email',
      );
    }
    if (!SupabaseConfig.isConfigured) {
      return StaffTeamLookupResult(
        loginEmail: normalized,
        errorMessage: 'Supabase not configured',
      );
    }

    try {
      final supabase = Supabase.instance.client;
      final staffRes = await supabase
          .from('staff')
          .select('app_id, team_id, email')
          .ilike('email', normalized)
          .limit(1)
          .maybeSingle();

      if (staffRes == null) {
        return StaffTeamLookupResult(
          loginEmail: normalized,
          errorMessage: 'No row in staff where email matches login (ilike)',
        );
      }

      final appId = staffRes['app_id'] as String?;
      final teamIdRaw = staffRes['team_id'];
      final staffEmailFromDb = staffRes['email'] as String?;

      String? teamName;
      if (teamIdRaw != null && teamIdRaw.toString().isNotEmpty) {
        final tid = teamIdRaw.toString().trim();
        // LEFT JOIN team ON staff.team_id = team.team_id
        final teamRow = await supabase
            .from('team')
            .select('team_name')
            .eq('team_id', tid)
            .maybeSingle();
        if (teamRow != null) {
          teamName = teamRow['team_name'] as String?;
        }
      }

      return StaffTeamLookupResult(
        loginEmail: normalized,
        appId: appId,
        staffTeamIdRaw: teamIdRaw?.toString(),
        teamName: teamName,
        staffEmailFromDb: staffEmailFromDb,
      );
    } catch (e) {
      return StaffTeamLookupResult(
        loginEmail: normalized,
        errorMessage: e.toString(),
      );
    }
  }
}
