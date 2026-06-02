import 'dart:html' as html;

const _kSubtaskKey = 'pt_deeplink_subtask';
const _kTaskKey = 'pt_deeplink_task';
const _kViewKey = 'pt_deeplink_view';
const _kProjectKey = 'pt_deeplink_project';

String? _paramFromFragment(String fragment, String key) {
  if (fragment.isEmpty) return null;
  final idx = fragment.indexOf('?');
  if (idx < 0) return null;
  final u = Uri.parse('https://dummy.invalid${fragment.substring(idx)}');
  return u.queryParameters[key]?.trim();
}

/// `window.location.hash` is `#/?subtask=` (email links); [Uri.fragment] omits `#`.
String? _paramFromWindowHash(String key) {
  final raw = html.window.location.hash;
  if (raw.length <= 1) return null;
  final frag = raw.startsWith('#') ? raw.substring(1) : raw;
  if (frag.startsWith('?')) {
    return Uri.parse('https://dummy.invalid$frag').queryParameters[key]?.trim();
  }
  return _paramFromFragment(frag, key);
}

String? _paramFromLocation(String key) {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  var v = uri.queryParameters[key]?.trim();
  if (v == null || v.isEmpty) {
    v = _paramFromWindowHash(key);
  }
  if (v == null || v.isEmpty) {
    v = _paramFromFragment(uri.fragment, key);
  }
  return v;
}

/// Stores deep-link ids from the address bar so they survive [usePathUrlStrategy] and login.
///
/// Call once **before** [usePathUrlStrategy] with [clearStaleWhenUrlEmpty] true so a visit to `/`
/// clears leftover session ids. Call again **after** [usePathUrlStrategy] with
/// [clearStaleWhenUrlEmpty] false: if the URL no longer shows `?task=` / hash params but the first
/// call already saved them, we must **not** clear session.
void captureWebDeepLinkForSession({bool clearStaleWhenUrlEmpty = true}) {
  final ids = _idsFromLocation();
  final sub = ids.$1;
  final task = ids.$2;
  final view = _paramFromLocation('view');
  final project = _paramFromLocation('project');
  final hasSub = sub != null && sub.isNotEmpty;
  final hasTask = task != null && task.isNotEmpty;
  final hasProject = project != null && project.isNotEmpty;
  final hasView = view != null && view.isNotEmpty;
  if (hasSub || hasTask) {
    if (hasSub) {
      html.window.sessionStorage[_kSubtaskKey] = sub;
    }
    if (hasTask) {
      html.window.sessionStorage[_kTaskKey] = task;
    }
    return;
  }
  if (hasProject) {
    html.window.sessionStorage[_kProjectKey] = project;
    return;
  }
  if (hasView) {
    html.window.sessionStorage[_kViewKey] = view;
    return;
  }
  if (clearStaleWhenUrlEmpty) {
    html.window.sessionStorage.remove(_kSubtaskKey);
    html.window.sessionStorage.remove(_kTaskKey);
    html.window.sessionStorage.remove(_kViewKey);
    html.window.sessionStorage.remove(_kProjectKey);
  }
}

/// Task / subtask ids from the address bar (path, query, hash) — **not** session storage.
(String?, String?) readDeepLinkIdsFromUrlOrHash() => _idsFromLocation();

(String?, String?) _idsFromLocation() {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  var sub = uri.queryParameters['subtask']?.trim();
  var task = uri.queryParameters['task']?.trim();
  if (sub == null || sub.isEmpty) {
    sub = _paramFromWindowHash('subtask');
  }
  if (sub == null || sub.isEmpty) {
    sub = _paramFromFragment(uri.fragment, 'subtask');
  }
  if (task == null || task.isEmpty) {
    task = _paramFromWindowHash('task');
  }
  if (task == null || task.isEmpty) {
    task = _paramFromFragment(uri.fragment, 'task');
  }
  return (sub, task);
}

String? readSubtaskIdFromUrlOrSession() {
  final ids = _idsFromLocation();
  if (ids.$1 != null && ids.$1!.isNotEmpty) return ids.$1;
  final s = html.window.sessionStorage[_kSubtaskKey]?.trim();
  if (s != null && s.isNotEmpty) return s;
  return null;
}

