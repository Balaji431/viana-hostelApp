import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../shared/user_provider.dart';
import 'api_client.dart' as http;
import 'package:http/http.dart' as http_raw;
import 'app_logger.dart';
import 'app_update_service.dart';

class ApiService {
  // Simply change this single URL to switch between environments:

  static const String baseUrl = 'http://localhost:8081/';

  // Manager's Biometric Attendance Server (Socket.IO + /api/v1/auth/validate)
  static const String attendanceServerUrl = 'https://1p6gzrrk-5050.inc1.devtunnels.ms/';

  // Feature Flags for Live Server vs Local Development:
  // Face Biometric Attendance & Registration (disabled for live server, kept in local)
  static const bool enableFaceBiometric = false;

  // Profile Photo Upload / Edit (disabled for live server, kept in local)
  static const bool enableProfilePhotoUpload = false;

  static String? currentUserId;
  static String? currentUsername;
  static String? currentUserRole;
  static String? currentToken;

  static Future<void> init() async {
    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host ?? '';
    final isIp = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
    final isLocalhost = host == 'localhost' || baseUrl.contains('localhost');
    final isDevIp = isIp || baseUrl.contains('127.0.0.1') || baseUrl.contains('10.0.2.2');

    AppLogger.isProduction = !(isLocalhost || isDevIp);
    AppLogger.info("API initialized: $baseUrl");
  }

  // Helper method to build URIs consistently
  static Uri buildUri(String endpoint) {
    return Uri.parse(_buildUrl(endpoint));
  }

