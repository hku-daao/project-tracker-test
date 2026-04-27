import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/backend_api.dart';
import '../services/firebase_attachment_upload_service.dart';
import 'attachment_open_bytes.dart';
import 'attachment_storage_new_tab.dart';
import 'copyable_snackbar.dart';

/// True when [raw] is an `https://firebasestorage.googleapis.com/...` URL for this app’s
/// Storage bucket (typically an uploaded file saved in Supabase `attachment.content`).
bool isAppFirebaseStorageAttachmentUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return false;
  return _isAppFirebaseStorageObjectUrl(uri);
}

/// True when [uri] is an object URL under this app’s Firebase Storage bucket.
bool _isAppFirebaseStorageObjectUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') return false;
  if (uri.host.toLowerCase() != 'firebasestorage.googleapis.com') return false;
  if (Firebase.apps.isEmpty) return false;
  try {
    final bucket = Firebase.app().options.storageBucket?.trim() ?? '';
    if (bucket.isEmpty) return false;
    return uri.path.contains('/b/$bucket/') && uri.path.contains('/o/');
  } catch (_) {
    return false;
  }
}

User? _firebaseUserIfAvailable() {
  if (Firebase.apps.isEmpty) return null;
  try {
    return FirebaseAuth.instance.currentUser;
  } catch (_) {
    return null;
  }
}

/// True when [s] is JSON mistaken for a link (multipart body, DevTools copy, etc.).
///
/// Use from widgets that **display** attachment text so users do not see raw JSON.
bool attachmentTextIsJsonNotAUrl(String s) => _looksLikeJsonNotAUrl(s);

/// Multipart JSON, Storage object JSON from DevTools, or other non-URL JSON wrongly stored as "link".
bool _looksLikeJsonNotAUrl(String s) {
  final t = s.trim();
  if (!t.startsWith('{')) return false;
  if (t.contains('"contentType"')) return true;
  if (t.contains('"firebaseStorageDownloadTokens"')) return true;
  if (t.contains('"metadata"') && t.contains('"m0"')) return true;
  return false;
}

/// Object path `a/b/c` from `https://firebasestorage.googleapis.com/v0/b/BUCKET/o/ENCODED...`.
String? _objectPathFromFirebaseStorageApiUrl(Uri uri) {
  if (uri.host.toLowerCase() != 'firebasestorage.googleapis.com') return null;
  final i = uri.path.indexOf('/o/');
  if (i < 0) return null;
  final encoded = uri.path.substring(i + 3);
  if (encoded.isEmpty) return null;
  try {
    return Uri.decodeComponent(encoded);
  } catch (_) {
    return null;
  }
}

bool _projectFirebaseUrlMissingDownloadToken(Uri uri) {
  if (!_isAppFirebaseStorageObjectUrl(uri)) return false;
  final token = uri.queryParameters['token'];
  return token == null || token.isEmpty;
}

/// Public Storage file URL with `alt=media` and a non-empty `token` (safe to open in a new tab).
bool _isFirebaseStorageMediaDownloadUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') return false;
  if (uri.host.toLowerCase() != 'firebasestorage.googleapis.com') return false;
  if (uri.path.contains('/o/') == false) return false;
  if (uri.queryParameters['alt'] != 'media') return false;
  final token = uri.queryParameters['token'];
  return token != null && token.isNotEmpty;
}

Future<String> _effectiveLaunchUrl(String raw) async {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return raw.trim();
  if (!_projectFirebaseUrlMissingDownloadToken(uri)) return raw.trim();
  if (Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) {
    return raw.trim();
  }
  final objectPath = _objectPathFromFirebaseStorageApiUrl(uri);
  if (objectPath == null || objectPath.isEmpty) return raw.trim();
  try {
    if (kIsWeb) {
      try {
        final sdkUrl =
            await FirebaseStorage.instance.ref(objectPath).getDownloadURL();
        if (sdkUrl.contains('token=')) return sdkUrl;
      } catch (e, st) {
        debugPrint('openAttachmentUrl web getDownloadURL: $e\n$st');
      }
      final resolved =
          await FirebaseAttachmentUploadService.fetchStorageDownloadUrlRest(
            objectPath,
          );
      if (resolved != null && resolved.isNotEmpty) return resolved;
    } else {
      return await FirebaseStorage.instance.ref(objectPath).getDownloadURL();
    }
  } catch (e, st) {
    debugPrint('openAttachmentUrl resolve download URL: $e\n$st');
  }
  return raw.trim();
}

String _filenameHintFromStorageObjectPath(String objectPath) {
  final segments = objectPath.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return 'attachment';
  return segments.last;
}

