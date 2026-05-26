import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'asana_anchored_overlay.dart';
import 'asana_detail_widgets.dart';
import 'asana_theme.dart';

/// Result of [showAsanaAnchoredAttachmentMenu].
sealed class AsanaAttachmentMenuResult {
  const AsanaAttachmentMenuResult();
}

/// User chose **Upload a file** (handled after the menu closes).
final class AsanaAttachmentUploadFile extends AsanaAttachmentMenuResult {
  const AsanaAttachmentUploadFile();
}

/// User submitted URL + description from the inline link form.
final class AsanaAttachmentWebsiteLink extends AsanaAttachmentMenuResult {
  const AsanaAttachmentWebsiteLink({
    required this.url,
    required this.description,
  });

  final String url;
  final String description;
}

/// Anchored attachment menu: upload file or inline website link form.
Future<AsanaAttachmentMenuResult?> showAsanaAnchoredAttachmentMenu({
  required LayerLink anchorLink,
  required BuildContext anchorContext,
  BuildContext? widthAlignContext,
  VoidCallback? onClosed,
}) async {
  AsanaAttachmentMenuResult? picked;
  final alignCtx = widthAlignContext ?? anchorContext;
  final menuWidth = asanaAnchoredFieldWidth(alignCtx);
  await showAsanaAnchoredOverlay(
    anchorLink: anchorLink,
    anchorContext: anchorContext,
    widthAlignContext: alignCtx,
    placement: AsanaAnchoredVerticalPlacement.above,
    panelWidth: menuWidth,
    whenClosed: onClosed,
    builder: (ctx, close) {
      return _AsanaAttachmentMenuPanel(
        anchorContext: anchorContext,
        onUploadFile: () {
          picked = const AsanaAttachmentUploadFile();
          SchedulerBinding.instance.addPostFrameCallback((_) => close());
        },
        onAddLink: (url, description) {
          picked = AsanaAttachmentWebsiteLink(
            url: url,
            description: description,
          );
          close();
        },
      );
    },
  );
  return picked;
}

/// Inline editor for an existing website link (same styling as the attachment menu).
Future<AsanaAttachmentWebsiteLink?> showAsanaAnchoredLinkEditor({
  required LayerLink anchorLink,
  required BuildContext anchorContext,
  BuildContext? widthAlignContext,
  required String initialUrl,
  required String initialDescription,
  VoidCallback? onClosed,
}) async {
  AsanaAttachmentWebsiteLink? picked;
  final alignCtx = widthAlignContext ?? anchorContext;
  final menuWidth = asanaAnchoredFieldWidth(alignCtx);
  await showAsanaAnchoredOverlay(
    anchorLink: anchorLink,
    anchorContext: anchorContext,
    widthAlignContext: alignCtx,
    placement: AsanaAnchoredVerticalPlacement.above,
    panelWidth: menuWidth,
    whenClosed: onClosed,
    builder: (ctx, close) {
      return _AsanaAttachmentLinkEditorPanel(
        anchorContext: anchorContext,
        initialUrl: initialUrl,
        initialDescription: initialDescription,
        onSave: (url, description) {
          picked = AsanaAttachmentWebsiteLink(
            url: url,
            description: description,
          );
          close();
        },
        onCancel: close,
      );
    },
  );
  return picked;
}

class _AsanaAttachmentLinkEditorPanel extends StatefulWidget {
  const _AsanaAttachmentLinkEditorPanel({
    required this.anchorContext,
    required this.initialUrl,
    required this.initialDescription,
    required this.onSave,
    required this.onCancel,
  });

  final BuildContext anchorContext;
  final String initialUrl;
  final String initialDescription;
  final void Function(String url, String description) onSave;
  final VoidCallback onCancel;

  @override
  State<_AsanaAttachmentLinkEditorPanel> createState() =>
      _AsanaAttachmentLinkEditorPanelState();
}

