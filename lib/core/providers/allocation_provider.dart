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

  List<Map<String, dynamic>> get rooms => _rooms;
  List<Map<String, dynamic>> get hostels => _hostels;
  List<Map<String, dynamic>> get preferences => _preferences;
  Map<String, dynamic>? get allocation => _allocation;
  Map<String, dynamic>? get paidHostelData => _paidHostelData;
  bool get isLoading => _isLoading;
  bool get firstPriorityHeldByPending => _firstPriorityHeldByPending;
  bool get hasSecondPriority => _hasSecondPriority;

  String get allocationStatus => _allocation?['allocation_status'] ?? 'none';

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

  Future<void> fetchPaidHostelType(String registerNo) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.getPaidHostelType(registerNo);
      if (response['success'] == true) {
        _paidHostelData = response['data'];
      }
    } catch (e) {
      debugPrint("Error fetching paid hostel type: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
