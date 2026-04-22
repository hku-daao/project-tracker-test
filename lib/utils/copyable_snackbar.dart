import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom snack bar with selectable text and a **Copy** action (for errors and long messages).
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: SelectableText(message),
      duration: duration,
      backgroundColor: backgroundColor,
      action: SnackBarAction(
        label: 'Copy',
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message));
        },
      ),
    ),
  );
}
