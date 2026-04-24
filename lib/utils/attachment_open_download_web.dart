// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:http/http.dart' as http;

/// Fetches [href] in the app context and opens the bytes in a new tab as a blob URL.
/// Returns true if a new tab was opened. Returns false if the response looks like JSON metadata.
Future<bool> openHttpUrlAsBlobInNewTab(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null) return false;
  final r = await http.get(uri);
  if (r.statusCode < 200 || r.statusCode >= 300) return false;
  final ct = r.headers['content-type']?.toLowerCase() ?? '';
  final bodyStart = r.body.trimLeft();
  if (bodyStart.startsWith('{') &&
      (ct.contains('json') ||
          bodyStart.contains('"contentType"') ||
          bodyStart.contains('"firebaseStorageDownloadTokens"'))) {
    return false;
  }
  final blob = html.Blob([r.bodyBytes]);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(objectUrl, '_blank');
  Future<void>.delayed(const Duration(minutes: 2), () {
    html.Url.revokeObjectUrl(objectUrl);
  });
  return true;
}
