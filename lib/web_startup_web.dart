import 'dart:html' as html;

import 'package:flutter_web_plugins/url_strategy.dart';

import 'web_deep_link.dart';
import 'web_host_env_web.dart';

void configureWebStartup() {
  _clearStaleServiceWorkers();
  _migrateTestHostSession();
  // Read `?subtask=` / `/#/?subtask=` before path strategy; second pass must not clear session
  // if the query/hash was only visible before [usePathUrlStrategy].
  captureWebDeepLinkForSession(clearStaleWhenUrlEmpty: true);
  usePathUrlStrategy();
  captureWebDeepLinkForSession(clearStaleWhenUrlEmpty: false);
}

/// Old Flutter PWA workers often keep serving previous `main.dart.js` after deploy.
void _clearStaleServiceWorkers() {
  final sw = html.window.navigator.serviceWorker;
  if (sw == null) return;
  sw.getRegistrations().then((regs) {
    for (final r in regs) {
      r.unregister();
    }
  });
}

/// Normal browsers may still have `pt_deeplink_view=original` from before the Asana shell.
void _migrateTestHostSession() {
  if (!isTestWebHost) return;
  final view = html.window.sessionStorage['pt_deeplink_view']?.trim().toLowerCase();
  if (view == null || view.isEmpty || view == 'original' || view == 'default') {
    html.window.sessionStorage['pt_deeplink_view'] = 'asana';
  }
}
