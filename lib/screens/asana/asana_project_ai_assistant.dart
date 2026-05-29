import '../../utils/hk_time.dart';
import 'asana_task_ai_assistant.dart';

/// Current project form values + staff list (for LLM context and name resolution).
class AsanaProjectAiFormSnapshot {
  const AsanaProjectAiFormSnapshot({
    required this.name,
    required this.description,
    required this.status,
    required this.startDate,
    required this.dueDate,
    required this.assigneesLabel,
    required this.picLabel,
    required this.staff,
    required this.selectedAssigneeIds,
    required this.selectedPicAssigneeIds,
  });

  final String name;
  final String description;
  final String status;
  final DateTime? startDate;
  final DateTime? dueDate;
  final String assigneesLabel;
  final String picLabel;
  final List<({String id, String name})> staff;
  final Set<String> selectedAssigneeIds;
  final Set<String> selectedPicAssigneeIds;

  String buildLlmContext() {
    final buf = StringBuffer()
      ..writeln('Today (Hong Kong): ${_ymd(HkTime.todayDateOnlyHk())}')
      ..writeln('Current project form values:')
      ..writeln('- name: ${name.isEmpty ? "(empty)" : name}')
      ..writeln('- description: ${description.isEmpty ? "(empty)" : description}')
      ..writeln('- status: ${status.isEmpty ? "(empty)" : status}')
      ..writeln('- start date: ${startDate == null ? "(empty)" : _ymd(startDate!)}')
      ..writeln('- due date: ${dueDate == null ? "(empty)" : _ymd(dueDate!)}')
      ..writeln('- assignees: ${assigneesLabel.isEmpty ? "(none)" : assigneesLabel}')
      ..writeln('- PIC: ${picLabel.isEmpty ? "(none)" : picLabel}');

    if (staff.isNotEmpty) {
      buf.writeln(
        'Available staff: ${staff.map((s) => s.name).join('; ')}',
      );
    }
    buf.writeln('Status options: Not started, In progress, Completed');
    return buf.toString();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Callbacks when user adopts a project AI suggestion.
class AsanaProjectAiApply {
  const AsanaProjectAiApply({
    required this.applyName,
    required this.applyDescription,
    required this.applyAssignees,
    required this.applyPic,
    required this.applyStatus,
    required this.applyStartDate,
    required this.applyDueDate,
  });

  final void Function(String name) applyName;
  final void Function(String description) applyDescription;
  final void Function(Set<String> assigneeIds) applyAssignees;
  final void Function(Set<String> picAssigneeIds) applyPic;
  final void Function(String status) applyStatus;
  final void Function(DateTime start) applyStartDate;
  final void Function(DateTime due) applyDueDate;
}

/// Validates LLM JSON and builds adoptable lines for project fields.
class AsanaProjectAiSuggestionBuilder {
  static List<AsanaTaskAiSuggestionLine> build({
    required Map<String, dynamic> raw,
    required AsanaProjectAiFormSnapshot form,
    required AsanaProjectAiApply apply,
  }) {
    final related = raw['related'];
    if (related is bool && !related) {
      final msg = _str(raw['message']) ??
          'This prompt does not look related to updating a project.';
      return [AsanaTaskAiSuggestionLine.warning(msg)];
    }

    final lines = <AsanaTaskAiSuggestionLine>[];

    final name = _str(raw['name']);
    if (name != null &&
        name.isNotEmpty &&
        !_sameNormalizedText(name, form.name)) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.taskName,
          fieldLabel: 'Name',
          currentValue: AsanaTaskAiSuggestionLine.displayCurrent(form.name),
          suggestedText: name,
          onAdopt: () => apply.applyName(name),
        ),
      );
    }

