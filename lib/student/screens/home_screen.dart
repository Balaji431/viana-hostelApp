import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/app_update_service.dart';
import '../../core/styles.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import 'payment_screens.dart';
import '../../shared/user_provider.dart';
import 'allocation_explorer_screen.dart';
import 'allocation_status_screen.dart';
import '../../core/providers/allocation_provider.dart';
import '../../core/design_system.dart' as ds;
import 'maintenance_chat_screen.dart';
import 'parent_warden_chat_screen.dart';
import '../../shared/category_provider.dart';
import '../widgets/room_vacancy_browser.dart';
import '../widgets/student_room_change_history_dialog.dart';
import 'warden_chat_screen.dart';
import '../../shared/ui_provider.dart';
import 'security_chat_screen.dart';
import '../../shared/main_layout.dart';
import '../widgets/temporary_stay_dialog.dart';
import '../widgets/room_transfer_modal.dart';
import '../widgets/student_vacate_modal.dart';
import 'student_wallet_screen.dart';
import 'no_due_page.dart';
import '../../core/top_notification.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../face_attendance/screens/face_attendance_screen.dart';
import '../face_attendance/models/face_attendance_models.dart';
import '../face_attendance/services/attendance_punch_service.dart';
import '../../shared/widgets/raise_issue_header_button.dart';
import '../../shared/widgets/user_avatar_header.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;
  final ScrollController _nameScrollController = ScrollController();
  bool _isScrolling = false;
  
  bool _showRoomOptionsModal = false;
  bool _showVacancyBrowser = false;
  bool _isCheckingWarden = false; // Stack-level overlay — avoids Navigator.pop issues
  String _roomChangeStatus = 'none';
  Map<String, dynamic>? _latestRoomRequest;
  String _vacateStatus = 'none';
  Map<String, dynamic>? _latestVacateRequest;
  bool _showRoomHistory = false;
  bool _showRenewTransferNotice = false;
  bool _hasShownRoomChangeApprovalToast = false;
  bool _isFaceEnrolled = false;

  void _updateOverlayState({
    bool? showRoomOptionsModal,
    bool? showVacancyBrowser,
  }) {
    setState(() {
      if (showRoomOptionsModal != null) {
        _showRoomOptionsModal = showRoomOptionsModal;
        if (!showRoomOptionsModal) _showRenewTransferNotice = false;
      }
      if (showVacancyBrowser != null) _showVacancyBrowser = showVacancyBrowser;
    });

    final showBar = !_showRoomOptionsModal && !_showVacancyBrowser;
    context.read<UIProvider>().setShowBottomNavBar(showBar);
  }

  UserProvider? _userProvider;
  Timer? _tempStayPollingTimer;
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
      _checkFaceEnrollment();
    }
  }

  Future<void> _checkFaceEnrollment() async {
    final user = _userProvider ?? (mounted ? context.read<UserProvider>() : null);
    if (user != null && user.username.isNotEmpty) {
      final enrolled = await AttendancePunchService.isFaceEnrolled(user.username);
      if (mounted && enrolled != _isFaceEnrolled) {
        setState(() {
          _isFaceEnrolled = enrolled;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
    _fetchPayments();
    _checkFaceEnrollment();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Check for mandatory app update
      AppUpdateService.checkUpdateAndPrompt(context);

      final user = _userProvider ?? context.read<UserProvider>();
      _checkFaceEnrollment();
      user.refreshUserData().then((_) {
        if (mounted) {
          _checkFaceEnrollment();
          context.read<CategoryProvider>().fetchCounts(
            studentUsername: user.isParent ? user.linkedStudentUsername : user.username,
          );
        }
      });
      _fetchRoomChangeStatus();
      _fetchVacateStatus();
      
      final int? fetchId = user.isParent ? user.linkedStudentId : user.dbId;
      if (fetchId != null) {
        context.read<CategoryProvider>().fetchAssignedStaff(fetchId);
        if (!user.isParent && user.role == UserRole.student) {
          final allocProvider = context.read<AllocationProvider>();
          allocProvider.loadAllocation(fetchId).then((_) {
            if (mounted) {
              if (!user.isRoomAllocated || (allocProvider.allocationStatus != 'approved' && allocProvider.allocationStatus != 'confirmed')) {
                allocProvider.fetchPaidHostelType(user.username);
              }
            }
          });
        }
      }
    });

    // Periodic auto-refresh for guest/temporary stay status updates
    _tempStayPollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && _userProvider != null) {
        final u = _userProvider!;
        if (u.isGuest || u.temporaryStayRequest != null || u.username.startsWith('TEMP_')) {
          u.refreshUserData();
        }
      }
    });
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
    if (!mounted) return;
    _fetchAnnouncements();
    _fetchPayments();
    _fetchRoomChangeStatus();
    _fetchVacateStatus();
    _checkFaceEnrollment();
    if (!mounted || _userProvider == null) return;
    final user = _userProvider!;
    try {
      context.read<CategoryProvider>().fetchCounts(
        studentUsername: user.isParent ? user.linkedStudentUsername : user.username,
      );
      final int? fetchId = user.isParent ? user.linkedStudentId : user.dbId;
      if (fetchId != null) {
        context.read<CategoryProvider>().fetchAssignedStaff(fetchId);
        if (!user.isParent && user.role == UserRole.student) {
          final allocProvider = context.read<AllocationProvider>();
          allocProvider.loadAllocation(fetchId).then((_) {
            if (mounted) {
              if (!user.isRoomAllocated || (allocProvider.allocationStatus != 'approved' && allocProvider.allocationStatus != 'confirmed')) {
                allocProvider.fetchPaidHostelType(user.username);
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tempStayPollingTimer?.cancel();
    _userProvider?.removeListener(_handleGlobalRefreshListener);
    _userProvider = null;
    _nameScrollController.dispose();
    super.dispose();
  }

  void _scrollName() async {
    if (_isScrolling) return;
    setState(() => _isScrolling = true);
    
    if (_nameScrollController.hasClients) {
      final maxScroll = _nameScrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        await _nameScrollController.animateTo(
          maxScroll,
          duration: Duration(milliseconds: maxScroll.toInt() * 40),
          curve: Curves.linear,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await _nameScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    }
    
    setState(() => _isScrolling = false);
  }

  Future<void> _fetchAnnouncements() async {
    try {
      final response = await ApiService.getAnnouncements();
      if (response['status'] == 'success') {
        if (mounted) {
          setState(() {
            final List<dynamic> data = response['data'] ?? [];
            _announcements = data.map((e) => Map<String, dynamic>.from(e)).toList();
            _isLoadingAnnouncements = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoadingAnnouncements = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingAnnouncements = false);
    }
  }

  Future<void> _fetchPayments() async {
    final user = context.read<UserProvider>();
    if (user.dbId == null) return;

    try {
      final response = await ApiService.getPaymentHistory(user.dbId!);
      if (mounted) {
        setState(() {
          if (response['status'] == 'success') {
            // Payments loaded but not stored in unused local variable
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching payments: $e");
    }
  }

  Future<void> _fetchRoomChangeStatus() async {
    final user = context.read<UserProvider>();
    if (user.dbId == null) return;
    
    try {
      final response = await ApiService.getRoomChangeRequests(
        status: 'all',
        studentId: user.dbId,
      );
      if (response['status'] == 'success') {
        final List<dynamic> rawRequests = response['data'] ?? [];
        final studentRequests = rawRequests.map((e) => Map<String, dynamic>.from(e)).toList();
            
        if (studentRequests.isNotEmpty) {
           studentRequests.sort((a, b) {
              final idA = int.tryParse(a['request_id']?.toString() ?? '0') ?? 0;
              final idB = int.tryParse(b['request_id']?.toString() ?? '0') ?? 0;
              return idB.compareTo(idA);
           });
           
            if (mounted) {
              final latest = studentRequests.first;
              final status = (latest['status'] ?? 'none').toString().toLowerCase();
              final payStatus = (latest['payment_status'] ?? '').toString().toLowerCase();
              final double amt = double.tryParse((latest['amount_to_pay'] ?? latest['amount'] ?? 0).toString()) ?? 0.0;
              
              setState(() {
                _latestRoomRequest = latest;
                _roomChangeStatus = status;
              });

              // Notify student once when room change approval is accepted
              if (!_hasShownRoomChangeApprovalToast && (status == 'approved' || status == 'completed') && (amt <= 0 || payStatus == 'paid')) {
                final reqId = latest['request_id']?.toString() ?? latest['id']?.toString() ?? '';
                if (reqId.isNotEmpty) {
                  SharedPreferences.getInstance().then((prefs) {
                    final hasSeenKey = 'seen_room_change_notif_${user.username}_$reqId';
                    final alreadySeen = prefs.getBool(hasSeenKey) ?? false;
                    if (!alreadySeen) {
                      prefs.setBool(hasSeenKey, true);
                      _hasShownRoomChangeApprovalToast = true;
                      final targetRoom = latest['requested_room'] ?? latest['room_code'] ?? 'New Room';
                      final targetType = (latest['requested_room_type'] ?? '').toString();
                      if (mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            TopNotification.showSuccess(
                              context,
                              title: 'Room Change Approved! 🎉',
                              message: 'Your room change request has been accepted. You are now allocated to $targetRoom' + (targetType.isNotEmpty ? ' ($targetType)' : '') + '.',
                            );
                          }
                        });
                      }
                    }
                  });
                }
              }
            }
        } else {
           if (mounted) setState(() => _roomChangeStatus = 'none');
        }
      }
    } catch (e) {
      debugPrint("Error fetching room change status: $e");
    }
  }

  Future<void> _fetchVacateStatus() async {
    final user = context.read<UserProvider>();
    if (user.username.isEmpty) return;
    try {
      final res = await ApiService.getStudentVacateStatus(regNo: user.username);
      if (res['success'] == true && res['has_request'] == true && mounted) {
        final data = res['data'];
        setState(() {
          _latestVacateRequest = data;
          _vacateStatus = (data['status'] ?? 'none').toString().toLowerCase();
        });
      } else if (mounted) {
        setState(() {
          _latestVacateRequest = null;
          _vacateStatus = 'none';
        });
      }
    } catch (e) {
      debugPrint("Error fetching vacate status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<UserProvider>();
    final isTempStayPaid = user.temporaryStayRequest != null &&
        (user.temporaryStayRequest!['status'] == 'allocated' ||
            user.temporaryStayRequest!['payment_status'] == 'paid');
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Viana Stay',
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        rightAction: const RaiseIssueHeaderButton(),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () async {
              await _fetchAnnouncements();
              await _fetchPayments();
              await _fetchRoomChangeStatus();
              if (mounted) {
                final user = context.read<UserProvider>();
                await user.refreshUserData();
                await context.read<CategoryProvider>().fetchCounts(
                  studentUsername: user.isParent ? user.linkedStudentUsername : user.username,
                );
                if (!user.isParent && user.role == UserRole.student) {
                  final allocProvider = context.read<AllocationProvider>();
                  await allocProvider.loadAllocation(user.dbId!);
                  if (!user.isRoomAllocated || (allocProvider.allocationStatus != 'approved' && allocProvider.allocationStatus != 'confirmed')) {
                    await allocProvider.fetchPaidHostelType(user.username);
                  }
                }
              }
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildProfileHeader(user),
                    const SizedBox(height: 10),
                    if (isTempStayPaid) ...[
                      // Once paid & allocated, show standard Room Allocation Card with days remaining
                      _buildAllocationCard(context, user),
                    ] else if (user.isGuest || user.temporaryStayRequest != null || user.username.startsWith('TEMP_')) ...[
                      // Temporary / Short stay student — show live lifecycle progress & status stepper
                      _buildTemporaryStayCard(context, user),
                    ] else if (user.isRoomAllocated) ...[
                      // Student has a room — show ONLY the room allocation card
                      _buildAllocationCard(context, user),
                    ] else if (!user.isParent) ...[
                      // Student has NO room — show ONLY the fee paid card with Contact Hostel Warden
                      _buildNewStudentAllocationCard(context, user),
                    ],

                    if (ApiService.enableFaceBiometric) ...[
                      const SizedBox(height: 10), 
                      _buildFaceAttendanceCard(context, user),
                    ],
                    const SizedBox(height: 10),
                    _buildProceedPaymentButton(),
                    _buildQuickActionsHeader(),
                    _buildQuickActions(context),
                    _buildAnnouncementsHeader(),
                    _buildAnnouncements(),
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ),
          
          if (_showRoomOptionsModal)
            _buildRoomOptionsModal(context, user),
            
          if (_showVacancyBrowser)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _updateOverlayState(showVacancyBrowser: false),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: GestureDetector(
                    onTap: () {}, 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        RoomVacancyBrowser(
                          isOpen: _showVacancyBrowser,
                          onClose: () {
                            _updateOverlayState(showVacancyBrowser: false);
                          },
                          currentRoomString: user.isParent ? user.linkedStudentRoom : user.fullRoomDetails,
                          studentId: user.dbId,
                          onStatusChanged: _fetchRoomChangeStatus,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),



          // Warden-check loading overlay — sits on top of the renewal modal
          // Uses Stack (not Navigator) so nothing gets accidentally popped
          if (_isCheckingWarden)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFD4AF37)),
                          SizedBox(height: 16),
                          Text(
                            'Checking warden assignment…',
                            style: TextStyle(fontSize: 13, color: Color(0xFF4A4A4A)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomOptionsModal(BuildContext context, UserProvider user) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    final statusLower = _roomChangeStatus.toLowerCase();
    final double reqAmount = double.tryParse((_latestRoomRequest?['amount_to_pay'] ?? _latestRoomRequest?['amount'] ?? 0).toString()) ?? 0.0;
    final reqPaymentStatus = (_latestRoomRequest?['payment_status'] ?? '').toString().toLowerCase();
    final bool isUpgradePaymentPending = (statusLower == 'approved' || statusLower == 'pre_approved') && reqAmount > 0 && reqPaymentStatus != 'paid';
    final hasActiveOrPendingRequest = _roomChangeStatus.isNotEmpty &&
        statusLower != 'none' &&
        statusLower != 'completed' &&
        statusLower != 'rejected' &&
        isUpgradePaymentPending;
    final roomType = user.roomType.isNotEmpty ? user.roomType : (user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "Standard Room");
    final hostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final roomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final renewalDateStr = user.renewalDate != null
        ? DateFormat('dd MMM yyyy').format(user.renewalDate!)
        : 'N/A';
    final DateTime? renewDeadline = user.renewalDate != null
        ? DateTime(
            user.renewalDate!.year,
            user.renewalDate!.month,
            user.renewalDate!.day,
            23, 59, 59,
          )
        : null;
    final bool isRenewalExpired = renewDeadline != null && DateTime.now().isAfter(renewDeadline);
    final assignedWarden = (_latestRoomRequest?['assigned_warden_name'] ?? _latestRoomRequest?['warden_name'] ?? '').toString().trim();
    final wardenDisplay = assignedWarden.isNotEmpty ? 'Warden $assignedWarden' : 'the Hostel Warden';

    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF9F6F0),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Bar
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF9F6F0),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE0D8CC),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Manage Room',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1A2744),
                          fontFamily: 'Lato',
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          _updateOverlayState(showRoomOptionsModal: false);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close, 
                                       size: 18, color: isDark ? Colors.white70 : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content Body
                Container(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF9F6F0),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Existing Room Allotted Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Icon(Icons.king_bed_outlined, color: isDark ? const Color(0xFFEBC15B) : const Color(0xFF1A2744), size: 20),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    roomType,
                                    style: GoogleFonts.lato(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF1A2744),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (_isFaceEnrolled) ...[
                                  _buildEnrolledBadge(),
                                  const SizedBox(width: 6),
                                ],
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Text(
                                    'Active',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Row(
                              children: [
                                Icon(Icons.location_on_outlined, color: isDark ? Colors.white60 : Colors.grey, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '$hostel · ${user.campus}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Row(
                              children: [
                                Text(
                                  'Room No: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white70 : const Color(0xFF1A2744),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    roomNo,
                                    style: GoogleFonts.lato(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF10B981),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Total Fee', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₹${NumberFormat('#,##,###').format(user.totalFee.toInt())}',
                                      style: GoogleFonts.lato(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF1A2744),
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Additional EB Charges', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Yes',
                                      style: GoogleFonts.lato(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF1A2744),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Renewal Date', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey)),
                                const SizedBox(height: 2),
                                Text(
                                  renewalDateStr,
                                  style: GoogleFonts.lato(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(child: _buildModalInfoBox('Amount', '₹${NumberFormat('#,##,###').format(user.roomAmount.toInt())}', isDark)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildModalInfoBox('Food', '₹${NumberFormat('#,##,###').format(user.roomFood.toInt())}', isDark)),
                                const SizedBox(width: 8),
                                Expanded(child: _buildModalInfoBox('Caution', '₹${NumberFormat('#,##,###').format(user.roomCaution.toInt())}', isDark)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      if (!user.isGuest) ...[
                        if (_showRenewTransferNotice) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF7F1D1D).withOpacity(0.3) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '⚠️ Please complete the Transfer request first.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_vacateStatus == 'pending') ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF450A0A).withOpacity(0.3) : const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.exit_to_app_rounded, color: Color(0xFFDC2626), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'VACATE REQUEST PENDING APPROVAL',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Requested date: ${_latestVacateRequest?['expected_vacate_date'] ?? ''}. Review by ${_latestVacateRequest?['assigned_warden_name'] ?? 'Warden'}. Room will be freed upon approval.',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B),
                                              height: 1.3,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: InkWell(
                                    onTap: () async {
                                      final reqId = _latestVacateRequest?['request_id'];
                                      if (reqId != null) {
                                        await ApiService.cancelVacateRequest(requestId: reqId);
                                        _fetchVacateStatus();
                                      }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Text(
                                        'Cancel Request',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFDC2626),
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (statusLower == 'pending') ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF78350F).withOpacity(0.3) : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFD97706).withOpacity(0.4)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TRANSFER REQUEST PENDING',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFB45309),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Your transfer request is under review by $wardenDisplay. Only 1 request allowed at a time.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? const Color(0xFFFED7AA) : const Color(0xFFEA580C),
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (isUpgradePaymentPending) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                _updateOverlayState(showRoomOptionsModal: false);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => NoDuePage()),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 2,
                                shadowColor: const Color(0xFF1D4ED8).withOpacity(0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                'Pay Upgrade Fee (₹${NumberFormat('#,##,###').format(reqAmount.toInt())})',
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Row(
                            children: [
                              // Renew Button (Blue)
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    _updateOverlayState(showRoomOptionsModal: false);
                                    if (isRenewalExpired) {
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                          title: const Row(
                                            children: [
                                              Icon(Icons.timer_off_outlined, color: Colors.red),
                                              SizedBox(width: 8),
                                              Text('Renewal Window Closed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          content: Text(
                                            'The renewal deadline for your room expired on ${user.renewalDate != null ? DateFormat('dd MMM yyyy').format(user.renewalDate!) : 'N/A'} at 11:59 PM.\n\nSince the renewal date has passed, room renewal is closed and the bed is released for new bookings.\n\nIf you need accommodation, please apply freshly via the VStudy portal.',
                                            style: const TextStyle(fontSize: 14, height: 1.4),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );
                                      return;
                                    }
                                    _showRenewBookingModal(context, user);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isRenewalExpired ? const Color(0xFF64748B) : const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(isRenewalExpired ? Icons.timer_off_outlined : Icons.sync, size: 18, color: Colors.white),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          isRenewalExpired
                                              ? 'Renewal Expired'
                                              : 'Renew ₹${NumberFormat('#,##,###').format(user.renewAmount > 0 ? user.renewAmount.toInt() : 120000)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.lato(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Transfer Button
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    _updateOverlayState(showRoomOptionsModal: false);
                                    StudentRoomTransferModal.show(
                                      context,
                                      initialStep: 2,
                                      onSubmitted: () {
                                        _fetchRoomChangeStatus();
                                      },
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
                                    foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    side: BorderSide(
                                      color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFFCBD5E1),
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.location_on_outlined, size: 18, color: isDark ? Colors.white : const Color(0xFF1E293B)),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Room Change',
                                        style: GoogleFonts.lato(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                _updateOverlayState(showRoomOptionsModal: false);
                                StudentVacateModal.show(
                                  context,
                                  user,
                                  onSubmitted: () {
                                    _fetchVacateStatus();
                                  },
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF450A0A).withOpacity(0.2) : const Color(0xFFFEF2F2),
                                foregroundColor: const Color(0xFFDC2626),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                  color: const Color(0xFFEF4444).withOpacity(0.4),
                                  width: 1.2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.exit_to_app_rounded, size: 18, color: Color(0xFFDC2626)),
                                  SizedBox(width: 8),
                                  Text(
                                    'Request to Vacate Room',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: Color(0xFFDC2626),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Temporary Stay allocations cannot be renewed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalInfoBox(String label, String amount, [bool isDark = false]) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: GoogleFonts.lato(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1A2744),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenewBookingModal(BuildContext context, UserProvider user) {
    final hostelName = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final campus = user.campus.isNotEmpty ? user.campus : "Thandalam Campus";
    final roomType = user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "4 IN 1 AC";
    final roomNumber = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";

    final bool is3In1 = roomType.contains('3 IN 1') || roomType.toLowerCase().contains('triple');
    final double baseRent = is3In1 ? 75000.0 : (user.roomAmount > 0 ? user.roomAmount : 70000.0);
    final double baseFood = 50000.0;

    List<Map<String, dynamic>> durationOptions = [
      {
        'months': 12,
        'multiplier': '',
        'premiumMultiplier': 1.0,
        'roomRent': baseRent,
        'food': baseFood,
        'total': baseRent + baseFood,
      },
      {
        'months': 9,
        'multiplier': '1.32x',
        'premiumMultiplier': 1.32,
        'roomRent': (baseRent * 0.99).roundToDouble(),
        'food': (baseFood * 0.75).roundToDouble(),
        'total': (baseRent * 0.99 + baseFood * 0.75).roundToDouble(),
      },
      {
        'months': 6,
        'multiplier': '1.56x',
        'premiumMultiplier': 1.56,
        'roomRent': (baseRent * 0.78).roundToDouble(),
        'food': (baseFood * 0.50).roundToDouble(),
        'total': (baseRent * 0.78 + baseFood * 0.50).roundToDouble(),
      },
      {
        'months': 3,
        'multiplier': '1.8x',
        'premiumMultiplier': 1.8,
        'roomRent': (baseRent * 0.45).roundToDouble(),
        'food': (baseFood * 0.25).roundToDouble(),
        'total': (baseRent * 0.45 + baseFood * 0.25).roundToDouble(),
      },
    ];

    int selectedMonths = 12;
    bool hasFetchedRemote = false;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (!hasFetchedRemote) {
              hasFetchedRemote = true;
              ApiService.getRoomPricing(roomType).then((res) {
                if (res['success'] == true && res['data']?['renewals'] is List) {
                  final List<dynamic> renList = res['data']['renewals'];
                  if (renList.isNotEmpty) {
                    final updated = renList.map((item) {
                      final m = int.tryParse(item['months'].toString()) ?? 12;
                      final pm = double.tryParse(item['premiumMultiplier'].toString()) ?? 1.0;
                      final rr = double.tryParse(item['roomRent'].toString()) ?? 0.0;
                      final fd = double.tryParse(item['food'].toString()) ?? 0.0;
                      final tot = double.tryParse(item['total'].toString()) ?? (rr + fd);
                      return {
                        'months': m,
                        'multiplier': m == 12 ? '' : '${pm}x',
                        'premiumMultiplier': pm,
                        'roomRent': rr,
                        'food': fd,
                        'total': tot,
                      };
                    }).toList();
                    if (ctx.mounted) {
                      setModalState(() {
                        durationOptions = updated;
                      });
                    }
                  }
                }
              }).catchError((_) {});
            }

            final selectedOpt = durationOptions.firstWhere(
              (o) => o['months'] == selectedMonths,
              orElse: () => durationOptions.first,
            );

            final double selectedRent = (selectedOpt['roomRent'] as num).toDouble();
            final double selectedFood = (selectedOpt['food'] as num).toDouble();
            final double selectedTotal = (selectedOpt['total'] as num).toDouble();
            final double selectedMultiplier = (selectedOpt['premiumMultiplier'] as num).toDouble();
            final int perMonth = (selectedTotal / selectedMonths).round();

            final rentFormatted = NumberFormat('#,##,###').format(selectedRent.toInt());
            final foodFormatted = NumberFormat('#,##,###').format(selectedFood.toInt());
            final totalFormatted = NumberFormat('#,##,###').format(selectedTotal.toInt());
            final perMonthFormatted = NumberFormat('#,##,###').format(perMonth);
            final bool hasEnoughBalance = user.walletBalance >= selectedTotal;

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              elevation: 6,
              backgroundColor: const Color(0xFFF1F3F5),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Icon + Title + Close Button
                    Row(
                      children: [
                        const Icon(Icons.sync_rounded, size: 22, color: Color(0xFF1E293B)),
                        const SizedBox(width: 8),
                        Text(
                          'Renew Hostel Booking',
                          style: GoogleFonts.lato(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: const Icon(Icons.close, size: 18, color: Color(0xFF475569)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Card 1: Existing Room Details
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDEE2E6)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Hostel', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Flexible(
                                child: Text(
                                  '$hostelName · $campus',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.lato(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Room Type', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Text(
                                roomType,
                                style: GoogleFonts.lato(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Room Number', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Text(
                                roomNumber,
                                style: GoogleFonts.lato(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Card 2: Renewal Duration (2x2 Grid)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDEE2E6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Renewal Duration',
                            style: GoogleFonts.lato(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // Row 1: 12 months & 9 months
                          Row(
                            children: [
                              Expanded(
                                child: _buildDurationCard(
                                  option: durationOptions.isNotEmpty ? durationOptions[0] : {'months': 12, 'total': 120000},
                                  isSelected: selectedMonths == (durationOptions.isNotEmpty ? durationOptions[0]['months'] : 12),
                                  onTap: () {
                                    setModalState(() {
                                      selectedMonths = durationOptions[0]['months'];
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDurationCard(
                                  option: durationOptions.length > 1 ? durationOptions[1] : {'months': 9, 'total': 106800, 'multiplier': '1.32x'},
                                  isSelected: selectedMonths == (durationOptions.length > 1 ? durationOptions[1]['months'] : 9),
                                  onTap: () {
                                    setModalState(() {
                                      selectedMonths = durationOptions[1]['months'];
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Row 2: 6 months & 3 months
                          Row(
                            children: [
                              Expanded(
                                child: _buildDurationCard(
                                  option: durationOptions.length > 2 ? durationOptions[2] : {'months': 6, 'total': 79600, 'multiplier': '1.56x'},
                                  isSelected: selectedMonths == (durationOptions.length > 2 ? durationOptions[2]['months'] : 6),
                                  onTap: () {
                                    setModalState(() {
                                      selectedMonths = durationOptions[2]['months'];
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDurationCard(
                                  option: durationOptions.length > 3 ? durationOptions[3] : {'months': 3, 'total': 44000, 'multiplier': '1.8x'},
                                  isSelected: selectedMonths == (durationOptions.length > 3 ? durationOptions[3]['months'] : 3),
                                  onTap: () {
                                    setModalState(() {
                                      selectedMonths = durationOptions[3]['months'];
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Card 3: Fee Breakdown
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9ECEF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFDEE2E6)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Room Rent ($selectedMonths months)', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Text('₹$rentFormatted', style: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Food ($selectedMonths months)', style: const TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Text('₹$foodFormatted', style: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Caution Deposit', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Text('Not re-charged', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Divider(color: Color(0xFFCED4DA), height: 1),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Renewal Total', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                              Text('₹$totalFormatted', style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Per month', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                              Text('₹$perMonthFormatted/mo', style: GoogleFonts.lato(fontSize: 13.5, fontWeight: FontWeight.bold, color: const Color(0xFF1E293B))),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Disclaimer text
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'This extends your stay by $selectedMonths months and debits ₹$totalFormatted from your wallet.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF4B5563)),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Buttons: Cancel & Confirm & Pay
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: const Color(0xFFDEE2E6),
                                foregroundColor: const Color(0xFF1E293B),
                                side: const BorderSide(color: Color(0xFFCED4DA)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: () {
                                if (!hasEnoughBalance) {
                                  Navigator.pop(ctx);
                                  TopNotification.showInsufficientBalance(
                                    context,
                                    currentBalance: user.walletBalance,
                                    requiredAmount: selectedTotal,
                                    onTopUp: () => _navigateToStudentWallet(context, user),
                                  );
                                  return;
                                }
                                _handleHostelRenewal(
                                  ctx,
                                  totalAmount: selectedTotal,
                                  months: selectedMonths,
                                  roomRent: selectedRent,
                                  food: selectedFood,
                                  premiumMultiplier: selectedMultiplier,
                                  user: user,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.sync, size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Confirm & Pay ₹$totalFormatted',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
          },
        );
      },
    );
  }

  Widget _buildDurationCard({
    required Map<String, dynamic> option,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final int months = option['months'] ?? 12;
    final String multiplier = option['multiplier'] ?? '';
    final num total = option['total'] ?? 0;
    final String formattedTotal = NumberFormat('#,##,###').format(total.toInt());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFFCBD5E1),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    )
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$months months',
                    style: GoogleFonts.lato(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF1E293B),
                    ),
                  ),
                  if (multiplier.isNotEmpty)
                    Text(
                      multiplier,
                      style: GoogleFonts.lato(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '₹$formattedTotal',
                style: GoogleFonts.lato(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToStudentWallet(BuildContext context, UserProvider user) {
    final mainResponsive = context.findAncestorStateOfType<MainResponsiveLayoutState>();
    if (mainResponsive != null) {
      mainResponsive.setSelectedIndex(user.role == UserRole.guest ? 1 : 2);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StudentWalletScreen()),
      );
    }
  }

  Future<void> _handleHostelRenewal(
    BuildContext ctx, {
    required double totalAmount,
    required int months,
    required double roomRent,
    required double food,
    required double premiumMultiplier,
    required UserProvider user,
  }) async {
    Navigator.pop(ctx);
    final regNo = user.username.isNotEmpty ? user.username : user.studentId;
    final email = user.email.isNotEmpty ? user.email : (regNo.contains('@') ? regNo : '$regNo.simats@saveetha.com');
    final studentId = user.dbId ?? 0;

    try {
      final res = await ApiService.renewHostelWithWallet(
        regNo: regNo,
        email: email,
        studentId: studentId,
        amount: totalAmount,
        months: months,
        roomRent: roomRent,
        food: food,
        premiumMultiplier: premiumMultiplier,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        await user.refreshUserData();
        TopNotification.showSuccess(
          context,
          title: 'Stay Extended! 🎉',
          message: res['message'] ?? 'Renewal successful! Stay extended by $months months.',
        );
      } else if (res['renewal_expired'] == true) {
        TopNotification.showError(
          context,
          title: 'Renewal Window Closed',
          message: res['message'] ?? 'Renewal deadline has expired. Please apply freshly via VStudy.',
        );
      } else if (res['insufficient_balance'] == true) {
        final double curBal = (res['current_balance'] != null)
            ? (double.tryParse(res['current_balance'].toString()) ?? user.walletBalance)
            : user.walletBalance;
        final double reqAmt = (res['required_amount'] != null)
            ? (double.tryParse(res['required_amount'].toString()) ?? totalAmount)
            : totalAmount;

        TopNotification.showInsufficientBalance(
          context,
          currentBalance: curBal,
          requiredAmount: reqAmt,
          onTopUp: () => _navigateToStudentWallet(context, user),
        );
      } else {
        TopNotification.showError(
          context,
          title: 'Renewal Failed',
          message: res['message'] ?? 'Unable to process renewal. Please try again.',
        );
      }
    } catch (e) {
      if (mounted) {
        TopNotification.showError(
          context,
          title: 'Renewal Error',
          message: 'An error occurred while processing renewal: ${e.toString()}',
        );
      }
    }
  }

  Widget _buildRenewDetailRow(String label, String value, {bool isBold = false, bool isGrey = false, bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 14 : 13,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            color: isTotal ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 16 : 13,
            fontWeight: isBold || isTotal ? FontWeight.bold : FontWeight.w600,
            color: isGrey ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHeader(UserProvider user) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    String initials = "VS";
    if (user.userName.trim().isNotEmpty) {
      final parts = user.userName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        initials = (parts[0][0] + parts[1][0]).toUpperCase();
      } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
        initials = parts[0][0].toUpperCase();
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
                GestureDetector(
                  onTap: _scrollName,
                  child: SizedBox(
                    height: 20,
                    child: SingleChildScrollView(
                      controller: _nameScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Text(
                        (user.isParent ? user.linkedStudentName : user.userName).toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'Lato', 
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'ID: ${user.username}',
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

  Future<void> _showRenewalDialog(BuildContext context, UserProvider user) async {
    if (user.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Renewal is not available for temporary stay.')),
      );
      return;
    }
    if (user.renewalDate != null) {
      final DateTime renewDeadline = DateTime(
        user.renewalDate!.year,
        user.renewalDate!.month,
        user.renewalDate!.day,
        23, 59, 59,
      );
      if (DateTime.now().isAfter(renewDeadline)) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.timer_off_outlined, color: Colors.red),
                SizedBox(width: 8),
                Text('Renewal Window Closed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(
              'The renewal deadline for your room expired on ${DateFormat('dd MMM yyyy').format(user.renewalDate!)} at 11:59 PM.\n\nSince the renewal date has passed, late renewal is not permitted and the room is released for new bookings.\n\nIf you need accommodation, please apply freshly via the VStudy portal.',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        return;
      }
    }
    if (user.hasBadConduct) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Renewal Blocked'),
          content: const Text('Due to conduct issues, renewal requires special permission from the Dean or Warden.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }
    await _fetchRoomChangeStatus();
    _updateOverlayState(showRoomOptionsModal: true);
  }

  Future<void> _handleRoomChangePressed(BuildContext context, UserProvider user) async {
    // Block new request if a previous one is already approved but not paid yet
    final status = _roomChangeStatus.toLowerCase();
    if (status == 'approved' || status == 'pre_approved') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.block, color: Color(0xFFD4AF37), size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Request Blocked',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: const Text(
            'You cannot submit a new room change request because your previous request has been approved by the warden.\n\nPlease complete the payment for your approved room change first. Once the payment is done, you can submit a new room change request.',
            style: TextStyle(fontSize: 13, color: Color(0xFF555555), height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // Use Stack overlay instead of showDialog — avoids Navigator.pop accidentally
    // dismissing the renewal modal on desktop layouts with nested navigators.
    setState(() => _isCheckingWarden = true);

    try {
      final response = await ApiService.getAssignedStaff(user.dbId!);

      if (!mounted) return;
      setState(() => _isCheckingWarden = false);

      if (response['success'] == true && response['data'] != null) {
        final warden = response['data']['warden'];
        if (warden == null) {
          // No floorwise warden — show alert; renewal modal stays open underneath
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Warden Not Assigned'),
              content: const Text(
                'Warden not assigned. You cannot request a room change until a floorwise warden is assigned.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      } else {
        throw Exception('Failed to verify warden assignment.');
      }

      // Warden is assigned — close the modal and open the vacancy browser
      _updateOverlayState(showRoomOptionsModal: false, showVacancyBrowser: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCheckingWarden = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }


  void _showRoomDetails(Map<String, dynamic>? allocation) {
    if (allocation == null) return;
    
    final bool isPaid = allocation['allocation_status'] == 'approved';
    final user = Provider.of<UserProvider>(context, listen: false);

    ds.SkeuomorphicModal.show(
      context,
      title: 'Room Details',
      child: Column(
        children: [
          // Hero strip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ds.RoyalTheme.primaryGoldStart.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ds.RoyalTheme.primaryGoldStart,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.apartment, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Room ${allocation['room_no'] ?? allocation['room_allocation'] ?? 'N/A'}',
                        style: GoogleFonts.lato(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Block ${allocation['building_code'] ?? allocation['block'] ?? ''} • ${allocation['floor'] ?? allocation['floor_name'] ?? ''} Floor',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Details List
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
            ),
            child: Column(
              children: [
                _buildDetailRow('Capacity', allocation['room_type'] ?? 'N/A'),
                _buildDivider(),
                _buildDetailRow('Block', allocation['building_code'] ?? allocation['block'] ?? 'N/A'),
                _buildDivider(),
                _buildDetailRow('Floor', allocation['floor'] ?? allocation['floor_name'] ?? 'N/A'),
                _buildDivider(),
                _buildDetailRow('Amenities', allocation['facility'] ?? allocation['amenities'] ?? 'Wi-Fi, AC, Attached Bath'),
                if (isPaid && allocation['paid_at'] != null) ...[
                  _buildDivider(),
                  _buildDetailRow('Paid On', allocation['paid_at'].toString().split(' ')[0]),
                ],
              ],
            ),
          ),
          
          if (!isPaid) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Text('Held 24h — Pending Payment', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (context.read<AllocationProvider>().allocation?['allocated_bed_no'] != null) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                'New student allocations are final and cannot be modified.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFC5A358),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ] else if (!user.isGuest) ...[
          // Renew / Room Options button temporarily hidden for production release
        ],
        const SizedBox(height: 8),
        ds.SkeuomorphicButton(
          text: 'Close',
          isPrimary: false,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildDivider() => Divider(height: 1, color: Colors.black.withOpacity(0.05), indent: 16, endIndent: 16);

  Widget _buildStatusPill(int days, {bool isTemporary = false}) {
    if (isTemporary) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          "TEMP",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E88E5),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF059669),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        "Active",
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildEnrolledBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD4AF37), Color(0xFFA67C1E)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4AF37).withOpacity(0.35),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 13, color: Colors.white),
          SizedBox(width: 4),
          Text(
            "Enrolled",
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationEntryCard(BuildContext context, UserProvider user) {
    final alloc = context.watch<AllocationProvider>();
    final status = alloc.allocationStatus;
    
    // Status definitions
    bool hasDraft = status == 'draft';
    bool inProcess = status == 'submitted';
    bool needsPayment = status == 'payment_pending';
    bool isExpired = status == 'payment_expired';
    bool isAllocated = status == 'approved' || status == 'confirmed' || user.isRoomAllocated;

    // UI Configuration based on status
    String title = 'Apply for Room';
    String subtitle = 'Pick your preferred room';
    IconData icon = Icons.bed_outlined;
    LinearGradient gradient = ds.RoyalTheme.goldGradient;

    if (isAllocated) {
      title = 'Room Allocation Confirmed';
      subtitle = 'View your room details';
      icon = Icons.verified_user;
      gradient = ds.RoyalTheme.goldGradient;
    } else if (needsPayment) {
      title = 'Payment Pending';
      subtitle = 'Complete payment to secure your room';
      icon = Icons.payment_outlined;
      gradient = ds.RoyalTheme.navyGradient;
    } else if (inProcess) {
      title = 'Allocation in Progress';
      subtitle = 'Warden is reviewing your request';
      icon = Icons.hourglass_top_outlined;
      gradient = ds.RoyalTheme.navyGradient;
    } else if (hasDraft) {
      title = 'Manage Priorities';
      subtitle = '${alloc.preferences.length} rooms in your queue';
      icon = Icons.list_alt_outlined;
      gradient = ds.RoyalTheme.goldGradient;
    } else if (isExpired) {
      title = 'Hold Expired';
      subtitle = 'Payment window closed. Re-apply now.';
      icon = Icons.timer_off_outlined;
      gradient = ds.RoyalTheme.navyGradient;
    } else {
      title = 'Browse Rooms';
      subtitle = 'View vacancies and apply';
      icon = Icons.search_outlined;
      gradient = ds.RoyalTheme.goldGradient;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ds.SkeuomorphicCard(
        onTap: () async {
          if (isAllocated || inProcess || needsPayment || isExpired) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: '/allocation_status'),
                builder: (_) => const AllocationStatusScreen(),
              ),
            );
            if (user.dbId != null) {
              Provider.of<AllocationProvider>(context, listen: false).loadAllocation(user.dbId!);
            }
          } else {
            await Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: '/allocation_explorer'),
                builder: (_) => const AllocationExplorerScreen(),
              ),
            );
            if (user.dbId != null) {
              Provider.of<AllocationProvider>(context, listen: false).loadAllocation(user.dbId!);
            }
          }
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceAttendanceCard(BuildContext context, UserProvider user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(name: '/face_attendance'),
                builder: (_) => const FaceAttendanceScreen(initialMode: FaceScanMode.punch),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A2744),
                  Color(0xFF2A3A5C),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F1A2E).withOpacity(0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Gold square scan-face icon on the left
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFE8D48A),
                        Color(0xFFD4AF37),
                        Color(0xFFB8962E),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF8B7025),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.face_retouching_natural,
                    color: Color(0xFF3D2E0A),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),

                // Center texts: "Face Biometric" & "Touch to Check-In / Check-Out"
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Face Biometric',
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Touch to Check-In / Check-Out',
                        style: GoogleFonts.lato(
                          fontSize: 12.5,
                          color: const Color(0xFFC8D2E0),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                // Right arrow indicator
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFD4AF37),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllocationCard(BuildContext context, UserProvider user) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;
    final isTemp = user.temporaryStayRequest != null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final renewDay = user.renewalDate != null
        ? DateTime(user.renewalDate!.year, user.renewalDate!.month, user.renewalDate!.day)
        : null;
    final int rawDays = renewDay != null ? renewDay.difference(today).inDays : 0;
    final int daysRemaining = user.renewalDate != null
        ? (rawDays > 0 ? rawDays : (user.renewalDate!.isAfter(now) ? 1 : 0))
        : 0;
    final String displayRoom = user.isParent
        ? user.linkedStudentRoom
        : (user.roomAllocation.isNotEmpty
            ? user.roomAllocation
            : user.roomNumber);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: InkWell(
        onTap: () {
          if (user.isParent) return;
          
          final allocProvider = context.read<AllocationProvider>();
          if (allocProvider.allocationStatus == 'payment_pending') {
             Navigator.push(
               context,
               MaterialPageRoute(
                 settings: const RouteSettings(name: '/allocation_status'),
                 builder: (_) => const AllocationStatusScreen(),
               ),
             );
             return;
          }

          _updateOverlayState(showRoomOptionsModal: true);
        },
        borderRadius: BorderRadius.circular(25),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 15),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF0141C2B) : const Color(0xFFF9F6F0),
            borderRadius: BorderRadius.circular(20),
            border: isDark
                ? Border.all(color: Colors.white.withOpacity(0.12), width: 1.2)
                : null,
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.45) : Colors.black.withOpacity(0.08),
                blurRadius: isDark ? 18 : 10,
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
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC5A358),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.home, color: Color(0xFF2D1E17), size: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Room Allocation',
                                style: TextStyle(
                                  fontFamily: 'Lato',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                displayRoom
                                    .replaceAll(' - ', '-')
                                    .replaceAll('- ', '-')
                                    .replaceAll(' ', '')
                                    .replaceAll('T-32', 'T32')
                                    .trim(),
                                style: TextStyle(
                                  fontSize: 13, 
                                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600, 
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isFaceEnrolled) ...[
                          _buildEnrolledBadge(),
                          const SizedBox(width: 6),
                        ],
                        _buildStatusPill(
                          daysRemaining,
                          isTemporary: isTemp,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildDateBox('Check-in', user.checkInDate, Icons.calendar_today_outlined, isDark: isDark),
                  const SizedBox(width: 12),
                  _buildDateBox(isTemp ? 'Valid Till' : 'Renewal Due', user.renewalDate, Icons.calendar_month_outlined, isDark: isDark),
                ],
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.15)),
              const SizedBox(height: 15),
              Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '${daysRemaining > 0 ? daysRemaining : 0}',
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFFDE047) : const Color(0xFFC5A358), 
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'days remaining',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Lato',
                    ),
                  ),
                  const Spacer(),
                  if (!user.isParent && 
                      _roomChangeStatus.toLowerCase() != 'none' && 
                      _roomChangeStatus.isNotEmpty) ...[
                    Flexible(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _updateOverlayState(showRoomOptionsModal: true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFF43A047).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark ? const Color(0xFF34D399).withOpacity(0.6) : const Color(0xFF43A047).withOpacity(0.4), 
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  _roomChangeStatus.toLowerCase() == 'pending' 
                                      ? 'Pending Request' 
                                      : (_roomChangeStatus.toLowerCase() == 'pre_approved' 
                                          ? 'Awaiting Payment' 
                                          : (_roomChangeStatus.toLowerCase() == 'approved' 
                                              ? 'Request Approved' 
                                              : (_roomChangeStatus.toLowerCase() == 'rejected' 
                                                  ? 'Request Rejected' 
                                                  : 'Proceed to Payment'))),
                                  textAlign: TextAlign.right,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
                                    fontFamily: 'Lato',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateBox(String label, DateTime? date, IconData icon, {bool isDark = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B).withOpacity(0.9) : const Color(0xFFFDF9F0), 
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE8E0D5), 
            width: 1,
          ), 
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8E8E8E)),
                const SizedBox(width: 6),
                Text(
                  label, 
                  style: TextStyle(
                    fontSize: 12, 
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF8E8E8E), 
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              date != null ? DateFormat('d MMM yyyy').format(date) : 'N/A',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF003366), 
                fontFamily: 'Lato',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    final wallpaper = context.watch<WallpaperProvider>();
    final headingColor = wallpaper.sectionHeaderColor;
    final subColor = wallpaper.subHeadingColor;
    final iconColor = wallpaper.headerIconColor;
    final borderColor = wallpaper.headerBorderColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: headingColor,
              fontFamily: 'Lato',
              letterSpacing: 0.2,
              shadows: wallpaper.isDarkTheme
                  ? const [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      )
                    ]
                  : null,
            ),
          ),
          if (context.read<UserProvider>().dbId != null)
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => StudentRoomChangeHistoryDialog(studentId: context.read<UserProvider>().dbId ?? 0),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: wallpaper.isDarkTheme ? Colors.white.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.history,
                      size: 13,
                      color: iconColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'View History',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                        fontFamily: 'Lato',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleServiceClick(BuildContext context, String category, String subcategory) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final bool isParent = user.isParent;
    final String normalizedCat = category.toLowerCase();

    if (isParent && (normalizedCat == 'security' || normalizedCat == 'maintenance')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Access denied: Parents cannot access Security or Maintenance services'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    
    final ui = Provider.of<UIProvider>(context, listen: false);
    final isDesktop = MediaQuery.of(context).size.width >= 768;
    
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);

    final String roleKey = category.toLowerCase();
    if (isDesktop) {
      ui.setActiveChatChannel(category);
      return;
    }

    Widget target;
    if (normalizedCat == 'warden') {
      target = isParent ? ParentWardenChatScreen(department: category) : WardenChatScreen(department: category);
    } else if (normalizedCat == 'security') {
      target = SecurityChatScreen(department: category);
    } else {
      target = MaintenanceChatScreen(department: category);
    }
    
    await Navigator.push(context, MaterialPageRoute(
      builder: (context) => target,
      settings: RouteSettings(name: '/chat_$normalizedCat'),
    ));
    if (context.mounted) {
      context.read<CategoryProvider>().fetchCounts(
        studentUsername: user.username,
      );
    }
  }

  Widget _buildQuickActions(BuildContext context) {
    final catProvider = context.watch<CategoryProvider>();
    final categories = catProvider.categories;
    final user = Provider.of<UserProvider>(context, listen: false);
    final bool isParent = user.isParent;

    final List<Map<String, dynamic>> actions = categories.where((cat) {
      if (isParent) {
        final name = cat['name']?.toString().toLowerCase() ?? '';
        return name == 'warden';
      }
      return true;
    }).map((cat) {
      final name = cat['name']?.toString() ?? 'Unnamed';
      final iconStr = cat['icon']?.toString() ?? cat['icon_name']?.toString() ?? name;
      
      String displayTitle = name; // 🔥 Keep it as 'Warden' for parent login as requested

      return <String, dynamic>{
        "title": displayTitle,
        "icon": catProvider.getIconData(iconStr),
        "color": catProvider.getColor(cat['color']?.toString() ?? cat['color_hex']?.toString()),
        "count": catProvider.getUnreadCount(name),
        "onTap": () => _handleServiceClick(context, name, 'General Inquiry')
      };
    }).toList();


    if (actions.isEmpty && !catProvider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text("No actions available")),
      );
    }

  if (MediaQuery.of(context).size.width >= 768) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: actions.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,   
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.9, 
        ),
        itemBuilder: (context, index) {
          final item = actions[index];
          return _buildCustomAction(
            item['title'] as String,
            item['icon'] as IconData,
            item['color'] as Color,
            item['count'] as int? ?? 0,
            item['onTap'] as VoidCallback,
          );
        },
      ),
    );
  }

  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    decoration: const BoxDecoration(
      color: Colors.transparent, 
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...actions.take(3).map((item) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: AspectRatio(
                aspectRatio: 0.85,
                child: _buildCustomAction(
                  item['title'] as String,
                  item['icon'] as IconData,
                  item['color'] as Color? ?? Colors.grey,
                  item['count'] as int? ?? 0,
                  item['onTap'] as VoidCallback,
                ),
              ),
            ),
          );
        }),
        // 🔥 Add empty Expanded containers as placeholders if there are less than 3 actions.
        // This ensures the single action (Warden for Parent) takes exactly 1/3 of the width,
        // matching the exact size used in Student and Warden logins.
        if (actions.length < 3)
          ...List.generate(3 - actions.length, (_) => const Expanded(child: SizedBox())),
      ],
    ),
  );
}

  IconData _getIconForCategory(String name) {
    final lowerName = name.toLowerCase();
    if (lowerName.contains('warden')) return Icons.group;
    if (lowerName.contains('security')) return Icons.security;
    if (lowerName.contains('maintenance')) return Icons.build;
    return Icons.help_outline;
  }

  Widget _buildCustomAction(
  String title,
  IconData icon,
  Color color,
  int count,
  VoidCallback onTap,
) {
  return _HoverButton(
    title: title,
    icon: icon,
    color: color,
    count: count,
    onTap: onTap,
  );
}

  Widget _buildProceedPaymentButton() {
    return const SizedBox.shrink();
  }

  Widget _buildAnnouncementsHeader() {
    final wallpaper = context.watch<WallpaperProvider>();
    final headingColor = wallpaper.sectionHeaderColor;
    final iconColor = wallpaper.headerIconColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Announcements',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: headingColor,
              fontFamily: 'Lato',
              letterSpacing: 0.2,
              shadows: wallpaper.isDarkTheme
                  ? const [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(0, 1),
                        blurRadius: 3,
                      )
                    ]
                  : null,
            ),
          ),
          Icon(Icons.notifications_none_outlined, size: 20, color: iconColor),
        ],
      ),
    );
  }

  Widget _buildAnnouncements() {
    final wallpaper = context.watch<WallpaperProvider>();

    if (_isLoadingAnnouncements) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: CircularProgressIndicator(color: wallpaper.isDarkTheme ? Colors.white : const Color(0xFFD4AF37)),
        ),
      );
    }
    
    if (_announcements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            "No announcements yet",
            style: TextStyle(
              color: wallpaper.isDarkTheme ? Colors.white70 : Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    return Column(
      children: _announcements.map((a) => _buildAnnouncementCard(
        title: a['title'] ?? '',
        date: a['date'] ?? '',
        description: a['content'] ?? '',
        wardenName: a['warden_name'],
      )).toList(),
    );
  }

  Widget _buildAnnouncementCard({
    required String title,
    required String date,
    required String description,
    String? wardenName,
  }) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(12), 
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF0141C2B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.06),
            blurRadius: isDark ? 10 : 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700, 
                    fontSize: 13, 
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                (wardenName != null && wardenName.trim().isNotEmpty) ? '$wardenName · $date' : date, 
                style: TextStyle(
                  fontSize: 11, 
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description, 
            style: TextStyle(
              fontSize: 12, 
              color: isDark ? const Color(0xFFCBD5E1) : Colors.grey.shade600, 
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewStudentAllocationCard(BuildContext context, UserProvider user) {
    final alloc = context.watch<AllocationProvider>();
    final status = alloc.allocationStatus;
    final paidData = alloc.paidHostelData;

    if (alloc.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
        ),
      );
    }

    if (status == 'under_review') {
      final roomNo = alloc.allocation?['room_no'] ?? 'Calculating...';
      final block = alloc.allocation?['building_code'] ?? 'Calculating...';
      final bed = alloc.allocation?['allocated_bed_no'] ?? 'Calculating...';
      final roomType = alloc.allocation?['room_type'] ?? 'Premium Room';
      final facility = alloc.allocation?['facility'] ?? 'AC';

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: ds.SkeuomorphicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: ds.RoyalTheme.navyGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.hourglass_top, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested Room Allocation',
                          style: GoogleFonts.lato(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: const Color(0xFF1B2B48),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Pending Warden Approval',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFC5A358),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.grey.withOpacity(0.15)),
              const SizedBox(height: 16),
              const Text(
                'A matching room and bed have been automatically reserved for you based on your paid hostel type.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF9F0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8E0D5)),
                ),
                child: Column(
                  children: [
                    _buildRowDetail('Suggested Room', 'Room $roomNo ($block Block)'),
                    const SizedBox(height: 8),
                    _buildRowDetail('Suggested Bed', 'Bed $bed'),
                    const SizedBox(height: 8),
                    _buildRowDetail('Room Category', roomType),
                    const SizedBox(height: 8),
                    _buildRowDetail('Facility', facility),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFC5A358),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Warden is reviewing your suggested allocation...',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Paid hostel loading / error / not-found states ─────────────────────
    if (paidData == null) {
      // Trigger fetch once (guard inside provider prevents re-entry)
      if (!alloc.paidFetchDone && !alloc.paidFetchLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<AllocationProvider>().fetchPaidHostelType(user.username);
        });
      }

      if (alloc.paidFetchLoading) {
        // In-flight: show spinner
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: const ds.SkeuomorphicCard(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    SizedBox(height: 12),
                    Text(
                      'Fetching paid hostel specifications…',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      // Error or not-found state
      final errorMsg = alloc.paidFetchError;
      final httpStatus = alloc.paidFetchHttpStatus;

      if (errorMsg != null || alloc.paidFetchDone) {
        final is404 = httpStatus == 404;
        final isRetryable = !is404; // 503, 0 (timeout/network) are retryable

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: ds.SkeuomorphicCard(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    is404 ? Icons.info_outline : Icons.error_outline,
                    color: is404 ? Colors.grey : Colors.orange.shade700,
                    size: 36,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    is404
                        ? 'No paid hostel application found for this roll number.'
                        : (errorMsg ?? 'Unable to fetch payment details.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: is404 ? Colors.grey : Colors.red.shade700,
                      height: 1.4,
                    ),
                  ),
                  if (isRetryable) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        context.read<AllocationProvider>().resetPaidFetch();
                        context.read<AllocationProvider>().fetchPaidHostelType(user.username);
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A2744),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }

      // Still not triggered yet (first frame) — show brief loading
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: const ds.SkeuomorphicCard(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
          ),
        ),
      );
    }

    final hType = paidData['hostel_type'] ?? 'Girls';
    final hostelName = paidData['hostel_name'] ?? hType;
    final rType = paidData['room_type'] ?? 'AC - B ATTACHED (6 IN 1)';
    final facility = paidData['facility'] ?? 'AC';
    final amount = paidData['paid_amount'] ?? 68000.00;
    final inst = paidData['institution'] ?? 'Saveetha School of Engineering';

    final paymentStatus = paidData['payment_status'] ?? 'Paid';
    final appStatus = paidData['application_status'] ?? 'Application Verified';
    final gender = paidData['gender'] ?? (hType == 'Girls' ? 'Female' : 'Male');
    final academicYear = paidData['academic_year'] ?? '1st Year';
    final hostelPref = paidData['hostel_preference'] ?? rType;

    final bool hasRoomAllocation = paidData['has_room_allocation'] == true;
    final bool isPaid = paymentStatus.toString().toLowerCase() == 'paid';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ds.SkeuomorphicCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: ds.RoyalTheme.goldGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hostel Fee Paid',
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: const Color(0xFF1B2B48),
                        ),
                      ),
                      Text(
                        appStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: isPaid ? Colors.green.shade700 : Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(height: 1, color: Colors.grey.withOpacity(0.15)),
            const SizedBox(height: 16),
            const Text(
              'Your hostel fee payment has been successfully verified. Please review your paid hostel specifications and request your room allocation below.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFDF9F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8E0D5)),
              ),
              child: Column(
                children: [
                  _buildRowDetail('Paid Status', paymentStatus),
                  const SizedBox(height: 8),
                  _buildRowDetail('Hostel Name', hostelName),
                  const SizedBox(height: 8),
                  _buildRowDetail('Hostel Preference', hostelPref),
                  const SizedBox(height: 8),
                  _buildRowDetail('Institution', inst),
                  const SizedBox(height: 8),
                  _buildRowDetail('Gender', gender),
                  const SizedBox(height: 8),
                  _buildRowDetail('Academic Year', academicYear),
                  const SizedBox(height: 8),
                  _buildRowDetail('Fee Paid', '₹${amount.toStringAsFixed(2)}'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ds.SkeuomorphicButton(
              text: hasRoomAllocation ? 'Request Room Allocation' : 'Contact Hostel Warden',
              onPressed: hasRoomAllocation && isPaid ? () async {
                setState(() => _isCheckingWarden = true);
                final response = await alloc.requestNewStudentAllocation(user.dbId!, user.username);
                if (mounted) {
                  setState(() => _isCheckingWarden = false);
                  if (response['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(response['message'] ?? 'Suggested allocation generated!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    user.refreshUserData();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(response['message'] ?? 'Failed to request allocation'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              } : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowDetail(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B2B48)),
          ),
        ),
      ],
    );
  }

  Widget _buildTemporaryStayCard(BuildContext context, UserProvider user) {
    final req = user.temporaryStayRequest;
    if (req == null) return const SizedBox.shrink();

    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final paymentStatus = (req['payment_status'] ?? 'unpaid').toString().toLowerCase();
    final double rawAmount = (req['amount'] != null) ? double.tryParse(req['amount'].toString()) ?? 0.0 : 0.0;
    final int roundedAmt = (rawAmount / 50.0).round() * 50;
    final String amountStr = roundedAmt > 0 ? '₹${NumberFormat('#,##,###').format(roundedAmt)}' : (rawAmount > 0 ? '₹${rawAmount.toInt()}' : 'Calculating...');
    final String roomCodeDisplay = (req['room_code'] != null && req['room_code'].toString().isNotEmpty)
        ? req['room_code']
        : (req['room_no'] ?? 'N/A');
    final String wardenName = req['warden_name'] ?? 'Assigned Room Warden';
    final int holdRemainingSeconds = int.tryParse(req['hold_remaining_seconds']?.toString() ?? '0') ?? 0;

    int currentStep = 1;
    if (status == 'approved' && paymentStatus != 'paid') {
      currentStep = 3;
    } else if (status == 'allocated' || paymentStatus == 'paid') {
      currentStep = 4;
    } else if (status == 'rejected' || status == 'timed_out') {
      currentStep = 2;
    } else {
      currentStep = 2; // pending warden review
    }

    IconData statusIcon = Icons.hourglass_top_rounded;
    Color statusColor = const Color(0xFFD97706);
    String statusTitle = 'Application Submitted';
    String statusSubtitle = 'Pending Warden Approval';
    Color bannerBg = const Color(0xFFFEF3C7);

    if (status == 'approved' && paymentStatus != 'paid') {
      statusIcon = Icons.timer_outlined;
      statusColor = const Color(0xFF0288D1);
      statusTitle = 'Approved — Room on 24h Hold';
      statusSubtitle = 'Payment Required to Allocate Room';
      bannerBg = const Color(0xFFE0F2FE);
    } else if (status == 'allocated' || paymentStatus == 'paid') {
      statusIcon = Icons.vpn_key_rounded;
      statusColor = const Color(0xFF10B981);
      statusTitle = 'Room Allocated & Confirmed!';
      statusSubtitle = 'Temporary Stay Active';
      bannerBg = const Color(0xFFD1FAE5);
    } else if (status == 'rejected') {
      statusIcon = Icons.cancel_outlined;
      statusColor = const Color(0xFFEF4444);
      statusTitle = 'Application Rejected';
      statusSubtitle = req['admin_notes'] ?? 'Rejected by Hostel Administration';
      bannerBg = const Color(0xFFFEE2E2);
    } else if (status == 'timed_out') {
      statusIcon = Icons.timer_off_outlined;
      statusColor = const Color(0xFF6B7280);
      statusTitle = 'Hold Period Expired';
      statusSubtitle = '24-hour payment window timed out';
      bannerBg = const Color(0xFFF3F4F6);
    }

    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF0141C2B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : statusColor.withOpacity(0.3), 
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header Row with Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? statusColor.withOpacity(0.2) : bannerBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(statusIcon, color: isDark ? const Color(0xFF38BDF8) : statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF1B2B48),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFF94A3B8) : statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (status == 'approved' && holdRemainingSeconds > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${holdRemainingSeconds ~/ 3600}h left',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Visual 4-Step Stepper Progress Bar
          _buildLifecycleStepper(status, paymentStatus),
          const SizedBox(height: 16),

          // 3. Details Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B).withOpacity(0.85) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _tempCardRow('Hostel & Room', '${req['hostel_name'] ?? 'Hostel'} • $roomCodeDisplay', isDark: isDark),
                Divider(height: 14, color: isDark ? Colors.white.withOpacity(0.08) : null),
                _tempCardRow('Room Warden', wardenName, isDark: isDark),
                Divider(height: 14, color: isDark ? Colors.white.withOpacity(0.08) : null),
                _tempCardRow('Stay Duration', '${req['duration_value']} ${req['duration_type']} (${req['from_date']} to ${req['to_date']})', fontSize: 11, isDark: isDark),
                Divider(height: 14, color: isDark ? Colors.white.withOpacity(0.08) : null),
                _tempCardRow('Total Stay Fee', amountStr, isDark: isDark),
              ],
            ),
          ),

          // 4. Action Buttons based on status
          if (status == 'approved' && paymentStatus != 'paid') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0288D1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.account_balance_wallet, size: 20),
                label: Text(
                  'Go to Wallet & Pay ($amountStr)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () => _navigateToStudentWallet(context, user),
              ),
            ),
          ] else if (status == 'rejected' || status == 'timed_out') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B2B48),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text(
                  'Reapply for Temporary Stay',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => TemporaryStayDialog(
                      googleEmail: user.email,
                      googleName: user.userName,
                    ),
                  ).then((_) {
                    user.refreshUserData();
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLifecycleStepper(String status, String paymentStatus) {
    bool isAppliedDone = true;
    bool isWardenDone = status == 'approved' || status == 'allocated' || paymentStatus == 'paid';
    bool isWardenPending = status == 'pending';
    bool isPaymentDone = status == 'allocated' || paymentStatus == 'paid';
    bool isPaymentActive = status == 'approved' && paymentStatus != 'paid';
    bool isAllocatedDone = status == 'allocated' || paymentStatus == 'paid';

    return Row(
      children: [
        _stepperNode('Applied', isDone: isAppliedDone, isActive: false),
        _stepperLine(isDone: isWardenDone),
        _stepperNode('Warden', isDone: isWardenDone, isActive: isWardenPending),
        _stepperLine(isDone: isPaymentDone),
        _stepperNode('Payment', isDone: isPaymentDone, isActive: isPaymentActive),
        _stepperLine(isDone: isAllocatedDone),
        _stepperNode('Allocated', isDone: isAllocatedDone, isActive: false),
      ],
    );
  }

  Widget _stepperNode(String label, {required bool isDone, required bool isActive}) {
    Color bg = const Color(0xFFE2E8F0);
    Color fg = const Color(0xFF64748B);
    IconData icon = Icons.circle;

    if (isDone) {
      bg = const Color(0xFF10B981);
      fg = Colors.white;
      icon = Icons.check;
    } else if (isActive) {
      bg = const Color(0xFF0288D1);
      fg = Colors.white;
      icon = Icons.hourglass_bottom;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(icon, color: fg, size: 14),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: isDone || isActive ? FontWeight.bold : FontWeight.normal,
            color: isDone ? const Color(0xFF10B981) : (isActive ? const Color(0xFF0288D1) : const Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Widget _stepperLine({required bool isDone}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 14),
        color: isDone ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
      ),
    );
  }

  Widget _tempCardRow(String label, String value, {double fontSize = 12.5, bool isDark = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : Colors.grey, fontSize: 12.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: fontSize, 
              color: isDark ? Colors.white : const Color(0xFF1B2B48),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _HoverButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final VoidCallback onTap;

  const _HoverButton({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.onTap,
  });

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool isHovering = false;

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovering = true),
      onExit: (_) => setState(() => isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, isHovering ? -5 : 0, 0),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF0141C2B) : Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: isDark
                ? Border.all(color: Colors.white.withOpacity(0.12), width: 1)
                : null,
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black.withOpacity(0.4) : Colors.black.withOpacity(0.06),
                blurRadius: isDark ? 14 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.color,
                          HSLColor.fromColor(widget.color)
                              .withLightness(
                                (HSLColor.fromColor(widget.color).lightness - 0.15).clamp(0.0, 1.0),
                              )
                              .toColor(),
                        ],
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  if (widget.count > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Center(
                          child: Text(
                            '${widget.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isDark ? FontWeight.w600 : FontWeight.w500,
                    color: isDark ? Colors.white : const Color(0xFF4A4A4A),
                    fontFamily: 'Lato',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Color is now driven dynamically from widget.color (set by admin in CategoryProvider)
}
