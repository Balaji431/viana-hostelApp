import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../core/api_service.dart';
import '../../core/app_logger.dart';
import '../../core/styles.dart';

// ─────────────────────────────────────────────────────────
//  Utility Helper Functions
// ─────────────────────────────────────────────────────────

/// Formats HH:mm string to 12-hour AM/PM format (e.g. "07:53" -> "7:53 AM", "19:34" -> "7:34 PM")
String formatAmPm(String? timeStr) {
  if (timeStr == null || timeStr.isEmpty || timeStr == '--:--') return '—';
  try {
    final parts = timeStr.split(':');
    int h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final period = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    final mStr = m.toString().padLeft(2, '0');
    return '$h:$mStr $period';
  } catch (_) {
    return timeStr;
  }
}

/// Checks if movement triggers a Gold Dot alert:
/// 1. Out time (checkOut) <= 8:00 AM (480 mins)
/// 2. Out time or In time >= 8:00 PM / 20:00 (1200 mins)
/// 3. In time (checkIn) <= 8:00 AM (480 mins)
bool hasGoldDotAlert(Map<String, dynamic> attendance) {
  final String? checkIn = attendance['checkIn'];
  final String? checkOut = attendance['checkOut'];

  int? parseMinutes(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty || timeStr == '--:--') return null;
    try {
      final parts = timeStr.split(':');
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      return h * 60 + m;
    } catch (_) {
      return null;
    }
  }

  final inMin = parseMinutes(checkIn);
  final outMin = parseMinutes(checkOut);

  // Out time <= 8:00 AM (480) OR >= 8:00 PM / 20:00 (1200)
  if (outMin != null && (outMin <= 480 || outMin >= 1200)) return true;
  // In time >= 8:00 PM / 20:00 (1200) OR <= 8:00 AM (480)
  if (inMin != null && (inMin >= 1200 || inMin <= 480)) return true;

  return false;
}

// ─────────────────────────────────────────────────────────
//  Standalone Biometric History Page (for tab/sidebar nav)
// ─────────────────────────────────────────────────────────

class BiometricHistoryPage extends StatefulWidget {
  const BiometricHistoryPage({super.key});

  @override
  State<BiometricHistoryPage> createState() => _BiometricHistoryPageState();
}

