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
        return {
          'id': localRoom['id'],
          'location_name': locName,
          'building_code': _normalizeBuildingCode(localRoom['building_code'] ?? '', locName),
          'floor_no': localRoom['floor_no'] ?? '',
          'block_no': localRoom['block_no'] ?? '',
          'room_no': localRoom['room_no'] ?? '',
          'room_type': roomType,
          'room_capacity': int.tryParse(localRoom['room_capacity']?.toString() ?? '') ?? _extractCapacity(roomType),
          'location_code': localRoom['room_code'] ?? '',
        };
      }).toList();

      _allRooms = mappedLocalRooms;

      // 2. Fetch external locations API via backend proxy to bypass CORS on Web
      final extResponse = await ApiService.getRequest('rooms/fetch_locations.php?t=${DateTime.now().millisecondsSinceEpoch}');
      if (extResponse['success'] == true || extResponse['status'] == 'success') {
        final dynamic decoded = extResponse['data'];
        List<dynamic> data = (decoded is List) ? decoded : (decoded['data'] ?? []);

        final List<Map<String, dynamic>> externalRooms = data.map<Map<String, dynamic>>((item) {
          final String locationCode = item['location_code'] ?? '';
          final String locationName = item['location_name'] ?? '';
          
          // Smart parsing: find F\d+ floor token so building codes with dashes
          // (T-30, T-32, T-14, T-19, P-05) are kept intact.
          // e.g. "T-30-F01-WA0-R01" → building=T-30, floor=F01, wing=WA0, room=R01
          String buildingCode = 'N/A';
          String floorCode    = 'N/A';
          String wingCode     = 'N/A';
          String roomCode     = 'N/A';
          if (locationCode.isNotEmpty) {
            final parts = locationCode.split('-');
            int floorIdx = -1;
            for (int i = 0; i < parts.length; i++) {
              if (RegExp(r'^F\d+$', caseSensitive: false).hasMatch(parts[i])) {
                floorIdx = i;
                break;
              }
            }
            if (floorIdx != -1) {
              buildingCode = parts.sublist(0, floorIdx).join('-');
              floorCode    = parts[floorIdx];
              wingCode     = floorIdx + 1 < parts.length ? parts[floorIdx + 1] : 'N/A';
              roomCode     = floorIdx + 2 < parts.length ? parts[floorIdx + 2] : 'N/A';
            } else {
              buildingCode = parts.isNotEmpty ? parts[0] : 'N/A';
              floorCode    = parts.length > 1 ? parts[1] : 'N/A';
              wingCode     = parts.length > 2 ? parts[2] : 'N/A';
              roomCode     = parts.length > 3 ? parts[3] : 'N/A';
            }
          }
          buildingCode = _normalizeBuildingCode(buildingCode, locationName);
          final normalizedFloor = _normalizeFloor(floorCode);
          
          // Look up local database record for room details
          final localRoom = (locationCode.isNotEmpty ? localRoomsByCode[locationCode] : null) ?? localRoomsByName[locationName];
          final String roomType = localRoom?['room_type'] ?? 'Not Assigned';
          final int roomCapacity = localRoom?['room_capacity'] != null 
              ? int.tryParse(localRoom!['room_capacity'].toString()) ?? _extractCapacity(locationName)
              : _extractCapacity(locationName);
          final dynamic localId = localRoom?['id'];

          return {
            'id': localId,
            'location_name': locationName,
            'building_code': buildingCode,
            'floor_no': normalizedFloor,
            'block_no': wingCode,
            'room_no': roomCode,
            'room_type': roomType,
            'room_capacity': roomCapacity,
            'location_code': locationCode,
          };
        }).toList();

        // Avoid duplicates in the external list
        final Set<String> processedNames = externalRooms.map((r) => r['location_name'] as String).toSet();
        
        // Append local rooms that are not in the external list
        final List<Map<String, dynamic>> missingLocalRooms = [];
        for (var entry in localRoomsByName.entries) {
          if (!processedNames.contains(entry.key)) {
            final localRoom = entry.value;
            final String roomType = localRoom['room_type'] ?? 'Not Assigned';
            final String locName = localRoom['location_name'] ?? '';
            missingLocalRooms.add({
              'id': localRoom['id'],
              'location_name': locName,
              'building_code': _normalizeBuildingCode(localRoom['building_code'] ?? '', locName),
              'floor_no': localRoom['floor_no'] ?? '',
              'block_no': localRoom['block_no'] ?? '',
              'room_no': localRoom['room_no'] ?? '',
              'room_type': roomType,
              'room_capacity': int.tryParse(localRoom['room_capacity']?.toString() ?? '') ?? _extractCapacity(roomType),
              'location_code': localRoom['room_code'] ?? '',
            });
          }
        }

        _allRooms = [...externalRooms, ...missingLocalRooms];
      }
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
    // Canonical group codes — map parsed room-code prefixes to their group codes
    if (code == 'T14' || code == 'T-14') return 'T-14';
    if (code == 'T12' || code == 'T-12') return 'T-12';
    if (code == 'T30' || code == 'T-30') return 'T-30';
    if (code == 'T32' || code == 'T-32') return 'T-32';
    if (code == 'T19' || code == 'T-19') return 'T-19';
    // P04- prefix rooms belong to the P05 group (Max Fax)
    if (code == 'P04') return 'P05';
    // P05- prefix rooms belong to the P-05 group (Radiance Inn)
    if (code == 'P05') return 'P-05';
    // P-10 prefix rooms belong to the P10 group (Stunners Den)
    if (code == 'P-10') return 'P10';
    return code;
  }

  String _cleanHostelName(String rawName) {
    final Map<String, String> hostelMapping = {
      'KAVERI': 'Kaveri Hostel',
      'VAIGAI': 'Vaigai Hostel',
      'KRISHNA': 'Krishna Hostel',
      'KRISHAN': 'Krishna Hostel',
      'NOYYAL': 'Noyyal Hostel',
      'PONNI': 'Ponni Hostel',
      'SIRUVANI': 'Siruvani Hostel',
      'PORUNAI': 'Porunai Hostel (4F - 8F )',
      'PALAR': 'Palar Hostel',
      'ALLIED': 'Allied Health Sciences',
      'RADIANTS': 'Radiance Inn',
      'MAXFAX': 'Max Fax',
      'MAX FAX': 'Max Fax',
      'STUNNER': 'Stunners Den',
    };
    
    final upperName = rawName.toUpperCase();
    for (var entry in hostelMapping.entries) {
      if (upperName.contains(entry.key)) {
        return entry.value;
      }
    }
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

  Widget _buildDataTable() {
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
            color: const Color(0xFFEAEAEA),
            width: 0.5,
          ),
          columnSpacing: 24,
          minWidth: 1000,
          dataRowHeight: 64,
          headingRowHeight: 56,
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8F9FA)),
          rowsPerPage: 15,
          availableRowsPerPage: const [10, 15, 25, 50, 100],
          columns: const [
            DataColumn2(label: Text('Hostel Name', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 264),
            DataColumn2(label: Text('Room Code', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 240),
            DataColumn2(label: Text('Room Type', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 300),
            DataColumn2(label: Text('Edit', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 80, numeric: false),
            DataColumn2(label: Text('Save', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A2744))), size: ColumnSize.S, fixedWidth: 90),
          ],
          source: RoomDataTableSource(
            rooms: _filteredRooms,
            roomTypes: _roomTypes,
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
          const Text('RR ADMIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2)),
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
  final Function(Map<String, dynamic>, String) onRoomTypeChanged;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onSave;
  final String Function(String) cleanHostelName;

  RoomDataTableSource({
    required this.rooms,
    required this.roomTypes,
    required this.onRoomTypeChanged,
    required this.onEdit,
    required this.onSave,
    required this.cleanHostelName,
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

    return DataRow(
      cells: [
        DataCell(Text(
          cleanHostelName(r['location_name'] ?? ''),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1A2744)),
        )),
        DataCell(Text(
          r['location_code'] ?? '',
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
