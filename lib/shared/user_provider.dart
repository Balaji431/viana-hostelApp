import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../core/api_session.dart';
import '../core/notification_service.dart';
import '../core/app_logger.dart';

enum UserRole { student, warden, admin, parent, maintenance, security, staff, guest }

class UserProvider with ChangeNotifier {
  final SharedPreferences? _prefs;
  bool _prefsInitialized = false;

  UserProvider({SharedPreferences? prefs}) : _prefs = prefs {
    if (prefs != null) {
      _prefsInitialized = true;
      _initializeFromPrefs(prefs);
    }
  }

  /// Called post-frame by main.dart to inject SharedPreferences without
  /// blocking runApp(). Restores saved session data (login token, user data).
  void initPrefs(SharedPreferences prefs) {
    if (_prefsInitialized) return; // already initialized — skip
    _prefsInitialized = true;
    _initializeFromPrefs(prefs);
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ?? await SharedPreferences.getInstance();
  }

  void _initializeFromPrefs(SharedPreferences prefs) {
    try {
      final String? userDataStr = prefs.getString('user_data');
      final String? loginTimeStr = prefs.getString('login_time');

      if (userDataStr != null && loginTimeStr != null) {
        final DateTime loginTime = DateTime.parse(loginTimeStr);
        final DateTime now = DateTime.now();

        if (now.difference(loginTime).inDays < 7) {
          final Map<String, dynamic> userData =
              Map<String, dynamic>.from(jsonDecode(userDataStr));
          _loginSync(userData);
        }
      }
    } catch (e) {
      AppLogger.error("Persistence initialization error: $e");
    }
  }
  UserRole _role = UserRole.student;
  List<UserRole> _availableRoles = []; // NEW: Stores all roles user is authorized for
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
  String _hostelType = "Boys";
  String _roomNumber = "";
  String _roomCode = "";
  String _bedNo = "";
  String _roomAllocation = "";
  String _groupName = "";
  String _warden = "";
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

  // 🔥 DYNAMIC ROOM FEE PROPERTIES
  double _roomAmount = 70000.0;
  double _roomFood = 50000.0;
  double _roomCaution = 5000.0;
  double _totalFee = 125000.0;
  double _renewAmount = 120000.0;
  double _walletBalance = 0.0;

  // 🔥 TEMPORARY STAY GUEST PROPERTIES
  Map<String, dynamic>? _temporaryStayRequest;
  Map<String, dynamic>? get temporaryStayRequest => _temporaryStayRequest;

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
  int _dashboardRefreshTick = 0;

  int? get dbId => _dbId;
  String? _token;
  String? get token => _token;
  int get dashboardRefreshTick => _dashboardRefreshTick;
  UserRole get role => _role;
  List<UserRole> get availableRoles => List.unmodifiable(_availableRoles);
  bool get hasMultipleRoles => _availableRoles.length > 1;
  bool get isGuest => _role == UserRole.guest;
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
  String get hostelType => _hostelType;
  String get roomNumber {
    final String val = _roomNumber.isNotEmpty ? _roomNumber : _roomAllocation;
    return val
        .replaceAll(' - ', '-')
        .replaceAll('- ', '-')
        .replaceAll(' ', '')
        .replaceAll('T-32', 'T32')
        .trim();
  }
  String get roomCode => _roomCode;
  String get bedNo => _bedNo;
  String get roomAllocation {
    final String val = _roomAllocation.isNotEmpty ? _roomAllocation : _roomNumber;
    return val
        .replaceAll(' - ', '-')
        .replaceAll('- ', '-')
        .replaceAll(' ', '')
        .replaceAll('T-32', 'T32')
        .trim();
  }
  String get groupName => _groupName.isNotEmpty
      ? _groupName
      : (_hostelName.isNotEmpty ? "$_hostelName Second Floor" : "Vaigai Hostel Second Floor");
  String get warden => _warden;
  String get block => _block;
  String get wing => _wing;
  String get fullRoomDetails => _roomNumber.isNotEmpty
      ? "$_roomNumber, $_block, $_wing"
      : (_roomAllocation.isNotEmpty
          ? _roomAllocation
          : "$hostelName, Room: $roomNumber, Bed: $bedNo");
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

  // 🔥 DYNAMIC ROOM FEE GETTERS
  double get roomAmount => _roomAmount;
  double get roomFood => _roomFood;
  double get roomCaution => _roomCaution;
  double get totalFee => _totalFee;
  double get renewAmount => _renewAmount;
  double get walletBalance => _walletBalance;

