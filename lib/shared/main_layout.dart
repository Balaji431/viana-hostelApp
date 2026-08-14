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
import '../core/notification_service.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/providers/allocation_provider.dart';
import '../student/screens/home_screen.dart';
import '../student/screens/attendance_page.dart' show AttendancePage, BiometricHistoryPage;
import '../student/screens/no_due_page.dart';
import '../student/screens/settings_page.dart';
import '../warden/screens/warden_home_tab.dart';
import '../warden/screens/warden_attendance_tab.dart';
import '../warden/screens/warden_reports_tab.dart';
import '../warden/screens/warden_management_tab.dart';
import '../warden/screens/warden_room_change_requests_screen.dart';
import '../warden/screens/warden_room_search_screen.dart';
import '../admin/admin_screen.dart';
import '../admin/screens/admin_activity_logs_screen.dart';
import '../admin/screens/temporary_stay_admin_screen.dart';
import '../student/screens/warden_chat_screen.dart';
import '../student/screens/security_chat_screen.dart';
import '../student/screens/maintenance_chat_screen.dart';
import '../student/screens/parent_warden_chat_screen.dart';
import '../warden/screens/warden_chat_interface.dart';
import '../maintenance/screens/maintenance_home_tab.dart';
import '../security/screens/security_home_tab.dart';
import '../admin/screens/category_manager_screen.dart';
import '../admin/screens/admin_hostel_manager_screen.dart';
import '../admin/staff_mapping_manager_screen.dart';
import '../admin/screens/hostel_detail_screen.dart';
import '../admin/screens/register_staff_screen.dart';
import '../core/models/hierarchical_hostel_model.dart';
import 'widgets/glassmorphic_jelly_navbar.dart';
import 'role_guard.dart';

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

    _countTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
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

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final ui = context.watch<UIProvider>();
    final isDesktop = MediaQuery.of(context).size.width >= 768;

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
          backgroundColor:
              isDesktop ? const Color(0xFF0A1128) : const Color(0xFFE8E4DB),
          body: Container(
            decoration: isDesktop
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F1520),
                        Color(0xFF1A2235),
                        Color(0xFF0F1520),
                      ],
                    ),
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
                                _buildSidebar(context, user, tabs),
                                const SizedBox(width: 16),
                                _buildMainContentCard(isDesktop, tabs),
                                if (ui.activeChatChannel != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: _buildChatSidePanel(context, ui, user.role),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  )
                : LinenGridBackground(
                    child: _buildMainContentCard(isDesktop, tabs),
                  ),
          ),
          bottomNavigationBar:
              (!isDesktop && ui.showBottomNavBar) ? _buildBottomNavigationBar(tabs) : null,
        ),
      ),
    );
  }

  Widget _buildContentView(bool isDesktop, List<_TabItem> tabs) {
    final bool useSwipeView = !isDesktop && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

    if (useSwipeView) {
      return PageView(
        controller: _pageController,
        scrollDirection: Axis.horizontal,
        physics: (_phoneNavigatorKey.currentState?.canPop() ?? false)
            ? const NeverScrollableScrollPhysics()
            : const PageScrollPhysics(parent: ClampingScrollPhysics()),
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

    return IndexedStack(
      index: _selectedIndex >= tabs.length ? 0 : _selectedIndex,
      children: tabs.map((t) => t.page).toList(),
    );
  }

  Widget _buildMainContentCard(bool isDesktop, List<_TabItem> tabs) {
    if (!isDesktop) {
      return _buildContentView(isDesktop, tabs);
    }

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        margin: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF0F1520), width: 4),
          color: const Color(0xFF0F1520),
          borderRadius: BorderRadius.circular(36),
          boxShadow: const [
            BoxShadow(
                color: Colors.black54, blurRadius: 40, offset: Offset(0, 20)),
            BoxShadow(
                color: Colors.black38, blurRadius: 15, offset: Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: LinenGridBackground(
            child: PopScope(
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
                  switch (settings.name) {
                    case '/category_manager':
                      builder = (context) => const RoleGuard(
                            allowedRoles: [UserRole.admin],
                            child: CategoryManagerScreen(showAppBar: true),
                          );
                      break;
                    case '/hostel_manager':
                      builder = (context) => const RoleGuard(
                            allowedRoles: [UserRole.admin],
                            child: AdminHostelManagerScreen(showAppBar: true),
                          );
                      break;
                    case '/mapping_manager':
                      builder = (context) => const RoleGuard(
                            allowedRoles: [UserRole.admin],
                            child: StaffMappingManagerScreen(showAppBar: true),
                          );
                      break;
                    case '/hostel_detail':
                      final args = settings.arguments as HierarchicalHostel;
                      builder = (context) => RoleGuard(
                            allowedRoles: const [UserRole.admin],
                            child: HostelDetailScreen(
                                hostel: args, showAppBar: true),
                          );
                      break;
                    default:
                      builder = (context) => _buildContentView(isDesktop, tabs);
                  }
                  return MaterialPageRoute(
                    builder: builder,
                    settings: settings,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatSidePanel(
      BuildContext context, UIProvider ui, UserRole role) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dynamicWidth = (screenWidth - 220 - 390 - 44).clamp(300.0, 400.0);

    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        width: dynamicWidth,
        margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F6F1),
          borderRadius: BorderRadius.circular(24),
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
      return WardenChatInterface(channel: channel);
    }

    final user = Provider.of<UserProvider>(context, listen: false);

    AppLogger.info(
        "Chat: $channel, Role: $role, User: ${user.username}, Request: ${widget.initialRequestId}");

    switch (channel.toLowerCase()) {
      case 'warden':
        AppLogger.info("Creating Warden ChatScreen");
        return user.isParent
            ? ParentWardenChatScreen(requestId: widget.initialRequestId)
            : WardenChatScreen(requestId: widget.initialRequestId);
      case 'security':
        AppLogger.info("Creating Security ChatScreen");
        return SecurityChatScreen(requestId: widget.initialRequestId);
      default:
        AppLogger.info("Creating Dynamic ChatScreen for $channel");
        return MaintenanceChatScreen(
            requestId: widget.initialRequestId, department: channel);
    }
  }

  Widget _buildSidebar(
      BuildContext context, UserProvider user, List<_TabItem> tabs) {
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
          color: const Color(0xFF141E2E),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            bottomLeft: Radius.circular(24),
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
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 2))
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/images/favicon.png',
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
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
                                  ? Colors.white.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: active
                                  ? Border.all(
                                      color: const Color(0xFFD4AF37)
                                          .withOpacity(0.4),
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
        return [
          const _TabItem(
              label: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              page: StudentHomeScreen()),
          const _TabItem(
              label: 'Attendance',
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month,
              page: AttendancePage()),
          const _TabItem(
              label: 'No Due',
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long,
              page: NoDuePage()),
          const _TabItem(
              label: 'Bio History',
              icon: Icons.fingerprint,
              activeIcon: Icons.fingerprint,
              page: BiometricHistoryPage()),
          const _TabItem(
              label: 'Settings',
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              page: SettingsPage()),
        ];
      case UserRole.guest:
        return [
          const _TabItem(
              label: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              page: StudentHomeScreen()),
          const _TabItem(
              label: 'Settings',
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              page: SettingsPage()),
        ];
      case UserRole.parent:
        return [
          const _TabItem(
              label: 'Dashboard',
              icon: Icons.dashboard_outlined,
              activeIcon: Icons.dashboard,
              page: StudentHomeScreen()),
          const _TabItem(
              label: 'Attendance',
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month,
              page: AttendancePage()),
          const _TabItem(
              label: 'Bio History',
              icon: Icons.fingerprint,
              activeIcon: Icons.fingerprint,
              page: BiometricHistoryPage()),
          const _TabItem(
              label: 'Settings',
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              page: SettingsPage()),
        ];
      case UserRole.warden:
        return [
          const _TabItem(
              label: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              page: WardenHomeTab()),
          const _TabItem(
              label: 'Attendance',
              icon: Icons.calendar_month_outlined,
              activeIcon: Icons.calendar_month,
              page: WardenAttendanceTab()),
          _TabItem(
              label: 'Transfer',
              icon: Icons.sync_outlined,
              activeIcon: Icons.sync,
              page: WardenRoomChangeRequestsScreen(wardenId: user.dbId ?? 1)),
          _TabItem(
              label: 'Reports',
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart,
              page: WardenReportsTab(initialCategory: reportsCategoryFilter)),
          const _TabItem(
              label: 'Management',
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              page: WardenManagementTab()),
          const _TabItem(
              label: 'Room Search',
              icon: Icons.search_outlined,
              activeIcon: Icons.search,
              page: WardenRoomSearchScreen()),
          const _TabItem(
              label: 'Settings',
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              page: SettingsPage()),
        ];
      case UserRole.admin:
        return [
          const _TabItem(
              label: 'Admin',
              icon: Icons.admin_panel_settings_outlined,
              activeIcon: Icons.admin_panel_settings,
              page: AdminScreen()),
          const _TabItem(
              label: 'Activity Logs',
              icon: Icons.assignment_outlined,
              activeIcon: Icons.assignment,
              page: AdminActivityLogsScreen()),
          const _TabItem(
              label: 'Temp Stay',
              icon: Icons.hotel_outlined,
              activeIcon: Icons.hotel,
              page: TemporaryStayAdminScreen()),
          const _TabItem(
              label: 'Management',
              icon: Icons.settings_outlined,
              activeIcon: Icons.settings,
              page: WardenManagementTab()),
          const _TabItem(
              label: 'Settings',
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              page: SettingsPage()),
        ];
      case UserRole.maintenance:
        return [
          const _TabItem(
              label: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              page: MaintenanceHomeTab()),
          _TabItem(
              label: 'Reports',
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart,
              page: WardenReportsTab(initialCategory: reportsCategoryFilter)),
          const _TabItem(
              label: 'Settings',
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              page: SettingsPage()),
        ];
      case UserRole.security:
        return [
          const _TabItem(
              label: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              page: SecurityHomeTab()),
          _TabItem(
              label: 'Reports',
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart,
              page: WardenReportsTab(initialCategory: reportsCategoryFilter)),
          const _TabItem(
              label: 'Settings',
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              page: SettingsPage()),
        ];
      case UserRole.staff:
        return [
          const _TabItem(
              label: 'Home',
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              page: MaintenanceHomeTab()),
          _TabItem(
              label: 'Reports',
              icon: Icons.bar_chart_outlined,
              activeIcon: Icons.bar_chart,
              page: WardenReportsTab(initialCategory: reportsCategoryFilter)),
          const _TabItem(
              label: 'Settings',
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              page: SettingsPage()),
        ];
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
