import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bottom snack bar with selectable text and a **Copy** action (for errors and long messages).
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Color? foregroundColor,
  Duration duration = const Duration(seconds: 4),
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      content: SelectableText(
        message,
        style: foregroundColor != null ? TextStyle(color: foregroundColor) : null,
      ),
      duration: duration,
      backgroundColor: backgroundColor,
      action: SnackBarAction(
        label: 'Copy',
        textColor: foregroundColor,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: message));
        },
      ),
    ),
  );
}
