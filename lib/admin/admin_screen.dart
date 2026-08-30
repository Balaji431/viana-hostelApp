import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../core/styles.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/notification_service.dart';
import '../core/api_service.dart';
import '../shared/category_provider.dart';
import '../shared/wallpaper_provider.dart';
import 'staff_mapping_manager_screen.dart';
import 'screens/admin_hostel_manager_screen.dart';
import 'screens/hostel_detail_screen.dart';
import 'screens/category_manager_screen.dart';
import 'screens/room_master_screen.dart';
import 'screens/temporary_stay_admin_screen.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';
import '../shared/user_provider.dart';
import '../shared/main_layout.dart';
import 'package:intl/intl.dart';
import '../warden/widgets/warden_modals.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _roomCount = 2932;
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
      NotificationService.fcmRefreshNotifier.addListener(_onNotificationReceived);
    });
    _lastRefreshTick = context.read<UserProvider>().dashboardRefreshTick;
    context.read<UserProvider>().addListener(_handleGlobalRefreshListener);
  }

  int _lastRefreshTick = 0;

  void _handleGlobalRefreshListener() {
    if (!mounted) return;
    final user = context.read<UserProvider>();
    if (user.dashboardRefreshTick > _lastRefreshTick) {
      _lastRefreshTick = user.dashboardRefreshTick;
      _refreshData();
    }
  }

  @override
  void dispose() {
    context.read<UserProvider>().removeListener(_handleGlobalRefreshListener);
    NotificationService.fcmRefreshNotifier.removeListener(_onNotificationReceived);
    super.dispose();
  }

  void _onNotificationReceived() {
    if (mounted) {
      _refreshData();
    }
  }

  Future<void> _refreshData() async {
    try {
      final user = context.read<UserProvider>();
      await Future.wait([
        context.read<CategoryProvider>().fetchCategories(),
        context.read<HierarchicalHostelProvider>().loadHostels(),
        context.read<MappingProvider>().loadMappings(),
        context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username),
        _fetchRoomCount(),
        _fetchAnnouncements(),
      ]);
    } catch (e) {
      debugPrint('Error refreshing admin data: $e');
    }
  }

  Future<void> _fetchAnnouncements() async {
    try {
      final response = await ApiService.getAnnouncements();
      if (response['status'] == 'success' && response['data'] != null) {
        if (mounted) {
          setState(() {
            _announcements = List<Map<String, dynamic>>.from(response['data']);
            _isLoadingAnnouncements = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingAnnouncements = false);
      }
    } catch (e) {
      debugPrint('Error fetching announcements: $e');
      if (mounted) setState(() => _isLoadingAnnouncements = false);
    }
  }

  Future<void> _fetchRoomCount() async {
    try {
      final response = await ApiService.getRequest('rooms/fetch_room_master.php?page=1&limit=1&t=${DateTime.now().millisecondsSinceEpoch}');
      if (response['status'] == 'success' || response['success'] == true) {
        final total = int.tryParse(response['total']?.toString() ?? '2932') ?? 2932;
        if (mounted) {
          setState(() {
            _roomCount = total;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching room count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: 'Admin Dashboard',
          onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
          rightAction: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: _refreshData,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
              const SizedBox(width: 8),
              ProfileButton(
                onTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(4),
              ),
            ],
          ),
        ),
        body: _buildLaunchpad(isDark),
      ),
    );
  }

  Widget _buildLaunchpad(bool isDark) {
    final catProvider = context.watch<CategoryProvider>();
    final hostelProvider = context.watch<HierarchicalHostelProvider>();
    final mappingProvider = context.watch<MappingProvider>();
    
    final categoryCount = catProvider.categories.length;
    final hostelCount = hostelProvider.hostels.length;
    final mappingCount = mappingProvider.mappings.length;

    final isDesktop = kIsWeb
        ? MediaQuery.of(context).size.width >= 1024
        : (defaultTargetPlatform == TargetPlatform.windows ||
           defaultTargetPlatform == TargetPlatform.macOS ||
           defaultTargetPlatform == TargetPlatform.linux);

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            children: [
              _buildManagerCard(
                title: 'Category Management',
                subtitle: 'Manage room types & categories',
                icon: Icons.layers_rounded,
                accentColor: const Color(0xFFB08900),
                iconBg: const Color(0xFFB08900),
                count: categoryCount,
                isDark: isDark,
                onTap: () => Navigator.of(context).push(
                  InstantPageRoute(
                    settings: const RouteSettings(name: '/category_manager'),
                    builder: (_) => const CategoryManagerScreen(showAppBar: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildManagerCard(
                title: 'Hostel Management',
                subtitle: 'Manage hostels, floors & wings',
                icon: Icons.business_rounded,
                accentColor: const Color(0xFF2A4A8C),
                iconBg: const Color(0xFF2A4A8C),
                count: hostelCount,
                isDark: isDark,
                onTap: () => Navigator.of(context).push(
                  InstantPageRoute(
                    settings: const RouteSettings(name: '/hostel_manager'),
                    builder: (_) => AdminHostelManagerScreen(
                      showAppBar: true,
                      onHostelSelected: (hostel) => Navigator.of(context).push(
                        InstantPageRoute(
                          settings: const RouteSettings(name: '/hostel_detail'),
                          builder: (_) => HostelDetailScreen(hostel: hostel),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildManagerCard(
                title: 'Mapping Management',
                subtitle: 'Map staff & student allocations',
                icon: Icons.map_rounded,
                accentColor: const Color(0xFF7B3FC4),
                iconBg: const Color(0xFF7B3FC4),
                count: mappingCount,
                isDark: isDark,
                onTap: () => Navigator.of(context).push(
                  InstantPageRoute(
                    settings: const RouteSettings(name: '/mapping_manager'),
                    builder: (_) => const StaffMappingManagerScreen(showAppBar: true),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildManagerCard(
                title: 'Room Master',
                subtitle: isDesktop ? 'Manage room inventory & setups' : 'Desktop Only',
                icon: Icons.bed_rounded,
                accentColor: const Color(0xFF2E7D32),
                iconBg: const Color(0xFF2E7D32),
                count: _roomCount,
                isWarningSubtitle: !isDesktop,
                isDark: isDark,
                onTap: () {
                  if (!isDesktop) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Access Restricted'),
                        content: const Text(
                          'Room Master is available only on Desktop/Laptop.\n\nPlease use a desktop browser to access this feature.'
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    return;
                  }
                  // BREAK OUT of the mobile container by pushing to root navigator
                  Navigator.of(context, rootNavigator: true).push(
                    InstantPageRoute(
                      settings: const RouteSettings(name: '/room_master'),
                      builder: (context) => const RoomMasterScreen(),
                    ),
                  );
                },
              ),
              if (context.watch<UserProvider>().username != 'admin1')
                _buildAnnouncementsSection(context, isDark),
              const SizedBox(height: 100),
            ],
          ),
        ),
      );
  }

  Widget _buildManagerCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required Color iconBg,
    required int count,
    required VoidCallback onTap,
    String? subtitle,
    bool isWarningSubtitle = false,
    bool isDark = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : null,
        gradient: isDark ? null : const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFFAF7F2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE2DACC),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
          if (!isDark)
            BoxShadow(
              color: Colors.white.withOpacity(0.9),
              blurRadius: 2,
              offset: const Offset(0, -1),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Avatar Box on Left
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: iconBg.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A2744),
                          fontFamily: 'Lato',
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: isWarningSubtitle ? Colors.redAccent : (isDark ? Colors.white60 : Colors.grey.shade600),
                            fontWeight: isWarningSubtitle ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (count > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2196F3).withOpacity(0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white60 : const Color(0xFF8E8276),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementsSection(BuildContext context, bool isDark) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Color(0xFFB08900), size: 18),
                const SizedBox(width: 8),
                Text(
                  'ANNOUNCEMENTS', 
                  style: TextStyle(
                    fontSize: 11, 
                    color: isDark ? const Color(0xFFD4AF37) : Colors.grey, 
                    fontWeight: FontWeight.bold, 
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFFB08900), size: 28), 
              onPressed: () => showDialog(
                context: context,
                builder: (context) => NewAnnouncementModal(
                  onPost: (title, content) async {
                    final user = context.read<UserProvider>();
                    final response = await ApiService.postAnnouncement(title, content, username: user.username);
                    if (response['status'] == 'success') {
                      _fetchAnnouncements();
                    }
                  }
                )
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_isLoadingAnnouncements)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20), 
              child: CircularProgressIndicator(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)),
            ),
          )
        else if (_announcements.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20), 
              child: Text("No announcements yet", style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
            ),
          )
        else
          ..._announcements.map((a) => _buildAnnouncementItem(a, isDark)),
      ],
    );
  }

  Widget _buildAnnouncementItem(Map<String, dynamic> announcement, bool isDark) {
    String dateStr = announcement['date'] ?? DateTime.now().toString();
    DateTime? date;
    try {
      date = DateTime.parse(dateStr);
    } catch (e) {
      date = DateTime.now();
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFB08900), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        announcement['title'] ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A2744),
                          fontFamily: 'Lato',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                DateFormat('dd MMM yyyy').format(date),
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey, fontFamily: 'Lato'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement['content'] ?? '',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.blueGrey, fontFamily: 'Lato'),
          ),
        ],
      ),
    );
  }
}

class InstantPageRoute<T> extends PageRouteBuilder<T> {
  final WidgetBuilder builder;

  InstantPageRoute({
    required this.builder,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
}