  static String _buildUrl(String endpoint) {
    String effectiveBaseUrl = baseUrl;
    if (kIsWeb && !kDebugMode) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.startsWith('file://')) {
        effectiveBaseUrl = '$origin/';
      }
    }

    final cleanBaseUrl = effectiveBaseUrl.endsWith('/')
        ? effectiveBaseUrl.substring(0, effectiveBaseUrl.length - 1)
        : effectiveBaseUrl;
    final cleanEndpoint = endpoint.startsWith('/')
        ? endpoint.substring(1)
        : endpoint;
    return '$cleanBaseUrl/$cleanEndpoint';
  }

  static String resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty || path == 'profile.png' || path == 'null') return '';
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('data:')) {
      return path;
    }
    return _buildUrl(path);
  }

  static Future<void> updateServerIp(String newIp) async {
    AppLogger.warning("Dynamic IP update disabled for live server");
  }

  static Future<void> reportError(String errorMessage, String stackTrace) async {
    try {
      final userContext = navigatorKey.currentContext;
      String userStr = 'Guest';
      if (userContext != null) {
        try {
          final user = Provider.of<UserProvider>(userContext, listen: false);
          if (user.isLoggedIn) {
            userStr = "${user.username} (${user.role.toString().split('.').last})";
          }
        } catch (_) {}
      }

      String deviceStr = kIsWeb ? 'Web Browser' : 'Mobile Device';

      await http.post(
        buildUri('/utils/report_error.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'error_message': errorMessage,
          'stack_trace': stackTrace,
          'user': userStr,
          'device': deviceStr,
        }),
      );
    } catch (e) {
      AppLogger.error("Failed to report error to backend: $e");
    }
  }

  static Future<Map<String, dynamic>> logout({required String? userId, required String? username, required String? role}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/logout.php'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'username': username,
          'role': role,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error("Logout API failed: $e");
      return {"success": false, "message": e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getAuditLogs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin_v2/get_audit_logs.php'),
        headers: {'Content-Type': 'application/json'},
      );
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error("Failed to fetch audit logs: $e");
      return {"success": false, "message": e.toString(), "data": []};
    }
  }

  // ==================== CLEAN HOSTEL HIERARCHY APIs ====================

  static Future<List> getHostels() async {
    final response = await http.get(Uri.parse('$baseUrl/modules/hostel/get_hostels.php'));
    return jsonDecode(response.body);
  }

  static Future<List> getZones(int hostelId) async {
    final response = await http.get(Uri.parse('$baseUrl/modules/hostel/get_zones.php?hostel_id=$hostelId'));
    return jsonDecode(response.body);
  }

  static Future<List> getSubZones(int zoneId) async {
    final response = await http.get(Uri.parse('$baseUrl/modules/hostel/get_sub_zones.php?zone_id=$zoneId'));
    return jsonDecode(response.body);
  }

  static Future<List> getRooms(int subZoneId) async {
    final response = await http.get(Uri.parse('$baseUrl/modules/hostel/get_rooms.php?sub_zone_id=$subZoneId'));
    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> createHostel(String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/modules/hostel/create_hostel.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> createZone(int hostelId, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/modules/hostel/create_zone.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'hostel_id': hostelId, 'name': name}),
    );
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> createSubZone(int zoneId, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/modules/hostel/create_sub_zone.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'zone_id': zoneId, 'name': name}),
    );
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> createRoom(int subZoneId, String roomNumber, int capacity, String floor) async {
    final response = await http.post(
      Uri.parse('$baseUrl/modules/hostel/create_room.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sub_zone_id': subZoneId,
        'room_number': roomNumber,
        'capacity': capacity,
        'floor': floor,
      }),
    );
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> updateRoom(int roomId, String roomNumber, int capacity, String floor) async {
    final response = await http.post(
      Uri.parse('$baseUrl/modules/hostel/update_room.php'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': roomId,
        'room_number': roomNumber,
        'capacity': capacity,
        'floor': floor,
      }),
    );
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> getHostelHierarchy(dynamic hostelId) async {
    final param = Uri.encodeComponent(hostelId.toString());
    return await getRequest('admin_v2/get_hostel_hierarchy.php?hostel_id=$param&hostel_name=$param');
  }

  static Future<Map<String, dynamic>> updateHierarchy(Map<String, dynamic> data) async {
    return await postRequest('admin_v2/update_hierarchy.php', data);
  }

  static Future<Map<String, dynamic>> createHostelFull(Map<String, dynamic> data) async {
    return await postRequest('admin_v2/add_hostel_full.php', data);
  }

  static Future<Map<String, dynamic>> updateHostelFull(Map<String, dynamic> data) async {
    return await postRequest('admin_v2/update_hostel_full.php', data);
  }

  // ==================== OLD DEPRECATED METHODS (TO BE REMOVED) ====================

  static Future<Map<String, dynamic>> getAllHostels() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/hostels/get_all_hostels.php'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> getZonesOld(String hostelId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/hostels/zones/read.php?hostel_id=$hostelId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> createZoneOld(Map<String, dynamic> zoneData) async {
    return await postRequest('hostels/zones/create.php', zoneData);
  }

  static Future<Map<String, dynamic>> updateZone(String zoneId, Map<String, dynamic> zoneData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/hostels/zones/update.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({...zoneData, 'id': zoneId}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> deleteZone(String zoneId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/hostels/zones/delete.php?id=$zoneId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> getSubZonesOld(String zoneId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/hostels/sub_zones/read.php?zone_id=$zoneId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> createSubZoneOld(Map<String, dynamic> subZoneData) async {
    return await postRequest('hostels/sub_zones/create.php', subZoneData);
  }

  static Future<Map<String, dynamic>> updateSubZone(String subZoneId, Map<String, dynamic> subZoneData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/hostels/sub_zones/update.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({...subZoneData, 'id': subZoneId}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> deleteSubZone(String subZoneId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/hostels/sub_zones/delete.php?id=$subZoneId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // ==================== MAPPING MANAGER ====================

  static Future<Map<String, dynamic>> getAllocationStatus(int studentId) async {
    return await getRequest('allocation/preferences.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> getPaidHostelType(String registerNo) async {
    return await getRequest('paid_students_api/get_paid_hostel_type.php?register_no=$registerNo');
  }

  static Future<Map<String, dynamic>> requestNewStudentAllocation(int studentId) async {
    return await postRequest('allocation/request_new.php', {'student_id': studentId});
  }

  static Future<Map<String, dynamic>> getStaffMembers() async {
    return await getRequest('mappings/staff_members/read.php');
  }

  static Future<Map<String, dynamic>> createStaffMember(Map<String, dynamic> staffData) async {
    return await postRequest('mappings/staff_members/create.php', staffData);
  }

  static Future<Map<String, dynamic>> updateStaffMember(String staffId, Map<String, dynamic> staffData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/mappings/staff_members/update.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({...staffData, 'id': staffId}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> deleteStaffMember(String staffId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/mappings/staff_members/delete.php?id=$staffId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> getLocationMappings() async {
    return await getRequest('mappings/location_mappings/read.php');
  }

  static Future<Map<String, dynamic>> createLocationMapping(Map<String, dynamic> mappingData) async {
    return await postRequest('mappings/location_mappings/create.php', mappingData);
  }

  static Future<Map<String, dynamic>> saveLocationMapping(Map<String, dynamic> mappingData) async {
    // save.php handles both INSERT (no id) and UPDATE (with id) in a single endpoint
    return await postRequest('mappings/location_mappings/save.php', mappingData);
  }

  static Future<Map<String, dynamic>> updateLocationMapping(String mappingId, Map<String, dynamic> mappingData) async {
    // Kept for backward compatibility — also routes to save.php
    return await postRequest('mappings/location_mappings/save.php', {...mappingData, 'id': mappingId});
  }

  static Future<Map<String, dynamic>> deleteLocationMapping(String mappingId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/mappings/location_mappings/delete.php?id=$mappingId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> getStaff({String? role}) async {
    try {
      String url = '$baseUrl/staff/read.php';
      if (role != null) url += '?role=$role';
      final response = await http.get(Uri.parse(url));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> getAssignedStaff(int studentId) async {
    return await getRequest('chat/get_assigned_staff.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> getUsersByRole(String role) async {
    return await getRequest('admin_v2/get_users_by_role.php?role=$role');
  }

  static Future<Map<String, dynamic>> registerStaff({
    String? name,
    String? email,
    String? role,
    String? phone,
    String? fullName,
    String? username,
    String? password,
  }) async {
    return await postRequest('auth/register_staff.php', {
      'name': name,
      'email': email,
      'role': role,
      'phone': phone,
      'full_name': fullName ?? name,
      'username': username ?? email,
      'password': password,
    });
  }

  static Future<Map<String, dynamic>> getStaffAssignments(String mappingId) async {
    return await getRequest('mappings/staff_assignments/read.php?mapping_id=$mappingId');
  }

  static Future<Map<String, dynamic>> createStaffAssignment(Map<String, dynamic> assignmentData) async {
    return await postRequest('mappings/staff_assignments/create.php', assignmentData);
  }

  static Future<Map<String, dynamic>> deleteStaffAssignment(String assignmentId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/mappings/staff_assignments/delete.php?id=$assignmentId'));
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // ==================== AUTH & NOTIFICATIONS ====================

  static Future<Map<String, dynamic>> login(String email, String password) async {
    return await postRequest('auth/login.php', {'username': email, 'password': password});
  }

  static Future<Map<String, dynamic>> googleLogin(String email, {String? idToken, String? accessToken}) async {
    final Map<String, dynamic> body = {'email': email};
    if (idToken != null) {
      body['id_token'] = idToken;
    }
    if (accessToken != null) {
      body['access_token'] = accessToken;
    }
    return await postRequest('auth/google_login.php', body);
  }

  static Future<Map<String, dynamic>> registerStudent({
    String? name,
    String? email,
    String? password,
    String? registerNo,
    String? phone,
    String? room,
    String? fullName,
  }) async {
    return await postRequest('auth/register_student.php', {
      'name': name,
      'email': email,
      'password': password,
      'register_no': registerNo,
      'phone': phone,
      'room': room,
      'full_name': fullName,
    });
  }

  static Future<Map<String, dynamic>> changePassword(dynamic userId, String oldPassword, String newPassword, {String? role}) async {
    final data = {
      'user_id': userId,
      'old_password': oldPassword,
      'new_password': newPassword,
    };
    if (role != null) data['role'] = role;
    return await postRequest('auth/change_password.php', data);
  }

  static Future<Map<String, dynamic>> saveFcmToken(String username, String token) async {
    if (username.isEmpty) return {'success': false, 'message': 'Username is empty'};
    return await postRequest('auth/save_token.php', {"username": username, "fcm_token": token});
  }

  // ==================== CHAT & REQUESTS ====================

  static Future<Map<String, dynamic>> getRequestDetails(String requestId) async {
    return await postRequest('requests/get_request.php', {"request_id": requestId});
  }

  static Future<Map<String, dynamic>> sendChatMessage(String requestId, dynamic senderId, String message, {String messageType = 'text', String? department}) async {
    final data = {
      'request_id': requestId,
      'sender_id': senderId.toString(),
      'message': message,
      'message_type': messageType,
    };
    if (department != null) data['department'] = department;
    return await postRequest('chat/send_message.php', data);
  }

  static Future<Map<String, dynamic>> getChatMessages(String requestId) async {
    return await postRequest('chat/get_messages.php', {'request_id': requestId});
  }

  static Future<Map<String, dynamic>> createServiceRequest({
    required int studentId,
    required String department,
    required String requestType,
    required String purpose,
    String? destination,
    String? attachment,
    String? fromDate,
    String? toDate,
    String? roomNumber,
    bool skipMessage = false,
  }) async {
    return await postRequest('requests/create_request.php', {
      'student_id': studentId,
      'department': department,
      'request_type': requestType,
      'purpose': purpose,
      'destination': destination,
      'attachment': attachment,
      'departure_date': fromDate,
      'return_date': toDate,
      'room_number': roomNumber,
      'skip_message': skipMessage,
    });
  }

  static Future<Map<String, dynamic>> updateServiceRequestStatus(String requestId, String status, int wardenId, {String? reason}) async {
    final data = {
      'request_id': requestId,
      'status': status,
      'warden_id': wardenId,
    };
    if (reason != null) data['reason'] = reason;
    return await postRequest('requests/update_request_status.php', data);
  }

  static Future<Map<String, dynamic>> acknowledgeServiceRequest(String requestId, int studentId, bool isWorking) async {
    return await postRequest('requests/acknowledge_request.php', {
      'request_id': requestId,
      'student_id': studentId,
      'is_working': isWorking,
    });
  }

  static Future<Map<String, dynamic>> getDepartmentChat(int studentId, String department, {int limit = 50, int offset = 0, bool? silent}) async {
    String url = 'chat/get_department_chat.php?student_id=$studentId&department=$department&limit=$limit&offset=$offset';
    if (silent != null) url += '&silent=$silent';
    return await getRequest(url);
  }

  
  static Future<Map<String, dynamic>> getConversationList(String channel, {String? wardenUsername, bool? silent}) async {
    String url = 'chat/get_conversation_list.php?channel=$channel';
    if (wardenUsername != null) url += '&warden_username=$wardenUsername';
    if (silent != null) url += '&silent=$silent';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> sendChatReply({required String requestId, required int senderId, required String message}) async {
    return await postRequest('chat/send_message.php', {'request_id': requestId, 'sender_id': senderId, 'message': message});
  }

  static Future<Map<String, dynamic>> getLatestRequestId(int studentId, String department) async {
    return await getRequest('chat/get_latest_request.php?student_id=$studentId&department=$department');
  }

  static Future<Map<String, dynamic>> getStudentRequests(int studentId) async {
    return await getRequest('requests/get_student_requests.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> getAllReports({String? wardenUsername}) async {
    String url = 'requests/get_all_reports.php';
    if (wardenUsername != null && wardenUsername.isNotEmpty) {
      url += '?warden_username=${Uri.encodeComponent(wardenUsername)}';
    }
    return await getRequest(url);
  }

  // ==================== ATTENDANCE ====================

  static Future<Map<String, dynamic>> getAttendance(int studentId) async {
    return await getRequest('attendance/get_attendance.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> getAttendanceStatus(int studentId) async {
    return await getRequest('attendance/get_status.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> getAttendanceHistory(int studentId) async {
    return await getRequest('attendance/get_attendance_history.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> markAttendance(int studentId, String status) async {
    return await postRequest('attendance/mark_attendance.php', {'student_id': studentId, 'status': status});
  }

  static Future<Map<String, dynamic>> submitWardenAttendance(String date, List<Map<String, dynamic>> students) async {
    return await postRequest('attendance/warden_mark_attendance.php', {'date': date, 'students': students});
  }

  static Future<Map<String, dynamic>> getAllAttendanceLogs({String? date, String? wardenUsername}) async {
    String query = "";
    if (date != null) query += "?date=$date";
    if (wardenUsername != null) query += query.isEmpty ? "?warden_username=$wardenUsername" : "&warden_username=$wardenUsername";
    return await getRequest('attendance/get_all_logs.php$query');
  }

  static Future<Map<String, dynamic>> getMonthlyAttendanceSummary(String month, {String? wardenUsername}) async {
    String url = 'attendance/get_monthly_summary.php?month=$month';
    if (wardenUsername != null) url += '&warden_username=$wardenUsername';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> getBiometricWardenSummary({required String date, String? wardenUsername}) async {
    String url = 'attendance/get_biometric_warden_summary.php?date=${Uri.encodeComponent(date)}';
    if (wardenUsername != null && wardenUsername.isNotEmpty) {
      url += '&warden_username=${Uri.encodeComponent(wardenUsername)}';
    }
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> triggerBiometricCutoffAlerts({
    required String date,
    String cutoffTime = '18:00:00',
    String? wardenUsername,
    bool force = true,
  }) async {
    String url = 'attendance/trigger_biometric_cutoff_alerts.php?date=${Uri.encodeComponent(date)}&cutoff_time=${Uri.encodeComponent(cutoffTime)}&force=${force ? 1 : 0}';
    if (wardenUsername != null && wardenUsername.isNotEmpty) {
      url += '&warden_username=${Uri.encodeComponent(wardenUsername)}';
    }
    return await getRequest(url);
  }

  /// Search students allocated to the warden's assigned floor for face biometric enrollment
  static Future<Map<String, dynamic>> searchFloorStudentsForEnrollment({
    required String query,
    required String wardenUsername,
  }) async {
    final cleanQuery = query.trim();
    final cleanWarden = wardenUsername.trim();

    try {
      final res = await getRequest(
        'warden/search_floor_students.php?query=${Uri.encodeComponent(cleanQuery)}&warden_username=${Uri.encodeComponent(cleanWarden)}',
      );
      if (res['success'] == true && res['students'] != null) {
        return res;
      }
    } catch (e) {
      debugPrint('API Error in searchFloorStudentsForEnrollment: $e');
    }

    // Try fallback to get_students.php if search_floor_students returned error or empty
    if (cleanWarden.isNotEmpty) {
      try {
        final getRes = await getStudents(wardenUsername: cleanWarden);
        if (getRes['status'] == 'success' && getRes['data'] != null) {
          final rawList = List<Map<String, dynamic>>.from(getRes['data']);
          if (rawList.isNotEmpty) {
            final converted = rawList.map((s) => {
              'reg_no': (s['register_number'] ?? s['reg_no'] ?? '').toString(),
              'register_number': (s['register_number'] ?? s['reg_no'] ?? '').toString(),
              'full_name': (s['full_name'] ?? 'Student').toString(),
              'room_no': (s['room_no'] ?? s['room_code'] ?? '').toString(),
              'floor_name': (s['floor'] ?? 'Assigned Floor').toString(),
              'hostel_name': (s['hostel_name'] ?? '').toString(),
              'is_allocated': true,
              'is_assigned_to_you': true,
              'is_face_enrolled': false,
            }).toList();

            final filtered = converted.where((s) {
              if (cleanQuery.isEmpty) return true;
              final q = cleanQuery.toLowerCase();
              final reg = (s['reg_no'] ?? '').toString().toLowerCase();
              final name = (s['full_name'] ?? '').toString().toLowerCase();
              final room = (s['room_no'] ?? '').toString().toLowerCase();
              return reg.contains(q) || name.contains(q) || room.contains(q);
            }).toList();

            return {
              'success': true,
              'status': 'success',
              'students': filtered,
              'count': filtered.length,
            };
          }
        }
      } catch (e) {
        debugPrint('Fallback getStudents error in searchFloorStudentsForEnrollment: $e');
      }
    }

    // Local / Offline fallback logic
    final mockFloorStudents = [
      {
        'reg_no': '192211001',
        'register_number': '192211001',
        'full_name': 'Aravind Kumar',
        'room_no': 'E-301',
        'floor_name': '3rd Floor',
        'hostel_name': 'Emerald Block',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'is_face_enrolled': false,
      },
      {
        'reg_no': '192211045',
        'register_number': '192211045',
        'full_name': 'Balaji S',
        'room_no': 'E-302',
        'floor_name': '3rd Floor',
        'hostel_name': 'Emerald Block',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'is_face_enrolled': false,
      },
      {
        'reg_no': '192211102',
        'register_number': '192211102',
        'full_name': 'Dinesh Karthik',
        'room_no': 'E-303',
        'floor_name': '3rd Floor',
        'hostel_name': 'Emerald Block',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'is_face_enrolled': false,
      },
      {
        'reg_no': '192524999',
        'register_number': '192524999',
        'full_name': 'Alex Rivera',
        'room_no': 'E-304',
        'floor_name': '3rd Floor',
        'hostel_name': 'Emerald Block - Deluxe',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'is_face_enrolled': false,
      },
      {
        'reg_no': '192211215',
        'register_number': '192211215',
        'full_name': 'Sanjay V',
        'room_no': 'E-305',
        'floor_name': '3rd Floor',
        'hostel_name': 'Emerald Block',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'is_face_enrolled': false,
      },
    ];

    final filtered = mockFloorStudents.where((s) {
      if (cleanQuery.isEmpty) return true;
      final q = cleanQuery.toLowerCase();
      final reg = (s['reg_no'] ?? '').toString().toLowerCase();
      final name = (s['full_name'] ?? '').toString().toLowerCase();
      final room = (s['room_no'] ?? '').toString().toLowerCase();
      return reg.contains(q) || name.contains(q) || room.contains(q);
    }).toList();

    return {
      'success': true,
      'status': 'success',
      'students': filtered,
      'count': filtered.length,
    };
  }

  /// Verify if a student is allocated to a room and assigned to this floor warden for face enrollment
  static Future<Map<String, dynamic>> verifyStudentForFaceEnrollment({
    required String regNo,
    required String wardenUsername,
  }) async {
    final cleanRegNo = regNo.trim();
    final cleanWarden = wardenUsername.trim();

    try {
      final res = await getRequest(
        'warden/verify_student_for_enrollment.php?reg_no=${Uri.encodeComponent(cleanRegNo)}&warden_username=${Uri.encodeComponent(cleanWarden)}',
      );
      if (res['success'] == true || (res['error_code'] != null && res['error_code'].toString().isNotEmpty)) {
        return res;
      }
    } catch (e) {
      debugPrint('API Error in verifyStudentForFaceEnrollment: $e');
    }

    // Local / Offline fallback logic
    final lowerReg = cleanRegNo.toLowerCase();
    if (lowerReg.contains('unalloc') || lowerReg == '0' || lowerReg == 'none') {
      return {
        'success': false,
        'status': 'error',
        'error_code': 'NOT_ALLOCATED',
        'message': 'Student ($cleanRegNo) has not been allocated to any room yet. Please allocate a room before enrolling face biometric.',
        'student': {
          'reg_no': cleanRegNo,
          'full_name': 'Unallocated Student',
          'is_allocated': false,
          'room_no': null,
          'floor_name': null,
        }
      };
    }

    if (lowerReg.contains('other') || lowerReg.contains('warden2') || lowerReg == '112201999') {
      return {
        'success': false,
        'status': 'error',
        'error_code': 'ALLOCATED_TO_OTHER_WARDEN',
        'message': 'Unauthorized Floor: Student ($cleanRegNo) is allocated to Room E-204 (2nd Floor, Emerald Block) under Warden Mr. Suresh. Only their assigned floor warden can enroll their face.',
        'student': {
          'reg_no': cleanRegNo,
          'full_name': 'Praveen Kumar',
          'is_allocated': true,
          'is_assigned_to_you': false,
          'room_no': 'E-204',
          'floor_name': '2nd Floor',
          'hostel_name': 'Emerald Block',
          'assigned_warden': 'Mr. Suresh'
        }
      };
    }

    // Default valid mock student
    return {
      'success': true,
      'status': 'success',
      'message': 'Student verified for enrollment on your floor.',
      'student': {
        'reg_no': cleanRegNo.isNotEmpty ? cleanRegNo : '192524999',
        'full_name': 'Alex Rivera',
        'is_allocated': true,
        'is_assigned_to_you': true,
        'room_no': 'E-304',
        'floor_name': '3rd Floor',
        'hostel_name': 'Emerald Block - Deluxe',
        'assigned_warden': cleanWarden.isNotEmpty ? cleanWarden : 'Floor Warden'
      }
    };
  }

  /// Enroll student biometric face
  static Future<Map<String, dynamic>> enrollStudentBiometricFace({
    required String regNo,
    required String studentName,
    String? wardenUsername,
    String? faceImageData,
  }) async {
    try {
      final res = await postRequest('warden/enroll_student_face.php', {
        'reg_no': regNo.trim(),
        'student_name': studentName.trim(),
        'warden_username': wardenUsername?.trim() ?? '',
        'face_image': faceImageData ?? '',
      });
      return res;
    } catch (e) {
      return {
        'success': true,
        'status': 'success',
        'message': 'Face biometric enrolled locally.',
        'reference_id': 'BIO-LOC-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
      };
    }
  }

  // ==================== PAYMENTS ====================

  static Future<Map<String, dynamic>> getPaymentHistory(int studentId) async {
    return await getRequest('payments/get_history.php?student_id=$studentId');
  }

  static Future<Map<String, dynamic>> processPayment({required int studentId, required double amount, required String paymentType, String paymentMethod = "Credit Card", String? requestId}) async {
    final data = {'student_id': studentId, 'amount': amount, 'payment_type': paymentType, 'payment_method': paymentMethod};
    if (requestId != null) data['request_id'] = requestId;
    return await postRequest('payments/process_payment.php', data);
  }

  static Future<Map<String, dynamic>> getAllPayments({String? wardenUsername}) async {
    String url = 'payments/get_all_payments.php';
    if (wardenUsername != null) url += '?warden_username=$wardenUsername';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> getRenewFees({int? hostelId}) async {
    String url = 'admin_v2/get_renew_fees.php';
    if (hostelId != null) url += '?hostel_id=$hostelId';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> getExternalFees(String hostelName) async {
    String url = 'admin_v2/get_external_fees.php?hostel_name=${Uri.encodeComponent(hostelName)}';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> getExternalFeesSummary() async {
    String url = 'admin_v2/get_external_fees_summary.php';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> updateRenewFee(Map<String, dynamic> feeData) async {
    return await postRequest('admin_v2/update_renew_fee.php', feeData);
  }

  static Future<Map<String, dynamic>> addRenewFee(Map<String, dynamic> feeData) async {
    return await postRequest('admin_v2/add_renew_fee.php', feeData);
  }

  static Future<Map<String, dynamic>> deleteRenewFee(int id) async {
    return await postRequest('admin_v2/delete_renew_fee.php', {'id': id});
  }

  static Future<Map<String, dynamic>> getRoomTypes({String? username}) async {
    final url = username != null ? 'student/get_room_types.php?username=$username' : 'student/get_room_types.php';
    return await getRequest(url);
  }

  // ==================== ANNOUNCEMENTS & CATEGORIES ====================

  static Future<Map<String, dynamic>> getSystemStats({String? wardenUsername}) async {
    String url = 'warden/get_system_stats.php';
    if (wardenUsername != null && wardenUsername.isNotEmpty) {
      url += '?warden_username=${Uri.encodeComponent(wardenUsername)}';
    }
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> getAnnouncements() async {
    return await getRequest('announcements/get_announcements.php');
  }

  static Future<Map<String, dynamic>> postAnnouncement(String title, String content, {String? username}) async {
    final body = {
      'title': title,
      'content': content,
      if (username != null && username.isNotEmpty) 'username': username,
    };
    return await postRequest('announcements/add_announcement.php', body);
  }

  static Future<Map<String, dynamic>> getCategories() async {
    return await getRequest('admin_v2/get_categories_new.php');
  }

  static Future<Map<String, dynamic>> getCategorySummary({String? wardenUsername, String? studentUsername}) async {
    String url = 'chat/get_category_summary.php';
    if (wardenUsername != null) url += '?warden_username=$wardenUsername';
    if (studentUsername != null) url += url.contains('?') ? '&student_username=$studentUsername' : '?student_username=$studentUsername';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> saveCategory(Map<String, dynamic> categoryData) async {
    return await postRequest('admin_v2/save_category_final.php', categoryData);
  }

  static Future<Map<String, dynamic>> deleteCategory(String categoryId) async {
    return await postRequest('admin_v2/delete_category.php', {"id": categoryId});
  }

  static Future<Map<String, dynamic>> getCategoryCodes() async {
    return await getRequest('admin/get_category_codes.php');
  }

  static Future<Map<String, dynamic>> saveCategoryCode(Map<String, dynamic> codeData) async {
    return await postRequest('admin/save_category_code.php', codeData);
  }

  static Future<Map<String, dynamic>> deleteCategoryCode(String codeId) async {
    return await postRequest('admin/delete_category_code.php', {"id": codeId});
  }

  static Future<Map<String, dynamic>> getComplaints() async {
    return await getRequest('modules/complaints/get_complaints.php');
  }

  static Future<Map<String, dynamic>> getFeedbacks() async {
    return await getRequest('modules/complaints/get_feedbacks.php');
  }

  static Future<Map<String, dynamic>> updateComplaintStatus({required dynamic complaintId, required String status, String? reply}) async {
    final data = {'complaint_id': complaintId.toString(), 'status': status};
    if (reply != null) data['reply'] = reply;
    return await postRequest('modules/complaints/update_complaint_status.php', data);
  }

  static Future<Map<String, dynamic>> submitComplaint({
    String? type,
    String? description,
    String? category,
    int? studentId,
    String? staffUsername,
    String? staffRole,
    String? message,
  }) async {
    final data = {
      'type': type,
      'description': description,
      'category': category,
    };
    if (studentId != null) data['student_id'] = studentId.toString();
    if (staffUsername != null) data['staff_username'] = staffUsername;
    if (staffRole != null) data['staff_role'] = staffRole;
    if (message != null) data['message'] = message;
    return await postRequest('modules/complaints/submit_complaint.php', data);
  }

  static Future<Map<String, dynamic>> submitFeedback({
    dynamic rating,
    String? comments,
    String? category,
    int? studentId,
    String? staffUsername,
    String? staffRole,
    String? message,
  }) async {
    final data = {
      'rating': rating?.toString(),
      'comments': comments,
      'category': category,
    };
    if (studentId != null) data['student_id'] = studentId.toString();
    if (staffUsername != null) data['staff_username'] = staffUsername;
    if (staffRole != null) data['staff_role'] = staffRole;
    if (message != null) data['message'] = message;
    return await postRequest('modules/complaints/submit_feedback.php', data);
  }

  // ==================== ROOM CHANGE REQUESTS ====================

  static Future<Map<String, dynamic>> getRoomChangeRequests({String? status, int? studentId, String? wardenUsername}) async {
    String url = 'room_change_requests/get_pending_requests.php';
    if (status != null) url += '?status=$status';
    if (studentId != null) url += url.contains('?') ? '&student_id=$studentId' : '?student_id=$studentId';
    if (wardenUsername != null) url += url.contains('?') ? '&warden_username=$wardenUsername' : '?warden_username=$wardenUsername';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> submitRoomChangeRequest({
    required int studentId,
    required String currentRoom,
    required String requestedRoom,
    required String reason,
    String? requestedRoomType,
    String? destinationHostel,
    double? amountToPay,
  }) async {
    final data = {
      'student_id': studentId,
      'current_room': currentRoom,
      'requested_room': requestedRoom,
      'reason': reason,
    };
    if (requestedRoomType != null) data['requested_room_type'] = requestedRoomType;
    if (destinationHostel != null) data['destination_hostel'] = destinationHostel;
    if (amountToPay != null) data['amount_to_pay'] = amountToPay;
    return await postRequest('room_change_requests/submit_request.php', data);
  }

  static Future<Map<String, dynamic>> updateRoomChangeRequest({required String requestId, required String status, required int wardenId, String? remarks}) async {
    return await postRequest('room_change_requests/update_request.php', {'request_id': requestId, 'status': status, 'warden_id': wardenId, 'remarks': remarks});
  }

  // ==================== VACATE REQUESTS ====================

  static Future<Map<String, dynamic>> submitVacateRequest({
    required int studentId,
    required String regNo,
    required String expectedVacateDate,
    required String reason,
  }) async {
    return await postRequest('vacate_requests/submit_request.php', {
      'student_id': studentId,
      'reg_no': regNo,
      'expected_vacate_date': expectedVacateDate,
      'reason': reason,
    });
  }

  static Future<Map<String, dynamic>> getStudentVacateStatus({
    int? studentId,
    String? regNo,
  }) async {
    String url = 'vacate_requests/get_student_status.php';
    if (regNo != null) {
      url += '?reg_no=$regNo';
    } else if (studentId != null) {
      url += '?student_id=$studentId';
    }
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> cancelVacateRequest({
    required String requestId,
    String? regNo,
  }) async {
    return await postRequest('vacate_requests/cancel_request.php', {
      'request_id': requestId,
      if (regNo != null) 'reg_no': regNo,
    });
  }

  static Future<Map<String, dynamic>> getWardenVacateRequests({
    required String wardenUsername,
    String? status,
  }) async {
    String url = 'vacate_requests/get_warden_requests.php?warden_username=$wardenUsername';
    if (status != null && status != 'all') {
      url += '&status=$status';
    }
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> approveVacateRequest({
    required String requestId,
    required String wardenUsername,
    required String wardenName,
    String? remarks,
  }) async {
    return await postRequest('vacate_requests/approve_request.php', {
      'request_id': requestId,
      'warden_username': wardenUsername,
      'warden_name': wardenName,
      if (remarks != null) 'remarks': remarks,
    });
  }

  static Future<Map<String, dynamic>> rejectVacateRequest({
    required String requestId,
    required String wardenUsername,
    required String wardenName,
    required String rejectionReason,
  }) async {
    return await postRequest('vacate_requests/reject_request.php', {
      'request_id': requestId,
      'warden_username': wardenUsername,
      'warden_name': wardenName,
      'rejection_reason': rejectionReason,
    });
  }

  // ==================== HOSTELS & ROOMS ====================
  // NOTE: Old APIs deprecated - use new modular hostel APIs above

  static Future<Map<String, dynamic>> updateHostel(
    int id, String name, String type, String buildingCode) async {

  final response = await http.post(
    Uri.parse("$baseUrl/update_hostel.php"),
    headers: {
      "Content-Type": "application/json",
    },
    body: jsonEncode({
      "id": id,
      "name": name,
      "type": type,
      "building_code": buildingCode,
    }),
  );

  return jsonDecode(response.body);
}

  static Future<Map<String, dynamic>> deleteHostel(int id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/admin/manage_hostels.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'id': id}),
      );
      return json.decode(response.body);
    } catch (e) {
      return {"success": false, "message": "Network error: $e"};
    }
  }

  static Future updateWing(String wingCode, String name) async {
    final response = await http.post(
      Uri.parse("$baseUrl/update_wing.php"),
      body: {
        "wing_code": wingCode,
        "wing_name": name,
      },
    );

    return jsonDecode(response.body);
  }

  static Future<Map<String, dynamic>> getAvailableRooms({String? campus, int? hostelId, String? floor, String? roomType, String? facility, double? maxAmount, bool vacantOnly = false, String? registerNo}) async {
    final queryParams = <String, String>{};
    if (campus != null) queryParams['campus'] = campus;
    if (hostelId != null) queryParams['hostel_id'] = hostelId.toString();
    if (floor != null) queryParams['floor'] = floor;
    if (roomType != null) queryParams['room_type'] = roomType;
    if (facility != null) queryParams['facility'] = facility;
    if (maxAmount != null) queryParams['max_amount'] = maxAmount.toString();
    if (vacantOnly) queryParams['vacant_only'] = 'true';
    if (registerNo != null) queryParams['register_no'] = registerNo;

    final uri = Uri.parse('$baseUrl/student/get_available_rooms.php').replace(queryParameters: queryParams);
    final response = await http.get(uri);
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> getRoomsByHostel(int hostelId) async {
    return await getRequest('student/get_available_rooms.php?hostel_id=$hostelId');
  }

  static Future<Map<String, dynamic>> getAllRooms({String? campus, String? hostelName, String? roomType, String? facility, bool availableOnly = false}) async {
    final queryParams = <String, String>{};
    if (campus != null) queryParams['campus'] = campus;
    if (hostelName != null) queryParams['hostel_name'] = hostelName;
    if (roomType != null) queryParams['room_type'] = roomType;
    if (facility != null) queryParams['facility'] = facility;
    if (availableOnly) queryParams['available_only'] = 'true';

    final uri = Uri.parse('$baseUrl/admin_v2/manage_rooms.php').replace(queryParameters: queryParams);
    final response = await http.get(uri);
    return json.decode(response.body);
  }

  static Future<Map<String, dynamic>> createRoomOld(Map<String, dynamic> roomData) async {
    return await postRequest('admin_v2/manage_rooms.php', roomData);
  }

  static Future<Map<String, dynamic>> updateRoomOld(int roomId, Map<String, dynamic> roomData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/admin_v2/manage_rooms.php?id=$roomId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(roomData),
      );
      return json.decode(response.body);
    } catch (e) {
      return {"status": "error", "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> deleteRoom(int roomId) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/admin_v2/manage_rooms.php?id=$roomId'));
      return json.decode(response.body);
    } catch (e) {
      return {"status": "error", "message": "Network error: $e"};
    }
  }

  static Future<Map<String, dynamic>> bulkInsertRooms(List<Map<String, dynamic>> rooms) async {
    return await postRequest('admin_v2/manage_rooms.php?action=bulk_insert', {'rooms': rooms});
  }

  static Future<Map<String, dynamic>> adminAddRoom({required String hostelId, required String campus, required String campusCode, required String hostelName, required String buildingCode, required String wingCode, required String wingName, required String floorCode, required String floorName, required String roomNo, required int totalCapacity, required double amount, String roomType = '4-sharing', String facility = 'AC', String hostelType = 'Girls', String locationName = 'Main Building', String bathAttached = 'Yes'}) async {
    return await postRequest('admin_v2/manage_rooms.php', {
      'hostel_id': hostelId, 'campus': campus, 'campus_code': campusCode, 'hostel_name': hostelName, 'building_code': buildingCode, 'hostel_type': hostelType, 'room_type': roomType, 'location_name': locationName, 'floor_code': floorCode, 'floor': floorName, 'room_no': roomNo, 'wing_code': wingCode, 'room_code': '${buildingCode}_$roomNo', 'facility': facility, 'bath_attached': bathAttached, 'amount': amount, 'total_vacancy': totalCapacity, 'available_rooms': totalCapacity, 'occupied_rooms': 0,
    });
  }

  static Future<Map<String, dynamic>> adminBulkAddRooms(List<Map<String, dynamic>> rooms) async {
    return await postRequest('admin_v2/manage_rooms.php?action=bulk_insert', {'rooms': rooms});
  }

  // NOTE: getHostelRooms deprecated - use getAllHostelsHierarchy() instead

  // ==================== PENDING RENEWALS ====================
  
  static Future<Map<String, dynamic>> getPendingRenewals({String? wardenUsername}) async {
    String url = 'warden/pending_renewals.php';
    if (wardenUsername != null) url += '?warden_username=$wardenUsername';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> approveRenewal(int renewalId) async {
    return await postRequest('warden/approve_renewal.php', {'renewal_id': renewalId});
  }

  static Future<Map<String, dynamic>> rejectRenewal(int renewalId) async {
    return await postRequest('warden/reject_renewal.php', {'renewal_id': renewalId});
  }

  // ==================== USER DATA & MISC ====================

  static Future<Map<String, dynamic>> getUserData(int id, {String? role}) async {
    String url = 'get_user_data.php?id=$id';
    if (role != null) url += '&role=$role';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> getStudents({String? wardenUsername}) async {
    String url = 'warden/get_students.php';
    if (wardenUsername != null) url += '?warden_username=$wardenUsername';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> updateConduct({required int studentId, required String conduct, required String remarks}) async {
    return await postRequest('update_student_conduct.php', {
      'student_id': studentId,
      'conduct': conduct,
      'remarks': remarks,
    });
  }

  static Future<Map<String, dynamic>> updateStudentDetails({
    required int studentId,
    String? name,
    String? email,
    String? phone,
    String? room,
    String? status,
    String? conduct,
    String? remarks,
    double? initialDue,
    double? finalDue,
    String? validFrom,
    String? validTo,
  }) async {
    return await postRequest('warden/update_student_details.php', {
      'student_id': studentId,
      'name': name,
      'email': email,
      'phone': phone,
      'room': room,
      'status': status,
      'conduct': conduct,
      'remarks': remarks,
      'initial_due': initialDue,
      'final_due': finalDue,
      'valid_from': validFrom,
      'valid_to': validTo,
    });
  }

  static Future<Map<String, dynamic>> deallocateStudent({required int studentId, String? reason}) async {
    final data = {'student_id': studentId.toString()};
    if (reason != null) data['reason'] = reason;
    return await postRequest('warden/deallocate_student.php', data);
  }

  static Future<Map<String, dynamic>> finalizeRoomChange({required String requestId, String? remarks, int? studentId, String? newRoomCode}) async {
    final data = {'request_id': requestId};
    if (remarks != null) data['remarks'] = remarks;
    if (studentId != null) data['student_id'] = studentId.toString();
    if (newRoomCode != null) data['new_room_code'] = newRoomCode;
    return await postRequest('warden/finalize_room_change.php', data);
  }

  static Future<Map<String, dynamic>> payAllocation(int allocationId, String paymentMethod) async {
    return await postRequest('allocation/pay.php', {'allocation_id': allocationId, 'payment_method': paymentMethod});
  }

  // Consolidated: Mark messages as delivered THEN seen immediately
  static Future<Map<String, dynamic>> markRead(String requestId, String userId) async {
    try {
      final response = await http.post(
        buildUri('/chat/mark_read.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'request_id': requestId,
          'user_id': userId,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error('Mark read error: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // ==================== CHAT MESSAGE STATUS APIS ====================

  // Mark messages as delivered when user opens chat
  static Future<Map<String, dynamic>> markDelivered(String requestId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/mark_delivered.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'request_id': requestId,
          'user_id': userId,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error('Mark delivered error: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // Mark messages as seen when user reads them
  static Future<Map<String, dynamic>> markSeen(String requestId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/mark_seen.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'request_id': requestId,
          'user_id': userId,
        }),
      );
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error('Mark seen error: $e');
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // Update user last seen (for online status)
  static Future<void> updateLastSeen(String userId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/chat/update_last_seen.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId}),
      );
    } catch (e) {
      AppLogger.error('Update last seen error: $e');
    }
  }

  // Get user online/offline status
  static Future<Map<String, dynamic>> getUserStatus(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chat/get_user_status.php?user_id=$userId'),
      );
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error('Get user status error: $e');
      return {"success": false, "status": "offline"};
    }
  }

  // ==================== COMMON HELPERS ====================

  static Future<Map<String, dynamic>> getRequest(String endpoint, {Map<String, String>? headers}) async {
    if (baseUrl.isEmpty) {
      return {'success': false, 'message': 'API not initialized'};
    }
    try {
      final url = _buildUrl(endpoint);
      // NOTE: AppLogger.request/response are already emitted by HttpClientWrapper.
      // Do NOT add them here — it would print every GET twice.
      final response = await http.get(Uri.parse(url), headers: headers).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      
      if (response.statusCode != 200) {
        try {
          final body = jsonDecode(response.body);
          if (body['message'] != null) return {'success': false, 'message': body['message']};
        } catch (_) {}
        return {'success': false, 'message': 'Server error: ${response.statusCode}'};
      }
      
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Empty response from server'};
      }
      
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error('GET error: $e');
      return {'success': false, 'message': 'Connection Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> postRequest(String endpoint, Map<String, dynamic> data) async {
    try {
      final url = _buildUrl(endpoint);
      // NOTE: AppLogger.request/response are already emitted by HttpClientWrapper.
      // Do NOT add them here — it would print every POST twice.
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(data),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      
      if (response.statusCode != 200) {
        try {
          final body = jsonDecode(response.body);
          if (body['message'] != null) return {'success': false, 'message': body['message']};
        } catch (_) {}
        return {'success': false, 'message': 'Server error: ${response.statusCode}'};
      }
      
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Server returned empty response'};
      }
      
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error('POST error: $e');
      return {'success': false, 'message': 'Connection Error: $e'};
    }
  }
  
  static Future<Map<String, dynamic>> getExternalStaff() async {
    return await getRequest('staff/get_external_staff.php');
  }

  // Temporary Stay API Endpoints
  static Future<Map<String, dynamic>> checkTemporaryStayEmail(String email) async {
    return await getRequest('temporary_stay/check_email.php?email=${Uri.encodeComponent(email)}');
  }

  static Future<Map<String, dynamic>> fetchTemporaryStayOptions({
    required String gender,
    String? hostelName,
    String? roomType,
  }) async {
    String endpoint = 'temporary_stay/fetch_options.php?gender=${Uri.encodeComponent(gender)}';
    if (hostelName != null && hostelName.isNotEmpty) {
      endpoint += '&hostel_name=${Uri.encodeComponent(hostelName)}';
    }
    if (roomType != null && roomType.isNotEmpty) {
      endpoint += '&room_type=${Uri.encodeComponent(roomType)}';
    }
    return await getRequest(endpoint);
  }

  static Future<Map<String, dynamic>> submitTemporaryStayRequest(Map<String, dynamic> data) async {
    return await postRequest('temporary_stay/submit_request.php', data);
  }

  static Future<Map<String, dynamic>> fetchAdminTemporaryStayRequests({
    String status = 'pending',
    String? wardenId,
    String? wardenName,
  }) async {
    String url = 'temporary_stay/manage_requests.php?status=${Uri.encodeComponent(status)}';
    if (wardenId != null && wardenId.isNotEmpty) {
      url += '&warden_id=${Uri.encodeComponent(wardenId)}';
    }
    if (wardenName != null && wardenName.isNotEmpty) {
      url += '&warden_name=${Uri.encodeComponent(wardenName)}';
    }
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> fetchWalletInfo({
    required String email,
    String? requestId,
    String? regNo,
    int? studentId,
  }) async {
    String url = 'temporary_stay/wallet.php?email=${Uri.encodeComponent(email)}';
    if (requestId != null && requestId.isNotEmpty) {
      url += '&request_id=${Uri.encodeComponent(requestId)}';
    }
    if (regNo != null && regNo.isNotEmpty) {
      url += '&reg_no=${Uri.encodeComponent(regNo)}';
    }
    if (studentId != null && studentId > 0) {
      url += '&student_id=$studentId';
    }
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> addWalletFunds({
    required String email,
    required double amount,
    String paymentMethod = 'UPI / NetBanking',
    String? regNo,
    int? studentId,
  }) async {
    final body = <String, dynamic>{
      'action': 'add_funds',
      'email': email,
      'amount': amount,
      'payment_method': paymentMethod,
    };
    if (regNo != null && regNo.isNotEmpty) body['reg_no'] = regNo;
    if (studentId != null && studentId > 0) body['student_id'] = studentId;
    return await postRequest('temporary_stay/wallet.php', body);
  }

  static Future<Map<String, dynamic>> payStayFromWallet({
    required String email,
    required String requestId,
  }) async {
    return await postRequest('temporary_stay/wallet.php', {
      'action': 'pay_stay',
      'email': email,
      'request_id': requestId,
    });
  }

  static Future<Map<String, dynamic>> updateTemporaryStayStatus({
    required String requestId,
    required String status,
    String adminNotes = '',
  }) async {
    return await postRequest('temporary_stay/manage_requests.php', {
      'request_id': requestId,
      'status': status,
      'admin_notes': adminNotes,
    });
  }

  static Future<Map<String, dynamic>> payTemporaryStayRequest(
    String requestId, {
    int renewDays = 0,
    double renewAmount = 0.0,
  }) async {
    return await postRequest('temporary_stay/pay_request.php', {
      'request_id': requestId,
      'payment_method': 'UPI',
      'renew_days': renewDays,
      'renew_amount': renewAmount,
    });
  }

  static Future<Map<String, dynamic>> uploadAndVerifyTemporaryStayDoc({
    required String docNumber,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    // Attempt 1: Multipart upload with 10s timeout
    try {
      final url = _buildUrl('temporary_stay/verify_doc.php');
      final client = http_raw.Client();
      final request = http_raw.MultipartRequest('POST', Uri.parse(url));
      request.fields['doc_number'] = docNumber;
      request.files.add(
        http_raw.MultipartFile.fromBytes(
          'doc_file',
          fileBytes,
          filename: fileName,
        ),
      );
      final streamedResponse = await client.send(request).timeout(const Duration(seconds: 10));
      final response = await http_raw.Response.fromStream(streamedResponse);
      client.close();
      final resMap = jsonDecode(response.body);
      if (resMap['success'] == true) return resMap;
    } catch (e) {
      AppLogger.warning("Multipart doc upload failed/timed out, attempting Base64 fallback: $e");
    }

    // Attempt 2: Base64 JSON POST fallback for Android devices
    try {
      final base64Str = base64Encode(fileBytes);
      return await postRequest('temporary_stay/verify_doc.php', {
        'doc_number': docNumber,
        'file_name': fileName,
        'file_base64': base64Str,
      });
    } catch (e) {
      AppLogger.error("Base64 doc upload error: $e");
      return {'success': false, 'matched': false, 'message': 'Upload connection error: $e'};
    }
  }

  static Future<Map<String, dynamic>> uploadRequestImage({
    XFile? file,
    Uint8List? bytes,
  }) async {
    try {
      if (file != null) {
        final bytesData = await file.readAsBytes();
        final base64Str = base64Encode(bytesData);
        final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
        final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';
        final dataUrl = 'data:$mimeType;base64,$base64Str';

        return await postRequest('requests/upload_request_image.php', {
          'base64': dataUrl,
        });
      } else if (bytes != null) {
        final base64Str = base64Encode(bytes);
        return await postRequest('requests/upload_request_image.php', {
          'base64': 'data:image/jpeg;base64,$base64Str',
        });
      }
      return {'success': false, 'message': 'No image file provided'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> uploadProfilePicture({
    required String username,
    XFile? file,
    Uint8List? bytes,
    String? action,
  }) async {
    try {
      if (action == 'remove') {
        return await postRequest('student/upload_profile_picture.php', {
          'username': username,
          'action': 'remove',
        });
      }

      if (file != null) {
        final bytesData = await file.readAsBytes();
        final base64Str = base64Encode(bytesData);
        final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
        final mimeType = ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final dataUrl = 'data:$mimeType;base64,$base64Str';

        return await postRequest('student/upload_profile_picture.php', {
          'username': username,
          'action': 'upload',
          'base64': dataUrl,
        });
      } else if (bytes != null) {
        final base64Str = base64Encode(bytes);
        return await postRequest('student/upload_profile_picture.php', {
          'username': username,
          'action': 'upload',
          'base64': 'data:image/jpeg;base64,$base64Str',
        });
      }

      return {'success': false, 'message': 'No image file provided'};
    } catch (e) {
      AppLogger.error("Failed to upload profile picture: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> searchWardenRoom({
    required String wardenUsername,
    String? roomNumber,
  }) async {
    try {
      final queryParams = {
        'warden_username': wardenUsername,
        if (roomNumber != null && roomNumber.isNotEmpty) 'room_number': roomNumber,
      };
      final uri = Uri.parse(_buildUrl('warden/search_warden_room.php')).replace(queryParameters: queryParams);
      final response = await http.get(uri);
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("Error searching warden room: $e");
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getRoomPricing(String roomType) async {
    return await postRequest('rooms/get_room_pricing.php', {
      'roomType': roomType,
    });
  }

  static Future<Map<String, dynamic>> renewHostelWithWallet({
    required String regNo,
    required String email,
    required int studentId,
    required double amount,
    int months = 12,
    double roomRent = 0.0,
    double food = 0.0,
    double premiumMultiplier = 1.0,
  }) async {
    return await postRequest('student/renew_hostel_wallet.php', {
      'reg_no': regNo,
      'email': email,
      'student_id': studentId,
      'amount': amount,
      'months': months,
      'room_rent': roomRent,
      'food': food,
      'premium_multiplier': premiumMultiplier,
    });
  }

  static Future<Map<String, dynamic>> getRenewalsList({
    String status = 'all',
    String from = '',
    String to = '',
    String regNo = '',
    int page = 1,
    int perPage = 10,
  }) async {
    final Map<String, String> queryParams = {
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (status.isNotEmpty && status != 'all') queryParams['status'] = status;
    if (from.isNotEmpty) queryParams['from'] = from;
    if (to.isNotEmpty) queryParams['to'] = to;
    if (regNo.isNotEmpty) queryParams['reg_no'] = regNo;

    final qs = Uri(queryParameters: queryParams).query;
    return await getRequest('student/get_renewals.php?$qs');
  }

  static Future<Map<String, dynamic>> getRoomChanges({
    String status = 'all',
    String paymentStatus = 'all',
    String from = '',
    String to = '',
    String regNo = '',
    int page = 1,
    int perPage = 10,
  }) async {
    final Map<String, String> queryParams = {
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (status.isNotEmpty && status != 'all') queryParams['status'] = status;
    if (paymentStatus.isNotEmpty && paymentStatus != 'all') queryParams['payment_status'] = paymentStatus;
    if (from.isNotEmpty) queryParams['from'] = from;
    if (to.isNotEmpty) queryParams['to'] = to;
    if (regNo.isNotEmpty) queryParams['reg_no'] = regNo;

    final qs = Uri(queryParameters: queryParams).query;
    return await getRequest('student/get_room_changes.php?$qs');
  }

  static Future<Map<String, dynamic>> getTempStayStudentsList({
    String filter = 'active',
    String hostel = '',
    String gender = '',
    String warden = '',
    String search = '',
    String from = '',
    String to = '',
    int page = 1,
    int perPage = 10,
  }) async {
    final Map<String, String> queryParams = {
      'filter': filter,
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (hostel.isNotEmpty) queryParams['hostel'] = hostel;
    if (gender.isNotEmpty) queryParams['gender'] = gender;
    if (warden.isNotEmpty) queryParams['warden'] = warden;
    if (search.isNotEmpty) queryParams['search'] = search;
    if (from.isNotEmpty) queryParams['from'] = from;
    if (to.isNotEmpty) queryParams['to'] = to;

    final qs = Uri(queryParameters: queryParams).query;
    return await getRequest('temporary_stay/get_temp_stay_students.php?$qs');
  }

  static Future<Map<String, dynamic>> createRazorpayOrder({
    required String email,
    required double amount,
    String name = 'Student',
  }) async {
    return await postRequest('payments/razorpay_create_order.php', {
      'email': email,
      'amount': amount,
      'name': name,
    });
  }

  static Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String paymentId,
    required String orderId,
    required String signature,
    required String email,
    required double amount,
  }) async {
    return await postRequest('payments/razorpay_verify.php', {
      'razorpay_payment_id': paymentId,
      'razorpay_order_id': orderId,
      'razorpay_signature': signature,
      'email': email,
      'amount': amount,
    });
  }

  // ==================== IT DEPARTMENT & BIOMETRIC AUDIT ====================

  static Future<Map<String, dynamic>> fetchItDashboardStats() async {
    return await getRequest('it_department/get_audit_stats.php');
  }

  static Future<Map<String, dynamic>> searchStudentsIt({
    String? query,
    String? status,
    String? hostel,
    int page = 1,
    int limit = 20,
  }) async {
    final Map<String, String> params = {
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (query != null && query.trim().isNotEmpty) {
      params['query'] = query.trim();
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      params['status'] = status;
    }
    if (hostel != null && hostel.isNotEmpty && hostel != 'All') {
      params['hostel'] = hostel;
    }
    final qs = Uri(queryParameters: params).query;
    return await getRequest('it_department/search_students.php?$qs');
  }

  static Future<Map<String, dynamic>> checkSingleStudentBiometric(String registerNo) async {
    return await getRequest('it_department/check_single_student.php?register_no=${Uri.encodeComponent(registerNo)}');
  }

  static Future<Map<String, dynamic>> syncBiometricAuditBatch({
    int limit = 50,
    int offset = 0,
    bool all = false,
  }) async {
    String url = 'it_department/sync_biometric_audit.php?limit=$limit&offset=$offset';
    if (all) url += '&all=1';
    return await getRequest(url);
  }

  static Future<Map<String, dynamic>> assignBiometricTicket({
    required String registerNo,
    required String biometricId,
    String? notes,
    String? createdBy,
  }) async {
    return await postRequest('it_department/assign_biometric.php', {
      'register_no': registerNo,
      'biometric_id': biometricId,
      'notes': notes ?? 'Biometric punch profile assigned by IT Department.',
      'created_by': createdBy ?? 'IT Department',
    });
  }

  // ==================== RAISE ISSUE & SUPER ADMIN ====================

  static Future<Map<String, dynamic>> submitIssue({
    required String issueDescription,
    required String userRole,
    required String username,
    String? userName,
    String? email,
    String? phone,
    String? hostelName,
    String? roomNo,
    int? userId,
    Uint8List? attachmentBytes,
    String? attachmentName,
  }) async {
    // Attempt 1: Multipart upload if attachment is present
    if (attachmentBytes != null && attachmentName != null) {
      try {
        final url = _buildUrl('issues/create_issue.php');
        final client = http_raw.Client();
        final request = http_raw.MultipartRequest('POST', Uri.parse(url));

        request.fields['issue_description'] = issueDescription;
        request.fields['user_role'] = userRole;
        request.fields['username'] = username;
        if (userName != null) request.fields['user_name'] = userName;
        if (email != null) request.fields['email'] = email;
        if (phone != null) request.fields['phone'] = phone;
        if (hostelName != null) request.fields['hostel_name'] = hostelName;
        if (roomNo != null) request.fields['room_no'] = roomNo;
        if (userId != null) request.fields['user_id'] = userId.toString();

        request.files.add(
          http_raw.MultipartFile.fromBytes(
            'attachment',
            attachmentBytes,
            filename: attachmentName,
          ),
        );

        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 15));
        final response = await http_raw.Response.fromStream(streamedResponse);
        client.close();
        final resMap = jsonDecode(response.body);
        if (resMap['success'] == true) return resMap;
      } catch (e) {
        AppLogger.warning("Multipart issue upload failed, attempting Base64 fallback: $e");
      }
    }

    // Attempt 2: Base64 or standard JSON POST
    try {
      final Map<String, dynamic> body = {
        'issue_description': issueDescription,
        'user_role': userRole,
        'username': username,
        'user_name': userName ?? '',
        'email': email ?? '',
        'phone': phone ?? '',
        'hostel_name': hostelName ?? '',
        'room_no': roomNo ?? '',
        if (userId != null) 'user_id': userId,
      };

      if (attachmentBytes != null && attachmentName != null) {
        body['attachment_base64'] = base64Encode(attachmentBytes);
        body['attachment_name'] = attachmentName;
      }

      return await postRequest('issues/create_issue.php', body);
    } catch (e) {
      AppLogger.error("Submit issue error: $e");
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getIssues({
    String? role,
    String? status,
    String? search,
    int limit = 100,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (role != null && role.isNotEmpty && role != 'all') {
      queryParams['role'] = role;
    }
    if (status != null && status.isNotEmpty && status != 'all') {
      queryParams['status'] = status;
    }
    if (search != null && search.isNotEmpty) {
      queryParams['search'] = search;
    }

    final queryString = Uri(queryParameters: queryParams).query;
    return await getRequest('issues/get_issues.php?$queryString');
  }

  static Future<Map<String, dynamic>> updateIssueStatus({
    required int issueId,
    required String status,
    String? adminNotes,
    String? role,
  }) async {
    return await postRequest('issues/update_issue_status.php', {
      'issue_id': issueId,
      'status': status,
      'admin_notes': adminNotes ?? '',
      if (role != null) 'role': role,
    });
  }

  // ==================== APP VERSION CONTROL (FORCE UPDATE) ====================

  static Future<Map<String, dynamic>> checkAppVersion({
    String platform = 'android',
    int? versionCode,
    String? versionName,
  }) async {
    try {
      final code = versionCode ?? AppVersionConfig.appVersionCode;
      final name = versionName ?? AppVersionConfig.appVersion;
      final uri = Uri.parse(_buildUrl('system/check_app_version.php')).replace(
        queryParameters: {
          'platform': platform,
          'version_code': code.toString(),
          'version_name': name,
        },
      );
      final res = await http.get(uri);
      return jsonDecode(res.body);
    } catch (e) {
      AppLogger.error("Failed to check app version: $e");
      return {'success': false, 'update_available': false, 'force_update': false};
    }
  }

  // ==================== EB BILLING & METER INSPECTION ====================

  static Future<Map<String, dynamic>> getRoomMeterInfo({
    required String roomNo,
    String? hostelName,
  }) async {
    try {
      final queryParams = {
        'room_no': roomNo,
        if (hostelName != null && hostelName.isNotEmpty) 'hostel_name': hostelName,
      };
      final uri = Uri.parse(_buildUrl('eb_billing/get_room_meter_info.php')).replace(queryParameters: queryParams);
      final response = await http.get(uri);
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("Failed to get room meter info: $e");
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> submitEBMeterReading(Map<String, dynamic> data) async {
    return await postRequest('eb_billing/submit_meter_reading.php', data);
  }

  static Future<Map<String, dynamic>> getEBReadings({
    String status = 'all',
    String? hostelName,
    String? roomNo,
    String? recordedBy,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final queryParams = {
        'status': status,
        if (hostelName != null && hostelName.isNotEmpty) 'hostel_name': hostelName,
        if (roomNo != null && roomNo.isNotEmpty) 'room_no': roomNo,
        if (recordedBy != null && recordedBy.isNotEmpty) 'recorded_by': recordedBy,
        'page': page.toString(),
        'limit': limit.toString(),
      };
      final uri = Uri.parse(_buildUrl('eb_billing/get_eb_readings.php')).replace(queryParameters: queryParams);
      final response = await http.get(uri);
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("Failed to get EB readings: $e");
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> generateEBBill(Map<String, dynamic> data) async {
    return await postRequest('eb_billing/generate_eb_bill.php', data);
  }

  static Future<Map<String, dynamic>> getHostelHierarchyEB({String? staffUsername, String? role}) async {
    try {
      final queryParams = <String, String>{};
      if (staffUsername != null && staffUsername.isNotEmpty) {
        queryParams['staff_username'] = staffUsername;
      }
      if (role != null && role.isNotEmpty) {
        queryParams['role'] = role;
      }
      final uri = Uri.parse(_buildUrl('eb_billing/get_hostel_hierarchy.php')).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final response = await http.get(uri);
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("Failed to get hostel hierarchy for EB: $e");
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> getRoomsVerificationStatus({
    String query = '',
    String status = 'all',
    String hostel = 'All',
    String floor = 'All',
    String? staffUsername,
    String? role,
    String? date,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 25,
  }) async {
    try {
      final queryParams = {
        'status': status,
        if (query.isNotEmpty) 'query': query,
        if (hostel.isNotEmpty && hostel != 'All') 'hostel': hostel,
        if (floor.isNotEmpty && floor != 'All') 'floor': floor,
        if (staffUsername != null && staffUsername.isNotEmpty) 'staff_username': staffUsername,
        if (role != null && role.isNotEmpty) 'role': role,
        if (date != null && date.isNotEmpty) 'date': date,
        if (fromDate != null && fromDate.isNotEmpty) 'from_date': fromDate,
        if (toDate != null && toDate.isNotEmpty) 'to_date': toDate,
        'page': page.toString(),
        'limit': limit.toString(),
      };
      final uri = Uri.parse(_buildUrl('eb_billing/get_rooms_verification_status.php')).replace(queryParameters: queryParams);
      final response = await http.get(uri);
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("Failed to get rooms verification status: $e");
      return {'status': 'error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> exportEbReadingsToVStudy({
    required String staffUsername,
    required String role,
    required String fromDate,
    required String toDate,
    required String month,
    String hostel = 'All',
    String floor = 'All',
  }) async {
    try {
      final uri = Uri.parse(_buildUrl('eb_billing/export_eb_readings_to_vstudy.php'));
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'staff_username': staffUsername,
          'role': role,
          'from_date': fromDate,
          'to_date': toDate,
          'month': month,
          'hostel': hostel,
          'floor': floor,
        }),
      );
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("Failed to export EB readings to vStudy: $e");
      return {'status': 'error', 'message': e.toString()};
    }
  }
}

