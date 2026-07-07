import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../core/styles.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/notification_service.dart';
import '../core/api_service.dart';
import '../shared/category_provider.dart';
import 'staff_mapping_manager_screen.dart';
import 'screens/admin_hostel_manager_screen.dart';
import 'screens/hostel_detail_screen.dart';
import 'screens/category_manager_screen.dart';
import 'screens/room_master_screen.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';
import '../shared/user_provider.dart';
import '../shared/main_layout.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _roomCount = 0;

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
      ]);
    } catch (e) {
      debugPrint('Error refreshing admin data: $e');
    }
  }

  Future<void> _fetchRoomCount() async {
    try {
      final response = await ApiService.getRequest('rooms/fetch_room_master.php?t=${DateTime.now().millisecondsSinceEpoch}');
      if (response['status'] == 'success' || response['success'] == true) {
        setState(() {
          _roomCount = (response['data'] as List?)?.length ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error fetching room count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
        body: _buildLaunchpad(),
      ),
    );
  }

  Widget _buildLaunchpad() {
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
                icon: Icons.layers_rounded,
                accentColor: const Color(0xFFB08900),
                iconBg: const Color(0xFFB08900),
                count: categoryCount,
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
                icon: Icons.business_rounded,
                accentColor: const Color(0xFF2A4A8C),
                iconBg: const Color(0xFF2A4A8C),
                count: hostelCount,
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
                icon: Icons.map_rounded,
                accentColor: const Color(0xFF7B3FC4),
                iconBg: const Color(0xFF7B3FC4),
                count: mappingCount,
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
                icon: Icons.bed_rounded,
                accentColor: const Color(0xFF2E7D32),
                iconBg: const Color(0xFF2E7D32),
                count: _roomCount,
                subtitle: isDesktop ? null : 'Desktop Only',
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                        fontFamily: 'Lato',
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 14),
                child: Icon(
                  Icons.keyboard_arrow_right_rounded,
                  color: Colors.grey.shade400,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
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
