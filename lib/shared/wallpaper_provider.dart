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
    WallpaperOption(
      id: 'night_dunes',
      label: 'Night Dunes',
      assetPath: 'assets/wallpapers/wallpaper_night_dunes.jpg',
      previewColor: Color(0xFF0F1D35),
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

  /// True if current wallpaper has a dark background requiring white headings & frosted glass cards
  bool get isDarkTheme =>
      _type == 'custom' ||
      (_type == 'asset' && _value != 'marble');

  bool get isNightDunes => _type == 'asset' && _value == 'night_dunes';

  /// Text and icon colors optimized for the active background wallpaper
  Color get headingColor => isDarkTheme ? Colors.white : const Color(0xFF1B2B48);
  Color get sectionHeaderColor => isDarkTheme ? Colors.white : const Color(0xFF333333);
  Color get subHeadingColor => isDarkTheme ? Colors.white70 : const Color(0xFF666666);
  Color get bodyTextColor => isDarkTheme ? Colors.white : const Color(0xFF2D3748);
  Color get mutedTextColor => isDarkTheme ? Colors.white54 : const Color(0xFF718096);
  Color get headerIconColor => isDarkTheme ? Colors.white70 : const Color(0xFF4A5568);
  Color get headerBorderColor => isDarkTheme ? Colors.white30 : const Color(0xFFCCCCCC);
  Color get primaryAccentColor => const Color(0xFFD4AF37); // Gold

  /// Desktop outer container background gradient
  LinearGradient get ambientBackgroundGradient {
    if (_type == 'asset') {
      switch (_value) {
        case 'forest':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF071B12), Color(0xFF103322), Color(0xFF071B12)],
          );
        case 'ocean':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A192F), Color(0xFF17365D), Color(0xFF0A192F)],
          );
        case 'water':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF052126), Color(0xFF0E3E47), Color(0xFF052126)],
          );
        case 'marble':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E232A), Color(0xFF2C3540), Color(0xFF1E232A)],
          );
        case 'royal_navy':
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF0B132B)],
          );
        case 'night_dunes':
        default:
          return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F1520), Color(0xFF1A2235), Color(0xFF0F1520)],
          );
      }
    }
    // Default linen/light ambient canvas
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF0F1520), Color(0xFF1A2235), Color(0xFF0F1520)],
    );
  }

  /// Desktop sidebar container background color
  Color get sidebarColor {
    if (_type == 'asset') {
      switch (_value) {
        case 'forest':
          return const Color(0xFF0D2418);
        case 'ocean':
          return const Color(0xFF0F223B);
        case 'water':
          return const Color(0xFF0A2B32);
        case 'royal_navy':
          return const Color(0xFF121D33);
        case 'marble':
          return const Color(0xFF161E28);
        case 'night_dunes':
        default:
          return const Color(0xFF141E2E);
      }
    }
    return const Color(0xFF141E2E);
  }

  /// Desktop sidebar border color
  Color get sidebarBorderColor =>
      isDarkTheme ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);

  /// Card fill color (glass on dark, opaque card on default)
  Color get cardFillColor => isDarkTheme
      ? const Color(0xFF121B2B).withOpacity(0.72)
      : Colors.white.withOpacity(0.95);

  /// Card border color
  Color get cardBorderColor => isDarkTheme
      ? Colors.white.withOpacity(0.16)
      : const Color(0xFFD4AF37).withOpacity(0.35);

  /// Card decoration tailored to the active theme
  BoxDecoration get cardDecoration => BoxDecoration(
        color: cardFillColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor, width: 1),
        boxShadow: isDarkTheme
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      );

  /// Bottom Navigation Bar background tint
  Color get navBarBackgroundColor => isDarkTheme
      ? const Color(0xFF101928).withOpacity(0.85)
      : const Color(0xFFF5F0E6).withOpacity(0.88);

  /// Bottom Navigation Bar border color
  Color get navBarBorderColor => isDarkTheme
      ? const Color(0xFFD4AF37).withOpacity(0.4)
      : const Color(0xFFD4AF37).withOpacity(0.3);

  /// Bottom Navigation Bar unselected icon & text color
  Color get navUnselectedColor =>
      isDarkTheme ? Colors.white60 : const Color(0xFF4A4A4A);

  /// Bottom Navigation Bar Jelly slider pill gradient
  LinearGradient get navPillGradient => isDarkTheme
      ? LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.22),
            Colors.white.withOpacity(0.08),
          ],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF5F0E6).withOpacity(0.65),
            const Color(0xFFF5F0E6).withOpacity(0.35),
          ],
        );

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
