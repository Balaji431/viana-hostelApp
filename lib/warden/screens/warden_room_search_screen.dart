import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_widgets.dart';

class WardenRoomSearchScreen extends StatefulWidget {
  final bool isDialog;
  const WardenRoomSearchScreen({super.key, this.isDialog = false});

  @override
  State<WardenRoomSearchScreen> createState() => _WardenRoomSearchScreenState();
}

class _WardenRoomSearchScreenState extends State<WardenRoomSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;
  bool _isInitialLoad = true;
  bool _showRoomDropdown = false;
  
  List<String> _allocatedRooms = [];
  List<Map<String, dynamic>> _roomDetails = [];
  List<Map<String, dynamic>> _students = [];
  
  bool _roomFound = false;
  bool _accessDenied = false;
  String _searchedRoomNumber = '';
  String _hostelName = '';
  String _floorName = '';
  String _wardenName = '';
  String _message = '';

  int _totalBeds = 0;
  int _occupiedBeds = 0;
  int _vacancyBeds = 0;
  String _roomType = '';

  // Filter selection: 'total', 'occupied', 'vacancy'
  String _activeBedFilter = 'total';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadWardenAllocatedRooms();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadWardenAllocatedRooms() async {
    setState(() => _isLoading = true);
    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final res = await ApiService.searchWardenRoom(wardenUsername: user.username);
      if (mounted && res['success'] == true) {
        setState(() {
          _allocatedRooms = List<String>.from(res['allocated_rooms'] ?? []);
          _roomDetails = List<Map<String, dynamic>>.from(res['room_details'] ?? []);
          _isInitialLoad = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _performRoomSearch(String roomNum) async {
    final cleanRoom = roomNum.trim();
    if (cleanRoom.isEmpty) return;

    setState(() {
      _isLoading = true;
      _searchedRoomNumber = cleanRoom;
      _showRoomDropdown = false;
      _activeBedFilter = 'total';
    });

    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final res = await ApiService.searchWardenRoom(
        wardenUsername: user.username,
        roomNumber: cleanRoom,
      );

      if (mounted) {
        if (res['success'] == true) {
          setState(() {
            _roomFound = res['room_found'] ?? false;
            _accessDenied = res['access_denied'] ?? false;
            _hostelName = res['hostel_name'] ?? '';
            _floorName = res['floor_name'] ?? '';
            _wardenName = res['warden_name'] ?? '';
            _message = res['message'] ?? '';
            _totalBeds = res['total_beds'] ?? 4;
            _occupiedBeds = res['occupied_beds'] ?? 0;
            _vacancyBeds = res['vacancy_beds'] ?? 0;
            _roomType = res['room_type'] ?? '';
            // Use the room number as stored in the API (original format e.g. T-32 F02- W0-R16)
            _searchedRoomNumber = (res['room_number'] ?? _searchedRoomNumber).toString();
            _students = List<Map<String, dynamic>>.from(res['students'] ?? []);
            if (res['allocated_rooms'] != null) {
              _allocatedRooms = List<String>.from(res['allocated_rooms']);
            }
            if (res['room_details'] != null) {
              _roomDetails = List<Map<String, dynamic>>.from(res['room_details']);
            }
            _isLoading = false;
          });
        } else {
          setState(() {
            _message = res['message'] ?? 'Search failed';
            _students = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = 'Error performing room search: $e';
          _students = [];
          _isLoading = false;
        });
      }
    }
  }

  void _showStudentRenewalModal(BuildContext context, Map<String, dynamic> student) {
    final name = student['student_name'] ?? 'Student';
    final regNo = student['reg_no'] ?? student['username'] ?? 'N/A';
    final roomNo = student['room_allocation'] ?? student['room_number'] ?? 'N/A';
    String phone = (student['personal_phone'] ?? '').toString().trim();
    // Strip country code: 919XXXXXXXXX → 9XXXXXXXXX (10 digits)
    if (phone.startsWith('+91') && phone.length == 13) {
      phone = phone.substring(3);
    } else if (phone.startsWith('91') && phone.length == 12) {
      phone = phone.substring(2);
    } else if (phone.startsWith('0') && phone.length == 11) {
      phone = phone.substring(1);
    }
    final email = (student['email'] ?? '').toString();
    final renewalDate = (student['renewal_date'] ?? 'N/A').toString();
    final status = (student['status'] ?? 'Active').toString();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFF1A2744),
                    child: const Icon(Icons.person, color: Color(0xFFD4AF37), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1A2744)),
                        ),
                        Text(
                          'Reg No: $regNo',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.of(ctx).pop(),
                  )
                ],
              ),
              const Divider(height: 24),

              const Text(
                'Student Details & Renewal Status',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A2744)),
              ),
              const SizedBox(height: 14),

              // Detail Tiles
              _buildModalTile(Icons.door_sliding_outlined, 'Assigned Room', roomNo),
              const SizedBox(height: 10),
              _buildModalTile(Icons.phone_outlined, 'Contact Number', phone.isNotEmpty ? phone : 'N/A'),
              const SizedBox(height: 10),
              _buildModalTile(Icons.event_repeat_outlined, 'Renewal Date', renewalDate, isHighlight: true),
              const SizedBox(height: 10),
              _buildModalTile(Icons.verified_outlined, 'Status', status),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A2744),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalTile(IconData icon, String label, String value, {bool isHighlight = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isHighlight ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isHighlight ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final String query = _searchController.text.trim().toLowerCase();
    final matchingRooms = _roomDetails.where((r) {
      if (query.isEmpty) return true;
      final roomNo = (r['room_number'] ?? '').toString().toLowerCase();
      final cleanRoom = roomNo.replaceAll('-', '').replaceAll(' ', '');
      final cleanQuery = query.replaceAll('-', '').replaceAll(' ', '');
      return roomNo.contains(query) || cleanRoom.contains(cleanQuery);
    }).toList();

    // Calculate occupied and vacant counts
    final int occupiedCount = _students.length;
    final int vacantCount = max(0, _totalBeds - occupiedCount);

    Widget content = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: widget.isDialog
          ? null
          : const SkeuomorphicNavBar(
              title: 'Room Search',
            ),
      body: LinenBackground(
        child: Column(
          children: [
            // Header Search Box
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : null,
                gradient: isDark ? null : SkeuomorphicColors.royalContentGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                border: isDark ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))) : null,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(isDark ? 0.35 : 0.15), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Warden: ${user.userName} (${user.username})',
                    style: const TextStyle(color: Color(0xFFD4AF37), fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Search rooms allocated to your floor & hostel groups',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  
                  // Search TextField
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        onTap: () {
                          setState(() {
                            _showRoomDropdown = true;
                          });
                        },
                        onChanged: (val) {
                          setState(() {
                            _showRoomDropdown = true;
                          });
                        },
                        onSubmitted: (val) {
                          setState(() {
                            _showRoomDropdown = false;
                          });
                          _performRoomSearch(val);
                        },
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Click or type room number (e.g. T30-F01-WE-R10)...',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : Colors.white.withOpacity(0.1),
                          prefixIcon: const Icon(Icons.meeting_room_outlined, color: Color(0xFFD4AF37)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _showRoomDropdown = false;
                              });
                              _performRoomSearch(_searchController.text);
                            },
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.white.withOpacity(0.2))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                        ),
                      ),
                      
                      // CURVED BLUE DROPDOWN CARDS
                      if (_showRoomDropdown && matchingRooms.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isDark ? Colors.white24 : Colors.transparent),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDark ? 0.35 : 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(6),
                            itemCount: matchingRooms.length,
                            itemBuilder: (context, index) {
                              final roomItem = matchingRooms[index];
                              final String rName = (roomItem['room_number'] ?? '').toString();
                              final bool isSelected = _searchedRoomNumber.toLowerCase() == rName.toLowerCase();

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    debugPrint('=== [WARDEN ROOM TAP] Selected room: $rName ===');
                                    _searchController.text = rName;
                                    setState(() {
                                      _showRoomDropdown = false;
                                    });
                                    _performRoomSearch(rName);
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected 
                                          ? const Color(0xFF4A80D6) 
                                          : (isDark ? const Color(0xFF0F1520) : Colors.white),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: const Color(0xFF4A80D6).withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                                          : [],
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.door_sliding_outlined,
                                          size: 18,
                                          color: isSelected ? Colors.white : (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Room $rName',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isSelected ? Colors.white : (isDark ? Colors.white : const Color(0xFF1A2744)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Results Section
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_searchedRoomNumber.isNotEmpty && !_accessDenied && _roomFound) ...[
                            // SECTION 1: Single Line 3 Stat Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildBedFilterButton(
                                    icon: Icons.hotel,
                                    label: 'Total: $_totalBeds',
                                    filterKey: 'total',
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _buildBedFilterButton(
                                    icon: Icons.person_pin,
                                    label: 'Occupied: $occupiedCount',
                                    filterKey: 'occupied',
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _buildBedFilterButton(
                                    icon: Icons.meeting_room_outlined,
                                    label: 'Vacancy: $vacantCount',
                                    filterKey: 'vacancy',
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // SECTION 2: Room Type Card
                            if (_roomType.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isDark ? Colors.white24 : Colors.blue.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.king_bed_outlined, size: 20, color: isDark ? const Color(0xFFD4AF37) : Colors.blue.shade900),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Room Type: ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 13, 
                                        color: isDark ? Colors.white : Colors.blue.shade900,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        _roomType,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600, 
                                          fontSize: 13, 
                                          color: isDark ? const Color(0xFFD4AF37) : Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // SECTION 3: BED CARDS LIST
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _activeBedFilter == 'occupied'
                                      ? 'Occupied Student Cards ($occupiedCount)'
                                      : (_activeBedFilter == 'vacancy'
                                          ? 'Vacant Bed Cards ($vacantCount)'
                                          : 'Room Bed Allocation Cards ($_totalBeds Total)'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold, 
                                    fontSize: 16, 
                                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // RENDER BED CARDS
                            if (_activeBedFilter == 'total') ...[
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _totalBeds,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  if (index < occupiedCount) {
                                    return _buildStudentCard(context, _students[index]);
                                  } else {
                                    return _buildVacantBedCard(context, _searchedRoomNumber, index - occupiedCount, isDark);
                                  }
                                },
                              ),
                            ] else if (_activeBedFilter == 'occupied') ...[
                              if (occupiedCount > 0)
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: occupiedCount,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    return _buildStudentCard(context, _students[index]);
                                  },
                                )
                              else
                                _buildEmptyStateCard('No occupied beds in this room.', isDark),
                            ] else if (_activeBedFilter == 'vacancy') ...[
                              if (vacantCount > 0)
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: vacantCount,
                                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    return _buildVacantBedCard(context, _searchedRoomNumber, index, isDark);
                                  },
                                )
                              else
                                _buildEmptyStateCard('This room is fully occupied! Zero vacant beds remaining.', isDark),
                            ],
                          ],

                          // ACCESS DENIED ALERT
                          if (_accessDenied) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF3B1219) : Colors.red.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.red.shade300),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.shield_outlined, color: Colors.red.shade400, size: 48),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Access Denied',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.red.shade900),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _message,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: isDark ? Colors.white70 : Colors.red.shade800, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ]
                          // INITIAL PROMPT
                          else if (_searchedRoomNumber.isEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.search_outlined, color: Color(0xFFD4AF37), size: 54),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Select or Search a Room Number',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold, 
                                      fontSize: 16, 
                                      color: isDark ? Colors.white : const Color(0xFF1A2744),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Click or type in the search bar above to dropdown your assigned rooms and view student details.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );

    if (widget.isDialog) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 700,
          height: 650,
          child: content,
        ),
      );
    }

    return content;
  }

  Widget _buildEmptyStateCard(String message, [bool isDark = false]) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          message,
          style: TextStyle(color: isDark ? Colors.white70 : Colors.grey.shade600, fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildBedFilterButton({
    required IconData icon,
    required String label,
    required String filterKey,
    bool isDark = false,
  }) {
    final bool isSelected = _activeBedFilter == filterKey;
    Color bgColor = isSelected 
        ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) 
        : (isDark ? const Color(0xFF1E293B) : Colors.white);
    Color textColor = isSelected 
        ? (isDark ? const Color(0xFF1B2B48) : Colors.white) 
        : (isDark ? Colors.white : const Color(0xFF1A2744));
    Color borderColor = isSelected 
        ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) 
        : (isDark ? Colors.white24 : Colors.grey.shade300);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _activeBedFilter = filterKey;
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
            boxShadow: isSelected ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))] : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: textColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // OCCUPIED BED CARD (Dark Blue with Student Details)
  Widget _buildStudentCard(BuildContext context, Map<String, dynamic> student) {
    final name = student['student_name'] ?? 'Student';
    final regNo = student['reg_no'] ?? student['username'] ?? 'N/A';
    final roomNo = student['room_allocation'] ?? student['room_number'] ?? 'N/A';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showStudentRenewalModal(context, student),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A2744),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.15),
                child: const Icon(Icons.person, color: Color(0xFFD4AF37), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Reg No: $regNo',
                      style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  roomNo,
                  style: const TextStyle(color: Color(0xFF1A2744), fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // VACANT BED CARD (White Glass Card with Room Code Badge)
  Widget _buildVacantBedCard(BuildContext context, String roomNo, int bedIndex, [bool isDark = false]) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.grey.shade300, 
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade100,
            child: Icon(Icons.bed_outlined, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade600, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vacant Bed Slot #${bedIndex + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 15, 
                    color: isDark ? Colors.white : Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Available for Student Allocation',
                  style: TextStyle(color: isDark ? const Color(0xFF81C784) : Colors.green.shade700, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
            ),
            child: Text(
              roomNo,
              style: TextStyle(
                color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700, 
                fontWeight: FontWeight.bold, 
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
