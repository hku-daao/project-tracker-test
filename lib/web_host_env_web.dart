import 'dart:html' as html;

/// True on Firebase test URLs (even if the build used the wrong `DEPLOY_ENV`).
bool get isTestWebHost {
  final host = (html.window.location.hostname ?? '').trim().toLowerCase();
  if (host.isEmpty) return false;
  return host.contains('project-tracker-test') ||
      host.contains('projecttrackertest');
}
