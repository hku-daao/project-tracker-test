import 'package:flutter/material.dart';

/// Bottom bar: **Back**, optional middle action, **Home**.
class FlowBottomNavThree extends StatelessWidget {
  const FlowBottomNavThree({
    super.key,
    required this.onBack,
    required this.onHome,
    this.midLabel,
    this.midIcon,
    this.onMid,
    this.enabled = true,
  });

  final VoidCallback onBack;
  final VoidCallback onHome;
  /// When null (or [midIcon] null), the middle slot is omitted (e.g. no linked project).
  final String? midLabel;
  final Widget? midIcon;
  final VoidCallback? onMid;
  final bool enabled;

  bool get _showMid =>
      midIcon != null &&
      midLabel != null &&
      midLabel!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget slot(VoidCallback? onTap, Widget icon, String label) {
      return TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: slot(
                  enabled ? onBack : null,
                  const Icon(Icons.arrow_back, size: 18),
                  'Back',
                ),
              ),
              if (_showMid)
                Expanded(
                  child: slot(
                    enabled ? onMid : null,
                    midIcon!,
                    midLabel!.trim(),
                  ),
                ),
              Expanded(
                child: slot(
                  enabled ? onHome : null,
                  const Icon(Icons.home_outlined, size: 18),
                  'Home',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom bar: **Back**, **Task**, optional **Project**, **Home**.
class FlowBottomNavFour extends StatelessWidget {
  const FlowBottomNavFour({
    super.key,
    required this.onBack,
    required this.mid1Label,
    required this.mid1Icon,
    required this.onMid1,
    required this.onHome,
    this.mid2Label,
    this.mid2Icon,
    this.onMid2,
    this.enabled = true,
  });

  final VoidCallback onBack;
  final String mid1Label;
  final Widget mid1Icon;
  final VoidCallback? onMid1;
  /// When null (or [mid2Icon] null), the Project slot is omitted.
  final String? mid2Label;
  final Widget? mid2Icon;
  final VoidCallback? onMid2;
  final VoidCallback onHome;
  final bool enabled;

  bool get _showMid2 =>
      mid2Icon != null &&
      mid2Label != null &&
      mid2Label!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget slot(VoidCallback? onTap, Widget icon, String label) {
      return TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant, width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: slot(
                  enabled ? onBack : null,
                  const Icon(Icons.arrow_back, size: 18),
                  'Back',
                ),
              ),
              Expanded(
                child: slot(
                  enabled ? onMid1 : null,
                  mid1Icon,
                  mid1Label,
                ),
              ),
              if (_showMid2)
                Expanded(
                  child: slot(
                    enabled ? onMid2 : null,
                    mid2Icon!,
                    mid2Label!.trim(),
                  ),
                ),
              Expanded(
                child: slot(
                  enabled ? onHome : null,
                  const Icon(Icons.home_outlined, size: 18),
                  'Home',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
