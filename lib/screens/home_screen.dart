import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../config/admin_config.dart';
import '../../config/api_config.dart';
import '../../config/environment_config.dart';
import '../../config/supabase_config.dart';
import '../../services/backend_api.dart';
import 'create_supabase_task_screen.dart';
import 'high_level/initiative_list_screen.dart';
import 'high_level/create_task_screen.dart';
import 'assignee/my_tasks_screen.dart';
import 'admin/system_admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _backendOk;
  String? _backendError;
  bool _checkingBackend = false;
  final BackendApi _backendApi = BackendApi();

  @override
  void initState() {
    super.initState();
    _checkBackend();
  }

  Future<void> _checkBackend() async {
    if (_checkingBackend) return;
    setState(() {
      _checkingBackend = true;
      _backendError = null;
    });
    try {
      final result = await _backendApi.checkHealth();
      if (mounted) {
        setState(() {
          _backendOk = result.ok;
          _backendError = result.ok ? null : (result.message ?? 'Unknown error');
          _checkingBackend = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backendOk = false;
          _backendError = e.toString();
          _checkingBackend = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final revampLookup = context.watch<AppState>().revampStaffLookup;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Project/ Task Tracker',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ) ?? const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (SupabaseConfig.isConfigured)
            IconButton(
              icon: const Icon(Icons.add_task),
              tooltip: 'Create task (Supabase)',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const CreateSupabaseTaskScreen(),
                  ),
                );
              },
            ),
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
          if (kIsWeb)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              tooltip: 'Sign out',
            ),
          Tooltip(
            message: _backendOk == true
                ? 'Backend (${AppEnvironment.label}): ${ApiConfig.baseUrl}'
                : _backendOk == false
                    ? 'Backend unavailable${_backendError != null ? ': $_backendError' : ''}'
                    : 'Checking backend...',
            child: IconButton(
              icon: _checkingBackend
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _backendOk == true ? Icons.cloud_done : Icons.cloud_off,
                      color: _backendOk == true
                          ? Colors.green
                          : _backendOk == false
                              ? Colors.red
                              : Colors.grey,
                    ),
              onPressed: () async {
                await _checkBackend();
                if (mounted && _backendOk == false && _backendError != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Backend: $_backendError'),
                      duration: const Duration(seconds: 5),
                      action: SnackBarAction(
                        label: 'Retry',
                        onPressed: _checkBackend,
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (revampLookup != null)
            Card(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Revamp test — staff / team (by login email)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    // One block so web/desktop can drag-select or double-click to copy all lines.
                    SelectionArea(
                      child: SelectableText(
                        revampLookup.copyableSummary,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: revampLookup.errorMessage != null
                              ? Colors.red.shade900
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy all'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: revampLookup.copyableSummary),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
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
            child: const _HomePageView(),
          ),
        ],
      ),
    );
  }
}

/// Home Page: Role-based tabs
class _HomePageView extends StatelessWidget {
  const _HomePageView();

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().userRole;
    
    // Determine tabs and default index based on role
    int defaultIndex = 0;
    List<Widget> tabs = [];
    List<Widget> tabViews = [];
    
    if (role == 'sys_admin') {
      // sys_admin
      defaultIndex = 0;
      tabs = [
        const Tab(icon: Icon(Icons.flag), text: 'Tasks'),
        const Tab(icon: Icon(Icons.add_circle_outline), text: 'Create task'),
        const Tab(icon: Icon(Icons.assignment), text: 'My tasks'),
      ];
      tabViews = [
        const InitiativeListScreen(),
        const CreateTaskScreen(),
        const MyTasksScreen(),
      ];
    } else if (role == 'dept_head') {
      // dept_head
      defaultIndex = 0;
      tabs = [
        const Tab(icon: Icon(Icons.flag), text: 'Tasks'),
        const Tab(icon: Icon(Icons.add_circle_outline), text: 'Create task'),
      ];
      tabViews = [
        const InitiativeListScreen(),
        const CreateTaskScreen(),
      ];
    } else if (role == 'supervisor') {
      // supervisor
      defaultIndex = 2;
      tabs = [
        const Tab(icon: Icon(Icons.flag), text: 'Tasks'),
        const Tab(icon: Icon(Icons.add_circle_outline), text: 'Create task'),
        const Tab(icon: Icon(Icons.assignment), text: 'My tasks'),
      ];
      tabViews = [
        const InitiativeListScreen(),
        const CreateTaskScreen(),
        const MyTasksScreen(),
      ];
    } else {
      // general
      defaultIndex = 1;
      tabs = [
        const Tab(icon: Icon(Icons.add_circle_outline), text: 'Create task'),
        const Tab(icon: Icon(Icons.assignment), text: 'My tasks'),
      ];
      tabViews = [
        const CreateTaskScreen(),
        const MyTasksScreen(),
      ];
    }
    
    return DefaultTabController(
      length: tabs.length,
      initialIndex: defaultIndex,
      child: Column(
        children: [
          TabBar(
            tabs: tabs,
            isScrollable: tabs.length > 3,
          ),
          Expanded(
            child: TabBarView(
              children: tabViews,
            ),
          ),
        ],
      ),
    );
  }
}
