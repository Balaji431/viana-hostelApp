import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
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
import 'student_wallet_screen.dart';
import 'no_due_page.dart';
import 'package:flutter/foundation.dart';

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
  bool _showRoomHistory = false;
  bool _showRenewTransferNotice = false;

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

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
    _fetchPayments();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<UserProvider>();
      user.refreshUserData().then((_) {
        if (mounted) {
          context.read<CategoryProvider>().fetchCounts(
            studentUsername: user.isParent ? user.linkedStudentUsername : user.username,
          );
        }
      });
      _fetchRoomChangeStatus();
      
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
    _fetchPayments();
    _fetchRoomChangeStatus();
    final user = context.read<UserProvider>();
    user.refreshUserData().then((_) {
      if (mounted) {
        context.read<CategoryProvider>().fetchCounts(
          studentUsername: user.isParent ? user.linkedStudentUsername : user.username,
        );
      }
    });
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
  }

  @override
  void dispose() {
    context.read<UserProvider>().removeListener(_handleGlobalRefreshListener);
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
              setState(() {
                _latestRoomRequest = studentRequests.first;
                _roomChangeStatus = _latestRoomRequest?['status'] ?? 'none';
              });
            }
        } else {
           if (mounted) setState(() => _roomChangeStatus = 'none');
        }
      }
    } catch (e) {
      debugPrint("Error fetching room change status: $e");
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
        rightAction: ProfileButton(onTap: () {
          context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(2);
        }),
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
                    if (user.isRoomAllocated || isTempStayPaid) ...[
                      // Student has a room — show ONLY the room allocation card
                      _buildAllocationCard(context, user),
                    ] else if (!user.isParent) ...[
                      // Student has NO room — show ONLY the fee paid card with Contact Hostel Warden
                      _buildNewStudentAllocationCard(context, user),
                    ],
                    const SizedBox(height: 10), 
                    const SizedBox.shrink(),
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
    final statusLower = _roomChangeStatus.toLowerCase();
    final hasActiveOrPendingRequest = _roomChangeStatus.isNotEmpty &&
        statusLower != 'none' &&
        statusLower != 'completed' &&
        statusLower != 'rejected';
    final roomType = user.roomType.isNotEmpty ? user.roomType : (user.roomTypeDisplay.isNotEmpty ? user.roomTypeDisplay : "Standard Room");
    final hostel = user.hostelName.isNotEmpty ? user.hostelName : "Vaigai Hostel";
    final roomNo = user.roomNumber.isNotEmpty ? user.roomNumber : "T-32 F02- W0-R16";
    final renewalDateStr = DateFormat('dd MMM yyyy').format(user.renewalDate);

    return Container(
      color: Colors.black.withOpacity(0.5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF9F6F0),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Bar
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9F6F0),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFFE0D8CC),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Manage Room',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2744),
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
                            color: Colors.grey.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, 
                                       size: 18, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content Body
                Container(
                  color: const Color(0xFFF9F6F0),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Image 1 Layout: Existing Room Allotted Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.king_bed_outlined, color: Color(0xFF1A2744), size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  roomType,
                                  style: GoogleFonts.lato(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1A2744),
                                  ),
                                ),
                                const Spacer(),
                                // Light Green Paid Badge (Image 1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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

                            const SizedBox(height: 4),

                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, color: Colors.grey, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '$hostel · Thandalam Campus',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),

                            Row(
                              children: [
                                const Text(
                                  'Room No: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A2744),
                                  ),
                                ),
                                Text(
                                  roomNo,
                                  style: GoogleFonts.lato(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10B981),
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
                                    const Text('Total Fee', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text('₹${NumberFormat('#,##,###').format(user.totalFee.toInt())}', style: GoogleFonts.lato(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF1A2744))),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Additional EB Charges', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 2),
                                    Text('Yes', style: GoogleFonts.lato(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A2744))),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Renewal Date', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                const SizedBox(height: 2),
                                Text(renewalDateStr, style: GoogleFonts.lato(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1A2744))),
                              ],
                            ),

                            const SizedBox(height: 14),

                            Row(
                              children: [
                                Expanded(child: _buildModalInfoBox('Amount', '₹${NumberFormat('#,##,###').format(user.roomAmount.toInt())}')),
                                const SizedBox(width: 8),
                                Expanded(child: _buildModalInfoBox('Food', '₹${NumberFormat('#,##,###').format(user.roomFood.toInt())}')),
                                const SizedBox(width: 8),
                                Expanded(child: _buildModalInfoBox('Caution', '₹${NumberFormat('#,##,###').format(user.roomCaution.toInt())}')),
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
                              color: const Color(0xFFFEF2F2),
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
                                      color: Color(0xFF991B1B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (statusLower == 'pending') ...[
                          // Pending Transfer Request Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFD97706).withOpacity(0.4)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 22),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'TRANSFER REQUEST PENDING',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFB45309),
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Your transfer request is under review by Warden Manoj A. Only 1 request allowed at a time.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF92400E),
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (statusLower == 'approved' || statusLower == 'pre_approved') ...[
                          // Approved State: Full-width Pay Now button (Renew button temporarily hidden for production release)
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
                                'Pay Now',
                                style: GoogleFonts.lato(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Renew and Transfer buttons temporarily hidden for current release
                        ],
                      ] else ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Temporary Stay allocations cannot be renewed.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade700,
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

  Widget _buildModalInfoBox(String label, String amount) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(amount, style: GoogleFonts.lato(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF1A2744))),
        ],
      ),
    );
  }

  void _showRenewBookingModal(BuildContext context, UserProvider user) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentPage(
          renewAmount: user.renewAmount,
        ),
      ),
    );
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
    String initials = "AK";
    if (user.userName.isNotEmpty) {
      final parts = user.userName.trim().split(' ');
      if (parts.length >= 2) {
        initials = (parts[0][0] + parts[1][0]).toUpperCase();
      } else {
        initials = parts[0][0].toUpperCase();
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(
        gradient: SkeuomorphicColors.royalContentGradient,
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
                    color: SkeuomorphicColors.residenceMutedText,
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

  Widget _buildAllocationCard(BuildContext context, UserProvider user) {
    final int daysRemaining = user.renewalDate.difference(DateTime.now()).inDays;
    
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
            color: const Color(0xFFF9F6F0),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
                          const Text(
                            'Room Allocation',
                            style: TextStyle(
                              fontFamily: 'Lato',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B2B48),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (user.isParent ? user.linkedStudentRoom : user.roomNumber)
                                .replaceAll(' - ', '-')
                                .replaceAll('- ', '-')
                                .replaceAll(' ', '')
                                .replaceAll('T-32', 'T32')
                                .trim(),
                            style: TextStyle(
                              fontSize: 13, 
                              color: Colors.grey.shade600, 
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
                    child: _buildStatusPill(
                      daysRemaining,
                      isTemporary: user.temporaryStayRequest != null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _buildDateBox('Check-in', user.checkInDate, Icons.calendar_today_outlined),
                  const SizedBox(width: 12),
                  _buildDateBox('Renewal Due', user.renewalDate, Icons.calendar_month_outlined),
                ],
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.grey.withOpacity(0.15)),
              const SizedBox(height: 15),
              Row(
                children: [
                  const SizedBox(width: 8),
                  Text(
                    '${daysRemaining > 0 ? daysRemaining : 0}',
                    style: const TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFC5A358), 
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'days remaining',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
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
                            color: const Color(0xFF43A047).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF43A047).withOpacity(0.4), width: 1),
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
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF2E7D32),
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

  Widget _buildDateBox(String label, DateTime date, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFDF9F0), 
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8E0D5), width: 1), 
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: const Color(0xFF8E8E8E)),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E8E), fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat('d MMM yyyy').format(date),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF003366), 
                fontFamily: 'Lato',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF666666),
              fontFamily: 'Lato',
              letterSpacing: 0.2,
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
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFCCCCCC),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.history,
                      size: 13,
                      color: Color(0xFF888888),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'View History',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF888888),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Announcements',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF666666),
              fontFamily: 'Lato',
              letterSpacing: 0.2,
            ),
          ),
          Icon(Icons.notifications_none_outlined, size: 20, color: Colors.grey.shade500),
        ],
      ),
    );
  }

  Widget _buildAnnouncements() {
    if (_isLoadingAnnouncements) {
      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    }
    
    if (_announcements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text("No announcements yet", style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
    }

    return Column(
      children: _announcements.map((a) => _buildAnnouncementCard(
        title: a['title'] ?? '',
        date: a['date'] ?? '',
        description: a['content'] ?? '',
      )).toList(),
    );
  }

  Widget _buildAnnouncementCard({required String title, required String date, required String description}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      padding: const EdgeInsets.all(12), 
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700, 
                  fontSize: 13, 
                  color: Color(0xFF1B2B48)
                ),
              ),
              Text(
                date, 
                style: const TextStyle(fontSize: 11, color: Colors.grey) 
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description, 
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4) 
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

    final status = req['status'] ?? 'pending';
    final paymentStatus = req['payment_status'] ?? 'unpaid';
    final double amount = (req['amount'] != null) ? double.tryParse(req['amount'].toString()) ?? 0.0 : 0.0;
    final String amountStr = amount > 0 ? '₹${amount.toStringAsFixed(2)}' : 'Calculating...';
    final String roomCodeDisplay = (req['room_code'] != null && req['room_code'].toString().isNotEmpty)
        ? req['room_code']
        : (req['room_no'] ?? 'N/A');

    IconData statusIcon = Icons.hourglass_top_rounded;
    Color statusColor = Colors.amber;
    String statusTitle = 'Suggested Room Allocation';
    String statusSubtitle = 'Pending Admin Approval';
    Color bannerBg = const Color(0xFFFFF8E1);

    if (status == 'approved' && paymentStatus != 'paid') {
      statusIcon = Icons.verified_rounded;
      statusColor = const Color(0xFF2E7D32);
      statusTitle = 'Temporary Stay Approved! 🎉';
      statusSubtitle = 'Payment Required to Allocate Room';
      bannerBg = const Color(0xFFE8F5E9);
    } else if (status == 'allocated' || paymentStatus == 'paid') {
      statusIcon = Icons.vpn_key_rounded;
      statusColor = const Color(0xFF1B2B48);
      statusTitle = 'Room Allocated & Confirmed! 🔑';
      statusSubtitle = 'Temporary Stay Active';
      bannerBg = const Color(0xFFE3F2FD);
    } else if (status == 'rejected') {
      statusIcon = Icons.cancel_rounded;
      statusColor = Colors.red;
      statusTitle = 'Application Rejected ❌';
      statusSubtitle = req['admin_notes'] ?? 'Administrative Decision';
      bannerBg = const Color(0xFFFFEBEE);
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bannerBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(statusIcon, color: statusColor, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1B2B48),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Details Box (matching photo)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                _tempCardRow('Hostel Name', req['hostel_name'] ?? 'N/A'),
                const Divider(height: 14),
                _tempCardRow('Suggested Room', roomCodeDisplay),
                const Divider(height: 14),
                _tempCardRow('Stay Duration', '${req['duration_value']} ${req['duration_type']} (${req['from_date']} to ${req['to_date']})', fontSize: 10.5),
                const Divider(height: 14),
                _tempCardRow('Calculated Fee', amountStr),
              ],
            ),
          ),

          if (status == 'approved' && paymentStatus != 'paid') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: const Icon(Icons.payment, size: 20),
                label: Text(
                  'Pay Now & Allocate Room ($amountStr)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                onPressed: () async {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => PaymentPage(
                        requestId: req['request_id'],
                        customAmount: amount,
                        requestedRoom: roomCodeDisplay,
                        isTemporaryStay: true,
                      ),
                    ),
                  ).then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
            ),
          ] else if (status == 'rejected') ...[
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
                      googleName: user.displayName,
                    ),
                  ).then((_) async {
                    final checkRes = await ApiService.checkTemporaryStayEmail(user.email);
                    if (checkRes['has_request'] == true && checkRes['request_details'] != null) {
                      final updatedReq = Map<String, dynamic>.from(checkRes['request_details']);
                      final freshUserData = {
                        'id': updatedReq['id'] ?? 0,
                        'username': updatedReq['email'] ?? user.email,
                        'full_name': updatedReq['full_name'] ?? user.displayName,
                        'email': user.email,
                        'role': 'guest',
                        'hostel_name': updatedReq['hostel_name'] ?? '',
                        'room_no': updatedReq['room_no'] ?? '',
                        'room_code': updatedReq['room_code'] ?? updatedReq['room_no'] ?? '',
                        'temporary_stay_request': updatedReq,
                      };
                      if (context.mounted) {
                        await user.login(freshUserData);
                        setState(() {});
                      }
                    }
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tempCardRow(String label, String value, {double fontSize = 12.5}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: fontSize, 
              color: const Color(0xFF1B2B48),
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4A4A4A),
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
