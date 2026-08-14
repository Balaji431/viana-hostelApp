import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:data_table_2/data_table_2.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../dialogs/csv_helper_stub.dart'
    if (dart.library.html) '../dialogs/csv_helper_web.dart'
    if (dart.library.io) '../dialogs/csv_helper_mobile.dart';

class RoomMasterScreen extends StatefulWidget {
  const RoomMasterScreen({super.key});

  @override
  State<RoomMasterScreen> createState() => _RoomMasterScreenState();
}

class _RoomMasterScreenState extends State<RoomMasterScreen> {
  List<Map<String, dynamic>> _allRooms = [];
  List<Map<String, dynamic>> _filteredRooms = [];
  List<Map<String, dynamic>> _roomTypes = [];
  bool _isLoading = true;

  final TextEditingController _searchController = TextEditingController();
  String? _selectedBuildingFilter;
  String? _selectedFloorFilter;
  String? _selectedRoomTypeFilter;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    // Fetch external locations and local room types
    await Future.wait([_fetchExternalLocations(), _fetchRoomTypes()]);
    if (mounted) {
      setState(() => _isLoading = false);
      _applyFilters();
    }
  }

  // CORE TASK: Fix Data Mapping from External API and Local DB
  Future<void> _fetchExternalLocations() async {
    try {
      // 1. Fetch local room master records from database
      Map<String, Map<String, dynamic>> localRoomsByName = {};
      Map<String, Map<String, dynamic>> localRoomsByCode = {};
      List<Map<String, dynamic>> localRoomsList = [];
      try {
        final localResponse = await ApiService.getRequest('rooms/fetch_room_master.php?t=${DateTime.now().millisecondsSinceEpoch}');
        if (localResponse['status'] == 'success' || localResponse['success'] == true) {
          final List<dynamic> localData = localResponse['data'] ?? [];
          for (var item in localData) {
            if (item is Map) {
              final Map<String, dynamic> typedItem = Map<String, dynamic>.from(item);
              final String name = typedItem['location_name'] ?? '';
              final String code = typedItem['room_code'] ?? '';
              if (name.isNotEmpty) {
                localRoomsByName[name] = typedItem;
              }
              if (code.isNotEmpty) {
                localRoomsByCode[code] = typedItem;
              }
              localRoomsList.add(typedItem);
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching local rooms: $e');
      }

      // Initialize with local rooms by default, mapping to the expected UI model fields
      final List<Map<String, dynamic>> mappedLocalRooms = localRoomsList.map<Map<String, dynamic>>((localRoom) {
        final String roomType = localRoom['room_type'] ?? 'Not Assigned';
        final String locName = localRoom['location_name'] ?? '';
        final int occupancy = int.tryParse(localRoom['occupancy']?.toString() ?? '') ?? int.tryParse(localRoom['total_beds']?.toString() ?? '') ?? _extractCapacity(roomType);
        final int totalBeds = int.tryParse(localRoom['total_beds']?.toString() ?? '') ?? occupancy;
        final int occupiedBeds = int.tryParse(localRoom['occupied_beds']?.toString() ?? '') ?? 0;
        final int assignedPending = int.tryParse(localRoom['assigned_pending']?.toString() ?? '') ?? 0;
        final int availableBeds = int.tryParse(localRoom['available_beds']?.toString() ?? '') ?? (totalBeds - (occupiedBeds + assignedPending));

        final String roomCode = localRoom['room_code'] ?? localRoom['location_code'] ?? '';
        final List<dynamic> rawStudents = localRoom['students'] is List ? localRoom['students'] : [];
        final List<String> studentsList = rawStudents.map((s) => s.toString()).toList();

        return {
          'id': localRoom['id'],
          'location_name': _cleanHostelName(locName, roomCode),
          'building_code': _normalizeBuildingCode(localRoom['building_code'] ?? '', locName),
          'floor_no': localRoom['floor_no'] ?? '',
          'block_no': localRoom['block_no'] ?? '',
          'room_no': localRoom['room_no'] ?? '',
          'room_type': roomType,
          'occupancy': occupancy,
          'total_beds': totalBeds,
          'occupied_beds': occupiedBeds,
          'assigned_pending': assignedPending,
          'available_beds': availableBeds < 0 ? 0 : availableBeds,
          'gender': localRoom['gender'] ?? 'Male',
          'active': localRoom['active'] ?? 1,
          'amount': localRoom['amount'] ?? 0.00,
          'location_code': roomCode,
          'students': studentsList,
        };
      }).toList();

      _allRooms = mappedLocalRooms;
      _allRooms.sort((a, b) {
        final int idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        final int idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return idA.compareTo(idB);
      });
    } catch (e) {
      debugPrint('Error mapping room data: $e');
    }
  }

  String _normalizeFloor(String code) {
    switch (code.toUpperCase()) {
      case 'F00': return 'Ground';
      case 'F01': return 'First';
      case 'F02': return 'Second';
      case 'F03': return 'Third';
      case 'F04': return 'Fourth';
      case 'F05': return 'Fifth';
      case 'F06': return 'Sixth';
      case 'F07': return 'Seventh';
      case 'F08': return 'Eighth';
      case 'F09': return 'Ninth';
      case 'F10': return 'Tenth';
      case 'F11': return 'Eleventh';
      case 'F12': return 'Twelfth';
      case 'F13': return 'Thirteenth';
      case 'F14': return 'Fourteenth';
      case 'F15': return 'Fifteenth';
      default: return code;
    }
  }

  int _extractCapacity(String name) {
    final String upper = name.toUpperCase();
    final RegExp match = RegExp(r'(\d+)\s*IN\s*1');
    final RegExpMatch? res = match.firstMatch(upper);
    if (res != null) {
      return int.parse(res.group(1)!);
    }
    if (upper.contains('FOUR') || upper.contains('4')) {
      return 4;
    }
    if (upper.contains('TRIPLE') || upper.contains('3')) {
      return 3;
    }
    if (upper.contains('DOUBLE')) {
      return 2;
    }
    if (upper.contains('SINGLE')) {
      return 1;
    }
    return 0;
  }

  Future<void> _fetchRoomTypes() async {
    try {
      final res = await ApiService.getRequest('rooms/fetch_external_room_types.php');
      if (res['success'] == true || res['status'] == 'success') {
        final List<dynamic> list = res['data'] ?? [];
        setState(() {
          _roomTypes = list.map((item) => item is Map ? Map<String, dynamic>.from(item) : {'id': item.toString(), 'name': item.toString()}).toList();
        });
      }
    } catch (e) {
      setState(() {
        _roomTypes = [{'id': '1', 'name': '4 IN 1 AC'}, {'id': '2', 'name': '6 IN 1 AC'}];
      });
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredRooms = _allRooms.where((room) {
        final search = _searchController.text.toLowerCase();
        return (search.isEmpty || 
                room['room_no'].toString().toLowerCase().contains(search) || 
                room['location_code'].toString().toLowerCase().contains(search) || 
                room['location_name'].toString().toLowerCase().contains(search)) &&
               (_selectedBuildingFilter == null || room['building_code'] == _selectedBuildingFilter) &&
               (_selectedFloorFilter == null || room['floor_no'] == _selectedFloorFilter);
      }).toList();

      _filteredRooms.sort((a, b) {
        final int idA = int.tryParse(a['id']?.toString() ?? '0') ?? 0;
        final int idB = int.tryParse(b['id']?.toString() ?? '0') ?? 0;
        return idA.compareTo(idB);
      });
    });
  }

  // IMPORT TASK: Store external details to local database and download the Excel file
  Future<void> _importToMaster() async {
    final String downloadUrl = '${ApiService.baseUrl}rooms/import_and_export.php';
    
    // 1. Trigger the download synchronously inside the click gesture handler context.
    // This bypasses Chrome's automatic download blocking policy, showing it directly
    // in the downloads history (Ctrl+J).
    triggerImportAndExport(downloadUrl);
    
    setState(() => _isLoading = true);
    try {
      // 2. Wait 4 seconds for the server to download external locations, import them, and stream the file
      await Future.delayed(const Duration(seconds: 4));
      
      // 3. Fetch the fresh database records and rebuild the UI table
      await _fetchInitialData();
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Import initiated. File added to downloads history successfully.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      debugPrint('Import error: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Import error: $e')
      ));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _exportToCSV() {
    final List<List<dynamic>> rows = [
      ['Hostel Name', 'Room Code', 'Room Type', 'Capacity']
    ];
    
    for (var room in _filteredRooms) {
      rows.add([
        _cleanHostelName(room['location_name'] ?? ''),
        room['location_code'] ?? '',
        room['room_type'] ?? 'Not Assigned',
        room['room_capacity'] ?? 0,
      ]);
    }
    
    final String csvContent = const ListToCsvConverter().convert(rows);
    downloadCSV(csvContent, 'room_master_export.csv');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth > 1100;
          return Row(
            children: [
              if (isWide) _buildSidebar(),
              Expanded(
                child: Column(
                  children: [
                    _buildAppBar(!isWide),
                    _buildFilterBar(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: _isLoading 
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A2744)))
                          : _buildDataTable(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppBar(bool showBack) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
      child: Row(
        children: [
          if (showBack) IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context, rootNavigator: true).pop()),
          const Text('Room Master Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A2744), fontFamily: 'Lato')),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _exportToCSV,
            icon: const Icon(Icons.file_download, size: 16, color: Colors.white),
            label: const Text('Export Excel', style: TextStyle(color: Colors.white, fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => _applyFilters(),
                decoration: InputDecoration(hintText: 'Search Location, Room, or Code...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              ),
            ),
            const SizedBox(width: 16),
            _buildDropdownFilter('Building', _selectedBuildingFilter, _allRooms.map((e) => e['building_code'].toString()).toSet().toList(), (v) { setState(()=>_selectedBuildingFilter=v); _applyFilters(); }),
            const SizedBox(width: 16),
            _buildDropdownFilter('Floor', _selectedFloorFilter, _allRooms.map((e) => e['floor_no'].toString()).toSet().toList(), (v) { setState(()=>_selectedFloorFilter=v); _applyFilters(); }),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownFilter(String hint, String? val, List<String> items, Function(String?) fn) {
    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: val,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          items: [DropdownMenuItem(value: null, child: Text('All $hint')), ...items.where((e)=>e.isNotEmpty).map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))],
          onChanged: fn,
        ),
      ),
    );
  }

  String _normalizeBuildingCode(String buildingCode, String locationName) {
    final String code = buildingCode.trim();
    if (code == 'T30') return 'T30';
    if (code == 'T-30') return 'T-30';
    if (code == 'T32') return 'T32';
    if (code == 'T-32') return 'T-32';
    if (code == 'T14' || code == 'T-14') return 'T14';
    if (code == 'T12' || code == 'T-12') return 'T12';
    if (code == 'T19' || code == 'T-19') return 'T19';
    if (code == 'T10' || code == 'T-10') return 'T10';
    if (code == 'T22' || code == 'T-22') return 'T22';
    if (code == 'T09' || code == 'T-09') return 'T09';
    if (code == 'P05' || code == 'P-05') return 'P-05';
    if (code == 'P10' || code == 'P-10') return 'P-10';
    return code;
  }

  String _cleanHostelName(String rawName, [String? roomCode]) {
    final String code = (roomCode ?? '').trim().toUpperCase();
    if (code.startsWith('T30-') || code.startsWith('T30 -') || code.startsWith('T30_')) {
      return 'Krishna hostel(new)';
    }
    if (code.startsWith('T32-') || code.startsWith('T32 -') || code.startsWith('T32_')) {
      return 'Vaigai hostel(new)';
    }
    if (code.startsWith('T-30-') || code.startsWith('T-30 -')) {
      return 'Krishna Hostel';
    }
    if (code.startsWith('T-32-') || code.startsWith('T-32 -')) {
      return 'Vaigai Hostel';
    }

    final String name = rawName.trim();
    if (name.toLowerCase().contains('(new)')) {
      if (name.toLowerCase().contains('krishna')) return 'Krishna hostel(new)';
      if (name.toLowerCase().contains('vaigai')) return 'Vaigai hostel(new)';
    }
    if (name.toLowerCase().contains('krishna')) return 'Krishna Hostel';
    if (name.toLowerCase().contains('vaigai')) return 'Vaigai Hostel';
    if (name.toLowerCase().contains('kaveri')) return 'Kaveri Hostel';
    if (name.toLowerCase().contains('noyyal')) return 'Noyyal Hostel';
    if (name.toLowerCase().contains('ponni')) return 'Ponni Hostel';
    if (name.toLowerCase().contains('siruvani')) return 'Siruvani Hostel';
    if (name.toLowerCase().contains('porunai')) return 'Porunai Hostel';
    if (name.toLowerCase().contains('palar')) return 'Palar Hostel';
    if (name.toLowerCase().contains('radiance')) return 'Radiance Inn';
    if (name.toLowerCase().contains('stunner')) return 'Stunners Den';
    return rawName;
  }

  Future<bool> _updateRoomTypeDirect(Map<String, dynamic> room, String newType) async {
    try {
      final data = {
        'id': room['id'],
        'location_name': room['location_name'],
        'building_code': room['building_code'],
        'floor_no': room['floor_no'],
        'block_no': room['block_no'],
        'room_no': room['room_no'],
        'room_code': room['location_code'],
        'room_type': newType,
        'room_capacity': room['room_capacity'],
      };
      
      final res = await ApiService.postRequest('rooms/save_room_master.php', data);
      if (res['success'] == true || res['status'] == 'success') {
        if (room['id'] == null && res['id'] != null) {
          room['id'] = res['id'];
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Updated ${room['room_no']} to $newType'),
          duration: const Duration(seconds: 1),
        ));
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update room type: ${res['message'] ?? 'Unknown error'}'),
        ));
        return false;
      }
    } catch (e) {
      debugPrint('Error updating room type: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error updating room type: $e'),
      ));
      return false;
    }
  }

  int _calculateMaxRoomCols(List<Map<String, dynamic>> rooms) {
    int maxCap = 1;
    for (var r in rooms) {
      final String typeName = r['room_type']?.toString() ?? '';
      final int cap = _extractCapacity(typeName);
      if (cap > 0 && cap <= 12) {
        if (cap > maxCap) maxCap = cap;
      }
    }
    return maxCap;
  }

  Widget _buildDataTable() {
    final int dynamicColsCount = _calculateMaxRoomCols(_filteredRooms);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: PaginatedDataTable2(
          border: TableBorder.all(
            color: const Color(0xFF94A3B8),
            width: 1.5,
          ),
          columnSpacing: 24,
          minWidth: 1400 + (dynamicColsCount * 130),
          dataRowHeight: 64,
          headingRowHeight: 56,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FA)),
          rowsPerPage: 100,
          availableRowsPerPage: const [15, 25, 50, 100, 200],
          columns: [
            const DataColumn2(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 60),
            const DataColumn2(label: Text('Hostel Name', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 170),
            const DataColumn2(label: Text('Room Code', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 170),
            const DataColumn2(label: Text('Room Type', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 240),
            const DataColumn2(label: Text('Total Beds', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 90, numeric: true),
            const DataColumn2(label: Text('Occupied Beds', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 100, numeric: true),
            const DataColumn2(label: Text('Assigned Pending', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 120, numeric: true),
            const DataColumn2(label: Text('Available Beds', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 110, numeric: true),
            ...List.generate(dynamicColsCount, (i) => DataColumn2(
              label: Text('Bed ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
              size: ColumnSize.S,
              fixedWidth: 130,
            )),
            const DataColumn2(label: Text('Gender', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 80),
            const DataColumn2(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 100, numeric: true),
            const DataColumn2(label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 60),
            const DataColumn2(label: Text('Save', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 80),
          ],
          source: RoomDataTableSource(
            rooms: _filteredRooms,
            roomTypes: _roomTypes,
            dynamicColsCount: dynamicColsCount,
            onRoomTypeChanged: (room, newType) {
              setState(() {
                room['room_type'] = newType;
                room['room_capacity'] = _extractCapacity(newType);
              });
            },
            onEdit: _showAddRoomDialog,
            onSave: (room) async {
              await _updateRoomTypeDirect(room, room['room_type'] ?? 'Not Assigned');
            },
            cleanHostelName: _cleanHostelName,
            extractCapacity: _extractCapacity,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: const Color(0xFF141E2E),
      child: Column(
        children: [
          const SizedBox(height: 40),
          const Text('VSTAY ADMIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2)),
          const SizedBox(height: 40),
          _sidebarItem(Icons.bed, 'Room Master', true),
          const Spacer(),
          _sidebarItem(Icons.logout, 'Exit', false, onTap: () => Navigator.of(context, rootNavigator: true).pop()),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool active, {VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: active ? const Color(0xFFD4AF37) : Colors.white54),
      title: Text(label, style: TextStyle(color: active ? Colors.white : Colors.white54, fontSize: 14)),
    );
  }

  void _showAddRoomDialog([Map<String, dynamic>? room]) {
    showDialog(
      context: context,
      builder: (context) => RoomEditDialog(
        room: room,
        roomTypes: _roomTypes,
        onSave: _fetchInitialData,
      ),
    );
  }
}

class RoomEditDialog extends StatefulWidget {
  final Map<String, dynamic>? room;
  final List<Map<String, dynamic>> roomTypes;
  final VoidCallback onSave;
  const RoomEditDialog({super.key, this.room, required this.roomTypes, required this.onSave});
  @override
  State<RoomEditDialog> createState() => _RoomEditDialogState();
}

class _RoomEditDialogState extends State<RoomEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _locNameCtrl, _buildCtrl, _floorCtrl, _blockCtrl, _roomCtrl, _roomCodeCtrl, _capCtrl;
  String? _selectedType;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.room;
    _locNameCtrl = TextEditingController(text: r?['location_name'] ?? '');
    _buildCtrl = TextEditingController(text: r?['building_code'] ?? '');
    _floorCtrl = TextEditingController(text: r?['floor_no'] ?? '');
    _blockCtrl = TextEditingController(text: r?['block_no'] ?? '');
    _roomCtrl = TextEditingController(text: r?['room_no'] ?? '');
    _roomCodeCtrl = TextEditingController(text: r?['location_code'] ?? '');
    _capCtrl = TextEditingController(text: r?['room_capacity']?.toString() ?? '');
    _selectedType = (r?['room_type'] == 'Not Assigned') ? null : r?['room_type'];
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final data = {
      'id': widget.room?['id'],
      'location_name': _locNameCtrl.text,
      'building_code': _buildCtrl.text,
      'floor_no': _floorCtrl.text,
      'block_no': _blockCtrl.text,
      'room_no': _roomCtrl.text,
      'room_code': _roomCodeCtrl.text,
      'room_type': _selectedType ?? 'Not Assigned',
      'room_capacity': int.tryParse(_capCtrl.text) ?? 0,
    };
    await ApiService.postRequest('rooms/save_room_master.php', data);
    widget.onSave();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Edit Room Master', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 32),
                _field('Location Name', _locNameCtrl),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _field('Building', _buildCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _field('Floor', _floorCtrl)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _field('Block', _blockCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _field('Room No', _roomCtrl)),
                    const SizedBox(width: 16),
                    Expanded(child: _field('Room Code', _roomCodeCtrl)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedType,
                        hint: const Text('Select Room Type'),
                        items: widget.roomTypes.map((t) => DropdownMenuItem(value: t['name'].toString(), child: Text(t['name'].toString()))).toList(),
                        onChanged: (v) => setState(() {
                          _selectedType = v;
                          _capCtrl.text = _extractCapacity(v ?? '').toString();
                        }),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _field('Capacity', _capCtrl, isNum: true)),
                  ],
                ),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A2744), padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20)),
                      child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Record', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _extractCapacity(String name) {
    final upper = name.toUpperCase();
    final in1Match = RegExp(r'(\d+)\s*IN\s*1').firstMatch(upper);
    if (in1Match != null) {
      return int.tryParse(in1Match.group(1) ?? '') ?? 0;
    }
    final dormMatch = RegExp(r'DORM\s*(\d+)').firstMatch(upper);
    if (dormMatch != null) {
      return int.tryParse(dormMatch.group(1) ?? '') ?? 0;
    }
    if (upper.contains('DOUBLE')) {
      return 2;
    }
    if (upper.contains('SINGLE')) {
      return 1;
    }
    return 0;
  }

  Widget _field(String label, TextEditingController ctrl, {bool isNum = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(controller: ctrl, keyboardType: isNum ? TextInputType.number : TextInputType.text),
      ],
    );
  }
}

class RoomDataTableSource extends DataTableSource {
  final List<Map<String, dynamic>> rooms;
  final List<Map<String, dynamic>> roomTypes;
  final int dynamicColsCount;
  final Function(Map<String, dynamic>, String) onRoomTypeChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onSave;
  final String Function(String, [String?]) cleanHostelName;
  final int Function(String) extractCapacity;

  RoomDataTableSource({
    required this.rooms,
    required this.roomTypes,
    required this.dynamicColsCount,
    required this.onRoomTypeChanged,
    required this.onEdit,
    required this.onSave,
    required this.cleanHostelName,
    required this.extractCapacity,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= rooms.length) return null;
    final r = rooms[index];

    // Ensure value matches exactly one item in the dropdown
    final String? currentType = (r['room_type'] == 'Not Assigned' || r['room_type'] == null || r['room_type'].toString().isEmpty)
        ? null
        : r['room_type'].toString();

    // Validate if currentType is in the list of roomTypes
    final bool typeExists = roomTypes.any((t) => t['name'].toString() == currentType);
    final String? dropdownValue = typeExists ? currentType : null;

    final String idStr = r['id']?.toString() ?? (index + 1).toString();
    final int occupancy = int.tryParse(r['occupancy']?.toString() ?? '') ?? 1;
    final int totalBeds = int.tryParse(r['total_beds']?.toString() ?? '') ?? occupancy;
    final int occupiedBeds = int.tryParse(r['occupied_beds']?.toString() ?? '') ?? 0;
    final int assignedPending = int.tryParse(r['assigned_pending']?.toString() ?? '') ?? 0;
    final int availableBeds = int.tryParse(r['available_beds']?.toString() ?? '') ?? (totalBeds - (occupiedBeds + assignedPending));
    final String gender = r['gender']?.toString() ?? 'Male';
    final String amountStr = (r['amount'] != null && r['amount'].toString() != '0.00' && r['amount'].toString() != '0') 
        ? '₹${r['amount']}' 
        : '₹0';

    final String roomCode = (r['location_code'] ?? r['room_code'] ?? '').toString();

    final List<String> studentRolls = (r['students'] is List)
        ? (r['students'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final int cap = extractCapacity(r['room_type']?.toString() ?? '');
    final int roomCapacity = cap > 0 ? cap : totalBeds;

    final List<DataCell> dynamicRoomCells = List.generate(dynamicColsCount, (colIdx) {
      if (roomCapacity > 12) {
        if (colIdx == 0) {
          return DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                roomCapacity.toString(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue),
              ),
            ),
          );
        } else {
          return const DataCell(Text('-', style: TextStyle(fontSize: 12, color: Colors.grey)));
        }
      } else {
        if (colIdx < roomCapacity) {
          // ONLY show roll number if this bed slot is within the occupied count
          if (colIdx < occupiedBeds && colIdx < studentRolls.length && studentRolls[colIdx].trim().isNotEmpty) {
            final String studentRoll = studentRolls[colIdx].trim();
            return DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  studentRoll,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1565C0)),
                ),
              ),
            );
          } else {
            return const DataCell(Text('-', style: TextStyle(fontSize: 12, color: Colors.grey)));
          }
        } else {
          return const DataCell(Text('-', style: TextStyle(fontSize: 12, color: Colors.grey)));
        }
      }
    });

    return DataRow(
      cells: [
        DataCell(Text(idStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A2744)))),
        DataCell(Text(
          cleanHostelName(r['location_name'] ?? '', roomCode),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1A2744)),
        )),
        DataCell(Text(
          roomCode,
          style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'Lato'),
        )),
        DataCell(
          SizedBox(
            width: double.infinity,
            child: DropdownButtonFormField<String>(
              initialValue: dropdownValue,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              hint: const Text('Select Room Type', style: TextStyle(fontSize: 12, color: Colors.grey)),
              style: const TextStyle(fontSize: 13, color: Colors.black),
              selectedItemBuilder: (BuildContext context) {
                return [
                  const Text(
                    'Not Assigned',
                    style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13),
                    softWrap: true,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  ...roomTypes.map((type) {
                    return Text(
                      type['name'].toString(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      softWrap: true,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  }),
                ];
              },
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Not Assigned', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                ...roomTypes.map((type) {
                  final String name = type['name'].toString();
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }),
              ],
              onChanged: (newValue) => onRoomTypeChanged(r, newValue ?? 'Not Assigned'),
            ),
          ),
        ),
        DataCell(Text(totalBeds.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        DataCell(Text(occupiedBeds.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue))),
        DataCell(Text(assignedPending.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange))),
        DataCell(Text(availableBeds < 0 ? '0' : availableBeds.toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: availableBeds > 0 ? Colors.green : Colors.red))),
        ...dynamicRoomCells,
        DataCell(Text(gender, style: const TextStyle(fontSize: 12))),
        DataCell(Text(amountStr, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1A2744)))),
        DataCell(
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 20,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit, size: 18, color: Colors.blue),
            ),
            onPressed: () => onEdit(r),
          ),
        ),
        DataCell(
          ElevatedButton.icon(
            onPressed: () => onSave(r),
            icon: const Icon(Icons.save, size: 14, color: Colors.white),
            label: const Text('Save', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2744),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(76, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rooms.length;

  @override
  int get selectedRowCount => 0;
}
