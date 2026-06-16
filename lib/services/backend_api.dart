import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Client for the Railway backend API.
class BackendApi {
  BackendApi({String? baseUrl}) : _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String _baseUrl;

  String get baseUrl => _baseUrl;

  /// Build full URL for a path (ensures single slash between base and path).
  Uri url(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p');
  }

  /// Returned by [notifySubtaskUpdated] when the server sends generic 404
  /// `{ error: 'Not found' }` (no route matched). Redeploy the Railway backend
  /// from this repo so `POST /api/notify/subtask-updated` is registered.
  static const String notifySubtaskUpdatedBackendNotDeployed =
      'NOTIFY_SUBTASK_UPDATED_BACKEND_NOT_DEPLOYED';

  /// Creates a one-time Railway URL that streams the file (no Firebase `token=` in the address bar).
  ///
  /// Requires [BackendApi] deployment with `POST /api/attachment/open-session` and
  /// `GET /api/attachment/stream/:id`. Server enforces the same rules as [storage.rules]
  /// (uploader or `staffKey` claim vs object `m0`…`m9` metadata).
  Future<String?> createAttachmentProxyStreamUrl({
    required String idToken,
    required String objectPath,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/attachment/open-session'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'objectPath': objectPath}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        debugPrint(
          'BackendApi.createAttachmentProxyStreamUrl: HTTP ${response.statusCode} ${response.body}',
        );
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final p = json['path'] as String?;
      if (p == null || p.isEmpty) return null;
      final base = _baseUrl.endsWith('/')
          ? _baseUrl.substring(0, _baseUrl.length - 1)
          : _baseUrl;
      return p.startsWith('/') ? '$base$p' : '$base/$p';
    } catch (e) {
      debugPrint('BackendApi.createAttachmentProxyStreamUrl: $e');
      return null;
    }
  }

  /// Emails sub-task assignees after creation (creator only). Requires Mailgun.
  Future<String?> notifySubtaskAssigned({
    required String idToken,
    required String subtaskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/subtask-assigned'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'subtaskId': subtaskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails each assignee (assignee_01..10) after task creation. Requires Mailgun on Railway.
  /// Returns `null` on success, or an error message (caller may log and ignore).
  Future<String?> notifyTaskAssigned({
    required String idToken,
    required String taskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-assigned'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'taskId': taskId}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails each project assignee (`assignee_01`–`assignee_20`) after project creation.
  /// Server: `POST /api/notify/project-assigned` (`handleNotifyProjectAssigned`).
  Future<String?> notifyProjectAssigned({
    required String idToken,
    required String projectId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/project-assigned'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'projectId': projectId}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails project assignees after project detail columns change (`POST /api/notify/project-updated`).
  ///
  /// [changes]: `{ 'field': 'projectName'|'description'|'assignees'|'pic'|'status'|'startDate'|'endDate', 'value': '...' }`.
  Future<String?> notifyProjectUpdated({
    required String idToken,
    required String projectId,
    List<Map<String, String>>? changes,
  }) async {
    try {
      final payload = <String, dynamic>{'projectId': projectId};
      if (changes != null && changes.isNotEmpty) {
        payload['changes'] = changes;
      }
      final response = await http
          .post(
            url('/api/notify/project-updated'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails the task creator after a comment is saved (not when the creator comments on own task).
  /// Server: `POST /api/notify/task-comment` (`handleNotifyTaskComment`). Requires Mailgun;
  /// enable with `TASK_COMMENT_EMAIL_ENABLED` on the backend (on by default unless set to false).
  Future<String?> notifyTaskCommentAdded({
    required String idToken,
    required String commentId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-comment'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'commentId': commentId}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails task creator + assignees when a comment is edited (server excludes the editor).
  /// Server: `POST /api/notify/task-comment-edited` (`handleNotifyTaskEditedComment`).
  Future<String?> notifyTaskCommentEdited({
    required String idToken,
    required String commentId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-comment-edited'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'commentId': commentId}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails the **sub-task creator** when a **non-creator** saves a comment. The server accepts the
  /// caller when Firebase email matches `staff.email` or a linked `app_users.email` for the comment
  /// author, and resolves the creator’s inbox via the same helper when `staff.email` is empty.
  /// Server: `POST /api/notify/subtask-comment` (`handleNotifySubtaskComment`). Uses
  /// `TASK_COMMENT_EMAIL_ENABLED` like task-comment notifications.
  Future<String?> notifySubtaskCommentAdded({
    required String idToken,
    required String commentId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/subtask-comment'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'commentId': commentId}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails sub-task creator + assignees when a comment is edited (server excludes the editor).
  /// Server: `POST /api/notify/subtask-comment-edited` (`handleNotifySubtaskEditedComment`).
  Future<String?> notifySubtaskCommentEdited({
    required String idToken,
    required String commentId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/subtask-comment-edited'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'commentId': commentId}),
          )
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Emails assignees and creator after a task row is updated (Update button). Requires Mailgun.
  ///
  /// [changes]: each `{ 'field': 'taskName'|'description'|... , 'value': '...' }` for email lines.
  /// [commentAddedText]: when a comment was saved in the same update, avoids a duplicate comment-only email.
  Future<String?> notifyTaskUpdated({
    required String idToken,
    required String taskId,
    List<Map<String, String>>? changes,
    String? commentAddedText,

    /// Singular `comment.id` when the update email should use comment audit fields.
    String? taskCommentId,
  }) async {
    try {
      final payload = <String, dynamic>{'taskId': taskId};
      if (changes != null && changes.isNotEmpty) {
        payload['changes'] = changes;
      }
      final c = commentAddedText?.trim();
      if (c != null && c.isNotEmpty) {
        payload['commentAddedText'] = c;
      }
      final tc = taskCommentId?.trim();
      if (tc != null && tc.isNotEmpty) {
        payload['taskCommentId'] = tc;
      }
      final response = await http
          .post(
            url('/api/notify/task-updated'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Sub-task update notification (`POST /api/notify/subtask-updated`). Requires Mailgun.
  ///
  /// The server **only sends** when `subtask.update_by` is the sub-task **creator** (`create_by`)
  /// and the signed-in user matches that staff row. Recipients: non-empty `assignee_01`…`assignee_10`
  /// plus `create_by`, deduped (one Mailgun message each).
  ///
  /// [changes]: `{ 'field': 'subtaskName'|'description'|'assignees'|'priority'|'startDate'|'dueDate', 'value': '...' }`.
  /// [commentAddedText]: optional; when the creator saved a comment in the same action, body includes
  /// `Sub-task comment is added – …`.
  Future<String?> notifySubtaskUpdated({
    required String idToken,
    required String subtaskId,
    List<Map<String, String>>? changes,
    String? commentAddedText,

    /// `subtask_comment.id` when only a creator comment was saved (no subtask `update_by`).
    String? subtaskCommentId,
  }) async {
    try {
      final payload = <String, dynamic>{'subtaskId': subtaskId};
      if (changes != null && changes.isNotEmpty) {
        payload['changes'] = changes;
      }
      final c = commentAddedText?.trim();
      if (c != null && c.isNotEmpty) {
        payload['commentAddedText'] = c;
      }
      final sc = subtaskCommentId?.trim();
      if (sc != null && sc.isNotEmpty) {
        payload['subtaskCommentId'] = sc;
      }
      final response = await http
          .post(
            url('/api/notify/subtask-updated'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        final err = j['error']?.toString();
        // Generic 404 { error: 'Not found' } = no matching route (server.js
        // fallback). Confirmed on Railway when POST /api/notify/subtask-updated
        // was never deployed; redeploy the `backend/` service from this repo.
        if (response.statusCode == 404 && err == 'Not found') {
          debugPrint(
            'BackendApi.notifySubtaskUpdated: 404 Not found — redeploy Railway '
            'backend so POST /api/notify/subtask-updated is registered.',
          );
          return notifySubtaskUpdatedBackendNotDeployed;
        }
        return err ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        if (response.statusCode == 404) {
          debugPrint(
            'BackendApi.notifySubtaskUpdated: 404 without JSON; redeploy backend.',
          );
          return notifySubtaskUpdatedBackendNotDeployed;
        }
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// PIC submission for review — To creator, Cc PIC.
  Future<String?> notifyTaskSubmission({
    required String idToken,
    required String taskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-submission'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'taskId': taskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Creator accepted — To PIC, Cc creator.
  Future<String?> notifyTaskAccepted({
    required String idToken,
    required String taskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-accepted'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'taskId': taskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Creator returned — To PIC, Cc creator.
  Future<String?> notifyTaskReturned({
    required String idToken,
    required String taskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-returned'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'taskId': taskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// PIC submission for review — To creator, Cc PIC.
  Future<String?> notifySubtaskSubmission({
    required String idToken,
    required String subtaskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/subtask-submission'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'subtaskId': subtaskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Creator accepted — To PIC, Cc creator.
  Future<String?> notifySubtaskAccepted({
    required String idToken,
    required String subtaskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/subtask-accepted'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'subtaskId': subtaskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// Creator returned — To PIC, Cc creator.
  Future<String?> notifySubtaskReturned({
    required String idToken,
    required String subtaskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/subtask-returned'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'subtaskId': subtaskId}),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) return null;
      try {
        final j = jsonDecode(response.body) as Map<String, dynamic>;
        return j['error']?.toString() ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }
}
