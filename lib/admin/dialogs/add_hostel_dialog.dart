import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:io' as io;

import '../../core/api_service.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';
import 'csv_helper_stub.dart'
    if (dart.library.html) 'csv_helper_web.dart'
    if (dart.library.io) 'csv_helper_mobile.dart';

enum AddHostelMode { initial, manual, csv }

class AddHostelDialog extends StatefulWidget {
  final HierarchicalHostel? hostel;
  const AddHostelDialog({super.key, this.hostel});

  @override
  State<AddHostelDialog> createState() => _AddHostelDialogState();
}

class _AddHostelDialogState extends State<AddHostelDialog> {
  AddHostelMode _mode = AddHostelMode.initial;
  int _currentStep = 0;
  bool _isLoading = false;
  bool _isEditMode = false;

  final List<Map<String, String>> _hostelsList = [
    {'name': 'Kaveri Hostel (T12)', 'code': 'T12'},
    {'name': 'Kaveri Hostel (T-12)', 'code': 'T-12'},
    {'name': 'Krishna Hostel', 'code': 'T-30'},
    {'name': 'Noyyal Hostel', 'code': 'T22'},
    {'name': 'Palar Hostel', 'code': 'T10'},
    {'name': 'Ponni Hostel', 'code': 'T09'},
    {'name': 'Siruvani Hostel', 'code': 'T-14'},
    {'name': 'Vaigai Hostel', 'code': 'T-32'},
    {'name': 'Porunai Hostel (4F - 8F )', 'code': 'T-19'},
    {'name': 'Stunners Den', 'code': 'P10'},
    {'name': 'Radiance Inn (P-05)', 'code': 'P-05'},
    {'name': 'Max Fax', 'code': 'P05'},
  ];

  List<Map<String, dynamic>> _externalRoomTypes = [];

  // Step 1: Basic Info Controllers
  String selectedCampus = 'Thandalam Campus';
  final hostelController = TextEditingController();
  final typeController = TextEditingController(text: 'Girls');
  final codeController = TextEditingController(text: 'T32');

  // Step 2: Floors
  final floorController = TextEditingController();
  final floorCodeController = TextEditingController();
  List<Map<String, String>> floors = [];

  // Step 3: Wings
  final wingController = TextEditingController();
  final wingCodeController = TextEditingController();
  List<Map<String, String>> wings = [];

  // Step 4: Rooms
  final roomController = TextEditingController();
  String selectedFloor = 'All';
  String selectedWing = '';
  String _roomType = 'AC';
  List<Map<String, dynamic>> rooms = [];
  List<Map<String, dynamic>> _masterRooms = [];
  String? selectedRoomNo;

  @override
  void initState() {
    super.initState();
    _fetchExternalRoomTypes();
    if (widget.hostel != null) {
      _isEditMode = true;
      _mode = AddHostelMode.manual;
      final h = widget.hostel!;
      selectedCampus = h.campus;
      hostelController.text = h.name;
      typeController.text = h.type.isEmpty ? 'Girls' : h.type;
      codeController.text = h.buildingCode;
      
      for (var zone in h.zones) {
        wings.add({'name': zone.name, 'code': zone.name});
      }
      if (wings.isNotEmpty) selectedWing = wings.first['name']!;
      
      Set<String> floorSet = {};
      for (var zone in h.zones) {
        for (var subZone in zone.subZones) {
          if (!floorSet.contains(subZone.name)) {
            floors.add({'name': subZone.name, 'code': subZone.name});
            floorSet.add(subZone.name);
          }
        }
      }
      if (floors.isNotEmpty) selectedFloor = floors.first['name']!;

      for (var zone in h.zones) {
        for (var subZone in zone.subZones) {
          for (var room in subZone.rooms) {
            rooms.add({
              'id': room.id,
              'room_number': room.roomNumber,
              'room_code': room.roomCode,
              'capacity': room.capacity,
              'floor': subZone.name,
              'wing': zone.name,
              'amount': room.amount,
              'type': room.facility,
            });
          }
        }
      }
    }
  }

