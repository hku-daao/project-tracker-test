import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'copyable_snackbar.dart';

/// Opens [raw] in the browser / default handler when it looks like `http` / `https`.
Future<void> openAttachmentUrl(BuildContext context, String raw) async {
  final t = raw.trim();
  if (t.isEmpty) return;
  final uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'This attachment is not a valid web link',
      backgroundColor: Colors.orange,
    );
    return;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Cannot open links of type “$scheme” from here',
      backgroundColor: Colors.orange,
    );
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showCopyableSnackBar(
        context,
        'Could not open the link',
        backgroundColor: Colors.orange,
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Could not open link: $e',
      backgroundColor: Colors.orange,
    );
  }
}
