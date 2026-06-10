import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api_service.dart';
import '../screens/payment_screens.dart';

class RoomChangeRequestStatus extends StatefulWidget {
  final int studentId;
  
  const RoomChangeRequestStatus({
    super.key,
    required this.studentId,
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

    // If the latest one is dismissed, we show nothing (don't fall back to older ones)
    if (_dismissedIds.contains(requestId)) return const SizedBox.shrink();

    final status = latestRequest['status'] ?? 'pending';

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
                      Text(latestRequest['request_id'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _getStatusColor(status))),
                ),
                const SizedBox(width: 8),
                // Only show dismiss button if status is not pending (optional, but requested for "REJECTED" in screenshot)
                // Actually user said "enable the cross button" so I'll show it for all states if they want to clear it.
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
                  Flexible(child: Text(latestRequest['current_room'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 14, color: Colors.grey)),
                  Flexible(child: Text(latestRequest['requested_room'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37), fontSize: 13), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            if (latestRequest['reason'] != null) ...[
              const SizedBox(height: 12),
              const Text('REASON:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(latestRequest['reason'], style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
            if (status.toLowerCase() == 'rejected' && latestRequest['remarks'] != null && latestRequest['remarks'].toString().isNotEmpty) ...[
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
                  latestRequest['remarks'], 
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
                          requestedRoom: latestRequest['requested_room'],
                          customAmount: double.tryParse(latestRequest['amount_to_pay']?.toString() ?? '0'),
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
}
