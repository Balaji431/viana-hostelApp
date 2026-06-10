import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/app_logger.dart';
import '../core/styles.dart';
import 'user_provider.dart';
import 'request_provider.dart';
import 'ui_provider.dart';
import 'category_provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import '../student/screens/home_screen.dart';
import '../student/screens/attendance_page.dart';
import '../student/screens/settings_page.dart';
import '../warden/screens/warden_home_tab.dart';
import '../warden/screens/warden_attendance_tab.dart';
import '../warden/screens/warden_reports_tab.dart';
import '../warden/screens/warden_management_tab.dart';
import '../admin/admin_screen.dart';
import '../admin/screens/admin_activity_logs_screen.dart';
import '../student/screens/warden_chat_screen.dart';
import '../student/screens/security_chat_screen.dart';
import '../student/screens/maintenance_chat_screen.dart';
import '../student/screens/parent_warden_chat_screen.dart';
import '../warden/screens/warden_chat_interface.dart';
import '../maintenance/screens/maintenance_home_tab.dart';
import '../maintenance/screens/maintenance_attendance_tab.dart';
import '../maintenance/screens/maintenance_settings_tab.dart';
import '../security/screens/security_home_tab.dart';
import '../admin/screens/category_manager_screen.dart';
import '../admin/screens/admin_hostel_manager_screen.dart';
import '../admin/staff_mapping_manager_screen.dart';
import '../admin/screens/hostel_detail_screen.dart';
import '../core/models/hierarchical_hostel_model.dart';


class MainResponsiveLayout extends StatefulWidget {
  final String? initialRequestId;
  final String? senderId;
  final bool isSecurity;
  final bool showAnnouncements;
  final String? initialRoute;
  final Object? initialRouteArgs;
  
  const MainResponsiveLayout({
    this.initialRequestId, 
    this.senderId, 
    this.isSecurity = false, 
    this.showAnnouncements = false, 
    this.initialRoute,
    this.initialRouteArgs,
    super.key
  });

  @override
  State<MainResponsiveLayout> createState() => MainResponsiveLayoutState();
}

class MainResponsiveLayoutState extends State<MainResponsiveLayout> {
  int _selectedIndex = 0;
  final GlobalKey<NavigatorState> _phoneNavigatorKey = GlobalKey<NavigatorState>();
  late final _NestedNavigatorObserver _navigatorObserver;

  void setSelectedIndex(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (_phoneNavigatorKey.currentState != null) {
      _phoneNavigatorKey.currentState!.popUntil((route) => route.isFirst);
    }
  }
  Timer? _countTimer;

