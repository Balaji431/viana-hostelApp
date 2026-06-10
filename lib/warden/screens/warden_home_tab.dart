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
import '../../core/models/room_change_request_model.dart';
import 'warden_main_screen.dart';
import 'warden_allocation_screen.dart';
import '../../core/design_system.dart' as ds;
import '../../core/models/request_model.dart';
import '../../shared/chat/request_details_screen.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/main_layout.dart';

class WardenHomeTab extends StatefulWidget {
  const WardenHomeTab({super.key});

  @override
  State<WardenHomeTab> createState() => _WardenHomeTabState();
}

class _WardenHomeTabState extends State<WardenHomeTab> {
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;
  List<RoomChangeRequest> _pendingRequests = [];
  bool _isRoomChangeLoading = false;
  List<Map<String, dynamic>> _pendingApprovals = [];
  Map<String, dynamic>? _systemStats;
  bool _isLoadingStats = true;
  List<Map<String, dynamic>> _pendingWardenRequests = [];
  bool _isLoadingWardenRequests = true;
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
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAllData({bool silent = false}) async {
     if (!silent) {
       setState(() {
         _isLoadingAnnouncements = true;
         _isLoadingStats = true;
         _isLoadingWardenRequests = true;
         _isRoomChangeLoading = true;
       });
    }
    
    final user = Provider.of<UserProvider>(context, listen: false);
    
    await Future.wait([
      _fetchAnnouncements(),
      _loadPendingRequests(),
      _loadPendingApprovals(),
      _fetchSystemStats(),
      _loadGeneralRequests(),
      context.read<CategoryProvider>().fetchCounts(wardenUsername: user.username),
    ]);
  }

