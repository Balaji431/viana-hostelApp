import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/models/room_change_request_model.dart';
import '../../shared/user_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: SkeuomorphicNavBar(
        title: 'Room Change Requests',
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _loadRequests,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All'),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pending'),
                  const SizedBox(width: 8),
                  _buildFilterChip('approved', 'Approved'),
                  const SizedBox(width: 8),
                  _buildFilterChip('rejected', 'Rejected'),
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
                    ? const Center(
                        child: Text('No requests found'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _allRequests.length,
                        itemBuilder: (context, index) {
                          return _buildRequestCard(_allRequests[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
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
      selectedColor: const Color(0xFF2D4A7A),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black,
        fontSize: 12,
      ),
    );
  }

  Widget _buildRequestCard(RoomChangeRequest request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2744),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${request.currentRoom} → ${request.requestedRoom}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              request.reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
      ),
    );
  }
}
