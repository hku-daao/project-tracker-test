import 'package:flutter/material.dart';

import '../asana_landing_screen.dart';
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
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: asanaDetailLabelStyle(context)),
          ),
          Expanded(child: child),
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
      style: asanaDetailValueStyle(context).copyWith(
        color: completed ? Colors.black38 : kAsanaTextPrimary,
      ),
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
    final showBorder = widget.showOutline ||
        (widget.canEdit && _hovering && !widget.readOnly);
    final baseStyle = widget.style ??
        (widget.maxLines > 1
            ? asanaDetailMultilineValueStyle(context)
            : asanaDetailValueStyle(context));

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
    this.emptyPlaceholder = '',
    this.anchorLink,
  });

  final String value;
  final bool canEdit;
  /// Receives this field's [BuildContext] (for anchored overlays).
  final void Function(BuildContext fieldContext)? onTap;
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
    final display = widget.value.trim().isEmpty
        ? widget.emptyPlaceholder
        : widget.value.trim();

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
          child: Text(
            display,
            style: asanaDetailValueStyle(context),
          ),
        ),
      ),
    );
    if (widget.anchorLink != null) {
      child = CompositedTransformTarget(
        link: widget.anchorLink!,
        child: child,
      );
    }
    return child;
  }
}

/// Status pill for slide detail rows (matches table chip size).
class AsanaDetailStatusPill extends StatelessWidget {
  const AsanaDetailStatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AsanaTableCellChip(child: AsanaStatusChip(status: status)),
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
        color: canPress
            ? const Color(0xFFECEFF1)
            : const Color(0xFFF5F6F7),
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

  /// Extra bottom scroll padding when [footer] is shown (clears the action bar).
  final double footerScrollPadding;

  @override
  Widget build(BuildContext context) {
    final scrollPadding = footer != null
        ? contentPadding.copyWith(bottom: footerScrollPadding)
        : contentPadding;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: backgroundColor,
          child: SingleChildScrollView(
            padding: scrollPadding,
            child: body,
          ),
        ),
        if (footer != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: footer!,
          ),
      ],
    );
  }
}

/// Slide task detail bottom action bar button styles.
class AsanaTaskDetailActionStyles {
  AsanaTaskDetailActionStyles._();

  static const Color successGreen = Color(0xFF298A00);
  static const Color returnBlue = Color(0xFF0B0094);
  static const double _cornerRadius = 8;

  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);

  static final RoundedRectangleBorder _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(_cornerRadius),
  );

  static ButtonStyle _rounded(ButtonStyle style) {
    return style.copyWith(
      shape: WidgetStatePropertyAll(_shape),
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    );
  }

  static ButtonStyle updateFilled(AsanaLandingPalette palette) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: Colors.white,
        padding: _padding,
        elevation: 0,
      ),
    );
  }

  static ButtonStyle createFilled(AsanaLandingPalette palette) {
    return updateFilled(palette);
  }

  static ButtonStyle successFilled() {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: successGreen,
        foregroundColor: Colors.white,
        padding: _padding,
        elevation: 0,
      ),
    );
  }

  static ButtonStyle returnFilled() {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: returnBlue,
        foregroundColor: Colors.white,
        padding: _padding,
        elevation: 0,
      ),
    );
  }

  static ButtonStyle submitFilled(AsanaLandingPalette palette) {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: palette.accent.withValues(alpha: 0.88),
        foregroundColor: Colors.white,
        padding: _padding,
        elevation: 0,
      ),
    );
  }

  static ButtonStyle undoOutlined(AsanaLandingPalette palette) {
    return _rounded(
      OutlinedButton.styleFrom(
        foregroundColor: kAsanaTextPrimary,
        backgroundColor: palette.listSurface,
        side: BorderSide(color: palette.accent.withValues(alpha: 0.35)),
        padding: _padding,
      ),
    );
  }

  /// Strong filled delete — visible on all five landing themes.
  static ButtonStyle deleteFilled() {
    return _rounded(
      FilledButton.styleFrom(
        backgroundColor: const Color(0xFFC62828),
        foregroundColor: Colors.white,
        padding: _padding,
        elevation: 1,
        shadowColor: const Color(0x66B71C1C),
      ).copyWith(
        side: const WidgetStatePropertyAll(
          BorderSide(color: Color(0xFFB71C1C), width: 1.5),
        ),
      ),
    );
  }
}

/// Submission pill for slide detail rows (matches table chip size).
class AsanaDetailSubmissionPill extends StatelessWidget {
  const AsanaDetailSubmissionPill({super.key, required this.submission});

  final String? submission;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AsanaTableCellChip(
        child: AsanaSubmissionChip(submission: submission),
      ),
    );
  }
}
