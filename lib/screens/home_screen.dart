import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_state.dart';
import '../../models/staff_team_lookup.dart';
import '../../config/admin_config.dart';
import '../../config/environment_config.dart';
import '../../config/supabase_config.dart';
import '../../web_deep_link.dart';
import 'high_level/initiative_list_screen.dart';
import 'high_level/create_task_screen.dart';
import 'admin/system_admin_screen.dart';

/// Warn before leaving the create flow while a draft exists (create screen / Sign out).
Future<bool> _confirmLeaveCreateTaskDraft(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Unsaved task'),
      content: Text.rich(
        TextSpan(
          style: Theme.of(ctx).textTheme.bodyLarge,
          children: const [
            TextSpan(text: 'Press '),
            TextSpan(
              text: 'Create task',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text:
                  ' to save your task. If you leave now, nothing will be saved.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Stay'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Leave anyway'),
        ),
      ],
    ),
  );
  return r == true;
}

/// Microsoft Forms — feedback (AppBar).
const String _kFeedbackFormUrl =
    'https://forms.cloud.microsoft/Pages/ResponsePage.aspx?id=TrX5QnckukG_CXoNKoP_CXmxjjVqONdDujd4tWBFFN9UMk1ZS0EzMFZSSlFSMkhXTjI5UE82QThKTC4u';

Future<void> _openFeedbackForm(BuildContext context) async {
  final uri = Uri.parse(_kFeedbackFormUrl);
  final ok = await canLaunchUrl(uri);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(duration: Duration(seconds: 4), content: Text('Could not open feedback form')),
    );
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _welcomeDisplayName(StaffTeamLookupResult? lookup) {
  final display = lookup?.staffDisplayName?.trim();
  if (display != null && display.isNotEmpty) return display;
  final n = lookup?.staffName?.trim();
  if (n != null && n.isNotEmpty) return n;
  final u = FirebaseAuth.instance.currentUser;
  final dn = u?.displayName?.trim();
  if (dn != null && dn.isNotEmpty) return dn;
  final e = u?.email;
  if (e != null && e.isNotEmpty) {
    final at = e.split('@').first.trim();
    if (at.isNotEmpty) return at;
  }
  return 'User';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppState? _appState;

  /// Hides the FAB while scrolling down; shows again on scroll up or when scrolling stops.
  bool _createTaskFabVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppState>();
    if (!identical(_appState, app)) {
      _appState?.removeListener(_onConsumeSwitchToTasksTab);
      _appState = app;
      _appState!.addListener(_onConsumeSwitchToTasksTab);
    }
  }

  /// Clears [AppState.takeSwitchToTasksTabPending] after save / deep link; task list is always shown.
  void _onConsumeSwitchToTasksTab() {
    if (!mounted) return;
    _appState?.takeSwitchToTasksTabPending();
  }

  @override
  void dispose() {
    _appState?.removeListener(_onConsumeSwitchToTasksTab);
    super.dispose();
  }

  void _openCreateTaskScreen() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Create task')),
          body: const CreateTaskScreen(),
        ),
      ),
    );
  }

  bool _onLandingScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is ScrollUpdateNotification) {
      final d = n.scrollDelta;
      if (d == null) return false;
      if (d > 6 && _createTaskFabVisible) {
        setState(() => _createTaskFabVisible = false);
      } else if (d < -6 && !_createTaskFabVisible) {
        setState(() => _createTaskFabVisible = true);
      }
    } else if (n is ScrollEndNotification) {
      if (!_createTaskFabVisible) {
        setState(() => _createTaskFabVisible = true);
      }
    }
    return false;
  }

  void _closeDrawerThenFeedback() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openFeedbackForm(context);
    });
  }

  void _closeDrawerThenGoHome() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  static const String _kImportantNoticeBody =
      'Do not store donor, prospect, or alumni data in Project Tracker, '
      'including personal details, giving history, or engagement records. '
      'Use Project Tracker only for task-based entries such as "prepare donor report" '
      'or "update alumni engagement plan", and link to the appropriate secure system—'
      'such as the institutional CRM or advancement intelligence platform—where the '
      'actual information is maintained.';

  void _closeDrawerThenImportantNotice() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Important Notice'),
          content: SingleChildScrollView(
            child: Text(
              _kImportantNoticeBody,
              style: Theme.of(ctx).textTheme.bodyLarge,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _closeDrawerThenSignOut() async {
    Navigator.of(context).pop();
    if (!mounted) return;
    final appState = context.read<AppState>();
    if (appState.hasCreateTaskUnsavedDraft) {
      final leave = await _confirmLeaveCreateTaskDraft(context);
      if (!mounted || !leave) return;
    }
    if (kIsWeb) {
      syncWebLocationForLanding();
    }
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final revampLookup = context.watch<AppState>().revampStaffLookup;
    final welcomeName = _welcomeDisplayName(revampLookup);
    final titleStyle = Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ) ??
        const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
        );
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                margin: EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Project Tracker',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Welcome, $welcomeName',
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Home'),
                onTap: _closeDrawerThenGoHome,
              ),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('Feedback'),
                onTap: _closeDrawerThenFeedback,
              ),
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Important Notice'),
                onTap: _closeDrawerThenImportantNotice,
              ),
              if (kIsWeb)
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign out'),
                  onTap: () async {
                    await _closeDrawerThenSignOut();
                  },
                ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 0,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Project Tracker',
            style: titleStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          if (FirebaseAuth.instance.currentUser?.email?.toLowerCase() ==
              AdminConfig.systemAdminEmail.toLowerCase())
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'System Admin',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const SystemAdminScreen(),
                  ),
                );
              },
            ),
        ],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!SupabaseConfig.isConfigured)
            Card(
              margin: const EdgeInsets.all(8),
              color: Colors.amber.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.storage, color: Colors.amber.shade900),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Supabase URL/key not set (${AppEnvironment.label}) — nothing is saved to the cloud. '
                        'For testing: set _testingAnonKey in supabase_config.dart or use '
                        '--dart-define=SUPABASE_ANON_KEY=.... See docs/ENVIRONMENTS.md.',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onLandingScrollNotification,
              child: const InitiativeListScreen(),
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedOpacity(
        opacity: _createTaskFabVisible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: !_createTaskFabVisible,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FloatingActionButton.extended(
              onPressed: _openCreateTaskScreen,
              icon: const Icon(Icons.add),
              label: const Text('Create task'),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
