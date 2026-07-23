import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../shared/user_provider.dart';
import 'dart:math';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_widgets.dart';

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
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<UserProvider>();
    final showInternalAppBar = (user.role == UserRole.warden || user.role == UserRole.admin);

    return Scaffold(
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
                  _buildMonthSelector(),
                  _buildHeatmapCard(),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: _buildMarkAttendanceButton(),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SearchHeaderDelegate(
                child: _buildSearchAndStatsHeader(),
              ),
            ),
            SliverToBoxAdapter(
              child: _buildDailyStatsSection(),
            ),
            _buildStudentListSliver(),
          ],
        ),
      ),
    );
  }

  Widget _buildMarkAttendanceButton() {
    return Container(
      color: const Color(0xFFFDFBF7), // Match background
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: SkeuomorphicButton(
        onTap: () => _showManualAttendanceModal(context),
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD4AF37), Color(0xFFB8860B)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.edit, color: Color(0xFF1B2B48), size: 18),
              const SizedBox(width: 10),
              Text('Mark Attendance Manually', style: SkeuomorphicStyles.playfairHeader.copyWith(color: const Color(0xFF1B2B48), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      decoration: const BoxDecoration(gradient: SkeuomorphicColors.navyAppBarGradient),
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

  Widget _buildHeatmapCard() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(15),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Text(d, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))).toList(),
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
                    color: _monthlyDailyData.containsKey(day) ? _getHeatmapColor(attendancePerc, isFuture) : const Color(0xFFE8E0D5),
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
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Low', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(
                  'Tap dates to view • Multi-select supported', 
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('High', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }



  Widget _buildSearchAndStatsHeader() {
    return Container(
      color: const Color(0xFFFDFBF7),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedDays.isNotEmpty && !_isLoadingLogs) ...[
            _buildDailyStats(_attendanceLogs),
            const SizedBox(height: 15),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search students...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_getFilteredLogs().length} Records', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey, fontSize: 14)),
                Text(DateFormat('dd MMM yyyy').format(DateTime(_selectedMonth.year, _selectedMonth.month, _selectedDays.last)), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDailyStatsSection() {
    if (_selectedDays.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Column(
          children: [
            Icon(Icons.calendar_month, size: 64, color: Colors.grey),
            SizedBox(height: 15),
            Text('Tap dates on the calendar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
            Text('Select a date to view detailed attendance logs', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
    
    if (_isLoadingLogs) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildStudentListSliver() {
    if (_selectedDays.isEmpty || _isLoadingLogs) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final filteredLogs = _getFilteredLogs();
    
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.builder(
        itemCount: filteredLogs.length,
        itemBuilder: (context, index) {
          return _buildStudentCard(filteredLogs[index]);
        },
      ),
    );
  }

  Widget _buildDailyStats(List<Map<String, dynamic>> logs) {
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatColumn('Present', present, Colors.green),
          _buildStatColumn('Absent', absent, Colors.red),
          _buildStatColumn('Half Day', half, Colors.orange),
          _buildStatColumn('Not Marked', notMarked, Colors.grey),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, int value, Color color) {
    return Column(
      children: [
        Text(value.toString(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
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

  Widget _buildStudentCard(Map<String, dynamic> log) {
    String name = log['name'] ?? 'Unknown';
    String initials = name.isNotEmpty ? name.trim().split(' ').where((s) => s.isNotEmpty).map((l) => l[0]).take(2).join().toUpperCase() : "?";
    String status = log['status'] ?? 'Not Marked';
    String timeStr = log['created_at'] != null ? DateFormat('hh:mm a').format(DateTime.parse(log['created_at'])) : "";
    
    return GestureDetector(
      onTap: null, // Disabled navigation to student details
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: _getAvatarGradient(status),
              color: status == 'Not Marked' ? Colors.grey.shade400 : null,
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 14, color: const Color(0xFF1B2B48))),
                Text('Room: ${log['room_no'] ?? "N/A"} • ID: ${log['RegisterNumber'] ?? 'N/A'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                    Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
    if (_isSuccess) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green, size: 80),
              SizedBox(height: 20),
              Text('Attendance Saved!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('Records updated successfully.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    int totalCount = _students.length;

    return Scaffold(
      backgroundColor: const Color(0xFFFDFBF7),
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
                      Text('ATTENDANCE DATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 18, color: Colors.grey),
                            const SizedBox(width: 15),
                            Text(
                              '${DateFormat('dd MMMM yyyy').format(_selectedDate)} (Strictly Today)', 
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Status Stats
                      Row(
                        children: [
                          Expanded(child: _buildStatBox('${_students.where((s) => s['status'] == 'present').length}', 'PRESENT', Colors.green)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildStatBox('${_students.where((s) => s['status'] == 'absent').length}', 'ABSENT', Colors.red)),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Search Bar & Filter
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Search student name...',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: Colors.grey.shade100,
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
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedRoom,
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                                  style: const TextStyle(color: Colors.black87, fontSize: 13),
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
                                      child: Text(displayValue, overflow: TextOverflow.ellipsis),
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
                          Text('$totalCount Total Students', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          Text('${filteredStudents.length} Found', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Student List
                      Expanded(
                        child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : filteredStudents.isEmpty
                            ? const Center(child: Text("No students matching search."))
                            : ListView.builder(
                                itemCount: filteredStudents.length,
                                itemBuilder: (context, index) => _buildStudentMarkingRow(filteredStudents[index]),
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
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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

  Widget _buildStatBox(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStudentMarkingRow(Map<String, dynamic> s) {
    String name = s['name'] ?? 'Unknown';
    String initials = name.isNotEmpty ? name.trim().split(' ').where((s) => s.isNotEmpty).map((l) => l[0]).take(2).join().toUpperCase() : "?";
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
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
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2B48))),
                Text(s['room'], style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSmallToggleButton(Icons.check, Colors.green, s['status'] == 'present', () => setState(() => s['status'] = 'present')),
              const SizedBox(width: 8),
              _buildSmallToggleButton(Icons.close, Colors.red, s['status'] == 'absent', () => setState(() => s['status'] = 'absent')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallToggleButton(IconData icon, Color color, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: active ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? Colors.transparent : Colors.black12),
        ),
        child: Icon(icon, size: 16, color: active ? Colors.white : color.withOpacity(0.7)),
      ),
    );
  }

}

class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _SearchHeaderDelegate({required this.child});

  @override
  double get minExtent => 190;
  @override
  double get maxExtent => 190;

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
