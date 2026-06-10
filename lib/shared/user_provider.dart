import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/notification_service.dart';
import '../core/api_service.dart';
import '../core/app_logger.dart';

enum UserRole { student, warden, admin, parent, maintenance, security, staff }

class UserProvider with ChangeNotifier {
  UserRole _role = UserRole.student;
  String _roleName = ""; // NEW: Stores dynamic role name (e.g. 'Electricity')
  bool _isLoggedIn = false; // Set to false to show login screen by default
  int? _dbId;
  String? _loginUsername; // NEW: The primary ID used for notifications
  String _userName = "User";
  String _studentId = ""; // Current Registration Number
  String _registerNo = "";
  String _email = "";
  String _phone = "";
  String _dob = "";
  String _address = "";
  String _institution = "";
  String _hostelName = "";
  String _roomNumber = "";
  String _roomCode = "";
  String _bedNo = "";
  String _roomAllocation = "";
  String _block = "";
  String _wing = "";
  String _roomType = "8-sharing"; // 8-sharing, 6-sharing, 4-sharing
  String _roomFacility = "";
  String _roomBathAttached = "";
  String _profilePic = "";
  DateTime _renewalDate = DateTime.now().add(const Duration(days: 365));
  DateTime _checkInDate = DateTime.now();
  bool get hasBadConduct => _conduct.toLowerCase() == 'poor';
  String _renewalStatus = 'Approved';
  String _conduct = 'Good';
  String _conductRemarks = '';
  
  // 🔥 PARENT PROPERTIES
  bool _isParent = false;
  int? _linkedStudentId;
  String _linkedStudentUsername = "";
  String _linkedStudentName = "";
  String _linkedStudentEmail = "";
  String _linkedStudentRoom = "";
  String _linkedStudentInstitution = "";
  String _linkedStudentHostel = "";
  String _linkedStudentProfilePic = "";
  
  DateTime? _lastRefreshTime;
  
  int? get dbId => _dbId;
  UserRole get role => _role;
  String get roleName => _roleName; // NEW: Accessor for dynamic role name
  bool get isLoggedIn => _isLoggedIn;
  String get userName => _userName;
  String get studentId => _studentId;
  String get registerNo => _registerNo;
  /// Returns the username used for API calls (login username for staff, register_no for students)
  String get username {
    // For staff/security/maintenance/warden/admin roles, _studentId/_registerNo may be empty
    // — fall back to the actual login username
    if (_studentId.isNotEmpty) return _studentId;
    if (_registerNo.isNotEmpty) return _registerNo;
    return _loginUsername ?? '';
  }
  String get email => _email;
  String get phone => _phone;
  String get dob => _dob;
  String get address => _address;
  String get institution => _institution;
  String get hostelName => _hostelName;
  String get roomNumber => _roomNumber;
  String get roomCode => _roomCode;
  String get bedNo => _bedNo;
  String get roomAllocation => _roomAllocation;
  String get block => _block;
  String get wing => _wing;
  String get fullRoomDetails => _roomNumber.isNotEmpty 
      ? "$_roomNumber, $_block, $_wing"
      : (_roomAllocation.isNotEmpty ? _roomAllocation : "$hostelName, Room: $roomNumber, Bed: $bedNo");
  String get roomType => _roomType;
  String get roomFacility => _roomFacility;
  String get roomBathAttached => _roomBathAttached;
  
  /// Get display name for room type
  /// e.g., "8-sharing" -> "Standard Room", "6-sharing" -> "Premium Room", "4-sharing" -> "Ultra Premium Room"
  String get roomTypeDisplay {
    if (_roomType == '4-sharing') return 'Ultra Premium Room';
    if (_roomType == '6-sharing') return 'Premium Room';
    return 'Standard Room'; // 8-sharing default
  }
  
  String get profilePic => _profilePic;
  
  DateTime get renewalDate => _renewalDate;
  DateTime get checkInDate => _checkInDate;
  String get renewalStatus => _renewalStatus;
  String get conduct => _conduct;
  String get conductRemarks => _conductRemarks;

  bool get isRoomAllocated {
    final String rNum = _roomNumber.trim().toUpperCase();
    final String rAlloc = _roomAllocation.trim().toUpperCase();
    
    if (rNum.isEmpty || rNum == "N/A" || rNum == "NONE" || rNum == "NULL") {
      if (rAlloc.isEmpty || rAlloc == "N/A" || rAlloc == "N/A, N/A, N/A" || rAlloc == "NONE" || rAlloc == "NULL") {
        return false;
      }
    }
    return true;
  }

