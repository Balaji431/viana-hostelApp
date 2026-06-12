import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/design_system.dart' as ds;
import '../../core/providers/allocation_provider.dart';
import '../../shared/user_provider.dart';
import 'priority_queue_screen.dart';

class AllocationExplorerScreen extends StatefulWidget {
  const AllocationExplorerScreen({super.key});

  @override
  State<AllocationExplorerScreen> createState() => _AllocationExplorerScreenState();
}

class _AllocationExplorerScreenState extends State<AllocationExplorerScreen> {
  String _searchQuery = '';
  String _selectedGender = 'All'; // 'All', 'Boys', 'Girls'
  String _selectedHostel = 'All';
  bool _isGenderFilterOpen = false;
  bool _isHostelFilterOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AllocationProvider>().fetchRooms();
      final user = context.read<UserProvider>();
      if (user.dbId != null) {
        context.read<AllocationProvider>().loadAllocation(user.dbId!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AllocationProvider>();
    final user = context.watch<UserProvider>();
    
    // Calculate dynamic hostels based on gender filter
    final List<String> hostelNames = ['All'];
    for (var h in provider.hostels) {
      final String type = h['hostel_type'] ?? '';
      final String name = h['hostel_name'] ?? '';
      if (_selectedGender == 'All' || type.toLowerCase() == _selectedGender.toLowerCase()) {
        if (!hostelNames.contains(name)) {
          hostelNames.add(name);
        }
      }
    }

    // Reset selected hostel to 'All' if it's no longer present in the list
    if (!hostelNames.contains(_selectedHostel)) {
      _selectedHostel = 'All';
    }

    final filteredRooms = provider.rooms.where((room) {
      final matchesSearch = room['number'].toString().contains(_searchQuery) ||
          room['room_type'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      
      final String roomGender = room['hostel_type']?.toString().toLowerCase() ?? '';
      final matchesGender = _selectedGender == 'All' || roomGender == _selectedGender.toLowerCase();

      final String roomHostel = room['hostel_name']?.toString().toLowerCase() ?? '';
      final matchesHostel = _selectedHostel == 'All' || roomHostel == _selectedHostel.toLowerCase();

      return matchesSearch && matchesGender && matchesHostel;
    }).toList();

    return Scaffold(
      body: ds.LinenBackground(
        child: Column(
          children: [
            const ds.SkeuomorphicNavBar(title: 'Room Explorer'),
            
            // Search & Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: ds.RoyalTheme.navyGradient,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                children: [
                  // Search Input
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search room or type...',
                        hintStyle: TextStyle(color: Colors.white70, fontSize: 13),
                        prefixIcon: Icon(Icons.search, color: Colors.white70, size: 20),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Single Row of Pill Buttons
                  Row(
                    children: [
                      // Category Dropdown Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isGenderFilterOpen = !_isGenderFilterOpen;
                              _isHostelFilterOpen = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isGenderFilterOpen 
                                ? ds.RoyalTheme.primaryGoldStart.withOpacity(0.2) 
                                : Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isGenderFilterOpen 
                                  ? ds.RoyalTheme.primaryGoldEnd 
                                  : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.category_outlined, 
                                      size: 16, 
                                      color: _isGenderFilterOpen ? ds.RoyalTheme.primaryGoldStart : Colors.white70
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Category: ${_selectedGender.toUpperCase()}',
                                      style: TextStyle(
                                        color: _isGenderFilterOpen ? ds.RoyalTheme.primaryGoldStart : Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  _isGenderFilterOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                  color: _isGenderFilterOpen ? ds.RoyalTheme.primaryGoldStart : Colors.white70,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Hostel Dropdown Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _isHostelFilterOpen = !_isHostelFilterOpen;
                              _isGenderFilterOpen = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _isHostelFilterOpen 
                                ? ds.RoyalTheme.primaryGoldStart.withOpacity(0.2) 
                                : Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _isHostelFilterOpen 
                                  ? ds.RoyalTheme.primaryGoldEnd 
                                  : Colors.white24,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.home_work_outlined, 
                                      size: 16, 
                                      color: _isHostelFilterOpen ? ds.RoyalTheme.primaryGoldStart : Colors.white70
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Hostel: ${_selectedHostel.toUpperCase()}',
                                      style: TextStyle(
                                        color: _isHostelFilterOpen ? ds.RoyalTheme.primaryGoldStart : Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                Icon(
                                  _isHostelFilterOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                                  color: _isHostelFilterOpen ? ds.RoyalTheme.primaryGoldStart : Colors.white70,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Floating panel drawers
                  if (_isGenderFilterOpen) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: ['All', 'Boys', 'Girls'].map((gender) {
                          final isSelected = _selectedGender == gender;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(
                              label: Text(gender.toUpperCase(), style: const TextStyle(fontSize: 10)),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedGender = gender;
                                    _isGenderFilterOpen = false;
                                  });
                                }
                              },
                              labelStyle: TextStyle(
                                color: isSelected ? ds.RoyalTheme.navyDarker : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                              selectedColor: ds.RoyalTheme.primaryGoldStart,
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  if (_isHostelFilterOpen) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: SizedBox(
                        height: 34,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: hostelNames.length,
                          itemBuilder: (context, index) {
                            final name = hostelNames[index];
                            final isSelected = _selectedHostel == name;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(name.toUpperCase(), style: const TextStyle(fontSize: 10)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _selectedHostel = name;
                                      _isHostelFilterOpen = false;
                                    });
                                  }
                                },
                                labelStyle: TextStyle(
                                  color: isSelected ? ds.RoyalTheme.navyDarker : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                ),
                                selectedColor: ds.RoyalTheme.primaryGoldStart,
                                backgroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Info Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: ds.RoyalTheme.warningStart.withOpacity(0.2),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: ds.RoyalTheme.warningEnd, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select up to 5 preferred rooms. Rooms are not locked during selection.',
                      style: GoogleFonts.lato(fontSize: 11, color: ds.RoyalTheme.navyDarker),
                    ),
                  ),
                ],
              ),
            ),

            // Room List
            Expanded(
              child: provider.isLoading
                ? const Center(child: CircularProgressIndicator(color: ds.RoyalTheme.primaryGoldEnd))
                : filteredRooms.isEmpty
                  ? const Center(child: Text('No rooms found'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredRooms.length,
                      itemBuilder: (context, index) {
                        final room = filteredRooms[index];
                        final int available = int.tryParse(room['available'].toString()) ?? 0;
                        final bool isAdded = provider.preferences.any((p) => p['room_id'].toString() == room['id'].toString());
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ds.SkeuomorphicCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${room['room_type'] ?? '${room['capacity']} Seater ${room['facility']}'}',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: ds.RoyalTheme.navyDarker,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    ds.GlossyBadge(
                                      label: available > 0 ? '$available Beds Left' : 'Full',
                                      isActive: available > 0,
                                      colorOverride: available > 1 
                                        ? ds.RoyalTheme.successMid 
                                        : available == 1 ? ds.RoyalTheme.warningMid : ds.RoyalTheme.dangerMid,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Room ${room['number']} (${room['block']}) • ${room['floor']} Floor',
                                  style: GoogleFonts.lato(fontSize: 12, color: Colors.grey.shade600),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.king_bed_outlined, size: 14, color: Colors.grey.shade700),
                                    const SizedBox(width: 4),
                                    Text('Capacity: ${room['capacity']} beds', style: const TextStyle(fontSize: 12)),
                                    const Spacer(),
                                    const Icon(Icons.wifi, size: 14, color: Colors.blue),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.ac_unit, size: 14, color: Colors.cyan),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ds.SkeuomorphicButton(
                                  text: isAdded ? 'SELECTED' : 'SELECT',
                                  icon: isAdded ? Icons.check : Icons.add,
                                  isPrimary: !isAdded,
                                  onPressed: (available <= 0 || (isAdded && !['draft', 'none', 'rejected', 'payment_expired'].contains(provider.allocationStatus)) || (!isAdded && provider.preferences.length >= 5))
                                    ? null
                                    : () {
                                        if (isAdded) {
                                          provider.removePreference(user.dbId!, int.parse(room['id'].toString()));
                                        } else {
                                          provider.addPreference(user.dbId!, int.parse(room['id'].toString()));
                                        }
                                      },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            // Bottom Submission Bar
            if (provider.preferences.isNotEmpty)
              Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  gradient: ds.RoyalTheme.navyGradient,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          settings: const RouteSettings(name: '/priority_queue'),
                          builder: (_) => const PriorityQueueScreen(),
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.shopping_cart_outlined, color: Colors.white, size: 22),
                          ),
                          Positioned(
                            right: -5,
                            top: -5,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: ds.RoyalTheme.dangerMid,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  )
                                ],
                              ),
                              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                              child: Text(
                                '${provider.preferences.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Your Priorities', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('${provider.preferences.length} / 5 rooms selected', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 140,
                      height: 40,
                      child: ds.SkeuomorphicButton(
                        text: 'Review & Submit',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              settings: const RouteSettings(name: '/priority_queue'),
                              builder: (context) => const PriorityQueueScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