class _AsanaAttachmentLinkEditorPanelState
    extends State<_AsanaAttachmentLinkEditorPanel> {
  static const _border = Color(0xFFD1D5DB);
  static const _bg = Color(0xFFFFFFFF);
  static const _divider = Color(0xFFE5E7EB);

  late final TextEditingController _urlController;
  late final TextEditingController _descController;
  String? _urlError;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
    _descController = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _save() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = 'Enter a URL');
      return;
    }
    widget.onSave(url, _descController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.anchorContext;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Edit website link',
                    style: asanaDetailValueStyle(ctx, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  _AsanaAttachmentMenuField(
                    label: 'URL',
                    controller: _urlController,
                    hintText: 'https://…',
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    errorText: _urlError,
                    onChanged: () {
                      if (_urlError != null) {
                        setState(() => _urlError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _AsanaAttachmentMenuField(
                    label: 'Description',
                    controller: _descController,
                    hintText: 'Optional label',
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
              child: Row(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onCancel,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Cancel',
                        style: asanaDetailValueStyle(ctx).copyWith(
                          color: kAsanaTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _save,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Save',
                        style: asanaDetailValueStyle(
                          ctx,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AsanaAttachmentMenuPanel extends StatefulWidget {
  const _AsanaAttachmentMenuPanel({
    required this.anchorContext,
    required this.onUploadFile,
    required this.onAddLink,
  });

  final BuildContext anchorContext;
  final VoidCallback onUploadFile;
  final void Function(String url, String description) onAddLink;

  @override
  State<_AsanaAttachmentMenuPanel> createState() =>
      _AsanaAttachmentMenuPanelState();
}

class _AsanaAttachmentMenuPanelState extends State<_AsanaAttachmentMenuPanel> {
  static const _border = Color(0xFFD1D5DB);
  static const _bg = Color(0xFFFFFFFF);
  static const _divider = Color(0xFFE5E7EB);

  bool _linkExpanded = false;
  String? _urlError;
  final _urlController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _expandLinkForm() {
    setState(() {
      _linkExpanded = true;
      _urlError = null;
    });
  }

  void _collapseLinkForm() {
    setState(() {
      _linkExpanded = false;
      _urlError = null;
    });
  }

  void _submitLink() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = 'Enter a URL');
      return;
    }
    widget.onAddLink(url, _descController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.anchorContext;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuRow(
              icon: Icons.upload_file_outlined,
              label: 'Upload a file',
              onTap: widget.onUploadFile,
            ),
            const Divider(height: 1, color: _divider),
            _MenuRow(
              icon: Icons.add_link_outlined,
              label: 'Add website link',
              selected: _linkExpanded,
              onTap: _linkExpanded ? null : _expandLinkForm,
            ),
            if (_linkExpanded) ...[
              const Divider(height: 1, color: _divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AsanaAttachmentMenuField(
                      label: 'URL',
                      controller: _urlController,
                      hintText: 'https://…',
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      errorText: _urlError,
                      onChanged: () {
                        if (_urlError != null) {
                          setState(() => _urlError = null);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _AsanaAttachmentMenuField(
                      label: 'Description',
                      controller: _descController,
                      hintText: 'Optional label',
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _collapseLinkForm,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Back',
                          style: asanaDetailValueStyle(ctx).copyWith(
                            color: kAsanaTextSecondary,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _submitLink,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Add',
                          style: asanaDetailValueStyle(
                            ctx,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF3F4F6) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: kAsanaTextSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: asanaDetailValueStyle(context),
                ),
              ),
              if (selected)
                Icon(
                  Icons.keyboard_arrow_up,
                  size: 18,
                  color: kAsanaTextSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AsanaAttachmentMenuField extends StatelessWidget {
  const _AsanaAttachmentMenuField({
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.autocorrect = true,
    this.textCapitalization = TextCapitalization.none,
    this.errorText,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final TextCapitalization textCapitalization;
  final String? errorText;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: asanaDetailLabelStyle(context)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: errorText != null
                  ? const Color(0xFFE57373)
                  : const Color(0xFFB0BEC5),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: TextField(
            controller: controller,
            style: asanaDetailValueStyle(context),
            keyboardType: keyboardType,
            autocorrect: autocorrect,
            textCapitalization: textCapitalization,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: hintText,
              hintStyle: asanaDetailValueStyle(context).copyWith(
                color: kAsanaTextSecondary,
                fontWeight: FontWeight.w400,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (_) => onChanged?.call(),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText!,
            style: asanaDetailLabelStyle(context).copyWith(
              color: const Color(0xFFC62828),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
