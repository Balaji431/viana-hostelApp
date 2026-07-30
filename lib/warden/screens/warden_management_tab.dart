import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';
import '../widgets/warden_widgets.dart';
import '../widgets/warden_modals.dart';
import '../../admin/hostel_fee_selector_screen.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class WardenManagementTab extends StatefulWidget {
  const WardenManagementTab({super.key});

  @override
  State<WardenManagementTab> createState() => _WardenManagementTabState();
}

class _WardenManagementTabState extends State<WardenManagementTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _activeSubTab = 0; // 0: Conduct, 1: Payments, 2: Renewals

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<UserProvider>();
    final showInternalAppBar = (user.role == UserRole.warden || user.role == UserRole.admin);

    return Scaffold(
      appBar: showInternalAppBar
          ? SkeuomorphicNavBar(
              title: user.role == UserRole.admin ? 'Fee Management' : 'Management',
              rightAction: const ProfileButton(),
            )
          : null,
      body: LinenGridBackground(
        child: CustomScrollView(
          slivers: [
            if (user.role != UserRole.admin) SliverToBoxAdapter(child: _buildProfileHeader()),
            if (user.role == UserRole.warden) SliverToBoxAdapter(child: _buildSubTabSelector()),
            // Warden-only: sub-tab section label pinned header
            if (user.role == UserRole.warden)
              SliverPersistentHeader(
                pinned: true,
                delegate: _ManagementHeaderDelegate(
                  child: Container(
                    color: const Color(0xFFF5F0E8),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      children: [
                        if (_activeSubTab == 0) ...[
                          const Icon(Icons.shield_outlined, size: 18, color: Color(0xFF1B2B48)),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          _activeSubTab == 0 ? 'Student Conduct' : (_activeSubTab == 1 ? 'Payment History' : 'Renewal Logs'),
                          style: TextStyle(
                            fontSize: _activeSubTab == 0 ? 15 : 12,
                            color: _activeSubTab == 0 ? const Color(0xFF1B2B48) : Colors.grey,
                            fontWeight: FontWeight.bold,
                            letterSpacing: _activeSubTab == 0 ? null : 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _buildActiveSubTabSliver(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSubTabSliver() {
    final user = context.read<UserProvider>();
    if (user.role == UserRole.admin) {
      return const SliverToBoxAdapter(
        child: HostelFeeSelectorScreen(isEmbedded: true),
      );
    }

    switch (_activeSubTab) {
      case 0: return const _ConductSubSliver();
      case 1: return const _PaymentsSubSliver();
      case 2: return const _RenewalsSubSliver();
      default: return const SliverToBoxAdapter(child: SizedBox());
    }
  }

  Widget _buildProfileHeader() {
    final user = context.watch<UserProvider>();
    String name = user.userName;
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";
    
    List<String> assignmentParts = [];
    if (user.hostelName.isNotEmpty && user.hostelName != 'N/A') {
      assignmentParts.add(user.hostelName);
    }
    if (user.block.isNotEmpty && user.block != 'N/A') {
      assignmentParts.add("${user.block} Floor");
    }
    if (user.wing.isNotEmpty && user.wing != 'N/A' && user.wing != '') {
      assignmentParts.add("${user.wing} Wing");
    }
    String assignmentText = assignmentParts.isNotEmpty 
        ? assignmentParts.join(' - ')
        : "";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
      decoration: const BoxDecoration(
        gradient: SkeuomorphicColors.royalContentGradient,
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 18, color: Colors.white), overflow: TextOverflow.ellipsis),
                Text(
                  (user.institution.isNotEmpty && user.institution != 'N/A' ? user.institution : "ID: ${user.username}"), 
                  style: SkeuomorphicStyles.latoBody.copyWith(fontSize: 13, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
                if (assignmentText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    "Assigned: $assignmentText",
                    style: SkeuomorphicStyles.latoBody.copyWith(fontSize: 12, color: const Color(0xFFD4AF37), fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSubTabItem('Conduct', 0),
            const SizedBox(width: 10),
            _buildSubTabItem('Payments', 1),
            const SizedBox(width: 10),
            _buildSubTabItem('Renewals', 2),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabItem(String label, int index) {
    bool active = _activeSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeSubTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: active 
          ? BoxDecoration(gradient: SkeuomorphicColors.goldGlossyGradient, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))])
          : BoxDecoration(color: const Color(0xFFF0EFEA), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black12)),
        child: Text(label, style: TextStyle(color: active ? const Color(0xFF1B2B48) : Colors.black54, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _ManagementHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ManagementHeaderDelegate({required this.child});
  @override double get minExtent => 45;
  @override double get maxExtent => 45;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override bool shouldRebuild(_ManagementHeaderDelegate oldDelegate) => false;
}

class _ConductSubSliver extends StatefulWidget {
  const _ConductSubSliver();
  @override State<_ConductSubSliver> createState() => _ConductSubSliverState();
}

class _ConductSubSliverState extends State<_ConductSubSliver> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _locations = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';
  String _searchQuery = '';
  String _selectedFloor = 'All Floors';
  String _selectedWing = 'All Wings';
  String _selectedRoom = 'All Rooms';

  String _extractWing(Map<String, dynamic> item) {
    final explicitWing = (item['wing'] ?? item['wing_name'] ?? item['sub_zone_id'] ?? '').toString().trim();
    if (explicitWing.isNotEmpty && explicitWing.toLowerCase() != 'unallocated') {
      return explicitWing;
    }
    final room = (item['room_number'] ?? item['room_no'] ?? item['room_code'] ?? '').toString().trim();
    if (room.isEmpty || room.toLowerCase() == 'unallocated') return 'General';
    final parts = room.split('-');
    if (parts.length >= 4) return parts[2];
    if (parts.length == 3) return parts[1];
    return 'General';
  }

  @override 
  void initState() { 
    super.initState(); 
    _fetchStudents(); 
  }

  Future<void> _fetchStudents() async {
    final user = context.read<UserProvider>();
    final response = await ApiService.getStudents(wardenUsername: user.username);
    if (response['status'] == 'success' || response['success'] == true) {
      if (mounted) {
        setState(() { 
          _students = List<Map<String, dynamic>>.from(response['data'] ?? []); 
          _locations = List<Map<String, dynamic>>.from(response['locations'] ?? []);
          _isLoading = false; 
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _floorOrder(String floor) {
    final f = floor.toLowerCase().trim();
    if (f.contains('ground') || f == 'f00' || f == '0') return 0;
    if (f.contains('first') || f == '1st' || f == 'f01' || f == '1') return 1;
    if (f.contains('second') || f == '2nd' || f == 'f02' || f == '2') return 2;
    if (f.contains('third') || f == '3rd' || f == 'f03' || f == '3') return 3;
    if (f.contains('fourth') || f == '4th' || f == 'f04' || f == '4') return 4;
    if (f.contains('fifth') || f == '5th' || f == 'f05' || f == '5') return 5;
    if (f.contains('sixth') || f == '6th' || f == 'f06' || f == '6') return 6;
    if (f.contains('seventh') || f == '7th' || f == 'f07' || f == '7') return 7;
    if (f.contains('eighth') || f == '8th' || f == 'f08' || f == '8') return 8;
    if (f.contains('ninth') || f == '9th' || f == 'f09' || f == '9') return 9;
    if (f.contains('tenth') || f == '10th' || f == 'f10' || f == '10') return 10;
    return 99;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Extract available floors (from students & locations)
    final rawFloors = <String>{};
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    final sortedFloors = rawFloors.toList();
    sortedFloors.sort((a, b) => _floorOrder(a).compareTo(_floorOrder(b)));
    final availableFloors = ['All Floors', ...sortedFloors];

    // 2. Extract available wings (Filtered by Selected Floor)
    final rawWings = <String>{};
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(s);
      if (w.isNotEmpty) rawWings.add(w);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(l);
      if (w.isNotEmpty) rawWings.add(w);
    }
    final sortedWings = rawWings.toList();
    sortedWings.sort();
    final availableWings = ['All Wings', ...sortedWings];

    // 3. Extract available rooms (Filtered by Selected Floor AND Selected Wing)
    final rawRooms = <String>{};
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      final r = (s['room_no'] ?? s['room_code'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(s).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (r.isNotEmpty && r.toLowerCase() != 'unallocated') rawRooms.add(r);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      final r = (l['room_number'] ?? l['room_no'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(l).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (r.isNotEmpty && r.toLowerCase() != 'unallocated') rawRooms.add(r);
    }
    final sortedRooms = rawRooms.toList();
    sortedRooms.sort();
    final availableRooms = ['All Rooms', ...sortedRooms];

    // 4. Filter students
    final filtered = _students.where((s) {
      final room = (s['room_no'] ?? s['room_code'] ?? '').toString();
      final floor = (s['floor'] ?? s['floor_name'] ?? '').toString();
      final wing = _extractWing(s);
      final isCheckedOut = room.isEmpty || room.toLowerCase() == 'unallocated';

      // Floor Filter
      if (_selectedFloor != 'All Floors') {
        if (floor.toLowerCase() != _selectedFloor.toLowerCase()) {
          return false;
        }
      }

      // Wing Filter
      if (_selectedWing != 'All Wings') {
        if (wing.toLowerCase() != _selectedWing.toLowerCase()) {
          return false;
        }
      }

      // Room Filter
      if (_selectedRoom != 'All Rooms') {
        if (room.toLowerCase() != _selectedRoom.toLowerCase()) {
          return false;
        }
      }

      // Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = (s['full_name'] ?? s['name'] ?? '').toString().toLowerCase();
        final regNo = (s['register_number'] ?? s['reg_no'] ?? '').toString().toLowerCase();
        final roomNo = room.toLowerCase();
        if (!name.contains(query) && !regNo.contains(query) && !roomNo.contains(query)) {
          return false;
        }
      }

      // Status pill filter
      if (_selectedFilter == 'Checked-out') {
        return isCheckedOut;
      } else if (_selectedFilter == 'All') {
        return true;
      } else {
        if (isCheckedOut) return false;
        return (s['conduct'] ?? 'Good').toString().toLowerCase() == _selectedFilter.toLowerCase();
      }
    }).toList();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10).copyWith(top: 15),
            child: Column(
              children: [
                _buildCascadingDropdowns(availableFloors, availableWings, availableRooms),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search name, reg no, or room...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD4AF37)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFilterPills(),
                const SizedBox(height: 10),
                Text(
                  '${filtered.length} students',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'Lato'),
                ),
              ],
            ),
          ),
        ),
        if (_isLoading)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (filtered.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40), 
              child: Center(
                child: Text(
                  "No active users for this selection",
                  style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildStudentCard(filtered[index]),
              childCount: filtered.length,
            ),
          ),
      ],
    );
  }

  Widget _buildCascadingDropdowns(List<String> availableFloors, List<String> availableWings, List<String> availableRooms) {
    final currentFloorValue = availableFloors.contains(_selectedFloor) ? _selectedFloor : 'All Floors';
    final currentWingValue = availableWings.contains(_selectedWing) ? _selectedWing : 'All Wings';
    final currentRoomValue = availableRooms.contains(_selectedRoom) ? _selectedRoom : 'All Rooms';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentFloorValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newFloor) {
                    if (newFloor != null) {
                      setState(() {
                        _selectedFloor = newFloor;
                        _selectedWing = 'All Wings';
                        _selectedRoom = 'All Rooms';
                      });
                    }
                  },
                  items: availableFloors.map((f) {
                    return DropdownMenuItem<String>(
                      value: f,
                      child: Text(
                        f == 'All Floors' ? '🏢 All Floors' : '📍 $f Floor',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentWingValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newWing) {
                    if (newWing != null) {
                      setState(() {
                        _selectedWing = newWing;
                        _selectedRoom = 'All Rooms';
                      });
                    }
                  },
                  items: availableWings.map((w) {
                    return DropdownMenuItem<String>(
                      value: w,
                      child: Text(
                        w == 'All Wings' ? '🚩 All Wings' : '🛏️ Wing $w',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentRoomValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newRoom) {
                    if (newRoom != null) {
                      setState(() {
                        _selectedRoom = newRoom;
                      });
                    }
                  },
                  items: availableRooms.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(
                        r == 'All Rooms' ? '🔑 All Rooms (${availableRooms.length - 1})' : '🚪 $r',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownContainer({required Widget child}) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1B2B48).withValues(alpha: 0.2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _buildFilterPills() {
    final filters = ['All', 'Good', 'Satisfactory', 'Poor'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          bool active = _selectedFilter == f;
          return GestureDetector(
            onTap: () => setState(() { _selectedFilter = f; }),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: _getFilterDecoration(f, active),
              child: Text(f, style: _getFilterTextStyle(f, active)),
            ),
          );
        }).toList(),
      ),
    );
  }

  BoxDecoration _getFilterDecoration(String f, bool active) {
    final val = f.trim().toLowerCase();
    if (val == 'all') {
      return BoxDecoration(
        color: active ? const Color(0xFF1B2B48) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1B2B48), width: 1.2),
      );
    }
    Color color;
    Color borderColor;
    if (val == 'good') {
      color = const Color(0xFF2E7D32);
      borderColor = const Color(0xFFA5D6A7);
    } else if (val == 'satisfactory') {
      color = const Color(0xFFE65100);
      borderColor = const Color(0xFFFFCC80);
    } else if (val == 'poor') {
      color = const Color(0xFFC62828);
      borderColor = const Color(0xFFEF9A9A);
    } else {
      color = Colors.grey;
      borderColor = Colors.grey.shade300;
    }

    return BoxDecoration(
      color: active ? color : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: borderColor, width: 1.2),
    );
  }

  TextStyle _getFilterTextStyle(String f, bool active) {
    final val = f.trim().toLowerCase();
    if (val == 'all') {
      return TextStyle(
        color: active ? Colors.white : const Color(0xFF1B2B48),
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
    }
    Color color;
    if (val == 'good') {
      color = const Color(0xFF2E7D32);
    } else if (val == 'satisfactory') {
      color = const Color(0xFFE65100);
    } else if (val == 'poor') {
      color = const Color(0xFFC62828);
    } else {
      color = Colors.grey;
    }

    return TextStyle(
      color: active ? Colors.white : color,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );
  }

  Color _getColor(String f) {
    final val = f.trim().toLowerCase();
    if (val == 'good') return const Color(0xFF2E7D32);
    if (val == 'satisfactory') return const Color(0xFFE65100);
    if (val == 'poor') return const Color(0xFFC62828);
    if (val == 'checked-out') return Colors.purple;
    return const Color(0xFF1B2B48);
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    String name = student['full_name'] ?? student['name'] ?? 'Unknown';
    String room = student['room_no'] ?? 'N/A';
    String conduct = student['conduct'] ?? 'Good';
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";
    bool isCheckedOut = room == null || room.isEmpty || room.toLowerCase() == 'unallocated';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: ListTile(
        onTap: () async {
          final result = await showDialog(
            context: context,
            builder: (context) => EditConductModal(student: student),
          );
          if (result == true) _fetchStudents();
        },
        onLongPress: () {
          final studentIdStr = student['id'] ?? student['user_id'] ?? student['profile_id'];
          final studentId = studentIdStr != null ? int.tryParse(studentIdStr.toString()) : null;
          showDialog(
            context: context,
            builder: (context) => StudentDetailsDialog(
              studentId: studentId,
              fallbackName: name,
              fallbackRegNo: (student['register_number'] ?? student['reg_no'] ?? 'N/A').toString(),
              fallbackRoom: isCheckedOut ? 'Checked-out / Deallocated' : 'Room $room',
            ),
          );
        },
        leading: Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
          child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        subtitle: Text(isCheckedOut ? 'Checked-out / Deallocated' : 'Room $room', style: TextStyle(color: isCheckedOut ? Colors.red.shade700 : Colors.grey.shade600, fontWeight: isCheckedOut ? FontWeight.bold : null)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _getColor(conduct).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(
            conduct[0].toUpperCase() + conduct.substring(1).toLowerCase(), 
            style: TextStyle(color: _getColor(conduct), fontSize: 10, fontWeight: FontWeight.bold)
          ),
        ),
      ),
    );
  }
}

class _PaymentsSubSliver extends StatefulWidget {
  const _PaymentsSubSliver();
  @override
  State<_PaymentsSubSliver> createState() => _PaymentsSubSliverState();
}

class _PaymentsSubSliverState extends State<_PaymentsSubSliver> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _locations = [];
  Map<String, List<Map<String, dynamic>>> _studentPayments = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'All';
  String _selectedFloor = 'All Floors';
  String _selectedWing = 'All Wings';
  String _selectedRoom = 'All Rooms';

  String _extractWing(Map<String, dynamic> item) {
    final explicitWing = (item['wing'] ?? item['wing_name'] ?? item['sub_zone_id'] ?? '').toString().trim();
    if (explicitWing.isNotEmpty && explicitWing.toLowerCase() != 'unallocated') {
      return explicitWing;
    }
    final room = (item['room_number'] ?? item['room_no'] ?? item['room_code'] ?? '').toString().trim();
    if (room.isEmpty || room.toLowerCase() == 'unallocated') return 'General';
    final parts = room.split('-');
    if (parts.length >= 4) return parts[2];
    if (parts.length == 3) return parts[1];
    return 'General';
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (mounted) setState(() => _isLoading = true);
    final user = context.read<UserProvider>();
    
    // Fetch both students and payments
    final studentsRes = await ApiService.getStudents(wardenUsername: user.username);
    final paymentsRes = await ApiService.getAllPayments(wardenUsername: user.username);
    
    if (mounted) {
      setState(() {
        if (studentsRes['status'] == 'success' || studentsRes['success'] == true) {
          _students = List<Map<String, dynamic>>.from(studentsRes['data'] ?? []);
          _locations = List<Map<String, dynamic>>.from(studentsRes['locations'] ?? []);
        }
        
        if (paymentsRes['success'] == true || paymentsRes['status'] == 'success') {
          final allPayments = List<Map<String, dynamic>>.from(paymentsRes['data']);
          _studentPayments = {};
          for (var p in allPayments) {
            String reg = (p['registerNumber'] ?? '').toString().trim();
            String name = (p['name'] ?? '').toString().trim().toUpperCase();
            
            if (reg.isNotEmpty) {
              if (!_studentPayments.containsKey(reg)) _studentPayments[reg] = [];
              _studentPayments[reg]!.add(p);
            }
            
            if (name.isNotEmpty) {
              if (!_studentPayments.containsKey(name)) _studentPayments[name] = [];
              if (!_studentPayments[name]!.contains(p)) {
                _studentPayments[name]!.add(p);
              }
            }
          }
        }
        _isLoading = false;
      });
    }
  }

  int _floorOrder(String floor) {
    final f = floor.toLowerCase().trim();
    if (f.contains('ground') || f == 'f00' || f == '0') return 0;
    if (f.contains('first') || f == '1st' || f == 'f01' || f == '1') return 1;
    if (f.contains('second') || f == '2nd' || f == 'f02' || f == '2') return 2;
    if (f.contains('third') || f == '3rd' || f == 'f03' || f == '3') return 3;
    if (f.contains('fourth') || f == '4th' || f == 'f04' || f == '4') return 4;
    if (f.contains('fifth') || f == '5th' || f == 'f05' || f == '5') return 5;
    if (f.contains('sixth') || f == '6th' || f == 'f06' || f == '6') return 6;
    if (f.contains('seventh') || f == '7th' || f == 'f07' || f == '7') return 7;
    if (f.contains('eighth') || f == '8th' || f == 'f08' || f == '8') return 8;
    if (f.contains('ninth') || f == '9th' || f == 'f09' || f == '9') return 9;
    if (f.contains('tenth') || f == '10th' || f == 'f10' || f == '10') return 10;
    return 99;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));

    // 1. Extract available floors (from students & locations)
    final rawFloors = <String>{};
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    final sortedFloors = rawFloors.toList();
    sortedFloors.sort((a, b) => _floorOrder(a).compareTo(_floorOrder(b)));
    final availableFloors = ['All Floors', ...sortedFloors];

    // 2. Extract available wings (Filtered by Selected Floor)
    final rawWings = <String>{};
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(s);
      if (w.isNotEmpty) rawWings.add(w);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(l);
      if (w.isNotEmpty) rawWings.add(w);
    }
    final sortedWings = rawWings.toList();
    sortedWings.sort();
    final availableWings = ['All Wings', ...sortedWings];

    // 3. Extract available rooms (Filtered by Selected Floor AND Selected Wing)
    final rawRooms = <String>{};
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      final r = (s['room_no'] ?? s['room_code'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(s).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (r.isNotEmpty && r.toLowerCase() != 'unallocated') rawRooms.add(r);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      final r = (l['room_number'] ?? l['room_no'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(l).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (r.isNotEmpty && r.toLowerCase() != 'unallocated') rawRooms.add(r);
    }
    final sortedRooms = rawRooms.toList();
    sortedRooms.sort();
    final availableRooms = ['All Rooms', ...sortedRooms];

    // 4. Filter students
    final filteredStudents = _students.where((s) {
      final name = (s['full_name'] ?? s['name'] ?? '').toString().toLowerCase();
      final room = (s['room_no'] ?? s['room_code'] ?? '').toString();
      final floor = (s['floor'] ?? s['floor_name'] ?? '').toString();
      final wing = _extractWing(s);

      // Floor Filter
      if (_selectedFloor != 'All Floors') {
        if (floor.toLowerCase() != _selectedFloor.toLowerCase()) {
          return false;
        }
      }

      // Wing Filter
      if (_selectedWing != 'All Wings') {
        if (wing.toLowerCase() != _selectedWing.toLowerCase()) {
          return false;
        }
      }

      // Room Filter
      if (_selectedRoom != 'All Rooms') {
        if (room.toLowerCase() != _selectedRoom.toLowerCase()) {
          return false;
        }
      }

      // Search Filter
      final matchesSearch = name.contains(_searchQuery.toLowerCase()) || room.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;
      
      if (_filterStatus == 'All') return true;
      final reg = (s['register_number'] ?? s['student_id'] ?? s['id'] ?? '').toString();
      bool hasPayments = _studentPayments.containsKey(reg) && _studentPayments[reg]!.isNotEmpty;
      if (_filterStatus == 'Paid') return hasPayments;
      if (_filterStatus == 'Pending') return !hasPayments;
      return true;
    }).toList();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Text('Student Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCascadingDropdowns(availableFloors, availableWings, availableRooms),
                const SizedBox(height: 12),
                _buildSearchBar(),
                const SizedBox(height: 12),
                _buildFilterPills(),
                const SizedBox(height: 8),
                Text('${filteredStudents.length} students', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildStudentPaymentCard(filteredStudents[index]),
            childCount: filteredStudents.length,
          ),
        ),
      ],
    );
  }

  Widget _buildCascadingDropdowns(List<String> availableFloors, List<String> availableWings, List<String> availableRooms) {
    final currentFloorValue = availableFloors.contains(_selectedFloor) ? _selectedFloor : 'All Floors';
    final currentWingValue = availableWings.contains(_selectedWing) ? _selectedWing : 'All Wings';
    final currentRoomValue = availableRooms.contains(_selectedRoom) ? _selectedRoom : 'All Rooms';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentFloorValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newFloor) {
                    if (newFloor != null) {
                      setState(() {
                        _selectedFloor = newFloor;
                        _selectedWing = 'All Wings';
                        _selectedRoom = 'All Rooms';
                      });
                    }
                  },
                  items: availableFloors.map((f) {
                    return DropdownMenuItem<String>(
                      value: f,
                      child: Text(
                        f == 'All Floors' ? '🏢 All Floors' : '📍 $f Floor',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentWingValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newWing) {
                    if (newWing != null) {
                      setState(() {
                        _selectedWing = newWing;
                        _selectedRoom = 'All Rooms';
                      });
                    }
                  },
                  items: availableWings.map((w) {
                    return DropdownMenuItem<String>(
                      value: w,
                      child: Text(
                        w == 'All Wings' ? '🚩 All Wings' : '🛏️ Wing $w',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentRoomValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newRoom) {
                    if (newRoom != null) {
                      setState(() {
                        _selectedRoom = newRoom;
                      });
                    }
                  },
                  items: availableRooms.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(
                        r == 'All Rooms' ? '🔑 All Rooms (${availableRooms.length - 1})' : '🚪 $r',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownContainer({required Widget child}) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1B2B48).withValues(alpha: 0.2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: const InputDecoration(hintText: 'Search name or room...', prefixIcon: Icon(Icons.search, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
      ),
    );
  }

  Widget _buildFilterPills() {
    return Row(
      children: [
        _filterPill('All'),
        const SizedBox(width: 10),
        _filterPill('Paid'),
        const SizedBox(width: 10),
        _filterPill('Pending'),
      ],
    );
  }

  Widget _filterPill(String label) {
    bool active = _filterStatus == label;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? SkeuomorphicColors.royalContentGradient : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: active ? Colors.transparent : (label == 'Paid' ? Colors.green.withOpacity(0.3) : (label == 'Pending' ? Colors.orange.withOpacity(0.3) : Colors.black12))),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : (label == 'Paid' ? Colors.green : (label == 'Pending' ? Colors.orange : Colors.grey)),
            fontSize: 12,
            fontWeight: FontWeight.bold
          ),
        ),
      ),
    );
  }

  Widget _buildStudentPaymentCard(Map<String, dynamic> student) {
    String reg = (student['register_number'] ?? student['student_id'] ?? student['id'] ?? '').toString().trim();
    String fullName = (student['full_name'] ?? student['name'] ?? '').toString().trim().toUpperCase();
    String room = student['room_no'] ?? 'N/A';
    List<Map<String, dynamic>> payments = _studentPayments[reg] ?? _studentPayments[fullName] ?? [];
    String initials = fullName.isNotEmpty ? fullName.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";

    return GestureDetector(
      onLongPress: () {
        final studentIdStr = student['id'] ?? student['user_id'] ?? student['profile_id'];
        final studentId = studentIdStr != null ? int.tryParse(studentIdStr.toString()) : null;
        showDialog(
          context: context,
          builder: (context) => StudentDetailsDialog(
            studentId: studentId,
            fallbackName: fullName,
            fallbackRegNo: reg,
            fallbackRoom: room,
          ),
        );
      },
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: SkeuomorphicStyles.skeuomorphicCard,
          child: ExpansionTile(
            leading: Container(
              width: 42, height: 42,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
              child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
            ),
            title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text('Room $room • ${payments.length} payment${payments.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            children: [
              if (payments.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text("No payment history recorded", style: TextStyle(color: Colors.grey, fontSize: 12)))
              else
                Column(
                  children: payments.map((p) => _buildPaymentDetailItem(p)).toList(),
                ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentDetailItem(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('₹${p['amount']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              Text(p['booking_date']?.toString().split(' ')[0] ?? 'N/A', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: (p['status']?.toString().toLowerCase() == 'success' ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(p['status'] ?? 'Success', style: TextStyle(color: p['status']?.toString().toLowerCase() == 'success' ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _RenewalsSubSliver extends StatefulWidget {
  const _RenewalsSubSliver();
  @override
  State<_RenewalsSubSliver> createState() => _RenewalsSubSliverState();
}

class _RenewalsSubSliverState extends State<_RenewalsSubSliver> {
  List<Map<String, dynamic>> _renewals = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _locations = [];
  bool _isLoading = true;
  String _selectedFloor = 'All Floors';
  String _selectedWing = 'All Wings';
  String _selectedRoom = 'All Rooms';
  String _searchQuery = '';

  String _extractWing(Map<String, dynamic> item) {
    final explicitWing = (item['wing'] ?? item['wing_name'] ?? item['sub_zone_id'] ?? '').toString().trim();
    if (explicitWing.isNotEmpty && explicitWing.toLowerCase() != 'unallocated') {
      return explicitWing;
    }
    final room = (item['room_number'] ?? item['room_no'] ?? item['room_code'] ?? '').toString().trim();
    if (room.isEmpty || room.toLowerCase() == 'unallocated') return 'General';
    final parts = room.split('-');
    if (parts.length >= 4) return parts[2];
    if (parts.length == 3) return parts[1];
    return 'General';
  }

  @override
  void initState() {
    super.initState();
    _fetchRenewals();
  }

  Future<void> _fetchRenewals() async {
    if (mounted) setState(() => _isLoading = true);
    final user = context.read<UserProvider>();
    final response = await ApiService.getPendingRenewals(wardenUsername: user.username);
    final studentsRes = await ApiService.getStudents(wardenUsername: user.username);
    
    if (mounted) {
      setState(() {
        if (studentsRes['status'] == 'success' || studentsRes['success'] == true) {
          _students = List<Map<String, dynamic>>.from(studentsRes['data'] ?? []);
          _locations = List<Map<String, dynamic>>.from(studentsRes['locations'] ?? []);
        }

        if (response['success'] == true || response['status'] == 'success') {
          final List rawList = response['data'] ?? [];
          final mapRegToStudent = <String, Map<String, dynamic>>{};
          for (var s in _students) {
            final reg = (s['register_number'] ?? s['reg_no'] ?? '').toString().trim();
            if (reg.isNotEmpty) mapRegToStudent[reg] = s;
          }

          _renewals = rawList
              .map<Map<String, dynamic>>((r) {
                final map = Map<String, dynamic>.from(r);
                final reg = (map['student_reg_no'] ?? '').toString().trim();
                if (mapRegToStudent.containsKey(reg)) {
                  final st = mapRegToStudent[reg]!;
                  if (map['floor_name'] == null || map['floor_name'].toString().isEmpty) {
                    map['floor_name'] = st['floor'] ?? st['floor_name'];
                  }
                }
                return map;
              })
              .where((r) => (r['status'] ?? '').toString().toLowerCase() == 'pending')
              .toList();
        }
        _isLoading = false;
      });
    }
  }

  int _floorOrder(String floor) {
    final f = floor.toLowerCase().trim();
    if (f.contains('ground') || f == 'f00' || f == '0') return 0;
    if (f.contains('first') || f == '1st' || f == 'f01' || f == '1') return 1;
    if (f.contains('second') || f == '2nd' || f == 'f02' || f == '2') return 2;
    if (f.contains('third') || f == '3rd' || f == 'f03' || f == '3') return 3;
    if (f.contains('fourth') || f == '4th' || f == 'f04' || f == '4') return 4;
    if (f.contains('fifth') || f == '5th' || f == 'f05' || f == '5') return 5;
    if (f.contains('sixth') || f == '6th' || f == 'f06' || f == '6') return 6;
    if (f.contains('seventh') || f == '7th' || f == 'f07' || f == '7') return 7;
    if (f.contains('eighth') || f == '8th' || f == 'f08' || f == '8') return 8;
    if (f.contains('ninth') || f == '9th' || f == 'f09' || f == '9') return 9;
    if (f.contains('tenth') || f == '10th' || f == 'f10' || f == '10') return 10;
    return 99;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));

    // 1. Extract available floors (from renewals, students, & locations)
    final rawFloors = <String>{};
    for (var r in _renewals) {
      final f = (r['floor_name'] ?? r['floor'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      if (f.isNotEmpty) rawFloors.add(f);
    }
    final sortedFloorsList = rawFloors.toList();
    sortedFloorsList.sort((a, b) => _floorOrder(a).compareTo(_floorOrder(b)));
    final availableFloors = ['All Floors', ...sortedFloorsList];

    // 2. Extract available wings (Filtered by Selected Floor)
    final rawWings = <String>{};
    for (var r in _renewals) {
      final f = (r['floor_name'] ?? r['floor'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(r);
      if (w.isNotEmpty) rawWings.add(w);
    }
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(s);
      if (w.isNotEmpty) rawWings.add(w);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      final w = _extractWing(l);
      if (w.isNotEmpty) rawWings.add(w);
    }
    final sortedWingsList = rawWings.toList();
    sortedWingsList.sort();
    final availableWings = ['All Wings', ...sortedWingsList];

    // 3. Extract available rooms (Filtered by Selected Floor AND Selected Wing)
    final rawRooms = <String>{};
    for (var r in _renewals) {
      final f = (r['floor_name'] ?? r['floor'] ?? '').toString().trim();
      final room = (r['room_number'] ?? r['room_no'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(r).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (room.isNotEmpty && room.toLowerCase() != 'unallocated') rawRooms.add(room);
    }
    for (var s in _students) {
      final f = (s['floor'] ?? s['floor_name'] ?? '').toString().trim();
      final room = (s['room_no'] ?? s['room_code'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(s).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (room.isNotEmpty && room.toLowerCase() != 'unallocated') rawRooms.add(room);
    }
    for (var l in _locations) {
      final f = (l['floor_name'] ?? l['floor'] ?? '').toString().trim();
      final room = (l['room_number'] ?? l['room_no'] ?? '').toString().trim();
      if (_selectedFloor != 'All Floors' && f.toLowerCase() != _selectedFloor.toLowerCase()) continue;
      if (_selectedWing != 'All Wings' && _extractWing(l).toLowerCase() != _selectedWing.toLowerCase()) continue;
      if (room.isNotEmpty && room.toLowerCase() != 'unallocated') rawRooms.add(room);
    }
    final sortedRoomsList = rawRooms.toList();
    sortedRoomsList.sort();
    final availableRooms = ['All Rooms', ...sortedRoomsList];

    // 4. Filter renewals
    final filteredRenewals = _renewals.where((r) {
      final name = (r['student_name'] ?? '').toString().toLowerCase();
      final reg = (r['student_reg_no'] ?? '').toString().toLowerCase();
      final room = (r['room_number'] ?? r['room_no'] ?? '').toString();
      final floor = (r['floor_name'] ?? r['floor'] ?? '').toString();
      final wing = _extractWing(r);

      // Floor Filter
      if (_selectedFloor != 'All Floors') {
        if (floor.toLowerCase() != _selectedFloor.toLowerCase()) {
          return false;
        }
      }

      // Wing Filter
      if (_selectedWing != 'All Wings') {
        if (wing.toLowerCase() != _selectedWing.toLowerCase()) {
          return false;
        }
      }

      // Room Filter
      if (_selectedRoom != 'All Rooms') {
        if (room.toLowerCase() != _selectedRoom.toLowerCase()) {
          return false;
        }
      }

      // Search Filter
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !reg.contains(q) && !room.toLowerCase().contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_edu, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Text('Pending Renewals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                    const Spacer(),
                    Text('${filteredRenewals.length} pending', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCascadingDropdowns(availableFloors, availableWings, availableRooms),
                const SizedBox(height: 12),
                _buildSearchBar(),
              ],
            ),
          ),
        ),
        if (filteredRenewals.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text("No pending renewal requests found", style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildRenewalCard(filteredRenewals[index]),
              childCount: filteredRenewals.length,
            ),
          ),
      ],
    );
  }

  Widget _buildCascadingDropdowns(List<String> availableFloors, List<String> availableWings, List<String> availableRooms) {
    final currentFloorValue = availableFloors.contains(_selectedFloor) ? _selectedFloor : 'All Floors';
    final currentWingValue = availableWings.contains(_selectedWing) ? _selectedWing : 'All Wings';
    final currentRoomValue = availableRooms.contains(_selectedRoom) ? _selectedRoom : 'All Rooms';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentFloorValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newFloor) {
                    if (newFloor != null) {
                      setState(() {
                        _selectedFloor = newFloor;
                        _selectedWing = 'All Wings';
                        _selectedRoom = 'All Rooms';
                      });
                    }
                  },
                  items: availableFloors.map((f) {
                    return DropdownMenuItem<String>(
                      value: f,
                      child: Text(
                        f == 'All Floors' ? '🏢 All Floors' : '📍 $f Floor',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentWingValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newWing) {
                    if (newWing != null) {
                      setState(() {
                        _selectedWing = newWing;
                        _selectedRoom = 'All Rooms';
                      });
                    }
                  },
                  items: availableWings.map((w) {
                    return DropdownMenuItem<String>(
                      value: w,
                      child: Text(
                        w == 'All Wings' ? '🚩 All Wings' : '🛏️ Wing $w',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildDropdownContainer(
                child: DropdownButton<String>(
                  value: currentRoomValue,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF1B2B48), size: 18),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                  onChanged: (newRoom) {
                    if (newRoom != null) {
                      setState(() {
                        _selectedRoom = newRoom;
                      });
                    }
                  },
                  items: availableRooms.map((r) {
                    return DropdownMenuItem<String>(
                      value: r,
                      child: Text(
                        r == 'All Rooms' ? '🔑 All Rooms (${availableRooms.length - 1})' : '🚪 $r',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDropdownContainer({required Widget child}) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1B2B48).withValues(alpha: 0.2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: const InputDecoration(hintText: 'Search name, reg no, or room...', prefixIcon: Icon(Icons.search, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
      ),
    );
  }

  Widget _buildRenewalCard(Map<String, dynamic> renewal) {
    String name = renewal['student_name'] ?? 'Unknown';
    String reg = (renewal['student_reg_no'] ?? 'N/A').toString();
    String room = renewal['room_number'] ?? 'N/A';
    String date = renewal['requested_at']?.toString().split(' ')[0] ?? 'N/A';
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
                child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Reg No: $reg • Room $room', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Text(date, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  'Reject', 
                  Colors.red, 
                  () => _handleAction(renewal, 'reject')
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  'Approve', 
                  Colors.green, 
                  () => _handleAction(renewal, 'approve')
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Future<void> _handleAction(Map<String, dynamic> renewal, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Request?'),
        content: Text('Are you sure you want to $action this renewal request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action, style: TextStyle(color: action == 'approve' ? Colors.green : Colors.red))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      bool success = false;
      final id = renewal['id'];
      if (action == 'approve') {
        final res = await ApiService.approveRenewal(int.parse(id.toString()));
        success = res['success'] == true;
      } else {
        final res = await ApiService.rejectRenewal(int.parse(id.toString()));
        success = res['success'] == true;
      }
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Renewal $action successful')));
        _fetchRenewals();
      }
    }
  }
}
