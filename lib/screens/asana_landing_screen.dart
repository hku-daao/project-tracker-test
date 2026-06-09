import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../services/asana_filter_cookie_storage.dart';
import '../web_deep_link.dart';
import 'asana/asana_blocking_loading_overlay.dart';
import 'asana/asana_detail_selection.dart';
import 'asana/asana_detail_slide_panel.dart';
import 'asana/asana_detail_widgets.dart';
import 'asana/asana_home_panel.dart';
import 'asana/asana_projects_panel.dart';
import 'asana/asana_tasks_panel.dart';
import 'asana/asana_theme.dart';

const String _kAsanaFeedbackFormUrl =
    'https://forms.cloud.microsoft/Pages/ResponsePage.aspx?id=TrX5QnckukG_CXoNKoP_CXmxjjVqONdDujd4tWBFFN9UMk1ZS0EzMFZSSlFSMkhXTjI5UE82QThKTC4u';

/// Header / body / footer colors for the right-hand detail slide.
class AsanaSlideChrome {
  const AsanaSlideChrome(this.palette);

  final AsanaLandingPalette palette;

  /// Top strip darker than the bottom action area (Asana: banner vs selectedNav).
  Color get header => palette.darkChrome ? palette.banner : palette.banner;
  Color get onHeader => palette.onBanner;
  Color get body => palette.content;
  Color get footer =>
      palette.darkChrome ? palette.selectedNav : palette.sidebar;
  Color get footerBorder => palette.darkChrome
      ? palette.onSidebarMuted.withValues(alpha: 0.35)
      : palette.accent.withValues(alpha: 0.25);
}

/// Visual palette for [AsanaLandingScreen] prototype themes.
class AsanaLandingPalette {
  const AsanaLandingPalette({
    required this.id,
    required this.banner,
    required this.sidebar,
    required this.content,
    required this.searchField,
    required this.selectedNav,
    required this.onBanner,
    required this.onSidebar,
    required this.onSidebarMuted,
    required this.darkChrome,
    required this.accent,
    required this.tableColors,
    required this.panelBackground,
    required this.listSurface,
  });

  final String id;
  final Color banner;
  final Color sidebar;
  final Color content;

  /// Pale background behind toolbars and around the list card.
  final Color panelBackground;

  /// White (or near-white) box containing the data table.
  final Color listSurface;
  final Color searchField;
  final Color selectedNav;
  final Color onBanner;
  final Color onSidebar;
  final Color onSidebarMuted;

  /// Dark header + sidebar (Asana-style); light text on nav.
  final bool darkChrome;
  final Color accent;

  /// Task / sub-task / project table row backgrounds for this theme.
  final AsanaTableColors tableColors;

  /// Home "People" metric chip (background, foreground).
  (Color bg, Color fg) homeMetricStyle(String metric) {
    switch (metric) {
      case 'overdue':
        return (
          Color.alphaBlend(accent.withValues(alpha: 0.18), listSurface),
          accent,
        );
      case 'completed':
        return (const Color(0xFFE8F5E9), const Color(0xFF2E7D32));
      case 'upcoming':
        return (
          Color.alphaBlend(accent.withValues(alpha: 0.14), listSurface),
          darkChrome ? const Color(0xFF8E2424) : const Color(0xFF9E2A2A),
        );
      case 'incomplete':
      default:
        return (const Color(0xFFECEFF1), const Color(0xFF455A64));
    }
  }

  /// Default: dark chrome + white content (matches Asana Inbox reference).
  static const asana = AsanaLandingPalette(
    id: 'Charcoal',
    banner: Color(0xFF2A2B2C),
    sidebar: Color(0xFF2A2B2C),
    content: Color(0xFFFFFFFF),
    searchField: Color(0xFF353636),
    selectedNav: Color(0xFF3F4041),
    onBanner: Color(0xFFFFFFFF),
    onSidebar: Color(0xFFF5F6F7),
    onSidebarMuted: Color(0xFF9CA6AF),
    darkChrome: true,
    accent: Color(0xFFF06A6A),
    tableColors: AsanaTableColors(
      taskRow: Color(0xFFFFFFFF),
      subtaskRow: Color(0xFFF5F6F7),
      subtaskSection: Color(0xFFEBECEE),
      projectRow: Color(0xFFFFFFFF),
    ),
    panelBackground: Color(0xFFF0F1F2),
    listSurface: Color(0xFFFFFFFF),
  );

