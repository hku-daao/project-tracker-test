import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config/supabase_config.dart';
import '../services/staff_team_lookup_service.dart';
import '../services/supabase_service.dart';
import '../services/task_fetch_visibility.dart';
import 'asana_landing_screen.dart';

/// All platforms use the Asana shell; legacy Home / Overview routes are removed in phase 2.
Widget _bootstrapShellChild() => const AsanaLandingScreen();

/// On startup: revamp step 1 loads staff/team by email; tasks + deleted-task audit load from Supabase.
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
        if (mounted) {
          state.setUserStaffContext(
            staffAppId: lookup.appId,
            staffUuid: lookup.staffId,
          );
          final subIds =
              await SupabaseService.fetchSubordinateAppIdsForSupervisor(
                lookup.appId ?? '',
              );
          if (mounted) state.setSubordinateAppIds(subIds);
        }
      }
    } catch (e) {
      debugPrint('AppBootstrap revamp staff/team lookup: $e');
    }

    TaskFetchVisibility? taskVisibility;
    if (mounted) {
      taskVisibility = await SupabaseService.enrichTaskFetchVisibility(
        state.buildTaskFetchVisibility(),
      );
      if (taskVisibility != null) {
        state.setSubordinateStaffUuids(taskVisibility.subordinateStaffUuids);
        final resolvedUuid = taskVisibility.supervisorStaffUuid?.trim();
        if (resolvedUuid != null && resolvedUuid.isNotEmpty) {
          state.setUserStaffContext(
            staffAppId: state.userStaffAppId,
            staffUuid: resolvedUuid,
          );
        }
      }
    }

    // Load Asana tasks/projects from Supabase.
    if (!SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() => _ready = true);
      }
      return;
    }
    try {
      final taskData = await SupabaseService.fetchTasksFromSupabase(
        visibility: taskVisibility ?? state.buildTaskFetchVisibility(),
      );
      if (!mounted) return;
      final loaded = taskData ?? TasksLoadResult.empty;
      debugPrint(
        'AppBootstrap: fetchTasksFromSupabase returned ${loaded.tasks.length} tasks',
      );
      state.applyTasksFromSupabase(
        loaded,
        visibilityScoped: taskVisibility != null && taskVisibility.isConfigured,
      );
      debugPrint(
        'AppBootstrap: ${state.tasks.length} tasks in AppState '
        '(visibilityScoped=${state.tasksLoadedWithVisibilityScope}, '
        'staffAppId=${state.userStaffAppId}, '
        'lookupKeys=${state.taskVisibilityLookupKeys.length})',
      );
      final filterTeams =
          await SupabaseService.fetchTeamsForFilterFromSupabase();
      final staffLabels =
          await SupabaseService.fetchStaffAssigneesFromSupabase();
      final appIdToTeamId = await SupabaseService.fetchStaffAppIdToTeamIdMap();
      if (!mounted) return;
      if (filterTeams.isNotEmpty) {
        state.setTeamsForFilter(filterTeams);
      }
      if (staffLabels.isNotEmpty) {
        state.mergeAssigneesFromSupabase(staffLabels);
      }
      if (appIdToTeamId.isNotEmpty) {
        state.setStaffAppIdToTeamIdMap(appIdToTeamId);
      }
      final projects = await SupabaseService.fetchAllProjectsFromSupabase();
      if (!mounted) return;
      state.applyProjects(projects);
    } catch (e) {
      debugPrint('AppBootstrap: load tasks/projects from Supabase: $e');
    }
    if (mounted) {
      setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        body: StartupLoadingView(
          label: SupabaseConfig.isConfigured ? 'Loading' : 'Starting',
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
    return _StartupShell(child: _bootstrapShellChild());
  }
}

class StartupLoadingView extends StatelessWidget {
  const StartupLoadingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const palette = AsanaLandingPalette.asana;
    const logoHeight = 48.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheH = (logoHeight * dpr).round().clamp(1, 4096);
    return ColoredBox(
      color: palette.banner,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  height: logoHeight,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  cacheHeight: cacheH,
                  semanticLabel: 'Project Tracker logo',
                ),
                const SizedBox(width: 12),
                Text(
                  'Project\nTracker',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.onBanner,
                    height: 1.05,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.onBanner,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Color(0x66FFFFFF),
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartupShell extends StatelessWidget {
  const _StartupShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