  // 🔥 PARENT GETTERS
  bool get isParent => _isParent;
  int? get linkedStudentId => _linkedStudentId;
  String get linkedStudentUsername => _linkedStudentUsername;
  String get linkedStudentName => _linkedStudentName;
  String get linkedStudentEmail => _linkedStudentEmail;
  String get linkedStudentRoom => _linkedStudentRoom;
  String get linkedStudentInstitution => _linkedStudentInstitution;
  String get linkedStudentHostel => _linkedStudentHostel;
  String get linkedStudentProfilePic => _linkedStudentProfilePic;
  
  // 🔥 For parent, return linked student data instead of own data
  String get displayName => _isParent ? _linkedStudentName : _userName;
  String get displayRoom => _isParent ? _linkedStudentRoom : roomNumber;
  String get displayInstitution => _isParent ? _linkedStudentInstitution : _institution;
  String get displayHostel => _isParent ? _linkedStudentHostel : _hostelName;
  String get displayProfilePic => _isParent ? _linkedStudentProfilePic : _profilePic;
  String get displayStudentId => _isParent ? _linkedStudentUsername : studentId;

  void setRole(UserRole newRole) {
    _role = newRole;
    notifyListeners();
  }

  /// Parse room type from room_allocation string
  /// e.g., "Vaigai, Room: T32-F00-W01-R01, Bed: (6 IN 1)" -> "6-sharing"
  /// Priority: 1. room_type from backend, 2. Parsed from room_allocation, 3. Default "8-sharing"
  String _parseRoomType(String roomAllocation, String? backendRoomType) {
    // First priority: use room_type from backend if available
    if (backendRoomType != null && backendRoomType.isNotEmpty) {
      return backendRoomType;
    }
    
    // Second priority: parse from room_allocation
    if (roomAllocation.isNotEmpty) {
      // Match patterns like "(6 IN 1)", "(4 IN 1)", "(8 IN 1)" - case insensitive
      final pattern = RegExp(r'\((\d+)\s+IN\s+1\)', caseSensitive: false);
      final match = pattern.firstMatch(roomAllocation);
      if (match != null) {
        final capacity = match.group(1);
        if (capacity == '4') return '4-sharing';
        if (capacity == '6') return '6-sharing';
        if (capacity == '8') return '8-sharing';
      }
    }
    
    // Default fallback
    return '8-sharing';
  }

  DateTime _parseDate(dynamic date) {
    if (date == null || date == "" || date == "0000-00-00") return DateTime.now();
    try {
      String dateStr = date.toString();
      // Handle MySQL 8.0 invalid date strings like '2026-04-31'
      // DateTime.parse will fail for April 31. We try to catch this.
      return DateTime.parse(dateStr);
    } catch (e) {
      debugPrint("Invalid date detected: $date. Falling back to current date.");
      return DateTime.now();
    }
  }

