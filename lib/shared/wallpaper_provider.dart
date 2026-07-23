import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a wallpaper option.
class WallpaperOption {
  final String id;
  final String label;
  final String? assetPath;   // null if custom or default theme
  final Color previewColor;  // used as fallback color in thumbnail

  const WallpaperOption({
    required this.id,
    required this.label,
    this.assetPath,
    required this.previewColor,
  });
}

class WallpaperProvider with ChangeNotifier {
  static const String _baseKeyType = 'wallpaper_type';
  static const String _baseKeyValue = 'wallpaper_value';

  static const List<WallpaperOption> defaultWallpapers = [
    WallpaperOption(
      id: 'water',
      label: 'Water',
      assetPath: 'assets/wallpapers/wallpaper_water.jpg',
      previewColor: Color(0xFF00A896),
    ),
    WallpaperOption(
      id: 'ocean',
      label: 'Ocean',
      assetPath: 'assets/wallpapers/wallpaper_ocean.jpg',
      previewColor: Color(0xFF2980B9),
    ),
    WallpaperOption(
      id: 'forest',
      label: 'Forest',
      assetPath: 'assets/wallpapers/wallpaper_forest.jpg',
      previewColor: Color(0xFF1E5E3E),
    ),
    WallpaperOption(
      id: 'marble',
      label: 'Marble',
      assetPath: 'assets/wallpapers/wallpaper_marble.jpg',
      previewColor: Color(0xFFE8E8E8),
    ),
    WallpaperOption(
      id: 'royal_navy',
      label: 'Royal Navy',
      assetPath: 'assets/wallpapers/wallpaper_royal_navy.jpg',
      previewColor: Color(0xFF1A2744),
    ),
  ];

  String _currentUsername = '';
  String _type = 'default';    // 'default' | 'asset' | 'custom'
  String _value = 'linen';     // asset id OR file path

  String get type => _type;
  String get value => _value;
  String get currentUsername => _currentUsername;

  /// True when using the classic default background theme (no wallpaper image)
  bool get isDefault => _type == 'default';

  /// Asset path for the currently selected wallpaper option (null if custom or default theme)
  String? get assetPath {
    if (_type == 'asset') {
      final match = defaultWallpapers.where((w) => w.id == _value);
      return match.isNotEmpty ? match.first.assetPath : defaultWallpapers.first.assetPath;
    }
    return null;
  }

  /// Custom device file path (null unless user picked from gallery)
  String? get customFilePath => _type == 'custom' ? _value : null;

  WallpaperProvider() {
    _load();
  }

  String _getKey(String baseKey) {
    if (_currentUsername.trim().isEmpty) {
      return '${baseKey}_default';
    }
    return '${baseKey}_${_currentUsername.trim().toLowerCase()}';
  }

  /// Syncs current user account so wallpaper settings are isolated per user profile.
  void syncUser(String username) {
    final cleanName = username.trim();
    if (_currentUsername != cleanName) {
      _currentUsername = cleanName;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _type = prefs.getString(_getKey(_baseKeyType)) ?? 'default';
      _value = prefs.getString(_getKey(_baseKeyValue)) ?? 'linen';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setDefault() async {
    _type = 'default';
    _value = 'linen';
    notifyListeners();
    await _save();
  }

  Future<void> setAssetWallpaper(String id) async {
    _type = 'asset';
    _value = id;
    notifyListeners();
    await _save();
  }

  Future<void> setCustomWallpaper(String filePath) async {
    _type = 'custom';
    _value = filePath;
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_getKey(_baseKeyType), _type);
      await prefs.setString(_getKey(_baseKeyValue), _value);
    } catch (_) {}
  }
}
