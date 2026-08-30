import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  List<RoomChangeRequest> _allRequests = [];
  bool _isLoading = true;
  String _selectedStatus = 'all'; // all, pending, approved, rejected

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
        setState(() {
          _allRequests = (response['data'] as List<dynamic>)
              .map((json) => RoomChangeRequest.fromJson(json))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
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
        return const Color(0xFF43A047);
      case 'rejected':
        return const Color(0xFFE53935);
      case 'pending':
        return const Color(0xFFFF9800);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Room Change Requests',
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _loadRequests,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            // Filter Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                    )
                  : _allRequests.isEmpty
                      ? Center(
                          child: Text(
                            'No requests found',
                            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _allRequests.length,
                          itemBuilder: (context, index) {
                            return _buildRequestCard(_allRequests[index], isDark);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, bool isDark) {
    final isSelected = _selectedStatus == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedStatus = value;
            _isLoading = true;
          });
          _loadRequests();
        }
      },
      selectedColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF2D4A7A),
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A2744),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.currentRoom} → ${request.requestedRoom}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
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
}
