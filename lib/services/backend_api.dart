import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Result of a health check.
class HealthResult {
  final bool ok;
  final String? message;
  final String? timestamp;

  const HealthResult({required this.ok, this.message, this.timestamp});
}

/// One row from backend /api/me assignableStaff (server-enforced visibility).
class AssignableStaffEntry {
  final String staffAppId;
  final String staffName;
  final String? teamAppId;
  final String? teamName;

  const AssignableStaffEntry({
    required this.staffAppId,
    required this.staffName,
    this.teamAppId,
    this.teamName,
  });

  static AssignableStaffEntry fromJson(Map<String, dynamic> json) {
    return AssignableStaffEntry(
      staffAppId: json['staffAppId'] as String? ?? '',
      staffName: json['staffName'] as String? ?? '',
      teamAppId: json['teamAppId'] as String?,
      teamName: json['teamName'] as String?,
    );
  }
}

/// Response from GET /api/me (role + assignable staff).
class UserProfileResult {
  final String? role;
  final String? staffAppId;
  final String? staffName;
  final List<AssignableStaffEntry> assignableStaff;

  const UserProfileResult({
    this.role,
    this.staffAppId,
    this.staffName,
    this.assignableStaff = const [],
  });

  static UserProfileResult fromJson(Map<String, dynamic> json) {
    final list = json['assignableStaff'] as List<dynamic>? ?? [];
    return UserProfileResult(
      role: json['role'] as String?,
      staffAppId: json['staffAppId'] as String?,
      staffName: json['staffName'] as String?,
      assignableStaff: list
          .map((e) => AssignableStaffEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Client for the Railway backend API.
class BackendApi {
  BackendApi({String? baseUrl}) : _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final String _baseUrl;

  String get baseUrl => _baseUrl;

  /// Check if the backend is reachable. Returns [HealthResult]; never null.
  /// On failure, returns HealthResult(ok: false, message: errorDetail).
  Future<HealthResult> checkHealth() async {
    try {
      final uri = Uri.parse('$_baseUrl${ApiConfig.healthPath}');
      final response = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Timeout after 15s'),
          );
      if (response.statusCode != 200) {
        return HealthResult(ok: false, message: 'HTTP ${response.statusCode}');
      }
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return HealthResult(
          ok: json['ok'] == true,
          message: json['message'] as String?,
          timestamp: json['timestamp'] as String?,
        );
      } catch (_) {
        return HealthResult(ok: true, message: response.body);
      }
    } catch (e) {
      // e.g. SocketException, TimeoutException, or CORS/network in browser
      final msg = e.toString();
      final short = msg.length > 80 ? '${msg.substring(0, 77)}...' : msg;
      return HealthResult(ok: false, message: short);
    }
  }

  /// Build full URL for a path (ensures single slash between base and path).
  Uri url(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p');
  }

  /// Get current user profile and assignable staff (server-enforced). Requires Firebase ID token.
  Future<UserProfileResult?> getMe(String idToken) async {
    try {
      final response = await http
          .get(url('/api/me'), headers: {'Authorization': 'Bearer $idToken'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          'BackendApi.getMe: HTTP ${response.statusCode} - ${response.body}',
        );
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = UserProfileResult.fromJson(json);
      debugPrint(
        'BackendApi.getMe: role=${result.role}, staffAppId=${result.staffAppId}, assignableStaff=${result.assignableStaff.length}',
      );
      return result;
    } catch (e) {
      debugPrint('BackendApi.getMe: Error - $e');
      return null;
    }
  }

  /// Get assignable staff only (for dropdown refresh). Requires Firebase ID token.
  Future<List<AssignableStaffEntry>> getAssignableStaff(String idToken) async {
    try {
      final response = await http
          .get(
            url('/api/assignable-staff'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final list = json['assignableStaff'] as List<dynamic>? ?? [];
      return list
          .map((e) => AssignableStaffEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getTeams(String idToken) async {
    try {
      final response = await http
          .get(url('/api/teams'), headers: {'Authorization': 'Bearer $idToken'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          'BackendApi.getTeams: HTTP ${response.statusCode} - ${response.body}',
        );
        return [];
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final list = json['teams'] as List<dynamic>? ?? [];
      debugPrint('BackendApi.getTeams: Received ${list.length} teams');
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('BackendApi.getTeams: Error - $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getStaff(String idToken) async {
    try {
      final response = await http
          .get(url('/api/staff'), headers: {'Authorization': 'Bearer $idToken'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          'BackendApi.getStaff: HTTP ${response.statusCode} - ${response.body}',
        );
        return [];
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final list = json['staff'] as List<dynamic>? ?? [];
      debugPrint('BackendApi.getStaff: Received ${list.length} staff');
      return list.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint('BackendApi.getStaff: Error - $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getAdminSnapshot(String idToken) async {
    try {
      final response = await http
          .get(
            url('/api/admin/snapshot'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<bool> adminUpsertUser({
    required String idToken,
    required String firebaseUid,
    required String email,
    String? displayName,
    String? staffAppId,
    required String roleAppId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/admin/user'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'firebase_uid': firebaseUid,
              'email': email,
              'display_name': displayName ?? email,
              'staff_app_id': staffAppId,
              'role_app_id': roleAppId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> adminDeleteUser(String idToken, String appUserId) async {
    try {
      final response = await http
          .delete(
            url('/api/admin/user/$appUserId'),
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> adminUpsertTeam({
    required String idToken,
    required String name,
    required String appId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/admin/team'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'name': name, 'app_id': appId}),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> adminTeamMember({
    required String idToken,
    required String teamAppId,
    required String staffAppId,
    required String role,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/admin/team-member'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'team_app_id': teamAppId,
              'staff_app_id': staffAppId,
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> adminSubordinate({
    required String idToken,
    required String supervisorStaffAppId,
    required String subordinateStaffAppId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/admin/subordinate'),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'supervisor_staff_app_id': supervisorStaffAppId,
              'subordinate_staff_app_id': subordinateStaffAppId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (_) {
      return false;
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

  /// Emails other assignees after a task comment is saved (not the author). Requires Mailgun.
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

  /// Emails assignees and creator after a task row is updated (Update button). Requires Mailgun.
  Future<String?> notifyTaskUpdated({
    required String idToken,
    required String taskId,
  }) async {
    try {
      final response = await http
          .post(
            url('/api/notify/task-updated'),
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
}
