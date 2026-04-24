import 'package:flutter/material.dart';

import 'copyable_snackbar.dart';

/// Shown after adding an attachment (file or link) so the user saves via **Update**.
void showAttachmentSaveReminderSnackBar(BuildContext context) {
  showCopyableSnackBar(
    context,
    'Press Update to save your attachment',
    backgroundColor: Colors.black87,
    foregroundColor: Colors.white,
  );
}
