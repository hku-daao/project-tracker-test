import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
import 'asana_blocking_loading_overlay.dart';
import 'asana_theme.dart';
import 'asana_value_chips.dart';

/// Section label (Inter, secondary).
TextStyle asanaDetailLabelStyle(BuildContext context) {
  return asanaTextStyle(
    Theme.of(context).textTheme.bodySmall,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: kAsanaTextSecondary,
    height: 1.3,
  )!;
}

/// Body value in slide detail (14px Inter).
TextStyle asanaDetailValueStyle(BuildContext context, {FontWeight? weight}) {
  return asanaTextStyle(
    Theme.of(context).textTheme.bodyMedium,
    fontSize: 14,
    fontWeight: weight ?? FontWeight.w400,
    color: kAsanaTextPrimary,
    height: 1.4,
  )!;
}

/// Large bold title at top of slide (task / sub-task / project name only).
TextStyle asanaDetailTitleStyle(BuildContext context) {
  return asanaTextStyle(
    Theme.of(context).textTheme.titleLarge,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: kAsanaTextPrimary,
    height: 1.25,
  )!;
}

/// Multiline fields (description, comments).
TextStyle asanaDetailMultilineValueStyle(BuildContext context) {
  return asanaDetailValueStyle(context);
}

/// First column width for 2-column rows (50% wider than the prior 150px).
const double kAsanaDetailLabelColumnWidth = 225;

/// Label and value on one row (invisible 2-column table).
class AsanaDetailTwoColumnRow extends StatelessWidget {
  const AsanaDetailTwoColumnRow({
    super.key,
    required this.label,
    required this.child,
    this.labelWidth = kAsanaDetailLabelColumnWidth,
    this.bottomPadding = 10,
  });

  final String label;
  final Widget child;
  final double labelWidth;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final effectiveLabelWidth = MediaQuery.sizeOf(context).width < 600
        ? labelWidth / 2
        : labelWidth;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: effectiveLabelWidth,
            child: Text(label, style: asanaDetailLabelStyle(context)),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// AI suggestion row: empty label column, then outlined value field with a
/// floating "Suggested" label that cuts through the border (like "Your prompt").
class AsanaDetailSuggestedValueRow extends StatelessWidget {
  const AsanaDetailSuggestedValueRow({
    super.key,
    required this.child,
    this.label = 'Suggested',
    this.labelWidth = kAsanaDetailLabelColumnWidth,
    this.labelColor,
    this.borderColor,
    this.fillColor,
    this.bottomPadding = 10,
    this.wrapField,
    this.insetLabelColumn = true,
  });

  final Widget child;
  final String label;
  final double labelWidth;
  final Color? labelColor;
  final Color? borderColor;
  final Color? fillColor;
  final double bottomPadding;

  /// When false, field spans full width (task name, description, comment).
  final bool insetLabelColumn;

  /// Optional outer wrap (e.g. glow shadow); outline stays on [InputDecorator].
  final Widget Function(Widget field)? wrapField;

  @override
  Widget build(BuildContext context) {
    final effectiveLabelWidth = MediaQuery.sizeOf(context).width < 600
        ? labelWidth / 2
        : labelWidth;
    final labelStyle = asanaDetailLabelStyle(
      context,
    ).copyWith(color: labelColor ?? kAsanaTextSecondary);
    final edge = borderColor ?? kAsanaTextSecondary.withValues(alpha: 0.35);
    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: edge),
    );

    Widget field = InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        alignLabelWithHint: true,
        isDense: true,
        filled: fillColor != null,
        fillColor: fillColor,
        border: outline,
        enabledBorder: outline,
        focusedBorder: outline,
        disabledBorder: outline,
        contentPadding: const EdgeInsets.fromLTRB(12, 12, 2, 10),
        labelStyle: labelStyle,
        floatingLabelStyle: labelStyle,
      ),
      child: child,
    );

    if (wrapField != null) {
      field = wrapField!(field);
    }

    if (!insetLabelColumn) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: field,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: effectiveLabelWidth),
          Expanded(child: field),
        ],
      ),
    );
  }
}

class AsanaDetailLabelValue extends StatelessWidget {
  const AsanaDetailLabelValue({
    super.key,
    required this.label,
    required this.child,
    this.gap = 4,
  });

  final String label;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: asanaDetailLabelStyle(context)),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}

class AsanaDetailPlainValue extends StatelessWidget {
  const AsanaDetailPlainValue({
    super.key,
    required this.text,
    this.maxLines,
    this.completed = false,
  });

