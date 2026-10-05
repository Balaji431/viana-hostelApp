import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodayPunchSummary {
  final bool hasCheckIn;
  final String? checkInTime;
  final bool hasCheckOut;
  final String? lastCheckOutTime;
  final int totalPunchesToday;
  final String currentActionType; // 'IN' (Check-In) or 'OUT' (Check-Out)

  const TodayPunchSummary({
    required this.hasCheckIn,
    this.checkInTime,
    required this.hasCheckOut,
    this.lastCheckOutTime,
    required this.totalPunchesToday,
    required this.currentActionType,
  });
}

class AttendancePunchService {
  static const String _enrolledPrefix = 'face_enrolled_';
  static const String _imagePathPrefix = 'face_image_path_';
  static const String _punchesPrefix = 'face_punches_';
  static const String _allHistoryPrefix = 'face_all_history_';

  /// Check if student's face embedding / image is registered
  static Future<bool> isFaceEnrolled(String username) async {
    if (username.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_enrolledPrefix$username') ?? false;
  }

  /// Mark student's face as registered
  static Future<void> setFaceEnrolled(String username, {String? imagePath}) async {
    if (username.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_enrolledPrefix$username', true);
    if (imagePath != null && imagePath.isNotEmpty) {
      await prefs.setString('$_imagePathPrefix$username', imagePath);
    }
  }

  /// Get today's punch summary (Check-in time, Last Check-out time, next action)
  static Future<TodayPunchSummary> getTodayPunchSummary(String username) async {
    if (username.isEmpty) {
      return const TodayPunchSummary(
        hasCheckIn: false,
        hasCheckOut: false,
        totalPunchesToday: 0,
        currentActionType: 'IN',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final todayKey = '$_punchesPrefix${username}_${DateFormat('yyyyMMdd').format(DateTime.now())}';
    final rawList = prefs.getStringList(todayKey) ?? [];

    if (rawList.isEmpty) {
      return const TodayPunchSummary(
        hasCheckIn: false,
        hasCheckOut: false,
        totalPunchesToday: 0,
        currentActionType: 'IN',
      );
    }

    // First punch is Check-In
    final firstPunch = jsonDecode(rawList.first) as Map<String, dynamic>;
    final checkInTime = firstPunch['time'] as String?;

    String? lastCheckOutTime;
    bool hasCheckOut = false;

    if (rawList.length > 1) {
      final lastPunch = jsonDecode(rawList.last) as Map<String, dynamic>;
      lastCheckOutTime = lastPunch['time'] as String?;
      hasCheckOut = true;
    }

    return TodayPunchSummary(
      hasCheckIn: true,
      checkInTime: checkInTime,
      hasCheckOut: hasCheckOut,
      lastCheckOutTime: lastCheckOutTime,
      totalPunchesToday: rawList.length,
      currentActionType: rawList.isEmpty ? 'IN' : 'OUT',
    );
  }

  /// Record a punch (Auto-determines IN for 1st punch, OUT for subsequent punches)
  static Future<Map<String, dynamic>> recordPunch({
    required String username,
    required String studentName,
    required String registerNumber,
    String? sessionName,
    String? referenceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayKey = '$_punchesPrefix${username}_${DateFormat('yyyyMMdd').format(now)}';
    final rawList = prefs.getStringList(todayKey) ?? [];

    final isFirstPunch = rawList.isEmpty;
    final punchType = isFirstPunch ? 'IN' : 'OUT';
    final timeFormatted = DateFormat('h:mm a').format(now);
    final dateFormatted = DateFormat('EEE, d MMM yyyy').format(now);

    final punchRecord = {
      'type': punchType,
      'time': timeFormatted,
      'date': dateFormatted,
      'timestamp': now.millisecondsSinceEpoch,
      'studentName': studentName,
      'registerNumber': registerNumber,
      'session': sessionName ?? 'Evening Roll Call',
      'referenceId': referenceId ?? 'PUNCH-${now.millisecondsSinceEpoch.toString().substring(6)}',
      'status': 'Verified',
      'method': 'Face Biometric',
    };

    rawList.add(jsonEncode(punchRecord));
    await prefs.setStringList(todayKey, rawList);

    // Also append to master all-history list
    final masterKey = '$_allHistoryPrefix$username';
    final masterList = prefs.getStringList(masterKey) ?? [];
    masterList.insert(0, jsonEncode(punchRecord)); // Latest first
    if (masterList.length > 100) {
      masterList.removeRange(100, masterList.length);
    }
    await prefs.setStringList(masterKey, masterList);

    // Get first check-in and last check-out
    final firstPunch = jsonDecode(rawList.first) as Map<String, dynamic>;
    final firstCheckIn = firstPunch['time'] as String?;
    final lastCheckOut = rawList.length > 1 ? timeFormatted : null;

    return {
      'punchType': punchType,
      'isCheckIn': isFirstPunch,
      'timeFormatted': timeFormatted,
      'dateFormatted': dateFormatted,
      'firstCheckIn': firstCheckIn,
      'lastCheckOut': lastCheckOut,
      'totalPunchesToday': rawList.length,
    };
  }

  /// Get all historical punch logs for a student
  static Future<List<Map<String, dynamic>>> getAllPunchLogs(String username) async {
    if (username.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final masterKey = '$_allHistoryPrefix$username';
    final masterList = prefs.getStringList(masterKey) ?? [];

    return masterList.map((item) {
      try {
        return jsonDecode(item) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((item) => item.isNotEmpty).toList();
  }

  /// Get punch timestamps (check-in and check-out) for a specific username and date
  static Future<Map<String, String?>> getPunchTimesForDate(String username, DateTime date) async {
    if (username.isEmpty) return {'checkIn': null, 'checkOut': null};
    final prefs = await SharedPreferences.getInstance();
    final dateKey = '$_punchesPrefix${username}_${DateFormat('yyyyMMdd').format(date)}';
    final rawList = prefs.getStringList(dateKey) ?? [];

    if (rawList.isEmpty) {
      return {'checkIn': null, 'checkOut': null};
    }

    try {
      final firstPunch = jsonDecode(rawList.first) as Map<String, dynamic>;
      final checkInTime = firstPunch['time'] as String?;
      String? checkOutTime;
      if (rawList.length > 1) {
        final lastPunch = jsonDecode(rawList.last) as Map<String, dynamic>;
        checkOutTime = lastPunch['time'] as String?;
      }
      return {'checkIn': checkInTime, 'checkOut': checkOutTime};
    } catch (_) {
      return {'checkIn': null, 'checkOut': null};
    }
  }
}
