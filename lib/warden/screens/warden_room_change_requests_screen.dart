import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/models/room_change_request_model.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_widgets.dart';
import '../widgets/warden_modals.dart';

class WardenRoomChangeRequestsScreen extends StatefulWidget {
  final int wardenId;
  
  const WardenRoomChangeRequestsScreen({super.key, required this.wardenId});

  @override
  State<WardenRoomChangeRequestsScreen> createState() => _WardenRoomChangeRequestsScreenState();
}

class _WardenRoomChangeRequestsScreenState extends State<WardenRoomChangeRequestsScreen> {
  // Main Tab: 0 = Room Transfers, 1 = Vacate Requests
  int _selectedMainTab = 0;

  // Room Change Requests state
  List<RoomChangeRequest> _allRequests = [];
  bool _isLoading = true;
  String _selectedStatus = 'all'; // all, pending, approved, rejected

  // Vacate Requests state
  List<Map<String, dynamic>> _vacateRequests = [];
  bool _isLoadingVacate = true;
  String _selectedVacateStatus = 'all'; // all, pending, approved, rejected
  int _pendingVacateCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRequests();
    _loadVacateRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.getRoomChangeRequests(
        status: _selectedStatus,
        wardenUsername: user.username,
      );
      if (response['success'] == true && mounted) {
        setState(() {
          _allRequests = (response['data'] as List<dynamic>)
              .map((json) => RoomChangeRequest.fromJson(json))
              .toList();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadVacateRequests() async {
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.getWardenVacateRequests(
        wardenUsername: user.username,
        status: _selectedVacateStatus,
      );
      if (response['success'] == true && mounted) {
        final List<dynamic> raw = response['data'] ?? [];
        final list = raw.map((e) => Map<String, dynamic>.from(e)).toList();
        final pendingCnt = list.where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending').length;
        setState(() {
          _vacateRequests = list;
          _pendingVacateCount = pendingCnt;
          _isLoadingVacate = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingVacate = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingVacate = false);
    }
  }

  void _showRequestDetails(BuildContext context, RoomChangeRequest request) {
    showDialog(
      context: context,
      builder: (context) => WardenRoomChangeDetailsModal(
        request: request,
        onActionComplete: _loadRequests,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
      case 'cancelled':
        return const Color(0xFFEF4444);
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return Colors.grey;
    }
  }

  // --- Vacate Dialog & Actions ---
  void _showVacateDetailsDialog(Map<String, dynamic> req, bool isDark) {
    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final isPending = status == 'pending';
    final name = req['student_name'] ?? 'Student';
    final regNo = req['student_reg_no'] ?? '';
    final room = req['room_number'] ?? '';
    final hostel = req['hostel_name'] ?? '';
    final vacateDate = req['expected_vacate_date'] ?? '';
    final renewalDate = req['renewal_date'] ?? 'N/A';
    final remainingDays = req['remaining_days'] ?? 0;
    final reason = req['reason'] ?? '';
    final phone = req['student_phone'] ?? '';
    final parentPhone = req['parent_phone'] ?? '';
    final dept = req['department'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Container(
            padding: const EdgeInsets.all(22),
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFDC2626), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vacate Clearance Request',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              'Ref: ${req['request_id'] ?? ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Student info block
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Student Name', '$name ($regNo)', isDark),
                        if (dept.isNotEmpty) _buildDetailRow('Department', dept, isDark),
                        if (phone.isNotEmpty) _buildDetailRow('Student Phone', phone, isDark),
                        if (parentPhone.isNotEmpty) _buildDetailRow('Parent Contact', parentPhone, isDark),
                        _buildDetailRow('Allocated Room', '$room ($hostel)', isDark, isHighlight: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Dates comparison block
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF451A03).withOpacity(0.3) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                    ),
                    child: Column(
                      children: [
                        _buildDetailRow('Expected Vacate Date', vacateDate, isDark, valueColor: const Color(0xFFDC2626)),
                        _buildDetailRow('Paid Tenure Expiry', renewalDate, isDark),
                        if (remainingDays > 0)
                          _buildDetailRow('Early Vacate Diff', '$remainingDays days before tenure expiry', isDark, valueColor: const Color(0xFFD97706)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reason
                  Text('Reason for Vacating:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Text(
                      reason.isNotEmpty ? reason : 'None provided',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Free room notice
                  if (isPending)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF059669), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Approval will checkout $name and IMMEDIATELY FREE room $room for new allocations.',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Actions
                  if (isPending) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _promptRejectVacate(req);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmApproveVacate(req);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Approve & Free', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {bool isHighlight = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmApproveVacate(Map<String, dynamic> req) {
    final user = context.read<UserProvider>();
    final name = req['student_name'] ?? 'Student';
    final room = req['room_number'] ?? '';
    final reqId = req['request_id'] ?? '';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Confirm Approval'),
            ],
          ),
          content: Text(
            'Are you sure you want to approve early checkout for $name?\n\n'
            'Room $room will be marked vacated and IMMEDIATELY FREED for new student allocations.',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isLoadingVacate = true);
                try {
                  final res = await ApiService.approveVacateRequest(
                    requestId: reqId,
                    wardenUsername: user.username,
                    wardenName: user.userName,
                  );
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Request approved! Room $room is now freed and available.'),
                        backgroundColor: const Color(0xFF10B981),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res['message'] ?? 'Failed to approve.'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
                _loadVacateRequests();
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: const Text('Confirm & Free Room'),
            ),
          ],
        );
      },
    );
  }

  void _promptRejectVacate(Map<String, dynamic> req) {
    final user = context.read<UserProvider>();
    final reqId = req['request_id'] ?? '';
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reject Vacate Request'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Please specify the reason for rejection (e.g. pending dues, inspection failure):', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Enter rejection reason...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) return;
                Navigator.pop(ctx);
                setState(() => _isLoadingVacate = true);
                try {
                  final res = await ApiService.rejectVacateRequest(
                    requestId: reqId,
                    wardenUsername: user.username,
                    wardenName: user.userName,
                    rejectionReason: reason,
                  );
                  if (res['success'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vacate request rejected.'), backgroundColor: Colors.orange),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(res['message'] ?? 'Failed to reject.'), backgroundColor: Colors.red),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                  );
                }
                _loadVacateRequests();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Reject Request'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: _selectedMainTab == 0 ? 'Room Change Requests' : 'Vacate Requests',
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: () {
            if (_selectedMainTab == 0) {
              _loadRequests();
            } else {
              _loadVacateRequests();
            }
          },
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            // Top Main Tab Selector: [ Room Transfers ] | [ Vacate Requests ]
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedMainTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedMainTab == 0
                              ? (isDark ? const Color(0xFF2563EB) : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _selectedMainTab == 0
                              ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.sync_rounded,
                              size: 16,
                              color: _selectedMainTab == 0
                                  ? Colors.white
                                  : (isDark ? Colors.white60 : Colors.grey.shade700),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Room Transfers (${_allRequests.length})',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _selectedMainTab == 0 ? FontWeight.bold : FontWeight.w500,
                                color: _selectedMainTab == 0
                                    ? (isDark ? Colors.white : const Color(0xFF1E293B))
                                    : (isDark ? Colors.white60 : Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedMainTab = 1);
                        _loadVacateRequests();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _selectedMainTab == 1
                              ? (isDark ? const Color(0xFFDC2626) : Colors.white)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: _selectedMainTab == 1
                              ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.exit_to_app_rounded,
                              size: 16,
                              color: _selectedMainTab == 1
                                  ? Colors.white
                                  : (isDark ? Colors.white60 : Colors.grey.shade700),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Vacate Requests',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: _selectedMainTab == 1 ? FontWeight.bold : FontWeight.w500,
                                color: _selectedMainTab == 1
                                    ? (isDark ? Colors.white : const Color(0xFF1E293B))
                                    : (isDark ? Colors.white60 : Colors.grey.shade700),
                              ),
                            ),
                            if (_pendingVacateCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_pendingVacateCount',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Filter Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.transparent,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('all', 'All', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('pending', 'Pending', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('approved', 'Approved', isDark),
                    const SizedBox(width: 8),
                    _buildFilterChip('rejected', 'Rejected', isDark),
                  ],
                ),
              ),
            ),
            
            // Content List
            Expanded(
              child: _selectedMainTab == 0
                  ? _buildRoomChangeContent(isDark)
                  : _buildVacateContent(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomChangeContent(bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
    }
    if (_allRequests.isEmpty) {
      return Center(
        child: Text(
          'No room change requests found',
          style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allRequests.length,
      itemBuilder: (context, index) {
        return _buildRequestCard(_allRequests[index], isDark);
      },
    );
  }

  Widget _buildVacateContent(bool isDark) {
    if (_isLoadingVacate) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFDC2626)));
    }
    if (_vacateRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: isDark ? Colors.white24 : Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              'No vacate requests found',
              style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _vacateRequests.length,
      itemBuilder: (context, index) {
        return _buildVacateCard(_vacateRequests[index], isDark);
      },
    );
  }

