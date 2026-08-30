import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'history_helper.dart';
import '../core/app_logger.dart';
import '../core/styles.dart';
import 'user_provider.dart';
import 'request_provider.dart';
import 'ui_provider.dart';
import 'category_provider.dart';
import 'wallpaper_provider.dart';
import '../core/notification_service.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/providers/allocation_provider.dart';
import '../student/student_routes.dart' deferred as student_routes;
import '../warden/warden_routes.dart' deferred as warden_routes;
import '../admin/admin_routes.dart' deferred as admin_routes;
import '../maintenance/maintenance_routes.dart' deferred as maintenance_routes;
import '../security/security_routes.dart' deferred as security_routes;
import 'widgets/glassmorphic_jelly_navbar.dart';

class MainResponsiveLayout extends StatefulWidget {
  final String? initialRequestId;
  final String? senderId;
  final bool isSecurity;
  final bool showAnnouncements;
  final String? initialRoute;
  final Object? initialRouteArgs;

  const MainResponsiveLayout(
      {this.initialRequestId,
      this.senderId,
      this.isSecurity = false,
      this.showAnnouncements = false,
      this.initialRoute,
      this.initialRouteArgs,
      super.key});

  @override
  State<MainResponsiveLayout> createState() => MainResponsiveLayoutState();
}

class MainResponsiveLayoutState extends State<MainResponsiveLayout> {
  int _selectedIndex = 0;
  String? reportsCategoryFilter;
  late final PageController _pageController;
  final GlobalKey<NavigatorState> _phoneNavigatorKey =
      GlobalKey<NavigatorState>();
  late final _NestedNavigatorObserver _navigatorObserver;