  Future<void> _fetchExternalRoomTypes() async {
    try {
      final res = await ApiService.getRequest('rooms/fetch_external_room_types.php');
      if (res['success'] == true || res['status'] == 'success') {
        final List<dynamic> list = res['data'] ?? [];
        setState(() {
          _externalRoomTypes = list.map((item) => item is Map ? Map<String, dynamic>.from(item) : {'id': item.toString(), 'name': item.toString()}).toList();
          if (_externalRoomTypes.isNotEmpty) {
            _roomType = _externalRoomTypes.first['name'].toString();
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching room types: $e');
    }
  }

  String _getFloorCode(String floorName) {
    switch (floorName.toLowerCase()) {
      case 'ground': return 'F00';
      case 'first': return 'F01';
      case 'second': return 'F02';
      case 'third': return 'F03';
      case 'fourth': return 'F04';
      case 'fifth': return 'F05';
      case 'sixth': return 'F06';
      case 'seventh': return 'F07';
      case 'eighth': return 'F08';
      case 'ninth': return 'F09';
      case 'tenth': return 'F10';
      case 'eleventh': return 'F11';
      case 'twelfth': return 'F12';
      case 'thirteenth': return 'F13';
      case 'fourteenth': return 'F14';
      case 'fifteenth': return 'F15';
      default: return 'F00';
    }
  }

  Future<void> _fetchRoomsFromMaster(String buildingCode) async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getRequest('rooms/fetch_room_master.php?building_code=${Uri.encodeComponent(buildingCode)}&t=${DateTime.now().millisecondsSinceEpoch}');
      if (res['success'] == true || res['status'] == 'success') {
        final List<dynamic> list = res['data'] ?? [];
        
        final Set<String> floorSet = {};
        final List<Map<String, String>> tempFloors = [];
        
        final Set<String> wingSet = {};
        final List<Map<String, String>> tempWings = [];
        
        final List<Map<String, dynamic>> tempRooms = [];
        
        for (var item in list) {
          final floorName = item['floor_no'] ?? 'Ground';
          final floorCode = _getFloorCode(floorName);
          if (!floorSet.contains(floorName)) {
            floorSet.add(floorName);
            tempFloors.add({'name': floorName, 'code': floorCode});
          }
          
          final wingName = item['block_no'] ?? 'General';
          if (!wingSet.contains(wingName)) {
            wingSet.add(wingName);
            tempWings.add({'name': wingName, 'code': wingName});
          }
          
          final roomNo = item['room_no'] ?? '';
          final facility = item['room_type'] ?? 'AC';
          final capacity = int.tryParse(item['room_capacity']?.toString() ?? '') ?? _extractCapacity(facility);
          
          final prefixCode = (buildingCode == 'T-14') ? 'T14' 
              : ((buildingCode == 'T-12') ? 'T12' 
              : ((buildingCode == 'P05') ? 'P04' 
              : ((buildingCode == 'P-05') ? 'P05' 
              : buildingCode)));
          tempRooms.add({
            'room_number': roomNo,
            'room_code': '$prefixCode-$floorCode-$wingName-$roomNo',
            'capacity': capacity,
            'floor': floorName,
            'wing': wingName,
            'amount': 0.0,
            'type': facility,
          });
        }
        
        final floorOrder = {
          'ground': 0, 'first': 1, 'second': 2, 'third': 3, 'fourth': 4,
          'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9,
          'tenth': 10, 'eleventh': 11, 'twelfth': 12, 'thirteenth': 13,
          'fourteenth': 14, 'fifteenth': 15
        };
        tempFloors.sort((a, b) {
          final aOrder = floorOrder[a['name']!.toLowerCase()] ?? 99;
          final bOrder = floorOrder[b['name']!.toLowerCase()] ?? 99;
          return aOrder.compareTo(bOrder);
        });
        
        setState(() {
          floors = tempFloors;
          wings = tempWings;
          rooms = tempRooms;
          _masterRooms = List<Map<String, dynamic>>.from(tempRooms);
          selectedFloor = 'All';
          if (wings.isNotEmpty) selectedWing = wings.first['name']!;
          selectedRoomNo = null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching master rooms: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleStepContinue() {
    if (_currentStep == 0) {
      if (hostelController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a Hostel Name before proceeding'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    }
  }

  void _handleStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 950, 
          maxHeight: size.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F2ED),
            borderRadius: BorderRadius.circular(24),
          ),
          child: _mode == AddHostelMode.initial 
              ? Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Add Hostel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
                          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                        ],
                      ),
                      const Divider(),
                      _buildSelectionView(),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == AddHostelMode.manual) _buildStepNavigator(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _isEditMode 
                                      ? 'Edit Hostel' 
                                      : (_mode == AddHostelMode.csv ? 'CSV Import' : 'Add New Hostel'),
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A2744)),
                                ),
                                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                              ],
                            ),
                            const Divider(height: 20),
                            Expanded(
                              child: _buildContent(),
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

  Widget _buildStepNavigator() {
    final stepTitles = ['Basic', 'Floors', 'Wings', 'Rooms', 'Review'];
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: Color(0xFF141E2E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SETUP WIZARD',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2.0),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stepTitles.length,
              separatorBuilder: (context, index) => Container(
                margin: const EdgeInsets.only(left: 14),
                height: 30,
                width: 2,
                color: _currentStep > index ? const Color(0xFFD4AF37) : Colors.white10,
              ),
              itemBuilder: (context, index) {
                final bool isActive = _currentStep == index;
                final bool isCompleted = _currentStep > index;
                return Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? const Color(0xFFD4AF37)
                            : (isActive ? Colors.white : Colors.transparent),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted 
                              ? const Color(0xFFD4AF37) 
                              : (isActive ? Colors.white : Colors.white24),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: isCompleted
                            ? const Icon(Icons.check, size: 16, color: Color(0xFF141E2E))
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: isActive ? const Color(0xFF141E2E) : Colors.white70,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      stepTitles[index],
                      style: TextStyle(
                        color: isActive ? Colors.white : (isCompleted ? Colors.white70 : Colors.white30),
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_mode == AddHostelMode.csv) {
      return _buildCSVUploadView();
    } else {
      return _buildManualStepper();
    }
  }

  Widget _buildSelectionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        _buildSelectionCard(
          title: 'Manual Setup',
          description: 'Configure hostel, floors, and rooms.',
          icon: Icons.list_alt_rounded,
          color: const Color(0xFF1A2744),
          onTap: () => setState(() => _mode = AddHostelMode.manual),
        ),
        const SizedBox(height: 16),
        _buildSelectionCard(
          title: 'CSV Import',
          description: 'Bulk import from a CSV file.',
          icon: Icons.upload_file_rounded,
          color: const Color(0xFFD4AF37),
          onTap: () => setState(() => _mode = AddHostelMode.csv),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSelectionCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: color.withValues(alpha: 0.1), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildManualStepper() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
            : SingleChildScrollView(
                child: _buildCurrentStepContent(),
              ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (_currentStep > 0)
                OutlinedButton(
                  onPressed: _handleStepCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1A2744)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  child: const Text('Back', style: TextStyle(color: Color(0xFF1A2744))),
                )
              else if (!_isEditMode)
                TextButton(
                  onPressed: () => setState(() {
                    _mode = AddHostelMode.initial;
                    rooms.clear();
                    floors.clear();
                    wings.clear();
                  }),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFFD4AF37))),
                ),
              const Spacer(),
              if (_currentStep < 4)
                ElevatedButton(
                  onPressed: _handleStepContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF1A2744),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Next', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              if (_currentStep == 4)
                ElevatedButton(
                  onPressed: _submitHostel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A2744),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(_isEditMode ? 'Update' : 'Create'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStepBasic();
      case 1:
        return _buildStepFloors();
      case 2:
        return _buildStepWings();
      case 3:
        return _buildStepRooms();
      case 4:
        return _buildStepReview();
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepBasic() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Basic Hostel Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
          const SizedBox(height: 20),
          _buildCampusDropdown(),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: hostelController.text.isEmpty ? null : hostelController.text,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Hostel Name',
              prefixIcon: Icon(Icons.home, size: 18),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: _hostelsList.map((h) => DropdownMenuItem(value: h['name'], child: Text(h['name']!, style: const TextStyle(fontSize: 14)))).toList(),
            onChanged: _isEditMode ? null : (v) {
              setState(() {
                hostelController.text = v!;
                final match = _hostelsList.firstWhere((element) => element['name'] == v);
                codeController.text = match['code']!;
              });
              _fetchRoomsFromMaster(codeController.text);
            },
          ),
          const SizedBox(height: 16),
          _buildDropdownField(),
          const SizedBox(height: 16),
          TextField(
            controller: codeController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Building Code',
              prefixIcon: Icon(Icons.code, size: 18),
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepFloors() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Floors Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
          const SizedBox(height: 8),
          const Text('These floors are automatically populated from the Room Master data source.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 20),
          if (floors.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No floors loaded. Please select a valid hostel in Step 1.', style: TextStyle(color: Colors.red)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: floors.map((f) => Chip(
                backgroundColor: Colors.white,
                label: Text('${f['name']} (${f['code']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
                side: const BorderSide(color: Color(0xFF1A2744)),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepWings() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wings / Blocks Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
          const SizedBox(height: 8),
          const Text('These wings/blocks are automatically populated from the Room Master data source.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 20),
          if (wings.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('No wings loaded. Please select a valid hostel in Step 1.', style: TextStyle(color: Colors.red)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: wings.map((w) => Chip(
                backgroundColor: Colors.white,
                label: Text('${w['name']} (${w['code']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                side: const BorderSide(color: Color(0xFFD4AF37)),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepRooms() {
    final filteredRooms = (selectedFloor == 'All' || selectedFloor.isEmpty)
        ? rooms
        : rooms.where((r) => r['floor'] == selectedFloor).toList();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rooms Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
          const SizedBox(height: 20),
          
          // Form to manually add a room if needed
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Add Manual Room Override', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedRoomNo,
                          decoration: const InputDecoration(labelText: 'Room No', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          items: _getAvailableRoomsForSelectedFloor().map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) => setState(() => selectedRoomNo = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedFloor.isEmpty ? 'All' : selectedFloor,
                          decoration: const InputDecoration(labelText: 'Floor', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All', style: TextStyle(fontSize: 12))),
                            ...floors.map((f) => DropdownMenuItem(value: f['name'], child: Text(f['name']!, style: const TextStyle(fontSize: 12)))),
                          ],
                          onChanged: (v) => setState(() {
                            selectedFloor = v!;
                            selectedRoomNo = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: selectedWing.isEmpty && wings.isNotEmpty ? wings.first['name'] : (selectedWing.isNotEmpty ? selectedWing : null),
                          decoration: const InputDecoration(labelText: 'Wing', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          items: wings.map((w) => DropdownMenuItem(value: w['name'], child: Text(w['name']!, style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) => setState(() => selectedWing = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _roomType,
                          decoration: const InputDecoration(labelText: 'Facility / Room Type', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                          items: _externalRoomTypes.map((t) => DropdownMenuItem(value: t['name'].toString(), child: Text(t['name'].toString(), style: const TextStyle(fontSize: 12)))).toList(),
                          onChanged: (v) => setState(() => _roomType = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _addRoom,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Room'),
                        style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF1A2744),
                           foregroundColor: Colors.white,
                           padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Rooms List (Total: ${filteredRooms.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A2744))),
          const SizedBox(height: 8),
          _buildRoomsList(),
        ],
      ),
    );
  }

  Widget _buildStepReview() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Review Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
          const SizedBox(height: 20),
          _buildReviewSection('Hostel Details', [
            'Campus: $selectedCampus',
            'Name: ${hostelController.text} (${typeController.text})',
            'Building Code: ${codeController.text}',
          ]),
          _buildReviewSection('Structure', [
            'Floors: ${floors.length} floors detected',
            'Wings: ${wings.length} blocks detected',
          ]),
          _buildReviewSection('Rooms Summary', [
            'Total Rooms to Create: ${rooms.length}',
          ]),
        ],
      ),
    );
  }

  Widget _buildCSVUploadView() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Hostel Basic Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 12),
                          _buildCampusDropdown(),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: hostelController.text.isEmpty ? null : hostelController.text,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Hostel Name',
                              prefixIcon: Icon(Icons.home, size: 18),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: _hostelsList.map((h) => DropdownMenuItem(value: h['name'], child: Text(h['name']!, style: const TextStyle(fontSize: 14)))).toList(),
                            onChanged: _isEditMode ? null : (v) {
                              setState(() {
                                hostelController.text = v!;
                                final match = _hostelsList.firstWhere((element) => element['name'] == v);
                                codeController.text = match['code']!;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildDropdownField(),
                          const SizedBox(height: 12),
                          TextField(
                            controller: codeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Building Code',
                              prefixIcon: Icon(Icons.code, size: 18),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.upload_file_rounded, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text('Upload Rooms CSV', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'Format: Floor, Wing, RoomNo, Capacity, Facility',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickCSVAndProcess,
                              icon: const Icon(Icons.file_upload_outlined, size: 18),
                              label: const Text('Choose CSV File'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFD4AF37),
                                foregroundColor: const Color(0xFF1A2744),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                const csvContent = "Floor,Wing,RoomNo,Capacity,Facility\nF01,W01,101,4,4 IN 1 AC\nF01,W01,102,6,6 IN 1 NON AC\nF02,W02,201,2,2 IN 1 AC";
                                downloadCSV(csvContent, "hostel_import_template.csv");
                              },
                              icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFFD4AF37)),
                              label: const Text('Sample'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD4AF37),
                                side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                textStyle: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        if (rooms.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text('${rooms.length} rooms ready!', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _mode = AddHostelMode.initial;
                  rooms.clear();
                  floors.clear();
                  wings.clear();
                }),
                child: const Text('Back', style: TextStyle(color: Color(0xFFD4AF37))),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: (rooms.isEmpty || hostelController.text.trim().isEmpty) ? null : _submitHostel,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A2744),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                child: _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create Hostel'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickCSVAndProcess() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      
      List<int>? fileBytes = file.bytes;
      if (fileBytes == null && !kIsWeb && file.path != null) {
        final ioFile = io.File(file.path!);
        fileBytes = await ioFile.readAsBytes();
      }

      if (fileBytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to read CSV file content'), backgroundColor: Colors.red),
        );
        return;
      }

      final csvString = utf8.decode(fileBytes);
      final List<List<dynamic>> csvData = const CsvToListConverter().convert(csvString);

      if (csvData.length < 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CSV file is empty or invalid'), backgroundColor: Colors.red),
        );
        return;
      }

      _processImportedCSV(csvData);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _processImportedCSV(List<List<dynamic>> csvData) {
    final header = csvData[0].map((h) => h.toString().toLowerCase().trim()).toList();
    
    int? floorIdx, wingIdx, roomNoIdx, capacityIdx, facilityIdx;
    
    for (int i = 0; i < header.length; i++) {
      final col = header[i];
      if (col.contains('floor')) { floorIdx = i; }
      else if (col.contains('wing')) { wingIdx = i; }
      else if (col.contains('room')) { roomNoIdx = i; }
      else if (col.contains('capacity')) { capacityIdx = i; }
      else if (col.contains('facility')) { facilityIdx = i; }
    }

    floorIdx ??= 0;
    wingIdx ??= 1;
    roomNoIdx ??= 2;
    capacityIdx ??= 3;
    facilityIdx ??= 4;

    final List<Map<String, dynamic>> importedRooms = [];
    final Set<String> importedFloors = {};
    final Set<String> importedWings = {};

    for (int i = 1; i < csvData.length; i++) {
      final row = csvData[i];
      if (row.isEmpty || row[0].toString().isEmpty) continue;

      try {
        final floorName = row.length > floorIdx ? row[floorIdx]?.toString().trim() ?? '' : '';
        final wingName = row.length > wingIdx ? row[wingIdx]?.toString().trim() ?? '' : '';
        final roomNo = row.length > roomNoIdx ? row[roomNoIdx]?.toString().trim() ?? '' : '';
        final facility = row.length > facilityIdx ? row[facilityIdx]?.toString().trim() ?? 'AC' : 'AC';
        final capacity = row.length > capacityIdx 
            ? (int.tryParse(row[capacityIdx]?.toString() ?? '') ?? _extractCapacity(facility)) 
            : _extractCapacity(facility);

        if (floorName.isEmpty || wingName.isEmpty || roomNo.isEmpty) continue;

        importedFloors.add(floorName);
        importedWings.add(wingName);

        final bCode = codeController.text.isEmpty ? 'T32' : codeController.text;
        final roomCode = "$bCode-$floorName-$wingName-R$roomNo";

        importedRooms.add({
          'room_number': roomNo,
          'room_code': roomCode,
          'capacity': capacity,
          'floor': floorName,
          'wing': wingName,
          'amount': 0.0,
          'type': facility,
        });
      } catch (e) {
        debugPrint('Error parsing row $i: $e');
      }
    }

    setState(() {
      rooms = importedRooms;
      floors = importedFloors.map((f) => {'name': f, 'code': f}).toList();
      wings = importedWings.map((w) => {'name': w, 'code': w}).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported ${rooms.length} rooms'), backgroundColor: Colors.green),
    );
  }

  Widget _buildCampusDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: selectedCampus,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Campus',
        prefixIcon: Icon(Icons.location_on, size: 18),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: ['Thandalam Campus', 'City Campus'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 14)))).toList(),
      onChanged: (v) => setState(() => selectedCampus = v!),
    );
  }

  Widget _buildDropdownField() {
    return DropdownButtonFormField<String>(
      initialValue: typeController.text,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Type',
        prefixIcon: Icon(Icons.people_outline, size: 18),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: ['Girls', 'Boys'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 14)))).toList(),
      onChanged: (v) => setState(() => typeController.text = v!),
    );
  }

  Widget _buildRoomsList() {
    final filteredRooms = (selectedFloor == 'All' || selectedFloor.isEmpty)
        ? rooms
        : rooms.where((r) => r['floor'] == selectedFloor).toList();

    if (filteredRooms.isEmpty) return const SizedBox(height: 50, child: Center(child: Text('No rooms configuration loaded.', style: TextStyle(color: Colors.grey))));
    return Container(
      height: 250,
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12), color: Colors.white),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filteredRooms.length,
        itemBuilder: (context, index) {
          final room = filteredRooms[index];
          return ListTile(
            dense: true,
            title: Text('Room: ${room['room_number']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
            subtitle: Text('Floor: ${room['floor']} | Wing: ${room['wing']} | Type: ${room['type']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
            trailing: IconButton(
              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
              onPressed: () => setState(() {
                rooms.removeWhere((r) => r['room_number'] == room['room_number'] && r['floor'] == room['floor']);
              }),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewSection(String title, List<String> details) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
          const SizedBox(height: 6),
          ...details.map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(d, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          )),
          const Divider(),
        ],
      ),
    );
  }

  List<String> _getAvailableRoomsForSelectedFloor() {
    if (selectedFloor == 'All') {
      return _masterRooms.map((r) => r['room_number'].toString()).toSet().toList()..sort();
    } else {
      return _masterRooms
          .where((r) => r['floor'] == selectedFloor)
          .map((r) => r['room_number'].toString())
          .toSet()
          .toList()
        ..sort();
    }
  }

  void _addRoom() {
    if (selectedRoomNo == null || selectedRoomNo!.isEmpty) return;
    
    final masterMatch = _masterRooms.firstWhere(
      (r) => r['room_number'] == selectedRoomNo,
      orElse: () => <String, dynamic>{},
    );
    
    final targetFloor = masterMatch.isNotEmpty ? masterMatch['floor'] : (selectedFloor == 'All' ? (floors.isNotEmpty ? floors.first['name']! : '') : selectedFloor);
    final targetWing = masterMatch.isNotEmpty ? masterMatch['wing'] : selectedWing;
    final targetType = masterMatch.isNotEmpty ? masterMatch['type'] : _roomType;
    
    final fCode = floors.isNotEmpty ? (floors.firstWhere((f) => f['name'] == targetFloor, orElse: () => floors.first)['code'] ?? targetFloor) : targetFloor;
    final wCode = wings.isNotEmpty ? (wings.firstWhere((w) => w['name'] == targetWing, orElse: () => wings.first)['code'] ?? targetWing) : targetWing;

    final code = "${codeController.text}-$fCode-$wCode-R$selectedRoomNo";

    if (rooms.any((r) => r['room_number'] == selectedRoomNo && r['floor'] == targetFloor)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room already added'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      rooms.add({
        'room_number': selectedRoomNo,
        'room_code': code,
        'capacity': masterMatch.isNotEmpty
            ? (int.tryParse(masterMatch['capacity']?.toString() ?? '') ?? _extractCapacity(targetType))
            : _extractCapacity(targetType),
        'floor': targetFloor,
        'wing': targetWing,
        'amount': 0.0,
        'type': targetType,
      });
      selectedRoomNo = null;
    });
  }

  Future<void> _submitHostel() async {
    if (hostelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a valid hostel name'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final payload = {
        'id': widget.hostel?.id,
        'campus': selectedCampus,
        'hostel_name': hostelController.text,
        'type': typeController.text,
        'building_code': codeController.text,
        'wings': wings.map((w) => w['name']).toList(),
        'rooms': rooms.map((r) => {
          'room_number': r['room_number'],
          'room_code': r['room_code'],
          'capacity': r['capacity'],
          'floor': r['floor'], 
          'floor_code': floors.firstWhere((f) => f['name'] == r['floor'], orElse: () => {'code': r['floor']})['code'],
          'wing': r['wing'], 
          'wing_code': wings.firstWhere((w) => w['name'] == r['wing'], orElse: () => {'code': r['wing']})['code'],
          'amount': r['amount'],
          'facility': r['type'],
          'room_type': '${r['capacity']}-sharing',
        }).toList(),
      };

      final response = _isEditMode 
        ? await ApiService.updateHostelFull(payload)
        : await ApiService.createHostelFull(payload);

      if (response['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_isEditMode ? 'Updated!' : 'Created!'), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(response['message']);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _extractCapacity(String name) {
    if (name.contains('8 IN 1')) return 8;
    if (name.contains('6 IN 1')) return 6;
    if (name.contains('4 IN 1')) return 4;
    if (name.contains('2 IN 1')) return 2;
    return 0; // Default
  }

  @override
  void dispose() {
    hostelController.dispose();
    typeController.dispose();
    codeController.dispose();
    wingController.dispose();
    wingCodeController.dispose();
    floorController.dispose();
    floorCodeController.dispose();
    roomController.dispose();
    super.dispose();
  }
}