  final String text;
  final int? maxLines;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: asanaDetailValueStyle(
        context,
      ).copyWith(color: completed ? Colors.black38 : kAsanaTextPrimary),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}

/// Text field border only when [canEdit] and pointer is hovering.
class AsanaHoverTextField extends StatefulWidget {
  const AsanaHoverTextField({
    super.key,
    required this.controller,
    required this.canEdit,
    this.maxLines = 1,
    this.minLines = 1,
    this.style,
    this.readOnly = false,
    this.hintText,
    this.showOutline = false,
  });

  final TextEditingController controller;
  final bool canEdit;
  final int maxLines;
  final int minLines;
  final TextStyle? style;
  final bool readOnly;
  final String? hintText;

  /// Always show a visible border (create-task slide).
  final bool showOutline;

  @override
  State<AsanaHoverTextField> createState() => _AsanaHoverTextFieldState();
}

class _AsanaHoverTextFieldState extends State<AsanaHoverTextField> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        widget.style ??
        (widget.maxLines > 1
            ? asanaDetailMultilineValueStyle(context)
            : asanaDetailValueStyle(context));
    if (!widget.canEdit) {
      final text = widget.controller.text;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          text.isEmpty ? (widget.hintText ?? '') : text,
          style: text.isEmpty
              ? baseStyle.copyWith(color: kAsanaTextSecondary)
              : baseStyle,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final showBorder = widget.showOutline || (_hovering && !widget.readOnly);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: showBorder
              ? Border.all(color: const Color(0xFFB0BEC5))
              : Border.all(color: Colors.transparent),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: showBorder ? 8 : 0,
          vertical: showBorder ? 6 : 2,
        ),
        child: TextField(
          controller: widget.controller,
          readOnly: widget.readOnly || !widget.canEdit,
          onTap: widget.readOnly
              ? null
              : () => AsanaBlockingLoadingOverlay.hideAll(),
          maxLines: widget.maxLines,
          minLines: widget.minLines,
          style: baseStyle,
          scrollPadding: EdgeInsets.zero,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: widget.hintText,
            hintStyle: asanaTextStyle(
              Theme.of(context).textTheme.bodyMedium,
              fontSize: 14,
              color: kAsanaTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable value row; border on hover when [canEdit].
class AsanaHoverTapValue extends StatefulWidget {
  const AsanaHoverTapValue({
    super.key,
    required this.value,
    required this.canEdit,
    this.onTap,
    this.onClear,
    this.emptyPlaceholder = '',
    this.anchorLink,
  });

  final String value;
  final bool canEdit;

  /// Receives this field's [BuildContext] (for anchored overlays).
  final void Function(BuildContext fieldContext)? onTap;
  final VoidCallback? onClear;
  final String emptyPlaceholder;

  /// When set, anchored overlays can follow this field on resize / scroll.
  final LayerLink? anchorLink;

  @override
  State<AsanaHoverTapValue> createState() => _AsanaHoverTapValueState();
}

class _AsanaHoverTapValueState extends State<AsanaHoverTapValue> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final showBorder = widget.canEdit && _hovering;
    final hasValue = widget.value.trim().isNotEmpty;
    final display = hasValue ? widget.value.trim() : widget.emptyPlaceholder;
    final showClear = widget.canEdit && widget.onClear != null && hasValue;

    Widget child = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.canEdit && widget.onTap != null
            ? () => widget.onTap!(context)
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: showBorder
                ? Border.all(color: const Color(0xFFB0BEC5))
                : Border.all(color: Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: showBorder ? 8 : 0,
            vertical: showBorder ? 6 : 2,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: IntrinsicWidth(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: showClear ? 14 : 0),
                    child: Text(
                      display,
                      style: asanaDetailValueStyle(context).copyWith(
                        color: hasValue
                            ? kAsanaTextPrimary
                            : kAsanaTextSecondary,
                      ),
                    ),
                  ),
                  if (showClear)
                    Positioned(
                      top: -8,
                      right: -2,
                      child: _AsanaSmallClearButton(onTap: widget.onClear!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.anchorLink != null) {
      child = CompositedTransformTarget(link: widget.anchorLink!, child: child);
    }
    return child;
  }
}

class _AsanaSmallClearButton extends StatelessWidget {
  const _AsanaSmallClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Color(0xFF6D6E6F),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.close, size: 12, color: Colors.white),
        ),
      ),
    );
  }
}

