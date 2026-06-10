import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/widgets/renewal_modal.dart';
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
import '../widgets/room_change_request_status.dart';
import 'warden_chat_screen.dart';
import '../../shared/ui_provider.dart';
import 'security_chat_screen.dart';
import '../../shared/main_layout.dart';

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _announcements = [];
  bool _isLoadingAnnouncements = true;
  final ScrollController _nameScrollController = ScrollController();
  bool _isScrolling = false;
  
  bool _showRoomOptionsModal = false;
  bool _showVacancyBrowser = false;
  bool _showRenewalModal = false;
  bool _isCheckingWarden = false; // Stack-level overlay — avoids Navigator.pop issues
  String _roomChangeStatus = 'none';
  Map<String, dynamic>? _latestRoomRequest;

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
            if (mounted && !user.isRoomAllocated && allocProvider.allocationStatus == 'none') {
              allocProvider.fetchPaidHostelType(user.username);
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
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
    final user = context.watch<UserProvider>();
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Royal Residences',
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
                  if (!user.isRoomAllocated && allocProvider.allocationStatus == 'none') {
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
                    if (user.isRoomAllocated || context.watch<AllocationProvider>().allocationStatus == 'approved') ...[
                      _buildAllocationCard(context, user),
                    ] else if (!user.isParent) ...[
                      _buildNewStudentAllocationCard(context, user),
                    ],
                    const SizedBox(height: 10), 
                    RoomChangeRequestStatus(studentId: user.dbId ?? 0),
                    _buildProceedPaymentButton(),
                    _buildQuickActionsHeader(),
                    _buildQuickActions(context),
                    _buildAnnouncementsHeader(),
                    _buildAnnouncements(),
                    const SizedBox(height: 25),
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
                onTap: () => setState(() => _showVacancyBrowser = false),
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
                            setState(() {
                              _showVacancyBrowser = false;
                            });
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

          if (_showRenewalModal)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showRenewalModal = false),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: GestureDetector(
                    onTap: () {}, 
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        RenewalModal(
                          isOpen: _showRenewalModal,
                          onClose: () => setState(() => _showRenewalModal = false),
                          currentRenewalDate: user.renewalDate,
                          currentRoomTypeId: user.roomType,
                          currentRoomFacility: user.roomFacility,
                          currentRoomBathAttached: user.roomBathAttached,
                          requestStatus: _roomChangeStatus,
                          approvedRoomType: _latestRoomRequest?['requested_room_type'],
                          onRoomChangeRequested: () {
                            _handleRoomChangePressed(context, user);
                          },
                          onRenewalSuccess: (newDate, receiptNumber, amount, newRoomType) {
                            user.approveRenewal();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Renewal successful! New room: $newRoomType'),
                                backgroundColor: const Color(0xFF43A047),
                              ),
                            );
                            Navigator.push(context, MaterialPageRoute(builder: (ctx) => const PaymentPage()));
                          },
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
                          fontFamily: 'Georgia',
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showRoomOptionsModal = false;
                          });
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
                
                Container(
                  color: const Color(0xFFF9F6F0),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      InkWell(
                        onTap: () {
                          setState(() {
                            _showRoomOptionsModal = false;
                          });
                          _showRenewalDialog(context, user);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD4AF37),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.calendar_today, 
                                       color: Color(0xFF1A2744), size: 24),
                              const SizedBox(width: 12),
                              const Text(
                                'Renew Current Stay',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2744),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
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
                  fontFamily: 'Georgia',
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
                        user.isParent ? user.linkedStudentName : user.userName,
                        style: const TextStyle(
                          fontFamily: 'Playfair Display', 
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
    setState(() {
      _showRenewalModal = true;
    });
  }

  Future<void> _handleRoomChangePressed(BuildContext context, UserProvider user) async {
    // Use Stack overlay instead of showDialog — avoids Navigator.pop accidentally
    // dismissing the renewal modal on desktop layouts with nested navigators.
    setState(() => _isCheckingWarden = true);

    try {
      final response = await ApiService.getAssignedStaff(user.dbId!);

      if (!mounted) return;
      setState(() => _isCheckingWarden = false);

      if (response['success'] == true && response['data'] != null) {
        final warden = response['data']['warden'];
        if (warden == null || warden['username'] == 'warden1') {
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

      // Warden is assigned — close the renewal modal and open the vacancy browser
      setState(() {
        _showRenewalModal = false;
        _showVacancyBrowser = true;
      });
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
                        style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold),
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
        ] else ...[
          ds.SkeuomorphicButton(
            text: 'Renew / Room Options',
            onPressed: () {
              Navigator.pop(context);
              if (_roomChangeStatus.toLowerCase() == 'pre_approved') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PaymentPage(
                      requestId: _latestRoomRequest?['request_id'],
                      requestedRoom: _latestRoomRequest?['requested_room'],
                      customAmount: double.tryParse(_latestRoomRequest?['amount_to_pay']?.toString() ?? '0'),
                    ),
                  ),
                ).then((_) => _fetchRoomChangeStatus());
              } else if (_roomChangeStatus.toLowerCase() == 'pending') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Room change/renewal request is pending approval.')),
                );
              } else {
                setState(() => _showRoomOptionsModal = true);
              }
            },
          ),
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

  Widget _buildStatusPill(int days) {
    String label = "Active";
    Color color = ds.RoyalTheme.successMid;
    if (days <= 0) {
      label = "Expired";
      color = ds.RoyalTheme.dangerMid;
    } else if (days <= 30) {
      label = "Expiring Soon";
      color = ds.RoyalTheme.warningMid;
    }
    return ds.GlossyBadge(label: label, isActive: days > 0, colorOverride: color);
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
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AllocationStatusScreen()));
            if (user.dbId != null) {
              Provider.of<AllocationProvider>(context, listen: false).loadAllocation(user.dbId!);
            }
          } else {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AllocationExplorerScreen()));
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
                    style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 16),
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
             Navigator.push(context, MaterialPageRoute(builder: (_) => const AllocationStatusScreen()));
             return;
          }

          if (allocProvider.allocation != null) {
            _showRoomDetails(allocProvider.allocation);
            return;
          }
          
          // Construct fallbacks from user details
          final dynamicAllocation = {
            'room_no': user.roomNumber,
            'room_allocation': user.roomAllocation,
            'building_code': user.block,
            'block': user.block,
            'floor': user.wing,
            'floor_name': user.wing,
            'room_type': user.roomTypeDisplay,
            'facility': 'Wi-Fi, AC, Attached Bath',
            'allocation_status': 'approved',
            'paid_at': DateFormat('yyyy-MM-dd').format(user.checkInDate),
          };
          _showRoomDetails(dynamicAllocation);
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
                              fontFamily: 'Georgia',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1B2B48),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.isParent ? user.linkedStudentRoom : user.fullRoomDetails,
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
                    child: _buildStatusPill(daysRemaining),
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
                      fontFamily: 'Georgia',
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
                  if (!user.isParent) ...[
                    Flexible(
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
                                              : (_roomChangeStatus.toLowerCase() == 'completed' 
                                                  ? 'Request Completed'
                                                  : 'Tap to Renew')))),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: _roomChangeStatus.toLowerCase() == 'pre_approved' 
                                    ? const Color(0xFFC5A358) 
                                    : ((_roomChangeStatus.toLowerCase() == 'pending' || _roomChangeStatus.toLowerCase() == 'rejected') 
                                        ? Colors.orange 
                                        : const Color(0xFF43A047)),
                                fontFamily: 'Lato',
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _roomChangeStatus.toLowerCase() == 'pending' ? Icons.hourglass_empty : Icons.chevron_right, 
                            size: 18, 
                            color: _roomChangeStatus.toLowerCase() == 'pending' ? Colors.orange : const Color(0xFFC5A358)
                          ),
                        ],
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 16, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF666666),
            fontFamily: 'Lato',
            letterSpacing: 0.2,
          ),
        ),
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
    final assignedStaff = catProvider.assignedStaff;

    if (!assignedStaff.containsKey(roleKey) || assignedStaff[roleKey] == null) {
      if (mounted) {
        String capitalizedTitle = category[0].toUpperCase() + category.substring(1).toLowerCase();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$capitalizedTitle is not assigned yet.',
                    style: const TextStyle(
                      fontFamily: 'Lato',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFC5A358), 
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

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
      settings: RouteSettings(name: '/chat_${normalizedCat}'),
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
      
      String displayTitle = name; // 🔥 Keep it as 'Warden' for parent login as requested

      return <String, dynamic>{
        "title": displayTitle,
        "icon": _getIconForCategory(name),
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
      color: Color(0xFFF1EDE6), 
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
        }).toList(),
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
    if (_roomChangeStatus.toLowerCase() != 'approved') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: GestureDetector(
        onTap: () {
          final user = context.read<UserProvider>();
          _showRenewalDialog(context, user);
        },
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFFEBC15B), Color(0xFFB88E2F)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment, color: Color(0xFF291E1A), size: 20),
                SizedBox(width: 10),
                Text(
                  'Proceed Payment',
                  style: TextStyle(
                    color: Color(0xFF291E1A),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                          style: GoogleFonts.playfairDisplay(
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

    if (paidData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        alloc.fetchPaidHostelType(user.username);
      });
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: const ds.SkeuomorphicCard(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text("Fetching paid hostel specifications...")),
          ),
        ),
      );
    }

    final hType = paidData['hostel_type'] ?? 'Girls';
    final rType = paidData['room_type'] ?? 'AC - B ATTACHED (6 IN 1)';
    final facility = paidData['facility'] ?? 'AC';
    final amount = paidData['paid_amount'] ?? 68000.00;
    final inst = paidData['institution'] ?? 'Saveetha School of Engineering';

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
                        style: GoogleFonts.playfairDisplay(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: const Color(0xFF1B2B48),
                        ),
                      ),
                      Text(
                        'Application Verified',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
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
                  _buildRowDetail('Hostel Category', '$hType Hostel'),
                  const SizedBox(height: 8),
                  _buildRowDetail('Room Specification', rType),
                  const SizedBox(height: 8),
                  _buildRowDetail('Facility', facility),
                  const SizedBox(height: 8),
                  _buildRowDetail('Institution', inst),
                  const SizedBox(height: 8),
                  _buildRowDetail('Fee Paid', '₹${amount.toStringAsFixed(2)}'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ds.SkeuomorphicButton(
              text: 'Request Room Allocation',
              onPressed: () async {
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
              },
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