  Widget _buildFilterChip(String value, String label, bool isDark) {
    final isSelected = _selectedMainTab == 0
        ? _selectedStatus == value
        : _selectedVacateStatus == value;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) {
          if (_selectedMainTab == 0) {
            setState(() {
              _selectedStatus = value;
              _isLoading = true;
            });
            _loadRequests();
          } else {
            setState(() {
              _selectedVacateStatus = value;
              _isLoadingVacate = true;
            });
            _loadVacateRequests();
          }
        }
      },
      selectedColor: _selectedMainTab == 0
          ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF2D4A7A))
          : const Color(0xFFDC2626),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected 
            ? (isDark ? const Color(0xFF1B2B48) : Colors.white) 
            : (isDark ? Colors.white70 : Colors.black87),
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildRequestCard(RoomChangeRequest request, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.04),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        onTap: () => _showRequestDetails(context, request),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: _getStatusColor(request.status),
          child: Text(
            request.studentName.isNotEmpty ? request.studentName[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          request.studentName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A2744),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${request.currentRoom} → ${request.requestedRoom}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (request.campus?.contains('Poonamallee') == true)
                        ? Colors.purple.withOpacity(0.15)
                        : Colors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    request.campus?.contains('Poonamallee') == true ? 'Poonamallee' : 'Thandalam',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: (request.campus?.contains('Poonamallee') == true)
                          ? (isDark ? Colors.purpleAccent : Colors.purple)
                          : (isDark ? Colors.lightBlueAccent : Colors.blue.shade700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              request.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white60 : Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        trailing: Icon(Icons.chevron_right, size: 20, color: isDark ? Colors.white60 : Colors.grey),
      ),
    );
  }

  Widget _buildVacateCard(Map<String, dynamic> req, bool isDark) {
    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final name = req['student_name'] ?? 'Student';
    final regNo = req['student_reg_no'] ?? '';
    final room = req['room_number'] ?? '';
    final hostel = req['hostel_name'] ?? '';
    final rawVacateDate = req['expected_vacate_date'] ?? '';
    final reason = req['reason'] ?? '';
    final remainingDays = req['remaining_days'] ?? 0;
    final statusColor = _getStatusColor(status);

    String formattedDate = rawVacateDate;
    if (rawVacateDate.isNotEmpty) {
      try {
        final dt = DateTime.parse(rawVacateDate);
        formattedDate = DateFormat('dd MMM yyyy').format(dt);
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withValues(alpha: 0.85) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'pending'
              ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
              : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06)),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showVacateDetailsDialog(req, isDark),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Top row: Icon + Student Name & Reg + Status Chip
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.exit_to_app_rounded, color: statusColor, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF1A2744),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            regNo,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  thickness: 0.8,
                  color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
                ),
                const SizedBox(height: 10),

                // 2. Middle Row: Room Chip + Vacating Date Chip + Early Diff Badge
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Room tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E3A8A).withValues(alpha: 0.3)
                            : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.4) : const Color(0xFFBFDBFE),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.meeting_room_outlined,
                            size: 13,
                            color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            room.isNotEmpty ? (hostel.isNotEmpty ? '$room • $hostel' : room) : 'Room N/A',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Vacating Date tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF7F1D1D).withValues(alpha: 0.25)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.4) : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 12,
                            color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Vacate: $formattedDate',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Early Vacate diff badge
                    if (remainingDays > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF78350F).withValues(alpha: 0.3)
                              : const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : const Color(0xFFFDE68A),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timelapse_rounded,
                              size: 12,
                              color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '$remainingDays d early',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                // 3. Reason row
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.notes_rounded,
                        size: 12,
                        color: isDark ? Colors.white38 : Colors.grey.shade500,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          reason,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.grey.shade400,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
