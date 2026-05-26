import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/hk_time.dart';
import 'asana_theme.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Month grid with year/month jump controls and themed range selection.
class AsanaDateRangePickerPanel extends StatefulWidget {
  const AsanaDateRangePickerPanel({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.accentColor,
    this.initialRange,
    this.helpText = 'Due date range',
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final Color accentColor;
  final DateTimeRange? initialRange;
  final String helpText;

  @override
  State<AsanaDateRangePickerPanel> createState() =>
      _AsanaDateRangePickerPanelState();
}

class _AsanaDateRangePickerPanelState extends State<AsanaDateRangePickerPanel> {
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  late int _displayYear;
  late int _displayMonth;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRange;
    _rangeStart = initial != null ? _dateOnly(initial.start) : null;
    _rangeEnd = initial != null ? _dateOnly(initial.end) : null;
    final anchor = _rangeEnd ?? _rangeStart ?? HkTime.todayDateOnlyHk();
    _displayYear = anchor.year;
    _displayMonth = anchor.month;
  }

  DateTime get _first => _dateOnly(widget.firstDate);
  DateTime get _last => _dateOnly(widget.lastDate);

  Iterable<int> get _yearOptions =>
      List.generate(_last.year - _first.year + 1, (i) => _first.year + i);

  bool _dayEnabled(DateTime day) =>
      !day.isBefore(_first) && !day.isAfter(_last);

  void _setDisplayMonth(int year, int month) {
    setState(() {
      _displayYear = year;
      _displayMonth = month;
    });
  }

  void _onDayTap(DateTime day) {
    if (!_dayEnabled(day)) return;
    setState(() {
      if (_rangeStart == null || (_rangeStart != null && _rangeEnd != null)) {
        _rangeStart = day;
        _rangeEnd = null;
        return;
      }
      if (day.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
        _rangeStart = day;
      } else {
        _rangeEnd = day;
      }
    });
  }

  bool _isRangeStart(DateTime day) =>
      _rangeStart != null && _sameDay(day, _rangeStart!);

  bool _isRangeEnd(DateTime day) {
    if (_rangeStart == null) return false;
    final end = _rangeEnd ?? _rangeStart!;
    return _sameDay(day, end);
  }

  bool _inRange(DateTime day) {
    if (_rangeStart == null) return false;
    final end = _rangeEnd ?? _rangeStart!;
    final start = _rangeStart!;
    return !day.isBefore(start) && !day.isAfter(end);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTimeRange? _buildResult() {
    if (_rangeStart == null) return null;
    final end = _rangeEnd ?? _rangeStart!;
    final start = _rangeStart!.isBefore(end) ? _rangeStart! : end;
    final finish = _rangeStart!.isBefore(end) ? end : _rangeStart!;
    return DateTimeRange(start: start, end: finish);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accentColor;
    final today = HkTime.todayDateOnlyHk();
    final monthLabel = MaterialLocalizations.of(context)
        .formatMonthYear(DateTime(_displayYear, _displayMonth));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.helpText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: kAsanaTextPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _displayYear,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: kAsanaTextPrimary,
                    ),
                    items: _yearOptions
                        .map(
                          (y) => DropdownMenuItem(
                            value: y,
                            child: Text('$y'),
                          ),
                        )
                        .toList(),
                    onChanged: (y) {
                      if (y == null) return;
                      _setDisplayMonth(y, _displayMonth);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _displayMonth,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: kAsanaTextPrimary,
                    ),
                    items: List.generate(12, (i) {
                      final m = i + 1;
                      final monthName =
                          DateFormat.MMM().format(DateTime(2000, m));
                      return DropdownMenuItem(
                        value: m,
                        child: Text(monthName),
                      );
                    }),
                    onChanged: (m) {
                      if (m == null) return;
                      _setDisplayMonth(_displayYear, m);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            monthLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: kAsanaTextSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _MonthDayGrid(
            year: _displayYear,
            month: _displayMonth,
            accentColor: accent,
            today: today,
            firstDate: _first,
            lastDate: _last,
            isRangeStart: _isRangeStart,
            isRangeEnd: _isRangeEnd,
            inRange: _inRange,
            dayEnabled: _dayEnabled,
            onDayTap: _onDayTap,
          ),
        ),
        if (_rangeStart != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              _rangeEnd == null
                  ? 'Select end date'
                  : '${_formatDay(_rangeStart!)} – ${_formatDay(_rangeEnd!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _rangeStart == null
                    ? null
                    : () => Navigator.pop(context, _buildResult()),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: accent.withValues(alpha: 0.35),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDay(DateTime d) =>
      MaterialLocalizations.of(context).formatShortDate(d);
}

class _MonthDayGrid extends StatelessWidget {
  const _MonthDayGrid({
    required this.year,
    required this.month,
    required this.accentColor,
    required this.today,
    required this.firstDate,
    required this.lastDate,
    required this.isRangeStart,
    required this.isRangeEnd,
    required this.inRange,
    required this.dayEnabled,
    required this.onDayTap,
  });

  final int year;
  final int month;
  final Color accentColor;
  final DateTime today;
  final DateTime firstDate;
  final DateTime lastDate;
  final bool Function(DateTime day) isRangeStart;
  final bool Function(DateTime day) isRangeEnd;
  final bool Function(DateTime day) inRange;
  final bool Function(DateTime day) dayEnabled;
  final void Function(DateTime day) onDayTap;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(year, month);
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    // Monday-first grid (1 = Mon … 7 = Sun).
    final lead = (firstOfMonth.weekday - 1) % 7;
    final cellCount = lead + daysInMonth;
    final rows = (cellCount / 7).ceil();

    return Column(
      children: [
        Row(
          children: _weekdays
              .map(
                (w) => Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: kAsanaTextSecondary,
                          ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: List.generate(7, (c) {
                final index = r * 7 + c;
                if (index < lead || index >= lead + daysInMonth) {
                  return const Expanded(child: SizedBox(height: 36));
                }
                final dayNum = index - lead + 1;
                final day = DateTime(year, month, dayNum);
                final enabled = dayEnabled(day);
                final start = isRangeStart(day);
                final end = isRangeEnd(day);
                final mid = inRange(day) && !start && !end;
                final isToday = day.year == today.year &&
                    day.month == today.month &&
                    day.day == today.day;

                Color? bg;
                Color fg = enabled ? kAsanaTextPrimary : kAsanaTextSecondary;
                Border? border;
                if (start || end) {
                  bg = accentColor;
                  fg = Colors.white;
                } else if (mid) {
                  bg = accentColor.withValues(alpha: 0.18);
                } else if (isToday && enabled) {
                  border = Border.all(color: accentColor, width: 1.5);
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(1),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: enabled ? () => onDayTap(day) : null,
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(18),
                            border: border,
                          ),
                          child: Text(
                            '$dayNum',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  start || end ? FontWeight.w600 : FontWeight.w400,
                              color: enabled ? fg : fg.withValues(alpha: 0.45),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}
