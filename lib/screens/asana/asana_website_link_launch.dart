import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../../utils/attachment_storage_new_tab.dart';

/// Opens a user-entered website URL in a new tab (prepends https:// when no scheme).
void openWebsiteUrlInNewTab(String raw) {
  var t = raw.trim();
  if (t.isEmpty) return;
  if (!_hasUriScheme(t)) {
    t = 'https://$t';
  }
  final uri = Uri.tryParse(t);
  if (uri == null) return;
  if (kIsWeb) {
    tryOpenUrlInNewTab(uri.toString());
    return;
  }
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

bool _hasUriScheme(String value) {
  return RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value);
}
