import 'package:flutter/material.dart';
import 'high_level/initiative_list_screen.dart';
import 'high_level/create_initiative_screen.dart';
import 'low_level/low_level_task_list_screen.dart';
import 'low_level/create_low_level_task_screen.dart';
import 'assignee/my_tasks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// true = High-level View (initiatives), false = Low-level View (tasks)
  bool _isHighLevelView = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Tracker'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('High-level View')),
                  ButtonSegment(value: false, label: Text('Low-level View')),
                ],
                selected: {_isHighLevelView},
                onSelectionChanged: (Set<bool> selected) {
                  setState(() => _isHighLevelView = selected.first);
                },
              ),
            ),
          ),
        ],
      ),
      body: _isHighLevelView
          ? const _HighLevelView()
          : const _LowLevelView(),
    );
  }
}

/// High-level View: Professors/Directors assign initiatives to Directors; milestones & progress.
class _HighLevelView extends StatelessWidget {
  const _HighLevelView();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.flag), text: 'Initiatives'),
              Tab(icon: Icon(Icons.add_circle_outline), text: 'Create Initiative'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                InitiativeListScreen(),
                CreateInitiativeScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Low-level View: Directors assign tasks to Responsible Officers (Planner-style).
class _LowLevelView extends StatelessWidget {
  const _LowLevelView();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: 'All Tasks'),
              Tab(icon: Icon(Icons.add_task), text: 'Create Task'),
              Tab(icon: Icon(Icons.assignment), text: 'My Tasks'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                LowLevelTaskListScreen(),
                CreateLowLevelTaskScreen(),
                MyTasksScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
