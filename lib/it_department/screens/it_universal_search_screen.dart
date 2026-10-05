import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/main_layout.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../widgets/assign_biometric_dialog.dart';
import 'it_biometric_history_screen.dart';

class ItUniversalSearchScreen extends StatefulWidget {
  const ItUniversalSearchScreen({super.key});

  @override
  State<ItUniversalSearchScreen> createState() => _ItUniversalSearchScreenState();
}

class _ItUniversalSearchScreenState extends State<ItUniversalSearchScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  String _statusFilter = 'all'; // all, synced, not_synced
  String _selectedHostel = 'All';
  List<String> _availableHostels = ['All'];

  List<Map<String, dynamic>> _students = [];
  bool _isLoading = false;
  int _page = 1;
  int _totalPages = 1;
  int _totalRecords = 0;

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _page = 1;
      });
      _fetchStudents();
    });
  }

  Future<void> _fetchStudents({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }

    try {
      final res = await ApiService.searchStudentsIt(
        query: _searchController.text.trim(),
        status: _statusFilter,
        hostel: _selectedHostel,
        page: _page,
        limit: 25,
      );

      if (mounted) {
        if (res['success'] == true) {
          final data = (res['data'] as List?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
          final pagination = res['pagination'] as Map<String, dynamic>? ?? {};
          final hostels = (res['hostels'] as List?)?.map((e) => e.toString()).toList() ?? [];

          setState(() {
            _students = data;
            _totalPages = (pagination['total_pages'] as num?)?.toInt() ?? 1;
            _totalRecords = (pagination['total'] as num?)?.toInt() ?? 0;
            if (hostels.isNotEmpty) {
              _availableHostels = ['All', ...hostels];
            }
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _liveCheckStudent(Map<String, dynamic> student) {
    final regNo = student['register_no']?.toString() ?? '';
    if (regNo.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ItBiometricHistoryScreen(
          student: student,
          onDataUpdated: () => _fetchStudents(showLoading: false),
        ),
      ),
    );
  }

  Color _getHostelColor(String hostel) {
    final h = hostel.toLowerCase();
    if (h.contains('vaigai')) return const Color(0xFF2563EB); // Royal Blue
    if (h.contains('krishna')) return const Color(0xFF8B5CF6); // Purple
    if (h.contains('siruvani')) return const Color(0xFF0D9488); // Teal
    if (h.contains('ponni')) return const Color(0xFFF43F5E); // Rose
    if (h.contains('kaveri')) return const Color(0xFFD97706); // Amber
    if (h.contains('palar')) return const Color(0xFF059669); // Emerald
    if (h.contains('noyyal')) return const Color(0xFF6366F1); // Indigo
    if (h.contains('porunai')) return const Color(0xFFBE123C); // Crimson
    if (h.contains('radiance')) return const Color(0xFFB45309); // Bronze
    if (h.contains('stunner')) return const Color(0xFF475569); // Slate
    return const Color(0xFF64748B);
  }


  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return 'ST';
    if (parts.length == 1) return parts[0].substring(0, parts[0].length.clamp(1, 2)).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  void _showStudentDetails(Map<String, dynamic> student) {
    final isDark = context.read<WallpaperProvider>().isDarkTheme;
    final isSynced = student['is_synced'] == true;
    final fullName = student['full_name']?.toString() ?? 'Student';
    final regNo = student['register_no']?.toString() ?? 'N/A';
    final hostel = student['hostel_name']?.toString() ?? 'N/A';
    final room = student['room_allocation']?.toString() ?? 'N/A';
    final bioId = student['biometric_id']?.toString() ?? '';
    final lastChecked = student['last_checked_at']?.toString() ?? 'Not checked yet';
    final lastAttendance = student['last_attendance_date']?.toString() ?? 'No logs';
    final recordsFound = student['records_found'] ?? 0;
    final notes = student['notes']?.toString() ?? '';
    final hostelColor = _getHostelColor(hostel);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131D2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 25, offset: Offset(0, -6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rich Royal Navy Blue Header Banner (Image 5 style)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A2744),
                    Color(0xFF2A3A5C),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFD4AF37), width: 1.2),
                ),
              ),
              child: Column(
                children: [
                  // Top Drag Handle & Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 24),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Student Profile in Blue Header (Gold Avatar + Name + ID)
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFE5C058), Color(0xFFD4AF37), Color(0xFFB8860B)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD4AF37).withOpacity(0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _getInitials(fullName),
                          style: const TextStyle(
                            fontFamily: 'Lato',
                            color: Color(0xFF1B2B48),
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontFamily: 'Lato',
                                fontSize: 17.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'ID: $regNo',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFD4AF37),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Status Badge (Registered / Not Registered)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isSynced
                                ? [const Color(0xFF4ADE80), const Color(0xFF16A34A)]
                                : [const Color(0xFFFBBF24), const Color(0xFFD97706)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: (isSynced ? const Color(0xFF16A34A) : const Color(0xFFD97706)).withOpacity(0.35),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          isSynced ? 'REGISTERED' : 'NOT REGISTERED',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Modal Body Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Hostel & Room', '$hostel • $room', isDark, accentColor: hostelColor),
                  _buildDetailRow('Biometric Machine ID', bioId.isNotEmpty ? bioId : 'Not Assigned', isDark),
                  _buildDetailRow('Attendance Records Found', '$recordsFound punch record(s)', isDark, isBold: isSynced),
                  _buildDetailRow('Latest Attendance Date', lastAttendance, isDark),
                  _buildDetailRow('Last Audit Timestamp', lastChecked, isDark),
                  if (notes.isNotEmpty) _buildDetailRow('API / Audit Notes', notes, isDark),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _liveCheckStudent(student);
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Live API Check'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFD4AF37),
                            side: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            showDialog(
                              context: context,
                              builder: (context) => AssignBiometricDialog(
                                registerNo: regNo,
                                fullName: fullName,
                                hostelName: hostel,
                                roomAllocation: room,
                                currentBiometricId: bioId,
                                onAssigned: () => _fetchStudents(showLoading: false),
                              ),
                            );
                          },
                          icon: const Icon(Icons.fingerprint_rounded, size: 16),
                          label: Text(isSynced ? 'Update ID' : 'Assign ID'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {Color? accentColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: accentColor ?? (isDark ? Colors.white : const Color(0xFF1B2B48)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = context.watch<WallpaperProvider>().isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Universal Biometric Search',
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        titleColor: const Color(0xFFD4AF37),
        borderColor: const Color(0xFFD4AF37).withOpacity(0.5),
        onHomeTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(0),
        rightAction: ProfileButton(
          onTap: () => context.findAncestorStateOfType<MainResponsiveLayoutState>()?.setSelectedIndex(3),
        ),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            // Top Search & Colorful Filter Bar
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
                        color: isDark ? Colors.white12 : const Color(0xFFD4AF37).withOpacity(0.4),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
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
                        hintText: 'Search by Reg No, Name, Room...',
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
                  const SizedBox(height: 12),

                  // Filter Chips & Hostel Selector (Gold used for Not Registered instead of Red)
                  Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildFilterChip('All', 'all', const Color(0xFF3B82F6), isDark),
                              const SizedBox(width: 6),
                              _buildFilterChip('Registered', 'synced', const Color(0xFF10B981), isDark),
                              const SizedBox(width: 6),
                              _buildFilterChip('Not Registered', 'not_synced', const Color(0xFFD4AF37), isDark),
                            ],
                          ),
                        ),
                      ),
                      // Hostel Dropdown
                      if (_availableHostels.length > 1) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.grey.shade300,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedHostel,
                              isDense: true,
                              icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFD4AF37), size: 20),
                              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                              ),
                              items: _availableHostels.map((h) {
                                return DropdownMenuItem<String>(
                                  value: h,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (h != 'All') ...[
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: _getHostelColor(h),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(h.length > 10 ? '${h.substring(0, 9)}..' : h),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedHostel = val;
                                    _page = 1;
                                  });
                                  _fetchStudents();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Results Counter & Pagination
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$_totalRecords Students',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_totalPages > 1)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: _page > 1 ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                          onPressed: _page > 1
                              ? () {
                                  setState(() => _page--);
                                  _fetchStudents();
                                }
                              : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '$_page / $_totalPages',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white60 : Colors.grey.shade600,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          color: _page < _totalPages ? const Color(0xFFD4AF37) : Colors.grey.shade400,
                          onPressed: _page < _totalPages
                              ? () {
                                  setState(() => _page++);
                                  _fetchStudents();
                                }
                              : null,
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Student Cards List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                      ),
                    )
                  : _students.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_search_rounded,
                                size: 52,
                                color: isDark ? Colors.white24 : Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No matching student records found',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white60 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _fetchStudents(showLoading: false),
                          color: const Color(0xFFD4AF37),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 80),
                            itemCount: _students.length,
                            itemBuilder: (context, index) {
                              return _buildStudentCard(_students[index], isDark);
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
        _fetchStudents();
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.3),
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

  Widget _buildStudentCard(Map<String, dynamic> student, bool isDark) {
    final isSynced = student['is_synced'] == true;
    final fullName = student['full_name']?.toString() ?? 'Student';
    final regNo = student['register_no']?.toString() ?? 'N/A';
    final hostel = student['hostel_name']?.toString() ?? 'N/A';
    final room = student['room_allocation']?.toString() ?? 'N/A';
    final recordsFound = student['records_found'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showStudentDetails(student),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Gold Circle Avatar with dark initials (Image 2 style)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFE5C058), Color(0xFFD4AF37), Color(0xFFB8860B)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getInitials(fullName),
                    style: const TextStyle(
                      fontFamily: 'Lato',
                      color: Color(0xFF1B2B48),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Student details (Title, Room, Subtitle note)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Room $room • $hostel',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white70 : Colors.grey.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '"ID: $regNo"',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 11.5,
                          color: isDark ? const Color(0xFFD4AF37) : const Color(0xFFB8860B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Right Side: 3D Skeuomorphic Pill Badge + Chevron (Image 2 style)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isSynced
                                  ? [const Color(0xFF4ADE80), const Color(0xFF16A34A)]
                                  : [const Color(0xFFFBBF24), const Color(0xFFD97706)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: (isSynced ? const Color(0xFF16A34A) : const Color(0xFFD97706)).withOpacity(0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            isSynced ? 'Registered' : 'Not Registered',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isSynced
                              ? (recordsFound > 0 ? '$recordsFound punch logs' : 'Active')
                              : 'Pending',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark ? Colors.white38 : Colors.grey.shade400,
                      size: 20,
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
}
