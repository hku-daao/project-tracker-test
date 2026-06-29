import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenAI-compatible DeepSeek chat API.
///
/// Pass at build time: `--dart-define=DEEPSEEK_API_KEY=sk-...`
/// Optional: `--dart-define=DEEPSEEK_MODEL=deepseek-chat`
class DeepseekService {
  DeepseekService._();

  static const String _url = 'https://api.deepseek.com/v1/chat/completions';

  static const String apiKey = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: '',
  );

  static const String model = String.fromEnvironment(
    'DEEPSEEK_MODEL',
    defaultValue: 'deepseek-chat',
  );

  static bool get isConfigured => apiKey.trim().isNotEmpty;

  /// Asks the model for a short title and longer description (JSON).
  static Future<({String title, String description})> suggestTitleDescription({
    required String userPrompt,
    String? extraContext,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Missing DEEPSEEK_API_KEY. Rebuild with '
        '--dart-define=DEEPSEEK_API_KEY=your_key',
      );
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    final ctx = extraContext?.trim();
    final system = StringBuffer()
      ..writeln(
        'You draft items for a workplace project tracker. '
        'Reply with ONLY a single JSON object (no markdown, no code fences): '
        '{"title":"...","description":"..."}. '
        'title: one short line. description: plain text for assignees; may use newlines.',
      );
    if (ctx != null && ctx.isNotEmpty) {
      system.writeln('Context:\n$ctx');
    }

    final body = jsonEncode({
      'model': model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      'messages': [
        {'role': 'system', 'content': system.toString()},
        {'role': 'user', 'content': trimmed},
      ],
      'temperature': 0.35,
    });

    final content = await _chatCompletionContent(body);
    final parsed = _parseTitleDescriptionJson(content);
    if (parsed == null) {
      throw FormatException(
        'Could not parse JSON from model. Raw (truncated): '
        '${content.length > 400 ? content.substring(0, 400) : content}',
      );
    }
    return parsed;
  }

  static ({String title, String description})? _parseTitleDescriptionJson(
    String raw,
  ) {
    final map = parseJsonObjectFromModel(raw);
    if (map == null) return null;
    final t = map['title'];
    final d = map['description'];
    if (t is! String || d is! String) return null;
    return (title: t.trim(), description: d.trim());
  }

  /// Structured task-field suggestions for the Asana create/edit slide.
  static Future<Map<String, dynamic>> suggestAsanaTaskDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Missing DEEPSEEK_API_KEY. Rebuild with '
        '--dart-define=DEEPSEEK_API_KEY=your_key',
      );
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users fill a task form in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when nothing can be suggested",
  "overallComment": "when you suggest any field change: 1-3 sentences summarizing what you inferred and what the user can adopt (required if any name/description/comment/project/assignees/pic/priority/dates/websiteLinks are set)",
  "name": "string or null",
  "description": "string or null",
  "comment": "comment body for the Comments field (posted when the user saves), or null",
  "projectName": "exact name from available projects list, or null",
  "assigneeNames": ["names from available staff list"] or [],
  "picName": "one staff name (must be in assigneeNames if assignees set), or null",
  "priority": "Standard" or "URGENT" or null,
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null,
  "reason": "reason for needing a long time to complete the task, or null",
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or []
}

