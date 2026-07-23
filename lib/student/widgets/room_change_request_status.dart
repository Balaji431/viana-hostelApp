import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_service.dart';
import '../screens/payment_screens.dart';

class RoomChangeRequestStatus extends StatefulWidget {
  final int studentId;
  final bool showHistory;
  
  const RoomChangeRequestStatus({
    super.key,
    required this.studentId,
    this.showHistory = false,
  });

  @override
  State<RoomChangeRequestStatus> createState() => _RoomChangeRequestStatusState();
}

class _RoomChangeRequestStatusState extends State<RoomChangeRequestStatus> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  final Set<String> _dismissedIds = {};

  @override
  void initState() {
    super.initState();
    _loadDismissedIds();
    _loadRequests();
  }

  Future<void> _loadDismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('dismissed_room_requests') ?? [];
    if (mounted) {
      setState(() {
        _dismissedIds.addAll(list);
      });
    }
  }

  Future<void> _dismissRequest(String requestId) async {
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds.add(requestId);
    await prefs.setStringList('dismissed_room_requests', _dismissedIds.toList());
    if (mounted) setState(() {});
  }

  Future<void> _loadRequests() async {
    try {
      // Fetch all requests for this student to see Approved/Rejected/Pending status
      final response = await ApiService.getRoomChangeRequests(
        status: 'all',
        studentId: widget.studentId,
      );
      if (response['status'] == 'success') {
        final studentRequests = (response['data'] as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        
        // Sort by ID descending to get the latest first
        studentRequests.sort((a, b) {
          final idA = int.tryParse(a['request_id']?.toString() ?? '0') ?? 0;
          final idB = int.tryParse(b['request_id']?.toString() ?? '0') ?? 0;
          return idB.compareTo(idA);
        });
        
        setState(() {
          _requests = studentRequests;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
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
      case 'expired':
        return Colors.red.shade900;
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
      case 'expired':
        return Icons.timer_off_rounded;
      case 'completed':
        return Icons.verified_rounded;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SizedBox.shrink();
    if (_requests.isEmpty) return const SizedBox.shrink();

    // Get the absolute latest request (first in sorted list)
    final latestRequest = _requests.first;
    final requestId = latestRequest['request_id']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Latest request card (only if not dismissed)
        if (!_dismissedIds.contains(requestId))
          _buildRequestCard(latestRequest, isLatest: true),

        // History section (controlled by parent via showHistory prop)
        if (widget.showHistory) ...[
          for (int i = 0; i < _requests.length; i++)
            if (i > 0 || _dismissedIds.contains(requestId))
              _buildHistoryCard(_requests[i]),
        ],
      ],
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request, {bool isLatest = false}) {
    final requestId = request['request_id']?.toString() ?? '';
    final status = request['status'] ?? 'pending';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getStatusColor(status).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Room Change Request', style: TextStyle(fontWeight: FontWeight.bold, color: _getStatusColor(status), fontSize: 13), overflow: TextOverflow.ellipsis),
                      Text(request['request_id'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _getStatusColor(status))),
                ),
                const SizedBox(width: 8),
                if (isLatest)
                  InkWell(
                    onTap: () => _dismissRequest(requestId),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.withOpacity(0.1),
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.grey),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Room Transition
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Flexible(child: Text(request['current_room'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey)),
                  Flexible(child: Text(request['requested_room'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37), fontSize: 13), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            if (request['reason'] != null) ...[
              const SizedBox(height: 12),
              const Text('REASON:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(request['reason'], style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
            if (status.toLowerCase() == 'rejected' && request['remarks'] != null && request['remarks'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('REJECTION REASON:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE53935))),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE53935).withOpacity(0.1)),
                ),
                child: Text(
                  request['remarks'], 
                  style: const TextStyle(fontSize: 12, color: Color(0xFFE53935), fontWeight: FontWeight.bold),
                ),
              ),
            ],
            if (status.toLowerCase() == 'pre_approved') ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate to Payment Page
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaymentPage(
                          requestId: requestId,
                          requestedRoom: request['requested_room'],
                          customAmount: double.tryParse(request['amount_to_pay']?.toString() ?? '0'),
                        ),
                      ),
                    ).then((_) => _loadRequests()); // Reload after returning
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 4,
                  ),
                  child: const Text('PROCEED TO PAYMENT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> request) {
    final status = request['status'] ?? 'pending';
    final statusColor = _getStatusColor(status);

    // Format date if available
    String dateStr = '';
    final createdAt = request['created_at']?.toString() ?? request['request_date']?.toString() ?? '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        dateStr = '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        dateStr = createdAt;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20).copyWith(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.15), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.12),
            ),
            child: Icon(_getStatusIcon(status), color: statusColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${request['current_room'] ?? ''}  →  ${request['requested_room'] ?? ''}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF333333)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      request['request_id'] ?? '',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                    if (dateStr.isNotEmpty) ...[
                      const Text('  •  ', style: TextStyle(color: Colors.grey, fontSize: 10)),
                      Text(dateStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