  static const classic = AsanaLandingPalette(
    id: 'Classic',
    banner: Color(0xFFB2DFDB),
    sidebar: Color(0xFFE8F5F3),
    content: Color(0xFFFAFCFC),
    searchField: Colors.white,
    selectedNav: Color(0xFF80CBC4),
    onBanner: Color(0xFF004D40),
    onSidebar: Color(0xFF2D2E2F),
    onSidebarMuted: Color(0xFF6D6E6F),
    darkChrome: false,
    accent: Color(0xFF00897B),
    tableColors: AsanaTableColors(
      taskRow: Color(0xFFFAFCFC),
      subtaskRow: Color(0xFFE8F5F3),
      subtaskSection: Color(0xFFD5EFEB),
      projectRow: Color(0xFFF2FAF9),
    ),
    panelBackground: Color(0xFFF4FBFA),
    listSurface: Color(0xFFFFFFFF),
  );

  /// Deep blue header, cool grey sidebar (professional / corporate).
  static const ocean = AsanaLandingPalette(
    id: 'Ocean',
    banner: Color(0xFF1565C0),
    sidebar: Color(0xFFE3F2FD),
    content: Color(0xFFF5F9FF),
    searchField: Color(0xFFFAFCFF),
    selectedNav: Color(0xFF90CAF9),
    onBanner: Colors.white,
    onSidebar: Color(0xFF2D2E2F),
    onSidebarMuted: Color(0xFF6D6E6F),
    darkChrome: false,
    accent: Color(0xFF1976D2),
    tableColors: AsanaTableColors(
      taskRow: Color(0xFFF5F9FF),
      subtaskRow: Color(0xFFE3F2FD),
      subtaskSection: Color(0xFFBBDEFB),
      projectRow: Color(0xFFEEF5FD),
    ),
    panelBackground: Color(0xFFF1F6FD),
    listSurface: Color(0xFFFFFFFF),
  );

  /// Sage greens (calm / operations).
  static const forest = AsanaLandingPalette(
    id: 'Forest',
    banner: Color(0xFF2E7D32),
    sidebar: Color(0xFFE8F5E9),
    content: Color(0xFFF6FBF6),
    searchField: Color(0xFFFAFFFA),
    selectedNav: Color(0xFFA5D6A7),
    onBanner: Colors.white,
    onSidebar: Color(0xFF2D2E2F),
    onSidebarMuted: Color(0xFF6D6E6F),
    darkChrome: false,
    accent: Color(0xFF388E3C),
    tableColors: AsanaTableColors(
      taskRow: Color(0xFFF6FBF6),
      subtaskRow: Color(0xFFE8F5E9),
      subtaskSection: Color(0xFFC8E6C9),
      projectRow: Color(0xFFF0F8F0),
    ),
    panelBackground: Color(0xFFF2FAF3),
    listSurface: Color(0xFFFFFFFF),
  );

  /// Warm coral header (energetic / creative).
  static const sunset = AsanaLandingPalette(
    id: 'Sunset',
    banner: Color(0xFFE64A19),
    sidebar: Color(0xFFFFF3E0),
    content: Color(0xFFFFFBF7),
    searchField: Color(0xFFFFFFFF),
    selectedNav: Color(0xFFFFCC80),
    onBanner: Colors.white,
    onSidebar: Color(0xFF2D2E2F),
    onSidebarMuted: Color(0xFF6D6E6F),
    darkChrome: false,
    accent: Color(0xFFF4511E),
    tableColors: AsanaTableColors(
      taskRow: Color(0xFFFFFBF7),
      subtaskRow: Color(0xFFFFF3E0),
      subtaskSection: Color(0xFFFFE0B2),
      projectRow: Color(0xFFFFF8F2),
    ),
    panelBackground: Color(0xFFFFF8F0),
    listSurface: Color(0xFFFFFFFF),
  );

