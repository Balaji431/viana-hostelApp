import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../shared/category_provider.dart';
import '../core/models/mapping_model.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';
import '../core/api_service.dart';
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

  final Map<String, List<Map<String, dynamic>>> _availableStaffByRole = {};

  Future<void> _loadAvailableStaff() async {
    try {
      final catProvider = context.read<CategoryProvider>();
      final roles = catProvider.categories
          .where((c) => (c['is_staff_role'] ?? 1) == 1)
          .map((c) => (c['name'] as String).toLowerCase())
          .toList();
      if (roles.isEmpty) roles.addAll(['warden', 'security', 'maintenance']);
      
      for (var role in roles) {
        final res = await ApiService.getUsersByRole(role);
        if (res['success'] == true) {
          _availableStaffByRole[role] = List<Map<String, dynamic>>.from(res['data'] ?? []);
        }
      }
    } catch (e) {
      debugPrint('Error loading staff: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load staff members. Please check backend. ($e)')),
        );
      }
    } finally {
      // Done loading
    }
  }

  Color _getRoleColor(String role) {
    final catProvider = context.read<CategoryProvider>();
    final cat = catProvider.getCategoryByName(role);
    if (cat != null) return catProvider.getColor(cat['color']);
    
    switch (role.toLowerCase()) {
      case 'warden': return const Color(0xFF4CAF50);
      case 'security': return const Color(0xFF2196F3);
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: widget.showAppBar 
        ? SkeuomorphicNavBar(
            title: 'Staff Mapping',
            onBack: () => Navigator.of(context).pop(),
            rightAction: IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              onPressed: () => mappingProvider.loadMappings(),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          )
        : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRegisterStaffDialog(context),
        backgroundColor: const Color(0xFF1A2744),
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: const Text('New Staff', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Georgia')),
        elevation: 8,
      ),
      body: mappingProvider.isLoading || hostelProvider.isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
          : Column(
              children: [
                Expanded(
                  child: mappingProvider.mappings.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), 
                          itemCount: mappingProvider.mappings.length + 1,
                          itemBuilder: (context, index) {
                            if (index < mappingProvider.mappings.length) {
                              return _buildEnhancedMappingCard(mappingProvider.mappings[index]);
                            } else {
                              return _buildAddNewMappingCard();
                            }
                          },
                        ),
                ),
              ],
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
            onPressed: () => _showEditMappingDialog(context, null),
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2744).withValues(alpha: 0.03),
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
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
                        onPressed: () => _showEditMappingDialog(context, mapping),
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
        border: Border(bottom: BorderSide(color: Colors.grey.shade50)),
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
      onTap: () => _showEditMappingDialog(context, null),
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 20),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFF5EEFF), 
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF7B3FC4).withValues(alpha: 0.5),
            width: 1.5,
          ),
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
                fontFamily: 'Georgia',
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

  void _showEditMappingDialog(BuildContext context, LocationMapping? existingMapping) {
    final hostelProvider = context.read<HierarchicalHostelProvider>();
    final mappingProvider = context.read<MappingProvider>();
    
    HierarchicalHostel? selectedHostel;
    Zone? selectedZone;
    SubZone? selectedSubZone;
    List<Staff> currentStaff = [];

    Future<void>? initFuture;
    if (existingMapping != null) {
      initFuture = () async {
        try {
          selectedHostel = hostelProvider.hostels.firstWhere((h) => h.id.toString() == existingMapping.hostelId);
          await hostelProvider.loadHostelHierarchy(selectedHostel);
          
          final zId = existingMapping.zoneName ?? existingMapping.zoneId ?? '';
          if (zId.isNotEmpty && selectedHostel!.zones.isNotEmpty) {
            try {
              selectedZone = selectedHostel!.zones.firstWhere(
                (z) => z.name == zId || z.id.toString() == zId,
              );
            } catch (_) {
              // zone not found — leave unselected
            }
          }
          
          final szId = existingMapping.subZoneName ?? existingMapping.subZoneId ?? '';
          if (szId.isNotEmpty && selectedZone != null && selectedZone!.subZones.isNotEmpty) {
            try {
              selectedSubZone = selectedZone!.subZones.firstWhere(
                (sz) => sz.name == szId || sz.id.toString() == szId,
              );
            } catch (_) {
              // sub-zone not found — leave unselected
            }
          }
          currentStaff = List.from(existingMapping.assignedStaff);
        } catch (e) {
          debugPrint("Error pre-populating edit dialog: $e");
        }
      }();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget buildFormFields() {
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
                        setDialogState(() {
                          selectedHostel = val;
                          selectedZone = null;
                          selectedSubZone = null;
                        });
                        await hostelProvider.loadHostelHierarchy(val);
                        setDialogState(() {}); 
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
                        setDialogState(() {
                          selectedZone = val;
                          selectedSubZone = null;
                        });
                      },
                    ),
                  const SizedBox(height: 16),
                  _buildDropdown<SubZone>(
                    label: 'Select Wing (Optional)',
                    value: selectedSubZone,
                    enabled: selectedZone != null && selectedZone!.subZones.isNotEmpty,
                    items: selectedZone?.subZones.map((sz) => DropdownMenuItem(value: sz, child: Text(sz.name))).toList() ?? [],
                    onChanged: (val) => setDialogState(() => selectedSubZone = val),
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
                  ...currentStaff.asMap().entries.map((entry) => _buildEditableStaffItem(entry.value, () {
                    setDialogState(() => currentStaff.removeAt(entry.key));
                  }, (updated) {
                    setDialogState(() => currentStaff[entry.key] = updated);
                  })),
                  
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _showAddStaffDialog(context, (newStaff) {
                      setDialogState(() => currentStaff.add(newStaff));
                    }),
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

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              width: MediaQuery.of(context).size.width * 0.95,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A2744),
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                    ),
                    child: Row(
                      children: [
                        const Text('Edit Mapping', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  
                  Flexible(
                    child: initFuture != null
                        ? FutureBuilder<void>(
                            future: initFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState != ConnectionState.done) {
                                return const SizedBox(
                                  height: 250,
                                  child: Center(
                                    child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                                  ),
                                );
                              }
                              return buildFormFields();
                            },
                          )
                        : buildFormFields(),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.all(24),
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
                              final success = await mappingProvider.saveMapping(updatedMapping);
                              if (success && context.mounted) Navigator.pop(context);
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDropdown<T>({required String label, required T? value, required List<DropdownMenuItem<T>> items, required Function(T?) onChanged, bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          value: value,
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

  Widget _buildEditableStaffItem(Staff staff, VoidCallback onRemove, Function(Staff) onEdit) {
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
          IconButton(icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey), onPressed: () => _showAddStaffDialog(context, onEdit, existing: staff)),
          IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.redAccent), onPressed: onRemove),
        ],
      ),
    );
  }

  void _showAddStaffDialog(BuildContext context, Function(Staff) onAdd, {Staff? existing}) {
    final nameController = TextEditingController(text: existing?.name);
    final phoneController = TextEditingController(text: existing?.phone);
    final usernameController = TextEditingController(text: existing?.username);
    final catProvider = context.read<CategoryProvider>();
    final roles = catProvider.categories
        .where((c) => (c['is_staff_role'] ?? 1) == 1)
        .map((c) => c['name'] as String)
        .toList();
    if (roles.isEmpty) roles.add('Warden'); 

    String selectedRole = existing?.role ?? roles.first;
    Map<String, dynamic>? selectedStaffUser;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableStaff = _availableStaffByRole[selectedRole.toLowerCase()] ?? [];
          
          if (existing != null && selectedStaffUser == null && availableStaff.isNotEmpty) {
            try {
              selectedStaffUser = availableStaff.firstWhere(
                (u) => u['phone'] == existing.phone || (u['full_name'] == existing.name && u['phone'] == existing.phone),
                orElse: () => availableStaff.first,
              );
            } catch (_) {}
          }
          
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Text(existing == null ? 'Add Staff' : 'Edit Staff', style: const TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: Text('Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: roles.map((role) {
                      bool isSelected = selectedRole == role;
                      return ChoiceChip(
                        label: Text(role),
                        selected: isSelected,
                        onSelected: (val) {
                          setDialogState(() {
                            selectedRole = role;
                            selectedStaffUser = null;
                            nameController.clear();
                            phoneController.clear();
                            usernameController.clear();
                          });
                        },
                        selectedColor: _getRoleColor(role).withValues(alpha: 0.2),
                        checkmarkColor: _getRoleColor(role),
                        labelStyle: TextStyle(color: isSelected ? _getRoleColor(role) : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                        backgroundColor: Colors.grey.shade100,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Person', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: selectedStaffUser,
                        items: availableStaff.map((u) => DropdownMenuItem(
                          value: u,
                          child: Text(u['full_name'] ?? u['username'] ?? 'Unknown'),
                        )).toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedStaffUser = val;
                            if (val != null) {
                              nameController.text = val['full_name'] ?? val['username'] ?? '';
                              phoneController.text = val['phone'] ?? '';
                              usernameController.text = val['username'] ?? '';
                            }
                          });
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          prefixIcon: const Icon(Icons.person),
                        ),
                        hint: Text(availableStaff.isEmpty ? 'No $selectedRole found' : 'Choose staff member...', style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  TextField(
                    controller: phoneController,
                    readOnly: true, 
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: 'Auto-populated',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.phone),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: usernameController,
                    readOnly: true, 
                    decoration: InputDecoration(
                      labelText: 'Username',
                      hintText: 'Auto-populated',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.alternate_email),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: (nameController.text.isNotEmpty) ? () {
                  onAdd(Staff(
                    id: selectedStaffUser?['id']?.toString() ?? existing?.id ?? '', 
                    name: nameController.text, 
                    role: selectedRole, 
                    phone: phoneController.text, 
                    username: usernameController.text
                  ));
                  Navigator.pop(context);
                } : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A2744),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: Colors.grey.shade300,
                ),
                child: const Text('Confirm', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRegisterStaffDialog(BuildContext context) {
    final nameController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final phoneController = TextEditingController();
    final catProvider = context.read<CategoryProvider>();
    final roles = catProvider.categories
        .where((c) => (c['is_staff_role'] ?? 1) == 1)
        .map((c) => c['name'] as String)
        .toList();
    if (roles.isEmpty) roles.addAll(['Warden', 'Security', 'Maintenance']);

    String selectedRole = roles.first;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            width: MediaQuery.of(context).size.width * 0.95,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: 5)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1A2744), Color(0xFF2D4A7A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.person_add, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: const Text(
                          'New Staff Member',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Georgia'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A2744))),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: roles.map((role) {
                            bool isSelected = selectedRole == role;
                            return GestureDetector(
                              onTap: () => setDialogState(() => selectedRole = role),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF1A2744) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isSelected ? const Color(0xFF1A2744) : Colors.grey.shade300),
                                ),
                                child: Text(
                                  role,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        
                        _buildStyledField(
                          label: 'Full Name',
                          controller: nameController,
                          icon: Icons.badge_outlined,
                          hint: 'Enter staff member\'s full name',
                        ),
                        const SizedBox(height: 16),
                        
                        _buildStyledField(
                          label: 'Username / Reg No',
                          controller: usernameController,
                          icon: Icons.alternate_email_rounded,
                          hint: 'e.g., warden_rajesh',
                        ),
                        const SizedBox(height: 16),
                        
                        _buildStyledField(
                          label: 'Login Password',
                          controller: passwordController,
                          icon: Icons.lock_outline_rounded,
                          hint: 'Set a secure password',
                          isPassword: true,
                        ),
                        const SizedBox(height: 16),
                        
                        _buildStyledField(
                          label: 'Phone Number',
                          controller: phoneController,
                          icon: Icons.phone_android_rounded,
                          hint: 'Primary contact number',
                          keyboardType: TextInputType.phone,
                        ),
                      ],
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isSaving ? null : () async {
                            if (nameController.text.isEmpty || usernameController.text.isEmpty || passwordController.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill all required fields')),
                              );
                              return;
                            }

                            setDialogState(() => isSaving = true);
                            try {
                              final res = await ApiService.registerStaff(
                                fullName: nameController.text,
                                username: usernameController.text,
                                password: passwordController.text,
                                role: selectedRole,
                                phone: phoneController.text,
                              );

                              if (res['success'] == true) {
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Staff member registered successfully')),
                                  );
                                  _loadAvailableStaff(); 
                                }
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(res['message'] ?? 'Registration failed')),
                                  );
                                }
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            } finally {
                              setDialogState(() => isSaving = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A2744),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 5,
                          ),
                          child: isSaving 
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Register Staff', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            prefixIcon: Icon(icon, color: const Color(0xFF1A2744), size: 20),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