  void setSelectedIndex(int index, {String? reportsCategory}) {
    setState(() {
      _selectedIndex = index;
      if (reportsCategory != null) {
        reportsCategoryFilter = reportsCategory;
      }
    });
    if (_pageController.hasClients && _pageController.page?.round() != index) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 180),
        curve: Curves.fastOutSlowIn,
      );
    }
    if (_phoneNavigatorKey.currentState != null) {
      _phoneNavigatorKey.currentState!.popUntil((route) => route.isFirst);
    }
  }

  DateTime? _lastBackPressed;

  Future<void> _handleBackPress() async {
    // If a nested page is open, pop it first
    if (_phoneNavigatorKey.currentState?.canPop() ?? false) {
      _phoneNavigatorKey.currentState!.pop();
      return;
    }

    // If we are on a different tab, go back to the home tab first (index 0)
    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
      });
      if (_phoneNavigatorKey.currentState != null) {
        _phoneNavigatorKey.currentState!.popUntil((route) => route.isFirst);
      }
      return;
    }

    // Double-back to exit logic
    if (_lastBackPressed == null ||
        DateTime.now().difference(_lastBackPressed!) >
            const Duration(seconds: 4)) {
      _lastBackPressed = DateTime.now();

      // Trigger global dashboard refresh (calls UserProvider.triggerDashboardRefresh)
      final user = Provider.of<UserProvider>(context, listen: false);
      user.triggerDashboardRefresh();

      // Show toast / snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    // Exit the application
    await SystemNavigator.pop();
  }

  void _handlePop() {
    debugPrint(
        'MainResponsiveLayoutState: _handlePop called. canPop = ${_phoneNavigatorKey.currentState?.canPop()}');
    if (_phoneNavigatorKey.currentState?.canPop() ?? false) {
      _phoneNavigatorKey.currentState!.pop();
    } else {
      _handleBackPress();
    }
  }

  Timer? _countTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _navigatorObserver = _NestedNavigatorObserver(
      onStackChanged: () {
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      },
    );
    if (kIsWeb) {
      HistoryHelper.addPopStateListener(_handlePop);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = Provider.of<UserProvider>(context, listen: false);
      _applyInitialUiState();
      unawaited(_hydrateAfterFirstPaint(user));

      if (widget.initialRoute != null) {
        _phoneNavigatorKey.currentState?.pushNamed(
          widget.initialRoute!,
          arguments: widget.initialRouteArgs,
        );
      }
    });
  }

  void _applyInitialUiState() {
    context.read<UIProvider>().setShowBottomNavBar(true);
    if (widget.initialRequestId != null) {
      if (widget.showAnnouncements) {
        context.read<UIProvider>().setActiveChatChannel('Announcements');
      } else if (widget.isSecurity) {
        context.read<UIProvider>().setActiveChatChannel('Security');
      } else {
        context.read<UIProvider>().setActiveChatChannel('Warden');
      }
    } else if (widget.showAnnouncements) {
      context.read<UIProvider>().setActiveChatChannel('Announcements');
    } else if (widget.isSecurity) {
      context.read<UIProvider>().setActiveChatChannel('Security');
    } else {
      context.read<UIProvider>().setActiveChatChannel(null);
    }
  }

  Future<void> _hydrateAfterFirstPaint(UserProvider initialUser) async {
    // Single short settle — lets the first frame paint before kicking off I/O
    await Future<void>.delayed(
        kIsWeb ? const Duration(milliseconds: 150) : const Duration(milliseconds: 300));
    if (!mounted) return;

    final user = Provider.of<UserProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);

    // Launch all background data fetches concurrently — fire-and-forget
    unawaited(catProvider.loadCachedCounts());
    unawaited(catProvider.fetchCategories());
    _fetchUnreadCounts(user, catProvider);

    if (user.role == UserRole.student && user.dbId != null) {
      if (mounted) {
        unawaited(
          Provider.of<RequestProvider>(context, listen: false)
              .fetchRequests(user.dbId!),
        );
      }
    }

    if (initialUser.role == UserRole.admin || user.role == UserRole.admin) {
      if (mounted) {
        unawaited(
          Provider.of<HierarchicalHostelProvider>(context, listen: false)
              .loadHostels(),
        );
        unawaited(
          Provider.of<MappingProvider>(context, listen: false).loadMappings(),
        );
      }
    }

    NotificationService.fcmRefreshNotifier.addListener(_onFCMCountRefresh);

    _countTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        final currentUser = Provider.of<UserProvider>(context, listen: false);
        final currentCatProvider =
            Provider.of<CategoryProvider>(context, listen: false);
        _fetchUnreadCounts(currentUser, currentCatProvider);
      }
    });
  }

  void _onFCMCountRefresh() {
    if (mounted) {
      final currentUser = Provider.of<UserProvider>(context, listen: false);
      final currentCatProvider =
          Provider.of<CategoryProvider>(context, listen: false);
      _fetchUnreadCounts(currentUser, currentCatProvider, force: true);
    }
  }

  void _fetchUnreadCounts(UserProvider user, CategoryProvider catProvider, {bool force = false}) {
    if (user.role == UserRole.warden ||
        user.role == UserRole.admin ||
        user.role == UserRole.security ||
        user.role == UserRole.maintenance ||
        user.role == UserRole.staff) {
      catProvider.fetchCounts(wardenUsername: user.username, force: force);
    } else if (user.role == UserRole.student) {
      catProvider.fetchCounts(studentUsername: user.username, force: force);
    } else if (user.isParent) {
      catProvider.fetchCounts(studentUsername: user.username, force: force);
    } else {
      catProvider.fetchCounts(force: force);
    }
  }

  @override
  void dispose() {
    NotificationService.fcmRefreshNotifier.removeListener(_onFCMCountRefresh);
    _pageController.dispose();
    _countTimer?.cancel();
    if (kIsWeb) {
      HistoryHelper.removePopStateListener();
    }
    super.dispose();
  }

  UserRole? _loadedRole;
  Future<void>? _roleLoaderFuture;

  Future<void> _ensureRoleLibraryLoaded(UserRole role) async {
    switch (role) {
      case UserRole.student:
      case UserRole.guest:
      case UserRole.parent:
        await student_routes.loadLibrary();
        break;
      case UserRole.warden:
        await warden_routes.loadLibrary();
        break;
      case UserRole.admin:
        await admin_routes.loadLibrary();
        break;
      case UserRole.maintenance:
      case UserRole.staff:
        await maintenance_routes.loadLibrary();
        break;
      case UserRole.security:
        await security_routes.loadLibrary();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final ui = context.watch<UIProvider>();
    final wallpaper = context.watch<WallpaperProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    if (_loadedRole != user.role || _roleLoaderFuture == null) {
      _loadedRole = user.role;
      _roleLoaderFuture = _ensureRoleLibraryLoaded(user.role);
    }

    return FutureBuilder<void>(
      future: _roleLoaderFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F1520),
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
              ),
            ),
          );
        }

        final tabs = _getTabsForRole(user);

        if (_selectedIndex >= tabs.length) {
          _selectedIndex = 0;
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            await _handleBackPress();
          },
          child: SafeArea(
            top: false,
            bottom: false,
            child: Scaffold(
              extendBody: !isDesktop,
              backgroundColor: isDesktop ? Colors.black : const Color(0xFFE8E4DB),
              body: Container(
                decoration: isDesktop
                    ? BoxDecoration(
                        gradient: wallpaper.ambientBackgroundGradient,
                      )
                    : null,
                child: isDesktop
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    _buildSidebar(context, user, tabs, wallpaper),
                                    const SizedBox(width: 16),
                                    _buildMainContentCard(isDesktop, tabs, wallpaper, user),
                                    if (ui.activeChatChannel != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 12),
                                        child: _buildChatSidePanel(context, ui, user.role, wallpaper),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : LinenGridBackground(
                        child: _buildMainContentCard(isDesktop, tabs, wallpaper, user),
                      ),
              ),
              bottomNavigationBar:
                  (!isDesktop && ui.showBottomNavBar) ? _buildBottomNavigationBar(tabs) : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildContentView(bool isDesktop, List<_TabItem> tabs) {
    if (isDesktop) {
      return IndexedStack(
        index: _selectedIndex >= tabs.length ? 0 : _selectedIndex,
        children: tabs.map((t) => t.page).toList(),
      );
    }
    return PageView(
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
      onPageChanged: (index) {
        if (_selectedIndex != index) {
          setState(() {
            _selectedIndex = index;
            if (index < tabs.length && tabs[index].label != 'Reports') {
              reportsCategoryFilter = null;
            }
          });
        }
      },
      children: tabs.map((t) => t.page).toList(),
    );
  }

  Widget _buildRoleSwitchButton(BuildContext context, UserProvider user, {bool isSidebar = false}) {
    if (!user.hasMultipleRoles) return const SizedBox.shrink();

    final isWarden = user.role == UserRole.warden;
    final roleIcon = isWarden ? Icons.shield_rounded : Icons.build_rounded;
    final roleLabel = isWarden ? 'Warden' : 'Maintenance';
    final badgeColor = isWarden ? const Color(0xFFD4AF37) : const Color(0xFF38BDF8);

    if (isSidebar) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: InkWell(
          onTap: () => _showRoleSwitchModal(context, user),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: badgeColor.withOpacity(0.4), width: 1.2),
            ),
            child: Row(
              children: [
                Icon(roleIcon, size: 14, color: badgeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    roleLabel.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontFamily: 'Lato',
                    ),
                  ),
                ),
                Icon(Icons.swap_horiz_rounded, size: 15, color: badgeColor),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showRoleSwitchModal(context, user),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: badgeColor.withOpacity(0.7), width: 1.3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(roleIcon, size: 14, color: badgeColor),
              const SizedBox(width: 6),
              Text(
                roleLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  fontFamily: 'Lato',
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.swap_horiz_rounded, size: 14, color: badgeColor),
            ],
          ),
        ),
      ),
    );
  }

  void _showRoleSwitchModal(BuildContext context, UserProvider user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 25,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD4AF37).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFFD4AF37), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Switch Active Profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF1B2B48),
                            fontFamily: 'Lato',
                          ),
                        ),
                        Text(
                          'Select which dashboard to view',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.grey.shade600,
                            fontFamily: 'Lato',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ...user.availableRoles.map((r) {
                  final isSelected = user.role == r;
                  final isWarden = r == UserRole.warden;
                  final roleTitle = isWarden
                      ? 'Hostel Warden'
                      : (r == UserRole.maintenance ? 'Maintenance Staff' : r.name.toUpperCase());
                  final roleSubtitle = isWarden
                      ? (user.hostelName.isNotEmpty
                          ? '${user.hostelName} (Attendance & Rooms)'
                          : 'Attendance, Rooms & Gate Pass')
                      : 'Work Orders, Tickets & QR Scanner';
                  final roleColor = isWarden ? const Color(0xFFD4AF37) : const Color(0xFF38BDF8);
                  final roleIcon = isWarden
                      ? Icons.shield_rounded
                      : (r == UserRole.maintenance ? Icons.build_rounded : Icons.person_rounded);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        if (!isSelected) {
                          user.switchActiveRole(r);
                          setState(() {
                            _selectedIndex = 0;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Switched to $roleTitle Profile'),
                              backgroundColor: roleColor,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? roleColor.withOpacity(0.12)
                              : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected ? roleColor : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: roleColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(roleIcon, color: roleColor, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    roleTitle,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                      fontFamily: 'Lato',
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    roleSubtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                                      fontFamily: 'Lato',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle_rounded, color: roleColor, size: 22)
                            else
                              Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey.shade400, size: 16),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainContentCard(bool isDesktop, List<_TabItem> tabs, WallpaperProvider wallpaper, UserProvider user) {
    final frameColor = wallpaper.sidebarColor;

    final navigatorWidget = PopScope(
      canPop: !(_phoneNavigatorKey.currentState?.canPop() ?? false),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_phoneNavigatorKey.currentState?.canPop() ?? false) {
          _phoneNavigatorKey.currentState!.pop();
        }
      },
      child: Navigator(
        key: _phoneNavigatorKey,
        observers: [_navigatorObserver],
        onGenerateRoute: (settings) {
          WidgetBuilder builder;
          final adminWidget = (user.role == UserRole.admin)
              ? admin_routes.buildAdminSubRoute(settings)
              : null;
          if (adminWidget != null) {
            builder = (context) => adminWidget;
          } else {
            builder = (context) => _buildContentView(isDesktop, tabs);
          }
          return PageRouteBuilder(
            settings: settings,
            opaque: true,
            pageBuilder: (context, animation, secondaryAnimation) => builder(context),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                ),
                child: child,
              );
            },
          );
        },
      ),
    );

    if (!isDesktop) {
      if (user.hasMultipleRoles) {
        return Stack(
          children: [
            navigatorWidget,
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 14,
              child: _buildRoleSwitchButton(context, user),
            ),
          ],
        );
      }
      return navigatorWidget;
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(color: frameColor, width: 4),
          color: frameColor,
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.55), blurRadius: 40, offset: const Offset(0, 20)),
            BoxShadow(
                color: Colors.black.withOpacity(0.38), blurRadius: 15, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: LinenGridBackground(
            child: user.hasMultipleRoles
                ? Stack(
                    children: [
                      navigatorWidget,
                      Positioned(
                        top: 14,
                        right: 14,
                        child: _buildRoleSwitchButton(context, user),
                      ),
                    ],
                  )
                : navigatorWidget,
          ),
        ),
      ),
    );
  }

  Widget _buildChatSidePanel(
      BuildContext context, UIProvider ui, UserRole role, WallpaperProvider wallpaper) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dynamicWidth = (screenWidth - 220 - 390 - 44).clamp(300.0, 400.0);
    final isDark = wallpaper.isDarkTheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        width: dynamicWidth,
        margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF131D2E).withOpacity(0.92)
              : const Color(0xFFF9F6F1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.14)
                : const Color(0xFFD4AF37).withOpacity(0.3),
          ),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45,
                blurRadius: 15,
                offset: Offset(0, 5))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Navigator(
          onGenerateRoute: (settings) => MaterialPageRoute(
            builder: (context) => Stack(
              children: [
                _getChatWidget(ui.activeChatChannel!, role),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _getChatWidget(String channel, UserRole role) {
    if (role == UserRole.warden ||
        role == UserRole.admin ||
        role == UserRole.security ||
        role == UserRole.maintenance ||
        role == UserRole.staff) {
      return warden_routes.getWardenChatWidget(channel);
    }

    final user = Provider.of<UserProvider>(context, listen: false);

    AppLogger.info(
        "Chat: $channel, Role: $role, User: ${user.username}, Request: ${widget.initialRequestId}");

    return student_routes.getStudentChatWidget(
        channel, user.isParent, widget.initialRequestId);
  }

  Widget _buildSidebar(
      BuildContext context, UserProvider user, List<_TabItem> tabs, WallpaperProvider wallpaper) {
    IconData roleIcon;
    String roleLabel;
    switch (user.role) {
      case UserRole.student:
        roleIcon = Icons.school_outlined;
        roleLabel = 'Student Portal';
        break;
      case UserRole.guest:
        roleIcon = Icons.card_travel_outlined;
        roleLabel = 'Temporary Stay';
        break;
      case UserRole.parent:
        roleIcon = Icons.family_restroom_outlined;
        roleLabel = 'Parent Portal';
        break;
      case UserRole.warden:
        roleIcon = Icons.shield_outlined;
        roleLabel = 'Warden Portal';
        break;
      case UserRole.admin:
        roleIcon = Icons.admin_panel_settings_outlined;
        roleLabel = 'Admin Portal';
        break;
      case UserRole.maintenance:
        roleIcon = Icons.build_outlined;
        roleLabel = 'Maintenance Portal';
        break;
      case UserRole.security:
        roleIcon = Icons.security_outlined;
        roleLabel = 'Security Portal';
        break;
      case UserRole.staff:
        roleIcon = Icons.engineering_outlined;
        roleLabel = '${user.roleName} Portal';
        break;
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        width: 220,
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: wallpaper.sidebarColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
          ),
          border: Border(
            left: BorderSide(color: wallpaper.sidebarBorderColor),
            top: BorderSide(color: wallpaper.sidebarBorderColor),
            bottom: BorderSide(color: wallpaper.sidebarBorderColor),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 36),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                            child: ClipOval(
                              child: Padding(
                                padding: const EdgeInsets.all(3.0),
                                child: Image.asset(
                                  'assets/images/favicon.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => const Center(
                                    child: Text('VS',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1B2B48),
                                            fontFamily: 'Lato')),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Viana',
                                  style: TextStyle(
                                      fontFamily: 'Lato',
                                      fontSize: 13,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2)),
                              Text('Stay',
                                  style: TextStyle(
                                      fontFamily: 'Lato',
                                      fontSize: 13,
                                      color: Color(0xFFD4AF37),
                                      fontWeight: FontWeight.bold,
                                      height: 1.2)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (user.hasMultipleRoles)
                      _buildRoleSwitchButton(context, user, isSidebar: true)
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            Icon(roleIcon,
                                size: 13, color: const Color(0xFF7A8BA0)),
                            const SizedBox(width: 6),
                            Text(
                              roleLabel.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF7A8BA0),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                                fontFamily: 'Lato',
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                    ...List.generate(tabs.length, (index) {
                      final t = tabs[index];
                      final active = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 1),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            if (_phoneNavigatorKey.currentState != null) {
                              _phoneNavigatorKey.currentState!
                                  .popUntil((route) => route.isFirst);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.white.withOpacity(0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: active
                                  ? Border.all(
                                      color: const Color(0xFFD4AF37)
                                          .withOpacity(0.5),
                                      width: 1)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  active ? t.activeIcon : t.icon,
                                  color: active
                                      ? const Color(0xFFD4AF37)
                                      : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  t.label,
                                  style: TextStyle(
                                    color:
                                        active ? Colors.white : Colors.white54,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    fontSize: 14,
                                    fontFamily: 'Lato',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
              child: InkWell(
                onTap: () async {
                  final userProvider =
                      Provider.of<UserProvider>(context, listen: false);
                  if (context.mounted) {
                    context.read<AllocationProvider>().reset();
                    context.read<UIProvider>().setActiveChatChannel(null);
                  }
                  await userProvider.logout();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.18)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.exit_to_app,
                          color: Colors.redAccent, size: 18),
                      SizedBox(width: 12),
                      Text('Logout',
                          style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Lato')),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(List<_TabItem> tabs) {
    return GlassmorphicJellyNavbar(
      currentIndex: _selectedIndex >= tabs.length ? 0 : _selectedIndex,
      totalTabs: tabs.length,
      tabs: tabs
          .map((t) => GlassmorphicTabItem(
                label: t.label,
                icon: t.icon,
                activeIcon: t.activeIcon,
              ))
          .toList(),
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
          if (tabs[index].label != 'Reports') {
            reportsCategoryFilter = null;
          }
        });
        if (_pageController.hasClients && _pageController.page?.round() != index) {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 180),
            curve: Curves.fastOutSlowIn,
          );
        }
        if (_phoneNavigatorKey.currentState != null) {
          _phoneNavigatorKey.currentState!.popUntil((route) => route.isFirst);
        }
      },
    );
  }

  List<_TabItem> _getTabsForRole(UserProvider user) {
    switch (user.role) {
      case UserRole.student:
        return student_routes.getStudentTabs(user).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
      case UserRole.guest:
        return student_routes.getGuestTabs(user).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
      case UserRole.parent:
        return student_routes.getParentTabs(user).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
      case UserRole.warden:
        return warden_routes.getWardenTabs(user, reportsCategoryFilter: reportsCategoryFilter).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
      case UserRole.admin:
        return admin_routes.getAdminTabs(user).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
      case UserRole.maintenance:
      case UserRole.staff:
        return maintenance_routes.getMaintenanceTabs(user, reportsCategoryFilter: reportsCategoryFilter).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
      case UserRole.security:
        return security_routes.getSecurityTabs(user, reportsCategoryFilter: reportsCategoryFilter).map((t) => _TabItem(
              label: t.label,
              icon: t.icon,
              activeIcon: t.activeIcon,
              page: t.page,
            )).toList();
    }
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;
  const _TabItem(
      {required this.label,
      required this.icon,
      required this.activeIcon,
      required this.page});
}

class _NestedNavigatorObserver extends NavigatorObserver {
  final VoidCallback onStackChanged;

  _NestedNavigatorObserver({required this.onStackChanged});

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    debugPrint(
        'NestedObserver: didPush | route=${route.settings.name} | previous=${previousRoute?.settings.name} | canPop=${navigator?.canPop()}');
    if (kIsWeb && route.settings.name != null && route.settings.name != '/') {
      HistoryHelper.pushState();
    }
    onStackChanged();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    debugPrint(
        'NestedObserver: didPop | route=${route.settings.name} | previous=${previousRoute?.settings.name} | canPop=${navigator?.canPop()}');
    onStackChanged();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    super.didRemove(route, previousRoute);
    debugPrint(
        'NestedObserver: didRemove | route=${route.settings.name} | previous=${previousRoute?.settings.name} | canPop=${navigator?.canPop()}');
    onStackChanged();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    debugPrint(
        'NestedObserver: didReplace | newRoute=${newRoute?.settings.name} | oldRoute=${oldRoute?.settings.name} | canPop=${navigator?.canPop()}');
    onStackChanged();
  }
}