  @override
  void initState() {
    super.initState();
    _navigatorObserver = _NestedNavigatorObserver(
      onStackChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserProvider>(context, listen: false);
      if (user.role == UserRole.student && user.dbId != null) {
        Provider.of<RequestProvider>(context, listen: false).fetchRequests(user.dbId!);
      }

      final catProvider = Provider.of<CategoryProvider>(context, listen: false);
      // Load cached counts instantly so badges show with zero delay
      catProvider.loadCachedCounts();
      catProvider.fetchCategories();
      
      _fetchUnreadCounts(user, catProvider);

      // Periodic timer to fetch unread counts every 15 seconds in the background
      _countTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted) {
          final currentUser = Provider.of<UserProvider>(context, listen: false);
          final currentCatProvider = Provider.of<CategoryProvider>(context, listen: false);
          _fetchUnreadCounts(currentUser, currentCatProvider);
        }
      });
      
      if (user.role == UserRole.admin) {
        Provider.of<HierarchicalHostelProvider>(context, listen: false).loadHostels();
        Provider.of<MappingProvider>(context, listen: false).loadMappings();
      }
      
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

      if (widget.initialRoute != null) {
        _phoneNavigatorKey.currentState?.pushNamed(
          widget.initialRoute!,
          arguments: widget.initialRouteArgs,
        );
      }
    });
  }

  void _fetchUnreadCounts(UserProvider user, CategoryProvider catProvider) {
    if (user.role == UserRole.warden || user.role == UserRole.admin || user.role == UserRole.security || user.role == UserRole.maintenance || user.role == UserRole.staff) {
      catProvider.fetchCounts(wardenUsername: user.username);
    } else if (user.role == UserRole.student) {
      catProvider.fetchCounts(studentUsername: user.username);
    } else if (user.isParent) {
      catProvider.fetchCounts(studentUsername: user.username);
    } else {
      catProvider.fetchCounts();
    }
  }

  @override
  void dispose() {
    _countTimer?.cancel();
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

    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: isDesktop ? const Color(0xFF0A1128) : const Color(0xFFE8E4DB),
        body: Container(
          decoration: isDesktop ? const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F1520),
                Color(0xFF1A2235),
                Color(0xFF0F1520),
              ],
            ),
          ) : null,
          child: isDesktop
            ? Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min, 
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildSidebar(context, user, tabs),
                    _buildMainContentCard(isDesktop, tabs),
                    if (ui.activeChatChannel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _buildChatSidePanel(context, ui, user.role),
                      ),
                  ],
                ),
              )
            : _buildMainContentCard(isDesktop, tabs),
        ),
        bottomNavigationBar: !isDesktop ? _buildBottomNavigationBar(tabs) : null,
      ),
    );
  }

  Widget _buildMainContentCard(bool isDesktop, List<_TabItem> tabs) {
    if (!isDesktop) {
      return IndexedStack(
        index: _selectedIndex,
        children: tabs.map((t) => t.page).toList(),
      );
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
            BoxShadow(color: Colors.black54, blurRadius: 40, offset: Offset(0, 20)),
            BoxShadow(color: Colors.black38, blurRadius: 15, offset: Offset(0, 6)),
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
                      builder = (context) => const CategoryManagerScreen(showAppBar: true);
                      break;
                    case '/hostel_manager':
                      builder = (context) => const AdminHostelManagerScreen(showAppBar: true);
                      break;
                    case '/mapping_manager':
                      builder = (context) => const StaffMappingManagerScreen(showAppBar: true);
                      break;
                    case '/hostel_detail':
                      final args = settings.arguments as HierarchicalHostel;
                      builder = (context) => HostelDetailScreen(hostel: args, showAppBar: true);
                      break;
                    default:
                      builder = (context) => IndexedStack(
                        index: _selectedIndex,
                        children: tabs.map((t) => t.page).toList(),
                      );
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

  Widget _buildChatSidePanel(BuildContext context, UIProvider ui, UserRole role) {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        width: 400,
        margin: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F6F1),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 15, offset: const Offset(0, 5))],
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
    if (role == UserRole.warden || role == UserRole.admin || role == UserRole.security || role == UserRole.maintenance || role == UserRole.staff) {
      return WardenChatInterface(channel: channel);
    }
    
    final user = Provider.of<UserProvider>(context, listen: false);
    
    AppLogger.info("Chat: $channel, Role: $role, User: ${user.username}, Request: ${widget.initialRequestId}");
    
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
          requestId: widget.initialRequestId,
          department: channel
        );
    }
  }

  Widget _buildSidebar(BuildContext context, UserProvider user, List<_TabItem> tabs) {
    IconData roleIcon;
    String roleLabel;
    switch (user.role) {
      case UserRole.student: roleIcon = Icons.school_outlined; roleLabel = 'Student Portal'; break;
      case UserRole.parent: roleIcon = Icons.family_restroom_outlined; roleLabel = 'Parent Portal'; break;
      case UserRole.warden: roleIcon = Icons.shield_outlined; roleLabel = 'Warden Portal'; break;
      case UserRole.admin: roleIcon = Icons.admin_panel_settings_outlined; roleLabel = 'Admin Portal'; break;
      case UserRole.maintenance: roleIcon = Icons.build_outlined; roleLabel = 'Maintenance Portal'; break;
      case UserRole.security: roleIcon = Icons.security_outlined; roleLabel = 'Security Portal'; break;
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
                            width: 52, height: 52,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFFE8D48A), Color(0xFFD4AF37), Color(0xFFB8962E)],
                              ),
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
                            ),
                            child: const Center(
                              child: Text('RR', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF3D2E0A), fontFamily: 'Georgia'))
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('Royal', style: TextStyle(fontFamily: 'Georgia', fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold, height: 1.2)),
                              Text('Residences', style: TextStyle(fontFamily: 'Georgia', fontSize: 13, color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, height: 1.2)),
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
                          Icon(roleIcon, size: 13, color: const Color(0xFF7A8BA0)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedIndex = index);
                            if (_phoneNavigatorKey.currentState != null) {
                              _phoneNavigatorKey.currentState!.popUntil((route) => route.isFirst);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: active ? Colors.white.withOpacity(0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: active ? Border.all(color: const Color(0xFFD4AF37).withOpacity(0.4), width: 1) : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  active ? t.activeIcon : t.icon,
                                  color: active ? const Color(0xFFD4AF37) : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  t.label,
                                  style: TextStyle(
                                    color: active ? Colors.white : Colors.white54,
                                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
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
                  final userProvider = Provider.of<UserProvider>(context, listen: false);
                  await userProvider.logout();
                  if (context.mounted) {
                    context.read<UIProvider>().setActiveChatChannel(null);
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.18)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.exit_to_app, color: Colors.redAccent, size: 18),
                      SizedBox(width: 12),
                      Text('Logout', style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Lato')),
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C2C2C), Color(0xFF1A1A1A)],
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex >= tabs.length ? 0 : _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (_phoneNavigatorKey.currentState != null) {
            _phoneNavigatorKey.currentState!.popUntil((route) => route.isFirst);
          }
        },
        backgroundColor: Colors.transparent,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFD4AF37),
        unselectedItemColor: Colors.grey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: tabs.map((t) => BottomNavigationBarItem(
          icon: Icon(t.icon),
          activeIcon: Icon(t.activeIcon, shadows: const [Shadow(color: Color(0xFFD4AF37), blurRadius: 8)]),
          label: t.label,
        )).toList(),
      ),
    );
  }

  List<_TabItem> _getTabsForRole(UserProvider user) {
    switch (user.role) {
      case UserRole.student:
        return [
          const _TabItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home, page: StudentHomeScreen()),
          const _TabItem(label: 'Attendance', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, page: AttendancePage()),
          const _TabItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: SettingsPage()),
        ];
      case UserRole.parent:
        return [
          const _TabItem(label: 'Dashboard', icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, page: StudentHomeScreen()),
          const _TabItem(label: 'Attendance', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, page: AttendancePage()),
          const _TabItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: SettingsPage()),
        ];
      case UserRole.warden:
        return [
          const _TabItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home, page: WardenHomeTab()),
          const _TabItem(label: 'Attendance', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, page: WardenAttendanceTab()),
          const _TabItem(label: 'Reports', icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, page: WardenReportsTab()),
          const _TabItem(label: 'Management', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: WardenManagementTab()),
          const _TabItem(label: 'Settings', icon: Icons.person_outline, activeIcon: Icons.person, page: SettingsPage()),
        ];
      case UserRole.admin:
        return [
          const _TabItem(label: 'New Admin', icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings, page: AdminScreen()),
          const _TabItem(label: 'Activity Logs', icon: Icons.assignment_outlined, activeIcon: Icons.assignment, page: AdminActivityLogsScreen()),
          const _TabItem(label: 'Management', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: WardenManagementTab()),
          const _TabItem(label: 'Settings', icon: Icons.person_outline, activeIcon: Icons.person, page: SettingsPage()),
        ];
      case UserRole.maintenance:
        return [
          const _TabItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home, page: MaintenanceHomeTab()),
          const _TabItem(label: 'Attendance', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, page: MaintenanceAttendanceTab()),
          const _TabItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: MaintenanceSettingsTab()),
        ];
      case UserRole.security:
        return [
          const _TabItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home, page: SecurityHomeTab()),
          const _TabItem(label: 'Attendance', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, page: MaintenanceAttendanceTab()),
          const _TabItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: MaintenanceSettingsTab()),
        ];
      case UserRole.staff:
        return [
          const _TabItem(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home, page: MaintenanceHomeTab()),
          const _TabItem(label: 'Attendance', icon: Icons.calendar_month_outlined, activeIcon: Icons.calendar_month, page: MaintenanceAttendanceTab()),
          const _TabItem(label: 'Settings', icon: Icons.settings_outlined, activeIcon: Icons.settings, page: MaintenanceSettingsTab()),
        ];
    }
  }
}

class _TabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;
  const _TabItem({required this.label, required this.icon, required this.activeIcon, required this.page});
}

class _NestedNavigatorObserver extends NavigatorObserver {
  final VoidCallback onStackChanged;

  _NestedNavigatorObserver({required this.onStackChanged});

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name != null) {
      SystemNavigator.routeInformationUpdated(
        location: route.settings.name!,
      );
    }
    onStackChanged();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null && previousRoute.settings.name != null) {
      SystemNavigator.routeInformationUpdated(
        location: previousRoute.settings.name!,
      );
    } else {
      SystemNavigator.routeInformationUpdated(
        location: '/',
      );
    }
    onStackChanged();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    super.didRemove(route, previousRoute);
    onStackChanged();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null && newRoute.settings.name != null) {
      SystemNavigator.routeInformationUpdated(
        location: newRoute.settings.name!,
      );
    }
    onStackChanged();
  }
}
