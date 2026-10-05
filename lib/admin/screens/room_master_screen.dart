import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:data_table_2/data_table_2.dart';
import 'package:csv/csv.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/wallpaper_provider.dart';
import '../../warden/widgets/warden_widgets.dart';
import '../dialogs/csv_helper_stub.dart'
    if (dart.library.html) '../dialogs/csv_helper_web.dart'
    if (dart.library.io) '../dialogs/csv_helper_mobile.dart';

class RoomMasterScreen extends StatefulWidget {
  const RoomMasterScreen({super.key});

  @override
  State<RoomMasterScreen> createState() => _RoomMasterScreenState();
}

class _RoomMasterScreenState extends State<RoomMasterScreen> {
  // ── Data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _roomTypes = [];

  // ── Loading state ─────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isExporting = false;

  // ── Filters ───────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String? _selectedLocationFilter;
  String? _selectedBuildingFilter;
  String? _selectedFloorFilter;
  Timer? _debounce;

  // ── Dropdown options derived from backend metadata ────────────────────────
  List<String> _locationOptions = [];
  List<String> _buildingOptions = [];
  List<String> _floorOptions = [];

  // ── Server-side pagination state ──────────────────────────────────────────
  int _currentPage = 1;
  int _totalRows   = 0;
  int _totalPages  = 1;
  static const int _perPage = 100;

  // ── Precomputed for rendering (avoids recomputing inside build) ───────────
  int _maxRoomCols = 1;

