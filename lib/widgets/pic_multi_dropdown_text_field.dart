import 'package:flutter/material.dart';

import '../models/staff_for_assignment.dart';

/// Read-only text field that opens a scrollable checklist (dropdown-style) for
/// choosing multiple PICs from [candidates]. Shows all selected names in the field.
class PicMultiDropdownTextField extends StatefulWidget {
  const PicMultiDropdownTextField({
    super.key,
    required this.label,
    required this.candidates,
    required this.selectedIds,
    required this.onSelectionChanged,
    this.hint,
    this.enabled = true,
    this.dense = false,
  });

  final String label;
  final String? hint;
  final List<StaffForAssignment> candidates;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final bool enabled;
  final bool dense;

  @override
  State<PicMultiDropdownTextField> createState() =>
      _PicMultiDropdownTextFieldState();
}

class _PicMultiDropdownTextFieldState extends State<PicMultiDropdownTextField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _summary());
  }

  @override
  void didUpdateWidget(PicMultiDropdownTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds ||
        oldWidget.candidates.length != widget.candidates.length) {
      final next = _summary();
      if (_controller.text != next) {
        _controller.text = next;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _summary() {
    if (widget.selectedIds.isEmpty) {
      return '';
    }
    final names = widget.selectedIds
        .map(
          (id) => widget.candidates
              .firstWhere(
                (s) => s.assigneeId == id,
                orElse: () =>
                    StaffForAssignment(assigneeId: id, name: id),
              )
              .name,
        )
        .toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names.join(', ');
  }

  Future<void> _openSheet() async {
    if (!widget.enabled || widget.candidates.isEmpty) return;
    final sorted = [...widget.candidates]
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    final temp = Set<String>.from(widget.selectedIds);
    final maxSheetH = MediaQuery.sizeOf(context).height * 0.55;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(ctx).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        widget.label,
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    SizedBox(
                      height: maxSheetH.clamp(200.0, 520.0),
                      child: ListView(
                        children: [
                          for (final s in sorted)
                            CheckboxListTile(
                              value: temp.contains(s.assigneeId),
                              onChanged: widget.enabled
                                  ? (v) {
                                      setSheetState(() {
                                        if (v == true) {
                                          temp.add(s.assigneeId);
                                        } else {
                                          temp.remove(s.assigneeId);
                                        }
                                      });
                                    }
                                  : null,
                              title: Text(s.name),
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                        onPressed: () {
                          widget.onSelectionChanged(Set<String>.from(temp));
                          Navigator.pop(ctx);
                        },
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    if (mounted) {
      _controller.text = _summary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = widget.selectedIds.isEmpty;
    return TextFormField(
      controller: _controller,
      readOnly: true,
      enabled: widget.enabled,
      maxLines: widget.dense ? 2 : 3,
      minLines: 1,
      onTap: widget.enabled ? () => _openSheet() : null,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: empty
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint ??
            (widget.candidates.isEmpty
                ? 'Select assignees first'
                : 'Choose from assignees above'),
        border: const OutlineInputBorder(),
        suffixIcon: Icon(
          Icons.arrow_drop_down,
          color: widget.enabled
              ? theme.colorScheme.onSurfaceVariant
              : theme.disabledColor,
        ),
        isDense: widget.dense,
        alignLabelWithHint: true,
      ),
    );
  }
}