/// Status pill for slide detail rows (matches table chip size).
class AsanaDetailStatusPill extends StatelessWidget {
  const AsanaDetailStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      constrainedAxis: Axis.vertical,
      child: AsanaStatusChip(status: status, preserveFullLabel: true),
    );
  }
}

/// Circular [+] control (Attachments section, assignee field, etc.).
class AsanaDetailCircleAddButton extends StatelessWidget {
  const AsanaDetailCircleAddButton({
    super.key,
    this.onTap,
    this.enabled = true,
    this.tooltip = 'Add',
    this.size = 24,
    this.anchorLink,
  });

  /// Receives this button's [BuildContext] (for anchored menus).
  final void Function(BuildContext buttonContext)? onTap;
  final bool enabled;
  final String tooltip;
  final double size;
  final LayerLink? anchorLink;

  @override
  Widget build(BuildContext context) {
    final canPress = enabled && onTap != null;
    Widget child = Tooltip(
      message: tooltip,
      child: Material(
        color: canPress ? const Color(0xFFECEFF1) : const Color(0xFFF5F6F7),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canPress ? () => onTap!(context) : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(
                Icons.add,
                size: 16,
                color: canPress ? kAsanaTextPrimary : kAsanaTextSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    if (anchorLink != null) {
      child = CompositedTransformTarget(link: anchorLink!, child: child);
    }
    return child;
  }
}

/// Section title with circular [+] beside the label.
class AsanaDetailSectionHeader extends StatelessWidget {
  const AsanaDetailSectionHeader({
    super.key,
    required this.title,
    this.showAddButton = false,
    this.onAdd,
    this.addEnabled = true,
    this.addTooltip = 'Add',
    this.bottomPadding = 8,
    this.addAnchorLink,
  });

  final String title;
  final bool showAddButton;
  final void Function(BuildContext addButtonContext)? onAdd;
  final bool addEnabled;
  final String addTooltip;
  final double bottomPadding;
  final LayerLink? addAnchorLink;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Text(title, style: asanaDetailLabelStyle(context)),
          if (showAddButton) ...[
            const SizedBox(width: 8),
            AsanaDetailCircleAddButton(
              onTap: onAdd,
              enabled: addEnabled,
              tooltip: addTooltip,
              anchorLink: addAnchorLink,
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom action strip pinned to the slide panel (not the scroll content).
class AsanaDetailSlideFooter extends StatelessWidget {
  const AsanaDetailSlideFooter({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.child,
  });

  final Color backgroundColor;
  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: borderColor)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Scrollable body with an optional footer fixed to the slide bottom edge.
class AsanaDetailSlideScaffold extends StatelessWidget {
  const AsanaDetailSlideScaffold({
    super.key,
    required this.backgroundColor,
    required this.body,
    this.footer,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 12, 20, 20),
    this.footerScrollPadding = 88,
  });

  final Color backgroundColor;
  final Widget body;
  final Widget? footer;

  /// Padding around scroll content when there is no footer.
  final EdgeInsets contentPadding;

  /// Legacy: ignored when [footer] is set — scroll area is sized above the footer.
  final double footerScrollPadding;

  @override
  Widget build(BuildContext context) {
    if (footer == null) {
      return ColoredBox(
        color: backgroundColor,
        child: SingleChildScrollView(padding: contentPadding, child: body),
      );
    }

    // Column layout: footer (AI dock + actions) does not overlay scroll content.
    return ColoredBox(
      color: backgroundColor,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(padding: contentPadding, child: body),
          ),
          footer!,
        ],
      ),
    );
  }
}

/// Slide task detail bottom action bar button styles.
class AsanaTaskDetailActionStyles {
  AsanaTaskDetailActionStyles._();

  static const Color createTeal = Color(0xFF00897B);
  static const Color updateSlate = Color(0xFF455A64);
  static const Color submitPurple = Color(0xFF6A1B9A);
  static const Color successGreen = Color(0xFF2E7D32);
  static const Color returnOrange = Color(0xFFEF6C00);
  static const Color deleteRed = Color(0xFFC62828);
  static const Color pauseAmber = Color(0xFF8A5A00);
  static const Color resumeBlue = Color(0xFF1565C0);
  static const double _cornerRadius = 8;

  static const EdgeInsets _padding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );
  static const EdgeInsets _mobilePadding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 11,
  );

