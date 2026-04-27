import 'package:flutter/material.dart';

/// Full-screen blocking overlay while a file is uploading to Storage (after pick).
void showAttachmentUploadPleaseWait(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      return PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Material(
              color: Colors.black54,
              child: Center(
                child: Card(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          'Please wait...',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

void hideAttachmentUploadPleaseWait(BuildContext context) {
  if (!context.mounted) return;
  final nav = Navigator.of(context, rootNavigator: true);
  if (nav.canPop()) {
    nav.pop();
  }
}