    final desc = _str(raw['description']);
    if (desc != null &&
        desc.isNotEmpty &&
        !_sameNormalizedText(desc, form.description)) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.description,
          fieldLabel: 'Description',
          currentValue:
              AsanaTaskAiSuggestionLine.displayCurrent(form.description),
          suggestedText: desc,
          onAdopt: () => apply.applyDescription(desc),
        ),
      );
    }

    final names = _stringList(raw['assigneeNames']);
    if (names.isNotEmpty) {
      final resolved = <String>{};
      final missing = <String>[];
      for (final n in names) {
        final ids = _matchStaffIds(n, form.staff);
        if (ids.isEmpty) {
          missing.add(n);
        } else {
          resolved.addAll(ids);
        }
      }
      if (missing.isNotEmpty) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Could not match assignee(s): ${missing.join(', ')}',
            fieldKey: AsanaTaskAiFieldKey.assignees,
          ),
        );
      }
      if (resolved.isNotEmpty && !_sameIdSet(resolved, form.selectedAssigneeIds)) {
        final label = _staffNamesForIds(resolved.toList(), form.staff);
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.assignees,
            fieldLabel: 'Assignees',
            currentValue: AsanaTaskAiSuggestionLine.displayCurrent(
              form.assigneesLabel,
            ),
            suggestedText: label,
            onAdopt: () => apply.applyAssignees(resolved),
          ),
        );
      }
    }

    final picNames = _stringList(raw['picNames']);
    if (picNames.isNotEmpty) {
      final resolved = <String>{};
      final missing = <String>[];
      for (final n in picNames) {
        final ids = _matchStaffIds(n, form.staff);
        if (ids.isEmpty) {
          missing.add(n);
        } else {
          resolved.addAll(ids);
        }
      }
      if (missing.isNotEmpty) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Could not match PIC(s): ${missing.join(', ')}',
            fieldKey: AsanaTaskAiFieldKey.pic,
          ),
        );
      }
      if (resolved.isNotEmpty && !_sameIdSet(resolved, form.selectedPicAssigneeIds)) {
        final label = _staffNamesForIds(resolved.toList(), form.staff);
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.pic,
            fieldLabel: 'PIC',
            currentValue:
                AsanaTaskAiSuggestionLine.displayCurrent(form.picLabel),
            suggestedText: label,
            onAdopt: () => apply.applyPic(resolved),
          ),
        );
      }
    }

    final status = _str(raw['status']);
    if (status != null && status.isNotEmpty) {
      final normalized = _parseProjectStatus(status);
      if (normalized == null) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Status "$status" was not recognized (use Not started, In progress, or Completed).',
            fieldKey: AsanaTaskAiFieldKey.projectStatus,
          ),
        );
      } else if (normalized != form.status.trim()) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.projectStatus,
            fieldLabel: 'Status',
            currentValue: form.status.isEmpty ? '(empty)' : form.status,
            suggestedText: normalized,
            onAdopt: () => apply.applyStatus(normalized),
          ),
        );
      }
    }

    DateTime? proposedStart;
    DateTime? proposedDue;
    final startRaw = _str(raw['startDate']);
    final dueRaw = _str(raw['dueDate']);
    if (startRaw != null) proposedStart = _parseYmd(startRaw);
    if (dueRaw != null) proposedDue = _parseYmd(dueRaw);

    var datesBlocked = false;
    if (proposedStart != null &&
        proposedDue != null &&
        _dateOnly(proposedStart).isAfter(_dateOnly(proposedDue))) {
      datesBlocked = true;
      lines.add(
        const AsanaTaskAiSuggestionLine.info(
          'Start and due dates were not suggested because start would be after due.',
          fieldKey: AsanaTaskAiFieldKey.startDate,
        ),
      );
    }

    if (!datesBlocked) {
      final start = proposedStart;
      if (start != null && !_sameDateOnly(start, form.startDate)) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.startDate,
            fieldLabel: 'Start date',
            currentValue: form.startDate == null
                ? '(empty)'
                : _formatDisplayDate(form.startDate!),
            suggestedText: _formatDisplayDate(start),
            onAdopt: () => apply.applyStartDate(start),
          ),
        );
      }

      final due = proposedDue;
      if (due != null && !_sameDateOnly(due, form.dueDate)) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.dueDate,
            fieldLabel: 'Due date',
            currentValue: form.dueDate == null
                ? '(empty)'
                : _formatDisplayDate(form.dueDate!),
            suggestedText: _formatDisplayDate(due),
            onAdopt: () => apply.applyDueDate(due),
          ),
        );
      }
    }

    final hasAdopt = lines.any((l) => l.adoptable);
    if (!hasAdopt && lines.isEmpty) {
      return [
        const AsanaTaskAiSuggestionLine.info(
          'No project fields could be inferred from this prompt. Try being more specific.',
        ),
      ];
    }
    if (!hasAdopt && lines.every((l) => !l.adoptable)) {
      lines.add(
        const AsanaTaskAiSuggestionLine.info(
          'Nothing to apply — review the notes above.',
        ),
      );
    }

    return lines;
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    return v.toString().trim();
  }

  static List<String> _stringList(dynamic v) {
    if (v is! List) return [];
    return v
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static List<String> _matchStaffIds(
    String name,
    List<({String id, String name})> staff,
  ) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return [];

    final exact = <String>[];
    for (final s in staff) {
      if (s.name.trim().toLowerCase() == q) exact.add(s.id);
    }
    if (exact.isNotEmpty) return exact;

    final matches = <String>[];
    for (final s in staff) {
      final n = s.name.trim().toLowerCase();
      final parts = n.split(RegExp(r'\s+'));
      if (parts.any((p) => p == q || p.startsWith(q)) || n.contains(q)) {
        matches.add(s.id);
      }
    }
    return matches;
  }

  static String _staffNamesForIds(
    List<String> ids,
    List<({String id, String name})> staff,
  ) {
    return ids.map((id) {
      for (final s in staff) {
        if (s.id == id) return s.name.trim();
      }
      return id;
    }).join(', ');
  }

  static String? _parseProjectStatus(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('complete')) return 'Completed';
    if (s.contains('progress')) return 'In progress';
    if (s.contains('not') && s.contains('start')) return 'Not started';
    return null;
  }

  static DateTime? _parseYmd(String raw) {
    final t = raw.trim();
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (m != null) {
      final year = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      final day = int.parse(m.group(3)!);
      final parsed = DateTime(year, month, day);
      if (parsed.year != year ||
          parsed.month != month ||
          parsed.day != day) {
        return null;
      }
      return parsed;
    }
    try {
      final d = DateTime.parse(t);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameNormalizedText(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  static bool _sameDateOnly(DateTime? a, DateTime? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return _dateOnly(a) == _dateOnly(b);
  }

  static bool _sameIdSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.every(b.contains);

  static String _formatDisplayDate(DateTime d) =>
      HkTime.formatInstantAsHk(d, 'MMM d, yyyy');
}
