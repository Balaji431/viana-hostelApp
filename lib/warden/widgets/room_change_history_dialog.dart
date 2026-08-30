import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../core/api_service.dart';
import '../../core/models/room_change_request_model.dart';

class RoomChangeHistoryDialog extends StatefulWidget {
  final int wardenId;
  const RoomChangeHistoryDialog({super.key, required this.wardenId});

  @override
  State<RoomChangeHistoryDialog> createState() => _RoomChangeHistoryDialogState();
}

class _RoomChangeHistoryDialogState extends State<RoomChangeHistoryDialog> {
  List<RoomChangeRequest> _allRequests = [];
  bool _isLoading = true;
  String _selectedStatus = 'all';
  final Map<String, bool> _expandedIds = {}; // Track which requests are expanded

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final user = context.read<UserProvider>();
      final response = await ApiService.getRoomChangeRequests(
        status: _selectedStatus,
        wardenUsername: user.username,
      );
      if (response['success'] == true) {
        if (mounted) {
          setState(() {
            _allRequests = (response['data'] as List<dynamic>)
                .map((json) => RoomChangeRequest.fromJson(json))
                .toList();
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
                    color: isDark ? Colors.white : const Color(0xFF1E2F5E),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 16, color: isDark ? Colors.white70 : Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE0D8CC)),
          
          // Filter Section
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
                ],
              ),
            ),
          ),
          
          // History List
          Flexible(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                  : _allRequests.isEmpty
                      ? _buildEmptyState(isDark)
                      : ListView.builder(
                          itemCount: _allRequests.length,
                          padding: const EdgeInsets.only(bottom: 24),
                          itemBuilder: (context, index) {
                            final request = _allRequests[index];
                            return _buildRequestItem(request, isDark);
                          },
                        ),
            ),
          ),
        ],
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
            'No room change history found',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey.shade500, fontSize: 14),
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
          _isLoading = true;
        });
        _loadRequests();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1E2F5E)) 
              : (isDark ? Colors.white.withOpacity(0.06) : Colors.grey.shade50),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1E2F5E)) 
                : (isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected 
                ? (isDark ? const Color(0xFF0F172A) : Colors.white) 
                : (isDark ? Colors.white70 : Colors.grey.shade700),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildRequestItem(RoomChangeRequest request, bool isDark) {
    final statusColor = _getStatusColor(request.status);
    final isPending = request.status.toLowerCase() == 'pending';
    
    return StatefulBuilder(
      builder: (context, setItemState) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.studentName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF1A2744),
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'ID: ${request.studentRegNo}',
                                style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        
                        // Status Badge - Expandable if pending
                        GestureDetector(
                          onTap: isPending ? () {
                            setState(() {
                              final current = _expandedIds[request.requestId] ?? false;
                              _expandedIds[request.requestId] = !current;
                            });
                          } : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: isPending ? Border.all(color: statusColor.withOpacity(isDark ? 0.4 : 0.2)) : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  request.status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (isPending) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    (_expandedIds[request.requestId] ?? false) ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, 
                                    size: 12, 
                                    color: statusColor
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1, thickness: 0.5, color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade200),
                    ),
                    Row(
                      children: [
                        Flexible(child: _buildRoomBadge(request.currentRoom, isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600, isDark)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward_rounded, size: 14, color: isDark ? Colors.white54 : Colors.grey),
                        ),
                        Flexible(child: _buildRoomBadge(request.requestedRoom, const Color(0xFFD4AF37), isDark)),
                      ],
                    ),
                    if (request.reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'REASON',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF64748B) : Colors.grey.shade400,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.reason,
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.grey.shade700, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Actions Footer for Pending Requests (Conditionally visible)
              if (isPending && (_expandedIds[request.requestId] ?? false))
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _showRejectionDialog(request, isDark),
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? const Color(0xFFF87171) : Colors.red,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _updateStatus(request, 'approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF43A047),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                          minimumSize: const Size(80, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('APPROVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }
    );
  }

  void _showRejectionDialog(RoomChangeRequest request, bool isDark) {
    final TextEditingController reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.12)) : BorderSide.none,
        ),
        title: Text(
          'Reject Request', 
          style: TextStyle(
            fontFamily: 'Lato', 
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A2744),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please provide a reason for rejecting ${request.studentName}\'s request.', 
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.blueGrey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Enter reason here...',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), 
                  borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), 
                  borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a reason')));
                return;
              }
              Navigator.pop(context);
              _updateStatus(request, 'rejected', remarks: reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text('REJECT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(RoomChangeRequest request, String status, {String? remarks}) async {
    try {
      setState(() => _isLoading = true);
      
      final user = context.read<UserProvider>();
      final wardenId = user.dbId ?? 1;
      
      final response = await ApiService.updateRoomChangeRequest(
        requestId: request.requestId,
        status: status,
        wardenId: wardenId,
        remarks: remarks,
      );
      
      if (response['success'] == true) {
        _loadRequests();
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: ${response['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Widget _buildRoomBadge(String room, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(isDark ? 0.4 : 0.2)),
      ),
      child: Text(
        room,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return const Color(0xFF43A047);
      case 'rejected': return const Color(0xFFE53935);
      case 'pending': return const Color(0xFFFF9800);
      default: return Colors.grey;
    }
  }
}
