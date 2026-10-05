import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../widgets/assign_biometric_dialog.dart';

class ItBiometricHistoryScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final List<dynamic>? initialAttendanceData;
  final VoidCallback? onDataUpdated;

  const ItBiometricHistoryScreen({
    super.key,
    required this.student,
    this.initialAttendanceData,
    this.onDataUpdated,
  });

  @override
  State<ItBiometricHistoryScreen> createState() => _ItBiometricHistoryScreenState();
}

class _ItBiometricHistoryScreenState extends State<ItBiometricHistoryScreen> {
  final Color royalNavy = const Color(0xFF1B2744);
  final Color royalGold = const Color(0xFFD4AF37);
  final Color attendanceGreen = const Color(0xFF2E7D32);
  final Color attendanceRed = const Color(0xFFC62828);

  bool _isLoading = false;
  bool _isSynced = false;
  Map<String, Map<String, dynamic>> _processedAttendance = {};
  String _filterStatus = 'all';
  DateTime? _selectedMonth;

  late String _regNo;
  late String _fullName;
  late String _hostelName;
  late String _roomAllocation;
  late String _biometricId;

  @override
  void initState() {
    super.initState();
    _regNo = widget.student['register_no']?.toString() ?? '';
    _fullName = widget.student['full_name']?.toString() ?? 'Student';
    _hostelName = widget.student['hostel_name']?.toString() ?? 'N/A';
    _roomAllocation = widget.student['room_allocation']?.toString() ?? 'N/A';
    _biometricId = widget.student['biometric_id']?.toString() ?? '';
    _isSynced = widget.student['is_synced'] == true;

    if (widget.initialAttendanceData != null && widget.initialAttendanceData!.isNotEmpty) {
      _loadFromRawList(widget.initialAttendanceData!);
    } else {
      _fetchLiveBiometrics();
    }
  }

  void _loadFromRawList(List rawList) {
    final Map<String, Map<String, dynamic>> loadedData = {};
    for (var item in rawList) {
      if (item is Map) {
        final String date = item['date']?.toString() ?? '';
        if (date.isEmpty) continue;
        final String status = item['status']?.toString().toLowerCase() ?? 'none';
        final String? inTime = item['in_time']?.toString();
        final String? outTime = item['out_time']?.toString();
        loadedData[date] = {
          "status": status == 'late'
              ? 'present'
              : (status == 'half_day' ? 'half-day' : status),
          "checkIn": inTime != null && inTime.isNotEmpty
              ? inTime.substring(0, inTime.length >= 5 ? 5 : inTime.length)
              : null,
          "checkOut": outTime != null && outTime.isNotEmpty
              ? outTime.substring(0, outTime.length >= 5 ? 5 : outTime.length)
              : null,
          "source": item['source']?.toString().toLowerCase() ?? 'biometric',
        };
      }
    }

    setState(() {
      _processedAttendance = loadedData;
      _isSynced = loadedData.isNotEmpty;
      final months = _availableMonths;
      if (months.isNotEmpty && _selectedMonth == null) {
        _selectedMonth = months.first;
      }
    });
  }

