import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/attachment_url_launch.dart';
import '../utils/copyable_snackbar.dart';

typedef AttachmentPickUpload = Future<({String? url, String? label, String? error})> Function();

/// Edit description and link; optional **Replace with file from device** uploads to Firebase Storage.
Future<({String description, String url})?> showAttachmentEditDialog(
  BuildContext context, {
  required String initialDescription,
  required String initialUrl,
  required AttachmentPickUpload pickReplaceFromDevice,
}) {
  final descCtrl = TextEditingController(text: initialDescription);
  final linkCtrl = TextEditingController(text: initialUrl);
  final hideAttachmentLinkField =
      isAppFirebaseStorageAttachmentUrl(initialUrl);
  return showDialog<({String description, String url})>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Edit an attachment'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Attachment description',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  if (!hideAttachmentLinkField) ...[
                    TextField(
                      controller: linkCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Attachment link or website',
                        hintText: 'https://…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      autocorrect: false,
                      minLines: 1,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (hideAttachmentLinkField)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file_outlined, size: 20),
                      label: const Text('Replace with file from device'),
                      onPressed: () async {
                        // Let the dialog finish any tap handling before presenting the
                        // system document picker (iOS is strict about nested presentations).
                        if (!kIsWeb) {
                          await Future<void>.delayed(
                            const Duration(milliseconds: 50),
                          );
                        }
                        if (!ctx.mounted) return;
                        final r = await pickReplaceFromDevice();
                        if (!ctx.mounted) return;
                        if (r.error != null && r.error!.isNotEmpty) {
                          showCopyableSnackBar(
                            ctx,
                            r.error!,
                            backgroundColor: Colors.orange,
                          );
                          return;
                        }
                        if (r.url == null) return;
                        setLocal(() {
                          linkCtrl.text = r.url!;
                          if (descCtrl.text.trim().isEmpty &&
                              (r.label ?? '').trim().isNotEmpty) {
                            descCtrl.text = (r.label ?? '').trim();
                          }
                        });
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 4),
                            content: const Text(
                              'File is uploaded. Press Save to apply, then Update on the page to persist',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop((
                    description: descCtrl.text.trim(),
                    url: linkCtrl.text.trim(),
                  ));
                },
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(() {
    descCtrl.dispose();
    linkCtrl.dispose();
  });
}
