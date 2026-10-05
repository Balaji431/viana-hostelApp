import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/ui_provider.dart';
import '../../shared/category_provider.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../warden/screens/warden_chat_interface.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/main_layout.dart';
import '../../shared/widgets/raise_issue_header_button.dart';
import '../../shared/widgets/user_avatar_header.dart';
 
class SecurityHomeTab extends StatefulWidget {
  const SecurityHomeTab({super.key});

  @override
  State<SecurityHomeTab> createState() => _SecurityHomeTabState();
}

class _SecurityHomeTabState extends State<SecurityHomeTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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
      if (mounted && _userProvider != null) {
        try {
          context.read<CategoryProvider>().fetchCounts(wardenUsername: _userProvider!.username);
        } catch (_) {}
      }
    });
  }

  UserProvider? _userProvider;
  int _lastRefreshTick = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final up = Provider.of<UserProvider>(context, listen: false);
    if (_userProvider != up) {
      _userProvider?.removeListener(_handleGlobalRefreshListener);
      _userProvider = up;
      _lastRefreshTick = _userProvider!.dashboardRefreshTick;
      _userProvider!.addListener(_handleGlobalRefreshListener);
    }
  }

  void _handleGlobalRefreshListener() {
    if (!mounted || _userProvider == null) return;
    final user = _userProvider!;
    if (user.dashboardRefreshTick > _lastRefreshTick) {
      _lastRefreshTick = user.dashboardRefreshTick;
      _handleGlobalRefresh();
    }
  }

  void _handleGlobalRefresh() {
    _fetchAnnouncements();
    if (mounted && _userProvider != null) {
      final user = _userProvider!;
      try {
        context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _userProvider?.removeListener(_handleGlobalRefreshListener);
    _userProvider = null;
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
    super.build(context);
    final user = context.watch<UserProvider>();
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final isDualRole = user.hasMultipleRoles;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Security Dashboard',
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        leftAction: isDualRole ? const RaiseIssueHeaderButton() : null,
        rightAction: isDualRole ? null : const RaiseIssueHeaderButton(),
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
                    _buildHeaderSection(user, isDark),
                    const SizedBox(height: 15),
                    _buildQuickActionsHeader(isDark),
                    _buildQuickActions(context, isDark),
                    _buildAnnouncementsSection(context, isDark),
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

  Widget _buildHeaderSection(UserProvider user, bool isDark) {
    final String displayName = user.userName.isEmpty ? 'Security Staff' : user.userName;
    final String displayId = user.username.isEmpty ? 'ID: Security' : 'ID: ${user.username}';

    String initials = 'S';
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty) {
      if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else if (parts[0].isNotEmpty) {
        initials = parts[0].length >= 2 ? parts[0].substring(0, 2).toUpperCase() : parts[0][0].toUpperCase();
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : null,
        gradient: isDark ? null : SkeuomorphicColors.royalContentGradient,
        border: isDark ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))) : null,
      ),
      child: Row(
        children: [
          UserHeaderAvatar(user: user, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  displayId,
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : SkeuomorphicColors.residenceMutedText,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF5D5D5D),
          ),
        ),
      ),
    );
  }
  Widget _buildQuickActions(BuildContext context, bool isDark) {
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
                isDark,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, String channel, int count, bool isDark) {
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
                    backgroundColor: Colors.transparent,
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
                    color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isHover ? 0.25 : (isDark ? 0.35 : 0.08)),
                        blurRadius: isHover ? 18 : 10,
                        offset: Offset(0, isHover ? 8 : 4),
                      ),
                    ],
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.03),
                    ),
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
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
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

  Widget _buildAnnouncementsSection(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active, color: Color(0xFFD4AF37), size: 18),
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
      ),
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
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
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
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFD4AF37), shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        announcement['title'] ?? '', 
                        style: SkeuomorphicStyles.playfairHeader.copyWith(
                          fontSize: 14, 
                          color: isDark ? Colors.white : SkeuomorphicColors.residenceNavy,
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
                style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            announcement['content'] ?? '', 
            style: SkeuomorphicStyles.latoBody.copyWith(
              fontSize: 13, 
              color: isDark ? Colors.white70 : Colors.blueGrey,
            ),
          ),
        ],
      ),
    );
  }
}