class _BiometricHistoryPageState extends State<BiometricHistoryPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, Map<String, dynamic>> _processedAttendance = {};
  bool _isLoading = true;

  final Color royalNavy = const Color(0xFF1B2744);
  final Color royalGold = const Color(0xFFD4AF37);
  final Color attendanceGreen = const Color(0xFF2E7D32);
  final Color attendanceRed = const Color(0xFFC62828);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAttendance());
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final int? studentId = userProvider.isParent
          ? (userProvider.linkedStudentId ?? userProvider.dbId)
          : userProvider.dbId;

      if (studentId != null) {
        AppLogger.info("Fetching attendance logs for studentId: $studentId");
        final response = await ApiService.getAttendance(studentId);
        AppLogger.info("Attendance API response status: ${response['status']}");
        if (response['status'] == true && response['data'] != null) {
          final List rawData = response['data'];
          final Map<String, Map<String, dynamic>> loadedData = {};
          for (var item in rawData) {
            final String date = item['date'];
            final String status =
                item['status']?.toString().toLowerCase() ?? 'none';
            final String? inTime = item['in_time'];
            final String? outTime = item['out_time'];
            loadedData[date] = {
              "status": status == 'late'
                  ? 'present'
                  : (status == 'half_day' ? 'half-day' : status),
              "checkIn": inTime != null && inTime.isNotEmpty
                  ? inTime.substring(0, 5)
                  : null,
              "checkOut": outTime != null && outTime.isNotEmpty
                  ? outTime.substring(0, 5)
                  : null,
              "source": item['source']?.toString().toLowerCase(),
            };
          }
          AppLogger.info("Successfully loaded ${loadedData.length} attendance dates into memory");
          setState(() {
            _processedAttendance = loadedData;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint("Error loading attendance: $e");
    }
    setState(() {
      _processedAttendance = {};
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: 'Biometric History',
          rightAction: IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            onPressed: _loadAttendance,
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                ),
              )
            : _BiometricHistoryBody(
                processedAttendance: _processedAttendance,
                royalNavy: royalNavy,
                royalGold: royalGold,
                attendanceGreen: attendanceGreen,
                attendanceRed: attendanceRed,
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Attendance Calendar Page
// ─────────────────────────────────────────────────────────

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
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
      final int? studentId = userProvider.isParent
          ? (userProvider.linkedStudentId ?? userProvider.dbId)
          : userProvider.dbId;

      if (studentId != null) {
        final response = await ApiService.getAttendance(studentId);
        if (response['status'] == true && response['data'] != null) {
          final List rawData = response['data'];
          final Map<String, Map<String, dynamic>> loadedData = {};

          for (var item in rawData) {
            final String date = item['date'];
            final String status =
                item['status']?.toString().toLowerCase() ?? 'none';
            final String? inTime = item['in_time'];
            final String? outTime = item['out_time'];

            loadedData[date] = {
              "status": status == 'late'
                  ? 'present'
                  : (status == 'half_day' ? 'half-day' : status),
              "checkIn": inTime != null && inTime.isNotEmpty
                  ? inTime.substring(0, 5)
                  : null,
              "checkOut": outTime != null && outTime.isNotEmpty
                  ? outTime.substring(0, 5)
                  : null,
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

    setState(() {
      _processedAttendance = {};
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
        if (parsedDate.year == _focusedDay.year &&
            parsedDate.month == _focusedDay.month) {
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

  void _changeMonth(int offset) {
    setState(() {
      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + offset, 1);
      _selectedDay = null;
      _calculateSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final userProvider = Provider.of<UserProvider>(context);
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: const SkeuomorphicNavBar(
          title: 'Attendance',
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                if (userProvider.isParent) _buildParentBanner(userProvider, isDark),
                _buildMonthSelector(isDark),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                          ),
                        )
                      : SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            children: [
                              const SizedBox(height: 15),
                              _buildSummaryRow(isDark),
                              const SizedBox(height: 20),
                              _buildCalendarCard(isDark),
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildParentBanner(UserProvider userProvider, bool isDark) {
    final studentName = userProvider.linkedStudentName.isNotEmpty
        ? userProvider.linkedStudentName
        : userProvider.userName;
    final studentId = userProvider.linkedStudentUsername.isNotEmpty
        ? userProvider.linkedStudentUsername
        : "";

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : royalNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: royalGold.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : royalNavy.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.family_restroom, color: royalGold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  const TextSpan(
                    text: 'Student: ',
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  TextSpan(
                    text: studentName,
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: royalGold,
                    ),
                  ),
                  if (studentId.isNotEmpty)
                    TextSpan(
                      text: ' ($studentId)',
                      style: const TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF131D2E).withOpacity(0.85)
            : royalNavy.withValues(alpha: 0.98),
        border: isDark
            ? Border(bottom: BorderSide(color: Colors.white.withOpacity(0.12)))
            : null,
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
                  color: Colors.white.withValues(alpha: 0.6),
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
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildSummaryRow(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSummaryCard('$_presentCount', 'PRESENT', attendanceGreen, isDark),
          _buildSummaryCard('$_absentCount', 'ABSENT', attendanceRed, isDark),
          _buildSummaryCard(
              '$_halfDayCount', 'HALF DAY', isDark ? const Color(0xFFD4AF37) : Colors.brown.shade800, isDark),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String count, String label, Color color, bool isDark) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
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
                color: isDark ? Colors.white70 : Colors.grey.shade600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarCard(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.75) : Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.16) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildCalendarHeaders(isDark),
          const SizedBox(height: 15),
          _buildCalendarGrid(isDark),
          const SizedBox(height: 8),
          if (_selectedDay != null) ...[
            _buildDetailCard(isDark),
            const SizedBox(height: 10),
          ],
          Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 15),
          _buildLegend(isDark),
        ],
      ),
    );
  }

  Widget _buildCalendarHeaders(bool isDark) {
    final weekDays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: weekDays
          .map((day) => Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF1B2744),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildCalendarGrid(bool isDark) {
    final int year = _focusedDay.year;
    final int month = _focusedDay.month;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int firstWeekday = DateTime(year, month, 1).weekday % 7;
    final List<Widget> cells = [];
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      cells.add(_buildDayCell(day, isDark));
    }
    return GridView.count(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: cells,
    );
  }

  Widget _buildDayCell(int day, bool isDark) {
    final DateTime currentDay =
        DateTime(_focusedDay.year, _focusedDay.month, day);
    final String dateKey = DateFormat('yyyy-MM-dd').format(currentDay);
    final attendance = _processedAttendance[dateKey] ?? {"status": "none"};
    bool isSelected = _selectedDay != null &&
        _selectedDay!.year == currentDay.year &&
        _selectedDay!.month == currentDay.month &&
        _selectedDay!.day == currentDay.day;
    String status = attendance['status'] ?? 'none';
    final bool showGoldDot = hasGoldDotAlert(attendance);

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
          colors: [
            attendanceRed,
            attendanceRed,
            attendanceGreen,
            attendanceGreen
          ],
          stops: const [0.0, 0.5, 0.5, 1.0],
        ),
      );
    } else {
      decoration = BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : const Color(0xFFDED8CE).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      );
      textColor = isDark ? Colors.white30 : const Color(0xFF1B2B44).withValues(alpha: 0.2);
    }

    return GestureDetector(
      onTap: () {
        setState(() => _selectedDay = currentDay);
      },
      child: Container(
        decoration: isSelected
            ? (decoration as BoxDecoration).copyWith(
                border: Border.all(color: isDark ? royalGold : royalNavy, width: 2),
              )
            : decoration,
        child: Stack(
          children: [
            Center(
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
            if (showGoldDot)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: royalGold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem(attendanceGreen, 'Present', isDark),
          _buildLegendItem(attendanceRed, 'Absent', isDark),
          _buildHalfDayLegend(isDark),
          _buildLegendItem(royalGold, 'Late/Early', isDark, isDot: true),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, bool isDark, {bool isDot = false}) {
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
            color: isDark ? Colors.white70 : const Color(0xFF2D3748),
          ),
        ),
      ],
    );
  }

  Widget _buildHalfDayLegend(bool isDark) {
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
              colors: [
                attendanceRed,
                attendanceRed,
                attendanceGreen,
                attendanceGreen
              ],
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
            color: isDark ? Colors.white70 : const Color(0xFF2D3748),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailCard(bool isDark) {
    final String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final attendance = _processedAttendance[dateKey] ?? {"status": "none"};
    final String status = attendance['status'] ?? 'none';
    if (status == 'none') return const SizedBox.shrink();

    final String? checkIn = attendance['checkIn'];
    final String? checkOut = attendance['checkOut'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : const Color(0xFFE8E0D5).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.12) : Colors.black.withValues(alpha: 0.05),
        ),
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
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white70 : const Color(0xFF2D3748),
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('d MMM yyyy').format(_selectedDay!),
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF1B2B44),
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
                        color: Colors.grey.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTimeCardSideBySide(
                  time: checkIn,
                  isCheckIn: false,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimeCardSideBySide(
                  time: checkOut,
                  isCheckIn: true,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'present'
        ? attendanceGreen
        : (status == 'half-day' ? Colors.brown : attendanceRed);
    String label = status[0].toUpperCase() + status.substring(1);
    if (status == 'half-day') label = "Half Day";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTimeCardSideBySide({
    required String? time,
    required bool isCheckIn,
    required bool isDark,
  }) {
    final bool hasTime = time != null && time.isNotEmpty && time != '--:--';
    final Color mainColor =
        isCheckIn ? attendanceGreen : const Color(0xFFC62828);
    final IconData iconData =
        isCheckIn ? Icons.login_rounded : Icons.logout_rounded;
    final String label = isCheckIn ? "IN" : "OUT";
    final String formattedTime = formatAmPm(time);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.12)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: mainColor, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: mainColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasTime ? formattedTime : '--:--',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF1B2B44),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
//  Shared History Body (used by both Page & Sheet)
// ─────────────────────────────────────────────────────────

class _BiometricHistoryBody extends StatefulWidget {
  final Map<String, Map<String, dynamic>> processedAttendance;
  final Color royalNavy;
  final Color royalGold;
  final Color attendanceGreen;
  final Color attendanceRed;

  const _BiometricHistoryBody({
    required this.processedAttendance,
    required this.royalNavy,
    required this.royalGold,
    required this.attendanceGreen,
    required this.attendanceRed,
  });

  @override
  State<_BiometricHistoryBody> createState() => _BiometricHistoryBodyState();
}

class _BiometricHistoryBodyState extends State<_BiometricHistoryBody> {
  String _filterStatus = 'all';
  // Selected month — initialised to latest month in initState
  DateTime? _selectedMonth;

  @override
  void initState() {
    super.initState();
    // Default to the most recent month that has data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final months = _availableMonths;
      if (months.isNotEmpty && _selectedMonth == null) {
        setState(() => _selectedMonth = months.first);
      }
    });
  }

  // Build sorted, month-filtered, status-filtered entries
  List<MapEntry<String, Map<String, dynamic>>> get _filteredEntries {
    final all = widget.processedAttendance.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return all.where((e) {
      // Month filter
      if (_selectedMonth != null) {
        try {
          final d = DateTime.parse(e.key);
          if (d.year != _selectedMonth!.year ||
              d.month != _selectedMonth!.month) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }
      // Status filter
      if (_filterStatus != 'all') {
        final s = e.value['status'] ?? 'none';
        return s == _filterStatus;
      }
      return true;
    }).toList();
  }

  // All unique months from the data (sorted newest first)
  List<DateTime> get _availableMonths {
    final seen = <String>{};
    final months = <DateTime>[];
    for (final key in widget.processedAttendance.keys) {
      try {
        final d = DateTime.parse(key);
        final monthKey = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        if (!seen.contains(monthKey)) {
          seen.add(monthKey);
          months.add(DateTime(d.year, d.month));
        }
      } catch (_) {}
    }
    months.sort((a, b) => b.compareTo(a));
    return months;
  }

  // Stats for currently selected month (or all months)
  Map<String, int> get _stats {
    int present = 0, absent = 0, halfDay = 0, total = 0;
    for (final e in widget.processedAttendance.entries) {
      if (_selectedMonth != null) {
        try {
          final d = DateTime.parse(e.key);
          if (d.year != _selectedMonth!.year ||
              d.month != _selectedMonth!.month) {
            continue;
          }
        } catch (_) {
          continue;
        }
      }
      total++;
      final s = e.value['status'] ?? 'none';
      if (s == 'present') {
        present++;
      } else if (s == 'absent') {
        absent++;
      } else if (s == 'half-day') {
        halfDay++;
      }
    }
    return {
      'total': total,
      'present': present,
      'absent': absent,
      'halfDay': halfDay
    };
  }

  String _totalHours(String? checkIn, String? checkOut) {
    if (checkIn == null || checkOut == null) return 'N/A';
    try {
      final inParts = checkIn.split(':');
      final outParts = checkOut.split(':');
      final inMin = int.parse(inParts[0]) * 60 + int.parse(inParts[1]);
      final outMin = int.parse(outParts[0]) * 60 + int.parse(outParts[1]);
      final diff = outMin - inMin;
      if (diff <= 0) return 'N/A';
      final h = diff ~/ 60;
      final m = diff % 60;
      if (h == 0) return '${m}m';
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    } catch (_) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filteredEntries;
    final stats = _stats;
    final userProvider = Provider.of<UserProvider>(context);
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return Column(
      children: [
        if (userProvider.isParent) _buildParentBanner(userProvider, isDark),
        // ── Stats Row ──
        _buildStatsRow(stats, isDark),
        // ── Month Selector ──
        _buildMonthSelector(isDark),
        // ── Filter Chips ──
        _buildFilterChips(isDark),
        // ── Column Headers ──
        Container(
          height: 1,
          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
          margin: const EdgeInsets.symmetric(horizontal: 20),
        ),
        _buildColumnHeaders(isDark),
        // ── List ──
        Expanded(
          child: entries.isEmpty
              ? _buildEmpty(isDark)
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 30),
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _buildHistoryRow(entries[i], isDark),
                ),
        ),
      ],
    );
  }

  Widget _buildParentBanner(UserProvider userProvider, bool isDark) {
    final studentName = userProvider.linkedStudentName.isNotEmpty
        ? userProvider.linkedStudentName
        : userProvider.userName;
    final studentId = userProvider.linkedStudentUsername.isNotEmpty
        ? userProvider.linkedStudentUsername
        : "";

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : widget.royalNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.royalGold.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black45 : widget.royalNavy.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.family_restroom, color: widget.royalGold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  const TextSpan(
                    text: 'Student: ',
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  TextSpan(
                    text: studentName,
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: widget.royalGold,
                    ),
                  ),
                  if (studentId.isNotEmpty)
                    TextSpan(
                      text: ' ($studentId)',
                      style: const TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 11,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(Map<String, int> stats, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _statChip('${stats['total']}', 'Total', isDark ? Colors.white : const Color(0xFF1B2744), isDark),
          _statDivider(isDark),
          _statChip('${stats['present']}', 'Present', widget.attendanceGreen, isDark),
          _statDivider(isDark),
          _statChip('${stats['absent']}', 'Absent', widget.attendanceRed, isDark),
          _statDivider(isDark),
          _statChip('${stats['halfDay']}', 'Half Day', isDark ? const Color(0xFFD4AF37) : Colors.brown.shade800, isDark),
        ],
      ),
    );
  }

  Widget _statChip(String count, String label, Color color, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white70 : const Color(0xFF2D3748),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider(bool isDark) {
    return Container(width: 1, height: 32, color: isDark ? Colors.white12 : Colors.grey.shade200);
  }

  // ── Month/Year Dropdown Selector ──
  Widget _buildMonthSelector(bool isDark) {
    final months = _availableMonths;
    if (months.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : widget.royalNavy,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.12)) : null,
        boxShadow: [
          BoxShadow(
            color: widget.royalNavy.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month, color: widget.royalGold, size: 16),
          const SizedBox(width: 10),
          const Text(
            'SELECT MONTH',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.0,
            ),
          ),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<DateTime?>(
              value: _selectedMonth,
              dropdownColor: const Color(0xFF1E2E50),
              borderRadius: BorderRadius.circular(12),
              icon: Icon(Icons.keyboard_arrow_down,
                  color: widget.royalGold, size: 20),
              style: const TextStyle(
                fontFamily: 'Lato',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              selectedItemBuilder: (context) {
                final items = <DateTime?>[null, ...months];
                return items
                    .map((m) => Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            m != null
                                ? DateFormat('MMMM yyyy').format(m)
                                : 'All Months',
                            style: TextStyle(
                              fontFamily: 'Lato',
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: widget.royalGold,
                            ),
                          ),
                        ))
                    .toList();
              },
              items: [
                DropdownMenuItem<DateTime?>(
                  value: null,
                  child: Text(
                    'All Months',
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                ...months.map((m) => DropdownMenuItem<DateTime?>(
                      value: m,
                      child: Text(
                        DateFormat('MMMM yyyy').format(m),
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: (_selectedMonth != null &&
                                  _selectedMonth!.year == m.year &&
                                  _selectedMonth!.month == m.month)
                              ? widget.royalGold
                              : Colors.white,
                        ),
                      ),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedMonth = val),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    const filters = [
      {'key': 'all', 'label': 'All'},
      {'key': 'present', 'label': 'Present'},
      {'key': 'absent', 'label': 'Absent'},
      {'key': 'half-day', 'label': 'Half Day'},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: filters.map((f) {
          final isActive = _filterStatus == f['key'];
          Color activeColor = widget.royalNavy;
          if (f['key'] == 'present') activeColor = widget.attendanceGreen;
          if (f['key'] == 'absent') activeColor = widget.attendanceRed;
          if (f['key'] == 'half-day') activeColor = Colors.brown.shade700;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _filterStatus = f['key']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isActive
                      ? activeColor
                      : (isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? activeColor
                        : (isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade300),
                    width: 1.5,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Text(
                  f['label']!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: isActive
                        ? Colors.white
                        : (isDark ? Colors.white70 : const Color(0xFF2D3748)),
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildColumnHeaders(bool isDark) {
    final headerStyle = TextStyle(
      fontFamily: 'Lato',
      fontSize: 10,
      fontWeight: FontWeight.w900,
      color: isDark ? Colors.white : const Color(0xFF1B2744),
      letterSpacing: 0.8,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      color: isDark
          ? const Color(0xFF131D2E).withOpacity(0.92)
          : const Color(0xFFE2DACD),
      child: Row(
        children: [
          SizedBox(width: 75, child: Text('DATE', style: headerStyle)),
          SizedBox(
              width: 75,
              child: Text('OUT TIME',
                  style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: 75,
              child: Text('IN TIME',
                  style: headerStyle, textAlign: TextAlign.center)),
          Expanded(
              child:
                  Text('TOTAL', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(
              width: 65,
              child: Text('STATUS',
                  style: headerStyle, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(MapEntry<String, Map<String, dynamic>> entry, bool isDark) {
    final dateStr = entry.key;
    final data = entry.value;
    final status = data['status'] ?? 'none';
    final checkIn = data['checkIn'];
    final checkOut = data['checkOut'];
    final totalHrs = _totalHours(checkIn, checkOut);

    DateTime? parsedDate;
    try {
      parsedDate = DateTime.parse(dateStr);
    } catch (_) {}

    final dayStr = parsedDate != null ? DateFormat('d').format(parsedDate) : '';
    final monthStr = parsedDate != null
        ? DateFormat('MMM').format(parsedDate).toUpperCase()
        : '';
    final weekDayStr = parsedDate != null
        ? DateFormat('EEE').format(parsedDate).toUpperCase()
        : '';

    Color statusColor;
    String statusLabel;
    Color rowBg;
    switch (status) {
      case 'present':
        statusColor = widget.attendanceGreen;
        statusLabel = 'PRESENT';
        rowBg = isDark ? const Color(0xFF131D2E).withOpacity(0.65) : const Color(0xFFF5F0E8);
        break;
      case 'absent':
        statusColor = widget.attendanceRed;
        statusLabel = 'ABSENT';
        rowBg = isDark ? const Color(0xFF2A1515).withOpacity(0.65) : const Color(0xFFFFF3F3);
        break;
      case 'half-day':
        statusColor = Colors.brown.shade800;
        statusLabel = 'HALF DAY';
        rowBg = isDark ? const Color(0xFF2B2215).withOpacity(0.65) : const Color(0xFFFFF8F0);
        break;
      default:
        statusColor = Colors.grey.shade600;
        statusLabel = 'N/A';
        rowBg = isDark ? const Color(0xFF131D2E).withOpacity(0.5) : const Color(0xFFF5F0E8);
    }

    return Container(
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withValues(alpha: 0.08),
          ),
          left: BorderSide(color: statusColor, width: 4),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '$dayStr ',
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : widget.royalNavy,
                        ),
                      ),
                      TextSpan(
                        text: monthStr,
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: widget.royalGold,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  weekDayStr,
                  style: TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white70 : const Color(0xFF2D3748),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 75,
            child: Text(
              formatAmPm(checkIn),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: checkIn != null
                    ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF1E7E34))
                    : (isDark ? Colors.white38 : const Color(0xFF4A5568)),
              ),
            ),
          ),
          SizedBox(
            width: 75,
            child: Text(
              formatAmPm(checkOut),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: checkOut != null
                    ? (isDark ? const Color(0xFFF87171) : const Color(0xFFD32F2F))
                    : (isDark ? Colors.white38 : const Color(0xFF4A5568)),
              ),
            ),
          ),
          Expanded(
            child: Text(
              totalHrs,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white70 : const Color(0xFF1A202C),
              ),
            ),
          ),
          SizedBox(
            width: 65,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  statusLabel,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off, size: 52, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text(
            'No records found',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2D3748),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Try a different month or filter',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4A5568),
            ),
          ),
        ],
      ),
    );
  }
}
