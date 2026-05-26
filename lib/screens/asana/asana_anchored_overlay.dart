import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Layer link for [AsanaHoverTapValue.anchorLink] (optional; positioning uses [anchorContext]).
typedef AsanaAnchorLink = LayerLink;

const double _kViewportMargin = 8;
const double _kAnchorGap = 2;

/// Vertical placement relative to the anchor widget.
enum AsanaAnchoredVerticalPlacement {
  below,
  above,
}

/// Left offset so [panelWidth] fits inside [viewportWidth].
double asanaClampPanelLeft({
  required double anchorLeft,
  required double anchorWidth,
  required double panelWidth,
  required double viewportWidth,
}) {
  final maxLeft = viewportWidth - _kViewportMargin - panelWidth;
  var left = anchorLeft;
  // Prefer aligning the panel's right edge with the field's right edge when overflowing.
  if (left + panelWidth > viewportWidth - _kViewportMargin) {
    left = anchorLeft + anchorWidth - panelWidth;
  }
  if (left < _kViewportMargin) left = _kViewportMargin;
  if (left > maxLeft) left = math.max(_kViewportMargin, maxLeft);
  return left;
}

RenderBox? _anchorRenderBox(BuildContext anchorContext) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize) return box;
  return null;
}

/// Positions [child] under the [anchorLink] target and re-measures while open.
class _AnchoredOverlayPosition extends StatefulWidget {
  const _AnchoredOverlayPosition({
    required this.anchorLink,
    required this.anchorContext,
    this.widthAlignContext,
    this.placement = AsanaAnchoredVerticalPlacement.below,
    required this.width,
    required this.child,
  });

  final LayerLink anchorLink;
  final BuildContext anchorContext;
  /// When set, horizontal position and width follow this context; [anchorContext] sets vertical anchor.
  final BuildContext? widthAlignContext;
  final AsanaAnchoredVerticalPlacement placement;
  final double width;
  final Widget child;

  @override
  State<_AnchoredOverlayPosition> createState() =>
      _AnchoredOverlayPositionState();
}

class _AnchoredOverlayPositionState extends State<_AnchoredOverlayPosition>
    with WidgetsBindingObserver {
  final GlobalKey _childKey = GlobalKey();
  double _left = 0;
  double? _top;
  double? _bottom;
  bool _laidOut = false;
  bool _tracking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    _tracking = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleMeasure();
  }

  void _scheduleMeasure() {
    if (!_tracking) return;
    SchedulerBinding.instance.addPostFrameCallback(_measure);
  }

  void _measure(_) {
    if (!mounted || !_tracking) return;
    final anchorBox = _anchorRenderBox(widget.anchorContext);
    final widthBox = _anchorRenderBox(
      widget.widthAlignContext ?? widget.anchorContext,
    );
    if (anchorBox == null || widthBox == null) {
      _scheduleMeasure();
      return;
    }

    final anchorOffset = anchorBox.localToGlobal(Offset.zero);
    final widthOffset = widthBox.localToGlobal(Offset.zero);
    final widthSize = widthBox.size;
    final viewportW = MediaQuery.sizeOf(context).width;
    final viewportH = MediaQuery.sizeOf(context).height;
    final left = asanaClampPanelLeft(
      anchorLeft: widthOffset.dx,
      anchorWidth: widthSize.width,
      panelWidth: widget.width,
      viewportWidth: viewportW,
    );

    var placeAbove = widget.placement == AsanaAnchoredVerticalPlacement.above;
    final childBox =
        _childKey.currentContext?.findRenderObject() as RenderBox?;
    final panelHeight = childBox?.size.height ?? 0;
    if (placeAbove && panelHeight > 0) {
      final panelTop = anchorOffset.dy - _kAnchorGap - panelHeight;
      if (panelTop < _kViewportMargin) {
        placeAbove = false;
      }
    }

    final double? top;
    final double? bottom;
    if (placeAbove) {
      top = null;
      bottom = viewportH - anchorOffset.dy + _kAnchorGap;
    } else {
      top = anchorOffset.dy + anchorBox.size.height + _kAnchorGap;
      bottom = null;
    }

    final changed = !_laidOut ||
        (left - _left).abs() > 0.5 ||
        (_top != null && top != null && (top - _top!).abs() > 0.5) ||
        (_bottom != null &&
            bottom != null &&
            (bottom - _bottom!).abs() > 0.5) ||
        (_top == null) != (top == null) ||
        (_bottom == null) != (bottom == null);
    if (changed) {
      setState(() {
        _left = left;
        _top = top;
        _bottom = bottom;
        _laidOut = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_laidOut) return const SizedBox.shrink();
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (_bottom != null) {
      return Positioned(
        left: _left,
        bottom: _bottom,
        width: widget.width,
        child: child,
      );
    }
    return Positioned(
      left: _left,
      top: _top,
      width: widget.width,
      child: child,
    );
  }
}

/// Inserts an overlay directly under the anchor field (viewport-clamped).
Future<void> showAsanaAnchoredOverlay({
  required LayerLink anchorLink,
  required BuildContext anchorContext,
  BuildContext? widthAlignContext,
  AsanaAnchoredVerticalPlacement placement =
      AsanaAnchoredVerticalPlacement.below,
  required double panelWidth,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  VoidCallback? whenClosed,
}) {
  final completer = Completer<void>();
  final overlay = Overlay.maybeOf(anchorContext, rootOverlay: true);
  if (overlay == null) {
    completer.complete();
    return completer.future;
  }

  late OverlayEntry entry;
  var barrierActive = false;
  final viewportW = MediaQuery.sizeOf(anchorContext).width;
  final width = math.min(
    panelWidth,
    viewportW - _kViewportMargin * 2,
  ).clamp(120.0, viewportW);

  void close() {
    if (entry.mounted) entry.remove();
    if (!completer.isCompleted) {
      completer.complete();
      whenClosed?.call();
    }
  }

  entry = OverlayEntry(
    builder: (ctx) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (barrierActive) close();
              },
            ),
          ),
          _AnchoredOverlayPosition(
            anchorLink: anchorLink,
            anchorContext: anchorContext,
            widthAlignContext: widthAlignContext,
            placement: placement,
            width: width,
            child: builder(ctx, close),
          ),
        ],
      );
    },
  );

  overlay.insert(entry);
  SchedulerBinding.instance.addPostFrameCallback((_) {
    barrierActive = true;
  });

  return completer.future;
}

/// Popup width matches the anchor field (textbox), capped only by viewport.
double asanaAnchoredFieldWidth(BuildContext anchorContext) {
  final viewportW = MediaQuery.sizeOf(anchorContext).width;
  final maxW = viewportW - _kViewportMargin * 2;
  final box = _anchorRenderBox(anchorContext);
  final anchorW = box?.size.width;
  if (anchorW == null || anchorW <= 0) {
    return maxW.clamp(120.0, maxW);
  }
  return anchorW.clamp(120.0, maxW);
}
