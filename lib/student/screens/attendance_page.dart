import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/user_provider.dart';
import '../../core/api_service.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  DateTime _focusedDay = DateTime.now(); 
  DateTime? _selectedDay;
  Map<String, Map<String, dynamic>> _processedAttendance = {};
  bool _isLoading = true;

  int _presentCount = 0;
  int _absentCount = 0;
  int _halfDayCount = 0;

  final Color royalNavy = const Color(0xFF1B2744);
  final Color royalGold = const Color(0xFFD4AF37);
  final Color attendanceGreen = const Color(0xFF2E7D32); 
  final Color attendanceRed = const Color(0xFFC62828);   

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAttendance();
    });
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final int? studentId = userProvider.isParent ? userProvider.linkedStudentId : userProvider.dbId;
      if (studentId != null) {
        final response = await ApiService.getAttendance(studentId);
        if (response['status'] == true && response['data'] != null) {
          final List rawData = response['data'];
          final Map<String, Map<String, dynamic>> loadedData = {};
          
          for (var item in rawData) {
            final String date = item['date'];
            final String status = item['status']?.toString().toLowerCase() ?? 'none';
            final String? inTime = item['in_time'];
            final String? outTime = item['out_time'];
            
            loadedData[date] = {
              "status": status == 'late' ? 'present' : status,
              "checkIn": inTime != null && inTime.isNotEmpty ? inTime.substring(0, 5) : null,
              "checkOut": outTime != null && outTime.isNotEmpty ? outTime.substring(0, 5) : null,
              "source": item['source']?.toString().toLowerCase(),
            };
          }

          setState(() {
            _processedAttendance = loadedData;
            _focusedDay = DateTime.now();
            _selectedDay = DateTime.now();
            _calculateSummary();
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading attendance: $e");
    }

    // Fallback to mock data if loading fails or studentId is null
    setState(() {
      _loadMockData();
      _focusedDay = DateTime.now();
      _selectedDay = DateTime.now();
      _calculateSummary();
      _isLoading = false;
    });
  }

  void _calculateSummary() {
    _presentCount = 0;
    _absentCount = 0;
    _halfDayCount = 0;

    _processedAttendance.forEach((dateKey, data) {
      try {
        DateTime parsedDate = DateTime.parse(dateKey);
        if (parsedDate.year == _focusedDay.year && parsedDate.month == _focusedDay.month) {
          String status = data['status'] ?? 'none';

          if (status == 'present') {
            _presentCount++;
          } else if (status == 'absent') {
            _absentCount++;
          } else if (status == 'half-day') {
            _halfDayCount++;
          }
        }
      } catch (_) {}
    });
  }

  void _loadMockData() {
    _processedAttendance = {
      "2026-04-01": {"status": "absent", "checkIn": "21:30", "source": "warden"},
      "2026-04-02": {"status": "absent", "checkIn": "21:45", "source": "warden"},
      "2026-04-03": {"status": "present", "checkIn": "09:15", "source": "warden"},
      "2026-04-04": {"status": "present", "checkIn": "09:30", "source": "warden"},
      "2026-04-08": {"status": "present", "checkIn": "08:21", "source": "biometric"},
      "2026-04-09": {"status": "absent", "checkIn": "21:10", "source": "warden"},
      "2026-04-10": {"status": "absent", "checkIn": "21:15", "source": "warden"},
      "2026-04-16": {"status": "absent", "checkIn": "22:00", "source": "warden"},
      "2026-04-21": {"status": "present", "checkIn": "09:20", "source": "warden"},
      "2026-04-24": {"status": "present", "checkIn": "09:05", "source": "warden"},
      "2026-04-26": {"status": "half-day", "checkIn": "14:15", "source": "warden"},
      "2026-05-01": {"status": "present", "checkIn": "10:30", "source": "warden"},
      "2026-05-02": {"status": "absent", "checkIn": "21:05", "source": "warden"},
      "2026-05-03": {"status": "present", "checkIn": "08:50", "source": "warden"},
      "2026-05-04": {"status": "present", "checkIn": "08:45", "source": "warden"},
      "2026-05-05": {"status": "present", "checkIn": "08:55", "source": "warden"},
      "2026-05-06": {"status": "present", "checkIn": "09:00", "source": "warden"},
      "2026-05-07": {"status": "present", "checkIn": "08:45", "source": "biometric"},
    };
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + offset, 1);
      _selectedDay = null; 
      _calculateSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SkeuomorphicNavBar(
        title: 'Attendance',
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            children: [
              _buildMonthSelector(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                        ),
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            const SizedBox(height: 15),
                            _buildSummaryRow(),
                            const SizedBox(height: 20),
                            _buildCalendarCard(), 
                            const SizedBox(height: 30),
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

  Widget _buildMonthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        color: royalNavy.withOpacity(0.98),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildChevronButton(Icons.chevron_left, () => _changeMonth(-1)),
          Column(
            children: [
              Text(
                DateFormat('MMMM').format(_focusedDay),
                style: const TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                DateFormat('yyyy').format(_focusedDay),
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          _buildChevronButton(Icons.chevron_right, () => _changeMonth(1)),
        ],
      ),
    );
  }

  Widget _buildChevronButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryCard('$_presentCount', 'PRESENT', attendanceGreen),
          _buildSummaryCard('$_absentCount', 'ABSENT', attendanceRed),
          _buildSummaryCard('$_halfDayCount', 'HALF DAY', Colors.brown.shade800),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String count, String label, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: Colors.grey.shade400,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCalendarHeaders(),
          const SizedBox(height: 15),
          _buildCalendarGrid(),
          const SizedBox(height: 25),
          if (_selectedDay != null) ...[
            _buildDetailCard(),
            const SizedBox(height: 20),
          ],
          const Divider(height: 1),
          const SizedBox(height: 15),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _buildCalendarHeaders() {
    final weekDays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: weekDays.map((day) => Expanded(
        child: Center(
          child: Text(
            day,
            style: const TextStyle(
              fontFamily: 'Lato',
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1B2744),
              letterSpacing: 0.5,
            ),
          ),
        ),
      )).toList(),
    );
  }

  Widget _buildCalendarGrid() {
    final int year = _focusedDay.year;
    final int month = _focusedDay.month;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int firstWeekday = DateTime(year, month, 1).weekday % 7;
    final List<Widget> cells = [];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      cells.add(_buildDayCell(day));
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: cells,
    );
  }

  Widget _buildDayCell(int day) {
    final DateTime currentDay = DateTime(_focusedDay.year, _focusedDay.month, day);
    final String dateKey = DateFormat('yyyy-MM-dd').format(currentDay);
    final attendance = _processedAttendance[dateKey] ?? {"status": "none"};
    bool isSelected = _selectedDay != null && 
                     _selectedDay!.year == currentDay.year && 
                     _selectedDay!.month == currentDay.month && 
                     _selectedDay!.day == currentDay.day;
    String status = attendance['status'] ?? 'none';
    Decoration decoration;
    Color textColor = Colors.white;
    if (status == 'present') {
      decoration = BoxDecoration(
        color: attendanceGreen,
        borderRadius: BorderRadius.circular(4),
      );
    } else if (status == 'absent') {
      decoration = BoxDecoration(
        color: attendanceRed,
        borderRadius: BorderRadius.circular(4),
      );
    } else if (status == 'half-day') {
      decoration = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [attendanceRed, attendanceRed, attendanceGreen, attendanceGreen],
          stops: const [0.0, 0.5, 0.5, 1.0],
        ),
      );
    } else {
      decoration = BoxDecoration(
        color: const Color(0xFFDED8CE).withOpacity(0.8), 
        borderRadius: BorderRadius.circular(4),
      );
      textColor = const Color(0xFF1B2744).withOpacity(0.2);
    }
    return GestureDetector(
      onTap: () {
        setState(() => _selectedDay = currentDay);
      },
      child: Container(
        decoration: isSelected 
          ? (decoration as BoxDecoration).copyWith(
              border: Border.all(color: royalNavy, width: 2),
            )
          : decoration,
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem(attendanceGreen, 'Present'),
          _buildLegendItem(attendanceRed, 'Absent'),
          _buildHalfDayLegend(),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, {bool isDot = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: isDot ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isDot ? null : BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Lato',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildHalfDayLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [attendanceRed, attendanceRed, attendanceGreen, attendanceGreen],
              stops: const [0.0, 0.5, 0.5, 1.0],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Half Day',
          style: TextStyle(
            fontFamily: 'Lato',
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailCard() {
    final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final attendance = _processedAttendance[dateKey] ?? {"status": "none"};
    final String status = attendance['status'] ?? 'none';
    if (status == 'none') return const SizedBox.shrink();
    
    final String? checkIn = attendance['checkIn'];
    final String? source = attendance['source'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8E0D5).withOpacity(0.6), 
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE').format(_selectedDay!).toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMM yyyy').format(_selectedDay!),
                    style: const TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B2B44),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildStatusBadge(status),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => setState(() => _selectedDay = null),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildUnifiedTimeCard(
            status: status,
            time: checkIn,
            source: source,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'present' ? attendanceGreen : (status == 'half-day' ? Colors.brown : attendanceRed);
    String label = status[0].toUpperCase() + status.substring(1);
    if (status == 'half-day') label = "Half Day";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildUnifiedTimeCard({
    required String status,
    required String? time,
    required String? source,
  }) {
    final bool isPresent = status == 'present' || status == 'late';
    final Color mainColor = isPresent ? attendanceGreen : attendanceRed;
    
    String actionTitle = "";
    IconData iconData;
    
    final String src = source?.trim().toLowerCase() ?? "";
    
    if (src == 'warden' || src == 'manual' || src == 'manual_override') {
      if (isPresent) {
        actionTitle = "TAKEN PRESENT BY WARDEN";
        iconData = Icons.verified_rounded;
      } else {
        actionTitle = "MARKED ABSENT BY WARDEN";
        iconData = Icons.gpp_bad_rounded;
      }
    } else if (src == 'biometric') {
      if (isPresent) {
        actionTitle = "BIOMETRIC PRESENT VERIFICATION";
        iconData = Icons.fingerprint_rounded;
      } else {
        actionTitle = "BIOMETRIC ABSENT VERIFICATION";
        iconData = Icons.fingerprint_rounded;
      }
    } else {
      if (isPresent) {
        actionTitle = "ATTENDANCE VERIFIED PRESENT";
        iconData = Icons.check_circle_rounded;
      } else {
        actionTitle = "ATTENDANCE VERIFIED ABSENT";
        iconData = Icons.cancel_rounded;
      }
    }

    final String formattedTime = _formatTime12Hour(time);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.black.withOpacity(0.02)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mainColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconData,
              color: mainColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionTitle,
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: mainColor,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formattedTime,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B2B44),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime12Hour(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == '--:--') return '--:--';
    try {
      final parts = timeStr.split(':');
      if (parts.isEmpty) return timeStr;
      int hour = int.parse(parts[0]);
      int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
      
      final String period = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;
      
      final String minStr = minute.toString().padLeft(2, '0');
      final String hrStr = hour.toString().padLeft(2, '0');
      
      return '$hrStr:$minStr $period';
    } catch (_) {
      return timeStr;
    }
  }
}