Rules:
- The user is already working inside a task create/edit slide. Treat every prompt as an attempt to fill or improve this task form. Always set "related": true.
- Always try to suggest at least one useful field. Prefer name and description when the prompt contains task details; if the prompt is vague, make a best-effort improvement based on the prompt plus current form values.
- For optional structured fields (project, assignees, PIC, priority, dates, reason, websiteLinks), suggest them when the prompt mentions or implies them. Use null or omit fields you cannot infer.
- Avoid echoing unchanged values: compare each field to "Current form values" in context. If a suggested value would be identical to what is already on the form, improve/expand it when reasonable; otherwise omit that specific field.
- comment: text for the Comments field (a draft posted when the user saves the task). When the user asks to write, add, or improve a comment, set comment to the full suggested text. Compare to "comment (draft)" in context; omit if identical.
- Use assignee and project names only from the provided staff/projects lists.
- Assignees: when the user adds or removes people, set assigneeNames to the full resulting assignee list (start from current assignees in context, apply add/remove, then list everyone who should remain).
- PIC: the PIC must always be one of the assignees. If the user sets or changes PIC to someone, include that person in assigneeNames even if the user did not say "assignee" for them (e.g. "add A and B as assignees, C as PIC" → assigneeNames: A, B, C and picName: C).
- picName must match someone in assigneeNames when both are set.
- Dates must be YYYY-MM-DD. If the user gives a range, set startDate and dueDate accordingly.
- Do not contradict yourself: startDate must be on or before dueDate when both are set.
- reason: only suggest when the current form shows or implies a long duration that needs explanation. It should explain why the task needs that much time, in one concise sentence.
- Website links: when the user mentions one or more URLs (http/https or bare domains), add each as an entry in websiteLinks with a concise description (what the link is for). Use full https URLs when possible. Do not repeat URLs already listed under "Current website link attachments" in context. Omit websiteLinks when no URLs are mentioned.
- overallComment: required whenever you output at least one non-null field suggestion (name, description, comment, projectName, assigneeNames, picName, priority, startDate, dueDate, reason, or websiteLinks). Summarize the intended updates in plain language; do not list unchanged fields.
- You are suggesting values only; the app will show suggestions and the user adopts them. Do not mention overwriting.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.25,
    });

    final content = await _chatCompletionContent(body);
    final map = parseJsonObjectFromModel(content);
    if (map == null) {
      throw FormatException(
        'Could not parse JSON from model. Raw (truncated): '
        '${content.length > 400 ? content.substring(0, 400) : content}',
      );
    }
    return map;
  }

  /// Structured project-field suggestions for the Asana project slide.
  static Future<Map<String, dynamic>> suggestAsanaProjectDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Missing DEEPSEEK_API_KEY. Rebuild with '
        '--dart-define=DEEPSEEK_API_KEY=your_key',
      );
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users fill a project form in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when nothing can be suggested",
  "overallComment": "when you suggest any field change: 1-3 sentences summarizing what you inferred (required if any name/description/comment/status/assigneeNames/picNames/startDate/dueDate/websiteLinks are set)",
  "name": "string or null",
  "description": "string or null",
  "comment": "comment body for the Comments field (posted when the user saves), or null",
  "status": "Not started" or "In progress" or "Completed" or null,
  "assigneeNames": ["names from available staff list"] or [],
  "picNames": ["names from available staff list, must be assignees"] or [],
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null,
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or []
}

Rules:
- The user is already working inside a project create/edit slide. Treat every prompt as an attempt to fill or improve this project form. Always set "related": true.
- Always try to suggest at least one useful field. Prefer name and description when the prompt contains project details; if the prompt is vague, make a best-effort improvement based on the prompt plus current project form values.
- For optional structured fields (status, assigneeNames, picNames, startDate, dueDate, comment, websiteLinks), suggest them when the prompt mentions or implies them. Use null or omit fields you cannot infer.
- Avoid echoing unchanged values: compare each field to "Current project form values" in context. If a suggested value would be identical to what is already on the form, improve/expand it when reasonable; otherwise omit that specific field.
- Use assignee and PIC names only from the provided staff list.
- assigneeNames: full resulting assignee list when the user changes assignees.
- picNames: PIC(s) must be chosen from assigneeNames. When one assignee, they are usually PIC too.
- Dates must be YYYY-MM-DD. startDate must be on or before dueDate when both are set.
- status must be exactly one of: Not started, In progress, Completed.
- comment: text for the Comments field. When the user asks to write, add, or improve a comment, set comment to the full suggested text. Compare to "comment (draft)" in context; omit if identical.
- Website links: when the user mentions one or more URLs (http/https or bare domains), add each as an entry in websiteLinks with a concise description. Use full https URLs when possible. Do not repeat URLs already listed under "Current website link attachments" in context. Omit websiteLinks when no URLs are mentioned.
- overallComment: required whenever you output at least one non-null field suggestion.
- You are suggesting values only; the user adopts them. Do not mention overwriting.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.25,
    });

    final content = await _chatCompletionContent(body);
    final map = parseJsonObjectFromModel(content);
    if (map == null) {
      throw FormatException(
        'Could not parse JSON from model. Raw (truncated): '
        '${content.length > 400 ? content.substring(0, 400) : content}',
      );
    }
    return map;
  }

  /// Comment-only suggestions for assignees (does not touch task metadata).
  static Future<Map<String, dynamic>> suggestCommentDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Missing DEEPSEEK_API_KEY. Rebuild with '
        '--dart-define=DEEPSEEK_API_KEY=your_key',
      );
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users write a comment on an existing task in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when no comment can be suggested",
  "overallComment": "when comment is set: 1-2 sentences on how you improved the draft (required if comment is non-null)",
  "comment": "improved comment text or null",
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or []
}

