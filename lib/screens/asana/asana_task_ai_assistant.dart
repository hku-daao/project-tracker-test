import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../priority.dart';
import '../../services/deepseek_service.dart';
import '../../utils/hk_time.dart';
import '../asana_landing_screen.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

/// Which form field an AI suggestion belongs to (for inline placement).
enum AsanaTaskAiFieldKey {
  global,
  taskName,
  description,
  project,
  assignees,
  pic,
  priority,
  startDate,
  dueDate,
  comment,
}

/// Name, description, and comment use full slide width (no label column inset).
bool asanaTaskAiFieldUsesFullWidth(AsanaTaskAiFieldKey key) {
  return key == AsanaTaskAiFieldKey.taskName ||
      key == AsanaTaskAiFieldKey.description ||
      key == AsanaTaskAiFieldKey.comment;
}

/// Theme-derived colors for the AI assistant chrome and suggestion glow.
class AsanaTaskAiColors {
  const AsanaTaskAiColors({
    required this.boxBackground,
    required this.boxBorder,
    required this.accent,
    required this.suggestedLabel,
    required this.cardSurface,
    required this.adoptIcon,
  });

  final Color boxBackground;
  final Color boxBorder;
  final Color accent;
  final Color suggestedLabel;
  final Color cardSurface;
  final Color adoptIcon;

  factory AsanaTaskAiColors.fromPalette(AsanaLandingPalette palette) {
    final accent = palette.accent;
    return AsanaTaskAiColors(
      boxBackground: Color.alphaBlend(
        accent.withValues(alpha: palette.darkChrome ? 0.12 : 0.09),
        palette.content,
      ),
      boxBorder: accent.withValues(alpha: 0.4),
      accent: accent,
      suggestedLabel: accent,
      cardSurface: palette.listSurface,
      adoptIcon: palette.darkChrome
          ? const Color(0xFF66BB6A)
          : Color.lerp(accent, const Color(0xFF2E7D32), 0.45)!,
    );
  }
}

/// Current form values + pick lists (for LLM context and name resolution).
class AsanaTaskAiFormSnapshot {
  const AsanaTaskAiFormSnapshot({
    required this.name,
    required this.description,
    required this.projectLabel,
    required this.assigneesLabel,
    required this.picLabel,
    required this.priority,
    required this.startDate,
    required this.dueDate,
    required this.projects,
    required this.staff,
    required this.canSuggestProject,
    required this.canSuggestAssignees,
    required this.selectedAssigneeIds,
    this.selectedProjectId,
    this.picAssigneeId,
  });

  final String name;
  final String description;
  final String projectLabel;
  final String assigneesLabel;
  final String picLabel;
  final int priority;
  final DateTime? startDate;
  final DateTime? dueDate;
  final List<({String id, String name})> projects;
  final List<({String id, String name})> staff;
  final bool canSuggestProject;
  final bool canSuggestAssignees;
  final Set<String> selectedAssigneeIds;
  final String? selectedProjectId;
  final String? picAssigneeId;

