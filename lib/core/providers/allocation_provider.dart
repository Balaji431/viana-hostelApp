import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_service.dart';

class AllocationProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _hostels = [];
  List<Map<String, dynamic>> _preferences = [];
  Map<String, dynamic>? _allocation;
  Map<String, dynamic>? _paidHostelData;
  bool _isLoading = false;
  bool _firstPriorityHeldByPending = false;
  bool _hasSecondPriority = false;

  // ── paid hostel fetch state ───────────────────────────────────────────────
  /// Register number for which paidHostelData was fetched
  String? _currentRegisterNo;
  /// true while a fetch is in-flight
  bool _paidFetchLoading = false;
  /// true once a fetch has completed (success OR definitive error) — prevents
  /// repeated re-triggers from addPostFrameCallback rebuild loops
  bool _paidFetchDone = false;
  /// set to a user-visible message on failure, null on success
  String? _paidFetchError;
  /// HTTP status code returned by the backend (200/404/503/500/0)
  int _paidFetchHttpStatus = 0;

  List<Map<String, dynamic>> get rooms => _rooms;
  List<Map<String, dynamic>> get hostels => _hostels;
  List<Map<String, dynamic>> get preferences => _preferences;
  Map<String, dynamic>? get allocation => _allocation;
  Map<String, dynamic>? get paidHostelData => _paidHostelData;
  bool get isLoading => _isLoading;
  bool get firstPriorityHeldByPending => _firstPriorityHeldByPending;
  bool get hasSecondPriority => _hasSecondPriority;
  String? get currentRegisterNo => _currentRegisterNo;
  bool  get paidFetchLoading    => _paidFetchLoading;
  bool  get paidFetchDone       => _paidFetchDone;
  String? get paidFetchError    => _paidFetchError;
  int   get paidFetchHttpStatus => _paidFetchHttpStatus;

  /// Returns a normalised allocation status string.
  /// 'pending' and 'claimed' are the new canonical statuses from request_status.
  /// We map them to 'under_review' so the existing Flutter UI branches continue
  /// to work without a full UI rewrite.
  String get allocationStatus {
    final raw = _allocation?['allocation_status'] ?? _allocation?['request_status'] ?? 'none';
    if (raw == 'pending' || raw == 'claimed') return 'under_review';
    return raw as String;
  }

  Future<void> fetchRooms() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/allocation/get_rooms.php'));
      final data = json.decode(response.body);
      if (data['success']) {
        _rooms = List<Map<String, dynamic>>.from(data['rooms']);
        _hostels = List<Map<String, dynamic>>.from(data['hostels'] ?? []);
      }
    } catch (e) {
      print("Error fetching rooms: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllocation(int studentId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final data = await ApiService.getAllocationStatus(studentId);
      if (data['success']) {
        _preferences = List<Map<String, dynamic>>.from(data['preferences']);
        _allocation = data['allocation'];
        _firstPriorityHeldByPending = data['first_priority_held_by_pending'] ?? false;
        _hasSecondPriority = data['has_second_priority'] ?? false;
      }
    } catch (e) {
      debugPrint("Error loading allocation: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> continueToSecondPriority(int studentId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/continue_second_priority.php'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'student_id': studentId}),
      );
      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllocation(studentId);
      }
      return data;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addPreference(int studentId, int roomId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/preferences.php?student_id=$studentId'),
        body: json.encode({'room_id': roomId}),
      );
      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllocation(studentId);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removePreference(int studentId, int roomId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiService.baseUrl}/allocation/preferences.php?student_id=$studentId&room_id=$roomId'),
      );
      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllocation(studentId);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> reorderPreferences(int studentId, List<Map<String, dynamic>> newOrder) async {
    // Optimistic Update
    final originalOrder = List<Map<String, dynamic>>.from(_preferences);
    
    // We need to map the newOrder (which is room_id & priority) back to the full preference objects
    final Map<int, Map<String, dynamic>> fullPrefsMap = {
      for (var p in _preferences) int.parse(p['room_id'].toString()): p
    };
    
    List<Map<String, dynamic>> updatedPrefs = [];
    for (var item in newOrder) {
      final rid = int.parse(item['room_id'].toString());
      if (fullPrefsMap.containsKey(rid)) {
        final fullPref = Map<String, dynamic>.from(fullPrefsMap[rid]!);
        fullPref['priority_order'] = item['priority_order'];
        updatedPrefs.add(fullPref);
      }
    }
    
    _preferences = updatedPrefs;
    notifyListeners();

    try {
      final response = await http.put(
        Uri.parse('${ApiService.baseUrl}/allocation/preferences.php?student_id=$studentId'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'priorities': newOrder}),
      );
      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllocation(studentId);
        return true;
      } else {
        _preferences = originalOrder;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _preferences = originalOrder;
      notifyListeners();
      return false;
    }
  }

  Future<bool> submitPreferences(int studentId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/submit_preferences.php'),
        body: json.encode({'student_id': studentId}),
      );
      final data = json.decode(response.body);
      if (data['success']) {
        await loadAllocation(studentId);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Fetches paid hostel details for [registerNo].
  ///
  /// Guards against concurrent calls and re-trigger loops:
  ///  - returns immediately if already loading or already done.
  ///  - sets [paidFetchDone] = true on first completion (success or definitive failure).
  ///  - on 503 (service unavailable), [paidFetchDone] remains false so a manual
  ///    Retry button can call this again.
  Future<void> fetchPaidHostelType(String registerNo) async {
    final normReg = registerNo.trim();
    if (_currentRegisterNo != normReg) {
      _currentRegisterNo = normReg;
      _paidFetchDone = false;
      _paidHostelData = null;
      _paidFetchError = null;
      _paidFetchHttpStatus = 0;
    }

    // Don't re-trigger if already loading or already have a definitive result for this user
    if (_paidFetchLoading || _paidFetchDone) return;

    _paidFetchLoading = true;
    _paidFetchError   = null;
    _isLoading        = true;
    notifyListeners();

    try {
      final response = await ApiService.getPaidHostelType(normReg)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => {
              'success': false,
              'http_status': 0,
              'message': 'Request timed out. Please check your connection.',
            },
          );

      final httpStatus = (response['http_status'] as num?)?.toInt() ?? 0;
      _paidFetchHttpStatus = httpStatus;

      if (response['success'] == true) {
        _paidHostelData = response['data'] as Map<String, dynamic>?;
        _paidFetchError = null;
        _paidFetchDone  = true;   // success — no retry needed
      } else {
        final msg = (response['message'] as String?) ?? 'Unknown error';
        _paidHostelData = null;
        _paidFetchError = msg;

        if (httpStatus == 503 || httpStatus == 0) {
          // Transient failure — allow manual retry
          _paidFetchDone = false;
        } else {
          // 404, 400, 500 — definitive; don't loop
          _paidFetchDone = true;
        }
      }
    } catch (e) {
      debugPrint('fetchPaidHostelType error: $e');
      _paidHostelData      = null;
      _paidFetchError      = 'Connection error. Please try again.';
      _paidFetchHttpStatus = 0;
      _paidFetchDone       = false; // allow retry on network errors
    } finally {
      _paidFetchLoading = false;
      _isLoading        = false;
      notifyListeners();
    }
  }

  /// Resets paid fetch state so the user can manually retry after a transient error.
  void resetPaidFetch() {
    _paidFetchDone       = false;
    _paidFetchError      = null;
    _paidFetchHttpStatus = 0;
    _paidHostelData      = null;
    notifyListeners();
  }

  /// Completely resets all cached allocation & payment state (e.g. on user logout).
  void reset() {
    _rooms = [];
    _hostels = [];
    _preferences = [];
    _allocation = null;
    _paidHostelData = null;
    _isLoading = false;
    _firstPriorityHeldByPending = false;
    _hasSecondPriority = false;
    _paidFetchLoading = false;
    _paidFetchDone = false;
    _paidFetchError = null;
    _paidFetchHttpStatus = 0;
    _currentRegisterNo = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> requestNewStudentAllocation(int studentId, String registerNo) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.requestNewStudentAllocation(studentId);
      if (response['success'] == true) {
        await loadAllocation(studentId);
      }
      return response;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