  void setWalletBalance(double balance) {
    _walletBalance = balance;
    notifyListeners();
  }

  Future<void> fetchWalletBalance() async {
    try {
      final effEmail = email.isNotEmpty ? email : (username.contains('@') ? username : '$username.simats@saveetha.com');
      final res = await ApiService.fetchWalletInfo(
        email: effEmail,
        regNo: username,
        studentId: dbId,
      );
      if (res['success'] == true && res['balance'] != null) {
        _walletBalance = double.tryParse(res['balance'].toString()) ?? _walletBalance;
        notifyListeners();
      }
    } catch (_) {}
  }

  bool get isRoomAllocated {
    final String rNum = _roomNumber.trim().toUpperCase();
    final String rAlloc = _roomAllocation.trim().toUpperCase();

    if (rNum.isEmpty || rNum == "N/A" || rNum == "NONE" || rNum == "NULL") {
      if (rAlloc.isEmpty ||
          rAlloc == "N/A" ||
          rAlloc == "N/A, N/A, N/A" ||
          rAlloc == "NONE" ||
          rAlloc == "NULL") {
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
  String get displayInstitution =>
      _isParent ? _linkedStudentInstitution : _institution;
  String get displayHostel => _isParent ? _linkedStudentHostel : _hostelName;
  String get displayProfilePic =>
      _isParent ? _linkedStudentProfilePic : _profilePic;
  String get displayStudentId => _isParent ? _linkedStudentUsername : studentId;

  static UserRole stringToRole(String roleStr) {
    final lower = roleStr.toLowerCase().trim();
    if (lower == 'admin') return UserRole.admin;
    if (lower == 'warden') return UserRole.warden;
    if (lower == 'parent') return UserRole.parent;
    if (lower == 'maintenance') return UserRole.maintenance;
    if (lower == 'security') return UserRole.security;
    if (lower == 'guest' || lower == 'temp_student') return UserRole.guest;
    if (lower == 'student') return UserRole.student;
    return UserRole.staff;
  }

  void setRole(UserRole newRole) {
    _role = newRole;
    notifyListeners();
  }

  /// Switches active role between authorized available roles (e.g. Warden <-> Maintenance)
  void switchActiveRole(UserRole newRole) {
    if (_availableRoles.contains(newRole) && _role != newRole) {
      _role = newRole;
      _roleName = newRole.name;
      _dashboardRefreshTick++;
      notifyListeners();
    }
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
    if (date == null || date == "" || date == "0000-00-00") {
      return DateTime.now();
    }
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
    if (_lastRefreshTime != null &&
        now.difference(_lastRefreshTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastRefreshTime = now;

    try {
      AppLogger.info("Refreshing user data for ID: $_dbId");
      final String? roleParam = _isParent
          ? 'parent'
          : (_role == UserRole.student
              ? 'student'
              : (_roleName.isNotEmpty ? _roleName : null));
      final response = await ApiService.getUserData(
        _dbId!,
        role: roleParam,
      );

      if (response['success'] == true && response['data'] != null) {
        final Map<String, dynamic> userData =
            Map<String, dynamic>.from(response['data']);

        // 1. Update local properties
        setUserData(userData);

        // 2. Update persistence cache so it survives restart
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_data', jsonEncode(userData));

        if (_role == UserRole.student) {
          fetchWalletBalance();
        }

        AppLogger.info("User data refreshed successfully from DB");
      }
    } catch (e) {
      AppLogger.error("Error refreshing data from DB: $e");
    }
  }

  void triggerDashboardRefresh() {
    refreshUserData();
    _dashboardRefreshTick++;
    notifyListeners();
  }

  void requestRenewal() {
    _renewalStatus = 'Pending';
    notifyListeners();
  }

  void approveRenewal() {
    _renewalStatus = 'Approved';
    notifyListeners();
  }

  void _loginSync(Map<String, dynamic> userData) {
    final String roleStr =
        userData['role']?.toString().toLowerCase() ?? 'student';
    _roleName = roleStr;
    _role = stringToRole(roleStr);
    _isParent = (_role == UserRole.parent);

    // Parse available_roles
    final rawRoles = userData['available_roles'];
    _availableRoles = [];
    if (rawRoles is List) {
      for (var r in rawRoles) {
        final roleEnum = stringToRole(r.toString());
        if (!_availableRoles.contains(roleEnum)) {
          _availableRoles.add(roleEnum);
        }
      }
    }
    if (!_availableRoles.contains(_role)) {
      _availableRoles.insert(0, _role);
    }

    _dbId = int.tryParse(userData['id']?.toString() ?? "");
    _loginUsername = userData['username']?.toString() ??
        userData['register_no']?.toString() ??
        userData['parent_id']?.toString() ??
        userData['email']?.toString() ??
        "";
    _userName = userData['full_name']?.toString() ?? "User";
    _studentId = userData['register_no']?.toString() ??
        userData['email']?.toString() ??
        "";
    _registerNo = userData['register_no']?.toString() ?? "";
    _email = userData['email']?.toString() ?? "";
    AppLogger.currentUserEmail = _email;
    _phone = userData['phone']?.toString() ?? "";
    _dob = userData['dob']?.toString() ?? "";
    _address = userData['address']?.toString() ?? "";

    String _cleanRoom(dynamic val) {
      if (val == null) return "";
      return val.toString().replaceAll(' - ', '-').replaceAll('- ', '-').replaceAll(' ', '').replaceAll('T-32', 'T32').trim();
    }
    _institution = userData['institution']?.toString() ?? "";
    _hostelName = userData['hostel_name']?.toString() ?? "";
    _roomNumber = _cleanRoom(userData['room_no'] ?? userData['room_allocation']);
    _roomCode = _cleanRoom(userData['room_code'] ?? userData['room_no'] ?? userData['room_allocation']);
    _bedNo = userData['bed_no']?.toString() ?? "";
    _block = userData['block']?.toString() ?? "";
    _wing = userData['wing']?.toString() ?? "";
    _roomAllocation = _cleanRoom(userData['room_allocation'] ?? userData['room_no']);
    _groupName = userData['group_name']?.toString() ?? userData['floor_name']?.toString() ?? "";
    _warden = userData['warden']?.toString() ?? "";
    // Parse room type from room_allocation (e.g., "Bed: (6 IN 1)" -> "6-sharing")
    _roomType =
        _parseRoomType(_roomAllocation, userData['room_type']?.toString());
    _roomFacility = userData['room_facility']?.toString() ?? "";
    _roomBathAttached = userData['room_bath_attached']?.toString() ?? "";
    _roomAmount = double.tryParse(userData['room_amount']?.toString() ?? '') ?? 70000.0;
    _roomFood = double.tryParse(userData['room_food']?.toString() ?? '') ?? 50000.0;
    _roomCaution = double.tryParse(userData['room_caution']?.toString() ?? '') ?? 5000.0;
    _totalFee = double.tryParse(userData['total_fee']?.toString() ?? '') ?? (_roomAmount + _roomFood + _roomCaution);
    _renewAmount = double.tryParse(userData['renew_amount']?.toString() ?? '') ?? (_roomAmount + _roomFood);
    _walletBalance = double.tryParse(userData['wallet_balance']?.toString() ?? userData['balance']?.toString() ?? '') ?? _walletBalance;
    _profilePic = userData['profile_pic']?.toString() ?? "";
    _conduct = userData['conduct']?.toString() ?? "Good";
    _conductRemarks = userData['conduct_remarks']?.toString() ?? "";
    _checkInDate = _parseDate(userData['valid_from']);
    _renewalDate = _parseDate(userData['valid_to']);

    if (userData['temporary_stay_request'] != null) {
      _temporaryStayRequest = Map<String, dynamic>.from(userData['temporary_stay_request']);
      if (_temporaryStayRequest!['from_date'] != null) {
        _checkInDate = _parseDate(_temporaryStayRequest!['from_date']);
      }
      if (_temporaryStayRequest!['to_date'] != null) {
        _renewalDate = _parseDate(_temporaryStayRequest!['to_date']);
      }

      if (_temporaryStayRequest!['amount'] != null) {
        _totalFee = double.tryParse(_temporaryStayRequest!['amount'].toString()) ?? _totalFee;
        _roomAmount = _totalFee;
        _renewAmount = _totalFee;
      }
      if (_temporaryStayRequest!['room_type'] != null) {
        _roomType = _temporaryStayRequest!['room_type'].toString();
      }

      _hostelName = _temporaryStayRequest!['hostel_name']?.toString() ?? _hostelName;
      _roomNumber = _temporaryStayRequest!['room_no']?.toString() ?? _roomNumber;
      _roomCode = _temporaryStayRequest!['room_code']?.toString() ?? _temporaryStayRequest!['room_no']?.toString() ?? _roomCode;
      
      if (_roomCode.contains('-')) {
        final parts = _roomCode.split('-');
        if (parts.length >= 4) {
          _block = parts[0];
          _wing = "${parts[1]} - ${parts[2]}";
          _roomNumber = parts[3];
        } else if (parts.length == 3) {
          _block = parts[0];
          _wing = parts[1];
          _roomNumber = parts[2];
        }
      }

      if (_roomCode.isNotEmpty) {
        _roomAllocation = _roomCode;
      } else if (_roomNumber.isNotEmpty) {
        _roomAllocation = _roomNumber;
      }

      if (_temporaryStayRequest!['warden_name'] != null &&
          _temporaryStayRequest!['warden_name'].toString().isNotEmpty) {
        _warden = _temporaryStayRequest!['warden_name'].toString();
      }
    } else {
      _temporaryStayRequest = null;
    }

    // 🔥 PARENT ROLE: Handle linked student data
    if (_isParent) {
      _linkedStudentId =
          int.tryParse(userData['linked_student_id']?.toString() ?? "");
      _linkedStudentUsername =
          userData['linked_student_username']?.toString() ?? "";
      _linkedStudentName = userData['linked_student_name']?.toString() ?? "";
      _linkedStudentEmail = userData['linked_student_email']?.toString() ?? "";
      _linkedStudentRoom = userData['linked_student_room']?.toString() ?? "";
      _linkedStudentInstitution =
          userData['linked_student_institution']?.toString() ?? "";
      _linkedStudentHostel =
          userData['linked_student_hostel']?.toString() ?? "";
      _linkedStudentProfilePic =
          userData['linked_student_profile_pic']?.toString() ?? "";

      AppLogger.info(
          "Parent login: $_userName, Student: $_linkedStudentName (ID: $_linkedStudentId)");
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

    // Set variables for header injection without loading the full API layer.
    ApiSession.currentUserId = userData['id']?.toString();
    ApiSession.currentUsername =
        userData['username']?.toString() ?? userData['register_no']?.toString();
    ApiSession.currentUserRole = userData['role']?.toString();
    _token = userData['token']?.toString();
    ApiSession.currentToken = _token;
  }

  Future<void> login(Map<String, dynamic> userData) async {
    _loginSync(userData);

    // 🔥 SAVE FCM TOKEN TO BACKEND (Works for all users including parents)
    unawaited(_saveFCMTokenAfterStartup());

    // Non-blocking persistence update
    unawaited(() async {
      try {
        final prefs = await _getPrefs();
        await prefs.setString('user_data', jsonEncode(userData));
        await prefs.setString('login_time', DateTime.now().toIso8601String());
      } catch (e) {
        AppLogger.error("Failed to update persistence cache: $e");
      }
    }());

    notifyListeners();
  }

  // 🔥 SAVE FCM TOKEN TO BACKEND — called immediately after login
  Future<void> _saveFCMTokenAfterStartup() async {
    if (kIsWeb) return;
    // No artificial delay — use the cached token from NotificationService init.
    // If the token isn't cached yet (very rare: device just booted), wait briefly.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _saveFCMToken();
  }

  Future<void> _saveFCMToken() async {
    try {
      // Prefer _loginUsername (actual login key like 'admin1', '29066')
      // Fall back to _registerNo for students
      final String username =
          (_loginUsername != null && _loginUsername!.isNotEmpty)
              ? _loginUsername!
              : _registerNo;

      if (username.isNotEmpty && username != 'null') {
        // First try the cached token from NotificationService (already fetched at app init)
        // This avoids a second Firebase call and works even if the app is foregrounded
        String? token = NotificationService.cachedToken;
        if (token == null || token.isEmpty) {
          // Fallback: ask Firebase directly (first-ever launch or token expired)
          token = await NotificationService.getToken();
        }
        if (token != null && token.isNotEmpty) {
          await NotificationService.saveTokenToBackend(username, token);
        } else {
          AppLogger.error('FCM token is null — cannot register for push notifications');
        }
      } else {
        AppLogger.error('Invalid username for FCM token save: "$username"');
      }
    } catch (e) {
      AppLogger.error('Error saving FCM token: $e');
    }
  }

  Future<void> checkPersistence() async {
    if (_isLoggedIn) {
      unawaited(_saveFCMTokenAfterStartup());
      return;
    }

    try {
      final prefs = await _getPrefs();
      final String? userDataStr = prefs.getString('user_data');
      final String? loginTimeStr = prefs.getString('login_time');

      if (userDataStr != null && loginTimeStr != null) {
        final DateTime loginTime = DateTime.parse(loginTimeStr);
        final DateTime now = DateTime.now();

        // Check if session is older than 7 days
        if (now.difference(loginTime).inDays < 7) {
          final Map<String, dynamic> userData =
              Map<String, dynamic>.from(jsonDecode(userDataStr));
          await login(
              userData); // Re-use login logic for consistency and safety
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
    if (userData['temporary_stay_request'] != null) {
      _temporaryStayRequest = Map<String, dynamic>.from(userData['temporary_stay_request']);
      if (_temporaryStayRequest!['from_date'] != null) {
        _checkInDate = _parseDate(_temporaryStayRequest!['from_date']);
      }
      if (_temporaryStayRequest!['to_date'] != null) {
        _renewalDate = _parseDate(_temporaryStayRequest!['to_date']);
      }
      _hostelName = _temporaryStayRequest!['hostel_name']?.toString() ?? _hostelName;
      _roomNumber = _temporaryStayRequest!['room_no']?.toString() ?? _roomNumber;
      _roomCode = _temporaryStayRequest!['room_code']?.toString() ?? _temporaryStayRequest!['room_no']?.toString() ?? _roomCode;
      
      if (_roomCode.contains('-')) {
        final parts = _roomCode.split('-');
        if (parts.length >= 4) {
          _block = parts[0];
          _wing = "${parts[1]} - ${parts[2]}";
          _roomNumber = parts[3];
        } else if (parts.length == 3) {
          _block = parts[0];
          _wing = parts[1];
          _roomNumber = parts[2];
        }
      }

      if (_roomCode.isNotEmpty) {
        _roomAllocation = _roomCode;
      } else if (_roomNumber.isNotEmpty) {
        _roomAllocation = _roomNumber;
      }
    }

    if (userData.containsKey('full_name')) {
      _userName = userData['full_name']?.toString() ?? _userName;
    }
    if (userData.containsKey('register_no')) {
      _registerNo = userData['register_no']?.toString() ?? _registerNo;
    }
    if (userData.containsKey('email')) {
      _email = userData['email']?.toString() ?? _email;
      AppLogger.currentUserEmail = _email;
    }
    if (userData.containsKey('phone')) {
      _phone = userData['phone']?.toString() ?? _phone;
    }
    if (userData.containsKey('dob')) _dob = userData['dob']?.toString() ?? _dob;
    if (userData.containsKey('address')) {
      _address = userData['address']?.toString() ?? _address;
    }

    if (userData.containsKey('conduct')) {
      _conduct = userData['conduct']?.toString() ?? _conduct;
    }
    if (userData.containsKey('conduct_remarks')) {
      _conductRemarks =
          userData['conduct_remarks']?.toString() ?? _conductRemarks;
    }

    if (userData.containsKey('institution')) {
      _institution = userData['institution']?.toString() ?? _institution;
    }
    if (userData.containsKey('hostel_name')) {
      _hostelName = userData['hostel_name']?.toString() ?? _hostelName;
    }
    if (userData.containsKey('hostel_type')) {
      _hostelType = userData['hostel_type']?.toString() ?? _hostelType;
    }
    String _cleanRoom(dynamic val) {
      if (val == null) return "";
      return val.toString().replaceAll(' - ', '-').replaceAll('- ', '-').replaceAll(' ', '').replaceAll('T-32', 'T32').trim();
    }
    if (userData.containsKey('room_no')) {
      _roomNumber = _cleanRoom(userData['room_no']);
    }
    if (userData.containsKey('room_code')) {
      _roomCode = _cleanRoom(userData['room_code']);
    }
    if (userData.containsKey('bed_no')) {
      _bedNo = userData['bed_no']?.toString() ?? _bedNo;
    }
    if (userData.containsKey('block')) {
      _block = userData['block']?.toString() ?? _block;
    }
    if (userData.containsKey('wing')) {
      _wing = userData['wing']?.toString() ?? _wing;
    }
    if (userData.containsKey('room_allocation')) {
      _roomAllocation = _cleanRoom(userData['room_allocation']);
    }
    if (userData.containsKey('group_name') && userData['group_name'] != null && userData['group_name'].toString().isNotEmpty) {
      _groupName = userData['group_name'].toString();
    } else if (userData.containsKey('floor_name') && userData['floor_name'] != null && userData['floor_name'].toString().isNotEmpty) {
      _groupName = userData['floor_name'].toString();
    }
    if (userData.containsKey('warden') && userData['warden'] != null && userData['warden'].toString().isNotEmpty) {
      _warden = userData['warden'].toString();
    }
    final String? rawRoomType = userData['room_type']?.toString();
    _roomType = _parseRoomType(_roomAllocation, rawRoomType);
    _roomFacility = userData['room_facility']?.toString() ?? _roomFacility;
    _roomBathAttached =
        userData['room_bath_attached']?.toString() ?? _roomBathAttached;
    
    if (userData.containsKey('room_amount') && userData['room_amount'] != null) {
      _roomAmount = double.tryParse(userData['room_amount'].toString()) ?? _roomAmount;
    }
    if (userData.containsKey('room_food') && userData['room_food'] != null) {
      _roomFood = double.tryParse(userData['room_food'].toString()) ?? _roomFood;
    }
    if (userData.containsKey('room_caution') && userData['room_caution'] != null) {
      _roomCaution = double.tryParse(userData['room_caution'].toString()) ?? _roomCaution;
    }
    if (userData.containsKey('total_fee') && userData['total_fee'] != null) {
      _totalFee = double.tryParse(userData['total_fee'].toString()) ?? (_roomAmount + _roomFood + _roomCaution);
    } else if (userData.containsKey('room_amount')) {
      _totalFee = _roomAmount + _roomFood + _roomCaution;
    }
    if (userData.containsKey('renew_amount') && userData['renew_amount'] != null) {
      _renewAmount = double.tryParse(userData['renew_amount'].toString()) ?? (_roomAmount + _roomFood);
    } else if (userData.containsKey('room_amount')) {
      _renewAmount = _roomAmount + _roomFood;
    }

    AppLogger.info(
        "SYNC: Received raw room_type: $rawRoomType, Parsed to: $_roomType, TotalFee: $_totalFee, Amount: $_roomAmount");
    if (userData.containsKey('profile_pic')) {
      _profilePic = userData['profile_pic']?.toString() ?? _profilePic;
    }
    if (userData.containsKey('valid_from')) {
      _checkInDate = _parseDate(userData['valid_from']);
    }
    if (userData.containsKey('valid_to')) {
      _renewalDate = _parseDate(userData['valid_to']);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    final String activeUser = username;
    final String? activeUserId = _dbId?.toString();
    final String activeRole =
        _roleName.isNotEmpty ? _roleName : _role.toString().split('.').last;

    if (activeUser.isNotEmpty) {
      // Log logout event on backend
      unawaited(() async {
        try {
          await ApiService.logout(
            userId: activeUserId,
            username: activeUser,
            role: activeRole,
          );
        } catch (e) {
          AppLogger.error("Failed to log audit logout: $e");
        }
      }());

      // Fire-and-forget: do NOT await — waiting for FCM clear was causing 5-6 s logout delay
      unawaited(() async {
        try {
          if (kIsWeb) return;
          await NotificationService.saveTokenToBackend(
            activeUser,
            'clear',
          );
        } catch (e) {
          AppLogger.error("Failed to clear FCM token on logout: $e");
        }
      }());
    }

    // Clear user tracking headers
    ApiSession.clear();
    _token = null;

    _isLoggedIn = false;
    AppLogger.currentUserEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    await prefs.remove('login_time');
    await prefs.remove('unread_counts_cache');
    notifyListeners();
  }

  void extendRenewal(int months) {
    _renewalDate = DateTime(
        _renewalDate.year, _renewalDate.month + months, _renewalDate.day);
    notifyListeners();
  }

  Future<void> updateHostelName(String newName) async {
    _hostelName = newName;

    // Also update in SharedPreferences so it survives restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        final Map<String, dynamic> userData =
            Map<String, dynamic>.from(jsonDecode(userDataStr));
        userData['hostel_name'] = newName;
        await prefs.setString('user_data', jsonEncode(userData));
      }
    } catch (e) {
      AppLogger.error("Failed to update cached hostel name: $e");
    }

    notifyListeners();
  }
}