  String buildLlmContext() {
    final buf = StringBuffer()
      ..writeln('Today (Hong Kong): ${_ymd(HkTime.todayDateOnlyHk())}')
      ..writeln('Current form values (user may change; suggest only what the prompt implies):')
      ..writeln('- name: ${name.isEmpty ? "(empty)" : name}')
      ..writeln('- description: ${description.isEmpty ? "(empty)" : description}')
      ..writeln('- project: ${projectLabel.isEmpty ? "(none)" : projectLabel}')
      ..writeln('- assignees: ${assigneesLabel.isEmpty ? "(none)" : assigneesLabel}')
      ..writeln('- PIC: ${picLabel.isEmpty ? "(none)" : picLabel}')
      ..writeln('- priority: ${priorityToDisplayName(priority)}')
      ..writeln('- start date: ${startDate == null ? "(empty)" : _ymd(startDate!)}')
      ..writeln('- due date: ${dueDate == null ? "(empty)" : _ymd(dueDate!)}');

    if (canSuggestProject && projects.isNotEmpty) {
      buf.writeln('Available projects: ${projects.map((p) => p.name).join('; ')}');
    }
    if (canSuggestAssignees && staff.isNotEmpty) {
      buf.writeln('Available staff: ${staff.map((s) => s.name).join('; ')}');
    }
    buf.writeln('Priority options: Standard, URGENT');
    return buf.toString();
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Task-field assistant (create / creator edit) vs comment-only (assignees, etc.).
enum AsanaTaskAiAssistantMode { taskFields, commentOnly }

/// Context for comment-only assistant.
class AsanaCommentAiFormSnapshot {
  const AsanaCommentAiFormSnapshot({
    required this.taskName,
    required this.currentComment,
  });

  final String taskName;
  final String currentComment;

  String buildLlmContext() {
    return '''
Task: ${taskName.isEmpty ? "(unnamed task)" : taskName}
Current comment draft: ${currentComment.isEmpty ? "(empty)" : currentComment}

You may ONLY suggest an improved comment body. Do not change task name, dates, assignees, or any other task field.
''';
  }
}

/// One adoptable suggestion or a skip / info line.
class AsanaTaskAiSuggestionLine {
  const AsanaTaskAiSuggestionLine.adopt({
    required this.fieldKey,
    required this.fieldLabel,
    required this.currentValue,
    required this.suggestedText,
    required this.onAdopt,
  })  : message = null,
        adoptable = true,
        isWarning = false;

  const AsanaTaskAiSuggestionLine.info(
    this.message, {
    this.fieldKey = AsanaTaskAiFieldKey.global,
    this.isWarning = false,
  })  : fieldLabel = null,
        currentValue = null,
        suggestedText = null,
        onAdopt = null,
        adoptable = false;

  const AsanaTaskAiSuggestionLine.warning(this.message)
      : fieldKey = AsanaTaskAiFieldKey.global,
        fieldLabel = null,
        currentValue = null,
        suggestedText = null,
        onAdopt = null,
        adoptable = false,
        isWarning = true;

  final AsanaTaskAiFieldKey fieldKey;
  final String? fieldLabel;
  final String? currentValue;
  final String? suggestedText;
  final String? message;
  final VoidCallback? onAdopt;
  final bool adoptable;
  final bool isWarning;

  static String _displayCurrent(String value) =>
      value.trim().isEmpty ? '(empty)' : value.trim();
}

/// Validates LLM JSON and builds adoptable lines (no auto-apply).
class AsanaTaskAiSuggestionBuilder {
  static List<AsanaTaskAiSuggestionLine> build({
    required Map<String, dynamic> raw,
    required AsanaTaskAiFormSnapshot form,
    required AsanaTaskAiApply apply,
  }) {
    final related = raw['related'];
    if (related is bool && !related) {
      final msg = _str(raw['message']) ??
          'This prompt does not look related to filling in task details.';
      return [AsanaTaskAiSuggestionLine.warning(msg)];
    }

    final lines = <AsanaTaskAiSuggestionLine>[];
    final note = _str(raw['message']);
    if (note != null && note.isNotEmpty) {
      lines.add(AsanaTaskAiSuggestionLine.info(note));
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
          'Start and due dates were not suggested because the start date would be after the due date.',
          fieldKey: AsanaTaskAiFieldKey.startDate,
        ),
      );
    }

    final name = _str(raw['name']);
    if (name != null &&
        name.isNotEmpty &&
        !_sameNormalizedText(name, form.name)) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.taskName,
          fieldLabel: 'Task name',
          currentValue: AsanaTaskAiSuggestionLine._displayCurrent(form.name),
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
              AsanaTaskAiSuggestionLine._displayCurrent(form.description),
          suggestedText: desc,
          onAdopt: () => apply.applyDescription(desc),
        ),
      );
    }

    if (form.canSuggestProject) {
      final projName = _str(raw['projectName']);
      if (projName != null && projName.isNotEmpty) {
        final id = _matchProjectId(projName, form.projects);
        if (id == null) {
          lines.add(
            AsanaTaskAiSuggestionLine.info(
              'Project "$projName" was not found in your project list.',
              fieldKey: AsanaTaskAiFieldKey.project,
            ),
          );
        } else if (id != form.selectedProjectId) {
          lines.add(
            AsanaTaskAiSuggestionLine.adopt(
              fieldKey: AsanaTaskAiFieldKey.project,
              fieldLabel: 'Project',
              currentValue:
                  AsanaTaskAiSuggestionLine._displayCurrent(form.projectLabel),
              suggestedText: projName,
              onAdopt: () => apply.applyProject(id),
            ),
          );
        }
      }
    }

    if (form.canSuggestAssignees) {
      var workingAssignees = Set<String>.from(form.selectedAssigneeIds);
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
        if (resolved.isNotEmpty) {
          workingAssignees = resolved;
        }
      }

      String? proposedPicId;
      final picName = _str(raw['picName']);
      if (picName != null && picName.isNotEmpty) {
        final picIds = _matchStaffIds(picName, form.staff);
        if (picIds.isEmpty) {
          lines.add(
            AsanaTaskAiSuggestionLine.info(
              'PIC "$picName" was not found in the staff list.',
              fieldKey: AsanaTaskAiFieldKey.pic,
            ),
          );
        } else if (picIds.length > 1) {
          lines.add(
            AsanaTaskAiSuggestionLine.info(
              'Several staff match "$picName": '
              '${_staffNamesForIds(picIds, form.staff)}. Choose PIC manually.',
              fieldKey: AsanaTaskAiFieldKey.pic,
            ),
          );
        } else {
          proposedPicId = picIds.single;
          workingAssignees = {...workingAssignees, proposedPicId};
        }
      }

      if (!_sameIdSet(workingAssignees, form.selectedAssigneeIds)) {
        final label = _staffNamesForIds(workingAssignees.toList(), form.staff);
        final ids = workingAssignees;
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.assignees,
            fieldLabel: 'Assignees',
            currentValue: AsanaTaskAiSuggestionLine._displayCurrent(
              form.assigneesLabel,
            ),
            suggestedText: label,
            onAdopt: () => apply.applyAssignees(ids),
          ),
        );
      }

      if (proposedPicId != null && proposedPicId != form.picAssigneeId) {
        final picId = proposedPicId;
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.pic,
            fieldLabel: 'PIC',
            currentValue:
                AsanaTaskAiSuggestionLine._displayCurrent(form.picLabel),
            suggestedText: _staffNameForId(picId, form.staff),
            onAdopt: () => apply.applyPic(picId),
          ),
        );
      }
    }

    final pr = _str(raw['priority']);
    if (pr != null && pr.isNotEmpty) {
      final p = _parsePriority(pr);
      if (p == null) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Priority "$pr" was not recognized (use Standard or URGENT).',
            fieldKey: AsanaTaskAiFieldKey.priority,
          ),
        );
      } else if (p != form.priority) {
        lines.add(
          AsanaTaskAiSuggestionLine.adopt(
            fieldKey: AsanaTaskAiFieldKey.priority,
            fieldLabel: 'Priority',
            currentValue: priorityToDisplayName(form.priority),
            suggestedText: priorityToDisplayName(p),
            onAdopt: () => apply.applyPriority(p),
          ),
        );
      }
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
      } else if (startRaw != null && startRaw.isNotEmpty) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Start date "$startRaw" could not be parsed (use YYYY-MM-DD).',
            fieldKey: AsanaTaskAiFieldKey.startDate,
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
      } else if (dueRaw != null && dueRaw.isNotEmpty) {
        lines.add(
          AsanaTaskAiSuggestionLine.info(
            'Due date "$dueRaw" could not be parsed (use YYYY-MM-DD).',
            fieldKey: AsanaTaskAiFieldKey.dueDate,
          ),
        );
      }
    }

    final hasAdopt = lines.any((l) => l.adoptable);
    if (!hasAdopt && lines.isEmpty) {
      return [
        const AsanaTaskAiSuggestionLine.info(
          'No task fields could be inferred from this prompt. Try being more specific about name, dates, assignees, or priority.',
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

  static String? _matchProjectId(
    String name,
    List<({String id, String name})> projects,
  ) {
    final q = name.trim().toLowerCase();
    for (final p in projects) {
      if (p.name.trim().toLowerCase() == q) return p.id;
    }
    for (final p in projects) {
      if (p.name.trim().toLowerCase().contains(q)) return p.id;
    }
    return null;
  }

  /// All staff matching a name or partial token (e.g. "Ken" → Ken Lee & Ken Wong).
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

  static String _staffNameForId(
    String id,
    List<({String id, String name})> staff,
  ) {
    for (final s in staff) {
      if (s.id == id) return s.name.trim();
    }
    return id;
  }

  static String _staffNamesForIds(
    List<String> ids,
    List<({String id, String name})> staff,
  ) {
    return ids.map((id) => _staffNameForId(id, staff)).join(', ');
  }

  static int? _parsePriority(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.contains('urgent')) return priorityUrgent;
    if (s.contains('standard')) return priorityStandard;
    return null;
  }

  static DateTime? _parseYmd(String raw) {
    final t = raw.trim();
    final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
    if (m != null) {
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
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

/// Comment-only suggestions (assignees editing a task).
class AsanaCommentAiSuggestionBuilder {
  static List<AsanaTaskAiSuggestionLine> build({
    required Map<String, dynamic> raw,
    required AsanaCommentAiFormSnapshot form,
    required void Function(String comment) applyComment,
  }) {
    final related = raw['related'];
    if (related is bool && !related) {
      final msg = _str(raw['message']) ??
          'This prompt does not look related to writing a task comment.';
      return [AsanaTaskAiSuggestionLine.warning(msg)];
    }

    final lines = <AsanaTaskAiSuggestionLine>[];
    final comment = _str(raw['comment']);
    if (comment != null && comment.isNotEmpty) {
      lines.add(
        AsanaTaskAiSuggestionLine.adopt(
          fieldKey: AsanaTaskAiFieldKey.comment,
          fieldLabel: 'Comment',
          currentValue:
              AsanaTaskAiSuggestionLine._displayCurrent(form.currentComment),
          suggestedText: comment,
          onAdopt: () => applyComment(comment),
        ),
      );
    }

    if (lines.isEmpty) {
      return [
        const AsanaTaskAiSuggestionLine.info(
          'No comment suggestion from this prompt. Describe what you want to say in the comment box.',
        ),
      ];
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
}

/// Callbacks when user taps adopt (✓) on a suggestion.
class AsanaTaskAiApply {
  const AsanaTaskAiApply({
    required this.applyName,
    required this.applyDescription,
    required this.applyProject,
    required this.applyAssignees,
    required this.applyPic,
    required this.applyPriority,
    required this.applyStartDate,
    required this.applyDueDate,
  });

  final void Function(String name) applyName;
  final void Function(String description) applyDescription;
  final void Function(String projectId) applyProject;
  final void Function(Set<String> assigneeIds) applyAssignees;
  final void Function(String picAssigneeId) applyPic;
  final void Function(int priority) applyPriority;
  final void Function(DateTime start) applyStartDate;
  final void Function(DateTime due) applyDueDate;
}

/// Holds prompt + suggestion state; shared by prompt bar and inline field rows.
class AsanaTaskAiController extends ChangeNotifier {
  AsanaTaskAiController({
    required this.mode,
    required this.readOnly,
    this.formSnapshot,
    this.apply,
    this.commentSnapshot,
    this.onApplyComment,
  })  : assert(
          mode == AsanaTaskAiAssistantMode.taskFields
              ? formSnapshot != null && apply != null
              : commentSnapshot != null && onApplyComment != null,
        );

  final AsanaTaskAiAssistantMode mode;
  final bool Function() readOnly;
  final AsanaTaskAiFormSnapshot Function()? formSnapshot;
  final AsanaTaskAiApply? apply;
  final AsanaCommentAiFormSnapshot Function()? commentSnapshot;
  final void Function(String comment)? onApplyComment;

  final promptController = TextEditingController();
  bool busy = false;
  String? error;
  List<AsanaTaskAiSuggestionLine> lines = [];

  /// Called after a successful analyse (dock collapses, prompt cleared).
  VoidCallback? onAnalyseSuccess;

  List<AsanaTaskAiSuggestionLine> linesForField(AsanaTaskAiFieldKey key) =>
      lines.where((l) => l.fieldKey == key).toList();

  List<AsanaTaskAiSuggestionLine> get globalLines =>
      lines.where((l) => l.fieldKey == AsanaTaskAiFieldKey.global).toList();

  /// Removes inline suggestions for one field (after user taps ✓ or ✕).
  void dismissField(AsanaTaskAiFieldKey key) {
    final n = lines.length;
    lines.removeWhere((l) => l.fieldKey == key);
    if (lines.length != n) notifyListeners();
  }

  /// Clears all suggestions (e.g. user saved the task via Update).
  void clearAllSuggestions() {
    if (lines.isEmpty && error == null) return;
    lines = [];
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  Future<void> analyse() async {
    if (readOnly() || !DeepseekService.isConfigured) return;
    busy = true;
    error = null;
    lines = [];
    notifyListeners();
    try {
      final prompt = promptController.text;
      if (mode == AsanaTaskAiAssistantMode.commentOnly) {
        final form = commentSnapshot!();
        final raw = await DeepseekService.suggestCommentDraft(
          userPrompt: prompt,
          formContext: form.buildLlmContext(),
        );
        lines = AsanaCommentAiSuggestionBuilder.build(
          raw: raw,
          form: form,
          applyComment: onApplyComment!,
        );
      } else {
        final form = formSnapshot!();
        final raw = await DeepseekService.suggestAsanaTaskDraft(
          userPrompt: prompt,
          formContext: form.buildLlmContext(),
        );
        lines = AsanaTaskAiSuggestionBuilder.build(
          raw: raw,
          form: form,
          apply: apply!,
        );
      }
      busy = false;
      promptController.clear();
      onAnalyseSuccess?.call();
      notifyListeners();
    } catch (e, st) {
      debugPrint('$e\n$st');
      busy = false;
      error = e.toString();
      notifyListeners();
    }
  }
}

/// Collapsible AI dock pinned above the slide action footer.
class AsanaTaskAiDock extends StatefulWidget {
  const AsanaTaskAiDock({
    super.key,
    required this.controller,
    required this.palette,
    required this.footerBorder,
  });

  final AsanaTaskAiController controller;
  final AsanaLandingPalette palette;
  final Color footerBorder;

  @override
  State<AsanaTaskAiDock> createState() => _AsanaTaskAiDockState();
}

class _AsanaTaskAiDockState extends State<AsanaTaskAiDock> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    widget.controller.onAnalyseSuccess = _onAnalyseSuccess;
  }

  @override
  void didUpdateWidget(covariant AsanaTaskAiDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.onAnalyseSuccess = null;
      widget.controller.onAnalyseSuccess = _onAnalyseSuccess;
    }
  }

  @override
  void dispose() {
    widget.controller.onAnalyseSuccess = null;
    super.dispose();
  }

  void _onAnalyseSuccess() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AsanaTaskAiColors.fromPalette(widget.palette);
    final commentOnly =
        widget.controller.mode == AsanaTaskAiAssistantMode.commentOnly;

    return Material(
      color: colors.boxBackground,
      elevation: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: widget.footerBorder),
          ),
        ),
        child: SafeArea(
          top: false,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: colors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI assistant',
                            style: asanaDetailValueStyle(
                              context,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: kAsanaTextSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _AsanaTaskAiPromptContent(
                      controller: widget.controller,
                      palette: widget.palette,
                      colors: colors,
                      commentOnly: commentOnly,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AsanaTaskAiPromptContent extends StatelessWidget {
  const _AsanaTaskAiPromptContent({
    required this.controller,
    required this.palette,
    required this.colors,
    required this.commentOnly,
  });

  final AsanaTaskAiController controller;
  final AsanaLandingPalette palette;
  final AsanaTaskAiColors colors;
  final bool commentOnly;

  bool _enterSubmitsPrompt(BuildContext context) {
    if (!kIsWeb) return false;
    return MediaQuery.sizeOf(context).width >= 600;
  }

  @override
  Widget build(BuildContext context) {
    final configured = DeepseekService.isConfigured;
    final enterSubmits = _enterSubmitsPrompt(context);
    final readOnly = controller.readOnly();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final globalLines = controller.globalLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              commentOnly
                  ? 'This assistant helps you write a better comment.'
                  : 'Describe the task, then tap Analyse. Suggestions appear on matching fields.',
              style: asanaDetailLabelStyle(context),
            ),
            if (!configured) ...[
              const SizedBox(height: 8),
              Text(
                'Not configured. Run with secrets\\deepseek_api_key.txt or '
                '--dart-define=DEEPSEEK_API_KEY=...',
                style: asanaDetailLabelStyle(context).copyWith(
                  color: const Color(0xFFC62828),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Focus(
              onKeyEvent: (node, event) {
                if (!enterSubmits) return KeyEventResult.ignored;
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey != LogicalKeyboardKey.enter) {
                  return KeyEventResult.ignored;
                }
                if (HardwareKeyboard.instance.isShiftPressed ||
                    HardwareKeyboard.instance.isControlPressed ||
                    HardwareKeyboard.instance.isMetaPressed ||
                    HardwareKeyboard.instance.isAltPressed) {
                  return KeyEventResult.ignored;
                }
                if (readOnly || !configured || controller.busy) {
                  return KeyEventResult.handled;
                }
                controller.analyse();
                return KeyEventResult.handled;
              },
              child: TextField(
                controller: controller.promptController,
                readOnly: readOnly || !configured,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: 'Your prompt',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  alignLabelWithHint: true,
                  helperText: enterSubmits
                      ? 'Enter to analyse · Shift+Enter for new line'
                      : null,
                  filled: true,
                  fillColor: palette.listSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.boxBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.accent, width: 2),
                  ),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: readOnly || !configured || controller.busy
                    ? null
                    : controller.analyse,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: palette.darkChrome
                      ? Colors.white
                      : palette.onBanner,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: controller.busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.darkChrome
                              ? Colors.white
                              : palette.onBanner,
                        ),
                      )
                    : const Text('Analyse prompt'),
              ),
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 10),
              SelectableText(
                controller.error!,
                style: asanaDetailLabelStyle(context).copyWith(
                  color: const Color(0xFFC62828),
                ),
              ),
            ],
            if (globalLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...globalLines.map(
                (line) => _SuggestionRow(line: line, colors: colors),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Inline suggestion(s) beside or under the matching form field.
class AsanaTaskAiInlineSuggestions extends StatelessWidget {
  const AsanaTaskAiInlineSuggestions({
    super.key,
    required this.controller,
    required this.fieldKey,
    required this.palette,
  });

  final AsanaTaskAiController controller;
  final AsanaTaskAiFieldKey fieldKey;
  final AsanaLandingPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = AsanaTaskAiColors.fromPalette(palette);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final fieldLines = controller.linesForField(fieldKey);
        if (fieldLines.isEmpty) return const SizedBox.shrink();

        final fullWidth = asanaTaskAiFieldUsesFullWidth(fieldKey);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: fieldLines.map((line) {
            final isWarning = line.isWarning;
            return AsanaDetailSuggestedValueRow(
              insetLabelColumn: !fullWidth,
              labelColor: colors.suggestedLabel,
              borderColor: isWarning
                  ? const Color(0xFFFDBA74)
                  : colors.boxBorder,
              fillColor: line.adoptable || isWarning
                  ? (isWarning
                      ? const Color(0xFFFFF7ED)
                      : colors.cardSurface)
                  : null,
              wrapField: line.adoptable
                  ? (field) => _GlowingAdoptCard(
                        colors: colors,
                        child: field,
                      )
                  : null,
              child: _SuggestionRow(
                line: line,
                colors: colors,
                onAdopt: line.adoptable
                    ? () {
                        line.onAdopt?.call();
                        controller.dismissField(fieldKey);
                      }
                    : null,
                onReject: line.adoptable
                    ? () => controller.dismissField(fieldKey)
                    : null,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.line,
    required this.colors,
    this.onAdopt,
    this.onReject,
  });

  final AsanaTaskAiSuggestionLine line;
  final AsanaTaskAiColors colors;
  final VoidCallback? onAdopt;
  final VoidCallback? onReject;

  static const _warningColor = Color(0xFFB45309);
  static const _rejectColor = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    final valueStyle = asanaDetailValueStyle(context);

    if (!line.adoptable) {
      final isWarning = line.isWarning;
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          line.message ?? '',
          style: asanaDetailLabelStyle(context).copyWith(
            color: isWarning ? _warningColor : kAsanaTextSecondary,
            fontWeight: isWarning ? FontWeight.w600 : FontWeight.normal,
            height: 1.35,
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            line.suggestedText!,
            style: valueStyle.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ),
        if (onReject != null) _compactActionIcon(
          tooltip: 'Dismiss suggestion',
          icon: Icons.cancel_outlined,
          color: _rejectColor,
          onPressed: onReject,
        ),
        if (onAdopt != null) _compactActionIcon(
          tooltip: 'Apply this suggestion',
          icon: Icons.check_circle_outline,
          color: colors.adoptIcon,
          onPressed: onAdopt,
        ),
      ],
    );
  }

  Widget _compactActionIcon({
    required String tooltip,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: color),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 28,
        ),
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Pulsing border glow on adoptable suggestion cards.
class _GlowingAdoptCard extends StatefulWidget {
  const _GlowingAdoptCard({required this.colors, required this.child});

  final AsanaTaskAiColors colors;
  final Widget child;

  @override
  State<_GlowingAdoptCard> createState() => _GlowingAdoptCardState();
}

class _GlowingAdoptCardState extends State<_GlowingAdoptCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final edge = Color.lerp(
          widget.colors.accent,
          Color.lerp(widget.colors.accent, Colors.white, 0.45)!,
          t,
        )!;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: edge.withValues(alpha: 0.22 + t * 0.28),
                blurRadius: 6 + t * 10,
                spreadRadius: 0.5 + t * 1.5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
