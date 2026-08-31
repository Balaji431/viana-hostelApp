import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../core/api_service.dart';
import '../../core/websocket_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/ui_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../widgets/warden_widgets.dart';
import '../widgets/warden_modals.dart';
import '../widgets/room_change_history_dialog.dart';
import '../widgets/warden_temporary_stay_dialog.dart';
import 'warden_chat_interface.dart';
import '../../shared/category_provider.dart';
import 'warden_main_screen.dart';
import 'warden_room_search_screen.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/main_layout.dart';
import '../../admin/screens/temporary_stay_admin_screen.dart';



class WardenHomeTab extends StatefulWidget {
  const WardenHomeTab({super.key});

  @override
  State<WardenHomeTab> createState() => _WardenHomeTabState();
}

class _WardenHomeTabState extends State<WardenHomeTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _tempStayPendingCount = 0;
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAllData();
    });
    WebSocketService.instance.isConnectedNotifier.addListener(_onWSConnChange);
    _startRefreshTimer();
  }

  void _onWSConnChange() {
    if (mounted) _startRefreshTimer();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    final interval = WebSocketService.instance.isConnected ? 60 : 10;
    _refreshTimer = Timer.periodic(Duration(seconds: interval), (_) {
      if (mounted) {
        _refreshAllData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    WebSocketService.instance.isConnectedNotifier.removeListener(_onWSConnChange);
    _refreshTimer?.cancel();
    super.dispose();
  }


  Future<void> _refreshAllData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingAnnouncements = true;
      });
    }

    final user = Provider.of<UserProvider>(context, listen: false);

    await Future.wait([
      _fetchAnnouncements(),
      _fetchTempStayCounts(),
      context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username),
    ]);
  }

  Future<void> _fetchTempStayCounts() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final res = await ApiService.fetchAdminTemporaryStayRequests(
        status: 'pending',
        wardenId: user.dbId?.toString() ?? user.username,
        wardenName: user.userName,
      );
      if (res['success'] == true && mounted) {
        final counts = res['counts'] ?? {};
        setState(() {
          _tempStayPendingCount = int.tryParse(counts['pending_count']?.toString() ?? '0') ?? 0;
        });
      }
    } catch (e) {
      // ignore
    }
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Warden Dashboard',
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        rightAction: ProfileButton(
          onTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(4),
        ),
      ),
      body: LinenBackground(
        child: RefreshIndicator(
          onRefresh: () => _refreshAllData(),
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
                  const SizedBox(height: 20),
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
    final String displayName = user.userName.isNotEmpty ? user.userName : 'Warden';
    final String displayId = user.username.isNotEmpty ? "ID: ${user.username}" : (user.institution.isNotEmpty && user.institution != 'N/A' ? user.institution : "ID: Warden");

    String initials = 'W';
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SkeuomorphicColors.goldGlossyGradient,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1B2B48),
                  fontFamily: 'Lato',
                ),
              ),
            ),
          ),
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
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF5D5D5D),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, bool isDark) {
    final catProvider = context.watch<CategoryProvider>();
    final categories = catProvider.categories;

    final List<Map<String, dynamic>> actions = [];
    
    for (var cat in categories) {
      final name = cat['name'] ?? '';
      
      if (name.toLowerCase() != 'warden') continue;

      String title = 'Students';
      IconData icon = Icons.group;
      Color color = catProvider.getColor(cat['color'] ?? cat['color_hex']);
      String channel = name;

      actions.add({
        'title': title,
        'icon': icon,
        'color': color,
        'channel': channel,
        'type': 'chat',
      });
    }

    if (!actions.any((a) => a['channel'] == 'parent_warden')) {
      actions.add({
        'title': 'Parents',
        'icon': Icons.family_restroom,
        'color': const Color(0xFF8D6E63),
        'channel': 'parent_warden',
        'type': 'chat',
      });
    }

    actions.add({
      'title': 'Temp Stay',
      'icon': Icons.hotel_rounded,
      'color': const Color(0xFF0288D1),
      'channel': 'temporary_stay',
      'type': 'temporary_stay',
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
          child: Row(
            children: actions.map((action) {
              return Padding(
                padding: const EdgeInsets.only(right: 15),
                child: SizedBox(
                  width: 110,
                  child: _buildActionCard(
                    context, 
                    action['title'], 
                    action['icon'], 
                    action['color'],
                    action['channel'] ?? '',
                    type: action['type'],
                    category: action['category'],
                    isDark: isDark,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {
                final user = context.read<UserProvider>();
                final wardenId = user.dbId ?? 1;
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  barrierColor: Colors.transparent,
                  useRootNavigator: false,
                  builder: (context) => RoomChangeHistoryDialog(wardenId: wardenId),
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFFD4AF37).withOpacity(0.15) : const Color(0xFF1E2F5E).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFFD4AF37).withOpacity(0.3) : const Color(0xFF1E2F5E).withOpacity(0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1E2F5E), size: 10),
                        const SizedBox(width: 4),
                        Text(
                          'VIEW HISTORY',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1E2F5E),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, String channel, {String? type = 'chat', String? category, bool isDark = false}) {
    final catProvider = context.read<CategoryProvider>();
    int count = (type == 'temporary_stay')
        ? _tempStayPendingCount
        : catProvider.getUnreadCount(channel);

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

              if (type == 'temporary_stay') {
                if (isDesktop) {
                  context.read<UIProvider>().setActiveChatChannel('temporary_stay');
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TemporaryStayAdminScreen(),
                    ),
                  ).then((_) {
                    if (context.mounted) {
                      _refreshAllData(silent: true);
                    }
                  });
                }
                return;
              }

              if (type == 'room_search') {
                showDialog(
                  context: context,
                  builder: (context) => const WardenRoomSearchScreen(isDialog: true),
                );
                return;
              }

              if (type == 'reports') {
                final mainResponsive = context.findAncestorStateOfType<MainResponsiveLayoutState>();
                if (mainResponsive != null) {
                  mainResponsive.setSelectedIndex(2, reportsCategory: category);
                } else {
                  WardenMainScreen.of(context)?.setTabIndex(2, reportsCategory: category);
                }
                return;
              }

              if (isDesktop) {
                context.read<UIProvider>().setActiveChatChannel(channel);
              } else {
                // 🔥 ADD ROUTE SETTINGS FOR PROPER DETECTION
                final user = Provider.of<UserProvider>(context, listen: false);
                Navigator.push(context, MaterialPageRoute(
                  builder: (context) => LinenGridBackground(
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      body: WardenChatInterface(channel: channel),
                    ),
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
                        color: Colors.black.withOpacity(
                          isDark ? 0.35 : (isHover ? 0.18 : 0.08),
                        ),
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
    final user = context.watch<UserProvider>();
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
                      color: isDark ? Colors.white70 : Colors.grey,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              if (user.username.toLowerCase() == 'warden1' ||
                  user.userName.toLowerCase().contains('venkatesh') ||
                  user.role == UserRole.admin)
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFFD4AF37), size: 24),
                  tooltip: 'Add Announcement (Main Warden / Venkatesh)',
                  onPressed: () => showDialog(
                    context: context,
                    builder: (context) => NewAnnouncementModal(
                      onPost: (title, content) async {
                        final response = await ApiService.postAnnouncement(title, content, username: user.username);
                        if (response['status'] == 'success') {
                          _fetchAnnouncements();
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(response['message'] ?? 'Failed to post announcement')),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isLoadingAnnouncements)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: Color(0xFFD4AF37))))
          else if (_announcements.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("No announcements yet", style: TextStyle(color: isDark ? Colors.white54 : Colors.grey))))
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


  void showPendingRenewalsModal(List<Map<String, dynamic>> students) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3EFE9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // HEADER
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        "Pending Renewals",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Lato',
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 18),
                      ),
                    )
                  ],
                ),

                const Divider(height: 20),

                // LIST
                ...students.map((s) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F6F0),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                "Room ${s['room']}",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                        // Reject
                        GestureDetector(
                          onTap: () => _rejectStudent(s['id']),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.red),
                          ),
                        ),

                        // Approve
                        GestureDetector(
                          onTap: () => _approveStudent(s['id']),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check, color: Colors.green),
                          ),
                        ),
                      ],
                    ),
                  );
                })
              ],
            ),
          ),
        );
      },
    );
  }
  void _approveStudent(int id) async {
    try {
      final response = await ApiService.approveRenewal(id);
      if (response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Student approved!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _rejectStudent(int id) async {
    try {
      final response = await ApiService.rejectRenewal(id);
      if (response['success'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Student rejected'), backgroundColor: Colors.red),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }
}