String? readTaskIdFromUrlOrSession() {
  final ids = _idsFromLocation();
  if (ids.$2 != null && ids.$2!.isNotEmpty) return ids.$2;
  final s = html.window.sessionStorage[_kTaskKey]?.trim();
  if (s != null && s.isNotEmpty) return s;
  return null;
}

/// `project` query / session — opens [ProjectDetailScreen] after refresh.
String? readProjectIdFromUrlOrSession() {
  final fromUrl = _paramFromLocation('project');
  if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
  final s = html.window.sessionStorage[_kProjectKey]?.trim();
  if (s != null && s.isNotEmpty) return s;
  return null;
}

/// `view` query / session: `default` (main dashboard), `original` (landing list),
/// `asana` (new UI shell), legacy `overview`, or `project`.
String? readDashboardViewFromUrlOrSession() {
  final fromUrl = _paramFromLocation('view');
  if (fromUrl != null && fromUrl.isNotEmpty) return fromUrl;
  final ids = _idsFromLocation();
  final project = _paramFromLocation('project');
  if ((ids.$1 != null && ids.$1!.isNotEmpty) ||
      (ids.$2 != null && ids.$2!.isNotEmpty) ||
      (project != null && project.isNotEmpty)) {
    return 'asana';
  }
  final sessionSubtask = html.window.sessionStorage[_kSubtaskKey]?.trim();
  final sessionTask = html.window.sessionStorage[_kTaskKey]?.trim();
  final sessionProject = html.window.sessionStorage[_kProjectKey]?.trim();
  if ((sessionSubtask != null && sessionSubtask.isNotEmpty) ||
      (sessionTask != null && sessionTask.isNotEmpty) ||
      (sessionProject != null && sessionProject.isNotEmpty)) {
    return 'asana';
  }
  final s = html.window.sessionStorage[_kViewKey]?.trim();
  if (s != null && s.isNotEmpty) return s;
  return null;
}

void consumeSubtaskDeepLink() {
  html.window.sessionStorage.remove(_kSubtaskKey);
}

void consumeTaskDeepLink() {
  html.window.sessionStorage.remove(_kTaskKey);
}

/// Removes `?subtask=` / `?task=` from the visible URL after navigation (path strategy).
void clearDeepLinkQueryFromAddressBar() {
  final path = html.window.location.pathname;
  final safePath = (path == null || path.isEmpty) ? '/' : path;
  html.window.history.replaceState(null, '', safePath);
}

/// Keeps `?task=` in the address bar and session so a browser refresh reopens [TaskDetailScreen].
void syncWebLocationForTaskDetail(String taskId) {
  final id = taskId.trim();
  if (id.isEmpty) return;
  html.window.sessionStorage[_kTaskKey] = id;
  html.window.sessionStorage.remove(_kSubtaskKey);
  html.window.sessionStorage.remove(_kViewKey);
  html.window.sessionStorage.remove(_kProjectKey);
  _replaceQueryParams((q) {
    q['task'] = id;
    q.remove('subtask');
    q.remove('view');
    q.remove('project');
  });
}

/// Clears task id from URL/session (e.g. when leaving task detail for home).
void clearWebTaskDetailFromLocation() {
  html.window.sessionStorage.remove(_kTaskKey);
  _replaceQueryParams((q) => q.remove('task'));
}

/// Keeps `?subtask=` so refresh stays on [SubtaskDetailScreen].
void syncWebLocationForSubtaskDetail(String subtaskId) {
  final id = subtaskId.trim();
  if (id.isEmpty) return;
  html.window.sessionStorage[_kSubtaskKey] = id;
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kViewKey);
  html.window.sessionStorage.remove(_kProjectKey);
  _replaceQueryParams((q) {
    q['subtask'] = id;
    q.remove('task');
    q.remove('view');
    q.remove('project');
  });
}

/// Clears subtask from URL/session; optionally restores [parentTaskId] for the underlying task screen.
void clearWebSubtaskDetailFromLocation({String? parentTaskId}) {
  html.window.sessionStorage.remove(_kSubtaskKey);
  _replaceQueryParams((q) => q.remove('subtask'));
  final p = parentTaskId?.trim();
  if (p != null && p.isNotEmpty) {
    syncWebLocationForTaskDetail(p);
  }
}

