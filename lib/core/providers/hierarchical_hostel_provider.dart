import 'package:flutter/material.dart';
import '../api_service.dart';
import 'package:vianasoft_stay/core/models/hierarchical_hostel_model.dart';

class HierarchicalHostelProvider extends ChangeNotifier {
  List<HierarchicalHostel> _hostels = [];
  bool _isLoading = false;
  String? _error;

  List<HierarchicalHostel> get hostels => _hostels;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  int get totalZones => _hostels.fold<int>(0, (sum, hostel) => sum + (hostel.zones.length));
  int get totalSubZones => _hostels.fold<int>(0, (sum, hostel) => sum + hostel.zones.fold<int>(0, (sum, zone) => sum + zone.subZones.length));
  int get totalRooms => _hostels.fold<int>(0, (sum, hostel) => sum + hostel.totalRooms);

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setError(String? error) {
    _error = error;
    notifyListeners();
  }

  Future<void> loadHostels() async {
    setLoading(true);
    setError(null);
    try {
      final response = await ApiService.getRequest('student/get_hostels.php');
      if (response['status'] == 'success') {
        final List data = response['data']['all_hostels'] ?? [];
        _hostels = data.map<HierarchicalHostel>((h) => HierarchicalHostel(
          id: h['id'],
          name: h['hostel_name'] ?? '',
          createdAt: h['created_at'] ?? '',
          campus: h['campus'] ?? '',
          type: h['hostel_type'] ?? '',
          buildingCode: h['building_code'] ?? '',
          zones: [],
        )).toList();
        notifyListeners();
      } else {
        setError(response['message'] ?? 'Failed to load hostels');
      }
    } catch (e) {
      setError('Network error: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> loadHostelHierarchy(dynamic hostel) async {
    try {
      final hostelId = hostel.id;
      if (hostelId == null) return;
      final response = await ApiService.getHostelHierarchy(int.tryParse(hostelId.toString()) ?? 0);
      if (response['success'] == true) {
        final data = response['data'];
        hostel.zones.clear();
        if (data['wings'] != null) {
          for (var floorData in data['wings']) {
            final zone = Zone(
              id: floorData['id'] ?? floorData['floor_id'] ?? floorData['zone_id'] ?? floorData['code'] ?? floorData['name'], 
              hostelId: hostelId,
              name: floorData['name'] ?? '',
              code: floorData['code'] ?? floorData['name'] ?? '',
              subZones: [],
              createdAt: '',
            );
            if (zone.id != null) hostel.zones.add(zone);

            if (floorData['floors'] != null) {
              for (var wingData in floorData['floors']) {
                final subZone = SubZone(
                  id: wingData['id'] ?? wingData['wing_id'] ?? wingData['sub_zone_id'] ?? wingData['code'] ?? wingData['name'],
                  zoneId: zone.id,
                  name: wingData['name'] ?? '',
                  code: wingData['code'] ?? wingData['name'] ?? '',
                  rooms: [],
                  createdAt: '',
                );
                if (subZone.id != null) zone.subZones.add(subZone);

                if (wingData['rooms'] != null) {
                  for (var roomData in wingData['rooms']) {
                    if (roomData['type'] == 'Structural') continue;
                    subZone.rooms.add(Room(
                      id: roomData['id'],
                      subZoneId: subZone.id,
                      roomNumber: roomData['room_no']?.toString() ?? '',
                      roomCode: roomData['room_code'] ?? '',
                      capacity: roomData['capacity'] ?? 0,
                      availableRooms: roomData['available'] ?? 0,
                      floorLabel: floorData['name'] ?? '',
                      amount: double.parse((roomData['amount'] ?? 0.0).toString()),
                      createdAt: '',
                    ));
                  }
                }
              }
            }
          }
        }
        notifyListeners();
      }
    } catch (e) {
      setError('Failed to load hierarchy: $e');
    }
  }

  Future<bool> updateHierarchyAction(Map<String, dynamic> data) async {
    final response = await ApiService.updateHierarchy(data);
    if (response['success'] == true) {
      await loadHostels();
      return true;
    }
    return false;
  }

  Future<bool> updateHostel(dynamic id, String name, String type, String buildingCode) => 
    updateHierarchyAction({'action': 'update_hostel', 'id': id, 'name': name, 'type': type, 'building_code': buildingCode});

  Future<bool> updateZone(dynamic id, Map<String, dynamic> updates) => 
    updateHierarchyAction({'action': 'update_floor', 'id': id, ...updates});

  Future<bool> updateSubZone(dynamic id, Map<String, dynamic> updates) => 
    updateHierarchyAction({'action': 'update_wing', 'id': id, ...updates});

  Future<bool> deleteHostel(dynamic id) => updateHierarchyAction({'action': 'delete_hostel', 'id': id});
  Future<bool> deleteZone(dynamic id) => updateHierarchyAction({'action': 'delete_floor', 'id': id});
  Future<bool> deleteSubZone(dynamic id) => updateHierarchyAction({'action': 'delete_wing', 'id': id});
  
  Future<void> loadZonesForHostel(dynamic hostel) async { await loadHostelHierarchy(hostel); notifyListeners(); }

  Future<Map<String, dynamic>> addFloor(dynamic hostelId, String name) async {
    return await ApiService.updateHierarchy({
      'action': 'add_floor',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'name': name,
    });
  }

  Future<Map<String, dynamic>> addWing(dynamic hostelId, String floorName, String wingName) async {
    return await ApiService.updateHierarchy({
      'action': 'add_wing',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'wing_name': floorName,
      'name': wingName,
    });
  }

  Future<Map<String, dynamic>> addRoomWithFacility(
    dynamic hostelId,
    String floorName,
    String floorCode,
    String wingName,
    String wingCode,
    String roomNo,
    int capacity,
    double amount,
    String facility,
  ) async {
    return await ApiService.updateHierarchy({
      'action': 'add_room',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'wing_name': floorName,
      'floor_name': wingName,
      'floor_code': floorCode,
      'wing_code': wingCode,
      'room_no': roomNo,
      'capacity': capacity,
      'amount': amount,
      'facility': facility,
    });
  }

  Future<bool> updateFloor(dynamic hostelId, String oldName, String newName) async {
    final response = await ApiService.updateHierarchy({
      'action': 'update_floor',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'old_name': oldName,
      'new_name': newName,
    });
    return response['success'] == true;
  }

  Future<bool> updateWing(dynamic hostelId, String floorName, String oldName, String newName) async {
    final response = await ApiService.updateHierarchy({
      'action': 'update_wing',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'wing_name': floorName,
      'old_name': oldName,
      'new_name': newName,
    });
    return response['success'] == true;
  }

  Future<bool> deleteFloor(dynamic hostelId, String floorName) async {
    final response = await ApiService.updateHierarchy({
      'action': 'delete_floor',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'name': floorName,
    });
    return response['success'] == true;
  }

  Future<bool> deleteWing(dynamic hostelId, String floorName, String wingName) async {
    final response = await ApiService.updateHierarchy({
      'action': 'delete_wing',
      'hostel_id': int.tryParse(hostelId.toString()) ?? hostelId,
      'wing_name': floorName,
      'name': wingName,
    });
    return response['success'] == true;
  }

  Future<bool> deleteRoom(dynamic roomId) async {
    final response = await ApiService.deleteRoom(int.tryParse(roomId.toString()) ?? 0);
    return response['status'] == 'success' || response['success'] == true;
  }

  Future<bool> updateRoom(dynamic roomId, Map<String, dynamic> updates) async {
    final response = await ApiService.updateRoomOld(int.tryParse(roomId.toString()) ?? 0, updates);
    return response['status'] == 'success' || response['success'] == true;
  }
}
