import 'package:flutter/material.dart';
import '../models/mapping_model.dart';
import 'package:uuid/uuid.dart';
import '../api_service.dart';
import '../app_logger.dart';

class MappingProvider extends ChangeNotifier {
  final _uuid = const Uuid();
  List<LocationMapping> mappings = [];
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  Future<void> loadMappings() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.getLocationMappings();
      if (response['status'] == 'success' || response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        mappings = data.map((m) => LocationMapping.fromJson(m)).toList();
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error("Error loading mappings: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> saveMapping(LocationMapping mapping) async {
    try {
      final Map<String, dynamic> data = mapping.toJson();
      
      // Clean up ID: remove if new/temporary (UUID contains '-', or is '0'/empty)
      final String idStr = data['id']?.toString() ?? '';
      if (idStr.isEmpty || idStr.contains('-') || idStr == '0') {
        data.remove('id');
      }

      // Ensure all numeric ID fields are sent as integers, not strings
      void ensureInt(String key) {
        if (data[key] != null && data[key].toString().isNotEmpty) {
          final parsed = int.tryParse(data[key].toString());
          if (parsed != null) data[key] = parsed;
        }
      }
      ensureInt('hostel_id');
      ensureInt('zone_id');
      ensureInt('sub_zone_id');

      // save.php handles both INSERT and UPDATE atomically (including staff)
      final response = await ApiService.saveLocationMapping(data);
      
      if (response['status'] == 'success' || response['success'] == true) {
        await loadMappings();
        return null;
      }
      
      final String errorMsg = response['message'] ?? 'Unknown error';
      AppLogger.error("Save failed: $errorMsg");
      return errorMsg;
    } catch (e) {
      AppLogger.error("Error saving mapping: $e");
      return e.toString();
    }
  }

  Future<bool> deleteMapping(String mappingId) async {
    try {
      final response = await ApiService.deleteLocationMapping(mappingId);
      if (response['success'] == true || response['status'] == 'success') {
        await loadMappings();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error("Error deleting mapping: $e");
      return false;
    }
  }

  String getLocationLabel(LocationMapping mapping) {
    String label = mapping.hostelName ?? "Unknown Hostel";
    if (mapping.zoneName != null && mapping.zoneName!.isNotEmpty) label += " › ${mapping.zoneName}";
    if (mapping.subZoneName != null && mapping.subZoneName!.isNotEmpty) label += " › ${mapping.subZoneName}";
    return label;
  }
}
