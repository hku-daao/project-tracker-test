import 'dart:convert';

import 'package:http/http.dart' as http;

/// OpenAI-compatible DeepSeek chat API.
///
/// Pass at build time: `--dart-define=DEEPSEEK_API_KEY=sk-...`
/// Optional: `--dart-define=DEEPSEEK_MODEL=deepseek-chat`
class DeepseekService {
  DeepseekService._();

  static const String _url =
      'https://api.deepseek.com/v1/chat/completions';

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
  "message": "optional short note to the user",
  "name": "string or null",
  "description": "string or null",
  "projectName": "exact name from available projects list, or null",
  "assigneeNames": ["names from available staff list"] or [],
  "picName": "one staff name (must be in assigneeNames if assignees set), or null",
  "priority": "Standard" or "URGENT" or null,
  "startDate": "YYYY-MM-DD" or null,
  "dueDate": "YYYY-MM-DD" or null
}

Rules:
- Set "related": false only if the prompt is clearly unrelated to creating or updating a task.
- Only include fields the user clearly wants to set or change. Use null or omit for unsure fields.
- NEVER echo unchanged values: compare each field to "Current form values" in context. If your suggestion would be identical to what is already on the form, omit that field (null). Example: if the user only describes what the task is about, suggest name and/or description only — do not output assignees, PIC, priority, dates, or project unless the user asked to change them AND the new value differs from current.
- Use assignee and project names only from the provided staff/projects lists.
- Assignees: when the user adds or removes people, set assigneeNames to the full resulting assignee list (start from current assignees in context, apply add/remove, then list everyone who should remain).
- PIC: the PIC must always be one of the assignees. If the user sets or changes PIC to someone, include that person in assigneeNames even if the user did not say "assignee" for them (e.g. "add A and B as assignees, C as PIC" → assigneeNames: A, B, C and picName: C).
- picName must match someone in assigneeNames when both are set.
- Dates must be YYYY-MM-DD. If the user gives a range, set startDate and dueDate accordingly.
- Do not contradict yourself: startDate must be on or before dueDate when both are set.
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
  "message": "optional short note to the user",
  "comment": "improved comment text or null"
}

Rules:
- Set "related": false only if the prompt is clearly unrelated to drafting a task comment.
- You may ONLY suggest the comment body. Never suggest task name, description, dates, assignees, PIC, priority, or project.
- Improve clarity and tone; keep the user's intent. Use the task name and current draft for context.
- You are suggesting text only; the user adopts it into the comment field. Do not mention other fields.
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
  String toString() =>
      detail == null ? message : '$message\n$detail';
}
