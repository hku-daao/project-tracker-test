import 'package:flutter/material.dart';

import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

/// Create-task assignee row: names with hover ✕ to remove; tap empty area to open picker.
class AsanaAssigneeFieldValue extends StatefulWidget {
  const AsanaAssigneeFieldValue({
    super.key,
    required this.assignees,
    required this.canEdit,
    this.anchorLink,
    this.emptyPlaceholder = 'Select assignees',
    this.onOpenPicker,
    this.onRemove,
  });

  /// Sorted by display name.
  final List<({String id, String name})> assignees;
  final bool canEdit;
  final LayerLink? anchorLink;
  final String emptyPlaceholder;
  final void Function(BuildContext fieldContext)? onOpenPicker;
  final void Function(String assigneeId)? onRemove;

  @override
  State<AsanaAssigneeFieldValue> createState() => _AsanaAssigneeFieldValueState();
}

class _AsanaAssigneeFieldValueState extends State<AsanaAssigneeFieldValue> {
  bool _fieldHovering = false;

  @override
  Widget build(BuildContext context) {
    final hasNames = widget.assignees.isNotEmpty;
    final showBorder = widget.canEdit && _fieldHovering;

    Widget inner = MouseRegion(
      onEnter: (_) => setState(() => _fieldHovering = true),
      onExit: (_) => setState(() => _fieldHovering = false),
      child: GestureDetector(
        onTap: widget.canEdit && widget.onOpenPicker != null
            ? () => widget.onOpenPicker!(context)
            : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          decoration: BoxDecoration(
            border: showBorder
                ? Border.all(color: const Color(0xFFB0BEC5))
                : Border.all(color: Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: showBorder ? 8 : 0,
            vertical: showBorder ? 6 : 2,
          ),
          child: hasNames
              ? Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final a in widget.assignees)
                      _AssigneeNameChip(
                        name: a.name,
                        canRemove: widget.canEdit && widget.onRemove != null,
                        onRemove: () => widget.onRemove!(a.id),
                      ),
                    if (widget.canEdit && widget.onOpenPicker != null)
                      AsanaDetailCircleAddButton(
                        tooltip: 'Add assignee',
                        onTap: (_) => widget.onOpenPicker!(context),
                      ),
                  ],
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.emptyPlaceholder,
                    style: asanaDetailValueStyle(context).copyWith(
                      color: kAsanaTextSecondary,
                    ),
                  ),
                ),
        ),
      ),
    );

    if (widget.anchorLink != null) {
      inner = CompositedTransformTarget(
        link: widget.anchorLink!,
        child: inner,
      );
    }
    return inner;
  }
}

class _AssigneeNameChip extends StatefulWidget {
  const _AssigneeNameChip({
    required this.name,
    required this.canRemove,
    required this.onRemove,
  });

  final String name;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  State<_AssigneeNameChip> createState() => _AssigneeNameChipState();
}

class _AssigneeNameChipState extends State<_AssigneeNameChip> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: 2,
              right: widget.canRemove && _hovering ? 14 : 0,
            ),
            child: Text(
              widget.name,
              style: asanaDetailValueStyle(context),
            ),
          ),
          if (widget.canRemove && _hovering)
            Positioned(
              top: -2,
              right: -2,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    widget.onRemove();
                  },
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6D6E6F),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
