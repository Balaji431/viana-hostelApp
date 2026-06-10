import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/styles.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../shared/widgets/skeuomorphic_navbar.dart';

class MaintenanceAttendanceTab extends StatefulWidget {
  const MaintenanceAttendanceTab({super.key});

  @override
  State<MaintenanceAttendanceTab> createState() => _MaintenanceAttendanceTabState();
}

class _MaintenanceAttendanceTabState extends State<MaintenanceAttendanceTab> {
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  DateTime? _checkOutTime;
  List<Map<String, dynamic>> _attendanceHistory = [];

  @override
  void initState() {
    super.initState();
    _loadAttendanceHistory();
  }

  void _loadAttendanceHistory() {
    setState(() {
      _attendanceHistory = [
        {'date': '2024-01-15', 'checkIn': '08:00 AM', 'checkOut': '05:00 PM', 'status': 'Present'},
        {'date': '2024-01-14', 'checkIn': '08:15 AM', 'checkOut': '05:30 PM', 'status': 'Present'},
        {'date': '2024-01-13', 'checkIn': '07:55 AM', 'checkOut': '04:45 PM', 'status': 'Present'},
        {'date': '2024-01-12', 'checkIn': '-', 'checkOut': '-', 'status': 'Off'},
        {'date': '2024-01-11', 'checkIn': '08:05 AM', 'checkOut': '05:15 PM', 'status': 'Present'},
      ];
    });
  }

  void _toggleCheckInOut() {
    setState(() {
      if (!_isCheckedIn) {
        _isCheckedIn = true;
        _checkInTime = DateTime.now();
      } else {
        _isCheckedIn = false;
        _checkOutTime = DateTime.now();
        _attendanceHistory.insert(0, {
          'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          'checkIn': DateFormat('hh:mm a').format(_checkInTime!),
          'checkOut': DateFormat('hh:mm a').format(_checkOutTime!),
          'status': 'Present',
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SkeuomorphicNavBar(
        title: 'Attendance',
        rightAction: ProfileButton(),
      ),
      body: LinenBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAttendanceCard(),
                  const SizedBox(height: 25),
                  _buildHistoryHeader(),
                  _buildAttendanceHistory(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _isCheckedIn ? const Color(0xFF4CAF50) : const Color(0xFF1A2744),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              _isCheckedIn ? Icons.check_circle : Icons.access_time,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _isCheckedIn ? 'Checked In' : 'Not Checked In',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A2744)),
          ),
          const SizedBox(height: 10),
          if (_checkInTime != null)
            Text(
              'Check In: ${DateFormat('hh:mm a').format(_checkInTime!)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          if (_checkOutTime != null && !_isCheckedIn)
            Text(
              'Check Out: ${DateFormat('hh:mm a').format(_checkOutTime!)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _toggleCheckInOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCheckedIn ? const Color(0xFFE57373) : const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _isCheckedIn ? 'Check Out' : 'Check In',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 25),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'ATTENDANCE HISTORY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceHistory() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      child: Column(
        children: _attendanceHistory.map((record) => _buildHistoryItem(record)).toList(),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> record) {
    Color statusColor;
    switch (record['status']) {
      case 'Present':
        statusColor = const Color(0xFF4CAF50);
        break;
      case 'Off':
        statusColor = Colors.orange;
        break;
      case 'Absent':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record['date'],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1A2744)),
                ),
                const SizedBox(height: 4),
                Text(
                  'In: ${record['checkIn']} | Out: ${record['checkOut']}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              record['status'],
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