  static const List<AsanaLandingPalette> all = [
    asana,
    classic,
    ocean,
    forest,
    sunset,
  ];

  static AsanaLandingPalette byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => asana);
  }
}

const _kSidebarAnimDuration = Duration(milliseconds: 280);

/// Below this width, an open detail slide uses the full viewport width.
const _kDetailFullWidthBreakpoint = 840.0;

/// Below this viewport width the nav sidebar auto-hides (menu can reopen when wider).
const _kSidebarAutoHideWidth = 1280.0;

/// Prototype landing layout (Asana-inspired). Temporary UI design sandbox.
class AsanaLandingScreen extends StatefulWidget {
  const AsanaLandingScreen({super.key});

  @override
  State<AsanaLandingScreen> createState() => _AsanaLandingScreenState();
}

class _AsanaLandingScreenState extends State<AsanaLandingScreen> {
  static const Duration _kDetailSlideDuration = Duration(milliseconds: 300);
  static const double _kSidebarWidth = 240;
  static const String _themeCookieKey = 'asana_landing_theme';

  final _searchController = TextEditingController();

  String _selectedNav = 'Home';
  String _themeId = AsanaLandingPalette.asana.id;
  bool? _sidebarOpenOverride;
  double? _lastScreenWidth;
  bool _themeMenuExpanded = false;
  final List<AsanaDetailSelection> _detailStack = [];
  int _detailRefreshToken = 0;

  static const List<String> _navItems = [
    'Home',
    'All Tasks & Sub-tasks',
    'Tasks',
    'Projects',
  ];

  AsanaLandingPalette get _palette => AsanaLandingPalette.byId(_themeId);

  Future<void> _openFeedbackForm() async {
    await launchUrl(
      Uri.parse(_kAsanaFeedbackFormUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  void _showNavigationLoadingUntilNextFrame() {
    AsanaBlockingLoadingOverlay.show(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 450), () {
        AsanaBlockingLoadingOverlay.hide();
      });
    });
  }

  Widget _buildMainContent({
    required AsanaLandingPalette palette,
    required String searchQuery,
  }) {
    if (_selectedNav == 'Tasks' || _selectedNav == 'All Tasks & Sub-tasks') {
      return AsanaTasksPanel(
        key: ValueKey(_selectedNav),
        palette: palette,
        searchQuery: searchQuery,
        flatTasksAndSubtasks: _selectedNav == 'All Tasks & Sub-tasks',
        refreshToken: _detailRefreshToken,
        onOpenTask: (id) => setState(
          () => _detailStack
            ..clear()
            ..add(AsanaDetailSelection.task(id)),
        ),
        onOpenSubtask: (id) => setState(
          () => _detailStack
            ..clear()
            ..add(AsanaDetailSelection.subtask(id)),
        ),
        onCreateTask: () => setState(
          () => _detailStack
            ..clear()
            ..add(const AsanaDetailSelection.createTask()),
        ),
      );
    }
    if (_selectedNav == 'Projects') {
      return AsanaProjectsPanel(
        palette: palette,
        searchQuery: searchQuery,
        refreshToken: _detailRefreshToken,
        onOpenProject: (id) => setState(
          () => _detailStack
            ..clear()
            ..add(AsanaDetailSelection.project(id)),
        ),
        onOpenTask: (id) => setState(
          () => _detailStack
            ..clear()
            ..add(AsanaDetailSelection.task(id)),
        ),
        onCreateProject: () => setState(
          () => _detailStack
            ..clear()
            ..add(const AsanaDetailSelection.createProject()),
        ),
      );
    }
    if (_selectedNav == 'Home') {
      return AsanaHomePanel(
        palette: palette,
        searchQuery: searchQuery,
        onOpenTask: (id) => setState(
          () => _detailStack
            ..clear()
            ..add(AsanaDetailSelection.task(id)),
        ),
        onOpenProject: (id) => setState(
          () => _detailStack
            ..clear()
            ..add(AsanaDetailSelection.project(id)),
        ),
      );
    }
    return ColoredBox(color: palette.content);
  }