  @override
  void initState() {
    super.initState();
    _fetchRoomTypes();
    _loadPage(1);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATA FETCHING
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds the query string from current filter state + pagination.
  String _buildQueryParams({int? page, int? limit}) {
    final params = <String, String>{};
    params['page']  = (page ?? _currentPage).toString();
    params['limit'] = (limit ?? _perPage).toString();
    if (_selectedLocationFilter != null) params['location_name'] = _selectedLocationFilter!;
    if (_selectedBuildingFilter != null) params['building_code'] = _selectedBuildingFilter!;
    if (_selectedFloorFilter    != null) params['floor_no']       = _selectedFloorFilter!;
    final search = _searchController.text.trim();
    if (search.isNotEmpty) params['search'] = search;
    return params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  }

  /// Fetches a specific page from the server. Replaces client-side filtering.
  Future<void> _loadPage(int page) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final qs       = _buildQueryParams(page: page);
      final response = await ApiService.getRequest(
        'rooms/fetch_room_master.php?$qs&t=${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) return;

      if (response['status'] == 'success' || response['success'] == true) {
        final List<dynamic> rawData = response['data'] ?? [];
        final int total             = int.tryParse(response['total']?.toString() ?? '0') ?? 0;
        final int totalPages        = int.tryParse(response['total_pages']?.toString() ?? '1') ?? 1;

        final mapped = rawData.map<Map<String, dynamic>>((item) {
          if (item is Map) return _mapRoom(Map<String, dynamic>.from(item));
          return {};
        }).where((r) => r.isNotEmpty).toList();

        // Read full distinct locations, buildings and floors from backend metadata
        if (response['locations'] is List && (response['locations'] as List).isNotEmpty) {
          final lList = (response['locations'] as List).map((e) => e.toString().trim()).where((l) => l.isNotEmpty).toSet().toList()..sort();
          _locationOptions = lList;
        }

        if (response['buildings'] is List && (response['buildings'] as List).isNotEmpty) {
          final bList = (response['buildings'] as List).map((e) => e.toString().trim()).where((b) => b.isNotEmpty).toSet().toList()..sort();
          _buildingOptions = bList;
        } else if (_buildingOptions.isEmpty) {
          final buildings = mapped.map((r) => r['building_code'].toString()).toSet().toList()..sort();
          _buildingOptions = buildings.where((b) => b.isNotEmpty).toList();
        }

        if (response['floors'] is List && (response['floors'] as List).isNotEmpty) {
          final fList = (response['floors'] as List).map((e) => e.toString().trim()).where((f) => f.isNotEmpty).toSet().toList()..sort();
          _floorOptions = fList;
        } else if (_floorOptions.isEmpty) {
          final floors = mapped.map((r) => r['floor_no'].toString()).toSet().toList()..sort();
          _floorOptions = floors.where((f) => f.isNotEmpty).toList();
        }

        setState(() {
          _rooms       = mapped;
          _currentPage = page;
          _totalRows   = total;
          _totalPages  = totalPages;
          _maxRoomCols = _calculateMaxRoomCols(mapped);
          _isLoading   = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading rooms page $page: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchRoomTypes() async {
    try {
      final res = await ApiService.getRequest('rooms/fetch_external_room_types.php');
      if ((res['success'] == true || res['status'] == 'success') && mounted) {
        final List<dynamic> list = res['data'] ?? [];
        setState(() {
          _roomTypes = list
              .map((item) => item is Map
                  ? Map<String, dynamic>.from(item)
                  : {'id': item.toString(), 'name': item.toString()})
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _roomTypes = [
            {'id': '1', 'name': '4 IN 1 AC'},
            {'id': '2', 'name': '6 IN 1 AC'},
          ];
        });
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER / SEARCH (debounced, server-side)
  // ─────────────────────────────────────────────────────────────────────────

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _loadPage(1); // reset to page 1 on new search
    });
  }

  void _onFilterChanged() {
    _loadPage(1);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EXPORT (full export API call — not just current page)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _exportToCSV() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparing export — fetching all rooms…'),
          duration: Duration(seconds: 3),
        ),
      );

      // Fetch ALL rooms (page=0 disables pagination on the server)
      final qs       = _buildQueryParams(page: 0, limit: 9999);
      final response = await ApiService.getRequest(
        'rooms/fetch_room_master.php?$qs&t=${DateTime.now().millisecondsSinceEpoch}',
      );

      if (!mounted) return;

      if (response['status'] == 'success' || response['success'] == true) {
        final List<dynamic> rawData = response['data'] ?? [];
        final allRooms = rawData.map<Map<String, dynamic>>((item) {
          if (item is Map) return _mapRoom(Map<String, dynamic>.from(item));
          return {};
        }).where((r) => r.isNotEmpty).toList();

        final List<List<dynamic>> rows = [
          ['ID', 'Hostel Name', 'Room Code', 'Building', 'Floor', 'Room No', 'Room Type', 'Total Beds', 'Occupied Beds', 'Available Beds', 'Assigned Pending', 'Gender', 'Amount', 'Students'],
        ];

        for (final room in allRooms) {
          final students = (room['students'] is List)
              ? (room['students'] as List).join(', ')
              : '';
          rows.add([
            room['id']?.toString() ?? '',
            room['location_name'] ?? '',
            room['location_code'] ?? '',
            room['building_code'] ?? '',
            room['floor_no'] ?? '',
            room['room_no'] ?? '',
            room['room_type'] ?? 'Not Assigned',
            room['total_beds']?.toString() ?? '0',
            room['occupied_beds']?.toString() ?? '0',
            room['available_beds']?.toString() ?? '0',
            room['assigned_pending']?.toString() ?? '0',
            room['gender'] ?? '',
            room['amount']?.toString() ?? '0',
            students,
          ]);
        }

        final String csvContent = const ListToCsvConverter().convert(rows);
        downloadCSV(csvContent, 'room_master_export_${allRooms.length}_rooms.csv');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Exported ${allRooms.length} rooms to CSV ✓'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Export failed — please try again'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _mapRoom(Map<String, dynamic> localRoom) {
    final String roomType = localRoom['room_type'] ?? 'Not Assigned';
    final String locName  = localRoom['location_name'] ?? '';
    final int occupancy   = int.tryParse(localRoom['occupancy']?.toString()   ?? '') ??
                            int.tryParse(localRoom['total_beds']?.toString()  ?? '') ??
                            _extractCapacity(roomType);
    final int totalBeds      = int.tryParse(localRoom['total_beds']?.toString()      ?? '') ?? occupancy;
    final int occupiedBeds   = int.tryParse(localRoom['occupied_beds']?.toString()   ?? '') ?? 0;
    final int assignedPending= int.tryParse(localRoom['assigned_pending']?.toString() ?? '') ?? 0;
    final int availableBeds  = int.tryParse(localRoom['available_beds']?.toString()  ?? '') ??
                               (totalBeds - (occupiedBeds + assignedPending));

    final String roomCode      = localRoom['room_code'] ?? localRoom['location_code'] ?? '';
    final List<dynamic> rawSt  = localRoom['students'] is List ? localRoom['students'] : [];
    final List<String> students= rawSt.map((s) => s.toString()).toList();

    return {
      'id':               localRoom['id'],
      'location_name':    _cleanHostelName(locName, roomCode),
      'building_code':    _normalizeBuildingCode(localRoom['building_code'] ?? '', locName),
      'floor_no':         localRoom['floor_no'] ?? '',
      'block_no':         localRoom['block_no'] ?? '',
      'room_no':          localRoom['room_no'] ?? '',
      'room_type':        roomType,
      'occupancy':        occupancy,
      'total_beds':       totalBeds,
      'occupied_beds':    occupiedBeds,
      'assigned_pending': assignedPending,
      'available_beds':   availableBeds < 0 ? 0 : availableBeds,
      'gender':           localRoom['gender'] ?? 'Male',
      'active':           localRoom['active'] ?? 1,
      'amount':           localRoom['amount'] ?? 0.00,
      'location_code':    roomCode,
      'students':         students,
    };
  }

  int _calculateMaxRoomCols(List<Map<String, dynamic>> rooms) {
    int maxCap = 1;
    for (final r in rooms) {
      final int cap = _extractCapacity(r['room_type']?.toString() ?? '');
      if (cap > 0 && cap <= 12 && cap > maxCap) maxCap = cap;
    }
    return maxCap;
  }

  int _extractCapacity(String name) {
    final String upper = name.toUpperCase();
    final RegExpMatch? res = RegExp(r'(\d+)\s*IN\s*1').firstMatch(upper);
    if (res != null) return int.parse(res.group(1)!);
    if (upper.contains('FOUR') || upper.contains('4')) return 4;
    if (upper.contains('TRIPLE') || upper.contains('3')) return 3;
    if (upper.contains('DOUBLE')) return 2;
    if (upper.contains('SINGLE')) return 1;
    return 0;
  }

  String _normalizeBuildingCode(String buildingCode, String locationName) {
    final String code = buildingCode.trim();
    const Map<String, String> map = {
      'T30': 'T30', 'T-30': 'T-30', 'T32': 'T32', 'T-32': 'T-32',
      'T14': 'T14', 'T-14': 'T14', 'T12': 'T12', 'T-12': 'T12',
      'T19': 'T19', 'T-19': 'T19', 'T10': 'T10', 'T-10': 'T10',
      'T22': 'T22', 'T-22': 'T22', 'T09': 'T09', 'T-09': 'T09',
      'P05': 'P-05', 'P-05': 'P-05', 'P10': 'P-10', 'P-10': 'P-10',
    };
    return map[code] ?? code;
  }

  String _cleanHostelName(String rawName, [String? roomCode]) {
    final String code = (roomCode ?? '').trim().toUpperCase();
    if (code.startsWith('T30-') || code.startsWith('T30 -') || code.startsWith('T30_')) return 'Krishna hostel(new)';
    if (code.startsWith('T32-') || code.startsWith('T32 -') || code.startsWith('T32_')) return 'Vaigai hostel(new)';
    if (code.startsWith('T-30-') || code.startsWith('T-30 -')) return 'Krishna Hostel';
    if (code.startsWith('T-32-') || code.startsWith('T-32 -')) return 'Vaigai Hostel';
    final String name = rawName.trim().toLowerCase();
    if (name.contains('(new)') && name.contains('krishna')) return 'Krishna hostel(new)';
    if (name.contains('(new)') && name.contains('vaigai'))  return 'Vaigai hostel(new)';
    if (name.contains('krishna'))  return 'Krishna Hostel';
    if (name.contains('vaigai'))   return 'Vaigai Hostel';
    if (name.contains('kaveri'))   return 'Kaveri Hostel';
    if (name.contains('noyyal'))   return 'Noyyal Hostel';
    if (name.contains('ponni'))    return 'Ponni Hostel';
    if (name.contains('siruvani')) return 'Siruvani Hostel';
    if (name.contains('porunai'))  return 'Porunai Hostel';
    if (name.contains('palar'))    return 'Palar Hostel';
    if (name.contains('radiance')) return 'Radiance Inn';
    if (name.contains('stunner'))  return 'Stunners Den';
    return rawName;
  }

  Future<bool> _updateRoomTypeDirect(Map<String, dynamic> room, String newType) async {
    // Capture messenger before async gap
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ApiService.postRequest('rooms/save_room_master.php', {
        'id':             room['id'],
        'location_name':  room['location_name'],
        'building_code':  room['building_code'],
        'floor_no':       room['floor_no'],
        'block_no':       room['block_no'],
        'room_no':        room['room_no'],
        'room_code':      room['location_code'],
        'room_type':      newType,
        'room_capacity':  room['room_capacity'],
      });
      if (res['success'] == true || res['status'] == 'success') {
        if (room['id'] == null && res['id'] != null) room['id'] = res['id'];
        messenger.showSnackBar(SnackBar(
          content: Text('Updated ${room['room_no']} to $newType'),
          duration: const Duration(seconds: 1),
        ));
        return true;
      }
    } catch (e) {
      debugPrint('Error updating room type: $e');
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Failed to update room type')),
    );
    return false;
  }

  // ── Student detail popup (click on bed cell reg number) ────────────────────
  Future<void> _showStudentDetailModal(BuildContext context, String regNo) async {
    // Capture navigator/messenger before any async gap (lint: use_build_context_synchronously)
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Show loading spinner immediately (before await — context is still valid)
    navigator.push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.black26,
      pageBuilder: (_, __, ___) =>
          const Center(child: CircularProgressIndicator()),
    ));

    try {
      final res = await ApiService.getRequest(
        'rooms/get_student_by_regno.php?reg_no=${Uri.encodeComponent(regNo)}',
      );
      if (!mounted) return;
      navigator.pop(); // close loader

      if (res['success'] != true || res['student'] == null) {
        messenger.showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Student not found'), backgroundColor: Colors.red),
        );
        return;
      }

      final Map<String, dynamic> s = Map<String, dynamic>.from(res['student']);
      final String name        = s['student_name'] ?? 'Student';
      final String sRegNo      = s['reg_no'] ?? regNo;
      final String roomNo      = s['room_allocation'] ?? 'N/A';
      final String phone       = (s['phone'] ?? '').toString();
      final String renewal     = (s['renewal_date'] ?? 'N/A').toString();
      final String hostel      = (s['hostel_name'] ?? 'N/A').toString();
      final String institution = (s['institution'] ?? '').toString();
      final String warden      = (s['warden'] ?? '').toString();
      final String gender      = (s['gender'] ?? '').toString();
      final String roomType    = (s['room_type'] ?? '').toString();
      final String checkIn     = (s['check_in_date'] ?? 'N/A').toString();

      if (!mounted) return;
      final overlayContext = navigator.overlay?.context;
      if (overlayContext == null) return;
      // ignore: use_build_context_synchronously
      showDialog(
        context: overlayContext, // ignore: use_build_context_synchronously
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────────
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF1A2744),
                      child: const Icon(Icons.person, color: Color(0xFFD4AF37), size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: Color(0xFF1A2744))),
                          Text('Reg No: $sRegNo',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13)),
                          if (institution.isNotEmpty)
                            Text(institution,
                                style: TextStyle(
                                    color: Colors.grey.shade500, fontSize: 11)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const Divider(height: 24),

                const Text('Student Details & Renewal Status',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1A2744))),
                const SizedBox(height: 14),

