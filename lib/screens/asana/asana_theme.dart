import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Asana-style body/label color (dark gray, not pure black).
const Color kAsanaTextPrimary = Color(0xFF2D2E2F);
const Color kAsanaTextSecondary = Color(0xFF6D6E6F);

/// Narrow empty column after each plain-text table cell (before the next column).
const double kAsanaTextColumnGap = 16;

/// Status column width (fits "Incomplete" / "In progress" chips).
const double kAsanaTableStatusColWidth = 112;

/// Gap widget used between text columns in task / project / home tables.
Widget asanaTextColumnGap() => const SizedBox(width: kAsanaTextColumnGap);

/// Table row backgrounds per landing theme (task / sub-task / project).
class AsanaTableColors {
  const AsanaTableColors({
    required this.taskRow,
    required this.subtaskRow,
    required this.subtaskSection,
    required this.projectRow,
  });

  final Color taskRow;
  final Color subtaskRow;
  final Color subtaskSection;
  final Color projectRow;
}

/// Default table colors (Asana theme) — prefer [AsanaLandingPalette.tableColors].
const AsanaTableColors kAsanaDefaultTableColors = AsanaTableColors(
  taskRow: Color(0xFFFFFFFF),
  subtaskRow: Color(0xFFF5F6F7),
  subtaskSection: Color(0xFFEBECEE),
  projectRow: Color(0xFFFFFFFF),
);

@Deprecated('Use AsanaLandingPalette.tableColors.taskRow')
const Color kAsanaTaskRowBackground = Color(0xFFFFFFFF);

@Deprecated('Use AsanaLandingPalette.tableColors.subtaskRow')
const Color kAsanaSubtaskRowBackground = Color(0xFFF5F6F7);

@Deprecated('Use AsanaLandingPalette.tableColors.subtaskSection')
const Color kAsanaSubtaskSectionBackground = Color(0xFFEBECEE);

/// CJK fallback when Inter has no glyph (task names, staff names, etc.).
const List<String> kAsanaFontFallbacks = [
  'Noto Sans TC',
  'Segoe UI',
  'Roboto',
  'Helvetica Neue',
  'Arial',
  'sans-serif',
];

/// Inter-based theme for the Asana prototype shell (matches Asana Inbox-style UI).
ThemeData buildAsanaTheme(
  ThemeData parent, {
  required Color seedColor,
}) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: Brightness.light,
    surface: Colors.white,
  );

  final base = parent.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: parent.scaffoldBackgroundColor,
  );

  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: kAsanaTextPrimary,
    displayColor: kAsanaTextPrimary,
    fontFamilyFallback: kAsanaFontFallbacks,
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: kAsanaTextPrimary,
        height: 1.25,
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: kAsanaTextSecondary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    dividerTheme: base.dividerTheme.copyWith(color: const Color(0xFFE8ECEE)),
  );
}

/// Inter [TextStyle] for one-off widgets (search field, banner title, etc.).
TextStyle? asanaTextStyle(
  TextStyle? base, {
  FontWeight? fontWeight,
  double? fontSize,
  Color? color,
  double? height,
}) {
  return GoogleFonts.inter(
    textStyle: base,
    fontWeight: fontWeight ?? base?.fontWeight,
    fontSize: fontSize ?? base?.fontSize,
    color: color ?? base?.color,
    height: height ?? base?.height,
  ).copyWith(fontFamilyFallback: kAsanaFontFallbacks);
}

/// Header label cell with vertical centering (matches data row height).
Widget asanaTableHeaderLabel({
  required double width,
  required String label,
  required TextStyle? style,
  double rowHeight = 24,
}) {
  return SizedBox(
    width: width,
    height: rowHeight,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

/// Column header in task / project / home tables.
TextStyle? asanaTableHeaderStyle(BuildContext context) {
  return Theme.of(context).textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.1,
        color: kAsanaTextSecondary,
      );
}

/// Body cell text for table rows (matches tasks panel).
TextStyle? asanaTableRowValueStyle(
  BuildContext context, {
  bool completed = false,
}) {
  final theme = Theme.of(context);
  return theme.textTheme.bodyMedium?.copyWith(
    color: theme.colorScheme.onSurface,
  );
}

/// Task / sub-task / project name column (always bold; completion does not lighten).
TextStyle? asanaTableRowNameStyle(
  BuildContext context, {
  bool completed = false,
  bool isSubtask = false,
}) {
  return asanaTextStyle(
    Theme.of(context).textTheme.bodyMedium,
    fontSize: 14,
    fontWeight: isSubtask ? FontWeight.w600 : FontWeight.w700,
    color: kAsanaTextPrimary,
  );
}

/// User initials for sidebar avatar (e.g. Ken Lee → KL).
String asanaStaffInitials(String fullName) {
  final parts =
      fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    if (p.length >= 2) {
      return '${p[0]}${p[1]}'.toUpperCase();
    }
    return p[0].toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
