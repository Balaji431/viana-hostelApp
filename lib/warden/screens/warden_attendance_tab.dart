import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_widgets.dart';
import 'warden_biometric_screen.dart';

class WardenAttendanceTab extends StatefulWidget {
  const WardenAttendanceTab({super.key});

  @override
  State<WardenAttendanceTab> createState() => _WardenAttendanceTabState();
}

class _WardenAttendanceTabState extends State<WardenAttendanceTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _searchQuery = '';
  DateTime _selectedMonth = DateTime.now();
  final Set<int> _selectedDays = {DateTime.now().day}; // Default select today
  final String _statusFilter = 'All';
  List<Map<String, dynamic>> _attendanceLogs = [];
  bool _isLoadingLogs = false;
  List<Map<String, dynamic>> _allStudents = [];
  Map<int, double> _monthlyDailyData = {};
  double _averageAttendance = 0;

  @override
  void initState() {
    super.initState();
    _fetchAllData();
  }

  Future<void> _fetchAllData() async {
    if (mounted) setState(() => _isLoadingLogs = true);
    final user = context.read<UserProvider>();
    final response = await ApiService.getStudents(wardenUsername: user.username);
    if (response['status'] == 'success') {
      _allStudents = List<Map<String, dynamic>>.from(response['data']).map((s) {
        return {
          ...s,
          'id': s['register_number'] ?? s['id'], // Standardize to reg_no
        };
      }).toList();
    }
    _fetchMonthlySummary();
    _fetchLogs();
  }

  Future<void> _fetchMonthlySummary() async {
    final user = context.read<UserProvider>();
    final monthStr = DateFormat('yyyy-MM').format(_selectedMonth);
    final response = await ApiService.getMonthlyAttendanceSummary(monthStr, wardenUsername: user.username);
    if (response['status'] == 'success') {
      if (mounted) {
        setState(() {
          _averageAttendance = (response['average_attendance'] ?? 0).toDouble();
          _monthlyDailyData = {};
          if (response['daily_data'] != null) {
            Map<String, dynamic> daily = Map<String, dynamic>.from(response['daily_data']);
            daily.forEach((key, value) {
              _monthlyDailyData[int.parse(key)] = (value ?? 0).toDouble();
            });
          }
        });
      }
    }
  }


  Future<void> _fetchLogs() async {
    if (_selectedDays.isEmpty) return;

    setState(() => _isLoadingLogs = true);

    try {
      final user = context.read<UserProvider>();
      String dateStr = DateFormat('yyyy-MM-dd').format(
        DateTime(_selectedMonth.year, _selectedMonth.month, _selectedDays.last),
      );

      final response = await ApiService.getAllAttendanceLogs(date: dateStr, wardenUsername: user.username);

      // ✅ SAFE CHECK
      if (response['status'] != 'success' || response['data'] == null) {
        setState(() {
          _attendanceLogs = [];
          _isLoadingLogs = false;
        });
        return;
      }

      List<Map<String, dynamic>> logs =
          List<Map<String, dynamic>>.from(response['data']);

      List<Map<String, dynamic>> merged = _allStudents.map((s) {
        final log = logs.cast<Map<String, dynamic>>().firstWhere(
          (l) => l['student_id'].toString() == s['id'].toString(),
          orElse: () => <String, dynamic>{},
        );

        return {
          ...s,
          'name': s['full_name'] ?? 'Unknown',
          'status': log.isEmpty ? 'Not Marked' : log['status'] ?? 'Not Marked',
          'created_at': log['created_at'],
          'student_id': s['register_number'] ?? s['id'],
          'room_no': s['room_allocation'] ?? s['room_no'],
          'RegisterNumber': s['register_number'] ?? s['id'],
        };
      }).toList();

      if (mounted) {
        setState(() {
          _attendanceLogs = merged;
          _isLoadingLogs = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _attendanceLogs = [];
          _isLoadingLogs = false;
        });
      }
      print("FETCH LOG ERROR: $e");
    }
  }

  Color _getHeatmapColor(double percentage, bool isFuture) {
    if (percentage <= 0) return const Color(0xffc62828); // Red for 0%
    if (percentage >= 100) return const Color(0xff2e7d32); // Deep green for 100%
    
    // Gradient between red and green
    if (percentage < 50) {
      return Colors.red.withOpacity(0.8);
    } else if (percentage < 80) {
      return Colors.orange.withOpacity(0.8);
    } else {
      return const Color(0xff2e7d32).withOpacity(0.8);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<UserProvider>();
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;
    final showInternalAppBar = (user.role == UserRole.warden || user.role == UserRole.admin);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: showInternalAppBar 
          ? const SkeuomorphicNavBar(
              title: 'Attendance',
            )
          : null,
      body: LinenBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildMonthSelector(isDark),
                  _buildHeatmapCard(isDark),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: _buildMarkAttendanceButton(isDark),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SearchHeaderDelegate(
                child: _buildSearchAndStatsHeader(isDark),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildDailyStatsSection(isDark),
            ),
            _buildStudentListSliver(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkAttendanceButton(bool isDark) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SkeuomorphicButton(
              onTap: () => _showManualAttendanceModal(context),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFF1B2B48), const Color(0xFF101B2E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    'Manual',
                    style: SkeuomorphicStyles.playfairHeader.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SkeuomorphicButton(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const WardenBiometricScreen(showBackButton: true),
                  ),
                );
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFF1B2B48), const Color(0xFF101B2E)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fingerprint_rounded, color: Color(0xFFD4AF37), size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Biometric',
                      style: SkeuomorphicStyles.playfairHeader.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : null,
        gradient: isDark ? null : SkeuomorphicColors.royalContentGradient,
        border: isDark ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.08))) : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMonthNavButton(Icons.chevron_left, () {
                setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1));
                _fetchMonthlySummary();
                _fetchLogs();
              }),
              Column(
                children: [
                  Text(DateFormat('MMMM').format(_selectedMonth), style: SkeuomorphicStyles.playfairHeader.copyWith(color: Colors.white, fontSize: 18)),
                  Text('${_selectedMonth.year}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              _buildMonthNavButton(Icons.chevron_right, () {
                setState(() => _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1));
                _fetchMonthlySummary();
                _fetchLogs();
              }),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3)),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (_averageAttendance / 100).clamp(0.0, 1.0),
                    child: Container(decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF81C784)]),
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 4)]
                    )),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Text('${_averageAttendance.toInt()}%', style: SkeuomorphicStyles.playfairHeader.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNavButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(color: Colors.white12, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildHeatmapCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
            blurRadius: isDark ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Text(
              d,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
            )).toList(),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: 31 + DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday % 7,
            itemBuilder: (context, index) {
              final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1).weekday % 7;
              if (index < firstDay) return const SizedBox();
              final day = index - firstDay + 1;
              if (day > 31) return const SizedBox();
              DateTime now = DateTime.now();
              bool isFuture = (day > now.day && _selectedMonth.month == now.month && _selectedMonth.year == now.year) || (_selectedMonth.year > now.year) || (_selectedMonth.year == now.year && _selectedMonth.month > now.month);
              bool isToday = day == now.day && _selectedMonth.month == now.month && _selectedMonth.year == now.year;
              bool isSelected = _selectedDays.contains(day);
              double attendancePerc = _monthlyDailyData[day] ?? 0.0;
              return GestureDetector(
                onTap: (isFuture && !_monthlyDailyData.containsKey(day)) ? null : () {
                  setState(() {
                    if (_selectedDays.contains(day)) {
                      if (_selectedDays.length > 1) {
                        _selectedDays.remove(day);
                      }
                    } else {
                      _selectedDays.add(day);
                    }
                  });
                  _fetchLogs();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _monthlyDailyData.containsKey(day) 
                        ? _getHeatmapColor(attendancePerc, isFuture) 
                        : (isDark ? Colors.white12 : const Color(0xFFE8E0D5)),
                    borderRadius: BorderRadius.circular(4),
                    border: isSelected ? Border.all(color: const Color(0xFFD4AF37), width: 2) : (isToday ? Border.all(color: Colors.white, width: 2) : null),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$day', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                      if (!isFuture && _monthlyDailyData.containsKey(day)) 
                        Text('${attendancePerc.toInt()}%', style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Low', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(
                  'Tap dates to view • Multi-select supported', 
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Text('High', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndStatsHeader(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF0F172A).withOpacity(0.95) : const Color(0xFFFDFBF7),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedDays.isNotEmpty && !_isLoadingLogs) ...[
            _buildDailyStats(_attendanceLogs, isDark),
            const SizedBox(height: 10),
            TextField(
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'Search students...',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                prefixIcon: Icon(Icons.search, color: isDark ? Colors.white60 : Colors.grey, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_getFilteredLogs().length} Records',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFD4AF37) : Colors.blueGrey,
                    fontSize: 13,
                  ),
                ),
                Text(
                  DateFormat('dd MMM yyyy').format(DateTime(_selectedMonth.year, _selectedMonth.month, _selectedDays.last)),
                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyStatsSection(bool isDark) {
    if (_selectedDays.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Icon(Icons.calendar_month, size: 64, color: isDark ? Colors.white38 : Colors.grey),
            const SizedBox(height: 15),
            Text(
              'Tap dates on the calendar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.grey,
              ),
            ),
            Text(
              'Select a date to view detailed attendance logs',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
            ),
          ],
        ),
      );
    }
    
    if (_isLoadingLogs) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(
            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildStudentListSliver(bool isDark) {
    if (_selectedDays.isEmpty || _isLoadingLogs) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final filteredLogs = _getFilteredLogs();
    
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.builder(
        itemCount: filteredLogs.length,
        itemBuilder: (context, index) {
          return _buildStudentCard(filteredLogs[index], isDark);
        },
      ),
    );
  }

  Widget _buildDailyStats(List<Map<String, dynamic>> logs, bool isDark) {
    int present = 0;
    int absent = 0;
    int half = 0;
    int notMarked = 0;

    for (var log in logs) {
      String status = log['status']?.toString().toLowerCase() ?? 'not marked';
      if (status == 'present' || status == 'in') {
        present++;
      } else if (status == 'absent' || status == 'out') {
        absent++;
      } else if (status == 'halfday' || status == 'half') {
        half++;
      } else {
        notMarked++;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('Present', present, Colors.green, isDark),
          _buildStatColumn('Absent', absent, Colors.red, isDark),
          _buildStatColumn('Half Day', half, Colors.orange, isDark),
          _buildStatColumn('Not Marked', notMarked, isDark ? Colors.white60 : Colors.grey, isDark),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, int value, Color color, bool isDark) {
    return Column(
      children: [
        Text(value.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white60 : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _getFilteredLogs() {
    return _attendanceLogs.where((log) {
      final query = _searchQuery.toLowerCase();
      final nameMatch = log['name'].toString().toLowerCase().contains(query);
      final roomMatch = (log['room_no'] ?? '').toString().toLowerCase().contains(query);
      final regMatch = (log['RegisterNumber'] ?? '').toString().toLowerCase().contains(query);
      
      final matchesSearch = nameMatch || roomMatch || regMatch;
      
      if (_statusFilter != 'All') {
        return matchesSearch && log['status'].toString().toLowerCase() == _statusFilter.toLowerCase();
      }
      return matchesSearch;
    }).toList();
  }

  Widget _buildStudentCard(Map<String, dynamic> log, bool isDark) {
    String name = log['name'] ?? 'Unknown';
    String initials = name.isNotEmpty ? name.trim().split(' ').where((s) => s.isNotEmpty).map((l) => l[0]).take(2).join().toUpperCase() : "?";
    String status = log['status'] ?? 'Not Marked';
    String timeStr = log['created_at'] != null ? DateFormat('hh:mm a').format(DateTime.parse(log['created_at'])) : "";
    
    return GestureDetector(
      onTap: null, // Disabled navigation to student details
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: _getAvatarGradient(status),
                color: status == 'Not Marked' ? (isDark ? Colors.white24 : Colors.grey.shade400) : null,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: SkeuomorphicStyles.playfairHeader.copyWith(
                      fontSize: 14,
                      color: isDark ? Colors.white : const Color(0xFF1B2B48),
                    ),
                  ),
                  Text(
                    'Room: ${log['room_no'] ?? "N/A"} • ID: ${log['RegisterNumber'] ?? 'N/A'}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.grey),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildStatusBadge(status),
                const SizedBox(height: 5),
                if (status != 'Not Marked' && timeStr.isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        status.toLowerCase() == 'present' || status.toLowerCase() == 'in' ? Icons.check_circle : (status.toLowerCase() == 'half day' ? Icons.timelapse : Icons.cancel), 
                        size: 10, 
                        color: _getFilterColor(status)
                      ),
                      const SizedBox(width: 4),
                      Text(timeStr, style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    status = status.toLowerCase();
    Gradient? gradient = _getAvatarGradient(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.grey.shade600 : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(status.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Color _getFilterColor(String filter) {
    switch (filter) {
      case 'Present': return Colors.green;
      case 'Absent': return Colors.red;
      case 'Half Day': return Colors.amber;
      case 'Late': return const Color(0xFFD4AF37);
      case 'Not Marked': return Colors.grey;
      default: return const Color(0xFF1B2B48);
    }
  }

  Gradient? _getAvatarGradient(String status) {
    status = status.toLowerCase();
    if (status == 'present' || status == 'in') return SkeuomorphicColors.successGradient;
    if (status == 'absent' || status == 'out') return SkeuomorphicColors.dangerGradient;
    if (status == 'half day' || status == 'half') {
      return const LinearGradient(
        colors: [Colors.green, Colors.red],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );
    }
    return null;
  }

  void _showManualAttendanceModal(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ManualAttendanceModal(onRefresh: _fetchAllData),
      ),
    );
  }


}


class _ManualAttendanceModal extends StatefulWidget {
  final VoidCallback onRefresh;
  const _ManualAttendanceModal({required this.onRefresh});

  @override
  State<_ManualAttendanceModal> createState() => _ManualAttendanceModalState();
}

class _ManualAttendanceModalState extends State<_ManualAttendanceModal> {
  final bool _isSuccess = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _students = [];
  final DateTime _selectedDate = DateTime.now();
  String _searchQuery = '';
  String _selectedRoom = 'All Rooms';

  List<String> get availableRooms {
    final rooms = _students.map((s) => s['room'] as String).toSet().toList();
    rooms.sort();
    return ['All Rooms', ...rooms];
  }

  List<Map<String, dynamic>> get filteredStudents {
    var result = _students;
    if (_selectedRoom != 'All Rooms') {
      result = result.where((s) => s['room'] == _selectedRoom).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((s) {
        final name = s['name'].toString().toLowerCase();
        final room = s['room'].toString().toLowerCase();
        final id = s['id'].toString().toLowerCase();
        return name.contains(query) || room.contains(query) || id.contains(query);
      }).toList();
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _fetchStudents();
  }

  Future<void> _fetchStudents() async {
    final user = context.read<UserProvider>();
    final response = await ApiService.getStudents(wardenUsername: user.username);
    if (response['status'] == 'success') {
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(response['data']).map((s) {
            return {
              'id': s['register_number'] ?? s['id'], // Use reg_no as ID for better stability
              'name': s['full_name'] ?? 'Unknown',
              'room': 'Room: ${s['room_no'] ?? 'N/A'}',
              'status': 'not marked'
            };
          }).toList();
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    if (_isSuccess) {
      return Dialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.18)) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
              const SizedBox(height: 20),
              Text(
                'Attendance Saved!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1B2B48),
                ),
              ),
              Text('Records updated successfully.', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
            ],
          ),
        ),
      );
    }
    int totalCount = _students.length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F1520) : const Color(0xFFFDFBF7),
      body: SafeArea(
        child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: SkeuomorphicColors.navyAppBarGradient,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Manual Attendance', style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 20, color: Colors.white)),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      // Date Selector
                      Text(
                        'ATTENDANCE DATE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey),
                            const SizedBox(width: 15),
                            Text(
                              '${DateFormat('dd MMMM yyyy').format(_selectedDate)} (Strictly Today)', 
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.grey.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Status Stats
                      Row(
                        children: [
                          Expanded(child: _buildStatBox('${_students.where((s) => s['status'] == 'present').length}', 'PRESENT', Colors.green, isDark)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildStatBox('${_students.where((s) => s['status'] == 'absent').length}', 'ABSENT', Colors.red, isDark)),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Search Bar & Filter
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Search student name...',
                                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                                prefixIcon: Icon(Icons.search, size: 20, color: isDark ? Colors.white60 : Colors.grey),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                              ),
                              onChanged: (v) => setState(() => _searchQuery = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: isDark ? Border.all(color: Colors.white24) : null,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                  isExpanded: true,
                                  value: _selectedRoom,
                                  icon: Icon(Icons.arrow_drop_down, color: isDark ? Colors.white60 : Colors.grey),
                                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _selectedRoom = newValue;
                                      });
                                    }
                                  },
                                  items: availableRooms.map<DropdownMenuItem<String>>((String value) {
                                    String displayValue = value;
                                    if (value.startsWith('Room: ')) {
                                      displayValue = value.substring(6);
                                    }
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(
                                        displayValue,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$totalCount Total Students',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFD4AF37) : Colors.blueGrey,
                            ),
                          ),
                          Text(
                            '${filteredStudents.length} Found',
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Student List
                      Expanded(
                        child: _isLoading
                          ? Center(
                              child: CircularProgressIndicator(
                                color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                              ),
                            )
                          : filteredStudents.isEmpty
                            ? Center(
                                child: Text(
                                  "No students matching search.",
                                  style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filteredStudents.length,
                                itemBuilder: (context, index) => _buildStudentMarkingRow(filteredStudents[index], isDark),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131D2E) : Colors.white,
                  border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                        ),
                        child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      flex: 2,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFD4AF37), Color(0xFFB8860B)]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: const Color(0xFFD4AF37).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                        ),
                        child: InkWell(
                          onTap: _isLoading ? null : () async {
                            setState(() => _isLoading = true);
                            final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                            final response = await ApiService.submitWardenAttendance(dateStr, _students);
                            
                            if (response['status'] == 'success') {
                              widget.onRefresh();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance saved successfully!'), backgroundColor: Colors.green));
                                Navigator.pop(context);
                              }
                            } else {
                              if (mounted) {
                                setState(() => _isLoading = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${response["message"]}')));
                              }
                            }
                          },
                          child: const Center(child: Text('SAVE ATTENDANCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        ),
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

  Widget _buildStatBox(String value, String label, Color color, [bool isDark = false]) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : color.withOpacity(0.7), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStudentMarkingRow(Map<String, dynamic> s, [bool isDark = false]) {
    String name = s['name'] ?? 'Unknown';
    String initials = name.isNotEmpty ? name.trim().split(' ').where((s) => s.isNotEmpty).map((l) => l[0]).take(2).join().toUpperCase() : "?";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.02), blurRadius: 4)],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(color: Color(0xFFD4AF37), shape: BoxShape.circle),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                Text(s['room'], style: TextStyle(fontSize: 10, color: isDark ? Colors.white60 : Colors.grey)),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSmallToggleButton(Icons.check, Colors.green, s['status'] == 'present', () => setState(() => s['status'] = 'present'), isDark),
              const SizedBox(width: 8),
              _buildSmallToggleButton(Icons.close, Colors.red, s['status'] == 'absent', () => setState(() => s['status'] = 'absent'), isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallToggleButton(IconData icon, Color color, bool active, VoidCallback onTap, [bool isDark = false]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: active ? color : (isDark ? Colors.white12 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? Colors.transparent : (isDark ? Colors.white24 : Colors.black12)),
        ),
        child: Icon(icon, size: 16, color: active ? Colors.white : (isDark ? Colors.white60 : color.withOpacity(0.7))),
      ),
    );
  }

}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SearchHeaderDelegate({required this.child});

  @override
  double get minExtent => 205;
  @override
  double get maxExtent => 205;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(
      height: maxExtent,
      child: Material(
        elevation: overlapsContent || shrinkOffset > 0 ? 4 : 0,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(_SearchHeaderDelegate oldDelegate) => true;
}
