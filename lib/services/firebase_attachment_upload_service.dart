import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../utils/attachment_file_pick.dart';

/// Picks a file and uploads to Firebase Storage; callers store [downloadUrl] in Supabase
/// `attachment.content` / `subtask_attachment.content` and [suggestedLabel] in `description`.
///
/// **Access control (no Firestore):** each object stores up to 10 staff identifiers in
/// custom metadata keys `m0`…`m9` (creator, PIC, assignees — same strings you use in
/// Supabase, e.g. `staff.app_id` and/or `staff.id` uuid). Storage security rules should
/// allow **read** only when `request.auth.token.staffKey` equals one of those metadata
/// values. Set `staffKey` on the Firebase user with the Admin SDK after login/profile
/// sync so it matches the strings you pass in [aclStaffKeys].
///
/// On **web**, the first `await` in the pick flow must be the file dialog (see
/// [pickOneFileWithBytes]) so the browser keeps
/// [user activation](https://developer.mozilla.org/en-US/docs/Web/Security/User_activation).
class FirebaseAttachmentUploadService {
  FirebaseAttachmentUploadService._();

  /// Root prefix in Firebase Storage (no spaces — Storage rules path segments cannot contain spaces).
  static const String _storageAppRoot = 'project_tracker';

  static const int _maxBytes = 50 * 1024 * 1024;

  /// Max distinct staff keys stored per object (Storage rules should mirror this count).
  static const int aclMetadataSlotCount = 10;

  /// Builds `m0`…`m9` custom metadata from non-empty, de-duplicated [keys] (order preserved).
  static Map<String, String> aclMetadataFromStaffKeys(Iterable<String?> keys) {
    final seen = <String>{};
    final out = <String, String>{};
    var i = 0;
    for (final raw in keys) {
      final s = raw?.trim();
      if (s == null || s.isEmpty || seen.contains(s)) continue;
      seen.add(s);
      out['m$i'] = s;
      i++;
      if (i >= aclMetadataSlotCount) break;
    }
    return out;
  }