  /// Force refresh user data from the database
  Future<void> refreshUserData() async {
    if (_dbId == null) return;
    
    final now = DateTime.now();
    if (_lastRefreshTime != null && now.difference(_lastRefreshTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastRefreshTime = now;
    
    try {
      AppLogger.info("Refreshing user data for ID: $_dbId");
      final response = await ApiService.getUserData(_dbId!, role: _isParent ? 'parent' : null);
      
      if (response['success'] == true && response['data'] != null) {
        final Map<String, dynamic> userData = Map<String, dynamic>.from(response['data']);
        
        // 1. Update local properties
        setUserData(userData);
        
        // 2. Update persistence cache so it survives restart
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', jsonEncode(userData));
        
        AppLogger.info("User data refreshed successfully from DB");
      }
    } catch (e) {
      AppLogger.error("Error refreshing data from DB: $e");
    }
  }

  void requestRenewal() {
    _renewalStatus = 'Pending';
    notifyListeners();
  }

  void approveRenewal() {
    _renewalStatus = 'Approved';
    notifyListeners();
  }

  Future<void> login(Map<String, dynamic> userData) async {
    final String roleStr = userData['role']?.toString().toLowerCase() ?? 'student';
    _roleName = roleStr;
    if (roleStr == 'admin') {
      _role = UserRole.admin;
    } else if (roleStr == 'warden') {
      _role = UserRole.warden;
    } else if (roleStr == 'parent') {
      _role = UserRole.parent;
      _isParent = true;
    } else if (roleStr == 'maintenance') {
      _role = UserRole.maintenance;
      _isParent = false;
    } else if (roleStr == 'security') {
      _role = UserRole.security;
      _isParent = false;
    } else if (roleStr == 'student') {
      _role = UserRole.student;
      _isParent = false;
    } else {
      // DYNAMIC ROLE (e.g. 'Electricity', 'Plumbing')
      _role = UserRole.staff;
      _isParent = false;
    }

    _dbId = int.tryParse(userData['id']?.toString() ?? "");
    _loginUsername = userData['username']?.toString() ?? userData['register_no']?.toString() ?? userData['parent_id']?.toString() ?? userData['email']?.toString() ?? "";
    _userName = userData['full_name']?.toString() ?? "User";
    _studentId = userData['register_no']?.toString() ?? userData['email']?.toString() ?? "";
    _registerNo = userData['register_no']?.toString() ?? "";
    _email = userData['email']?.toString() ?? "";
    AppLogger.currentUserEmail = _email;
    _phone = userData['phone']?.toString() ?? "";
    _dob = userData['dob']?.toString() ?? "";
    _address = userData['address']?.toString() ?? "";
    
    _institution = userData['institution']?.toString() ?? "";
    _hostelName = userData['hostel_name']?.toString() ?? "";
    _roomNumber = userData['room_no']?.toString() ?? "";
    _roomCode = userData['room_code']?.toString() ?? "";
    _bedNo = userData['bed_no']?.toString() ?? "";
    _block = userData['block']?.toString() ?? "";
    _wing = userData['wing']?.toString() ?? "";
    _roomAllocation = userData['room_allocation']?.toString() ?? "";
    // Parse room type from room_allocation (e.g., "Bed: (6 IN 1)" -> "6-sharing")
    _roomType = _parseRoomType(_roomAllocation, userData['room_type']?.toString());
    _roomFacility = userData['room_facility']?.toString() ?? "";
    _roomBathAttached = userData['room_bath_attached']?.toString() ?? "";
    _profilePic = userData['profile_pic']?.toString() ?? "";
    _conduct = userData['conduct']?.toString() ?? "Good";
    _conductRemarks = userData['conduct_remarks']?.toString() ?? "";
    _checkInDate = _parseDate(userData['valid_from']);
    _renewalDate = _parseDate(userData['valid_to']);

    // 🔥 PARENT ROLE: Handle linked student data
    if (_isParent) {
      _linkedStudentId = int.tryParse(userData['linked_student_id']?.toString() ?? "");
      _linkedStudentUsername = userData['linked_student_username']?.toString() ?? "";
      _linkedStudentName = userData['linked_student_name']?.toString() ?? "";
      _linkedStudentEmail = userData['linked_student_email']?.toString() ?? "";
      _linkedStudentRoom = userData['linked_student_room']?.toString() ?? "";
      _linkedStudentInstitution = userData['linked_student_institution']?.toString() ?? "";
      _linkedStudentHostel = userData['linked_student_hostel']?.toString() ?? "";
      _linkedStudentProfilePic = userData['linked_student_profile_pic']?.toString() ?? "";
      
      AppLogger.info("Parent login: $_userName, Student: $_linkedStudentName (ID: $_linkedStudentId)");
    } else {
      // Reset parent data for non-parent users
      _isParent = false;
      _linkedStudentId = null;
      _linkedStudentUsername = "";
      _linkedStudentName = "";
      _linkedStudentEmail = "";
      _linkedStudentRoom = "";
      _linkedStudentInstitution = "";
      _linkedStudentHostel = "";
      _linkedStudentProfilePic = "";
    }

    _isLoggedIn = true;
    
    // 🔥 SAVE FCM TOKEN TO BACKEND (Works for all users including parents)
    _saveFCMToken();
    
    // Persistence: Save data and current timestamp
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(userData));
    await prefs.setString('login_time', DateTime.now().toIso8601String());
    
    notifyListeners();
  }

  // 🔥 SAVE FCM TOKEN TO BACKEND
  Future<void> _saveFCMToken() async {
    try {
      // Use _loginUsername as the primary identifier (consistent with send_message.php logic)
      final String username = (_loginUsername != null && _loginUsername!.isNotEmpty) 
          ? _loginUsername! 
          : _registerNo;
          
      if (username.isNotEmpty && username != 'null') {
        final String? token = await NotificationService.getToken();
        if (token != null && token.isNotEmpty) {
          await NotificationService.saveTokenToBackend(username, token);
        }
      } else {
        AppLogger.error("Invalid username for FCM token save");
      }
    } catch (e) {
      AppLogger.error("Error saving FCM token: $e");
    }
  }

  Future<void> checkPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userDataStr = prefs.getString('user_data');
      final String? loginTimeStr = prefs.getString('login_time');

      if (userDataStr != null && loginTimeStr != null) {
        final DateTime loginTime = DateTime.parse(loginTimeStr);
        final DateTime now = DateTime.now();

        // Check if session is older than 7 days
        if (now.difference(loginTime).inDays < 7) {
          final Map<String, dynamic> userData = Map<String, dynamic>.from(jsonDecode(userDataStr));
          await login(userData); // Re-use login logic for consistency and safety
        } else {
          // Expired
          await logout();
        }
      }
    } catch (e) {
      AppLogger.error("Persistence error: $e");
      await logout(); // Safe side: clear on error
    }
  }

  void setUserData(Map<String, dynamic> userData) {
    if (userData.containsKey('full_name')) _userName = userData['full_name']?.toString() ?? _userName;
    if (userData.containsKey('register_no')) _registerNo = userData['register_no']?.toString() ?? _registerNo;
    if (userData.containsKey('email')) {
      _email = userData['email']?.toString() ?? _email;
      AppLogger.currentUserEmail = _email;
    }
    if (userData.containsKey('phone')) _phone = userData['phone']?.toString() ?? _phone;
    if (userData.containsKey('dob')) _dob = userData['dob']?.toString() ?? _dob;
    if (userData.containsKey('address')) _address = userData['address']?.toString() ?? _address;
    
    if (userData.containsKey('conduct')) _conduct = userData['conduct']?.toString() ?? _conduct;
    if (userData.containsKey('conduct_remarks')) _conductRemarks = userData['conduct_remarks']?.toString() ?? _conductRemarks;
    
    if (userData.containsKey('institution')) _institution = userData['institution']?.toString() ?? _institution;
    if (userData.containsKey('hostel_name')) _hostelName = userData['hostel_name']?.toString() ?? _hostelName;
    if (userData.containsKey('room_no')) _roomNumber = userData['room_no']?.toString() ?? _roomNumber;
    if (userData.containsKey('room_code')) _roomCode = userData['room_code']?.toString() ?? _roomCode;
    if (userData.containsKey('bed_no')) _bedNo = userData['bed_no']?.toString() ?? _bedNo;
    if (userData.containsKey('block')) _block = userData['block']?.toString() ?? _block;
    if (userData.containsKey('wing')) _wing = userData['wing']?.toString() ?? _wing;
    if (userData.containsKey('room_allocation')) _roomAllocation = userData['room_allocation']?.toString() ?? _roomAllocation;
    final String? rawRoomType = userData['room_type']?.toString();
    _roomType = _parseRoomType(_roomAllocation, rawRoomType);
    _roomFacility = userData['room_facility']?.toString() ?? _roomFacility;
    _roomBathAttached = userData['room_bath_attached']?.toString() ?? _roomBathAttached;
    AppLogger.info("SYNC: Received raw room_type: $rawRoomType, Parsed to: $_roomType");
    if (userData.containsKey('profile_pic')) _profilePic = userData['profile_pic']?.toString() ?? _profilePic;
    if (userData.containsKey('valid_from')) _checkInDate = _parseDate(userData['valid_from']);
    if (userData.containsKey('valid_to')) _renewalDate = _parseDate(userData['valid_to']);
    notifyListeners();
  }

  Future<void> logout() async {
    final String activeUser = this.username;
    if (activeUser.isNotEmpty) {
      // Fire-and-forget: do NOT await — waiting for FCM clear was causing 5-6 s logout delay
      NotificationService.saveTokenToBackend(activeUser, 'clear').catchError(
        (e) => AppLogger.error("Failed to clear FCM token on logout: $e"),
      );
    }
    _isLoggedIn = false;
    AppLogger.currentUserEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    await prefs.remove('login_time');
    await prefs.remove('unread_counts_cache');
    notifyListeners();
  }

  void extendRenewal(int months) {
    _renewalDate = DateTime(_renewalDate.year, _renewalDate.month + months, _renewalDate.day);
    notifyListeners();
  }

  Future<void> updateHostelName(String newName) async {
    _hostelName = newName;
    
    // Also update in SharedPreferences so it survives restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        final Map<String, dynamic> userData = Map<String, dynamic>.from(jsonDecode(userDataStr));
        userData['hostel_name'] = newName;
        await prefs.setString('user_data', jsonEncode(userData));
      }
    } catch (e) {
      AppLogger.error("Failed to update cached hostel name: $e");
    }
    
    notifyListeners();
  }
}
