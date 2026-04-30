import 'package:flutter/material.dart';

/// Factories registered from [main] so [home_navigation] can open Overview / Project
/// without importing [home_screen] (avoids circular imports with [CreateTaskScreen]).
typedef PinnedDashboardFactory = Widget Function();

PinnedDashboardFactory? _overviewFactory;
PinnedDashboardFactory? _projectFactory;

void registerPinnedHomeDashboardPages({
  required PinnedDashboardFactory overview,
  required PinnedDashboardFactory project,
}) {
  _overviewFactory = overview;
  _projectFactory = project;
}

Widget buildOverviewDashboardPage() {
  final f = _overviewFactory;
  if (f == null) {
    throw StateError(
      'registerPinnedHomeDashboardPages was not called from main()',
    );
  }
  return f();
}

Widget buildProjectDashboardPage() {
  final f = _projectFactory;
  if (f == null) {
    throw StateError(
      'registerPinnedHomeDashboardPages was not called from main()',
    );
  }
  return f();
}
