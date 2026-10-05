import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;

class EBRoomSearchScreen extends StatefulWidget {
  const EBRoomSearchScreen({super.key});

  @override
  State<EBRoomSearchScreen> createState() => _EBRoomSearchScreenState();
}

class _EBRoomSearchScreenState extends State<EBRoomSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  final ScrollController _scrollController = ScrollController();
  int _monthOffset = 0; // -1: Previous Month, 0: Current Month, 1: Next Month
  String _statusFilter = 'all'; // all, verified, not_verified
  DateTime? _fromDate;
  DateTime? _toDate;
  String _selectedHostel = 'All';
  List<String> _availableHostels = ['All'];
  String _selectedFloor = 'All';
  List<String> _availableFloors = ['All'];

  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  int _totalRecords = 0;
  int _verifiedCount = 0;
  int _notVerifiedCount = 0;

  DateTime get _currentSelectedMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset, 1);
  }

  void _changeMonth(int delta) {
    final newOffset = _monthOffset + delta;
    if (newOffset < -1 || newOffset > 1) return;
    final now = DateTime.now();
    final targetMonth = DateTime(now.year, now.month + newOffset, 1);
    setState(() {
      _monthOffset = newOffset;
      _fromDate = DateTime(targetMonth.year, targetMonth.month, 1);
      _toDate = DateTime(targetMonth.year, targetMonth.month + 1, 0);
      _page = 1;
    });
    _fetchRooms();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Default to the current 1-month billing cycle (1st to last day of this month)
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = DateTime(now.year, now.month + 1, 0);
    _scrollController.addListener(_onScroll);
    _fetchRooms();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 250) {
      if (!_isLoading && !_isLoadingMore && _page < _totalPages) {
        _loadMoreRooms();
      }
    }
  }

  Future<void> _loadMoreRooms() async {
    if (_isLoadingMore || _page >= _totalPages) return;
    setState(() => _isLoadingMore = true);
    try {
      final user = context.read<UserProvider>();
      final nextPage = _page + 1;
      final res = await ApiService.getRoomsVerificationStatus(
        query: _searchController.text.trim(),
        status: _statusFilter,
        hostel: _selectedHostel,
        floor: _selectedFloor,
        staffUsername: user.username,
        role: user.roleName,
        fromDate: _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : null,
        toDate: _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : null,
        page: nextPage,
        limit: 25,
      );

      if (mounted && res['status'] == 'success') {
        final data = List<Map<String, dynamic>>.from(res['data'] ?? []);
        final pagination = res['pagination'] ?? {};
        setState(() {
          _page = nextPage;
          _rooms.addAll(data);
          _totalPages = pagination['total_pages'] ?? _totalPages;
          _isLoadingMore = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingMore = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      setState(() {
        _page = 1;
      });
      _fetchRooms();
    });
  }

  Future<void> _fetchRooms({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final user = context.read<UserProvider>();
      final res = await ApiService.getRoomsVerificationStatus(
        query: _searchController.text.trim(),
        status: _statusFilter,
        hostel: _selectedHostel,
        floor: _selectedFloor,
        staffUsername: user.username,
        role: user.roleName,
        fromDate: _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : null,
        toDate: _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : null,
        page: _page,
        limit: 25,
      );

      if (mounted) {
        if (res['status'] == 'success') {
          final data = List<Map<String, dynamic>>.from(res['data'] ?? []);
          final pagination = res['pagination'] ?? {};

          final rawHostels = List<String>.from(res['hostels'] ?? []);
          final rawFloors = List<String>.from(res['floors'] ?? []);

          final updatedHostels = ['All', ...rawHostels];
          final updatedFloors = ['All', ...rawFloors];

          setState(() {
            _rooms = data;
            _availableHostels = updatedHostels;
            _availableFloors = updatedFloors;

            if (!_availableHostels.contains(_selectedHostel)) {
              _selectedHostel = 'All';
            }
            if (!_availableFloors.contains(_selectedFloor)) {
              _selectedFloor = 'All';
            }

            _totalPages = pagination['total_pages'] ?? 1;
            _totalRecords = pagination['total'] ?? 0;
            _verifiedCount = pagination['verified_count'] ?? 0;
            _notVerifiedCount = pagination['not_verified_count'] ?? 0;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showEnterUnitsDialog(Map<String, dynamic> room) {
    final roomNo = room['room_number']?.toString() ?? '';
    final hostelName = room['hostel_name']?.toString() ?? '';
    final floorName = room['floor_name']?.toString() ?? '';
    final currentVal = room['current_reading']?.toString() ?? '';

    final unitsController = TextEditingController(text: currentVal);
    bool isSubmitting = false;
    String? errorText;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final isDark = context.read<WallpaperProvider>().isDarkTheme;
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.electric_meter_rounded, color: Color(0xFFD4AF37), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Enter Meter Units',
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomNo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$hostelName • $floorName',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: unitsController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1B2B48),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Units (kWh) *',
                      hintText: 'e.g. 145.50',
                      errorText: errorText,
                      prefixIcon: const Icon(Icons.bolt, color: Color(0xFFD4AF37), size: 20),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF0F172A) : Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.8),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF1B2B48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final text = unitsController.text.trim();
                          final units = double.tryParse(text);
                          if (units == null || units < 0) {
                            setDialogState(() {
                              errorText = 'Please enter a valid unit reading';
                            });
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            errorText = null;
                          });

                          final user = context.read<UserProvider>();
                          final payload = {
                            'hostel_name': hostelName,
                            'floor_no': floorName,
                            'room_no': roomNo,
                            'meter_no': '',
                            'previous_reading': 0.0,
                            'current_reading': units,
                            'volts': 230.0,
                            'watts': 0.0,
                            'recorded_by': user.username.isNotEmpty ? user.username : 'maintenance',
                            'inspector_name': user.userName.isNotEmpty ? user.userName : 'Maintenance Staff',
                          };
                          final nav = Navigator.of(ctx);
                          final messenger = ScaffoldMessenger.of(context);
                          final res = await ApiService.submitEBMeterReading(payload);
                          if (mounted) {
                            if (res['status'] == 'success') {
                              nav.pop();
                              // Update room locally so it turns GREEN immediately with units!
                              setState(() {
                                final wasNotVerified = room['is_verified'] != 1;
                                room['is_verified'] = 1;
                                room['current_reading'] = units;
                                room['units_consumed'] = units;
                                if (wasNotVerified) {
                                  _verifiedCount++;
                                  if (_notVerifiedCount > 0) _notVerifiedCount--;
                                }
                              });
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Row(
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text('$roomNo updated with $units kWh!'),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: const Color(0xFF10B981),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              );
                            } else {
                              setDialogState(() {
                                isSubmitting = false;
                                errorText = res['message'] ?? 'Failed to submit reading';
                              });
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B2B48)),
                        )
                      : const Text('Enter', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _getRoomInitials(String roomNo) {
    if (roomNo.isEmpty) return 'R';
    // If format like T12-F00-WA1-R01 -> extract R01 or last segment
    if (roomNo.contains('-')) {
      final parts = roomNo.split('-');
      final last = parts.last.trim();
      return last.length > 3 ? last.substring(last.length - 3) : last;
    }
    return roomNo.length > 3 ? roomNo.substring(roomNo.length - 3) : roomNo;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<WallpaperProvider>().isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Universal Room Search',
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        titleColor: const Color(0xFFD4AF37),
        borderColor: const Color(0xFFD4AF37).withValues(alpha: 0.5),
        onBack: () => Navigator.pop(context),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            // Top Search Box, Month Navigation & Filter Chips
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                children: [
                  // Search Box
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white12 : const Color(0xFFD4AF37).withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1B2B48),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search by Room Number...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Color(0xFFD4AF37),
                          size: 22,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.grey),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Month Navigation Selector
                  _buildMonthSelector(isDark),
                  const SizedBox(height: 10),

                  // Filter Chips (All, Verified, Not Verified)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFilterChip('All', 'all', const Color(0xFF3B82F6), isDark),
                        const SizedBox(width: 8),
                        _buildFilterChip('Verified', 'verified', const Color(0xFF10B981), isDark),
                        const SizedBox(width: 8),
                        _buildFilterChip('Not Verified', 'not_verified', const Color(0xFFD4AF37), isDark),
                      ],
                    ),
                  ),

                  // Hostel & Floor Selectors
                  if (_availableHostels.length > 1 || _availableFloors.length > 1) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        // Hostel Dropdown
                        if (_availableHostels.length > 1)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.apartment_rounded, color: Color(0xFFD4AF37), size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _availableHostels.contains(_selectedHostel) ? _selectedHostel : 'All',
                                        isDense: true,
                                        isExpanded: true,
                                        icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFD4AF37), size: 20),
                                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                        ),
                                        items: _availableHostels.map((hostel) {
                                          return DropdownMenuItem<String>(
                                            value: hostel,
                                            child: Text(
                                              hostel == 'All' ? 'All Hostels' : hostel,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              _selectedHostel = val;
                                              _selectedFloor = 'All';
                                              _page = 1;
                                            });
                                            _fetchRooms();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (_availableHostels.length > 1 && _availableFloors.length > 1)
                          const SizedBox(width: 8),
                        // Floor Dropdown
                        if (_availableFloors.length > 1)
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.layers_rounded, color: Color(0xFFD4AF37), size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _availableFloors.contains(_selectedFloor) ? _selectedFloor : 'All',
                                        isDense: true,
                                        isExpanded: true,
                                        icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFD4AF37), size: 20),
                                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                        ),
                                        items: _availableFloors.map((floor) {
                                          return DropdownMenuItem<String>(
                                            value: floor,
                                            child: Text(
                                              floor == 'All' ? 'All Floors' : floor,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              _selectedFloor = val;
                                              _page = 1;
                                            });
                                            _fetchRooms();
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Results Counter Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '$_totalRecords Rooms',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '($_verifiedCount Verified • $_notVerifiedCount Not Verified)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Room Cards List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                      ),
                    )
                  : _rooms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.meeting_room_outlined,
                                size: 52,
                                color: isDark ? Colors.white24 : Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No matching room records found',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            _page = 1;
                            await _fetchRooms(showLoading: false);
                          },
                          color: const Color(0xFFD4AF37),
                          child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                            itemCount: _rooms.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _rooms.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return _buildRoomCard(_rooms[index], isDark);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Color activeColor, bool isDark) {
    final isSelected = (_statusFilter == value);
    return InkWell(
      onTap: () {
        setState(() {
          _statusFilter = value;
          _page = 1;
        });
        _fetchRooms();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    final selectedMonth = _currentSelectedMonth;
    final monthName = DateFormat('MMMM yyyy').format(selectedMonth);

    final canGoPrev = _monthOffset > -1;
    final canGoNext = _monthOffset < 1;

    String badgeText;
    Color badgeBg;
    Color badgeTextColor;
    if (_monthOffset == 0) {
      badgeText = 'CURRENT';
      badgeBg = const Color(0xFFD1FAE5);
      badgeTextColor = const Color(0xFF047857);
    } else if (_monthOffset == -1) {
      badgeText = 'PREVIOUS';
      badgeBg = const Color(0xFFFEF3C7);
      badgeTextColor = const Color(0xFFB45309);
    } else {
      badgeText = 'NEXT';
      badgeBg = const Color(0xFFDBEAFE);
      badgeTextColor = const Color(0xFF1D4ED8);
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFD4AF37).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 26),
            color: canGoPrev ? const Color(0xFFD4AF37) : (isDark ? Colors.white24 : Colors.grey.shade300),
            onPressed: canGoPrev ? () => _changeMonth(-1) : null,
            tooltip: 'Previous Month',
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFFBF8EE),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_month_rounded,
                  color: Color(0xFFD4AF37),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  monthName,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: badgeTextColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: badgeTextColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 26),
            color: canGoNext ? const Color(0xFFD4AF37) : (isDark ? Colors.white24 : Colors.grey.shade300),
            onPressed: canGoNext ? () => _changeMonth(1) : null,
            tooltip: 'Next Month',
          ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room, bool isDark) {
    final isVerified = room['is_verified'] == 1 || room['is_verified'] == true;
    final roomNumber = room['room_number']?.toString() ?? 'N/A';
    final hostel = room['hostel_name']?.toString() ?? 'Hostel';
    final floor = room['floor_name']?.toString() ?? 'Floor';
    final currentReading = room['current_reading'];

    // Total log/card turns green when verified with units!
    final cardBgColor = isVerified
        ? (isDark ? const Color(0xFF0F2E22) : const Color(0xFFF0FDF4))
        : (isDark ? const Color(0xFF162032) : Colors.white);

    final cardBorderColor = isVerified
        ? const Color(0xFF10B981)
        : (isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardBorderColor,
          width: isVerified ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isVerified
                ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.1)
                : Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
            blurRadius: isVerified ? 10 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            // Circle Avatar (Emerald if verified, Gold if pending)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isVerified
                      ? const [Color(0xFF34D399), Color(0xFF10B981), Color(0xFF059669)]
                      : const [Color(0xFFE5C058), Color(0xFFD4AF37), Color(0xFFB8860B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isVerified ? const Color(0xFF10B981) : const Color(0xFFD4AF37)).withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                _getRoomInitials(roomNumber),
                style: TextStyle(
                  fontFamily: 'Lato',
                  color: isVerified ? Colors.white : const Color(0xFF1B2B48),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Center Info: Full Room Code (no 'Room ' prefix) and Hostel/Floor
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    roomNumber, // Full room code cleanly displayed without "Room " prefix
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: isVerified
                          ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46))
                          : (isDark ? Colors.white : const Color(0xFF1B2B48)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$hostel • $floor',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white60 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isVerified
                        ? (currentReading != null ? 'Reading: $currentReading kWh' : 'Verified')
                        : 'Pending meter check',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w600,
                      color: isVerified
                          ? const Color(0xFF10B981)
                          : const Color(0xFFD4AF37),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Right: Text box style input container to enter/edit units
            GestureDetector(
              onTap: () => _showEnterUnitsDialog(room),
              child: Container(
                constraints: const BoxConstraints(minWidth: 88),
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isVerified
                      ? (isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5))
                      : (isDark ? const Color(0xFF0F172A) : Colors.grey.shade50),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isVerified
                        ? const Color(0xFF10B981)
                        : (isDark ? Colors.white24 : Colors.grey.shade400),
                    width: 1.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isVerified ? Icons.bolt_rounded : Icons.edit_note_rounded,
                      size: 16,
                      color: isVerified
                          ? const Color(0xFF10B981)
                          : (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isVerified
                          ? '$currentReading kWh'
                          : 'Enter Units',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: isVerified
                            ? (isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46))
                            : (isDark ? Colors.white70 : Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
