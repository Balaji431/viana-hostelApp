import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../core/app_logger.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/auth_wrapper.dart';

class HostelExplorerScreen extends StatefulWidget {
  const HostelExplorerScreen({super.key});

  @override
  State<HostelExplorerScreen> createState() => _HostelExplorerScreenState();
}

class _HostelExplorerScreenState extends State<HostelExplorerScreen> {
  List<dynamic> _hostels = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  List<dynamic> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _fetchHostels();
    _fetchPendingRequests();
  }

  Future<void> _fetchPendingRequests() async {
    try {
      final user = context.read<UserProvider>();
      if (user.dbId == null) return;
      final response = await ApiService.getRoomChangeRequests(studentId: user.dbId);
      if (response['status'] == 'success') {
        setState(() {
          _pendingRequests = (response['data'] as List<dynamic>)
              .where((r) => r['status'].toString().toLowerCase() == 'pending' || r['status'].toString().toLowerCase() == 'pre_approved')
              .toList();
        });
      }
    } catch (e) {
      AppLogger.error("Error fetching pending requests: $e");
    }
  }

  Future<void> _fetchHostels() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService.getAvailableRooms(vacantOnly: false);
      AppLogger.info("HostelExplorer: Received response: $response");
      
      if (response['status'] == 'success') {
        setState(() {
          List<dynamic> rawHostels = response['hostels'] ?? response['data'] ?? [];
          if (rawHostels is Map) {
            rawHostels = (rawHostels as Map)['all_hostels'] ?? [];
          }
          
          final Map<String, dynamic> uniqueHostels = {};
          for (var h in rawHostels) {
            final name = (h['hostel_name'] ?? h['name'] ?? '').toString();
            if (name.isNotEmpty && !uniqueHostels.containsKey(name)) {
              uniqueHostels[name] = h;
            }
          }
          _hostels = uniqueHostels.values.toList();
          
          AppLogger.info("HostelExplorer: Loaded ${_hostels.length} unique hostels");
          
          if (_hostels.isEmpty) {
             _fetchHostelsFromAlternative();
          } else {
             _isLoading = false;
          }
        });
      } else {
        _fetchHostelsFromAlternative();
      }
    } catch (e) {
      _fetchHostelsFromAlternative();
    }
  }

  Future<void> _fetchHostelsFromAlternative() async {
    try {
      AppLogger.info("HostelExplorer: Attempting alternative fetch from get_hostels.php");
      final response = await ApiService.getRequest('student/get_hostels.php');
      if (response['status'] == 'success' && response['data'] != null) {
        setState(() {
          List<dynamic> rawHostels = response['data']['all_hostels'] ?? [];
          final Map<String, dynamic> uniqueHostels = {};
          for (var h in rawHostels) {
            final name = (h['hostel_name'] ?? h['name'] ?? '').toString();
            if (name.isNotEmpty && !uniqueHostels.containsKey(name)) {
              uniqueHostels[name] = h;
            }
          }
          _hostels = uniqueHostels.values.toList();
          AppLogger.info("HostelExplorer: Loaded ${_hostels.length} unique hostels from alternative");
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'No hostels found';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load hostels';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F6F0),
      appBar: SkeuomorphicNavBar(
        title: 'Hostel Explorer',
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _fetchHostels,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildDiscoveryHeader(),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: Color(0xFFC5A358))),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    TextButton(onPressed: _fetchHostels, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          else
            _buildHostelGrid(),
          const SliverToBoxAdapter(child: SizedBox(height: 30)),
        ],
      ),
    );
  }

  Widget _buildDiscoveryHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(25, 30, 25, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Discover Your\nNew Home',
            style: TextStyle(
              fontFamily: 'Playfair Display',
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1B2B48),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Explore world-class residences at SIMATS and find the perfect space for your academic journey.',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 25),
          
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search hostels or rooms...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFC5A358)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostelGrid() {
    final filteredHostels = _hostels.where((h) {
      final name = (h['hostel_name'] ?? h['name'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    if (filteredHostels.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: 50),
            child: Text('No hostels found matching your search'),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 1,
          mainAxisSpacing: 20,
          childAspectRatio: 1.5,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final hostel = filteredHostels[index];
            return _buildHostelCard(hostel, index);
          },
          childCount: filteredHostels.length,
        ),
      ),
    );
  }

  Widget _buildHostelCard(Map<String, dynamic> hostel, int index) {
    final String name = hostel['hostel_name'] ?? hostel['name'] ?? 'Residence';
    final String campus = hostel['campus'] ?? 'SIMATS';
    final String hostelId = (hostel['hostel_id'] ?? hostel['id'] ?? '').toString();
    final int available = int.tryParse(hostel['available_beds']?.toString() ?? '0') ?? 0;
    final int total = int.tryParse(hostel['total_beds']?.toString() ?? '0') ?? 0;
    final bool isNew = hostel['is_new'] == true || hostelId == '999'; 

    return GestureDetector(
      onTap: () => _openHostelDetails(hostel),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: double.infinity,
                child: Image.asset(
                  index % 2 == 0 ? 'assets/images/hostel_1.png' : 'assets/images/hostel_2.png',
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1B2B48),
                          const Color(0xFF2D4A7A).withOpacity(0.8),
                        ],
                      ),
                    ),
                    child: const Center(child: Icon(Icons.business, color: Colors.white24, size: 40)),
                  ),
                ),
              ),
              
              if (isNew)
                Positioned(
                  top: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: const Text(
                      'NEWLY ADDED',
                      style: TextStyle(
                        color: Color(0xFF1A2744),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),

              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.location_on, color: const Color(0xFFC5A358), size: 14),
                          const SizedBox(width: 4),
                          Text(
                            campus,
                            style: const TextStyle(
                              color: Color(0xFFC5A358),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Playfair Display',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildStatChip(Icons.bed, '$available Beds Vacant'),
                          const SizedBox(width: 10),
                          _buildStatChip(Icons.group, '$total Capacity'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _openHostelDetails(Map<String, dynamic> hostel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _HostelDetailSheet(hostel: hostel, pendingRequests: _pendingRequests),
    );
  }
}

class _HostelDetailSheet extends StatefulWidget {
  final Map<String, dynamic> hostel;
  final List<dynamic> pendingRequests;
  const _HostelDetailSheet({required this.hostel, required this.pendingRequests});

  @override
  State<_HostelDetailSheet> createState() => _HostelDetailSheetState();
}

class _HostelDetailSheetState extends State<_HostelDetailSheet> {
  bool _isLoading = true;
  List<dynamic> _floors = [];

  @override
  void initState() {
    super.initState();
    _fetchHierarchy();
  }

  Future<void> _fetchHierarchy() async {
    try {
      final hostelId = widget.hostel['hostel_id'] ?? widget.hostel['id'];
      if (hostelId == null) return;
      final response = await ApiService.getHostelHierarchy(int.parse(hostelId.toString()));
      if (response['success'] == true) {
        setState(() {
          _floors = response['data']['wings'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6F0),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 50,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.hostel['hostel_name'] ?? 'Residence Details',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A2744),
                          fontFamily: 'Playfair Display',
                        ),
                      ),
                      Text(
                        'Browse rooms and submit your application',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFFC5A358))))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _floors.length,
                itemBuilder: (context, index) => _buildFloorSection(_floors[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFloorSection(Map<String, dynamic> floorData) {
    final String floorName = floorData['name'] ?? 'Floor';
    final List<dynamic> wings = floorData['floors'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 5),
          child: Row(
            children: [
              const Icon(Icons.stairs, color: Color(0xFFC5A358), size: 18),
              const SizedBox(width: 10),
              Text(
                'Floor: $floorName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1B2B48),
                ),
              ),
            ],
          ),
        ),
        ...wings.map((wingData) => _buildWingSection(floorName, wingData)).toList(),
      ],
    );
  }

  Widget _buildWingSection(String floorName, Map<String, dynamic> wingData) {
    final String wingName = wingData['name'] ?? 'Wing';
    final List<dynamic> rooms = wingData['rooms'] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 30, bottom: 10, top: 5),
          child: Row(
            children: [
              Icon(Icons.door_sliding_outlined, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'Wing: $wingName',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(left: 30, right: 10, bottom: 20),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemCount: rooms.length,
          itemBuilder: (context, index) {
            final room = Map<String, dynamic>.from(rooms[index]);
            room['floor_name'] = floorName;
            room['wing_name'] = wingName;
            return _buildRoomTile(room);
          },
        ),
      ],
    );
  }

  Widget _buildRoomTile(Map<String, dynamic> room) {
    final int available = int.tryParse(room['available']?.toString() ?? '0') ?? 0;
    final int physicalAvailable = int.tryParse(room['physical_available']?.toString() ?? '0') ?? 0;
    
    final bool isFull = available <= 0;
    final bool isReserved = isFull && physicalAvailable > 0;
    
    final String roomNo = room['room_no'] ?? 'N/A';
    final String type = room['facility'] ?? 'Standard';

    return GestureDetector(
      onTap: isFull ? null : () => _confirmApplication(room),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isFull ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isFull ? Colors.grey.shade300 : const Color(0xFFE2DED0),
          ),
          boxShadow: isFull ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Room $roomNo',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isFull ? Colors.grey : Colors.black87,
                    ),
                  ),
                  Text(
                    type,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isFull 
                  ? (isReserved ? Colors.orange.withOpacity(0.1) : Colors.red.withOpacity(0.1))
                  : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isFull 
                  ? (isReserved ? 'LOCKED' : 'FULL') 
                  : '$available VAC',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isFull 
                    ? (isReserved ? Colors.orange : Colors.red) 
                    : Colors.green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmApplication(Map<String, dynamic> room) {
    if (widget.pendingRequests.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Request in Progress', style: TextStyle(fontFamily: 'Playfair Display', fontWeight: FontWeight.bold)),
          content: const Text('You already have an active room application. Please wait for it to be processed or cancel it from the dashboard before submitting a new one.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC5A358)),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }

    final String hostelName = widget.hostel['hostel_name'] ?? 'Residence';
    final String floorName = room['floor_name'] ?? 'N/A';
    final String wingName = room['wing_name'] ?? 'N/A';
    final String roomNo = room['room_no'] ?? 'N/A';
    final String roomType = room['room_type'] ?? room['type'] ?? room['facility'] ?? 'Standard';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Application', style: TextStyle(fontFamily: 'Playfair Display', fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('You are applying for the following room:'),
            const SizedBox(height: 15),
            _buildInfoRow(Icons.business, 'Hostel', hostelName),
            _buildInfoRow(Icons.stairs, 'Floor', floorName),
            _buildInfoRow(Icons.door_sliding_outlined, 'Wing', wingName),
            _buildInfoRow(Icons.meeting_room, 'Room', roomNo),
            _buildInfoRow(Icons.star_outline, 'Type', roomType),
            const SizedBox(height: 15),
            const Text(
              'Your application will be sent to the assigned Warden for approval. You will be notified once they review it.',
              style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC5A358),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _submitApplication(room);
            },
            child: const Text('Submit Application'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFC5A358)),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  void _submitApplication(Map<String, dynamic> room) async {
    final String hostelName = widget.hostel['hostel_name'] ?? 'Residence';
    final String floorName = room['floor_name'] ?? 'N/A';
    final String wingName = room['wing_name'] ?? 'N/A';
    final String roomNo = room['room_no'] ?? 'N/A';
    final String roomCode = room['room_code'] ?? roomNo;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFFC5A358))),
    );
    
    try {
      final user = context.read<UserProvider>();
      final String roomType = room['room_type'] ?? room['type'] ?? room['facility'] ?? 'AC';
      
      final response = await ApiService.submitRoomChangeRequest(
        studentId: user.dbId ?? 0,
        currentRoom: user.roomNumber,
        requestedRoom: roomCode,
        reason: 'New Application via Explorer: $hostelName - $floorName - $wingName - Room $roomNo',
        requestedRoomType: roomType,
      );

      // 1. ALWAYS dismiss the loading dialog first using rootNavigator
      try {
        Navigator.of(context, rootNavigator: true).pop(); 
      } catch (e) {
        AppLogger.warning("Failed to pop loading dialog: $e");
      }

      if (response['success'] == true || response['status'] == 'success') {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Application Submitted Successfully! Tracking via Dashboard.'), 
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
          
          // 2. Return to the Home screen (resetting the entire app stack for reliability)
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => AuthWrapper()),
            (route) => false,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${response['message']}')),
          );
        }
      }
    } catch (e) {
       // Ensure dialog is popped on error too
       try {
         Navigator.of(context, rootNavigator: true).pop();
       } catch (_) {}
       
       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection Error: $e')),
          );
        }
    }
  }
}