  Future<void> _fetchSystemStats() async {
    try {
      final response = await ApiService.getSystemStats();
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

  Future<void> _loadPendingRequests() async {
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.getRoomChangeRequests(
        status: 'pending',
        wardenUsername: user.username,
      );
      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        if (mounted) {
          setState(() {
            _pendingRequests = data.map((json) => RoomChangeRequest.fromJson(json)).toList();
            _isRoomChangeLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isRoomChangeLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isRoomChangeLoading = false);
    }
  }

  Future<void> _loadPendingApprovals() async {
    try {
      // Use real API call for pending renewals
      final response = await ApiService.getPendingRenewals();
      
      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        if (mounted) {
          setState(() {
            _pendingApprovals = data.map((item) => {
              'id': item['id'],
              'name': item['student_name'] ?? item['name'] ?? 'Unknown',
              'room': item['room_number'] ?? item['room'] ?? 'N/A',
              'request_id': item['request_id'] ?? item['id'],
            }).toList();
          });
        }
      }
    } catch (e) {
    }
  }

  Future<void> _loadGeneralRequests() async {
    // General category requests should only show in the chat screen, not in the Warden request sections.
    if (mounted) {
      setState(() {
        _pendingWardenRequests = [];
        _isLoadingWardenRequests = false;
      });
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


  Widget buildPendingApprovalCard(int count, VoidCallback onTap) {
    if (count == 0) return const SizedBox();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFE9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.group, color: Colors.black),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Pending Approvals",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'Georgia',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$count students awaiting renewal",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFC107), Color(0xFFFF9800)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "$count New",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget buildRoomChangeRequestCard(int count, VoidCallback onTap) {
    if (count == 0) return const SizedBox();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EFE9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.swap_horiz, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Pending Room Requests",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      fontFamily: 'Georgia',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$count room change requests",
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                "$count New",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            )
          ],
        ),
      ),
    );
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

  Widget _buildAllocationQueueCard() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (ctx) => const WardenAllocationScreen())),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: ds.RoyalTheme.navyGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: ds.RoyalTheme.goldGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_ind, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Allocation Queue",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                      fontFamily: 'Georgia',
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Manage student room preferences",
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  if (user.username == 'warden1') ...[
                    _buildAllocationQueueCard(),
                    const SizedBox(height: 10),
                  ],
                  _buildQuickActionsHeader(),
                  _buildQuickActions(context),
                  const SizedBox(height: 20),
                  _buildPendingRequestsSection(),
                  const SizedBox(height: 16),
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


  Widget _buildPendingRequestsSection() {
    if (_isLoadingWardenRequests || _isRoomChangeLoading) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    
    final allPending = [
      ..._pendingRequests.map((r) => {'type': 'room_change', 'data': r}),
      ..._pendingWardenRequests.map((r) => {'type': 'service', 'data': r}),
    ];

    if (allPending.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.pending_actions, color: Color(0xFFD4AF37), size: 18),
                  SizedBox(width: 8),
                  Text('PENDING REQUESTS', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ],
              ),
              if (allPending.length > 3)
                TextButton(
                  onPressed: () => WardenMainScreen.of(context)?.setTabIndex(2), 
                  child: const Text('View All', style: TextStyle(fontSize: 11, color: Color(0xFF1E2F5E)))
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...allPending.take(3).map((item) {
            if (item['type'] == 'room_change') {
              return _buildWardenRoomChangeCard(item['data'] as RoomChangeRequest);
            } else {
              return _buildDashboardRequestCard(item['data'] as Map<String, dynamic>);
            }
          }),
        ],
      ),
    );
  }

  Widget _buildWardenRoomChangeCard(RoomChangeRequest request) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => WardenRoomChangeDetailsModal(
            request: request,
            onActionComplete: () {
              _loadPendingRequests();
              _loadGeneralRequests();
            },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.hourglass_bottom, color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Room Change Request", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange)),
                        Text(request.requestId, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Text("PENDING", style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(request.currentRoom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                  const SizedBox(width: 10),
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  const SizedBox(width: 10),
                  Text(request.requestedRoom, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFD4AF37))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                children: [
                  const TextSpan(text: "REASON: ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 10)),
                  TextSpan(text: request.reason),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text("Student: ${request.studentName} (${request.studentRegNo})", style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardRequestCard(Map<String, dynamic> req) {
    return GestureDetector(
      onTap: () {
         showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          useRootNavigator: false,
          builder: (context) => FractionallySizedBox(
            heightFactor: 0.85,
            child: RequestDetailsScreen(
              request: RequestModel.fromJson(req),
              canAction: true,
            ),
          ),
        ).then((_) => _loadGeneralRequests());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: SkeuomorphicStyles.skeuomorphicCard,
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
              child: Center(child: Icon(Icons.description_outlined, color: Colors.white, size: 20)),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(req['request_type'] ?? 'Service Request', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48))),
                  const SizedBox(height: 2),
                  Text('${req['student_name']} • ${req['room_number']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
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
                WardenMainScreen.of(context)?.setTabIndex(2, reportsCategory: category);
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
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFFD4AF37), size: 28), 
                onPressed: () => showDialog(context: context, builder: (context) => NewAnnouncementModal(
                  onPost: (title, content) async {
                    final response = await ApiService.postAnnouncement(title, content);
                    if (response['status'] == 'success') {
                      _fetchAnnouncements();
                    }
                  }
                ))
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
                          fontFamily: 'Georgia',
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
                }).toList()
              ],
            ),
          ),
        );
      },
    );
  }

  void showRoomChangeRequestsModal(List<RoomChangeRequest> requests) {
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
                        "Pending Room Requests",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Georgia',
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
                ...requests.map((request) {
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
                                request.studentName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                "${request.currentRoom} -> ${request.requestedRoom}",
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),

                        // Reject
                        GestureDetector(
                          onTap: () => _rejectRoomRequest(request),
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
                          onTap: () => _approveRoomRequest(request),
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
                }).toList()
              ],
            ),
          ),
        );
      },
    );
  }

  void _approveStudent(int id) async {
    try {
      // Use real API call for approving renewal
      final response = await ApiService.approveRenewal(id);
      
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            _pendingApprovals.removeWhere((e) => e['id'] == id);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Student approved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to approve student'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _rejectStudent(int id) async {
    try {
      // Use real API call for rejecting renewal
      final response = await ApiService.rejectRenewal(id);
      
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            _pendingApprovals.removeWhere((e) => e['id'] == id);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Student rejected'),
              backgroundColor: Colors.red,
            ),
          );
          
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to reject student'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _approveRoomRequest(RoomChangeRequest request) async {
    try {
      // Use real API call for approving room change request
      final user = context.read<UserProvider>();
      final wardenId = user.dbId ?? 1;
      
      final response = await ApiService.updateRoomChangeRequest(
        requestId: request.requestId,
        status: 'approved',
        wardenId: wardenId,
      );
      
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            _pendingRequests.removeWhere((r) => r.requestId == request.requestId);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Room change request for ${request.studentName} approved!'),
              backgroundColor: Colors.green,
            ),
          );
          
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to approve room change request'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _rejectRoomRequest(RoomChangeRequest request) async {
    try {
      // Use real API call for rejecting room change request
      final user = context.read<UserProvider>();
      final wardenId = user.dbId ?? 1;
      
      final response = await ApiService.updateRoomChangeRequest(
        requestId: request.requestId,
        status: 'rejected',
        wardenId: wardenId,
      );
      
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            _pendingRequests.removeWhere((r) => r.requestId == request.requestId);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Room change request for ${request.studentName} rejected'),
              backgroundColor: Colors.red,
            ),
          );
          
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Failed to reject room change request'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
