import 'package:intl/intl.dart';

/// Service providing standalone demo/mock data for testing & App Store review.
class DemoDataService {
  /// Demo Student User Profile with complete allocation and academic details
  static Map<String, dynamic> get demoStudentUser => {
    'id': 999999,
    'username': '192524999',
    'register_no': '192524999',
    'student_id': '192524999',
    'name': 'Alex Rivera (Demo)',
    'email': 'alex.rivera.demo@saveetha.com',
    'phone': '+91 98765 43210',
    'dob': '2004-05-15',
    'gender': 'Male',
    'address': '123, Green Valley Campus Rd, Chennai, TN 602105',
    'institution': 'SIMATS Engineering',
    'department': 'Computer Science & Engineering',
    'academic_year': '2024-2028',
    'year_of_study': '3rd Year',
    'role': 'student',
    'profile_image': '',
    
    // Room & Hostel Allocation Details
    'hostel_name': 'Emerald Block - Deluxe',
    'hostel_type': 'Boys',
    'room_number': 'E-304',
    'room_code': 'E304',
    'bed_number': 'Bed 2',
    'floor': '3rd Floor',
    'block': 'Block E',
    'room_type': '2-Sharing AC with Attached Bath',
    'allocation_status': 'Occupied',
    'check_in_date': '2024-07-01',
    'warden_name': 'Mr. K. Venkatesh',
    'warden_phone': '+91 94440 12345',
    'warden_email': 'warden.emerald@saveetha.com',
    
    // Fee and Validity
    'fee_status': 'Paid',
    'validity_end': '2027-05-31',
  };

  /// Generate 30 days of realistic demo attendance & biometric logs
  static List<Map<String, dynamic>> get demoAttendanceLogs {
    final now = DateTime.now();
    final List<Map<String, dynamic>> logs = [];
    final dateFormat = DateFormat('yyyy-MM-dd');

    for (int i = 0; i < 30; i++) {
      final date = now.subtract(Duration(days: i));
      final dateStr = dateFormat.format(date);
      final weekday = date.weekday;

      // Weekends: Saturday/Sunday
      if (weekday == DateTime.sunday) {
        logs.add({
          'id': 1000 + i,
          'student_id': 999999,
          'date': dateStr,
          'status': 'present',
          'in_time': '20:15:00',
          'out_time': '10:30:00',
          'source': 'Biometric Gate Sensor 01',
          'remarks': 'Weekend Outing / Return',
        });
      } else if (weekday == DateTime.saturday && i == 8) {
        logs.add({
          'id': 1000 + i,
          'student_id': 999999,
          'date': dateStr,
          'status': 'absent',
          'in_time': null,
          'out_time': null,
          'source': 'Portal',
          'remarks': 'Approved Home Leave',
        });
      } else {
        // Regular College Days
        logs.add({
          'id': 1000 + i,
          'student_id': 999999,
          'date': dateStr,
          'status': 'present',
          'in_time': '08:15:00',
          'out_time': '20:45:00',
          'source': 'Biometric Fingerprint Scanner - Block E',
          'remarks': 'Regular Hostel Check-in',
        });
      }
    }

    return logs;
  }

  /// Demo Settings Preset
  static Map<String, dynamic> get demoSettings => {
    'dark_mode': false,
    'wallpaper': 'classic_linen',
    'push_notifications': true,
    'biometric_lock': true,
    'auto_sync': true,
    'app_version': '1.0.0 (VStay Demo)',
  };
}