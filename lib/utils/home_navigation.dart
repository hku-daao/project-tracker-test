import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/startup_view_storage.dart';
import 'pinned_dashboard_registry.dart';

/// [MaterialPageRoute.settings.name] for [CustomizedDashboardPage] (Overview).
const String kOverviewDashboardRouteName = 'overview_dashboard';

/// [MaterialPageRoute.settings.name] for [ProjectDashboardPage].
const String kProjectDashboardRouteName = 'project_dashboard';

/// Pops until Overview is on top, otherwise until landing home — never drops Overview when present.
void popUntilOverviewOrHome(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).popUntil((route) {
    final name = route.settings.name;
    return name == kOverviewDashboardRouteName ||
        name == kProjectDashboardRouteName ||
        route.isFirst;
  });
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final r = ModalRoute.of(context);
    if (r != null && r.isFirst) {
      app.requestSwitchToTasksTab();
    }
  });
}

/// Pops the entire stack back to the first route (home), then focuses the task list.
void navigateToHomeTasksTab(BuildContext context) {
  final app = context.read<AppState>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    app.requestSwitchToTasksTab();
  });
}

/// Pops to landing, then opens Overview or Project if that view is pinned as home.
Future<void> navigateToPinnedHomeFromDrawer(BuildContext context) async {
  final tag = await StartupViewStorage.getPreferredViewTag();
  if (!context.mounted) return;
  final app = context.read<AppState>();
  Navigator.of(context).popUntil((route) => route.isFirst);
  if (!context.mounted) return;
  if (tag == StartupViewStorage.viewOverview) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: kOverviewDashboardRouteName),
        builder: (context) => buildOverviewDashboardPage(),
      ),
    );
  } else if (tag == StartupViewStorage.viewProject) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: kProjectDashboardRouteName),
        builder: (context) => buildProjectDashboardPage(),
      ),
    );
  }
  if (tag == StartupViewStorage.viewLanding) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) app.requestSwitchToTasksTab();
    });
  }
}

/// Pops until the Project dashboard route is on top, otherwise until first route.
void popUntilProjectDashboardOrHome(BuildContext context) {
  Navigator.of(context).popUntil((route) {
    return route.settings.name == kProjectDashboardRouteName || route.isFirst;
  });
}