  static String? _guardSync() {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        return 'Firebase is not initialized; restart the app.';
      }
      return 'File upload needs Firebase. This build only configures Firebase for web.';
    }
    if (FirebaseAuth.instance.currentUser == null) {
      return 'Sign in to upload files.';
    }
    return null;
  }

  static String _contentTypeForFilename(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.txt')) return 'text/plain';
    if (n.endsWith('.csv')) return 'text/csv';
    if (n.endsWith('.json')) return 'application/json';
    if (n.endsWith('.zip')) return 'application/zip';
    if (n.endsWith('.doc')) return 'application/msword';
    if (n.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (n.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (n.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (n.endsWith('.ppt')) return 'application/vnd.ms-powerpoint';
    if (n.endsWith('.pptx')) {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    return 'application/octet-stream';
  }

  static String _storageObjectName(String originalName) {
    var ext = '';
    final dot = originalName.lastIndexOf('.');
    if (dot > 0 && dot < originalName.length - 1) {
      ext = originalName.substring(dot).toLowerCase();
      if (ext.length > 12 || !RegExp(r'^\.[a-z0-9]+$').hasMatch(ext)) {
        ext = '';
      }
    }
    return '${const Uuid().v4()}$ext';
  }

  /// Decodes object `name` from API if it was percent-encoded twice.
  static String _normalizeObjectPathForUrl(String pathOrName) {
    var s = pathOrName.trim();
    if (s.contains('%')) {
      try {
        s = Uri.decodeComponent(s);
      } catch (_) {}
    }
    return s;
  }

  static String? _extractFirebaseDownloadTokenRegex(String body) {
    final re = RegExp(
      r'"firebaseStorageDownloadTokens"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    );
    final m = re.firstMatch(body);
    if (m == null) return null;
    var t = (m.group(1) ?? '').trim();
    if (t.contains(',')) t = t.split(',').first.trim();
    return t.isEmpty ? null : t;
  }

  /// Parses multipart `GET` / insert JSON or a raw body string for `firebaseStorageDownloadTokens`.
  static String? _downloadUrlFromStorageResponseBody(
    String body,
    String bucket,
    String objectPath,
  ) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final fromMap = _downloadUrlFromObjectJson(
          Map<String, dynamic>.from(decoded),
          bucket,
          objectPath,
        );
        if (fromMap != null) return fromMap;
      }
    } catch (_) {}
    final token = _extractFirebaseDownloadTokenRegex(body);
    if (token == null) return null;
    final norm = _normalizeObjectPathForUrl(objectPath);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(norm)}?alt=media&token=$token';
  }

  /// `alt=media&token=` URL from a Storage object JSON body (multipart response or `GET .../o/`).
  static String? _downloadUrlFromObjectJson(
    Map<String, dynamic> json,
    String bucket,
    String fallbackObjectPath,
  ) {
    String? token;
    final md = json['metadata'];
    if (md is Map) {
      final mdMap = Map<String, dynamic>.from(md);
      final raw = mdMap['firebaseStorageDownloadTokens']?.toString();
      if (raw != null && raw.isNotEmpty) {
        token = raw.contains(',') ? raw.split(',').first.trim() : raw.trim();
      }
    }
    token ??= json['downloadTokens']?.toString();
    if (token != null && token.contains(',')) {
      token = token.split(',').first.trim();
    }
    final rawName = json['name']?.toString().trim();
    final objectName = _normalizeObjectPathForUrl(
      (rawName != null && rawName.isNotEmpty) ? rawName : fallbackObjectPath,
    );
    if (token == null || token.isEmpty) return null;
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(objectName)}?alt=media&token=$token';
  }

  /// Public for [openAttachmentUrl] on **web** only — avoids `firebase_storage_web` `getDownloadURL` interop bugs.
  static Future<String?> fetchStorageDownloadUrlRest(String objectPath) async {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final bucket = Firebase.app().options.storageBucket?.trim() ?? '';
    if (bucket.isEmpty) return null;
    final trimmed = objectPath.trim();
    if (trimmed.isEmpty) return null;
    final enc = Uri.encodeComponent(trimmed);
    final uri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$enc',
    );
    for (var attempt = 0; attempt < 8; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 120 * attempt));
      }
      final idToken = await user.getIdToken();
      final resp = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $idToken'},
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        debugPrint(
          'fetchStorageDownloadUrlRest HTTP ${resp.statusCode} (try ${attempt + 1})',
        );
        continue;
      }
      final url = _downloadUrlFromStorageResponseBody(resp.body, bucket, trimmed);
      if (url != null && url.contains('token=')) {
        return url;
      }
    }
    return null;
  }

  /// Web upload with custom metadata (multipart) so Storage `create` rules can require ACL.
  static Future<({String? url, String? error})> _uploadObjectWebMultipart({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
    required Map<String, String> customMetadata,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return (url: null, error: 'Not signed in.');
    }
    final idToken = await user.getIdToken();
    final bucket = Firebase.app().options.storageBucket?.trim() ?? '';
    if (bucket.isEmpty) {
      return (url: null, error: 'Firebase app has no storageBucket in options.');
    }
    if (customMetadata.isEmpty) {
      return (url: null, error: 'Missing attachment access metadata.');
    }

    final boundary = 'dart-${const Uuid().v4()}';
    final metaJson = jsonEncode({
      'contentType': contentType,
      'metadata': customMetadata,
    });
    final b = BytesBuilder(copy: false);
    b.add('--$boundary\r\n'.codeUnits);
    b.add('Content-Type: application/json; charset=UTF-8\r\n\r\n'.codeUnits);
    b.add(utf8.encode(metaJson));
    b.add('\r\n--$boundary\r\n'.codeUnits);
    b.add('Content-Type: $contentType\r\n\r\n'.codeUnits);
    b.add(bytes);
    b.add('\r\n--$boundary--\r\n'.codeUnits);

    final encodedName = Uri.encodeComponent(objectPath);
    final uri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$bucket/o?uploadType=multipart&name=$encodedName',
    );

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: b.toBytes(),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final bodyShort =
          resp.body.length > 400 ? '${resp.body.substring(0, 400)}…' : resp.body;
      var msg = 'Storage upload failed (HTTP ${resp.statusCode}). $bodyShort';
      if (resp.statusCode == 403) {
        msg += ' Deploy Storage rules (firebase deploy --only storage). If you use '
            'Firebase Anonymous sign-in, remove the anonymous check in storage.rules. '
            'Ensure your Firebase user uid matches the path and ACL metadata includes '
            'your staff key when staffKey custom claims are enabled.';
      }
      return (url: null, error: msg);
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        return (url: null, error: 'Unexpected Storage response (not JSON object).');
      }
      final json = Map<String, dynamic>.from(decoded);

      var downloadUrl = _downloadUrlFromObjectJson(json, bucket, objectPath);
      downloadUrl ??=
          _downloadUrlFromStorageResponseBody(resp.body, bucket, objectPath);
      if (downloadUrl != null) {
        return (url: downloadUrl, error: null);
      }
      // Bytes are on the server; token may appear after a follow-up GET (handled in [_putBytes]).
      return (url: null, error: null);
    } catch (e, st) {
      debugPrint('parse Storage multipart JSON: $e\n$st');
      return (url: null, error: 'Upload succeeded but response could not be parsed: $e');
    }
  }

  /// Returns `(url, label)` on success, `error` on failure, all null if user cancelled pick.
  static Future<({String? url, String? label, String? error})> pickUploadForTask(
    String taskId, {
    required List<String?> aclStaffKeys,
  }) async {
    try {
      final tid = taskId.trim();
      if (tid.isEmpty) return (url: null, label: null, error: 'Missing task id');

      final err = _guardSync();
      if (err != null) return (url: null, label: null, error: err);

      final picked = await pickOneFileWithBytes();
      if (picked == null) {
        return (url: null, label: null, error: null);
      }

      final label =
          picked.name.trim().isEmpty ? 'attachment' : picked.name.trim();
      final bytes = picked.bytes;
      if (bytes.isEmpty) {
        return (url: null, label: null, error: 'Could not read file data.');
      }
      if (bytes.length > _maxBytes) {
        return (url: null, label: null, error: 'File too large (max 50 MB).');
      }

      final acl = aclMetadataFromStaffKeys(aclStaffKeys);
      if (acl.isEmpty) {
        return (
          url: null,
          label: null,
          error:
              'Cannot upload: no staff keys for attachment access (creator / PIC / assignees).',
        );
      }

      return _putBytes(
        storageRelativeFolder: 'task_attachments/$tid',
        originalFilename: label,
        bytes: bytes,
        aclMetadata: acl,
      );
    } catch (e, st) {
      debugPrint('pickUploadForTask: $e\n$st');
      return (url: null, label: null, error: e.toString());
    }
  }

  /// Same contract as [pickUploadForTask] for sub-task rows.
  static Future<({String? url, String? label, String? error})> pickUploadForSubtask(
    String subtaskId, {
    required List<String?> aclStaffKeys,
  }) async {
    try {
      final sid = subtaskId.trim();
      if (sid.isEmpty) {
        return (url: null, label: null, error: 'Missing sub-task id');
      }

      final err = _guardSync();
      if (err != null) return (url: null, label: null, error: err);

      final picked = await pickOneFileWithBytes();
      if (picked == null) {
        return (url: null, label: null, error: null);
      }

      final label =
          picked.name.trim().isEmpty ? 'attachment' : picked.name.trim();
      final bytes = picked.bytes;
      if (bytes.isEmpty) {
        return (url: null, label: null, error: 'Could not read file data.');
      }
      if (bytes.length > _maxBytes) {
        return (url: null, label: null, error: 'File too large (max 50 MB).');
      }

      final acl = aclMetadataFromStaffKeys(aclStaffKeys);
      if (acl.isEmpty) {
        return (
          url: null,
          label: null,
          error:
              'Cannot upload: no staff keys for attachment access (creator / PIC / assignees).',
        );
      }

      return _putBytes(
        storageRelativeFolder: 'subtask_attachments/$sid',
        originalFilename: label,
        bytes: bytes,
        aclMetadata: acl,
      );
    } catch (e, st) {
      debugPrint('pickUploadForSubtask: $e\n$st');
      return (url: null, label: null, error: e.toString());
    }
  }

  static Future<({String? url, String? label, String? error})> _putBytes({
    required String storageRelativeFolder,
    required String originalFilename,
    required Uint8List bytes,
    required Map<String, String> aclMetadata,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final objectName = _storageObjectName(originalFilename);
    final path =
        '$_storageAppRoot/users/$uid/$storageRelativeFolder/$objectName';
    final contentType = _contentTypeForFilename(originalFilename);
    try {
      if (kIsWeb) {
        final up = await _uploadObjectWebMultipart(
          objectPath: path,
          bytes: bytes,
          contentType: contentType,
          customMetadata: aclMetadata,
        );
        if (up.error != null) {
          return (url: null, label: null, error: up.error);
        }
        // On web, `getDownloadURL()` often throws in firebase_storage_web; use REST instead.
        var downloadUrl = up.url;
        if (downloadUrl == null ||
            downloadUrl.isEmpty ||
            !downloadUrl.contains('token=')) {
          downloadUrl = await fetchStorageDownloadUrlRest(path);
        }
        if (downloadUrl == null || downloadUrl.isEmpty) {
          return (
            url: null,
            label: null,
            error:
                'Upload finished but could not obtain a download link (try again).',
          );
        }
        return (url: downloadUrl, label: originalFilename, error: null);
      }

      final ref = FirebaseStorage.instance.ref(path);
      final meta = SettableMetadata(
        contentType: contentType,
        customMetadata: aclMetadata,
      );
      await ref.putData(bytes, meta);
      final downloadUrl = await ref.getDownloadURL();
      return (url: downloadUrl, label: originalFilename, error: null);
    } catch (e, st) {
      debugPrint('Firebase Storage upload: $e\n$st');
      return (url: null, label: null, error: e.toString());
    }
  }
}
