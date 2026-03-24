import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config/dev_role_fallback.dart';
import '../config/supabase_config.dart';
import '../services/staff_team_lookup_service.dart';
import 'home_screen.dart';

// Revamp: old backend + legacy Supabase loads are commented in _load(); restore when schema returns.

/// On startup: revamp step 1 loads staff/team by email; legacy initiative/task sync is disabled.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = context.read<AppState>();

    // -------------------------------------------------------------------------
    // REVAMP STEP 1 — Supabase: staff (by email) + team name via staff.team_id
    // -------------------------------------------------------------------------
    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      if (email != null && email.isNotEmpty) {
        final lookup = await StaffTeamLookupService.lookupByEmail(email);
        if (mounted) {
          state.setRevampStaffLookup(lookup);
        }
        // Keep tabs working: role from DevRoleFallback; staffAppId from lookup
        final fbRole = DevRoleFallback.roleForEmail(email.toLowerCase());
        if (mounted) {
          state.setUserProfile(
            role: fbRole ?? 'general',
            staffAppId: lookup.appId,
            assignableStaff: const [],
          );
        }
      }
    } catch (e) {
      debugPrint('AppBootstrap revamp staff/team lookup: $e');
    }

    /*
    // --- LEGACY (commented for revamp): RBAC via Railway + load teams/staff ---
    if (kIsWeb) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        final token = await user?.getIdToken(true);
        if (token != null) {
          var profile = await BackendApi().getMe(token);
          final email = user?.email?.toLowerCase();
          debugPrint('AppBootstrap: email=$email, profile=$profile, profile.role=${profile?.role}');
          final fbRole = DevRoleFallback.roleForEmail(email);
          if (fbRole != null && (profile == null || profile.role == null)) {
            profile = UserProfileResult(
              role: fbRole,
              staffAppId: profile?.staffAppId,
              staffName: profile?.staffName,
              assignableStaff: profile?.assignableStaff ?? [],
            );
          }
          if (profile != null && profile.role != null) {
            if (mounted) {
              state.setUserProfile(
                role: profile.role,
                staffAppId: profile.staffAppId,
                assignableStaff: profile.assignableStaff,
              );
            }
          }
          if (mounted && token != null) {
            await state.loadTeamsAndStaff(token);
          }
        }
      } catch (e) {
        debugPrint('AppBootstrap: Error loading user profile: $e');
      }
      if (!mounted) return;
    }
    */

    // --- LEGACY (commented): load initiatives / tasks / deleted from Supabase ---
    if (!SupabaseConfig.isConfigured) {
      if (mounted) setState(() => _ready = true);
      return;
    }
    /*
    try {
      final initData = await SupabaseService.fetchInitiativesFromSupabase();
      if (!mounted) return;
      if (initData != null) {
        state.applyInitiativesFromSupabase(initData);
      } else {
        setState(() => _error = 'Could not load initiatives from Supabase.');
      }
      final taskData = await SupabaseService.fetchTasksFromSupabase();
      if (!mounted) return;
      if (taskData != null) {
        state.applyTasksFromSupabase(taskData);
      }
      final deletedAudit = await SupabaseService.fetchDeletedTasksFromSupabase();
      if (!mounted) return;
      state.applyDeletedTasksFromSupabase(deletedAudit);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    */
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                SupabaseConfig.isConfigured
                    ? 'Loading from Supabase…'
                    : 'Starting…',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null && SupabaseConfig.isConfigured) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _ready = false;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Continue without Supabase data'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const HomeScreen();
  }
}