Future<void> _openHttpsLaunchUri(BuildContext context, Uri launch) async {
  final user = _firebaseUserIfAvailable();
  final isAppStorage = _isAppFirebaseStorageObjectUrl(launch);

  if (isAppStorage && user != null && Firebase.apps.isNotEmpty) {
    final objectPath = _objectPathFromFirebaseStorageApiUrl(launch);
    if (objectPath == null || objectPath.isEmpty) {
      if (!context.mounted) return;
      showCopyableSnackBar(
        context,
        'Invalid attachment path.',
        backgroundColor: Colors.orange,
      );
      return;
    }
    try {
      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        if (!context.mounted) return;
        showCopyableSnackBar(
          context,
          'Sign in again to open this attachment.',
          backgroundColor: Colors.orange,
        );
        return;
      }
      final proxy = await BackendApi().createAttachmentProxyStreamUrl(
        idToken: idToken,
        objectPath: objectPath,
      );
      if (proxy == null || proxy.isEmpty) {
        if (!context.mounted) return;
        showCopyableSnackBar(
          context,
          'Could not open this attachment through a secure link. '
          'Ensure the app backend is deployed and try again.',
          backgroundColor: Colors.orange,
        );
        return;
      }
      final u = Uri.tryParse(proxy);
      if (u == null || !u.hasScheme) {
        if (!context.mounted) return;
        showCopyableSnackBar(
          context,
          'Invalid attachment open URL.',
          backgroundColor: Colors.orange,
        );
        return;
      }
      final resp = await http
          .get(
            u,
            headers: {'Authorization': 'Bearer $idToken'},
          )
          .timeout(const Duration(minutes: 2));
      if (resp.statusCode == 200) {
        final ct = resp.headers['content-type']?.split(';').first.trim() ??
            'application/octet-stream';
        final name = _filenameHintFromStorageObjectPath(objectPath);
        final opened = await openAttachmentBytesInSystemViewer(
          resp.bodyBytes,
          ct,
          name,
        );
        if (opened) {
          return;
        }
        if (!context.mounted) return;
        showCopyableSnackBar(
          context,
          'Could not open the file viewer.',
          backgroundColor: Colors.orange,
        );
        return;
      }
      if (!context.mounted) return;
      showCopyableSnackBar(
        context,
        'Could not load attachment (HTTP ${resp.statusCode}). '
        'Redeploy the backend if this persists.',
        backgroundColor: Colors.orange,
      );
      return;
    } catch (e, st) {
      debugPrint('openAttachmentUrl proxy: $e\n$st');
      if (!context.mounted) return;
      showCopyableSnackBar(
        context,
        'Could not open attachment: $e',
        backgroundColor: Colors.orange,
      );
      return;
    }
  }

  if (kIsWeb && _isFirebaseStorageMediaDownloadUrl(launch)) {
    if (tryOpenUrlInNewTab(launch.toString())) {
      return;
    }
  }
  final ok = await launchUrl(launch, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showCopyableSnackBar(
      context,
      'Could not open the link',
      backgroundColor: Colors.orange,
    );
  }
}

/// Opens [raw] in the browser / default handler when it looks like `http` / `https`.
///
/// Firebase Storage links for this project require a **signed-in** Firebase user so
/// logged-out people using the app cannot open uploaded attachments from here.
Future<void> openAttachmentUrl(BuildContext context, String raw) async {
  final t = raw.trim();
  if (t.isEmpty) return;
  if (_looksLikeJsonNotAUrl(t)) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'This is not a valid file link (it looks like JSON metadata, not a URL). '
      'Remove this row and re-upload the file so a proper download link is saved.',
      backgroundColor: Colors.orange,
    );
    return;
  }
  final uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      _looksLikeJsonNotAUrl(t)
          ? 'This attachment is not a valid link (stored value looks like JSON). '
              'Remove it and re-upload the file.'
          : 'This attachment is not a valid web link',
      backgroundColor: Colors.orange,
    );
    return;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Cannot open links of type “$scheme” from here',
      backgroundColor: Colors.orange,
    );
    return;
  }
  if (_isAppFirebaseStorageObjectUrl(uri) && _firebaseUserIfAvailable() == null) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Sign in to open this attachment.',
      backgroundColor: Colors.orange,
    );
    return;
  }
  try {
    final href = await _effectiveLaunchUrl(t);
    final launch = Uri.tryParse(href) ?? uri;
    // Opening .../o/path **without** ?alt=media&token= returns JSON in the browser.
    if (_isAppFirebaseStorageObjectUrl(launch) &&
        _projectFirebaseUrlMissingDownloadToken(launch)) {
      if (!context.mounted) return;
      showCopyableSnackBar(
        context,
        'This attachment link is incomplete (missing download token). '
        'Sign in with the same account used to upload, or re-upload the file.',
        backgroundColor: Colors.orange,
      );
      return;
    }
    if (!context.mounted) return;
    await _openHttpsLaunchUri(context, launch);
  } catch (e) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Could not open link: $e',
      backgroundColor: Colors.orange,
    );
  }
}
