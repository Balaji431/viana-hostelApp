import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/ui_provider.dart';
import '../widgets/warden_widgets.dart';
import '../widgets/warden_modals.dart';
import '../widgets/room_change_history_dialog.dart';
import 'warden_chat_interface.dart';
import '../../shared/category_provider.dart';
import 'warden_main_screen.dart';
import 'warden_allocation_screen.dart';
import '../../core/design_system.dart' as ds;
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/main_layout.dart';



class WardenHomeTab extends StatefulWidget {
  const WardenHomeTab({super.key});

  @override
  State<WardenHomeTab> createState() => _WardenHomeTabState();
}

class _WardenHomeTabState extends State<WardenHomeTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;
  Map<String, dynamic>? _systemStats;
  bool _isLoadingStats = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAllData();
    });
    // Set up periodic refresh every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        _refreshAllData(silent: true);
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
      _refreshAllData();
    }
  }

  @override
  void dispose() {
    context.read<UserProvider>().removeListener(_handleGlobalRefreshListener);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAllData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoadingAnnouncements = true;
        _isLoadingStats = true;
      });
    }

    final user = Provider.of<UserProvider>(context, listen: false);

    await Future.wait([
      _fetchAnnouncements(),
      _fetchSystemStats(),
      context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username),
    ]);
  }

  Future<void> _fetchSystemStats() async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final response = await ApiService.getSystemStats(wardenUsername: user.username);
      if (response['success'] == true && mounted) {
        setState(() {
          _systemStats = response['data'];
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStats = false);
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




  Widget _buildSystemStatsSection() {
    if (_isLoadingStats || _systemStats == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.analytics_outlined, color: Color(0xFF1E2F5E), size: 18),
                  SizedBox(width: 8),
                  Text('LIVE SYSTEM PULSE', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                onPressed: _fetchSystemStats,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem("Total Rooms", _systemStats!['total_rooms'].toString(), Icons.meeting_room, Colors.blue),
                _buildStatItem("Occupied", _systemStats!['total_occupied'].toString(), Icons.person_pin, Colors.green),
                _buildStatItem("Available", _systemStats!['total_available'].toString(), Icons.event_available, Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<UserProvider>();

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
                  _buildHeaderSection(user),
                  const SizedBox(height: 15),
                  _buildQuickActionsHeader(),
                  _buildQuickActions(context),
                  const SizedBox(height: 20),
                  _buildAnnouncementsSection(context),
                  const SizedBox(height: 16),
                  _buildSystemStatsSection(),
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
    String displayName = user.userName;
    String displayId = user.institution.isNotEmpty && user.institution != 'N/A' ? user.institution : "ID: ${user.username}";

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
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'V', 
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1a2744))
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName, style: SkeuomorphicStyles.playfairHeader.copyWith(color: Colors.white, fontSize: 16)),
                Text(displayId, style: SkeuomorphicStyles.latoBody.copyWith(color: const Color(0xFFA0B0C0), fontSize: 11)),
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
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5D5D5D),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final catProvider = context.watch<CategoryProvider>();
    final categories = catProvider.categories;

    // Standard actions that are always present or mapped specially
    final List<Map<String, dynamic>> actions = [];
    
    // Add dynamic categories from database - FILTERED TO ONLY STUDENTS (Warden)
    for (var cat in categories) {
      final name = cat['name'] ?? '';
      
      // ONLY include Warden (to be renamed Students)
      if (name.toLowerCase() != 'warden') continue;

      // Map display names and icons
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


    // Add Parents channel if not already there (it's often special)
    if (!actions.any((a) => a['channel'] == 'parent_warden')) {
      actions.add({
        'title': 'Parents',
        'icon': Icons.family_restroom,
        'color': const Color(0xFF8D6E63),
        'channel': 'parent_warden',
        'type': 'chat',
      });
    }

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
                  barrierColor: Colors.transparent, // 🔥 REMOVE BLACK LAYER
                  useRootNavigator: false, // 🔥 STAY INSIDE PHONE FRAME
                  builder: (context) => RoomChangeHistoryDialog(wardenId: wardenId),
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      final user = context.read<UserProvider>();
                      final wardenId = user.dbId ?? 1;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => RoomChangeHistoryDialog(wardenId: wardenId),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E2F5E).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF1E2F5E).withOpacity(0.12)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.history, color: Color(0xFF1E2F5E), size: 10),
                          SizedBox(width: 4),
                          Text(
                            'VIEW HISTORY',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E2F5E),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildActionCard(BuildContext context, String title, IconData icon, Color color, String channel, {String? type = 'chat', String? category}) {
    final catProvider = context.read<CategoryProvider>();
    // Fix: Use only unread message count for the red badge, not pending request counts
    int count = catProvider.getUnreadCount(channel);

    bool isHover = false;
    return StatefulBuilder(
      builder: (context, setHover) {

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setHover(() => isHover = true),
          onExit: (_) => setHover(() => isHover = false),
          child: GestureDetector(
            onTap: () {
              if (type == 'reports') {
                final mainResponsive = context.findAncestorStateOfType<MainResponsiveLayoutState>();
                if (mainResponsive != null) {
                  mainResponsive.setSelectedIndex(2, reportsCategory: category);
                } else {
                  WardenMainScreen.of(context)?.setTabIndex(2, reportsCategory: category);
                }
                return;
              }

              final isDesktop = MediaQuery.of(context).size.width >= 768;
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(
                          isHover ? 0.18 : 0.08,
                        ),
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
    final user = context.watch<UserProvider>();
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
