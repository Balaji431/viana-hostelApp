import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../core/api_service.dart';
import '../../core/models/room_change_request_model.dart';
import '../screens/payment_screens.dart';

class StudentRoomChangeHistoryDialog extends StatefulWidget {
  final int studentId;
  const StudentRoomChangeHistoryDialog({super.key, required this.studentId});

  @override
  State<StudentRoomChangeHistoryDialog> createState() => _StudentRoomChangeHistoryDialogState();
}

class _StudentRoomChangeHistoryDialogState extends State<StudentRoomChangeHistoryDialog> {
  List<RoomChangeRequest> _allRequests = [];
  bool _isLoading = true;
  String _selectedStatus = 'all'; // all, pending, approved, rejected, completed

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      // Query all requests for the student
      final response = await ApiService.getRoomChangeRequests(
        status: 'all',
        studentId: widget.studentId,
      );
      if (response['success'] == true) {
        if (mounted) {
          final list = (response['data'] as List<dynamic>)
              .map((json) => RoomChangeRequest.fromJson(json))
              .toList();
          
          // Sort latest requests first
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));

          setState(() {
            _allRequests = list;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<RoomChangeRequest> get _filteredRequests {
    if (_selectedStatus == 'all') {
      return _allRequests;
    }
    return _allRequests.where((req) {
      final s = req.status.toLowerCase();
      if (_selectedStatus == 'pending') {
        return s == 'pending';
      }
      if (_selectedStatus == 'approved') {
        return s == 'approved' || s == 'pre_approved';
      }
      if (_selectedStatus == 'rejected') {
        return s == 'rejected';
      }
      if (_selectedStatus == 'completed') {
        return s == 'completed';
      }
      return false;
    }).toList();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF43A047);
      case 'pre_approved':
        return const Color(0xFFD4AF37);
      case 'rejected':
        return const Color(0xFFE53935);
      case 'pending':
        return const Color(0xFFFF9800);
      case 'completed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'pre_approved':
        return Icons.hourglass_top_rounded;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
        return Icons.access_time;
      case 'completed':
        return Icons.verified_rounded;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return Container(
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
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Room Change History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Lato',
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 16, color: isDark ? Colors.white70 : Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE0D8CC)),
          
          // Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  _buildFilterChip('all', 'All History', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pending', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('approved', 'Approved', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('rejected', 'Rejected', isDark),
                  const SizedBox(width: 8),
                  _buildFilterChip('completed', 'Completed', isDark),
                ],
              ),
            ),
          ),
          
          // Request list
          Flexible(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                  : _filteredRequests.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.builder(
                          itemCount: _filteredRequests.length,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemBuilder: (context, index) {
                            final request = _filteredRequests[index];
                            return _buildRequestItem(request, isDark);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, bool isDark) {
    final isSelected = _selectedStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedStatus = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF1A2744)) 
              : (isDark ? Colors.white.withOpacity(0.08) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? (isDark ? const Color(0xFF3B82F6) : const Color(0xFF1A2744)) 
                : (isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE8E0D5)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected 
                ? Colors.white 
                : (isDark ? Colors.white70 : const Color(0xFF1A2744)),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'Lato',
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_outlined, size: 64, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No room change requests found in this category',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade500, fontSize: 13, fontFamily: 'Lato'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(RoomChangeRequest request, bool isDark) {
    final statusColor = _getStatusColor(request.status);
    final isPreApproved = request.status.toLowerCase() == 'pre_approved';
    final dateStr = DateFormat('dd MMM yyyy').format(request.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE8E0D5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(_getStatusIcon(request.status), color: statusColor, size: 20),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.requestId,
                          style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744), fontSize: 12),
                        ),
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request.status.toUpperCase(),
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, thickness: 0.5, color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFE8E0D5)),
            ),
            // Room Transition
            Row(
              children: [
                Flexible(child: _buildRoomBadge(request.currentRoom, isDark ? Colors.white70 : Colors.grey.shade600, isDark)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, size: 14, color: isDark ? Colors.white60 : Colors.grey),
                ),
                Flexible(child: _buildRoomBadge(request.requestedRoom, const Color(0xFFD4AF37), isDark)),
              ],
            ),
            if (request.reason.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'REASON',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white60 : Colors.grey.shade400,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                request.reason,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white : const Color(0xFF1A2744)),
              ),
            ],
            if (request.remarks != null && request.remarks!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                request.status.toLowerCase() == 'rejected' ? 'REJECTION REASON' : 'REMARKS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: request.status.toLowerCase() == 'rejected' 
                      ? (isDark ? const Color(0xFFF87171) : Colors.red.shade300) 
                      : (isDark ? Colors.white60 : Colors.grey.shade400),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                request.remarks!,
                style: TextStyle(
                  fontSize: 12,
                  color: request.status.toLowerCase() == 'rejected' 
                      ? (isDark ? const Color(0xFFFCA5A5) : Colors.red) 
                      : (isDark ? Colors.white : const Color(0xFF1A2744)),
                ),
              ),
            ],
            if (isPreApproved) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaymentPage(
                          requestId: request.requestId,
                          requestedRoom: request.requestedRoom,
                          customAmount: (request.amountToPay as num?)?.toDouble() ?? 0.0,
                        ),
                      ),
                    ).then((_) => _loadRequests());
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF1A2744),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 1,
                  ),
                  child: const Text('PROCEED TO PAYMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoomBadge(String code, Color c, [bool isDark = false]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : c.withOpacity(0.2)),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: isDark ? Colors.white : c,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