  /// One slide host for the whole open/close cycle (inner task panel keeps its own key).
  String _detailPanelKey() {
    if (_detailStack.isEmpty) return 'detail-closed';
    return 'detail-slide-open';
  }

  void _dismissAllDetails() {
    if (_detailStack.isEmpty) return;
    AsanaBlockingLoadingOverlay.hideAll();
    setState(_detailStack.clear);
  }

  void _popDetail() {
    if (_detailStack.isEmpty) return;
    AsanaBlockingLoadingOverlay.hideAll();
    setState(() {
      if (_detailStack.length > 1) {
        _detailStack.removeLast();
      } else {
        _detailStack.clear();
      }
    });
  }

  void _handleSubtaskCreated(String parentTaskId, String subtaskId) {
    setState(() {
      _detailRefreshToken++;
    });
  }

  void _handleSubtaskChanged() {
    setState(() => _detailRefreshToken++);
  }

  void _handleTaskCreated(String taskId) {
    setState(() {
      _detailStack
        ..clear()
        ..add(AsanaDetailSelection.task(taskId));
      _detailRefreshToken++;
    });
  }

  void _handleProjectChanged() {
    setState(() => _detailRefreshToken++);
  }

  void _handleProjectCreated(String projectId) {
    setState(() {
      _detailStack
        ..clear()
        ..add(AsanaDetailSelection.project(projectId));
      _detailRefreshToken++;
    });
  }

