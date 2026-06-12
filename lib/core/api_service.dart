import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../shared/user_provider.dart';
import 'api_client.dart' as http;
import 'app_logger.dart';

class ApiService {
  // Simply change this single URL to switch between environments:

  static const String baseUrl = 'https://vstay.saveetha.com/api/';

  static String? currentUserId;
  static String? currentUsername;
  static String? currentUserRole;

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
    final cleanBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanEndpoint = endpoint.startsWith('/')
        ? endpoint.substring(1)
        : endpoint;
    return '$cleanBaseUrl/$cleanEndpoint';
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
        Uri.parse('$baseUrl/utils/report_error.php'),
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

  static Future<Map<String, dynamic>> getHostelHierarchy(int hostelId) async {
    return await getRequest('admin_v2/get_hostel_hierarchy.php?hostel_id=$hostelId');
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
    return await getRequest('allocation/get_paid_hostel_type.php?register_no=$registerNo');
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

  static Future<Map<String, dynamic>> getAllReports( ) async {
    return await getRequest('requests/get_all_reports.php');
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

  static Future<Map<String, dynamic>> updateRenewFee(Map<String, dynamic> feeData) async {
    return await postRequest('admin_v2/update_renew_fee.php', feeData);
  }

  static Future<Map<String, dynamic>> addRenewFee(Map<String, dynamic> feeData) async {
    return await postRequest('admin_v2/add_renew_fee.php', feeData);
  }

  static Future<Map<String, dynamic>> deleteRenewFee(int id) async {
    return await postRequest('admin_v2/delete_renew_fee.php', {'id': id});
  }

  static Future<Map<String, dynamic>> getRoomTypes() async {
    return await getRequest('student/get_room_types.php');
  }

  // ==================== ANNOUNCEMENTS & CATEGORIES ====================

  static Future<Map<String, dynamic>> getSystemStats() async {
    return await getRequest('warden/get_system_stats.php');
  }

  static Future<Map<String, dynamic>> getAnnouncements() async {
    return await getRequest('announcements/get_announcements.php');
  }

  static Future<Map<String, dynamic>> postAnnouncement(String title, String content) async {
    return await postRequest('announcements/add_announcement.php', {'title': title, 'content': content});
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

  static Future<Map<String, dynamic>> submitRoomChangeRequest({required int studentId, required String currentRoom, required String requestedRoom, required String reason, String? requestedRoomType}) async {
    final data = {'student_id': studentId, 'current_room': currentRoom, 'requested_room': requestedRoom, 'reason': reason};
    if (requestedRoomType != null) data['requested_room_type'] = requestedRoomType;
    return await postRequest('room_change_requests/submit_request.php', data);
  }

  static Future<Map<String, dynamic>> updateRoomChangeRequest({required String requestId, required String status, required int wardenId, String? remarks}) async {
    return await postRequest('room_change_requests/update_request.php', {'request_id': requestId, 'status': status, 'warden_id': wardenId, 'remarks': remarks});
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

  static Future<Map<String, dynamic>> getAvailableRooms({String? campus, int? hostelId, String? floor, String? roomType, String? facility, double? maxAmount, bool vacantOnly = false}) async {
    final queryParams = <String, String>{};
    if (campus != null) queryParams['campus'] = campus;
    if (hostelId != null) queryParams['hostel_id'] = hostelId.toString();
    if (floor != null) queryParams['floor'] = floor;
    if (roomType != null) queryParams['room_type'] = roomType;
    if (facility != null) queryParams['facility'] = facility;
    if (maxAmount != null) queryParams['max_amount'] = maxAmount.toString();
    if (vacantOnly) queryParams['vacant_only'] = 'true';

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
      AppLogger.info("Marking messages as read: $requestId");
      final response = await http.post(
        Uri.parse('$baseUrl/chat/mark_read.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'request_id': requestId,
          'user_id': userId,
        }),
      );
      AppLogger.response("Mark read: ${response.statusCode}");
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error("Mark read error: $e");
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // ==================== CHAT MESSAGE STATUS APIS ====================

  // Mark messages as delivered when user opens chat
  static Future<Map<String, dynamic>> markDelivered(String requestId, String userId) async {
    try {
      AppLogger.info("Marking messages as delivered: $requestId");
      final response = await http.post(
        Uri.parse('$baseUrl/chat/mark_delivered.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'request_id': requestId,
          'user_id': userId,
        }),
      );
      AppLogger.response("Mark delivered: ${response.statusCode}");
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error("Mark delivered error: $e");
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // Mark messages as seen when user reads them
  static Future<Map<String, dynamic>> markSeen(String requestId, String userId) async {
    try {
      AppLogger.info("Marking messages as seen: $requestId");
      final response = await http.post(
        Uri.parse('$baseUrl/chat/mark_seen.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'request_id': requestId,
          'user_id': userId,
        }),
      );
      AppLogger.response("Mark seen: ${response.statusCode}");
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error("Mark seen error: $e");
      return {"success": false, "message": "Network error: $e"};
    }
  }

  // Update user last seen (for online status)
  static Future<void> updateLastSeen(String userId) async {
    try {
      AppLogger.info("Updating last seen: $userId");
      await http.post(
        Uri.parse('$baseUrl/chat/update_last_seen.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_id': userId}),
      );
      AppLogger.info("Last seen updated");
    } catch (e) {
      AppLogger.error("Update last seen error: $e");
    }
  }

  // Get user online/offline status
  static Future<Map<String, dynamic>> getUserStatus(String userId) async {
    try {
      AppLogger.info("Getting user status: $userId");
      final response = await http.get(
        Uri.parse('$baseUrl/chat/get_user_status.php?user_id=$userId'),
      );
      AppLogger.response("User status: ${response.statusCode}");
      return json.decode(response.body);
    } catch (e) {
      AppLogger.error("Get user status error: $e");
      return {"success": false, "status": "offline"};
    }
  }

  // ==================== COMMON HELPERS ====================

  static Future<Map<String, dynamic>> getRequest(String endpoint) async {
    if (baseUrl.isEmpty) {
      return {'success': false, 'message': 'API not initialized'};
    }
    try {
      final url = _buildUrl(endpoint);
      AppLogger.request("GET $url");
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      AppLogger.response("Status: ${response.statusCode}");
      
      if (response.statusCode != 200) {
        return {'success': false, 'message': 'Server error: ${response.statusCode}'};
      }
      
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Empty response from server'};
      }
      
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("GET error: $e");
      return {'success': false, 'message': 'Connection Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> postRequest(String endpoint, Map<String, dynamic> data) async {
    try {
      final url = _buildUrl(endpoint);
      AppLogger.request("POST $url");
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'HostelApp/1.0',
        },
        body: jsonEncode(data),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );
      AppLogger.response("Status: ${response.statusCode}");
      
      if (response.statusCode != 200) {
        return {'success': false, 'message': 'Server error: ${response.statusCode}'};
      }
      
      if (response.body.isEmpty) {
        return {'success': false, 'message': 'Server returned empty response'};
      }
      
      return jsonDecode(response.body);
    } catch (e) {
      AppLogger.error("POST error: $e");
      return {'success': false, 'message': 'Connection Error: $e'};
    }
  }
}
