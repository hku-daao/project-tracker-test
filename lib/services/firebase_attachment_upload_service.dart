import 'dart:convert';

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
/// On **web**, the first `await` in the pick flow must be the file dialog (see
/// [pickOneFileWithBytes]) so the browser keeps
/// [user activation](https://developer.mozilla.org/en-US/docs/Web/Security/User_activation).
class FirebaseAttachmentUploadService {
  FirebaseAttachmentUploadService._();

  /// Root prefix in Firebase Storage (no spaces — Storage rules path segments cannot contain spaces).
  static const String _storageAppRoot = 'project_tracker';

  static const int _maxBytes = 50 * 1024 * 1024;

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

  /// Web-only upload via Storage REST (`uploadType=media`) using the Firebase ID token.
  /// Avoids `firebase_storage_web` JS interop (`ref` / `guard`) which can throw non-`JSError`
  /// values in some browser/SDK combinations.
  static Future<({String? url, String? error})> _uploadObjectWebRest({
    required String objectPath,
    required Uint8List bytes,
    required String contentType,
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

    final encodedName = Uri.encodeComponent(objectPath);
    final uri = Uri.parse(
      'https://firebasestorage.googleapis.com/v0/b/$bucket/o?uploadType=media&name=$encodedName',
    );

    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': contentType,
      },
      body: bytes,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return (
        url: null,
        error:
            'Storage upload failed (HTTP ${resp.statusCode}). ${resp.body.length > 400 ? '${resp.body.substring(0, 400)}…' : resp.body}',
      );
    }

    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        return (url: null, error: 'Unexpected Storage response (not JSON object).');
      }
      final json = Map<String, dynamic>.from(decoded);

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

      final nameInObj = json['name']?.toString() ?? objectPath;
      final mediaLink = json['mediaLink']?.toString();

      if (token != null && token.isNotEmpty) {
        final downloadUrl =
            'https://firebasestorage.googleapis.com/v0/b/$bucket/o/${Uri.encodeComponent(nameInObj)}?alt=media&token=$token';
        return (url: downloadUrl, error: null);
      }
      if (mediaLink != null && mediaLink.isNotEmpty) {
        return (url: mediaLink, error: null);
      }
      return (
        url: null,
        error:
            'Upload succeeded but no download URL could be built. Response keys: ${json.keys.join(', ')}',
      );
    } catch (e, st) {
      debugPrint('parse Storage upload JSON: $e\n$st');
      return (url: null, error: 'Upload succeeded but response could not be parsed: $e');
    }
  }

  /// Returns `(url, label)` on success, `error` on failure, all null if user cancelled pick.
  static Future<({String? url, String? label, String? error})> pickUploadForTask(
    String taskId,
  ) async {
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

      return _putBytes(
        storageRelativeFolder: 'task_attachments/$tid',
        originalFilename: label,
        bytes: bytes,
      );
    } catch (e, st) {
      debugPrint('pickUploadForTask: $e\n$st');
      return (url: null, label: null, error: e.toString());
    }
  }

  /// Same contract as [pickUploadForTask] for sub-task rows.
  static Future<({String? url, String? label, String? error})> pickUploadForSubtask(
    String subtaskId,
  ) async {
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

      return _putBytes(
        storageRelativeFolder: 'subtask_attachments/$sid',
        originalFilename: label,
        bytes: bytes,
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
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final objectName = _storageObjectName(originalFilename);
    final path =
        '$_storageAppRoot/users/$uid/$storageRelativeFolder/$objectName';
    final contentType = _contentTypeForFilename(originalFilename);
    try {
      if (kIsWeb) {
        final up = await _uploadObjectWebRest(
          objectPath: path,
          bytes: bytes,
          contentType: contentType,
        );
        if (up.error != null) {
          return (url: null, label: null, error: up.error);
        }
        return (url: up.url, label: originalFilename, error: null);
      }

      final ref = FirebaseStorage.instance.ref(path);
      final meta = SettableMetadata(contentType: contentType);
      await ref.putData(bytes, meta);
      final downloadUrl = await ref.getDownloadURL();
      return (url: downloadUrl, label: originalFilename, error: null);
    } catch (e, st) {
      debugPrint('Firebase Storage upload: $e\n$st');
      return (url: null, label: null, error: e.toString());
    }
  }
}
