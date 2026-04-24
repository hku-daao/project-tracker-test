import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bumped on each [showCopyableSnackBar] so a delayed dismiss does not remove a newer snack bar.
int _copyableSnackBarGeneration = 0;

/// Bottom snack bar with selectable text and a **Copy** action (for errors and long messages).
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Color? foregroundColor,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final gen = ++_copyableSnackBarGeneration;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: SelectableText(
        message,
        style: foregroundColor != null ? TextStyle(color: foregroundColor) : null,
      ),
      duration: duration,
      backgroundColor: backgroundColor,
      showCloseIcon: false,
      action: SnackBarAction(
        label: 'Copy',
        textColor: foregroundColor,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message));
        },
      ),
    ),
  );
  // Some web builds keep floating snack bars visible when the auto-dismiss timer stalls;
  // hide explicitly after [duration] if this is still the latest snack bar.
  Future<void>.delayed(duration, () {
    if (gen != _copyableSnackBarGeneration) return;
    messenger.hideCurrentSnackBar();
  });
}
