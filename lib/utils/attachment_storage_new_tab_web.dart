import 'package:web/web.dart' as web;

/// Opens [url] in a new browsing context using the browser API directly.
///
/// Avoids [url_launcher] on web for long Firebase Storage URLs where some
/// environments surfaced `ClientException: Failed to fetch` despite valid links.
bool tryOpenUrlInNewTab(String url) {
  if (url.isEmpty) return false;
  try {
    web.window.open(url, '_blank', 'noopener,noreferrer');
    return true;
  } catch (_) {
    return false;
  }
}
