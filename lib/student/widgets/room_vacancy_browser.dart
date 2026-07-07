import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';

class Room {
  final String id;
  final String number;
  final String? roomCode;
  final String roomType;
  final int capacity;
  final int occupied;
  
  Room({
    required this.id,
    required this.number,
    this.roomCode,
    required this.roomType,
    required this.capacity,
    required this.occupied,
  });
  
  int get vacancies => capacity - occupied;
  bool get isFull => occupied >= capacity;
  bool get hasVacancy => vacancies > 0;
}

class SubZone {
  final String id;
  final String name;
  final List<Room> rooms;
  
  SubZone({
    required this.id,
    required this.name,
    required this.rooms,
  });
}

class Zone {
  final String id;
  final String name;
  final List<SubZone> subZones;
  
  Zone({
    required this.id,
    required this.name,
    required this.subZones,
  });
}

class Hostel {
  final String id;
  final String name;
  final List<Zone> zones;
  
  Hostel({
    required this.id,
    required this.name,
    required this.zones,
  });
}

class RoomVacancyBrowser extends StatefulWidget {
  final bool isOpen;
  final VoidCallback onClose;
  final String currentRoomString;
  final int? studentId;
  
  const RoomVacancyBrowser({
    super.key,
    required this.isOpen,
    required this.onClose,
    required this.currentRoomString,
    this.studentId,
    this.onStatusChanged,
  });

  final VoidCallback? onStatusChanged;

  @override
  State<RoomVacancyBrowser> createState() => _RoomVacancyBrowserState();
}

