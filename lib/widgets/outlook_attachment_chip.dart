import 'package:flutter/material.dart';

import '../utils/attachment_url_launch.dart';

/// Label for an attachment chip when description is empty (e.g. filename from URL).
String attachmentChipLabel(String description, String url) {
  final d = description.trim();
  if (d.isNotEmpty) return d;
  final u = url.trim();
  if (u.isEmpty) return 'Attachment';
  final uri = Uri.tryParse(u);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    final seg = uri.pathSegments.last;
    if (seg.isNotEmpty) return Uri.decodeComponent(seg);
  }
  return 'Attachment';
}

/// Outlook-style attachment control: paperclip, bordered pill, tap to open/download via browser.
class OutlookAttachmentChip extends StatelessWidget {
  const OutlookAttachmentChip({
    super.key,
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: url.trim().isEmpty
            ? null
            : () => openAttachmentUrl(context, url),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cs.outline.withValues(alpha: 0.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.attach_file,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    decoration: TextDecoration.underline,
                    decorationColor: cs.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
