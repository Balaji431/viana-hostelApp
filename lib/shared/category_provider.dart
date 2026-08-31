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
  bool _isFetchingCounts = false; // guard against concurrent duplicate HTTP calls

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

  /// Normalize department keys across variations (e.g. Maintenance -> maintenance, messages -> warden)
  /// IMPORTANT: 'parent_warden' must be checked BEFORE 'warden' — otherwise the generic
  /// contains('warden') check would swallow it and map it to 'warden' (Students badge).
  String _normalizeKey(String key) {
    final lower = key.trim().toLowerCase();
    // parent_warden must come first — it contains 'warden' but is a separate category
    if (lower == 'parent_warden' || lower.contains('parent')) return 'parent_warden';
    if (lower == 'messages' || lower == 'warden' || lower.contains('warden')) return 'warden';
    if (lower.contains('maint')) return 'maintenance';
    if (lower.contains('sec')) return 'security';
    return lower;
  }

  /// Immediately increment a category's unread count in memory (0 ms update on incoming message).
  void incrementUnread(String categoryName, [int amount = 1]) {
    final normKey = _normalizeKey(categoryName);

    bool found = false;
    for (final k in _unreadCounts.keys.toList()) {
      if (_normalizeKey(k) == normKey) {
        _unreadCounts[k] = (_unreadCounts[k] ?? 0) + amount;
        found = true;
        break;
      }
    }
    if (!found) {
      _unreadCounts[normKey] = amount;
    }
    notifyListeners();
    _saveCachedCounts();
  }

  /// Immediately zero a category's unread count in memory (call when user opens a chat).
  /// This makes the red badge vanish instantly without waiting for the next API poll.
  void setUnreadCount(String categoryName, int count) {
    final normKey = _normalizeKey(categoryName);
    bool found = false;
    for (final k in _unreadCounts.keys.toList()) {
      if (_normalizeKey(k) == normKey) {
        _unreadCounts[k] = count;
        found = true;
        break;
      }
    }
    if (!found) {
      _unreadCounts[normKey] = count;
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
        if (response['group_name'] != null && response['group_name'].toString().isNotEmpty) {
          _assignedStaff['group_name'] = response['group_name'].toString();
        }
        notifyListeners();
      }
    } catch (e) {
      AppLogger.error("Error fetching assigned staff: $e");
    }
  }

  List<String> get staffRoleNames {
    final Set<String> rolesSet = {'Warden', 'Security', 'Maintenance'};
    for (var c in _categories) {
      if ((c['is_staff_role'] ?? 1) == 1) {
        String name = c['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          if (name.toLowerCase().contains('warden')) {
            name = 'Warden';
          } else if (name.toLowerCase().contains('secur')) {
            name = 'Security';
          } else if (name.toLowerCase().contains('maint')) {
            name = 'Maintenance';
          }
          rolesSet.add(name);
        }
      }
    }
    return rolesSet.toList();
  }

  void setCategories(List<Map<String, dynamic>> categories) {
    _categories = categories;
    notifyListeners();
  }

  int getUnreadCount(String categoryName) {
    final normKey = _normalizeKey(categoryName);

    for (final entry in _unreadCounts.entries) {
      if (_normalizeKey(entry.key) == normKey) return entry.value;
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

  Future<void> fetchCounts({String? wardenUsername, String? studentUsername, bool force = false}) async {
    // Prevent concurrent duplicate HTTP calls.
    // Two callers firing within the same frame both pass the debounce timestamp
    // check before either sets _lastFetchTime — the flag stops the second one.
    if (_isFetchingCounts && !force) return;

    final now = DateTime.now();
    if (!force &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < const Duration(seconds: 5) &&
        _lastWardenUsername == wardenUsername &&
        _lastStudentUsername == studentUsername) {
      return;
    }
    _isFetchingCounts = true;
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
      AppLogger.error('Error fetching category counts: $e');
    } finally {
      _isFetchingCounts = false;
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

  // Dynamic icon mapper matching Admin Category Manager choices
  IconData getIconData(String iconName) {
    String name = iconName.toLowerCase().trim();
    if (name.contains('.')) name = name.split('.').last;
    
    switch (name) {
      case 'warden':
      case 'group':
      case 'groups':
      case 'people':
      case 'users':
        return Icons.group;
      case 'security':
      case 'shield':
      case 'lock':
      case 'verified_user':
        return Icons.security;
      case 'maintenance':
      case 'build':
      case 'tools':
      case 'repair':
      case 'handyman':
      case 'construction':
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
      case 'flash':
        return Icons.bolt;
      case 'plumbing':
      case 'water_drop':
      case 'water':
        return Icons.water_drop;
      case 'home':
      case 'house':
        return Icons.home;
      case 'person':
      case 'user':
      case 'account_circle':
        return Icons.person;
      case 'phone':
      case 'call':
        return Icons.phone;
      case 'email':
      case 'mail':
        return Icons.email;
      case 'warning':
      case 'alert':
        return Icons.warning;
      case 'info':
        return Icons.info;
      case 'camera':
      case 'photo':
        return Icons.camera_alt;
      case 'settings':
      case 'gear':
        return Icons.settings;
      case 'chat':
      case 'message':
        return Icons.chat;
      case 'assignment':
      case 'report':
        return Icons.assignment;
      case 'cleaning':
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'ac_unit':
      case 'ac':
        return Icons.ac_unit;
      default:
        if (name.contains('warden')) return Icons.group;
        if (name.contains('sec')) return Icons.security;
        if (name.contains('maint')) return Icons.build;
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