Rules:
- Set "related": false only if the prompt is clearly unrelated to drafting a task comment.
- You may ONLY suggest the comment body or website links. Never suggest task name, description, dates, assignees, PIC, priority, or project.
- Improve clarity and tone; keep the user's intent. Use the task name and current draft for context.
- Website links: when the user mentions one or more URLs, add each as an entry in websiteLinks with a concise description. Do not repeat URLs already listed under "Current website link attachments".
- overallComment: required when comment or websiteLinks is non-null/non-empty; briefly explain what you changed or added.
- You are suggesting text/links only; the user adopts it into the comment/attachments field. Do not mention other fields.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.25,
    });

    final content = await _chatCompletionContent(body);
    final map = parseJsonObjectFromModel(content);
    if (map == null) {
      throw FormatException(
        'Could not parse JSON from model. Raw (truncated): '
        '${content.length > 400 ? content.substring(0, 400) : content}',
      );
    }
    return map;
  }

  /// Structured subtask-field suggestions for the Asana subtask slide.
  static Future<Map<String, dynamic>> suggestAsanaSubtaskDraft({
    required String userPrompt,
    required String formContext,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Missing DEEPSEEK_API_KEY. Rebuild with '
        '--dart-define=DEEPSEEK_API_KEY=your_key',
      );
    }
    final trimmed = userPrompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Prompt is empty');
    }

    const system = '''
You help users fill a sub-task form in a workplace project tracker.
Reply with ONLY one JSON object (no markdown, no code fences).

Schema:
{
  "related": true or false,
  "message": "optional short note when nothing can be suggested",
  "overallComment": "when you suggest any field change: 1-3 sentences summarizing what you inferred and what the user can adopt",
  "name": "string or null",
  "description": "sub-task description/details, or null",
  "assigneeNames": ["names from available sub-task assignees list"] or [],
  "picName": "one staff name (must be in assigneeNames if assignees set), or null",
  "priority": "Standard" or "URGENT" or null,
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null,
  "reason": "reason for needing a long time to complete the sub-task, or null",
  "comment": "comment body for the Comments field (posted when the user saves), or null",
  "websiteLinks": [
    { "url": "https://...", "description": "short label for the link" }
  ] or []
}

Rules:
- The user is already working inside a sub-task create/edit slide. Treat every prompt as an attempt to fill or improve this sub-task form. Always set "related": true.
- Always try to suggest at least one useful field. Prioritize suggesting BOTH name and description when the prompt provides enough sub-task detail; if the prompt is vague, make a best-effort improvement based on the prompt plus current form values.
- For optional structured fields (assigneeNames, picName, priority, dates, reason, comment, websiteLinks), suggest them when the prompt mentions or implies them. Use null or omit fields you cannot infer.
- Avoid echoing unchanged values: compare each field to "Current form values" in context. If a suggested value would be identical, improve/expand it when reasonable; otherwise omit that specific field.
- The description should be useful execution detail, not just a repeat of the name.
- Use assignee and PIC names only from the available sub-task assignees list in context.
- Assignees: when the user adds or removes people, set assigneeNames to the full resulting assignee list (start from current assignees in context, apply add/remove, then list everyone who should remain).
- PIC: the PIC must always be one of the assignees. If the user sets or changes PIC to someone, include that person in assigneeNames even if the user did not say "assignee" for them.
- Dates must be YYYY-MM-DD. If the user gives a range, set startDate and dueDate accordingly.
- Relative dates such as "today", "tomorrow", "next week", or weekdays MUST be calculated from "Today (Hong Kong)" in the context, not from the current form's existing start/due dates.
- Do not contradict yourself: startDate must be on or before dueDate when both are set.
- comment: text for the Comments field. Compare to "comment (draft)" in context; omit if identical.
- reason: only suggest when the context says reason is editable and the long duration needs explanation. It should explain why the sub-task needs that much time, in one concise sentence.
- Website links: when the user mentions one or more URLs, add each as an entry in websiteLinks with a concise description. Do not repeat URLs already listed under "Current website link attachments".
- The user may or may not be the creator. If the user is NOT the creator, they cannot modify the name. The context will tell you if the name field is modifiable. If not modifiable, DO NOT suggest a name.
- Use the parent task context provided to understand the context of the sub-task.
- If assignees are discussed, treat the "Available sub-task assignees" list in context as the only valid people. Never suggest assigning someone outside that list.
- Attachments are represented as websiteLinks. Include URLs in websiteLinks, not in the comment text, unless the user explicitly asks to write them into the comment.
- overallComment: required whenever you output at least one non-null field suggestion. Summarize the intended updates in plain language.
- You are suggesting values only; the app will show suggestions and the user adopts them. Do not mention overwriting.
''';

    final user = StringBuffer()
      ..writeln(formContext.trim())
      ..writeln()
      ..writeln('User prompt:')
      ..writeln(trimmed);

    final body = jsonEncode({
      'model': model.trim().isEmpty ? 'deepseek-chat' : model.trim(),
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user.toString()},
      ],
      'temperature': 0.35,
    });

    final content = await _chatCompletionContent(body);
    final map = parseJsonObjectFromModel(content);
    if (map == null) {
      throw FormatException(
        'Could not parse JSON from model. Raw (truncated): '
        '${content.length > 400 ? content.substring(0, 400) : content}',
      );
    }
    return map;
  }

  static Future<String> _chatCompletionContent(String body) async {
    final res = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Authorization': 'Bearer ${apiKey.trim()}',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 120));

    if (res.statusCode != 200) {
      String detail = res.body;
      try {
        final m = jsonDecode(res.body);
        if (m is Map && m['error'] is Map) {
          final err = m['error'] as Map;
          detail = '${err['type'] ?? 'error'}: ${err['message'] ?? res.body}';
        }
      } catch (_) {}
      throw DeepseekHttpException(
        'DeepSeek HTTP ${res.statusCode}',
        detail.isNotEmpty ? detail : null,
      );
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected API response shape');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('No choices in API response');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('Invalid choice object');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Invalid message object');
    }
    final content = message['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const FormatException('Empty model content');
    }
    return content;
  }

  static Map<String, dynamic>? parseJsonObjectFromModel(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      final lines = s.split('\n');
      if (lines.length > 2) {
        s = lines.sublist(1, lines.length - 1).join('\n').trim();
      }
    }
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    final i = s.indexOf('{');
    final j = s.lastIndexOf('}');
    if (i >= 0 && j > i) {
      try {
        final decoded = jsonDecode(s.substring(i, j + 1));
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }
}

class DeepseekHttpException implements Exception {
  DeepseekHttpException(this.message, [this.detail]);

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message\n$detail';
}
