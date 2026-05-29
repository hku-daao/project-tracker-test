import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_anchored_overlay.dart';
import 'asana_date_range_picker.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

/// Calendar day from a [DateRangePickerDialog] result (local date components).
DateTime asanaDateOnlyFromPicker(DateTime d) => DateTime(d.year, d.month, d.day);

/// Filter control with a label above the current value (Asana-style toolbar).
class AsanaFilterDropdown extends StatelessWidget {
  const AsanaFilterDropdown({
    super.key,
    required this.title,
    required this.value,
    required this.onPressed,
    this.highlighted = false,
    this.buttonWidth = 116,
  });

  final String title;
  final String value;
  final void Function(BuildContext buttonContext) onPressed;
  final bool highlighted;
  final double buttonWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: kAsanaTextSecondary,
      fontSize: 11,
    );
    final valueStyle = theme.textTheme.bodySmall;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: 4),
          Builder(
            builder: (buttonContext) {
              return SizedBox(
                width: buttonWidth,
                child: OutlinedButton(
                  onPressed: () => onPressed(buttonContext),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                    minimumSize: Size(buttonWidth, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor: highlighted
                        ? theme.colorScheme.primaryContainer
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          textAlign: TextAlign.left,
                          style: valueStyle,
                        ),
                      ),
                      Icon(
                        highlighted
                            ? Icons.expand_less
                            : Icons.arrow_drop_down,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Primary create action (left side of list panel toolbars).
class AsanaToolbarCreateButton extends StatelessWidget {
  const AsanaToolbarCreateButton({
    super.key,
    required this.label,
    required this.palette,
    required this.onPressed,
  });

  final String label;
  final AsanaLandingPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Filter row: [create] on the left, filter dropdowns + Clear all on the right.
class AsanaPanelFilterToolbar extends StatefulWidget {
  const AsanaPanelFilterToolbar({
    super.key,
    required this.palette,
    required this.createLabel,
    required this.onCreate,
    required this.filterChildren,
    required this.onClearAll,
  });

  final AsanaLandingPalette palette;
  final String createLabel;
  final VoidCallback onCreate;
  final List<Widget> filterChildren;
  final VoidCallback onClearAll;

  @override
  State<AsanaPanelFilterToolbar> createState() =>
      _AsanaPanelFilterToolbarState();
}

class _AsanaPanelFilterToolbarState extends State<AsanaPanelFilterToolbar> {
  final _filterScrollController = ScrollController();

  @override
  void dispose() {
    _filterScrollController.dispose();
    super.dispose();
  }

  Widget _scrollableFilters(Widget child, {bool reverse = false}) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: SingleChildScrollView(
        controller: _filterScrollController,
        scrollDirection: Axis.horizontal,
        reverse: reverse,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final createButton = AsanaToolbarCreateButton(
            label: widget.createLabel,
            palette: widget.palette,
            onPressed: widget.onCreate,
          );
          final clearButton = TextButton(
            onPressed: widget.onClearAll,
            child: const Text('Clear all'),
          );
          final filterRow = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: widget.filterChildren,
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    createButton,
                    const Spacer(),
                    clearButton,
                  ],
                ),
                const SizedBox(height: 10),
                _scrollableFilters(filterRow),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              createButton,
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _scrollableFilters(filterRow, reverse: true),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 18, left: 8),
                child: clearButton,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// White rounded card that holds the scrollable list/table.
class AsanaPanelListSurface extends StatelessWidget {
  const AsanaPanelListSurface({
    super.key,
    required this.palette,
    required this.child,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final AsanaLandingPalette palette;
  final Widget child;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Material(
        color: palette.listSurface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: child,
      ),
    );
  }
}

/// One checkbox row in a compact anchored filter panel (no extra gap after "All").
class AsanaFilterCheckboxOption {
  const AsanaFilterCheckboxOption({
    required this.key,
    required this.label,
    this.isAll = false,
  });

  final String key;
  final String label;
  final bool isAll;
}

/// Shows a small menu under the filter button (not full-screen).
Future<Set<String>?> showAsanaCheckboxFilterPanel({
  required BuildContext anchorContext,
  required List<AsanaFilterCheckboxOption> options,
  required Set<String> initialSelection,
}) {
  final completer = Completer<Set<String>?>();
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    completer.complete(null);
    return completer.future;
  }

  final overlay = Overlay.maybeOf(anchorContext, rootOverlay: true);
  if (overlay == null) {
    completer.complete(null);
    return completer.future;
  }

  final offset = box.localToGlobal(Offset.zero);
  final size = box.size;
  late OverlayEntry entry;

  void close([Set<String>? result]) {
    if (entry.mounted) entry.remove();
    if (!completer.isCompleted) completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => close(null),
            behavior: HitTestBehavior.translucent,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: offset.dx,
          top: offset.dy + size.height + 2,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(anchorContext).colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: size.width.clamp(180, 280),
                maxWidth: 280,
              ),
              child: _CheckboxFilterPanelBody(
                options: options,
                initialSelection: initialSelection,
                onDone: (newSelection) => close(newSelection),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!anchorContext.mounted) {
      completer.complete(null);
      return;
    }
    overlay.insert(entry);
  });

  return completer.future;
}

class _CheckboxFilterPanelBody extends StatefulWidget {
  const _CheckboxFilterPanelBody({
    required this.options,
    required this.initialSelection,
    required this.onDone,
  });

  final List<AsanaFilterCheckboxOption> options;
  final Set<String> initialSelection;
  final void Function(Set<String>) onDone;

  @override
  State<_CheckboxFilterPanelBody> createState() => _CheckboxFilterPanelBodyState();
}

class _CheckboxFilterPanelBodyState extends State<_CheckboxFilterPanelBody> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.initialSelection);
  }

  void _toggle(String key, bool checked) {
    setState(() {
      _selected.remove('all');
      _selected.remove('__all__');
      if (checked) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    });
  }

  void _selectAll(String allKey) {
    setState(() {
      _selected.clear();
      _selected.add(allKey);
    });
  }

  bool _isChecked(AsanaFilterCheckboxOption opt) {
    if (opt.isAll) {
      return _selected.isEmpty || _selected.contains(opt.key);
    }
    return _selected.contains(opt.key);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final opt in widget.options)
          _CompactCheckboxTile(
            label: opt.label,
            value: _isChecked(opt),
            onChanged: (v) {
              if (opt.isAll) {
                if (v == true) _selectAll(opt.key);
              } else {
                _toggle(opt.key, v == true);
              }
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Align(
            alignment: mobile ? Alignment.centerLeft : Alignment.centerRight,
            child: FilledButton(
              onPressed: () {
                if (_selected.contains('all') || _selected.contains('__all__')) {
                  widget.onDone(<String>{});
                  return;
                }
                widget.onDone(_selected);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE4E6EB),
                foregroundColor: const Color(0xFF1F2937),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ).copyWith(
                overlayColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.hovered)
                      ? Colors.black12
                      : null,
                ),
              ),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactCheckboxTile extends StatelessWidget {
  const _CompactCheckboxTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anchored range calendar (one picker UI) below a filter or detail field.
Future<DateTimeRange?> showAsanaAnchoredDateRangePicker({
  required BuildContext anchorContext,
  DateTime? start,
  DateTime? end,
  String helpText = 'Due date range',
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;

  final now = HkTime.todayDateOnlyHk();
  final initialStart = start ?? now.subtract(const Duration(days: 30));
  final initialEnd = end ?? now;
  final initialRange = DateTimeRange(
    start: initialStart.isBefore(initialEnd) ? initialStart : initialEnd,
    end: initialEnd.isBefore(initialStart) ? initialStart : initialEnd,
  );

  final offset = box.localToGlobal(Offset.zero);
  final size = box.size;
  final screen = MediaQuery.sizeOf(anchorContext);
  const panelWidth = 380.0;
  const panelHeight = 420.0;
  final accent = Theme.of(anchorContext).colorScheme.primary;
  final pickerTheme = Theme.of(anchorContext).copyWith(
    colorScheme: Theme.of(anchorContext).colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
    ),
  );
  var left = offset.dx;
  if (left + panelWidth > screen.width - 8) {
    left = screen.width - panelWidth - 8;
  }
  if (left < 8) left = 8;
  var top = offset.dy + size.height + 4;
  if (top + panelHeight > screen.height - 8) {
    top = offset.dy - panelHeight - 4;
  }
  if (top < 8) top = 8;

  final picked = await showGeneralDialog<DateTimeRange>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black26,
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              color: pickerTheme.colorScheme.surface,
              child: Theme(
                data: pickerTheme,
                child: SizedBox(
                  width: panelWidth,
                  child: AsanaDateRangePickerPanel(
                    initialRange: initialRange,
                    firstDate: now.subtract(const Duration(days: 365 * 10)),
                    lastDate: now.add(const Duration(days: 365 * 5)),
                    accentColor: accent,
                    helpText: helpText,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  if (picked == null) return null;
  return DateTimeRange(
    start: asanaDateOnlyFromPicker(picked.start),
    end: asanaDateOnlyFromPicker(picked.end),
  );
}

/// Anchored single-date calendar for fields that should not imply a range.
Future<DateTime?> showAsanaAnchoredSingleDatePicker({
  required BuildContext anchorContext,
  DateTime? initialDate,
  String helpText = 'Select date',
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;

  final now = HkTime.todayDateOnlyHk();
  final firstDate = now.subtract(const Duration(days: 365 * 10));
  final lastDate = now.add(const Duration(days: 365 * 5));
  final initial = asanaDateOnlyFromPicker(initialDate ?? now);
  final offset = box.localToGlobal(Offset.zero);
  final size = box.size;
  final screen = MediaQuery.sizeOf(anchorContext);
  const panelWidth = 380.0;
  const panelHeight = 420.0;
  final accent = Theme.of(anchorContext).colorScheme.primary;
  final pickerTheme = Theme.of(anchorContext).copyWith(
    colorScheme: Theme.of(anchorContext).colorScheme.copyWith(
      primary: accent,
      onPrimary: Colors.white,
    ),
  );
  var left = offset.dx;
  if (left + panelWidth > screen.width - 8) {
    left = screen.width - panelWidth - 8;
  }
  if (left < 8) left = 8;
  var top = offset.dy + size.height + 4;
  if (top + panelHeight > screen.height - 8) {
    top = offset.dy - panelHeight - 4;
  }
  if (top < 8) top = 8;

  final picked = await showGeneralDialog<DateTime>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black26,
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              color: pickerTheme.colorScheme.surface,
              child: Theme(
                data: pickerTheme,
                child: SizedBox(
                  width: panelWidth,
                  child: CalendarDatePicker(
                    initialDate: initial.isBefore(firstDate) ||
                            initial.isAfter(lastDate)
                        ? now
                        : initial,
                    firstDate: firstDate,
                    lastDate: lastDate,
                    currentDate: now,
                    onDateChanged: (date) {
                      Navigator.pop(
                        dialogContext,
                        asanaDateOnlyFromPicker(date),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
  if (picked == null) return null;
  return asanaDateOnlyFromPicker(picked);
}

/// One selectable row in [showAsanaAnchoredOptionMenu].
class AsanaAnchoredOption<T> {
  const AsanaAnchoredOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Small menu anchored under a field (task-list filter style; follows anchor on resize).
Future<T?> showAsanaAnchoredOptionMenu<T>({
  required LayerLink anchorLink,
  required BuildContext anchorContext,
  required List<AsanaAnchoredOption<T>> options,
  VoidCallback? onClosed,
}) async {
  T? picked;
  final menuWidth = asanaAnchoredFieldWidth(anchorContext);
  await showAsanaAnchoredOverlay(
    anchorLink: anchorLink,
    anchorContext: anchorContext,
    panelWidth: menuWidth,
    whenClosed: onClosed,
    builder: (ctx, close) {
      return Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(anchorContext).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: options
              .map(
                (o) => InkWell(
                  onTap: () {
                    picked = o.value;
                    SchedulerBinding.instance.addPostFrameCallback((_) {
                      close();
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      o.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      style: asanaDetailValueStyle(anchorContext),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      );
    },
  );
  return picked;
}