class _RoomVacancyBrowserState extends State<RoomVacancyBrowser>
    with TickerProviderStateMixin {
  
  // API Data
  List<Hostel> _hostels = [];
  bool _isLoadingHostels = true;
  String? _loadError;

  String _currentStep = 'browse'; // 'browse', 'confirm', 'success'
  final Set<String> _expandedHostels = {'h1'};
  final Set<String> _expandedZones = {'z2'};
  final Set<String> _expandedSubZones = {'sz3'};
  Room? _selectedRoom;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSubmitting = false;
  String _requestId = '';
  List<dynamic> _roomTypes = [];
  Map<String, dynamic>? _assignedWarden;
  bool _isLoadingWarden = true;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    if (widget.isOpen) {
      _animationController.forward();
      _loadRoomVacancies();
      _loadRoomTypes();
      _fetchAssignedWarden();
    }

    _reasonController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _fetchAssignedWarden() async {
    try {
      final user = context.read<UserProvider>();
      final studentId = user.dbId ?? widget.studentId ?? 0;
      if (studentId != 0) {
        final res = await ApiService.getAssignedStaff(studentId);
        if (res['success'] == true && res['data'] != null) {
          if (mounted) {
            setState(() {
              _assignedWarden = res['data']['warden'];
              _isLoadingWarden = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      debugPrint("Error fetching assigned warden: $e");
    }
    if (mounted) {
      setState(() {
        _isLoadingWarden = false;
      });
    }
  }

  Future<void> _loadRoomTypes() async {
    try {
      final response = await ApiService.getRoomTypes();
      if (response['status'] == 'success') {
        setState(() => _roomTypes = response['data']);
      }
    } catch (e) {
      debugPrint("Error loading room types: $e");
    }
  }

  Future<void> _loadRoomVacancies() async {
    try {
      setState(() {
        _isLoadingHostels = true;
        _loadError = null;
      });

      // Use the new hostel rooms API
      final response = await ApiService.getAvailableRooms(vacantOnly: true);
      
      // Handle both old and new response formats
      if (response['success'] == true || response['status'] == 'success') {
        final List<dynamic> hostelsData = response['hostels'] ?? [];
        final List<Hostel> hostels = hostelsData.map((hostelData) {
          final List<dynamic> roomsData = hostelData['rooms'] ?? [];
          
          // Group rooms by floor
          final Map<String, List<Room>> floorRooms = {};
          for (var roomData in roomsData) {
            final floorCode = roomData['floor_code'] ?? 'Unknown';
            if (!floorRooms.containsKey(floorCode)) {
              floorRooms[floorCode] = [];
            }
            
            floorRooms[floorCode]!.add(Room(
              id: roomData['id'].toString(),
              number: roomData['room_no']?.toString() ?? 'Room ${roomData['id'] ?? 'Unknown'}',
              roomCode: roomData['room_code']?.toString(),
              roomType: roomData['room_type']?.toString() ?? 'Standard',
              capacity: roomData['total_capacity'] ?? 0,
              occupied: roomData['occupied_rooms'] ?? 0,
            ));
          }
          
          // Create zones (floors) and subZones
          final List<Zone> zones = floorRooms.entries.map((entry) {
            final subZone = SubZone(
              id: '${hostelData['hostel_id']}_${entry.key}',
              name: 'Floor ${entry.key}',
              rooms: entry.value,
            );
            return Zone(
              id: '${hostelData['hostel_id']}_zone_${entry.key}',
              name: 'Floor ${entry.key}',
              subZones: [subZone],
            );
          }).toList();
          
          return Hostel(
            id: hostelData['hostel_id'].toString(),
            name: hostelData['hostel_name'] ?? 'Unknown Hostel',
            zones: zones,
          );
        }).toList();

        setState(() {
          _hostels = hostels;
          _isLoadingHostels = false;
        });
      } else {
        throw Exception(response['message'] ?? 'Failed to load room vacancies');
      }
    } catch (e) {
      print('Error loading room vacancies: $e');
      setState(() {
        _loadError = e.toString();
        _hostels = []; // Empty list on error
        _isLoadingHostels = false;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String get _currentRoomDisplay {
    final user = context.read<UserProvider>();
    if (user.roomCode.isNotEmpty) return user.roomCode;
    return user.roomNumber;
  }

  void _toggleSet(Set<String> set, String id) {
    setState(() {
      if (set.contains(id)) {
        set.remove(id);
      } else {
        set.add(id);
      }
    });
  }

  void _handleRoomSelect(Room room) {
    final roomDisplay = room.roomCode ?? room.number;
    if (roomDisplay == _currentRoomDisplay || room.isFull) return;
    
    setState(() {
      _selectedRoom = room;
      _currentStep = 'confirm';
    });
    
    HapticFeedback.lightImpact();
  }

  void _handleSubmitRequest() async {
    if (_reasonController.text.trim().isEmpty) return;
    
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final user = context.read<UserProvider>();
      final studentId = user.dbId ?? widget.studentId ?? 0;

      if (studentId == 0) {
        throw Exception('Student ID not found in session. Please logout and login again.');
      }

      final response = await ApiService.submitRoomChangeRequest(
        studentId: studentId,
        currentRoom: _currentRoomDisplay,
        requestedRoom: _selectedRoom!.roomCode ?? _selectedRoom!.number,
        reason: _reasonController.text.trim(),
        requestedRoomType: _selectedRoom!.roomType,
      );

      if (response['success'] == true) {
        setState(() {
          _isSubmitting = false;
          _requestId = response['data']['request_id'] ?? 'REQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
          _currentStep = 'success';
        });
        // Notify parent to refresh status
        if (widget.onStatusChanged != null) {
          widget.onStatusChanged!();
        }
      } else {
        throw Exception(response['message'] ?? 'Failed to submit request');
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleClose() {
    _animationController.reverse().then((_) {
      widget.onClose();
      setState(() {
        _currentStep = 'browse';
        _selectedRoom = null;
        _reasonController.clear();
      });
    });
  }

  void _goBackToBrowse() {
    setState(() {
      _currentStep = 'browse';
      _selectedRoom = null;
      _reasonController.clear();
    });
  }

  Widget _buildBrowseStep() {
    if (_isLoadingHostels) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFD4AF37)),
            SizedBox(height: 16),
            Text(
              'Loading room vacancies...',
              style: TextStyle(
                color: Color(0xFF1A2744),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, 
                     color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Failed to load room vacancies',
              style: const TextStyle(
                color: Color(0xFF1A2744),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Using demo data',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _loadRoomVacancies,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(
                    color: Color(0xFF1A2744),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Banner
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE1F5FE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF81D4FA)),
              ),
              child: Row(
                children: [
                  Icon(Icons.door_front_door, 
                       color: const Color(0xFF01579B), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Browse Available Rooms',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF01579B),
                            fontFamily: 'Lato',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select a room with vacancies to submit a change request. Your current room is $_currentRoomDisplay.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF0277BD),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Hostels List
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _hostels.length,
                itemBuilder: (context, index) => _buildHostelCard(_hostels[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostelCard(Hostel hostel) {
    final isExpanded = _expandedHostels.contains(hostel.id);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF2D4A7A),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),
          
          InkWell(
            onTap: () => _toggleSet(_expandedHostels, hostel.id),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2D4A7A),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.apartment, 
                                 color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hostel.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                        fontFamily: 'Lato',
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right, 
                                 color: Colors.grey, size: 20),
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: hostel.zones.map((zone) => _buildZoneCard(zone)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildZoneCard(Zone zone) {
    final isExpanded = _expandedZones.contains(zone.id);
    
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleSet(_expandedZones, zone.id),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0D8CC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, 
                           color: Color(0xFF5B7FBF), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      zone.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                        fontFamily: 'Lato',
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right, 
                                 color: Colors.grey, size: 16),
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Column(
                children: zone.subZones.map((subZone) => _buildSubZoneCard(subZone)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSubZoneCard(SubZone subZone) {
    final isExpanded = _expandedSubZones.contains(subZone.id);
    
    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleSet(_expandedSubZones, subZone.id),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8E0D5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers, 
                           color: Color(0xFF9FA8DA), size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subZone.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                        fontFamily: 'Lato',
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right, 
                                 color: Colors.grey, size: 14),
                  ),
                ],
              ),
            ),
          ),
          
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 6),
              child: Column(
                children: subZone.rooms.map((room) => _buildRoomCard(room)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(Room room) {
    final roomDisplay = room.roomCode ?? room.number;
    final isCurrent = roomDisplay == _currentRoomDisplay;
    final isFull = room.isFull;
    final isSelectable = !isCurrent && !isFull;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: isSelectable ? () => _handleRoomSelect(room) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelectable 
                ? Colors.white 
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelectable 
                  ? const Color(0xFFD0C8BC)
                  : Colors.grey.shade300,
            ),
            boxShadow: isSelectable ? [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ] : null,
          ),
          child: Row(
            children: [
              const Icon(Icons.tag, 
                       color: Colors.grey, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomDisplay,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.people, 
                                 color: Colors.grey, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          '${room.occupied}/${room.capacity} occupied',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildRoomBadge(room, isCurrent, isFull),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomBadge(Room room, bool isCurrent, bool isFull) {
    if (isCurrent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD4AF37),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Current',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2744),
          ),
        ),
      );
    }
    
    if (isFull) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFE53935),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Full',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF43A047),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${room.vacancies} Vacant',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildConfirmStep() {
    if (_selectedRoom == null) return const SizedBox();
    
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            InkWell(
              onTap: _goBackToBrowse,
              child: Row(
                children: [
                  const Icon(Icons.arrow_back, 
                           color: Colors.grey, size: 16),
                  const SizedBox(width: 4),
                  const Text(
                    'Back to browsing',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F5F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE0D8CC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Request Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A2744),
                      fontFamily: 'Lato',
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildDetailRow('Current Room', _currentRoomDisplay),
                  const Divider(height: 20, color: Color(0xFFE8E0D5)),
                  _buildDetailRow('Requested Room', _selectedRoom!.roomCode ?? _selectedRoom!.number,
                                  isHighlighted: true),
                  const Divider(height: 20, color: Color(0xFFE8E0D5)),
                  _buildDetailRow('Room Type', _selectedRoom!.roomType),
                  const Divider(height: 20, color: Color(0xFFE8E0D5)),
                  _buildUpgradeCostRow(),
                  const Divider(height: 20, color: Color(0xFFE8E0D5)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Availability',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF43A047),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_selectedRoom!.vacancies} Slot(s) Open',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            const Text(
              'Reason for Change *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4A4A4A),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD0C8BC)),
              ),
              child: TextField(
                controller: _reasonController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Please explain why you want to change rooms...',
                  hintStyle: TextStyle(color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(12),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            
            const SizedBox(height: 16),
            
            if (_isLoadingWarden)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                ),
              )
            else if (_assignedWarden == null || _assignedWarden!['username'] == 'warden1')
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Warden not assigned. You cannot request a room change until a floorwise warden is assigned.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD54F)),
                ),
                child: const Text(
                  'Note: Room changes are subject to Warden approval and availability at the time of processing. Submitting this request does not guarantee the room change.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5D4037),
                  ),
                ),
              ),
            
            const SizedBox(height: 24),
            
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _goBackToBrowse,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2744),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: (_isSubmitting || _reasonController.text.trim().isEmpty || _assignedWarden == null || _assignedWarden!['username'] == 'warden1') ? null : _handleSubmitRequest,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: (_reasonController.text.trim().isEmpty || _assignedWarden == null || _assignedWarden!['username'] == 'warden1')
                            ? Colors.grey.shade300
                            : const Color(0xFFD4AF37),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          if (!(_reasonController.text.trim().isEmpty || _assignedWarden == null || _assignedWarden!['username'] == 'warden1'))
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Center(
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF1A2744)),
                                ),
                              )
                            : const Text(
                                'Submit Request',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A2744),
                                ),
                              ),
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
  }

  Widget _buildDetailRow(String label, String value, {bool isHighlighted = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isHighlighted ? 14 : 12,
            fontWeight: FontWeight.bold,
            color: isHighlighted ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF43A047),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(Icons.check, 
                         color: Colors.white, size: 40),
          ),
          
          const SizedBox(height: 24),
          
          const Text(
            'Request Submitted',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2E7D32),
              fontFamily: 'Lato',
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Text(
            'Your room change request has been sent to the Warden for approval.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5F0),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0D8CC)),
            ),
            child: Column(
              children: [
                const Text(
                  'REQUEST ID',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _requestId,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
                    fontFamily: 'Lato',
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          InkWell(
            onTap: _handleClose,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 'browse':
        return _buildBrowseStep();
      case 'confirm':
        return _buildConfirmStep();
      case 'success':
        return _buildSuccessStep();
      default:
        return _buildBrowseStep();
    }
  }

  String get _currentTitle {
    switch (_currentStep) {
      case 'browse':
        return 'Room Vacancies';
      case 'confirm':
        return 'Request Room Change';
      case 'success':
        return 'Request Submitted';
      default:
        return 'Room Vacancies';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOpen) return const SizedBox();
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6F0),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
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
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1A2744)),
                  onPressed: _currentStep == 'confirm' ? _goBackToBrowse : _handleClose,
                ),
                const SizedBox(width: 8),
                Text(
                  _currentTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
                    fontFamily: 'Lato',
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Container(
              color: const Color(0xFFF9F6F0),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildCurrentStep(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpgradeCostRow() {
    final user = context.read<UserProvider>();
    final requestedType = _selectedRoom!.roomType.trim();
    final currentType  = user.roomType.trim();

    // Find fee data for the requested room type
    Map<String, dynamic>? reqData;
    Map<String, dynamic>? curData;
    for (final t in _roomTypes) {
      final tName = t['id']?.toString().trim() ?? '';
      if (tName.toLowerCase() == requestedType.toLowerCase()) reqData = t as Map<String, dynamic>;
      if (tName.toLowerCase() == currentType.toLowerCase())  curData = t as Map<String, dynamic>;
    }

    if (reqData == null) {
      final isLoading = _roomTypes.isEmpty;
      return Column(
        children: [
          _buildDetailRow('Total Amount', isLoading ? 'Loading...' : 'N/A'),
          const Divider(height: 20, color: Color(0xFFE8E0D5)),
          _buildDetailRow('Extra Amount', isLoading ? 'Loading...' : 'N/A'),
        ],
      );
    }

    final double reqTotal = (reqData['total_fee'] as num?)?.toDouble() ?? (reqData['hostel_fee'] as num?)?.toDouble() ?? 0.0;
    final double curTotal = (curData?['total_fee'] as num?)?.toDouble() ?? (curData?['hostel_fee'] as num?)?.toDouble() ?? 0.0;
    final double extra   = reqTotal - curTotal;

    // Format currency
    String fmtAmount(double amt) {
      final abs = amt.abs();
      final str = abs.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
      return '₹$str';
    }

    final extraLabel = extra > 0
        ? '+${fmtAmount(extra)} extra to pay'
        : extra < 0
            ? '${fmtAmount(extra.abs())} cheaper'
            : 'Same price';
    final extraColor = extra > 0
        ? const Color(0xFFE53935)
        : extra < 0
            ? const Color(0xFF43A047)
            : const Color(0xFF1A2744);

    return Column(
      children: [
        // Total Amount row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Total Amount',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmtAmount(reqTotal),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A2744),
                  ),
                ),
                if (reqData['hostel_fee'] != null && reqData['food_fee'] != null)
                  Text(
                    'Hostel ${fmtAmount((reqData['hostel_fee'] as num).toDouble())} + Food ${fmtAmount((reqData['food_fee'] as num).toDouble())}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const Divider(height: 20, color: Color(0xFFE8E0D5)),
        // Extra Amount row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Extra Amount',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: extra > 0
                    ? const Color(0xFFFFEBEE)
                    : extra < 0
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: extra > 0
                      ? const Color(0xFFEF9A9A)
                      : extra < 0
                          ? const Color(0xFFA5D6A7)
                          : const Color(0xFFD1D5DB),
                ),
              ),
              child: Text(
                extraLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: extraColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
