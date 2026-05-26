import 'package:flutter/material.dart';

/// Full-screen dimmed overlay with centered spinner (task save, file upload, etc.).
class AsanaBlockingLoadingOverlay {
  AsanaBlockingLoadingOverlay._();

  static OverlayEntry? _entry;
  static int _depth = 0;

  static void show(BuildContext context) {
    _depth++;
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _entry = OverlayEntry(
      builder: (ctx) => Material(
        color: const Color(0x66000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Color(0xFF4573D2),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    if (_depth <= 0) return;
    _depth--;
    if (_depth > 0) return;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _depth = 0;
  }

  static void hideAll() {
    _depth = 0;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }
}