                _buildStudentTile(Icons.door_sliding_outlined, 'Assigned Room', roomNo),
                const SizedBox(height: 10),
                _buildStudentTile(Icons.home_outlined, 'Hostel', hostel),
                const SizedBox(height: 10),
                _buildStudentTile(Icons.phone_outlined, 'Contact Number',
                    phone.isNotEmpty ? phone : 'N/A'),
                const SizedBox(height: 10),
                if (gender.isNotEmpty) ...[
                  _buildStudentTile(Icons.wc_outlined, 'Gender', gender),
                  const SizedBox(height: 10),
                ],
                if (roomType.isNotEmpty) ...[
                  _buildStudentTile(Icons.bed_outlined, 'Room Type', roomType),
                  const SizedBox(height: 10),
                ],
                _buildStudentTile(Icons.login_outlined, 'Check-in Date', checkIn),
                const SizedBox(height: 10),
                _buildStudentTile(Icons.event_repeat_outlined, 'Renewal Date', renewal,
                    isHighlight: true),
                const SizedBox(height: 10),
                if (warden.isNotEmpty)
                  _buildStudentTile(Icons.supervised_user_circle_outlined, 'Warden', warden),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2744),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        navigator.pop(); // close loader if error
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStudentTile(IconData icon, String label, String value,
      {bool isHighlight = false}) {
    return Row(
      children: [
        Icon(icon,
            size: 18,
            color: isHighlight
                ? const Color(0xFFD4AF37)
                : const Color(0xFF1A2744)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500)),
        ),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isHighlight
                      ? const Color(0xFFD4AF37)
                      : const Color(0xFF1A2744))),
        ),
      ],
    );
  }

  void _showAddRoomDialog([Map<String, dynamic>? room]) {
    showDialog(
      context: context,
      builder: (context) => RoomEditDialog(
        room: room,
        roomTypes: _roomTypes,
        onSave: () => _loadPage(_currentPage),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final bool isDark = wallpaper?.isDarkTheme ?? false;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth > 1100;
            return Row(
              children: [
                if (isWide) _buildSidebar(isDark),
                Expanded(
                  child: Column(
                    children: [
                      _buildAppBar(!isWide, isDark),
                      _buildFilterBar(isDark),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: _isLoading ? _buildSkeletonLoader(isDark) : _buildDataTable(isDark),
                        ),
                      ),
                      _buildPaginationBar(isDark),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Skeleton loader — shows immediately while data loads ──────────────────
  Widget _buildSkeletonLoader(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 15, offset: const Offset(0, 5))],
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Skeleton header row
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F1520) : const Color(0xFFF8F9FA),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: List.generate(7, (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade300, borderRadius: BorderRadius.circular(7)),
                  ),
                ),
              )),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),
          // Skeleton data rows
          Expanded(
            child: ListView.separated(
              itemCount: 12,
              separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade200),
              itemBuilder: (_, rowIdx) => Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: List.generate(7, (i) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
                      child: Container(
                        height: 12,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool showBack, bool isDark) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white, 
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : const Color(0xFF1A2744)),
            tooltip: 'Back to Admin Dashboard',
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
          const SizedBox(width: 8),
          Text('Room Master Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744), fontFamily: 'Lato')),
          const Spacer(),
          // Total count badge
          if (_totalRows > 0)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white12 : const Color(0xFF1A2744).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: isDark ? Border.all(color: const Color(0xFFD4AF37).withOpacity(0.3)) : null,
              ),
              child: Text(
                '$_totalRows rooms',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _isExporting ? null : _exportToCSV,
            icon: _isExporting
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.file_download, size: 16, color: Colors.white),
            label: Text(_isExporting ? 'Exporting…' : 'Export Excel',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Reusable Searchable Selection Dialog ──────────────────────────────────
  Future<String?> _showSearchableSelectDialog({
    required BuildContext context,
    required String title,
    required List<String> items,
    String? currentSelected,
    bool allowClear = true,
    String clearLabel = 'All',
    bool isDark = false,
  }) async {
    String searchQuery = '';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredItems = items
                .where((item) =>
                    item.trim().isNotEmpty &&
                    item.toLowerCase().contains(searchQuery.toLowerCase().trim()))
                .toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: isDark ? BorderSide(color: Colors.white.withOpacity(0.14)) : BorderSide.none,
              ),
              backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440, maxHeight: 540),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Row
                      Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 20, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Select $title',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 20, color: isDark ? Colors.white70 : Colors.grey),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Search Input Field with real-time filtering
                      TextField(
                        autofocus: true,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Type to search $title…',
                          hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey),
                          prefixIcon: Icon(Icons.search, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.clear, size: 16, color: isDark ? Colors.white70 : Colors.grey),
                                  onPressed: () => setDialogState(() => searchQuery = ''),
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F1520) : const Color(0xFFF8F9FA),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                        ),
                        onChanged: (val) => setDialogState(() => searchQuery = val),
                      ),
                      const SizedBox(height: 10),
                      // List of options
                      Expanded(
                        child: ListView(
                          children: [
                            if (allowClear)
                              ListTile(
                                dense: true,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                leading: Icon(
                                  Icons.all_inclusive,
                                  size: 18,
                                  color: currentSelected == null ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) : Colors.grey,
                                ),
                                title: Text(
                                  '$clearLabel $title',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: currentSelected == null ? FontWeight.bold : FontWeight.normal,
                                    color: currentSelected == null ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                                trailing: currentSelected == null
                                    ? Icon(Icons.check, size: 18, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744))
                                    : null,
                                tileColor: currentSelected == null ? (isDark ? const Color(0xFFD4AF37).withOpacity(0.15) : const Color(0xFF1A2744).withValues(alpha: 0.06)) : null,
                                onTap: () => Navigator.of(dialogContext).pop('__CLEAR__'),
                              ),
                            if (filteredItems.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Text('No $title matches "$searchQuery"', style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey)),
                                ),
                              )
                            else
                              ...filteredItems.map((item) {
                                final isSelected = item == currentSelected;
                                return ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  title: Text(
                                    item,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) : (isDark ? Colors.white : Colors.black87),
                                    ),
                                  ),
                                  trailing: isSelected
                                      ? Icon(Icons.check, size: 18, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744))
                                      : null,
                                  tileColor: isSelected ? (isDark ? const Color(0xFFD4AF37).withOpacity(0.15) : const Color(0xFF1A2744).withValues(alpha: 0.06)) : null,
                                  onTap: () => Navigator.of(dialogContext).pop(item),
                                );
                              }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Filter Bar ────────────────────────────────────────────────────────────
  Widget _buildFilterBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFEEEEEE))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 250,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Search Location, Room, or Code…',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                  prefixIcon: Icon(Icons.search, color: isDark ? const Color(0xFFD4AF37) : Colors.grey),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0F1520) : const Color(0xFFF8F9FA),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            _buildDropdownFilter(
              'Hostel',
              _selectedLocationFilter,
              _locationOptions,
              (v) { setState(() => _selectedLocationFilter = v); _onFilterChanged(); },
              isDark,
            ),
            const SizedBox(width: 16),
            _buildDropdownFilter(
              'Building',
              _selectedBuildingFilter,
              _buildingOptions,
              (v) { setState(() => _selectedBuildingFilter = v); _onFilterChanged(); },
              isDark,
            ),
            const SizedBox(width: 16),
            _buildDropdownFilter(
              'Floor',
              _selectedFloorFilter,
              _floorOptions,
              (v) { setState(() => _selectedFloorFilter = v); _onFilterChanged(); },
              isDark,
            ),
            const SizedBox(width: 16),
            // Reset / Clear filters button
            if (_selectedLocationFilter != null || _selectedBuildingFilter != null || _selectedFloorFilter != null || _searchController.text.isNotEmpty) ...[
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedLocationFilter = null;
                    _selectedBuildingFilter = null;
                    _selectedFloorFilter = null;
                    _searchController.clear();
                  });
                  _onFilterChanged();
                },
                icon: const Icon(Icons.clear_all, size: 16, color: Colors.red),
                label: const Text('Clear Filters', style: TextStyle(fontSize: 12, color: Colors.red)),
              ),
              const SizedBox(width: 12),
            ],
            // Refresh button
            OutlinedButton.icon(
              onPressed: () => _loadPage(_currentPage),
              icon: Icon(Icons.refresh, size: 16, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
              label: Text('Refresh', style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744))),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownFilter(String hint, String? val, List<String> items, Function(String?) fn, bool isDark) {
    final displayText = val ?? 'All $hint';
    final isSelected = val != null;

    return InkWell(
      onTap: () async {
        final result = await _showSearchableSelectDialog(
          context: context,
          title: hint,
          items: items,
          currentSelected: val,
          allowClear: true,
          clearLabel: 'All',
          isDark: isDark,
        );
        if (result != null) {
          fn(result == '__CLEAR__' ? null : result);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? const Color(0xFFD4AF37).withOpacity(0.15) : const Color(0xFF1A2744).withValues(alpha: 0.05)) : (isDark ? const Color(0xFF0F1520) : Colors.white),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4AF37) : (isDark ? Colors.white24 : Colors.grey.shade300),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                displayText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) : (isDark ? Colors.white : Colors.black87),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.search_rounded,
              size: 16,
              color: isSelected ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) : (isDark ? Colors.white60 : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Pagination bar ────────────────────────────────────────────────────────
  Widget _buildPaginationBar(bool isDark) {
    if (_totalPages <= 1 && _totalRows == 0) return const SizedBox.shrink();
    final int start = _totalRows == 0 ? 0 : ((_currentPage - 1) * _perPage) + 1;
    final int end   = (_currentPage * _perPage).clamp(0, _totalRows);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $_totalRows rooms',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey),
          ),
          const Spacer(),
          // First page
          IconButton(
            icon: Icon(Icons.first_page, color: isDark ? Colors.white70 : Colors.black87),
            onPressed: _currentPage > 1 ? () => _loadPage(1) : null,
            tooltip: 'First page',
          ),
          // Previous page
          IconButton(
            icon: Icon(Icons.chevron_left, color: isDark ? Colors.white70 : Colors.black87),
            onPressed: _currentPage > 1 ? () => _loadPage(_currentPage - 1) : null,
            tooltip: 'Previous page',
          ),
          // Page indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Page $_currentPage / $_totalPages',
              style: TextStyle(color: isDark ? const Color(0xFF1A2744) : Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          // Next page
          IconButton(
            icon: Icon(Icons.chevron_right, color: isDark ? Colors.white70 : Colors.black87),
            onPressed: _currentPage < _totalPages ? () => _loadPage(_currentPage + 1) : null,
            tooltip: 'Next page',
          ),
          // Last page
          IconButton(
            icon: Icon(Icons.last_page, color: isDark ? Colors.white70 : Colors.black87),
            onPressed: _currentPage < _totalPages ? () => _loadPage(_totalPages) : null,
            tooltip: 'Last page',
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable(bool isDark) {
    final hStyle = TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744));

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05), blurRadius: 15, offset: const Offset(0, 5))],
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DataTable2(
          border: TableBorder.all(color: isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8), width: 1.5),
          columnSpacing: 24,
          minWidth: 1400 + (_maxRoomCols * 130),
          dataRowHeight: 64,
          headingRowHeight: 56,
          headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF0F1520) : const Color(0xFFF8F9FA)),
          columns: [
            DataColumn2(label: Text('ID',               style: hStyle), size: ColumnSize.S, fixedWidth: 60),
            DataColumn2(label: Text('Hostel Name',      style: hStyle), size: ColumnSize.S, fixedWidth: 170),
            DataColumn2(label: Text('Room Code',        style: hStyle), size: ColumnSize.S, fixedWidth: 170),
            DataColumn2(label: Text('Room Type',        style: hStyle), size: ColumnSize.S, fixedWidth: 240),
            DataColumn2(label: Text('Total Beds',       style: hStyle), size: ColumnSize.S, fixedWidth: 90,  numeric: true),
            DataColumn2(label: Text('Occupied Beds',    style: hStyle), size: ColumnSize.S, fixedWidth: 100, numeric: true),
            DataColumn2(label: Text('Assigned Pending', style: hStyle), size: ColumnSize.S, fixedWidth: 120, numeric: true),
            DataColumn2(label: Text('Available Beds',   style: hStyle), size: ColumnSize.S, fixedWidth: 110, numeric: true),
            ...List.generate(_maxRoomCols, (i) => DataColumn2(
              label: Text('Bed ${i + 1}', style: hStyle),
              size: ColumnSize.S,
              fixedWidth: 130,
            )),
            DataColumn2(label: Text('Gender', style: hStyle), size: ColumnSize.S, fixedWidth: 80),
            DataColumn2(label: Text('Amount', style: hStyle), size: ColumnSize.S, fixedWidth: 100, numeric: true),
            DataColumn2(label: Text('Edit',   style: hStyle), size: ColumnSize.S, fixedWidth: 60),
            DataColumn2(label: Text('Save',   style: hStyle), size: ColumnSize.S, fixedWidth: 95),
          ],
          rows: _rooms.map((r) => _buildRow(r, isDark)).toList(),
        ),
      ),
    );
  }

  DataRow2 _buildRow(Map<String, dynamic> r, bool isDark) {
    final String? currentType = (r['room_type'] == 'Not Assigned' || r['room_type'] == null || r['room_type'].toString().isEmpty)
        ? null
        : r['room_type'].toString();
    final bool typeExists    = _roomTypes.any((t) => t['name'].toString() == currentType);
    final String? dropdownVal = typeExists ? currentType : null;

    final String idStr          = r['id']?.toString() ?? '';
    final int totalBeds         = int.tryParse(r['total_beds']?.toString()       ?? '') ?? 0;
    final int occupiedBeds      = int.tryParse(r['occupied_beds']?.toString()    ?? '') ?? 0;
    final int assignedPending   = int.tryParse(r['assigned_pending']?.toString() ?? '') ?? 0;
    final int availableBeds     = int.tryParse(r['available_beds']?.toString()   ?? '') ?? 0;
    final String gender         = r['gender']?.toString() ?? 'Male';
    final String amountStr      = (r['amount'] != null && r['amount'].toString() != '0.00' && r['amount'].toString() != '0')
        ? '₹${r['amount']}' : '₹0';
    final String roomCode       = (r['location_code'] ?? r['room_code'] ?? '').toString();
    final List<String> students = (r['students'] is List)
        ? (r['students'] as List).map((e) => e.toString()).toList()
        : <String>[];

    final int cap         = _extractCapacity(r['room_type']?.toString() ?? '');
    final int roomCapacity = cap > 0 ? cap : totalBeds;

    final List<DataCell> bedCells = List.generate(_maxRoomCols, (colIdx) {
      if (roomCapacity > 12) {
        return colIdx == 0
            ? DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(roomCapacity.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue)),
              ))
            : DataCell(Text('-', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey)));
      }
      if (colIdx < roomCapacity) {
        if (colIdx < occupiedBeds && colIdx < students.length && students[colIdx].trim().isNotEmpty) {
          final String regNo = students[colIdx].trim();
          return DataCell(GestureDetector(
            onTap: () => _showStudentDetailModal(context, regNo),
            child: Tooltip(
              message: 'Tap to view student details',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: isDark ? 0.25 : 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: isDark ? 0.4 : 0.3),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(regNo,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.lightBlueAccent : const Color(0xFF1565C0))),
                    const SizedBox(width: 4),
                    Icon(Icons.info_outline,
                        size: 11,
                        color: isDark
                            ? Colors.lightBlueAccent.withOpacity(0.7)
                            : const Color(0xFF1565C0).withOpacity(0.6)),
                  ],
                ),
              ),
            ),
          ));
        }
        return DataCell(Text('-', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey)));
      }
      return DataCell(Text('-', style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey)));
    });

    return DataRow2(cells: [
      DataCell(Text(idStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744)))),
      DataCell(Text(_cleanHostelName(r['location_name'] ?? '', roomCode), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: isDark ? Colors.white : const Color(0xFF1A2744)))),
      DataCell(Text(roomCode, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey, fontFamily: 'Lato'))),
      DataCell(InkWell(
        onTap: () async {
          final roomTypeNames = _roomTypes.map((t) => t['name'].toString()).toList();
          final result = await _showSearchableSelectDialog(
            context: context,
            title: 'Room Type',
            items: roomTypeNames,
            currentSelected: dropdownVal,
            allowClear: true,
            clearLabel: 'Not Assigned',
            isDark: isDark,
          );
          if (result != null) {
            setState(() {
              final newType = result == '__CLEAR__' ? 'Not Assigned' : result;
              r['room_type']     = newType;
              r['room_capacity'] = _extractCapacity(newType);
            });
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: dropdownVal == null 
                ? Colors.orange.withValues(alpha: isDark ? 0.15 : 0.08) 
                : (isDark ? const Color(0xFF0F1520) : Colors.grey.shade50),
            border: Border.all(color: dropdownVal == null ? Colors.orange.shade300 : (isDark ? Colors.white24 : Colors.grey.shade300)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  dropdownVal ?? 'Not Assigned',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: dropdownVal == null ? FontWeight.bold : FontWeight.w500,
                    color: dropdownVal == null ? (isDark ? Colors.orangeAccent : Colors.orange.shade800) : (isDark ? Colors.white : Colors.black87),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.search_rounded, size: 16, color: isDark ? Colors.white60 : Colors.grey),
            ],
          ),
        ),
      )),
      DataCell(Text(totalBeds.toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87))),
      DataCell(Text(occupiedBeds.toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.lightBlueAccent : Colors.blue))),
      DataCell(Text(assignedPending.toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange))),
      DataCell(Text(availableBeds < 0 ? '0' : availableBeds.toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: availableBeds > 0 ? Colors.green : Colors.red))),
      ...bedCells,
      DataCell(Text(gender, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87))),
      DataCell(Text(amountStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)))),
      DataCell(IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        splashRadius: 20,
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: Colors.blue.withValues(alpha: isDark ? 0.2 : 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.edit, size: 18, color: Colors.blue),
        ),
        onPressed: () => _showAddRoomDialog(r),
      )),
      DataCell(ElevatedButton.icon(
        onPressed: () => _updateRoomTypeDirect(r, r['room_type'] ?? 'Not Assigned'),
        icon: Icon(Icons.save, size: 14, color: isDark ? const Color(0xFF1A2744) : Colors.white),
        label: Text(
          'Save',
          style: TextStyle(color: isDark ? const Color(0xFF1A2744) : Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          softWrap: false,
          maxLines: 1,
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(68, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      )),
    ]);
  }

  Widget _buildSidebar(bool isDark) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1520) : const Color(0xFF141E2E),
        border: Border(right: BorderSide(color: isDark ? Colors.white12 : Colors.transparent)),
      ),
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
}

