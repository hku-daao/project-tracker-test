import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class PerformanceScreen extends StatelessWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final statsMap = state.assigneeStats();
    final stats = statsMap.values.toList();

    if (stats.isEmpty) {
      return const Center(child: Text('No assignees.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Assignee performance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        ...stats.map((s) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.assigneeName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _StatChip(
                            label: 'Assigned',
                            value: '${s.assignedCount}',
                            icon: Icons.assignment,
                          ),
                        ),
                        Expanded(
                          child: _StatChip(
                            label: 'Completed',
                            value: '${s.completedCount}',
                            icon: Icons.check_circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _StatChip(
                            label: 'Avg progress',
                            value: '${s.averageProgressPercent.toStringAsFixed(0)}%',
                            icon: Icons.trending_up,
                          ),
                        ),
                        Expanded(
                          child: _StatChip(
                            label: 'Delay (days)',
                            value: '${s.totalDelayDays}',
                            icon: Icons.schedule,
                            valueColor: s.totalDelayDays > 0 ? Colors.red : null,
                          ),
                        ),
                      ],
                    ),
                    if (s.assignedCount > 0) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: s.assignedCount > 0
                            ? s.completedCount / s.assignedCount
                            : 0,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Completion rate: ${(s.assignedCount > 0 ? (s.completedCount / s.assignedCount * 100) : 0).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            )),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: valueColor ?? Theme.of(context).colorScheme.primary,
              ),
        ),
      ],
    );
  }
}