  static final RoundedRectangleBorder _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_cornerRadius),
  );

  static ButtonStyle _rounded(ButtonStyle style, {Size? minimumSize}) {
    return style.copyWith(
      shape: WidgetStatePropertyAll(_shape),
      minimumSize: WidgetStatePropertyAll(minimumSize ?? Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  static EdgeInsets _responsivePadding(BuildContext? context) {
    if (context != null && MediaQuery.sizeOf(context).width < 600) {
      return _mobilePadding;
    }
    return _padding;
  }

  static TextStyle? _responsiveTextStyle(BuildContext? context) {
    if (context == null) return null;
    final base = Theme.of(context).textTheme.labelLarge;
    if (MediaQuery.sizeOf(context).width < 600) {
      return base?.copyWith(fontSize: 12.6);
    }
    return base;
  }

  static Size _responsiveActionMinimumSize(BuildContext? context) {
    if (context != null && MediaQuery.sizeOf(context).width < 600) {
      return const Size(76, 40);
    }
    return const Size(88, 40);
  }

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;

  static ButtonStyle updateFilled(
    AsanaLandingPalette palette, {
    BuildContext? context,
  }) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: updateSlate,
        foregroundColor: Colors.white,
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
        elevation: 0,
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle createFilled(
    AsanaLandingPalette palette, {
    BuildContext? context,
  }) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: createTeal,
        foregroundColor: Colors.white,
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
        elevation: 0,
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle successFilled({BuildContext? context}) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: successGreen,
        foregroundColor: Colors.white,
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
        elevation: 0,
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle returnFilled({BuildContext? context}) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: returnOrange,
        foregroundColor: Colors.white,
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
        elevation: 0,
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle submitFilled(
    AsanaLandingPalette palette, {
    BuildContext? context,
  }) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: submitPurple,
        foregroundColor: Colors.white,
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
        elevation: 0,
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle undoOutlined(
    AsanaLandingPalette palette, {
    BuildContext? context,
  }) {
    return _rounded(
      OutlinedButton.styleFrom(
        foregroundColor: kAsanaTextPrimary,
        backgroundColor: palette.listSurface,
        side: BorderSide(color: palette.accent.withValues(alpha: 0.35)),
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle pauseOutlined({BuildContext? context}) {
    return _rounded(
      OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: pauseAmber,
        side: const BorderSide(color: pauseAmber),
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  static ButtonStyle resumeOutlined({BuildContext? context}) {
    return _rounded(
      OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: resumeBlue,
        side: const BorderSide(color: resumeBlue),
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }

  /// Strong filled delete — visible on all five landing themes.
  static ButtonStyle deleteFilled({BuildContext? context}) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: deleteRed,
        foregroundColor: Colors.white,
        padding: _responsivePadding(context),
        textStyle: _responsiveTextStyle(context),
        elevation: 1,
        shadowColor: const Color(0x66B71C1C),
      ).copyWith(
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0xFFB71C1C), width: 1.5),
        ),
      ),
      minimumSize: _responsiveActionMinimumSize(context),
    );
  }
}

/// Asana-style custom dialog for confirmations.
Future<bool?> showAsanaConfirmDialog({
  required BuildContext context,
  required String title,
  required String content,
  required String confirmText,
  bool isDestructive = false,
  required AsanaLandingPalette palette,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Dialog(
        backgroundColor: palette.panelBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: const Color(0xFFEDEAE9), width: 1),
        ),
        elevation: 12,
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                title,
                style: asanaTextStyle(
                  theme.textTheme.titleMedium,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: kAsanaTextPrimary,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                content,
                style: asanaTextStyle(
                  theme.textTheme.bodyMedium,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: kAsanaTextSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kAsanaTextPrimary,
                      side: const BorderSide(color: Color(0xFFEDEAE9)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: isDestructive
                          ? const Color(0xFFC62828)
                          : palette.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: Text(confirmText),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showAsanaInfoDialog({
  required BuildContext context,
  required String title,
  required String content,
  required AsanaLandingPalette palette,
  String confirmText = 'OK',
}) async {
  await showAsanaConfirmDialog(
    context: context,
    title: title,
    content: content,
    confirmText: confirmText,
    palette: palette,
  );
}

/// Submission pill for slide detail rows (matches table chip size).
class AsanaDetailSubmissionPill extends StatelessWidget {
  const AsanaDetailSubmissionPill({super.key, required this.submission});

  final String? submission;

  @override
  Widget build(BuildContext context) {
    return UnconstrainedBox(
      alignment: Alignment.centerLeft,
      constrainedAxis: Axis.vertical,
      child: AsanaSubmissionChip(
        submission: submission,
        preserveFullLabel: true,
      ),
    );
  }
}
