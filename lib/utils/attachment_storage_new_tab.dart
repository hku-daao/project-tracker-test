import 'attachment_storage_new_tab_stub.dart'
    if (dart.library.html) 'attachment_storage_new_tab_web.dart' as impl;

/// Browser-only: opens a URL in a new tab via [window.open]. Returns false on VM.
bool tryOpenUrlInNewTab(String url) => impl.tryOpenUrlInNewTab(url);
