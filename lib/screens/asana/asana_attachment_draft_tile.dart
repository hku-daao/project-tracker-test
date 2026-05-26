import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'asana_detail_widgets.dart';
import 'asana_website_link_launch.dart';
import 'asana_theme.dart';

/// Asana-styled chip for a staged task attachment (file or website link).
class AsanaAttachmentDraftTile extends StatefulWidget {
  const AsanaAttachmentDraftTile({
    super.key,
    required this.isWebsiteLink,
    required this.title,
    this.url,
    this.subtitle,
    this.enabled = true,
    this.onRemove,
    this.onEditLink,
    this.onOpenFile,
  });

  final bool isWebsiteLink;
  final String title;
  final String? url;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onRemove;
  final VoidCallback? onEditLink;
  final VoidCallback? onOpenFile;

  @override
  State<AsanaAttachmentDraftTile> createState() => _AsanaAttachmentDraftTileState();
}

class _AsanaAttachmentDraftTileState extends State<AsanaAttachmentDraftTile> {
  bool _hovering = false;

  static const _border = Color(0xFFEDEAE9);
  static const _bg = Color(0xFFFFFFFF);
  static const _bgHover = Color(0xFFF9FAFB);
  static const _linkBlue = Color(0xFF4573D2);

  @override
  Widget build(BuildContext context) {
    final canRemove = widget.enabled && widget.onRemove != null;
    final showRemove = canRemove && _hovering;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Material(
          color: _hovering ? _bgHover : _bg,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: !widget.isWebsiteLink ? widget.onOpenFile : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _border),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: widget.isWebsiteLink && widget.onEditLink != null
                          ? InkWell(
                              onTap: widget.onEditLink,
                              borderRadius: BorderRadius.circular(4),
                              child: Icon(
                                Icons.language_outlined,
                                size: 18,
                                color: kAsanaTextSecondary,
                              ),
                            )
                          : Icon(
                              widget.isWebsiteLink
                                  ? Icons.language_outlined
                                  : Icons.insert_drive_file_outlined,
                              size: 18,
                              color: kAsanaTextSecondary,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: widget.isWebsiteLink && (widget.url ?? '').isNotEmpty
                          ? _LinkBody(
                              title: widget.title,
                              url: widget.url!,
                              onEdit: widget.enabled ? widget.onEditLink : null,
                            )
                          : _PlainBody(
                              title: widget.title,
                              subtitle: widget.subtitle,
                            ),
                    ),
                    if (showRemove) const SizedBox(width: 22),
                  ],
                ),
                if (showRemove)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onRemove,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6D6E6F),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlainBody extends StatelessWidget {
  const _PlainBody({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: asanaDetailValueStyle(context)),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: asanaDetailLabelStyle(context)),
        ],
      ],
    );
  }
}

class _LinkBody extends StatelessWidget {
  const _LinkBody({
    required this.title,
    required this.url,
    this.onEdit,
  });

  final String title;
  final String url;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final urlStyle = asanaDetailValueStyle(context).copyWith(
      color: _AsanaAttachmentDraftTileState._linkBlue,
      decoration: TextDecoration.underline,
      decorationColor: _AsanaAttachmentDraftTileState._linkBlue,
    );
    final titleStyle = asanaDetailValueStyle(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                title,
                style: titleStyle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: url,
                style: urlStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => openWebsiteUrlInNewTab(url),
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (onEdit != null)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(4),
              child: const SizedBox(
                width: double.infinity,
                height: 6,
              ),
            ),
          ),
      ],
    );
  }
}
