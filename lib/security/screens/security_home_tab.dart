import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/ui_provider.dart';
import '../../shared/category_provider.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../warden/screens/warden_chat_interface.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/main_layout.dart';
 
class SecurityHomeTab extends StatefulWidget {
  const SecurityHomeTab({super.key});

  @override
  State<SecurityHomeTab> createState() => _SecurityHomeTabState();
}

class _SecurityHomeTabState extends State<SecurityHomeTab> {
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final user = context.read<UserProvider>();
        context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username);
      }
    });
    // Set up periodic refresh every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        final user = context.read<UserProvider>();
        context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username);
      }
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
      _handleGlobalRefresh();
    }
  }

  void _handleGlobalRefresh() {
    _fetchAnnouncements();
    if (mounted) {
      final user = context.read<UserProvider>();
      context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username);
    }
  }

  @override
  void dispose() {
    context.read<UserProvider>().removeListener(_handleGlobalRefreshListener);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAnnouncements() async {
    final response = await ApiService.getAnnouncements();
    if (response['status'] == 'success') {
      if (mounted) {
        setState(() {
          _announcements = List<Map<String, dynamic>>.from(response['data']);
          _isLoadingAnnouncements = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingAnnouncements = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Security Dashboard',
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        rightAction: ProfileButton(
          onTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(2),
        ),
      ),
      body: LinenBackground(
        child: RefreshIndicator(
          onRefresh: () async {
            await _fetchAnnouncements();
            if (mounted) {
              final user = context.read<UserProvider>();
              await context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username);
            }
          },
          color: const Color(0xFFC5A358),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderSection(user),
                    const SizedBox(height: 25),
                    _buildQuickActionsHeader(),
                    _buildQuickActions(context),
                    _buildAnnouncementsSection(context),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}



  Widget _buildHeaderSection(UserProvider user) {
    String displayName = user.userName.isEmpty ? 'Security Staff' : user.userName;
    String displayId = user.username.isEmpty ? 'ID: Security' : 'ID: ${user.username}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 30),
      decoration: const BoxDecoration(
        gradient: SkeuomorphicColors.royalContentGradient,
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SkeuomorphicColors.goldGlossyGradient,
              boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 5, offset: Offset(0, 3))],
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S', 
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1a2744))
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: SkeuomorphicStyles.playfairHeader.copyWith(color: Colors.white, fontSize: 20)),
                Text(displayId, style: SkeuomorphicStyles.latoBody.copyWith(color: const Color(0xFFA0B0C0), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 25),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5D5D5D),
          ),
        ),
      ),
    );
  }
  Widget _buildQuickActions(BuildContext context) {
    final catProvider = context.watch<CategoryProvider>();
    final List<Map<String, dynamic>> predefinedActions = [
      {
        'title': 'Security Chat', 
        'icon': Icons.security, 
        'color': const Color(0xFFEF5350), 
        'channel': 'security',
        'count': catProvider.getUnreadCount('security'),
      },
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
      child: Row(
        children: predefinedActions.map((action) {
          return Padding(
            padding: const EdgeInsets.only(right: 15),
            child: SizedBox(
              width: 110,
              child: _buildActionCard(
                context, 
                action['title'], 
                action['icon'], 
                action['color'],
                action['channel'],
                action['count'],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, String channel, int count) {
    bool isHover = false;
    return StatefulBuilder(
      builder: (context, setHover) {

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHover(() => isHover = true),
          onExit: (_) => setHover(() => isHover = false),
          child: GestureDetector(
            onTap: () {
              final isDesktop = MediaQuery.of(context).size.width >= 768;
              if (isDesktop) {
                context.read<UIProvider>().setActiveChatChannel(channel);
              } else {
                final user = Provider.of<UserProvider>(context, listen: false);
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => Scaffold(
                    backgroundColor: const Color(0xFFF9F6F1),
                    body: WardenChatInterface(channel: channel),
                  ),
                  settings: RouteSettings(name: '/chat_$channel'),
                )).then((_) {
                  if (context.mounted) {
                    context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username);
                  }
                });
              }
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  transform: Matrix4.identity()
                    ..translate(0.0, isHover ? -8.0 : 0.0)
                    ..scale(isHover ? 1.04 : 1.0),
                  width: 110,
                  height: 110,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isHover ? 0.18 : 0.08),
                        blurRadius: isHover ? 18 : 10,
                        offset: Offset(0, isHover ? 8 : 4),
                      ),
                    ],
                    border: Border.all(color: Colors.black.withOpacity(0.03)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1B2B48),
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    top: isHover ? -8.0 : -5.0,
                    right: isHover ? -8.0 : -5.0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF5350),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                      ),
                      child: Text(
                        count.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnnouncementsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.notifications_active, color: Color(0xFFD4AF37), size: 18),
                  SizedBox(width: 8),
                  Text('ANNOUNCEMENTS', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoadingAnnouncements)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
          else if (_announcements.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No announcements yet", style: TextStyle(color: Colors.grey))))
          else
            ..._announcements.map((a) => _buildAnnouncementItem(a)),
        ],
      ),
    );
  }

  Widget _buildAnnouncementItem(Map<String, dynamic> announcement) {
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
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFD4AF37), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(announcement['title'] ?? '', style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 14, color: SkeuomorphicColors.residenceNavy), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(DateFormat('dd MMM yyyy').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 8),
          Text(announcement['content'] ?? '', style: SkeuomorphicStyles.latoBody.copyWith(fontSize: 13, color: Colors.blueGrey)),
        ],
      ),
    );
  }
}
