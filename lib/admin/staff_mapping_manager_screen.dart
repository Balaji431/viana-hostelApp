import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../shared/category_provider.dart';
import '../core/models/mapping_model.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';
import '../core/api_service.dart';
import '../core/styles.dart';
import '../shared/widgets/skeuomorphic_navbar.dart';

class StaffMappingManagerScreen extends StatefulWidget {
  final String? initialHostelId;
  final bool showAppBar;
  const StaffMappingManagerScreen({
    super.key,
    this.initialHostelId,
    this.showAppBar = true,
  });

  @override
  State<StaffMappingManagerScreen> createState() => _StaffMappingManagerScreenState();
}

class _StaffMappingManagerScreenState extends State<StaffMappingManagerScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<CategoryProvider>().fetchCategories();
      if (mounted) {
        context.read<MappingProvider>().loadMappings();
        context.read<HierarchicalHostelProvider>().loadHostels();
        _loadAvailableStaff();
      }
    });
  }

  int _getHostelPriority(String? name) {
    if (name == null) return 99;
    final h = name.toLowerCase();
    if (h.contains('kaveri')) return 0;
    return 1;
  }

  int _getFloorOrderIndex(String? zoneName) {
    if (zoneName == null || zoneName.trim().isEmpty) return -1;
    final z = zoneName.trim().toLowerCase();
    if (z.contains('ground') || z.contains('g0') || z.contains('f00')) return 0;
    if (z.contains('first') || z.contains('1st') || z.contains('f01')) return 1;
    if (z.contains('second') || z.contains('2nd') || z.contains('f02')) return 2;
    if (z.contains('third') || z.contains('3rd') || z.contains('f03')) return 3;
    if (z.contains('fourth') || z.contains('4th') || z.contains('f04')) return 4;
    if (z.contains('fifth') || z.contains('5th') || z.contains('f05')) return 5;
    if (z.contains('sixth') || z.contains('6th') || z.contains('f06')) return 6;
    if (z.contains('seventh') || z.contains('7th') || z.contains('f07')) return 7;
    if (z.contains('eighth') || z.contains('8th') || z.contains('f08')) return 8;
    if (z.contains('ninth') || z.contains('9th') || z.contains('f09')) return 9;
    if (z.contains('tenth') || z.contains('10th') || z.contains('f10')) return 10;
    return 99;
  }

  void _sortMappingsList(List<LocationMapping> list) {
    list.sort((a, b) {
      final pA = _getHostelPriority(a.hostelName);
      final pB = _getHostelPriority(b.hostelName);
      final compPriority = pA.compareTo(pB);
      if (compPriority != 0) return compPriority;

      final hA = (a.hostelName ?? '').toLowerCase();
      final hB = (b.hostelName ?? '').toLowerCase();
      final compHostel = hA.compareTo(hB);
      if (compHostel != 0) return compHostel;

      final fA = _getFloorOrderIndex(a.zoneName ?? a.zoneId);
      final fB = _getFloorOrderIndex(b.zoneName ?? b.zoneId);
      final compFloor = fA.compareTo(fB);
      if (compFloor != 0) return compFloor;

      final wA = (a.subZoneName ?? a.subZoneId ?? '').toLowerCase();
      final wB = (b.subZoneName ?? b.subZoneId ?? '').toLowerCase();
      return wA.compareTo(wB);
    });
  }

  List<LocationMapping> _getFilteredMappings(List<LocationMapping> allMappings, MappingProvider mappingProvider) {
    List<LocationMapping> result;
    if (_searchQuery.trim().isEmpty) {
      result = List.from(allMappings);
    } else {
      final query = _searchQuery.trim().toLowerCase();
      result = allMappings.where((mapping) {
        final hostelName = (mapping.hostelName ?? '').toLowerCase();
        final zoneName = (mapping.zoneName ?? '').toLowerCase();
        final subZoneName = (mapping.subZoneName ?? '').toLowerCase();
        final pathLabel = mappingProvider.getLocationLabel(mapping).toLowerCase();

        if (hostelName.contains(query) ||
            zoneName.contains(query) ||
            subZoneName.contains(query) ||
            pathLabel.contains(query)) {
          return true;
        }

        for (var s in mapping.assignedStaff) {
          final sName = s.name.toLowerCase();
          final sUsername = s.username.toLowerCase();
          final sRole = s.role.toLowerCase();

          if (sName.contains(query) ||
              sUsername.contains(query) ||
              sRole.contains(query)) {
            return true;
          }
        }

        return false;
      }).toList();
    }

    _sortMappingsList(result);
    return result;
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_outlined, size: 64, color: Colors.grey.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'No Mappings Found',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade700, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'No hostel, floor, wing, or warden matched "$_searchQuery"',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  final Map<String, List<Map<String, dynamic>>> _availableStaffByRole = {};

  Future<void> _loadAvailableStaff() async {
    try {
      final res = await ApiService.getExternalStaff();
      if (!mounted) return; // Guard: widget may have been disposed while awaiting
      if (res['success'] == true) {
        final List<dynamic> staffList = res['data'] ?? [];

        // FIX 4: Pre-initialise all role buckets so lookups never return null
        final newMap = <String, List<Map<String, dynamic>>>{
          'warden': [],
          'security': [],
          'maintenance': [],
        };

        for (var emp in staffList) {
          String role = (emp['role']?.toString().toLowerCase().trim()) ?? 'staff';
          if (role.contains('maint')) {
            role = 'maintenance';
          } else if (role.contains('secur')) {
            role = 'security';
          }

          newMap.putIfAbsent(role, () => []);

          final formattedEmp = <String, dynamic>{
            'id': emp['bio_id']?.toString() ?? '',
            'bio_id': emp['bio_id']?.toString() ?? '',
            'username': emp['bio_id']?.toString() ?? '',
            'full_name': emp['name']?.toString() ?? '',
            'name': emp['name']?.toString() ?? '',
            'phone': emp['phone']?.toString() ?? '',
            'department': emp['department']?.toString() ?? '',
            'designation': emp['designation']?.toString() ?? '',
            'role': role,
            'search_key':
                '${emp['bio_id']} ${emp['name']} ${emp['department']} ${emp['designation']} (${emp['department']})'
                    .toLowerCase(),
          };

          if (role == 'security' || role == 'maintenance') {
            // FIX 1: Add to the role bucket exactly ONCE (removed the duplicate putIfAbsent add)
            newMap[role]!.add(formattedEmp);
          } else {
            // Wardens and any unrecognised roles go into the warden list
            newMap['warden']!.add(formattedEmp);
          }
        }

        // FIX 2: Assign result and call setState so any open page can read fresh data
        setState(() {
          _availableStaffByRole
            ..clear()
            ..addAll(newMap);
        });
      }
    } catch (e) {
      debugPrint('Error loading staff: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load staff members. Please check backend. ($e)')),
        );
      }
    }
  }

  Color _getRoleColor(String role) {
    final catProvider = context.read<CategoryProvider>();
    final cat = catProvider.getCategoryByName(role);
    if (cat != null) return catProvider.getColor(cat['color']);
    
    switch (role.toLowerCase()) {
      case 'warden': return const Color(0xFF4CAF50);
      case 'security': return const Color(0xFF2196F3);
      case 'maintenance':
      case 'maintenannce': return const Color(0xFFFF9800);
      default: return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    final catProvider = context.read<CategoryProvider>();
    return catProvider.getIconData(role);
  }

  @override
  Widget build(BuildContext context) {
    final mappingProvider = context.watch<MappingProvider>();
    final hostelProvider = context.watch<HierarchicalHostelProvider>();
    final filteredMappings = _getFilteredMappings(mappingProvider.mappings, mappingProvider);

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: widget.showAppBar 
          ? SkeuomorphicNavBar(
              title: 'Staff Mapping',
              onBack: Navigator.of(context).canPop() 
                ? () {
                    debugPrint("BACK BUTTON CLICKED in StaffMappingManagerScreen");
                    Navigator.of(context).pop();
                  }
                : null,
              rightAction: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: () => mappingProvider.loadMappings(),
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            )
          : null,

        body: mappingProvider.isLoading || hostelProvider.isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val.trim();
                          });
                        },
                        style: const TextStyle(fontSize: 14, color: Color(0xFF1A2744)),
                        decoration: InputDecoration(
                          hintText: 'Search hostel, floor, wing, or warden name...',
                          hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF1A2744), size: 20),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: mappingProvider.mappings.isEmpty
                        ? _buildEmptyState()
                        : filteredMappings.isEmpty
                            ? _buildNoSearchResultsState()
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), 
                                itemCount: filteredMappings.length + 1,
                                itemBuilder: (context, index) {
                                  if (index < filteredMappings.length) {
                                    return _buildEnhancedMappingCard(filteredMappings[index]);
                                  } else {
                                    return _buildAddNewMappingCard();
                                  }
                                },
                              ),
                  ),
                ],
              ),
      ),
    );
  }


  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 100, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text(
            'Ready to Map Staff?',
            style: TextStyle(fontSize: 20, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Link wardens, security, and maintenance staff to specific hostels or wings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () {
              debugPrint("ADD NEW MAPPING CLICKED from EmptyState");
              _navigateToEditMapping(context, null);
            },
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Add New Mapping'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2744),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedMappingCard(LocationMapping mapping) {
    final mappingProvider = context.read<MappingProvider>();
    final path = mappingProvider.getLocationLabel(mapping);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withValues(alpha: 0.12), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.8),
            blurRadius: 1,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2744).withValues(alpha: 0.03),
                border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08), width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2744),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_on, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          path,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A2744)),
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(Icons.meeting_room_outlined, size: 13, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '${mapping.roomCount ?? 0} Rooms',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.people_outline, size: 13, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '${mapping.assignedStaff.length} Staff',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, color: Color(0xFF2D4A7A), size: 20),
                        onPressed: () => _navigateToEditMapping(context, mapping),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: () => _confirmDelete(mapping),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            ...mapping.assignedStaff.map((staff) => _buildStaffItem(staff)),
            
            if (mapping.assignedStaff.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text('No staff assigned yet', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffItem(Staff staff) {
    final roleColor = _getRoleColor(staff.role);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.8)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: roleColor.withValues(alpha: 0.1),
            child: Icon(_getRoleIcon(staff.role), color: roleColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(staff.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 8),
                    if (staff.username.isNotEmpty)
                      Text(
                        '@${staff.username}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        staff.role,
                        style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.phone_outlined, size: 12, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Text(
                      staff.phone,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddNewMappingCard() {
    return GestureDetector(
      onTap: () {
        debugPrint("ADD NEW MAPPING CLICKED in StaffMappingManagerScreen");
        _navigateToEditMapping(context, null);
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 20),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF5EEFF), 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF7B3FC4),
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B3FC4).withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFF7B3FC4),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            const Text(
              'Add New Mapping',
              style: TextStyle(
                color: Color(0xFF7B3FC4),
                fontWeight: FontWeight.bold,
                fontSize: 16,
                fontFamily: 'Lato',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(LocationMapping mapping) async {
    final mappingProvider = context.read<MappingProvider>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Mapping?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('This will unassign all staff from ${mappingProvider.getLocationLabel(mapping)}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      mappingProvider.deleteMapping(mapping.id);
    }
  }

  /// Navigate to the full-screen Edit Mapping page instead of opening a dialog.
  void _navigateToEditMapping(BuildContext context, LocationMapping? existingMapping) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditMappingPage(
          existingMapping: existingMapping,
          availableStaffByRole: _availableStaffByRole,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// EditMappingPage — Full-screen page (replaces the old showDialog approach)
// ═══════════════════════════════════════════════════════════════════════════════

class EditMappingPage extends StatefulWidget {
  final LocationMapping? existingMapping;
  final Map<String, List<Map<String, dynamic>>> availableStaffByRole;

  const EditMappingPage({
    super.key,
    this.existingMapping,
    required this.availableStaffByRole,
  });

  @override
  State<EditMappingPage> createState() => _EditMappingPageState();
}

class _EditMappingPageState extends State<EditMappingPage> {
  HierarchicalHostel? selectedHostel;
  Zone? selectedZone;
  SubZone? selectedSubZone;
  List<Staff> currentStaff = [];
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    if (widget.existingMapping != null) {
      final hostelProvider = context.read<HierarchicalHostelProvider>();
      final existingMapping = widget.existingMapping!;
      try {
        selectedHostel = hostelProvider.hostels.firstWhere(
          (h) => h.id.toString() == existingMapping.hostelId ||
                 h.name.toLowerCase() == (existingMapping.hostelName ?? '').toLowerCase(),
          orElse: () => hostelProvider.hostels.first,
        );

        await hostelProvider.loadHostelHierarchy(selectedHostel);

        final zName = (existingMapping.zoneName ?? existingMapping.zoneId ?? '').trim();
        if (zName.isNotEmpty && selectedHostel != null && selectedHostel!.zones.isNotEmpty) {
          try {
            selectedZone = selectedHostel!.zones.firstWhere(
              (z) => z.name.trim().toLowerCase() == zName.toLowerCase() ||
                     z.id.toString().trim().toLowerCase() == zName.toLowerCase() ||
                     z.code.trim().toLowerCase() == zName.toLowerCase(),
            );
          } catch (_) {
            try {
              selectedZone = selectedHostel!.zones.firstWhere(
                (z) => z.name.toLowerCase().contains(zName.toLowerCase()) ||
                       zName.toLowerCase().contains(z.name.toLowerCase()),
              );
            } catch (_) {}
          }
        }

        final szName = (existingMapping.subZoneName ?? existingMapping.subZoneId ?? '').trim();
        if (szName.isNotEmpty && selectedZone != null) {
          if (selectedZone!.subZones.isNotEmpty) {
            try {
              selectedSubZone = selectedZone!.subZones.firstWhere(
                (sz) => sz.name.trim().toLowerCase() == szName.toLowerCase() ||
                       sz.id.toString().trim().toLowerCase() == szName.toLowerCase() ||
                       sz.code.trim().toLowerCase() == szName.toLowerCase(),
              );
            } catch (_) {
              selectedSubZone = SubZone(
                id: szName,
                zoneId: selectedZone!.id,
                name: szName,
                code: szName,
                rooms: [],
                createdAt: '',
              );
              selectedZone!.subZones.insert(0, selectedSubZone!);
            }
          } else {
            selectedSubZone = SubZone(
              id: szName,
              zoneId: selectedZone!.id,
              name: szName,
              code: szName,
              rooms: [],
              createdAt: '',
            );
            selectedZone!.subZones.add(selectedSubZone!);
          }
        }
        currentStaff = List.from(existingMapping.assignedStaff);
      } catch (e) {
        debugPrint("Error pre-populating edit page: $e");
      }
    }
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  Color _getRoleColor(String role) {
    final catProvider = context.read<CategoryProvider>();
    final cat = catProvider.getCategoryByName(role);
    if (cat != null) return catProvider.getColor(cat['color']);

    switch (role.toLowerCase()) {
      case 'warden': return const Color(0xFF4CAF50);
      case 'security': return const Color(0xFF2196F3);
      case 'maintenance':
      case 'maintenannce': return const Color(0xFFFF9800);
      default: return Colors.grey;
    }
  }

  IconData _getRoleIcon(String role) {
    final catProvider = context.read<CategoryProvider>();
    return catProvider.getIconData(role);
  }

  List<DropdownMenuItem<SubZone>> _getWingDropdownItems(Zone? zone, SubZone? currentSelection) {
    if (zone == null) return [];

    final List<SubZone> options = [];
    final Set<String> addedNames = {};

    if (currentSelection != null) {
      final name = currentSelection.name.trim();
      if (name.isNotEmpty) {
        options.add(currentSelection);
        addedNames.add(name.toLowerCase());
      }
    }

    for (var sz in zone.subZones) {
      final name = sz.name.trim();
      if (name.isNotEmpty && !addedNames.contains(name.toLowerCase())) {
        options.add(sz);
        addedNames.add(name.toLowerCase());
      }
    }

    final standardWings = ['W0', 'WC1', 'WD1', 'WE1', 'WA0', 'WB0', 'Wing A', 'Wing B', 'Wing C', 'Wing D', 'Wing E', 'General', 'N/A'];
    for (var wName in standardWings) {
      if (!addedNames.contains(wName.toLowerCase())) {
        options.add(SubZone(
          id: wName,
          zoneId: zone.id,
          name: wName,
          code: wName,
          rooms: [],
          createdAt: '',
        ));
        addedNames.add(wName.toLowerCase());
      }
    }

    return options.map((sz) => DropdownMenuItem<SubZone>(
      value: sz,
      child: Text(sz.name),
    )).toList();
  }

  Widget _buildDropdown<T>({required String label, required T? value, required List<DropdownMenuItem<T>> items, required Function(T?) onChanged, bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: enabled ? items : [],
          onChanged: enabled ? onChanged : null,
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          hint: Text(enabled ? 'Choose one...' : 'N/A', style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildEditableStaffItem(Staff staff, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 12, backgroundColor: _getRoleColor(staff.role).withValues(alpha: 0.1), child: Icon(_getRoleIcon(staff.role), size: 12, color: _getRoleColor(staff.role))),
          const SizedBox(width: 12),
          Expanded(child: Text(staff.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            onPressed: () async {
              final result = await Navigator.of(context).push<Staff>(
                MaterialPageRoute(
                  builder: (_) => AddStaffPage(
                    availableStaffByRole: widget.availableStaffByRole,
                    currentStaff: currentStaff,
                    existingMapping: widget.existingMapping,
                    existing: staff,
                  ),
                ),
              );
              if (result != null && mounted) {
                setState(() => currentStaff[index] = result);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
            onPressed: () => setState(() => currentStaff.removeAt(index)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hostelProvider = context.watch<HierarchicalHostelProvider>();
    final mappingProvider = context.read<MappingProvider>();

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: 'Edit Mapping',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: _isInitializing
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
              )
            : Column(
                children: [
                  Expanded(
                    child: _buildFormFields(hostelProvider),
                  ),
                  _buildSaveButton(mappingProvider),
                ],
              ),
      ),
    );
  }

  Widget _buildFormFields(HierarchicalHostelProvider hostelProvider) {
    String previewPath = selectedHostel?.name ?? 'Select Location';
    if (selectedZone != null) previewPath += ' › ${selectedZone!.name}';
    if (selectedSubZone != null) previewPath += ' › ${selectedSubZone!.name}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDropdown<HierarchicalHostel>(
            label: 'Select Hostel *',
            value: selectedHostel,
            items: hostelProvider.hostels.map((h) => DropdownMenuItem(value: h, child: Text(h.name))).toList(),
            onChanged: (val) async {
              if (val != null) {
                setState(() {
                  selectedHostel = val;
                  selectedZone = null;
                  selectedSubZone = null;
                });
                await hostelProvider.loadHostelHierarchy(val);
                if (mounted) setState(() {});
              }
            },
          ),
          const SizedBox(height: 16),
          if (selectedHostel != null && selectedHostel!.zones.isEmpty && hostelProvider.isLoading)
            const Center(child: LinearProgressIndicator())
          else
            _buildDropdown<Zone>(
              label: 'Select Floor (Optional)',
              value: selectedZone,
              enabled: selectedHostel != null && selectedHostel!.zones.isNotEmpty,
              items: selectedHostel?.zones.map((z) => DropdownMenuItem(value: z, child: Text(z.name))).toList() ?? [],
              onChanged: (val) {
                setState(() {
                  selectedZone = val;
                  selectedSubZone = (val != null && val.subZones.isNotEmpty) ? val.subZones.first : null;
                });
              },
            ),
          const SizedBox(height: 16),
          _buildDropdown<SubZone>(
            label: 'Select Wing (Optional)',
            value: selectedSubZone,
            enabled: selectedZone != null,
            items: _getWingDropdownItems(selectedZone, selectedSubZone),
            onChanged: (val) => setState(() => selectedSubZone = val),
          ),

          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFFD4AF37), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(previewPath, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1A2744)))),
              ],
            ),
          ),

          const SizedBox(height: 32),
          const Text('Assigned Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          ...currentStaff.asMap().entries.map((entry) => _buildEditableStaffItem(entry.value, entry.key)),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final result = await Navigator.of(context).push<Staff>(
                MaterialPageRoute(
                  builder: (_) => AddStaffPage(
                    availableStaffByRole: widget.availableStaffByRole,
                    currentStaff: currentStaff,
                    existingMapping: widget.existingMapping,
                  ),
                ),
              );
              if (result != null && mounted) {
                setState(() => currentStaff.add(result));
              }
            },
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add Staff Member'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1A2744),
              padding: const EdgeInsets.symmetric(vertical: 12),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(MappingProvider mappingProvider) {
    final existingMapping = widget.existingMapping;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: (selectedHostel != null && currentStaff.isNotEmpty) ? () async {
                  final updatedMapping = LocationMapping(
                    id: existingMapping?.id ?? '',
                    hostelId: selectedHostel!.id.toString(),
                    hostelName: selectedHostel!.name,
                    zoneId: selectedZone?.id.toString(),
                    zoneName: selectedZone?.name,
                    subZoneId: selectedSubZone?.id.toString(),
                    subZoneName: selectedSubZone?.name,
                    assignedStaff: currentStaff.map((s) {
                      return Staff(
                        id: s.id,
                        name: s.name,
                        role: s.role,
                        phone: s.phone,
                        username: s.username,
                        hostelName: selectedHostel!.name,
                        floorName: selectedZone?.name,
                        wingName: selectedSubZone?.name,
                      );
                    }).toList(),
                  );
                  final error = await mappingProvider.saveMapping(updatedMapping);
                  if (!mounted) return;
                  if (error == null) {
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(error),
                        backgroundColor: Colors.red.shade800,
                      ),
                    );
                  }
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A2744),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// AddStaffPage — Full-screen page (replaces the old showDialog approach)
// ═══════════════════════════════════════════════════════════════════════════════

class AddStaffPage extends StatefulWidget {
  final Map<String, List<Map<String, dynamic>>> availableStaffByRole;
  final List<Staff> currentStaff;
  final LocationMapping? existingMapping;
  final Staff? existing;

  const AddStaffPage({
    super.key,
    required this.availableStaffByRole,
    required this.currentStaff,
    this.existingMapping,
    this.existing,
  });

  @override
  State<AddStaffPage> createState() => _AddStaffPageState();
}

class _AddStaffPageState extends State<AddStaffPage> {
  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  late final TextEditingController usernameController;
  late final TextEditingController searchController;

  List<String> roles = ['Warden', 'Security', 'Maintenance'];
  late String selectedRole;
  Map<String, dynamic>? selectedStaffUser;
  bool showDropdown = false;
  bool _rolesInitialized = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.existing?.name);
    phoneController = TextEditingController(text: widget.existing?.phone);
    usernameController = TextEditingController(text: widget.existing?.username);
    searchController = TextEditingController();
    selectedRole = widget.existing?.role ?? 'Warden';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_rolesInitialized) {
      _rolesInitialized = true;
      final catProvider = context.read<CategoryProvider>();
      final Set<String> rolesSet = {};
      for (var r in ['Warden', 'Security', 'Maintenance']) {
        rolesSet.add(r);
      }
      for (var c in catProvider.categories) {
        if ((c['is_staff_role'] ?? 1) == 1) {
          String name = c['name']?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            if (name.toLowerCase().contains('warden')) {
              name = 'Warden';
            } else if (name.toLowerCase().contains('secur')) {
              name = 'Security';
            } else if (name.toLowerCase().contains('maint')) {
              name = 'Maintenance';
            }
            rolesSet.add(name);
          }
        }
      }
      roles = rolesSet.toList();
      if (widget.existing?.role != null && roles.contains(widget.existing!.role)) {
        selectedRole = widget.existing!.role;
      } else if (!roles.contains(selectedRole)) {
        selectedRole = roles.first;
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    usernameController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Color _getRoleColor(String role) {
    final catProvider = context.read<CategoryProvider>();
    final cat = catProvider.getCategoryByName(role);
    if (cat != null) return catProvider.getColor(cat['color']);

    switch (role.toLowerCase()) {
      case 'warden': return const Color(0xFF4CAF50);
      case 'security': return const Color(0xFF2196F3);
      case 'maintenance':
      case 'maintenannce': return const Color(0xFFFF9800);
      default: return Colors.grey;
    }
  }

  void _confirmAndPop() {
    final rawName = nameController.text.trim().isNotEmpty
        ? nameController.text.trim()
        : (selectedStaffUser?['full_name'] ?? selectedStaffUser?['name'] ?? 'Staff').toString();
    final cleanName = rawName.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
    final sPhone = phoneController.text.trim().isNotEmpty
        ? phoneController.text.trim()
        : (selectedStaffUser?['phone']?.toString() ?? '');
    final sBioId = usernameController.text.trim().isNotEmpty
        ? usernameController.text.trim()
        : (selectedStaffUser?['username']?.toString() ?? selectedStaffUser?['bio_id']?.toString() ?? cleanName.replaceAll(' ', '_').toLowerCase());

    debugPrint('=== [STAFF PAGE DEBUG] Confirm Clicked! ===');
    debugPrint('  Adding Staff: id=$sBioId, name=$cleanName, role=$selectedRole, phone=$sPhone');

    Navigator.pop(
      context,
      Staff(
        id: sBioId,
        name: cleanName,
        role: selectedRole,
        phone: sPhone,
        username: sBioId,
        hostelName: widget.existingMapping?.hostelName,
        floorName: widget.existingMapping?.zoneName ?? widget.existingMapping?.zoneId,
        wingName: widget.existingMapping?.subZoneName ?? widget.existingMapping?.subZoneId ?? 'All',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String roleKey = selectedRole.toLowerCase();
    if (roleKey.contains('maint')) {
      roleKey = 'maintenance';
    } else if (roleKey.contains('secur')) {
      roleKey = 'security';
    }
    final availableStaff = widget.availableStaffByRole[roleKey] ?? [];

    if (widget.existing != null && selectedStaffUser == null && availableStaff.isNotEmpty) {
      try {
        selectedStaffUser = availableStaff.firstWhere(
          (u) => u['phone'] == widget.existing!.phone || (u['full_name'] == widget.existing!.name && u['phone'] == widget.existing!.phone),
          orElse: () => availableStaff.first,
        );
      } catch (_) {}
    }

    final String searchFilter = searchController.text.trim().toLowerCase();
    final matchingStaff = availableStaff.where((u) {
      if (searchFilter.isEmpty) return true;
      final bio = (u['username'] ?? u['bio_id'] ?? '').toString().toLowerCase();
      final fn  = (u['full_name'] ?? u['name'] ?? '').toString().toLowerCase();
      final sk  = (u['search_key'] ?? '').toString().toLowerCase();
      return bio.contains(searchFilter) || fn.contains(searchFilter) || sk.contains(searchFilter);
    }).toList();

    final bool canConfirm = nameController.text.trim().isNotEmpty || selectedStaffUser != null;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: widget.existing == null ? 'Add Staff' : 'Edit Staff',
          onBack: () => Navigator.of(context).pop(),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ROLE SECTION
                        const Text(
                          'Role',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2744),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: roles.map((role) {
                            bool isSelected = selectedRole == role;
                            final roleColor = _getRoleColor(role);
                            return ChoiceChip(
                              avatar: Icon(
                                role.toLowerCase().contains('warden')
                                    ? Icons.shield_outlined
                                    : role.toLowerCase().contains('secur')
                                        ? Icons.security_outlined
                                        : Icons.build_outlined,
                                size: 16,
                                color: isSelected ? roleColor : Colors.grey.shade600,
                              ),
                              label: Text(role),
                              selected: isSelected,
                              onSelected: (val) {
                                setState(() {
                                  selectedRole = role;
                                  selectedStaffUser = null;
                                  nameController.clear();
                                  phoneController.clear();
                                  usernameController.clear();
                                  searchController.clear();
                                  showDropdown = false;
                                });
                              },
                              selectedColor: roleColor.withValues(alpha: 0.15),
                              checkmarkColor: roleColor,
                              side: BorderSide(
                                color: isSelected ? roleColor : Colors.grey.shade300,
                                width: isSelected ? 1.5 : 1,
                              ),
                              labelStyle: TextStyle(
                                color: isSelected ? roleColor : Colors.black87,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                fontSize: 13,
                              ),
                              backgroundColor: Colors.grey.shade50,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 28),

                        // SELECT PERSON SECTION
                        const Text(
                          'Select Person',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2744),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: searchController,
                          onTap: () {
                            setState(() {
                              showDropdown = true;
                            });
                          },
                          onChanged: (val) {
                            setState(() {
                              showDropdown = true;
                            });
                          },
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A2744), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF1A2744), size: 22),
                            hintText: 'Search or select staff person...',
                            hintStyle: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          ),
                        ),
                        if (showDropdown && matchingStaff.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: matchingStaff.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                              itemBuilder: (context, index) {
                                final staffItem = matchingStaff[index];
                                final String sName = (staffItem['full_name'] ?? staffItem['name'] ?? staffItem['username'] ?? 'Unknown').toString();
                                final String sDept = (staffItem['department'] ?? 'Staff').toString();
                                final String sPhone = (staffItem['phone'] ?? '').toString();
                                final String sBioId = (staffItem['username'] ?? staffItem['bio_id'] ?? '').toString();

                                final bool isSelected = (selectedStaffUser?['bio_id'] == sBioId) || (nameController.text == sName);

                                return Material(
                                  color: isSelected ? const Color(0xFF1A2744).withValues(alpha: 0.08) : Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      debugPrint('=== [STAFF SELECTOR TAP] Selected: $sName ($sBioId, $sPhone) ===');
                                      setState(() {
                                        selectedStaffUser = staffItem;
                                        nameController.text = sName;
                                        phoneController.text = sPhone;
                                        usernameController.text = sBioId;
                                        searchController.text = '$sName ($sDept)';
                                        showDropdown = false;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: _getRoleColor(selectedRole).withValues(alpha: 0.15),
                                            child: Icon(Icons.person, size: 16, color: _getRoleColor(selectedRole)),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  sName,
                                                  style: TextStyle(
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                    fontSize: 14,
                                                    color: isSelected ? const Color(0xFF1A2744) : Colors.black87,
                                                  ),
                                                ),
                                                Text(
                                                  '$sDept ${sBioId.isNotEmpty ? "• ID: $sBioId" : ""} ${sPhone.isNotEmpty ? "• Ph: $sPhone" : ""}',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(Icons.check_circle, color: Color(0xFF1A2744), size: 20),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        if (availableStaff.isEmpty && selectedRole.toLowerCase() == 'warden')
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'No active warden users are available. Create the user first through User Management.',
                              style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),

                        const SizedBox(height: 28),

                        // STAFF DETAILS SECTION
                        const Text(
                          'Phone Number',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2744),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: phoneController,
                          readOnly: false,
                          onChanged: (v) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Enter phone number',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A2744), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            prefixIcon: const Icon(Icons.phone, color: Color(0xFF1A2744), size: 22),
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Username / Staff Bio ID',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2744),
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: usernameController,
                          readOnly: false,
                          onChanged: (v) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Enter Username / Bio ID',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF1A2744), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF1A2744), size: 22),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom action buttons
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: canConfirm ? _confirmAndPop : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A2744),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              disabledBackgroundColor: Colors.grey.shade300,
                            ),
                            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