  Future<void> _fetchLiveBiometrics() async {
    if (_regNo.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final res = await ApiService.checkSingleStudentBiometric(_regNo);
      if (mounted) {
        if (res['success'] == true) {
          final isSynced = res['is_synced'] == true;
          final List rawLogs = (res['data'] as List?) ?? [];

          setState(() {
            _isSynced = isSynced;
            _isLoading = false;
          });

          _loadFromRawList(rawLogs);
          widget.onDataUpdated?.call();
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

  String _formatAmPm(String? timeStr) {
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

  List<DateTime> get _availableMonths {
    final seen = <String>{};
    final months = <DateTime>[];
    for (final key in _processedAttendance.keys) {
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

  List<MapEntry<String, Map<String, dynamic>>> get _filteredEntries {
    final all = _processedAttendance.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return all.where((e) {
      if (_selectedMonth != null) {
        try {
          final d = DateTime.parse(e.key);
          if (d.year != _selectedMonth!.year || d.month != _selectedMonth!.month) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }
      if (_filterStatus != 'all') {
        final s = e.value['status'] ?? 'none';
        return s == _filterStatus;
      }
      return true;
    }).toList();
  }

  Map<String, int> get _stats {
    int present = 0, absent = 0, halfDay = 0, total = 0;
    for (final e in _processedAttendance.entries) {
      if (_selectedMonth != null) {
        try {
          final d = DateTime.parse(e.key);
          if (d.year != _selectedMonth!.year || d.month != _selectedMonth!.month) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<WallpaperProvider>().isDarkTheme;
    final stats = _stats;
    final entries = _filteredEntries;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Biometric History',
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A2744),
            Color(0xFF2A3A5C),
          ],
        ),
        titleColor: const Color(0xFFD4AF37),
        borderColor: const Color(0xFFD4AF37).withValues(alpha: 0.5),
        onBack: () => Navigator.of(context).pop(),
        rightAction: IconButton(
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                  ),
                )
              : const Icon(Icons.refresh_rounded, color: Color(0xFFD4AF37), size: 22),
          onPressed: _isLoading ? null : _fetchLiveBiometrics,
          tooltip: 'Live Re-check',
        ),
      ),
      body: LinenBackground(
        child: Column(
          children: [
            // ── Top Student Info Header Banner (Image 3 Style) ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF1A2744),
                    Color(0xFF2A3A5C),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: royalGold, width: 1.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: royalGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: royalGold.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _regNo,
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: royalGold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullName,
                          style: const TextStyle(
                            fontFamily: 'Lato',
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_hostelName • $_roomAllocation',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _isSynced
                            ? [const Color(0xFF4ADE80), const Color(0xFF16A34A)]
                            : [const Color(0xFFFBBF24), const Color(0xFFD97706)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: (_isSynced ? const Color(0xFF16A34A) : const Color(0xFFD97706)).withValues(alpha: 0.35),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      _isSynced ? 'REGISTERED' : 'NOT REGISTERED',
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Main Body Content ──
            Expanded(
              child: Column(
                children: [
                  if (_isLoading)
                    const LinearProgressIndicator(
                      minHeight: 2.5,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                    ),
                  // ── 4 Stats Cards (Total, Present, Absent, Half Day) ──
                  _buildStatsRow(stats, isDark),

                  // ── Month Selector Dropdown ──
                  _buildMonthSelector(isDark),

                  // ── Filter Chips (All, Present, Absent, Half Day) ──
                  _buildFilterChips(isDark),

                  // ── Table Column Headers (DATE, OUT TIME, IN TIME, TOTAL, STATUS) ──
                  _buildColumnHeaders(isDark),

                  // ── Table Data Rows or Empty State ──
                  Expanded(
                    child: entries.isEmpty
                        ? _buildEmptyState(isDark)
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              return _buildHistoryRow(entries[index], isDark);
                            },
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

  Widget _buildStatsRow(Map<String, int> stats, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildStatItem('${stats['total']}', 'Total', isDark ? Colors.white : const Color(0xFF1B2744), isDark),
          _buildStatDivider(isDark),
          _buildStatItem('${stats['present']}', 'Present', attendanceGreen, isDark),
          _buildStatDivider(isDark),
          _buildStatItem('${stats['absent']}', 'Absent', attendanceRed, isDark),
          _buildStatDivider(isDark),
          _buildStatItem('${stats['halfDay']}', 'Half Day', isDark ? const Color(0xFFD4AF37) : Colors.brown.shade800, isDark),
        ],
      ),
    );
  }

  Widget _buildStatItem(String count, String label, Color color, bool isDark) {
    return Expanded(
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 19,
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
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : const Color(0xFF4A5568),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(bool isDark) {
    return Container(width: 1, height: 28, color: isDark ? Colors.white12 : Colors.grey.shade200);
  }

  Widget _buildMonthSelector(bool isDark) {
    final months = _availableMonths;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2744) : royalNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: royalGold.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_month, color: royalGold, size: 16),
          const SizedBox(width: 8),
          const Text(
            'SELECT MONTH',
            style: TextStyle(
              fontFamily: 'Lato',
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          DropdownButtonHideUnderline(
            child: DropdownButton<DateTime?>(
              value: _selectedMonth,
              dropdownColor: const Color(0xFF1E2E50),
              borderRadius: BorderRadius.circular(12),
              icon: Icon(Icons.keyboard_arrow_down, color: royalGold, size: 20),
              style: const TextStyle(
                fontFamily: 'Lato',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
              selectedItemBuilder: (context) {
                final items = <DateTime?>[null, ...months];
                return items.map((m) {
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      m != null ? DateFormat('MMMM yyyy').format(m) : 'All Months',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: royalGold,
                      ),
                    ),
                  );
                }).toList();
              },
              items: [
                DropdownMenuItem<DateTime?>(
                  value: null,
                  child: Text(
                    'All Months',
                    style: TextStyle(
                      fontFamily: 'Lato',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: (_selectedMonth != null &&
                                  _selectedMonth!.year == m.year &&
                                  _selectedMonth!.month == m.month)
                              ? royalGold
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
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Row(
        children: filters.map((f) {
          final isActive = _filterStatus == f['key'];
          Color activeColor = royalNavy;
          if (f['key'] == 'present') activeColor = attendanceGreen;
          if (f['key'] == 'absent') activeColor = attendanceRed;
          if (f['key'] == 'half-day') activeColor = Colors.brown.shade700;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _filterStatus = f['key']!),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 5),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isActive
                      ? activeColor
                      : (isDark ? const Color(0xFF1E293B) : Colors.white),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? activeColor
                        : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.grey.shade300),
                    width: 1.2,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: isDark ? const Color(0xFF1A2744).withValues(alpha: 0.9) : const Color(0xFFE6DDD2),
      child: Row(
        children: [
          SizedBox(width: 75, child: Text('DATE', style: headerStyle)),
          SizedBox(width: 75, child: Text('OUT TIME', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 75, child: Text('IN TIME', style: headerStyle, textAlign: TextAlign.center)),
          Expanded(child: Text('TOTAL', style: headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 65, child: Text('STATUS', style: headerStyle, textAlign: TextAlign.right)),
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
    final monthStr = parsedDate != null ? DateFormat('MMM').format(parsedDate).toUpperCase() : '';
    final weekDayStr = parsedDate != null ? DateFormat('EEE').format(parsedDate).toUpperCase() : '';

    Color statusColor;
    String statusLabel;
    Color rowBg;
    switch (status) {
      case 'present':
        statusColor = attendanceGreen;
        statusLabel = 'PRESENT';
        rowBg = isDark ? const Color(0xFF131D2E).withValues(alpha: 0.65) : const Color(0xFFF5F0E8);
        break;
      case 'absent':
        statusColor = attendanceRed;
        statusLabel = 'ABSENT';
        rowBg = isDark ? const Color(0xFF2A1515).withValues(alpha: 0.65) : const Color(0xFFFFF3F3);
        break;
      case 'half-day':
        statusColor = Colors.brown.shade800;
        statusLabel = 'HALF DAY';
        rowBg = isDark ? const Color(0xFF2B2215).withValues(alpha: 0.65) : const Color(0xFFFFF8F0);
        break;
      default:
        statusColor = Colors.grey.shade600;
        statusLabel = 'N/A';
        rowBg = isDark ? const Color(0xFF131D2E).withValues(alpha: 0.5) : const Color(0xFFF5F0E8);
    }

    return Container(
      decoration: BoxDecoration(
        color: rowBg,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          ),
          left: BorderSide(color: statusColor, width: 4),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          // Date Column
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
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isDark ? Colors.white : royalNavy,
                        ),
                      ),
                      TextSpan(
                        text: monthStr,
                        style: TextStyle(
                          fontFamily: 'Lato',
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: royalGold,
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
          // Out Time (checkIn in biometric format)
          SizedBox(
            width: 75,
            child: Text(
              _formatAmPm(checkIn),
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
          // In Time (checkOut in biometric format)
          SizedBox(
            width: 75,
            child: Text(
              _formatAmPm(checkOut),
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
          // Total Duration
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
          // Status Pill Badge
          SizedBox(
            width: 65,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
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
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white12 : Colors.grey.shade100),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fingerprint_rounded,
                size: 48,
                color: isDark ? Colors.white38 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'No Records Found',
              style: TextStyle(
                fontFamily: 'Lato',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1B2B48),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No biometric punch logs found for student $_regNo on the biometric machine.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AssignBiometricDialog(
                    registerNo: _regNo,
                    fullName: _fullName,
                    hostelName: _hostelName,
                    roomAllocation: _roomAllocation,
                    currentBiometricId: _biometricId,
                    onAssigned: () {
                      _fetchLiveBiometrics();
                      widget.onDataUpdated?.call();
                    },
                  ),
                );
              },
              icon: const Icon(Icons.add_task_rounded, size: 16),
              label: const Text('Assign Biometric ID'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