// ── RoomEditDialog ──────────────────────────────────────────────────────────
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
    _buildCtrl   = TextEditingController(text: r?['building_code'] ?? '');
    _floorCtrl   = TextEditingController(text: r?['floor_no'] ?? '');
    _blockCtrl   = TextEditingController(text: r?['block_no'] ?? '');
    _roomCtrl    = TextEditingController(text: r?['room_no'] ?? '');
    _roomCodeCtrl= TextEditingController(text: r?['location_code'] ?? '');
    _capCtrl     = TextEditingController(text: r?['room_capacity']?.toString() ?? '');
    _selectedType= (r?['room_type'] == 'Not Assigned') ? null : r?['room_type'];
  }

  @override
  void dispose() {
    _locNameCtrl.dispose(); _buildCtrl.dispose(); _floorCtrl.dispose();
    _blockCtrl.dispose(); _roomCtrl.dispose(); _roomCodeCtrl.dispose(); _capCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    await ApiService.postRequest('rooms/save_room_master.php', {
      'id':           widget.room?['id'],
      'location_name':_locNameCtrl.text,
      'building_code':_buildCtrl.text,
      'floor_no':     _floorCtrl.text,
      'block_no':     _blockCtrl.text,
      'room_no':      _roomCtrl.text,
      'room_code':    _roomCodeCtrl.text,
      'room_type':    _selectedType ?? 'Not Assigned',
      'room_capacity':int.tryParse(_capCtrl.text) ?? 0,
    });
    widget.onSave();
    if (mounted) Navigator.pop(context);
  }

  int _extractCapacity(String name) {
    final upper = name.toUpperCase();
    final in1Match = RegExp(r'(\d+)\s*IN\s*1').firstMatch(upper);
    if (in1Match != null) return int.tryParse(in1Match.group(1) ?? '') ?? 0;
    if (upper.contains('DOUBLE')) return 2;
    if (upper.contains('SINGLE')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final bool isDark = wallpaper?.isDarkTheme ?? false;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDark ? BorderSide(color: Colors.white.withOpacity(0.14)) : BorderSide.none,
      ),
      backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
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
                Text('Edit Room Master', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A2744))),
                const SizedBox(height: 32),
                _field('Location Name', _locNameCtrl, isDark: isDark),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _field('Building', _buildCtrl, isDark: isDark)), 
                  const SizedBox(width: 16), 
                  Expanded(child: _field('Floor', _floorCtrl, isDark: isDark)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _field('Block', _blockCtrl, isDark: isDark)), 
                  const SizedBox(width: 16),
                  Expanded(child: _field('Room No', _roomCtrl, isDark: isDark)), 
                  const SizedBox(width: 16),
                  Expanded(child: _field('Room Code', _roomCodeCtrl, isDark: isDark)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedType,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        labelText: 'Room Type',
                        labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F1520) : Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
                      ),
                      hint: Text('Select Room Type', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
                      items: widget.roomTypes.map((t) => DropdownMenuItem(value: t['name'].toString(), child: Text(t['name'].toString(), style: TextStyle(color: isDark ? Colors.white : Colors.black87)))).toList(),
                      onChanged: (v) => setState(() { _selectedType = v; _capCtrl.text = _extractCapacity(v ?? '').toString(); }),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _field('Capacity', _capCtrl, isNum: true, isDark: isDark)),
                ]),
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context), 
                      child: Text('Cancel', style: TextStyle(color: isDark ? const Color(0xFFD4AF37) : Colors.grey.shade700)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744), 
                        foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('Save Record', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _field(String label, TextEditingController ctrl, {bool isNum = false, bool isDark = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? Colors.white70 : Colors.grey)),
        const SizedBox(height: 8),
        TextFormField(
          controller: ctrl, 
          keyboardType: isNum ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? const Color(0xFF0F1520) : Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}