  @override
  void initState() {
    super.initState();
    final themeId = AsanaFilterCookieStorage.load(
      _themeCookieKey,
    )?['themeId']?.toString().trim();
    if (themeId != null &&
        themeId.isNotEmpty &&
        AsanaLandingPalette.all.any((p) => p.id == themeId)) {
      _themeId = themeId;
    }
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialDeepLink();
        syncWebLocationForAsanaDesign();
      });
    }
  }

  void _openInitialDeepLink() {
    final subtaskId = readSubtaskIdFromUrlOrSession();
    if (subtaskId != null && subtaskId.isNotEmpty) {
      setState(() {
        _selectedNav = 'All Tasks & Sub-tasks';
        _detailStack
          ..clear()
          ..add(AsanaDetailSelection.subtask(subtaskId));
      });
      return;
    }
    final taskId = readTaskIdFromUrlOrSession();
    if (taskId != null && taskId.isNotEmpty) {
      setState(() {
        _selectedNav = 'Tasks';
        _detailStack
          ..clear()
          ..add(AsanaDetailSelection.task(taskId));
      });
      return;
    }
    final projectId = readProjectIdFromUrlOrSession();
    if (projectId != null && projectId.isNotEmpty) {
      setState(() {
        _selectedNav = 'Projects';
        _detailStack
          ..clear()
          ..add(AsanaDetailSelection.project(projectId));
      });
    }
  }

  @override
  void dispose() {
    AsanaBlockingLoadingOverlay.hideAll();
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSidebarBody(AsanaLandingPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            children: [
              for (final label in _navItems)
                _SidebarNavTile(
                  label: label,
                  palette: palette,
                  selected: _selectedNav == label,
                  onTap: () {
                    if (_selectedNav != label) {
                      _showNavigationLoadingUntilNextFrame();
                    }
                    setState(() {
                      _selectedNav = label;
                      _detailStack.clear();
                      if (MediaQuery.sizeOf(context).width <
                          _kSidebarAutoHideWidth) {
                        _sidebarOpenOverride = false;
                      }
                    });
                  },
                ),
              _SidebarNavTile(
                label: 'Feedback',
                palette: palette,
                selected: false,
                onTap: _openFeedbackForm,
              ),
              _ThemeSidebarExpandable(
                palette: palette,
                expanded: _themeMenuExpanded,
                selectedThemeId: _themeId,
                onToggle: () =>
                    setState(() => _themeMenuExpanded = !_themeMenuExpanded),
                onSelectTheme: (id) => setState(() {
                  _themeId = id;
                  _themeMenuExpanded = false;
                  AsanaFilterCookieStorage.save(_themeCookieKey, {
                    'themeId': id,
                  });
                }),
              ),
            ],
          ),
        ),
        _SidebarUserAvatar(palette: palette),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarOverlay = screenWidth < _kSidebarAutoHideWidth;
    final sidebarOpen = _sidebarOpenOverride ?? !sidebarOverlay;
    if (_lastScreenWidth != null &&
        _lastScreenWidth! >= _kSidebarAutoHideWidth &&
        sidebarOverlay &&
        sidebarOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sidebarOpenOverride = false);
      });
    }
    _lastScreenWidth = screenWidth;

    final inlineSidebar = !sidebarOverlay && sidebarOpen;
    final overlaySidebar = sidebarOverlay && sidebarOpen;
    final sidebarVisible = inlineSidebar || overlaySidebar;
    final compactBanner = screenWidth < 600;
    final searchWidth = compactBanner ? screenWidth * 0.42 : screenWidth / 3;
    final asanaTheme = buildAsanaTheme(
      Theme.of(context),
      seedColor: palette.accent,
    );
    final titleStyle = asanaTextStyle(
      asanaTheme.textTheme.titleMedium,
      fontWeight: FontWeight.w600,
      fontSize: 15,
      color: palette.onBanner,
    );
    final titleFontSize = titleStyle?.fontSize ?? 15;
    final searchBarHeight = titleFontSize * 2.5;
    final searchTextStyle = asanaTextStyle(
      asanaTheme.textTheme.bodyMedium,
      fontSize: 14,
      height: 1.25,
      color: palette.darkChrome ? palette.onSidebar : kAsanaTextPrimary,
    );

    return Theme(
      data: asanaTheme,
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: palette.banner,
              elevation: 1,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          sidebarVisible ? Icons.menu_open : Icons.menu,
                          color: palette.onBanner,
                        ),
                        tooltip: sidebarVisible ? 'Hide panel' : 'Show panel',
                        onPressed: () =>
                            setState(() => _sidebarOpenOverride = !sidebarOpen),
                      ),
                      Expanded(
                        child: Center(
                          child: SizedBox(
                            width: searchWidth,
                            height: searchBarHeight,
                            child: TextField(
                              controller: _searchController,
                              style: searchTextStyle,
                              decoration: InputDecoration(
                                hintText: 'Search',
                                hintStyle: asanaTextStyle(
                                  asanaTheme.textTheme.bodyMedium,
                                  fontSize: 14,
                                  color: palette.darkChrome
                                      ? palette.onSidebarMuted
                                      : kAsanaTextSecondary,
                                ),
                                filled: true,
                                fillColor: palette.searchField,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical:
                                      (searchBarHeight - titleFontSize * 1.2) /
                                      2,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  size: titleFontSize * 1.35,
                                  color: palette.darkChrome
                                      ? palette.onSidebarMuted
                                      : Colors.black54,
                                ),
                                prefixIconConstraints: BoxConstraints(
                                  minWidth: searchBarHeight,
                                  minHeight: searchBarHeight,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: palette.accent,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _AsanaBannerLogo(height: titleFontSize * 1.6),
                            SizedBox(width: compactBanner ? 6 : 8),
                            Text(
                              compactBanner
                                  ? 'Project\nTracker'
                                  : 'Project Tracker',
                              style: titleStyle?.copyWith(
                                fontSize: compactBanner ? 12 : titleFontSize,
                                height: compactBanner ? 1.05 : 1.2,
                              ),
                              maxLines: compactBanner ? 2 : 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!sidebarOverlay)
                        ClipRect(
                          child: AnimatedContainer(
                            duration: _kSidebarAnimDuration,
                            curve: Curves.easeInOut,
                            width: sidebarOpen ? _kSidebarWidth : 0,
                            child: Material(
                              color: palette.sidebar,
                              child: SizedBox(
                                width: _kSidebarWidth,
                                child: _buildSidebarBody(palette),
                              ),
                            ),
                          ),
                        ),
                      Expanded(
                        child: ListenableBuilder(
                          listenable: _searchController,
                          builder: (context, _) {
                            final q = _searchController.text;
                            final screenW = MediaQuery.sizeOf(context).width;
                            final basePanelWidth = (screenW * 0.504).clamp(
                              480.0,
                              672.0,
                            );
                            final panelWidth =
                                _detailStack.isNotEmpty &&
                                    screenW < _kDetailFullWidthBreakpoint
                                ? screenW
                                : basePanelWidth;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                _buildMainContent(
                                  palette: palette,
                                  searchQuery: q,
                                ),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    ignoring: _detailStack.isEmpty,
                                    child: AnimatedOpacity(
                                      duration: _kDetailSlideDuration,
                                      opacity: _detailStack.isEmpty ? 0 : 1,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _dismissAllDetails,
                                        child: const ColoredBox(
                                          color: Color(0x33000000),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: AnimatedSwitcher(
                                    duration: _kDetailSlideDuration,
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      final offset = Tween<Offset>(
                                        begin: const Offset(1, 0),
                                        end: Offset.zero,
                                      ).animate(animation);
                                      return SlideTransition(
                                        position: offset,
                                        child: child,
                                      );
                                    },
                                    child: _detailStack.isEmpty
                                        ? const SizedBox.shrink(
                                            key: ValueKey<String>(
                                              'detail-closed',
                                            ),
                                          )
                                        : AsanaDetailSlidePanel(
                                            key: ValueKey<String>(
                                              _detailPanelKey(),
                                            ),
                                            width: panelWidth,
                                            palette: palette,
                                            stack:
                                                List<AsanaDetailSelection>.from(
                                                  _detailStack,
                                                ),
                                            detailRefreshToken:
                                                _detailRefreshToken,
                                            onDismissAll: _dismissAllDetails,
                                            onPop: _popDetail,
                                            onPushCreateSubtask: (taskId) =>
                                                setState(
                                                  () => _detailStack.add(
                                                    AsanaDetailSelection.createSubtask(
                                                      taskId,
                                                    ),
                                                  ),
                                                ),
                                            onPushSubtask: (id) {
                                              AsanaBlockingLoadingOverlay.show(
                                                context,
                                              );
                                              setState(
                                                () => _detailStack.add(
                                                  AsanaDetailSelection.subtask(
                                                    id,
                                                  ),
                                                ),
                                              );
                                              WidgetsBinding.instance
                                                  .addPostFrameCallback((_) {
                                                    Future<void>.delayed(
                                                      const Duration(
                                                        milliseconds: 450,
                                                      ),
                                                      () {
                                                        AsanaBlockingLoadingOverlay.hide();
                                                      },
                                                    );
                                                  });
                                            },
                                            onPushCreateTaskForProject:
                                                (projectId) => setState(
                                                  () => _detailStack.add(
                                                    AsanaDetailSelection.createTask(
                                                      initialProjectId:
                                                          projectId,
                                                    ),
                                                  ),
                                                ),
                                            onPushTaskFromProject: (taskId) =>
                                                setState(
                                                  () => _detailStack
                                                    ..clear()
                                                    ..add(
                                                      AsanaDetailSelection.task(
                                                        taskId,
                                                      ),
                                                    ),
                                                ),
                                            onTaskCreated: _handleTaskCreated,
                                            onProjectCreated:
                                                _handleProjectCreated,
                                            onProjectChanged:
                                                _handleProjectChanged,
                                            onSubtaskCreated:
                                                _handleSubtaskCreated,
                                            onSubtaskChanged:
                                                _handleSubtaskChanged,
                                          ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  if (sidebarOverlay) ...[
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !overlaySidebar,
                        child: AnimatedOpacity(
                          duration: _kSidebarAnimDuration,
                          opacity: overlaySidebar ? 1 : 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () =>
                                setState(() => _sidebarOpenOverride = false),
                            child: const ColoredBox(color: Color(0x33000000)),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: ClipRect(
                        child: AnimatedSlide(
                          duration: _kSidebarAnimDuration,
                          curve: Curves.easeInOut,
                          offset: overlaySidebar
                              ? Offset.zero
                              : const Offset(-1, 0),
                          child: Material(
                            elevation: 8,
                            color: palette.sidebar,
                            child: SizedBox(
                              width: _kSidebarWidth,
                              child: _buildSidebarBody(palette),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Theme" nav row — same look as [ _SidebarNavTile ]; expands theme list below.
class _ThemeSidebarExpandable extends StatelessWidget {
  const _ThemeSidebarExpandable({
    required this.palette,
    required this.expanded,
    required this.selectedThemeId,
    required this.onToggle,
    required this.onSelectTheme,
  });

  final AsanaLandingPalette palette;
  final bool expanded;
  final String selectedThemeId;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelectTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarNavTile(
          label: 'Theme',
          palette: palette,
          selected: expanded,
          onTap: onToggle,
          trailing: Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 22,
            color: expanded
                ? (palette.darkChrome
                      ? Colors.white
                      : palette.accent.withValues(alpha: 0.95))
                : palette.onSidebarMuted,
          ),
        ),
        AnimatedSize(
          duration: _kSidebarAnimDuration,
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2, bottom: 4),
                  child: Column(
                    children: [
                      for (final p in AsanaLandingPalette.all)
                        _SidebarNavTile(
                          label: p.id,
                          palette: palette,
                          selected: selectedThemeId == p.id,
                          onTap: () => onSelectTheme(p.id),
                          leading: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: p.banner,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black26),
                            ),
                          ),
                          densePadding: true,
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  const _SidebarNavTile({
    required this.label,
    required this.palette,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.leading,
    this.densePadding = false,
  });

  final String label;
  final AsanaLandingPalette palette;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? leading;
  final bool densePadding;

  static const double _kTileHeight = 48;
  static const double _kTileHeightDense = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tileHeight = densePadding ? _kTileHeightDense : _kTileHeight;
    final textColor = selected
        ? (palette.darkChrome ? Colors.white : palette.accent)
        : palette.onSidebar;
    final textStyle = asanaTextStyle(
      theme.textTheme.bodyMedium,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      fontSize: 14,
      color: textColor,
      height: 1.25,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? palette.selectedNav : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: tileHeight,
            decoration: selected && palette.darkChrome
                ? const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.white, width: 3),
                    ),
                  )
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: Text(
                      label,
                      style: textStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom-left sidebar avatar with staff initials (e.g. Ken Lee → KL) and log out button.
class _SidebarUserAvatar extends StatelessWidget {
  const _SidebarUserAvatar({required this.palette});

  final AsanaLandingPalette palette;

  Future<void> _confirmLogOut(BuildContext context) async {
    final ok = await showAsanaConfirmDialog(
      context: context,
      title: 'Log out',
      content: 'Are you sure you want to log out?',
      confirmText: 'Log out',
      isDestructive: true,
      palette: palette,
    );
    if (ok == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final id = state.userStaffAppId?.trim();
    var displayName = '';
    if (id != null && id.isNotEmpty) {
      displayName = state.assigneeById(id)?.name.trim() ?? '';
    }
    final initials = asanaStaffInitials(
      displayName.isNotEmpty ? displayName : '?',
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: asanaTextStyle(
                Theme.of(context).textTheme.labelLarge,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _confirmLogOut(context),
            icon: const Icon(Icons.logout),
            color: palette.darkChrome ? Colors.white : kAsanaTextSecondary,
            tooltip: 'Log out',
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

/// App logo in the top banner (same asset as login).
class _AsanaBannerLogo extends StatelessWidget {
  const _AsanaBannerLogo({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheH = (height * dpr).round().clamp(1, 4096);

    return Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      cacheHeight: cacheH,
      semanticLabel: 'Project Tracker logo',
    );
  }
}
