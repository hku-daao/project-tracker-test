import 'package:flutter/material.dart';

/// Shown after adding an attachment (file or link) so the user saves via **Update**.
void showAttachmentSaveReminderSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: Colors.black,
      duration: const Duration(seconds: 4),
      content: Text.rich(
        TextSpan(
          style: const TextStyle(color: Colors.white),
          children: [
            const TextSpan(text: 'Press '),
            const TextSpan(
              text: 'Update',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: ' to save your attachment'),
          ],
        ),
      ),
    ),
  );
}
