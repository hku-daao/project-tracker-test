import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Navigation drawer shared by [HomeScreen], Overview, and Project views.
class ProjectTrackerDrawer extends StatelessWidget {
  const ProjectTrackerDrawer({
    super.key,
    required this.welcomeName,
    required this.onHome,
    required this.onViewDefault,
    required this.onViewOverview,
    required this.onViewProject,
    required this.onFeedback,
    required this.onImportantNotice,
    required this.onSignOut,
    this.showSignOut = true,
  });

  final String welcomeName;
  final VoidCallback onHome;

  /// Views → Default (landing).
  final VoidCallback onViewDefault;

  /// Views → Overview.
  final VoidCallback onViewOverview;

  /// Views → Project (projects-only dashboard).
  final VoidCallback onViewProject;

  final VoidCallback onFeedback;
  final VoidCallback onImportantNotice;
  final VoidCallback onSignOut;
  final bool showSignOut;

  @override
  Widget build(BuildContext context) {
    return Drawer(
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
              onTap: onHome,
            ),
            ExpansionTile(
              leading: const Icon(Icons.view_list),
              title: const Text('Views'),
              children: [
                ListTile(
                  title: const Text('Default'),
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  onTap: onViewDefault,
                ),
                ListTile(
                  title: const Text('Overview'),
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  onTap: onViewOverview,
                ),
                ListTile(
                  title: const Text('Project'),
                  contentPadding: const EdgeInsets.only(left: 72, right: 16),
                  onTap: onViewProject,
                ),
              ],
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('Feedback'),
              onTap: onFeedback,
            ),
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Important Notice'),
              onTap: onImportantNotice,
            ),
            if (showSignOut && kIsWeb)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: onSignOut,
              ),
          ],
        ),
      ),
    );
  }
}
