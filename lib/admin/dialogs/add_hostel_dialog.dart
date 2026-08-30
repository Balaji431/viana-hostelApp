import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'dart:io' as io;

import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/wallpaper_provider.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';

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
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final bool isDark = wallpaper?.isDarkTheme ?? false;

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
            color: isDark ? const Color(0xFF131D2E) : const Color(0xFFF5F2ED),
            borderRadius: BorderRadius.circular(24),
            border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
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
                          Text('Add Hostel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
                          IconButton(
                            onPressed: () => Navigator.pop(context), 
                            icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black87),
                          ),
                        ],
                      ),
                      Divider(color: isDark ? Colors.white12 : Colors.grey.shade300),
                      _buildSelectionView(isDark),
                    ],
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == AddHostelMode.manual) _buildStepNavigator(isDark),
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
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(context), 
                                  icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black87),
                                ),
                              ],
                            ),
                            Divider(height: 20, color: isDark ? Colors.white12 : Colors.grey.shade300),
                            Expanded(
                              child: _buildContent(isDark),
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

  Widget _buildStepNavigator(bool isDark) {
    final stepTitles = ['Basic', 'Floors', 'Wings', 'Rooms', 'Review'];
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1520) : const Color(0xFF141E2E),
        borderRadius: const BorderRadius.only(
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
                            : (isActive ? (isDark ? const Color(0xFFD4AF37) : Colors.white) : Colors.transparent),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCompleted 
                              ? const Color(0xFFD4AF37) 
                              : (isActive ? (isDark ? const Color(0xFFD4AF37) : Colors.white) : Colors.white24),
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
                        color: isActive ? (isDark ? const Color(0xFFD4AF37) : Colors.white) : (isCompleted ? Colors.white70 : Colors.white30),
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

  Widget _buildContent(bool isDark) {
    if (_mode == AddHostelMode.csv) {
      return _buildCSVUploadView(isDark);
    } else {
      return _buildManualStepper(isDark);
    }
  }

  Widget _buildSelectionView(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        _buildSelectionCard(
          title: 'Manual Setup',
          description: 'Configure hostel, floors, and rooms manually step-by-step.',
          icon: Icons.list_alt_rounded,
          color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
          isDark: isDark,
          onTap: () => setState(() => _mode = AddHostelMode.manual),
        ),
        const SizedBox(height: 16),
        _buildSelectionCard(
          title: 'Bulk Excel / CSV Import',
          description: 'Bulk import rooms using sample Excel with Room Type dropdowns (4 columns: Floor, Wing, Room No, Room Type).',
          icon: Icons.upload_file_rounded,
          color: const Color(0xFFD4AF37),
          isDark: isDark,
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
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03), blurRadius: 10, offset: const Offset(0, 4)),
          ],
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : color.withValues(alpha: 0.1), width: 1),
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: isDark ? Colors.white38 : color.withValues(alpha: 0.5), size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildManualStepper(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _isLoading 
            ? Center(child: CircularProgressIndicator(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)))
            : SingleChildScrollView(
                child: _buildCurrentStepContent(isDark),
              ),
        ),
        Divider(color: isDark ? Colors.white12 : Colors.grey.shade300),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (_currentStep > 0)
                OutlinedButton(
                  onPressed: _handleStepCancel,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: isDark ? Colors.white38 : const Color(0xFF1A2744)),
                    foregroundColor: isDark ? Colors.white : const Color(0xFF1A2744),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  child: const Text('Back'),
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
                    backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                    foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
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

  Widget _buildCurrentStepContent(bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStepBasic(isDark);
      case 1:
        return _buildStepFloors(isDark);
      case 2:
        return _buildStepWings(isDark);
      case 3:
        return _buildStepRooms(isDark);
      case 4:
        return _buildStepReview(isDark);
      default:
        return const SizedBox();
    }
  }

  Widget _buildStepBasic(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Basic Hostel Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
          const SizedBox(height: 20),
          _buildCampusDropdown(isDark),
          const SizedBox(height: 16),
          TextField(
            controller: hostelController,
            enabled: !_isEditMode,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Hostel Name',
              labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
              hintText: 'Enter new hostel name (e.g. Ganga Hostel)',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
              prefixIcon: Icon(Icons.home_work_rounded, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onChanged: (val) {
              if (!_isEditMode && codeController.text.isEmpty && val.isNotEmpty) {
                final clean = val.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                final code = clean.length >= 3 ? clean.substring(0, 3) : clean;
                setState(() => codeController.text = 'T-$code');
              }
            },
          ),
          const SizedBox(height: 16),
          _buildDropdownField(isDark),
          const SizedBox(height: 16),
          TextField(
            controller: codeController,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              labelText: 'Building Code',
              labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
              hintText: 'e.g. T-40 or G-01',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
              prefixIcon: Icon(Icons.code, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepFloors(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Floors Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
          const SizedBox(height: 8),
          Text('Add all floors for this hostel (e.g. Ground Floor, First Floor, Second Floor).', style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: floorController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Floor Name',
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                    hintText: 'e.g. Ground Floor, First Floor',
                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final f = floorController.text.trim();
                  if (f.isNotEmpty && !floors.any((x) => x['name']?.toLowerCase() == f.toLowerCase())) {
                    setState(() {
                      floors.add({'name': f, 'code': _getFloorCode(f)});
                      floorController.clear();
                      if (selectedFloor.isEmpty || selectedFloor == 'All') selectedFloor = f;
                    });
                  }
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Floor'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                  foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (floors.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('No floors added yet. Please type a floor name above and click "Add Floor".', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: floors.map((f) => Chip(
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                label: Text('${f['name']} (${f['code']})', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
                side: BorderSide(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
                deleteIcon: Icon(Icons.close, size: 16, color: isDark ? Colors.white70 : Colors.black87),
                onDeleted: () => setState(() => floors.remove(f)),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepWings(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Wings / Blocks Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
          const SizedBox(height: 8),
          Text('Add wings or blocks for this hostel (e.g. Block A, Wing 1, General).', style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: wingController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'Wing / Block Name',
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                    hintText: 'e.g. Block A, Wing 1, General',
                    hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  final w = wingController.text.trim();
                  if (w.isNotEmpty && !wings.any((x) => x['name']?.toLowerCase() == w.toLowerCase())) {
                    setState(() {
                      wings.add({'name': w, 'code': w});
                      wingController.clear();
                      if (selectedWing.isEmpty) selectedWing = w;
                    });
                  }
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Wing'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: const Color(0xFF1A2744),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (wings.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text('No wings added yet. Please type a wing/block name above and click "Add Wing".', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: wings.map((w) => Chip(
                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                label: Text('${w['name']} (${w['code']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                side: const BorderSide(color: Color(0xFFD4AF37)),
                deleteIcon: Icon(Icons.close, size: 16, color: isDark ? Colors.white70 : Colors.black87),
                onDeleted: () => setState(() => wings.remove(w)),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepRooms(bool isDark) {
    final filteredRooms = (selectedFloor == 'All' || selectedFloor.isEmpty)
        ? rooms
        : rooms.where((r) => r['floor'] == selectedFloor).toList();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rooms Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
          const SizedBox(height: 20),
          
          // Form to manually add a room
          Card(
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add Room to Hostel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: roomController,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Room Number',
                            labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                            hintText: 'e.g. 101, 102, R01',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedFloor.isEmpty ? (floors.isNotEmpty ? floors.first['name'] : 'All') : selectedFloor,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Floor',
                            labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          items: [
                            DropdownMenuItem(value: 'All', child: Text('All Floors', style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87))),
                            ...floors.map((f) => DropdownMenuItem(value: f['name'], child: Text(f['name']!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)))),
                          ],
                          onChanged: (v) => setState(() {
                            selectedFloor = v!;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedWing.isEmpty && wings.isNotEmpty ? wings.first['name'] : (selectedWing.isNotEmpty ? selectedWing : null),
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Wing / Block',
                            labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          items: wings.map((w) => DropdownMenuItem(value: w['name'], child: Text(w['name']!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)))).toList(),
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
                          initialValue: _roomType,
                          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Facility / Room Type',
                            labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          items: _externalRoomTypes.isNotEmpty 
                              ? _externalRoomTypes.map((t) => DropdownMenuItem(value: t['name'].toString(), child: Text(t['name'].toString(), style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)))).toList()
                              : ['4 IN 1 AC', '6 IN 1 NON AC', '2 IN 1 AC', 'Standard AC', 'Standard Non AC'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87)))).toList(),
                          onChanged: (v) => setState(() => _roomType = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _addRoom,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Room'),
                        style: ElevatedButton.styleFrom(
                           backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                           foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
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
          Text('Rooms List (Total: ${filteredRooms.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1A2744))),
          const SizedBox(height: 8),
          _buildRoomsList(isDark),
        ],
      ),
    );
  }

  Widget _buildStepReview(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review Configuration', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
          const SizedBox(height: 20),
          _buildReviewSection('Hostel Details', [
            'Campus: $selectedCampus',
            'Name: ${hostelController.text} (${typeController.text})',
            'Building Code: ${codeController.text}',
          ], isDark),
          _buildReviewSection('Structure', [
            'Floors: ${floors.length} floors detected',
            'Wings: ${wings.length} blocks detected',
          ], isDark),
          _buildReviewSection('Rooms Summary', [
            'Total Rooms to Create: ${rooms.length}',
          ], isDark),
        ],
      ),
    );
  }

  Widget _buildCSVUploadView(bool isDark) {
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
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hostel Basic Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87)),
                          const SizedBox(height: 12),
                          _buildCampusDropdown(isDark),
                          const SizedBox(height: 12),
                          TextField(
                            controller: hostelController,
                            enabled: !_isEditMode,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              labelText: 'Hostel Name',
                              labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                              hintText: 'e.g. Ganga Hostel',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                              prefixIcon: Icon(Icons.home_work_rounded, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                            onChanged: (val) {
                              if (!_isEditMode && codeController.text.isEmpty && val.isNotEmpty) {
                                final clean = val.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
                                final code = clean.length >= 3 ? clean.substring(0, 3) : clean;
                                setState(() => codeController.text = 'T-$code');
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildDropdownField(isDark),
                          const SizedBox(height: 12),
                          TextField(
                            controller: codeController,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              labelText: 'Building Code',
                              labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
                              hintText: 'e.g. T-40 or G-01',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                              prefixIcon: Icon(Icons.code, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700),
                              filled: true,
                              fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Tooltip(
                            message: 'How to import rooms? Click for steps',
                            child: InkWell(
                              onTap: _showImportInstructionsDialog,
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37).withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.help_outline_rounded, color: Color(0xFFD4AF37), size: 20),
                              ),
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(Icons.description_rounded, size: 48, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
                            const SizedBox(height: 10),
                            Text(
                              'Bulk Import Rooms (Excel / CSV)',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0F1520) : const Color(0xFFF5F2ED),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? const Color(0xFFD4AF37).withOpacity(0.4) : const Color(0xFFD4AF37).withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'Required 4 Columns in Document:',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Floor  |  Wing  |  Room No  |  Room Type',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF2A4A8C)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _pickFileAndProcess,
                                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                                    label: const Text('Choose CSV / Excel'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDark ? const Color(0xFF0F1520) : const Color(0xFF1A2744),
                                      foregroundColor: Colors.white,
                                      side: isDark ? const BorderSide(color: Colors.white24) : null,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _openSampleGoogleSheet,
                                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                                    label: const Text('Sample Template'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD4AF37),
                                      foregroundColor: const Color(0xFF1A2744),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (rooms.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${rooms.length} rooms ready for onboarding!',
                                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
        Divider(color: isDark ? Colors.white12 : Colors.grey.shade300),
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
                  backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                  foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
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

  void _showImportInstructionsDialog() {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.read<WallpaperProvider>();
    } catch (_) {}
    final bool isDark = wallpaper?.isDarkTheme ?? false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.14)) : BorderSide.none,
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.help_outline_rounded, color: Color(0xFFD4AF37), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bulk Import Instructions',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: isDark ? Colors.white70 : Colors.grey),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: isDark ? Colors.white12 : Colors.grey.shade300),
              const SizedBox(height: 12),
              _buildStepItem(
                stepNum: '1',
                title: 'Open Sample Template',
                desc: 'Click "Sample Template" to open the Google Sheet in your browser.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildStepItem(
                stepNum: '2',
                title: 'Fill Hostel Rooms Data',
                desc: 'Fill in the Floor, Wing, Room No, and select Room Type from the dropdown.',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildStepItem(
                stepNum: '3',
                title: 'Download File',
                desc: 'In Google Sheets, go to File → Download → Comma Separated Values (.csv) or Microsoft Excel (.xlsx).',
                isDark: isDark,
              ),
              const SizedBox(height: 12),
              _buildStepItem(
                stepNum: '4',
                title: 'Upload and Finish',
                desc: 'Click "Choose CSV / Excel" in the app and upload your file. The rooms will be automatically parsed and populated for hostel creation.',
                isDark: isDark,
              ),
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                    foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepItem({required String stepNum, required String title, required String desc, bool isDark = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
            borderRadius: BorderRadius.circular(13),
          ),
          alignment: Alignment.center,
          child: Text(
            stepNum,
            style: TextStyle(color: isDark ? const Color(0xFF1A2744) : Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white : const Color(0xFF1A2744)),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openSampleGoogleSheet() async {
    const url = 'https://docs.google.com/spreadsheets/d/1TJkFLYjxoMaJvVOdZ_a-4QYQY8ZW-fkR5BUmGufr--E/edit?usp=sharing';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error opening Google Sheet: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFileAndProcess() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final ext = file.extension?.toLowerCase() ?? '';
      
      List<int>? fileBytes = file.bytes;
      if (fileBytes == null && !kIsWeb && file.path != null) {
        final ioFile = io.File(file.path!);
        fileBytes = await ioFile.readAsBytes();
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to read file content'), backgroundColor: Colors.red),
        );
        return;
      }

      List<List<dynamic>> rows = [];

      if (ext == 'xlsx' || ext == 'xls') {
        try {
          final excel = excel_pkg.Excel.decodeBytes(fileBytes);
          excel_pkg.Sheet? targetSheet;
          if (excel.tables.containsKey('Hostel Rooms')) {
            targetSheet = excel.tables['Hostel Rooms'];
          } else {
            final activeKey = excel.tables.keys.firstWhere((k) => k != 'LookupData', orElse: () => excel.tables.keys.first);
            targetSheet = excel.tables[activeKey];
          }

          if (targetSheet != null) {
            for (var row in targetSheet.rows) {
              final rowValues = row.map((cell) => cell?.value?.toString().trim() ?? '').toList();
              if (rowValues.any((v) => v.isNotEmpty)) {
                rows.add(rowValues);
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing Excel: $e');
        }
      }

      // If rows are still empty (e.g. file is CSV or fallback)
      if (rows.isEmpty) {
        String csvString = utf8.decode(fileBytes, allowMalformed: true);
        if (csvString.startsWith('\uFEFF')) {
          csvString = csvString.substring(1);
        }
        csvString = csvString.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();

        if (csvString.isNotEmpty) {
          final firstLine = csvString.split('\n').first;
          final delimiter = firstLine.contains(';') && !firstLine.contains(',') ? ';' : (firstLine.contains('\t') ? '\t' : ',');
          try {
            rows = CsvToListConverter(
              eol: '\n',
              fieldDelimiter: delimiter,
              shouldParseNumbers: false,
            ).convert(csvString);
          } catch (e) {
            debugPrint('CsvToListConverter failed, falling back to line split: $e');
          }

          if (rows.isEmpty || rows.length < 2) {
            final lines = csvString.split('\n').where((l) => l.trim().isNotEmpty).toList();
            if (lines.length >= 2) {
              rows = lines.map((l) => l.split(delimiter).map((c) => c.trim().replaceAll('"', '')).toList()).toList();
            }
          }
        }
      }

      if (rows.length < 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document must have 1 header row (Floor, Wing, Room No, Room Type) and at least 1 room data row'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _processImportedRows(rows);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading file: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _processImportedRows(List<List<dynamic>> rowData) {
    if (rowData.isEmpty) return;

    final header = rowData[0].map((h) => h.toString().toLowerCase().trim().replaceAll('"', '')).toList();
    
    int? floorIdx, wingIdx, roomNoIdx, roomTypeIdx;
    
    for (int i = 0; i < header.length; i++) {
      final col = header[i];
      if (col.contains('floor')) {
        floorIdx = i;
      } else if (col.contains('wing') || col.contains('block')) {
        wingIdx = i;
      } else if (col.contains('room') && (col.contains('no') || col.contains('number') || col.contains('num') || !col.contains('type'))) {
        roomNoIdx = i;
      } else if (col.contains('type') || col.contains('facility') || col.contains('category')) {
        roomTypeIdx = i;
      }
    }

    // Default column order: Floor(0), Wing(1), Room No(2), Room Type(3)
    floorIdx ??= 0;
    wingIdx ??= 1;
    roomNoIdx ??= 2;
    roomTypeIdx ??= 3;

    final List<Map<String, dynamic>> importedRooms = [];
    final Set<String> importedFloors = {};
    final Set<String> importedWings = {};

    for (int i = 1; i < rowData.length; i++) {
      final row = rowData[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;

      try {
        final floorName = row.length > floorIdx ? row[floorIdx]?.toString().trim().replaceAll('"', '') ?? '' : '';
        final wingName = row.length > wingIdx ? row[wingIdx]?.toString().trim().replaceAll('"', '') ?? '' : '';
        final roomNo = row.length > roomNoIdx ? row[roomNoIdx]?.toString().trim().replaceAll('"', '') ?? '' : '';
        final roomType = row.length > roomTypeIdx ? row[roomTypeIdx]?.toString().trim().replaceAll('"', '') ?? '4 IN 1 AC' : '4 IN 1 AC';

        if (floorName.isEmpty || roomNo.isEmpty) continue;
        final validWing = wingName.isNotEmpty ? wingName : 'General';
        final validRoomType = roomType.isNotEmpty ? roomType : '4 IN 1 AC';
        final capacity = _extractCapacity(validRoomType);

        importedFloors.add(floorName);
        importedWings.add(validWing);

        final bCode = codeController.text.trim().isNotEmpty ? codeController.text.trim() : 'H';
        final fCode = _getFloorCode(floorName);
        final roomCode = "$bCode-$fCode-$validWing-R$roomNo";

        importedRooms.add({
          'room_number': roomNo,
          'room_code': roomCode,
          'capacity': capacity,
          'floor': floorName,
          'wing': validWing,
          'amount': 0.0,
          'type': validRoomType,
        });
      } catch (e) {
        debugPrint('Error parsing row $i: $e');
      }
    }

    if (importedRooms.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid room rows found in the document. Please verify the 4 columns: Floor, Wing, Room No, Room Type.'), backgroundColor: Colors.red),
      );
      return;
    }

    final floorOrder = {
      'ground': 0, 'first': 1, 'second': 2, 'third': 3, 'fourth': 4,
      'fifth': 5, 'sixth': 6, 'seventh': 7, 'eighth': 8, 'ninth': 9,
      'tenth': 10, 'eleventh': 11, 'twelfth': 12, 'thirteenth': 13,
      'fourteenth': 14, 'fifteenth': 15
    };

    final sortedFloors = importedFloors.map((f) => {'name': f, 'code': _getFloorCode(f)}).toList()
      ..sort((a, b) {
        final aOrder = floorOrder[a['name']!.toLowerCase()] ?? 99;
        final bOrder = floorOrder[b['name']!.toLowerCase()] ?? 99;
        return aOrder.compareTo(bOrder);
      });

    setState(() {
      rooms = importedRooms;
      floors = sortedFloors;
      wings = importedWings.map((w) => {'name': w, 'code': w}).toList();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully imported ${rooms.length} rooms (${floors.length} floors, ${wings.length} wings)!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildCampusDropdown(bool isDark) {
    return DropdownButtonFormField<String>(
      initialValue: selectedCampus,
      isExpanded: true,
      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: 'Campus',
        labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
        prefixIcon: Icon(Icons.location_on, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: ['Thandalam Campus', 'City Campus'].map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)))).toList(),
      onChanged: (v) => setState(() => selectedCampus = v!),
    );
  }

  Widget _buildDropdownField(bool isDark) {
    return DropdownButtonFormField<String>(
      initialValue: typeController.text,
      isExpanded: true,
      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: 'Type',
        labelStyle: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF1A2744)),
        prefixIcon: Icon(Icons.people_outline, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F1520) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: ['Girls', 'Boys'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87)))).toList(),
      onChanged: (v) => setState(() => typeController.text = v!),
    );
  }

  Widget _buildRoomsList(bool isDark) {
    final filteredRooms = (selectedFloor == 'All' || selectedFloor.isEmpty)
        ? rooms
        : rooms.where((r) => r['floor'] == selectedFloor).toList();

    if (filteredRooms.isEmpty) return SizedBox(height: 50, child: Center(child: Text('No rooms configuration loaded.', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey))));
    return Container(
      height: 250,
      decoration: BoxDecoration(
        border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200), 
        borderRadius: BorderRadius.circular(12), 
        color: isDark ? const Color(0xFF0F1520) : Colors.white,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filteredRooms.length,
        itemBuilder: (context, index) {
          final room = filteredRooms[index];
          return ListTile(
            dense: true,
            title: Text('Room: ${room['room_number']}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
            subtitle: Text('Floor: ${room['floor']} | Wing: ${room['wing']} | Type: ${room['type']}', style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
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

  Widget _buildReviewSection(String title, List<String> details, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744))),
          const SizedBox(height: 6),
          ...details.map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.0),
            child: Text(d, style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
          )),
          Divider(color: isDark ? Colors.white12 : Colors.grey.shade300),
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
    final roomNo = roomController.text.trim().isNotEmpty ? roomController.text.trim() : selectedRoomNo;
    if (roomNo == null || roomNo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a room number'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    final masterMatch = _masterRooms.firstWhere(
      (r) => r['room_number'] == roomNo,
      orElse: () => <String, dynamic>{},
    );
    
    final targetFloor = masterMatch.isNotEmpty ? masterMatch['floor'] : (selectedFloor == 'All' ? (floors.isNotEmpty ? floors.first['name']! : 'Ground') : selectedFloor);
    final targetWing = masterMatch.isNotEmpty ? masterMatch['wing'] : (selectedWing.isNotEmpty ? selectedWing : (wings.isNotEmpty ? wings.first['name']! : 'General'));
    final targetType = masterMatch.isNotEmpty ? masterMatch['type'] : _roomType;
    
    final fCode = floors.isNotEmpty ? (floors.firstWhere((f) => f['name'] == targetFloor, orElse: () => {'code': targetFloor})['code'] ?? targetFloor) : targetFloor;
    final wCode = wings.isNotEmpty ? (wings.firstWhere((w) => w['name'] == targetWing, orElse: () => {'code': targetWing})['code'] ?? targetWing) : targetWing;
    final bCode = codeController.text.trim().isNotEmpty ? codeController.text.trim() : 'H';

    final code = "$bCode-$fCode-$wCode-R$roomNo";

    if (rooms.any((r) => r['room_number'] == roomNo && r['floor'] == targetFloor)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room already added on this floor'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      rooms.add({
        'room_number': roomNo,
        'room_code': code,
        'capacity': masterMatch.isNotEmpty
            ? (int.tryParse(masterMatch['capacity']?.toString() ?? '') ?? _extractCapacity(targetType))
            : _extractCapacity(targetType),
        'floor': targetFloor,
        'wing': targetWing,
        'amount': 0.0,
        'type': targetType,
      });
      roomController.clear();
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
          final hName = hostelController.text.trim();
          final rCount = rooms.length;
          Navigator.pop(context, true);

          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
                  const SizedBox(width: 8),
                  Text(_isEditMode ? 'Hostel Updated' : 'Hostel Created Successfully', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                _isEditMode 
                    ? '$hName has been updated.'
                    : 'Hostel "$hName" has been created with $rCount rooms!\n\nAll newly created rooms are now available in Room Master. You can now select and configure room types and fee structures directly in Room Master.',
                style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.4),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A2744),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
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
    final match = RegExp(r'(\d+)\s*(?:IN\s*1|in\s*1|sharing|bed|beds|seater|seaters|share|-sharing|-bed|-seater)', caseSensitive: false).firstMatch(name);
    if (match != null) {
      final cap = int.tryParse(match.group(1)!);
      if (cap != null && cap > 0) return cap;
    }
    if (name.contains('8 IN 1') || name.contains('8')) return 8;
    if (name.contains('6 IN 1') || name.contains('6')) return 6;
    if (name.contains('4 IN 1') || name.contains('4')) return 4;
    if (name.contains('3 IN 1') || name.contains('3')) return 3;
    if (name.contains('2 IN 1') || name.contains('2')) return 2;
    if (name.contains('1 IN 1') || name.toLowerCase().contains('single')) return 1;
    if (name.toLowerCase().contains('double')) return 2;
    if (name.toLowerCase().contains('triple')) return 3;
    return 4; // Default fallback
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
