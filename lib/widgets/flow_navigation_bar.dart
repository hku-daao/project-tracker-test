import 'package:flutter/material.dart';

/// Bottom padding to add under scrollable content when this bar is shown.
const double kFlowNavBarScrollBottomPadding = 88;

/// Home + Back bar for create/detail flows (replaces multiple TextButton links).
class FlowHomeBackBar extends StatelessWidget {
  const FlowHomeBackBar({
    super.key,
    required this.onBack,
    required this.onHome,
    this.enabled = true,
  });

  final VoidCallback onBack;
  final VoidCallback onHome;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: enabled ? onBack : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: enabled ? onHome : null,
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
