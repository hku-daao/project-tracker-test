import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config/supabase_config.dart';
import '../navigator_keys.dart';
import '../services/staff_team_lookup_service.dart';
import '../services/supabase_service.dart';
import '../services/task_fetch_visibility.dart';
import '../utils/home_navigation.dart';
import '../utils/pinned_dashboard_registry.dart';
import '../web_deep_link.dart';
import 'high_level/project_detail_screen.dart';
import 'high_level/subtask_detail_screen.dart';
import '../config/environment_config.dart';
import '../web_host_env.dart';
import 'asana_landing_screen.dart';
import 'home_screen.dart';
import 'task_detail_screen.dart';

/// Web: root shell matches `view` / session so [HomeScreen] is not painted before Overview.
/// Mobile: unchanged — [HomeScreen]; pinned Overview still opens via [_StartupShell._maybeOpenPinnedView].
bool _preferAsanaShellOnWeb(String? view) {
  if (!kIsWeb) return false;
  if (view == 'project') return false;
  if (view == 'original') return false;
  if (view == 'asana' || view == 'newui' || view == 'new-ui') return true;
  return view == null ||
      view.isEmpty ||
      view == 'default' ||
      view == 'overview';
}

Widget _bootstrapShellChild() {
  if (!kIsWeb) {
    return const HomeScreen();
  }
  final raw = readDashboardViewFromUrlOrSession();
  final view = raw?.trim().toLowerCase();
  if (_preferAsanaShellOnWeb(view)) {
    return const AsanaLandingScreen();
  }
  if (view == 'original') {
    return const HomeScreen();
  }
  if (view == 'project') {
    return buildProjectDashboardPage();
  }
  if (view == 'asana' || view == 'newui' || view == 'new-ui') {
    return const AsanaLandingScreen();
  }
  return buildOverviewDashboardPage();
}

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
            assignableStaff: const [],
          );
          final subIds = await SupabaseService.fetchSubordinateAppIdsForSupervisor(
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
            assignableStaff: state.assignableStaffFromServer,
          );
        }
      }
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
          debugPrint('AppBootstrap: email=$email, profile=$profile');
          if (profile != null && profile.staffAppId != null) {
            if (mounted) {
              state.setUserStaffContext(
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

    // Load low-level tasks from Supabase (plural `tasks` + singular `task`) and deleted-task audit.
    // Initiatives remain unloaded here unless you restore fetchInitiativesFromSupabase.
    if (!SupabaseConfig.isConfigured) {
      if (mounted) {
        setState(() => _ready = true);
        _scheduleWebDeepLink();
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
      final deletedAudit = await SupabaseService.fetchDeletedTasksFromSupabase();
      if (!mounted) return;
      state.applyDeletedTasksFromSupabase(deletedAudit);
      final filterTeams = await SupabaseService.fetchTeamsForFilterFromSupabase();
      final staffLabels = await SupabaseService.fetchStaffAssigneesFromSupabase();
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
      debugPrint('AppBootstrap: load tasks/deleted from Supabase: $e');
    }
    if (mounted) {
      setState(() => _ready = true);
      _scheduleWebDeepLink();
    }
  }

  void _scheduleWebDeepLink() {
    if (!kIsWeb) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openWebDeepLinkIfPending();
    });
  }

  void _openWebDeepLinkIfPending() {
    // Prefer URL, then session (populated by [captureWebDeepLinkForSession] before path strategy).
    // URL-only would miss deep links after [usePathUrlStrategy] strips the query from [href].
    final rawView = readDashboardViewFromUrlOrSession();
    final viewTag = rawView?.trim().toLowerCase();
    if (_preferAsanaShellOnWeb(viewTag)) {
      return;
    }
    final subId = readSubtaskIdFromUrlOrSession();
    if (subId != null && subId.isNotEmpty) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => SubtaskDetailScreen(
            subtaskId: subId,
            replaceWithParentTaskOnBack: true,
          ),
        ),
      );
      return;
    }
    final taskId = readTaskIdFromUrlOrSession();
    if (taskId != null && taskId.isNotEmpty) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => TaskDetailScreen(taskId: taskId),
        ),
      );
      return;
    }
    final projectId = readProjectIdFromUrlOrSession();
    if (projectId != null && projectId.isNotEmpty) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => ProjectDetailScreen(
            projectId: projectId,
            openedFromLanding: true,
            openedFromOverview: false,
          ),
        ),
      );
      return;
    }
    // Shell already shows Overview / Project / Original — avoid a second route (flash of Home).
    if (viewTag == 'overview' || viewTag == 'default') {
      syncWebStaleDetailSessionsIfUrlHasNoTaskOrSubtask();
      return;
    }
    if (viewTag == 'project') {
      syncWebStaleDetailSessionsIfUrlHasNoTaskOrSubtask();
      return;
    }
    syncWebStaleDetailSessionsIfUrlHasNoTaskOrSubtask();
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

/// After load, opens [CustomizedDashboardPage] (Default) unless a deep link wins.
class _StartupShell extends StatefulWidget {
  const _StartupShell({required this.child});

  final Widget child;

  @override
  State<_StartupShell> createState() => _StartupShellState();
}

class _StartupShellState extends State<_StartupShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOpenPinnedView());
  }

  Future<void> _maybeOpenPinnedView() async {
    final subId = readSubtaskIdFromUrlOrSession();
    final taskId = readTaskIdFromUrlOrSession();
    if (subId != null && subId.isNotEmpty) return;
    if (taskId != null && taskId.isNotEmpty) return;
    final projectId = readProjectIdFromUrlOrSession();
    if (projectId != null && projectId.isNotEmpty) return;
    final rawView = readDashboardViewFromUrlOrSession();
    final urlView = rawView?.trim().toLowerCase();
    if (urlView == 'overview' ||
        urlView == 'project' ||
        urlView == 'default' ||
        urlView == 'original' ||
        urlView == 'asana' ||
        urlView == 'newui' ||
        urlView == 'new-ui') {
      return;
    }
    // Web: shell already defaults to Overview when view is unset — do not stack a duplicate route.
    if (kIsWeb && (urlView == null || urlView.isEmpty)) {
      return;
    }

    if (!mounted || !context.mounted) return;
    if (Navigator.of(context).canPop()) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: kOverviewDashboardRouteName),
        builder: (context) => buildOverviewDashboardPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
