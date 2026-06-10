import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../core/app_logger.dart';

class CategoryProvider with ChangeNotifier {
  List<Map<String, dynamic>> _categories = [];
  Map<String, int> _unreadCounts = <String, int>{};
  Map<String, dynamic> _assignedStaff = <String, dynamic>{};
  bool _isLoading = false;

  DateTime? _lastFetchTime;
  String? _lastWardenUsername;
  String? _lastStudentUsername;

  /// Reset all unread counts — call this on user login/logout to clear stale data
  void reset() {
    _unreadCounts = <String, int>{};
    _assignedStaff = <String, dynamic>{};
    notifyListeners();
  }

  /// Load cached counts from SharedPreferences so badges show instantly on launch
  Future<void> loadCachedCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('unread_counts_cache');
      if (cached != null && cached.isNotEmpty) {
        final Map<String, dynamic> decoded = json.decode(cached);
        _unreadCounts = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error('Error loading cached counts: $e');
    }
  }

  /// Save current counts to SharedPreferences cache
  Future<void> _saveCachedCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('unread_counts_cache', json.encode(_unreadCounts));
    } catch (e) {
      AppLogger.error('Error saving cached counts: $e');
    }
  }

  /// Clear cached counts from SharedPreferences (call on logout)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('unread_counts_cache');
    } catch (e) {
      AppLogger.error('Error clearing counts cache: $e');
    }
  }

  /// Immediately zero a category's unread count in memory (call when user opens a chat).
  /// This makes the red badge vanish instantly without waiting for the next API poll.
  void setUnreadCount(String categoryName, int count) {
    final lowerKey = categoryName.toLowerCase();
    bool found = false;
    for (final k in _unreadCounts.keys.toList()) {
      if (k.toLowerCase() == lowerKey) {
        _unreadCounts[k] = count;
        found = true;
        break;
      }
    }
    if (!found) {
      _unreadCounts[lowerKey] = count;
    }
    notifyListeners();
    _saveCachedCounts();
  }

  List<Map<String, dynamic>> get categories => [..._categories];
  Map<String, int> get unreadCounts => _unreadCounts;
  Map<String, dynamic> get assignedStaff => _assignedStaff;
  bool get isLoading => _isLoading;

  Future<void> fetchAssignedStaff(int studentId) async {
    try {
      final response = await ApiService.getAssignedStaff(studentId);
      if (response['success'] == true && response['data'] != null) {
        _assignedStaff = Map<String, dynamic>.from(response['data']);
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error("Error fetching assigned staff: $e");
    }
  }

  void setCategories(List<Map<String, dynamic>> categories) {
    _categories = categories;
    notifyListeners();
  }

  int getUnreadCount(String categoryName) {
    // Normalize: 'messages' and 'warden' both map to 'warden' key
    String lowerKey = categoryName.toLowerCase();
    if (lowerKey == 'messages') lowerKey = 'warden';

    // Case-insensitive lookup — handles mismatches like 'security' vs 'Security'
    for (final entry in _unreadCounts.entries) {
      if (entry.key.toLowerCase() == lowerKey) return entry.value;
    }
    return 0;
  }

  Future<void> fetchCategories() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.getCategories();
      if (response['status'] == 'success' || response['success'] == true) {
        final List<dynamic> rawData = response['categories'] ?? response['data'] ?? [];
        final List<Map<String, dynamic>> newData = rawData.map((e) => Map<String, dynamic>.from(e)).toList();
        _categories = newData;
      }
    } catch (e) {
      AppLogger.error("Error fetching categories: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCounts({String? wardenUsername, String? studentUsername}) async {
    final now = DateTime.now();
    if (_lastFetchTime != null &&
        now.difference(_lastFetchTime!) < const Duration(seconds: 2) &&
        _lastWardenUsername == wardenUsername &&
        _lastStudentUsername == studentUsername) {
      return;
    }
    _lastFetchTime = now;
    _lastWardenUsername = wardenUsername;
    _lastStudentUsername = studentUsername;

    try {
      final response = await ApiService.getCategorySummary(
        wardenUsername: wardenUsername,
        studentUsername: studentUsername,
      );
      if (response['status'] == 'success' && response['data'] != null) {
        _unreadCounts = Map<String, int>.from(
          (response['data'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
        );
        notifyListeners();
        // Persist to cache so next app launch shows badges instantly
        _saveCachedCounts();
      }
    } catch (e) {
      AppLogger.error("Error fetching category counts: $e");
    }
  }

  // Helper to get category by name
  Map<String, dynamic>? getCategoryByName(String name) {
    try {
      return _categories.firstWhere((c) => c['name'].toString().toLowerCase() == name.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  // Simple icon mapper if the DB icon name doesn't match Icons.xxx
  IconData getIconData(String iconName) {
    String name = iconName.toLowerCase();
    if (name.contains('.')) name = name.split('.').last;
    
    switch (name) {
      case 'warden':
      case 'group':
        return Icons.group;
      case 'security':
      case 'shield':
        return Icons.shield;
      case 'maintenance':
      case 'build':
      case '0e148':
        return Icons.build;
      case 'internet':
      case 'wifi':
        return Icons.wifi;
      case 'food':
      case 'restaurant':
        return Icons.restaurant;
      case 'laundry':
      case 'local_laundry_service':
        return Icons.local_laundry_service;
      case 'electrical':
      case 'bolt':
        return Icons.bolt;
      case 'plumbing':
      case 'water_drop':
        return Icons.water_drop;
      default:
        return Icons.category;
    }
  }

  Color getColor(String? colorHex) {
    if (colorHex == null || colorHex.isEmpty) return Colors.blue;
    try {
      if (colorHex.startsWith('#')) {
        return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
      } else if (colorHex.startsWith('0x')) {
        return Color(int.parse(colorHex));
      }
      return Colors.blue;
    } catch (_) {
      return Colors.blue;
    }
  }
  Future<Map<String, dynamic>> saveCategory(Map<String, dynamic> categoryData) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.saveCategory(categoryData);
      if (response['status'] == 'success') {
        // Wait a moment to ensure the backend has processed the save
        await Future.delayed(const Duration(milliseconds: 300));
        await fetchCategories();
        return {'success': true};
      }
      return {'success': false, 'message': response['message'] ?? 'Failed to save category'};
    } catch (e) {
      AppLogger.error("Error saving category: $e");
      return {'success': false, 'message': 'Failed to save category'};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> deleteCategory(String id) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.deleteCategory(id);
      if (response['status'] == 'success') {
        await fetchCategories();
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error("Error deleting category: $e");
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
