import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// **Native iOS:** defer the native document picker until after the modal sheet is
/// torn down (two post-frame callbacks), or `UIDocumentPicker` may not present.
///
/// **Web (especially iOS Safari):** [user activation] is lost if we defer past the
/// current tap handler. Call the pick action **immediately** after [Navigator.pop].
///
/// [user activation]: https://developer.mozilla.org/en-US/docs/Web/Security/User_activation
Future<void> showAttachmentSourceBottomSheet({
  required BuildContext context,
  required VoidCallback onPickFromDevice,
  required VoidCallback onPickFromLink,
  /// When false, skips the sheet and runs [onPickFromLink] (device upload hidden).
  bool showPickFromDevice = true,
}) async {
  if (!showPickFromDevice) {
    onPickFromLink();
    return;
  }
  void runAfterSheetDismissed(VoidCallback action) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) => action());
    });
  }

  void afterPop(VoidCallback action) {
    if (kIsWeb) {
      action();
    } else {
      runAfterSheetDismissed(action);
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (sheetCtx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('From your device'),
              onTap: () {
                Navigator.pop(sheetCtx);
                afterPop(onPickFromDevice);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_link_outlined),
              title: const Text('Link to a file or website'),
              onTap: () {
                Navigator.pop(sheetCtx);
                afterPop(onPickFromLink);
              },
            ),
          ],
        ),
      );
    },
  );
}