/// Keeps `?project=` so refresh stays on [ProjectDetailScreen].
void syncWebLocationForProjectDetail(String projectId) {
  final id = projectId.trim();
  if (id.isEmpty) return;
  html.window.sessionStorage[_kProjectKey] = id;
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kSubtaskKey);
  html.window.sessionStorage.remove(_kViewKey);
  _replaceQueryParams((q) {
    q['project'] = id;
    q.remove('task');
    q.remove('subtask');
    q.remove('view');
  });
}

void clearWebProjectDetailFromLocation() {
  html.window.sessionStorage.remove(_kProjectKey);
  _replaceQueryParams((q) => q.remove('project'));
}

/// Original landing list ([HomeScreen]); refresh restores this tab.
void syncWebLocationForDefaultHome() {
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kSubtaskKey);
  html.window.sessionStorage.remove(_kProjectKey);
  html.window.sessionStorage[_kViewKey] = 'original';
  _replaceQueryParams((q) {
    q['view'] = 'original';
    q.remove('task');
    q.remove('subtask');
    q.remove('project');
  });
}

/// Asana-style landing shell ([AsanaLandingScreen]).
void syncWebLocationForAsanaDesign() {
  html.window.sessionStorage[_kViewKey] = 'asana';
  _replaceQueryParams((q) {
    q['view'] = 'asana';
  });
}

/// Default home dashboard (flat task / Overview layout).
void syncWebLocationForOverviewDashboard() {
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kSubtaskKey);
  html.window.sessionStorage.remove(_kProjectKey);
  html.window.sessionStorage[_kViewKey] = 'default';
  _replaceQueryParams((q) {
    q['view'] = 'default';
    q.remove('task');
    q.remove('subtask');
    q.remove('project');
  });
}

/// Project list dashboard route.
void syncWebLocationForProjectDashboard() {
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kSubtaskKey);
  html.window.sessionStorage.remove(_kProjectKey);
  html.window.sessionStorage[_kViewKey] = 'project';
  _replaceQueryParams((q) {
    q['view'] = 'project';
    q.remove('task');
    q.remove('subtask');
    q.remove('project');
  });
}

/// Clears task/subtask/project/view from URL and session (sign out, explicit reset).
void syncWebLocationForLanding() {
  html.window.sessionStorage.remove(_kTaskKey);
  html.window.sessionStorage.remove(_kSubtaskKey);
  html.window.sessionStorage.remove(_kViewKey);
  html.window.sessionStorage.remove(_kProjectKey);
  _replaceQueryParams((q) {
    q.remove('task');
    q.remove('subtask');
    q.remove('project');
    q.remove('view');
  });
}

/// Drops stale task/subtask session keys when the address bar has no task/subtask params.
void syncWebStaleDetailSessionsIfUrlHasNoTaskOrSubtask() {
  final ids = _idsFromLocation();
  if (ids.$1 == null || ids.$1!.isEmpty) {
    html.window.sessionStorage.remove(_kSubtaskKey);
  }
  if (ids.$2 == null || ids.$2!.isEmpty) {
    html.window.sessionStorage.remove(_kTaskKey);
  }
}

/// Updates either path `?query` or hash `#/path?query` so stored ids resolve after refresh.
void _replaceQueryParams(void Function(Map<String, String> q) mutate) {
  final href = html.window.location.href;
  final uri = Uri.parse(href);
  final frag = uri.fragment;
  if (frag.contains('?')) {
    final qIdx = frag.indexOf('?');
    final pathPart = frag.substring(0, qIdx);
    final queryPart = frag.substring(qIdx + 1);
    final inner = Uri.parse('https://dummy.invalid?$queryPart');
    final q = Map<String, String>.from(inner.queryParameters);
    mutate(q);
    final newFrag = q.isEmpty
        ? pathPart
        : '$pathPart?${Uri(queryParameters: q).query}';
    final newUri = uri.replace(fragment: newFrag);
    html.window.history.replaceState(null, '', newUri.toString());
    return;
  }
  final q = Map<String, String>.from(uri.queryParameters);
  mutate(q);
  final newUri = uri.replace(
    queryParameters: q.isEmpty ? null : q,
  );
  html.window.history.replaceState(null, '', newUri.toString());
}

/// Browser back — previous entry in the tab history.
void webHistoryBack() {
  html.window.history.back();
}
