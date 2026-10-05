import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vianasoft_stay/core/api_service.dart';
import 'package:vianasoft_stay/core/styles.dart';
import 'package:vianasoft_stay/shared/user_provider.dart';
import 'package:vianasoft_stay/shared/wallpaper_provider.dart';

/// A reusable round circular avatar for headers and dashboards.
/// Seamlessly reflects uploaded profile pictures or falls back to golden initials.
/// Tapping defaults to opening the high-resolution full photo dialog.
class UserHeaderAvatar extends StatelessWidget {
  final UserProvider user;
  final double size;
  final VoidCallback? onTap;
  final bool showBorder;
  final bool isInteractive;

  const UserHeaderAvatar({
    super.key,
    required this.user,
    this.size = 44.0,
    this.onTap,
    this.showBorder = true,
    this.isInteractive = true,
  });

  static bool hasCustomPic(String? pic) {
    if (pic == null || pic.isEmpty || pic == 'profile.png' || pic == 'null') return false;
    return true;
  }

  static String getInitials(String name) {
    if (name.trim().isEmpty) return "U";
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].length >= 2 ? parts[0].substring(0, 2).toUpperCase() : parts[0][0].toUpperCase();
    }
    return "U";
  }

  Widget _buildInitialsContent(String initials) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: (size * 0.32).clamp(10.0, 36.0),
          fontWeight: FontWeight.w900,
          color: const Color(0xFF1B2B48),
          fontFamily: 'Lato',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPic = hasCustomPic(user.profilePic);
    final initials = getInitials(user.userName);

    Widget imageContent;
    if (hasPic) {
      final rawUrl = ApiService.resolveMediaUrl(user.profilePic);
      int tick = 0;
      try {
        tick = user.dashboardRefreshTick;
      } catch (_) {}
      final photoUrl = rawUrl.contains('?')
          ? '$rawUrl&tick=$tick'
          : '$rawUrl?tick=$tick';

      imageContent = ClipOval(
        child: Image.network(
          photoUrl,
          key: ValueKey('hdr_avatar_$photoUrl'),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, __, ___) => _buildInitialsContent(initials),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return _buildInitialsContent(initials);
          },
        ),
      );
    } else {
      imageContent = _buildInitialsContent(initials);
    }

    final avatarWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SkeuomorphicColors.goldGlossyGradient,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: showBorder ? Border.all(color: Colors.white.withOpacity(0.18), width: 1) : null,
      ),
      child: imageContent,
    );

    if (!isInteractive) return avatarWidget;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap ?? () => showFullPhotoDialog(context, user),
        child: Tooltip(
          message: hasPic ? 'Tap to view full photo' : 'Profile: ${user.userName}',
          child: avatarWidget,
        ),
      ),
    );
  }
}

/// Displays a high-resolution, zoomable modal dialog with the user's photo and details.
void showFullPhotoDialog(
  BuildContext context,
  UserProvider user, {
  int? version,
  VoidCallback? onChangePhoto,
}) {
  WallpaperProvider? wallpaper;
  try {
    wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
  } catch (_) {}
  final isDark = wallpaper?.isDarkTheme ?? false;
  final hasPic = UserHeaderAvatar.hasCustomPic(user.profilePic);
  final rawUrl = ApiService.resolveMediaUrl(user.profilePic);
  int v = 0;
  try {
    v = version ?? user.dashboardRefreshTick;
  } catch (_) {
    v = version ?? 0;
  }
  final photoUrl = rawUrl.contains('?') ? '$rawUrl&v=$v' : '$rawUrl?v=$v';
  final initials = UserHeaderAvatar.getInitials(user.userName);

  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131D2E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.18) : const Color(0xFFD4AF37).withOpacity(0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD4AF37).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_circle_rounded,
                          color: Color(0xFFD4AF37),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.userName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF1B2B48),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user.role == UserRole.student
                                  ? 'Reg No: ${user.registerNo}'
                                  : 'User ID: ${user.username}',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Photo Display Container
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      height: 270,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: hasPic
                          ? InteractiveViewer(
                              minScale: 0.8,
                              maxScale: 4.0,
                              child: Center(
                                child: Image.network(
                                  photoUrl,
                                  fit: BoxFit.contain,
                                  width: double.infinity,
                                  height: double.infinity,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value: loadingProgress.expectedTotalBytes != null
                                            ? loadingProgress.cumulativeBytesLoaded /
                                                loadingProgress.expectedTotalBytes!
                                            : null,
                                        color: const Color(0xFFD4AF37),
                                      ),
                                    );
                                  },
                                  errorBuilder: (context, error, stackTrace) => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Unable to display photo',
                                        style: TextStyle(color: isDark ? Colors.white60 : Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: SkeuomorphicColors.goldGlossyGradient,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      initials,
                                      style: const TextStyle(
                                        fontSize: 38,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1B2B48),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Default Initials Avatar',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'No custom profile photo uploaded yet',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                // Location / Hostel Info
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Icon(
                        Icons.home_work_outlined,
                        size: 16,
                        color: isDark ? Colors.white60 : Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          user.hostelName.isNotEmpty && user.hostelName != 'N/A'
                              ? 'Hostel: ${user.hostelName}${user.roomAllocation.isNotEmpty ? ' • Room: ${user.roomAllocation}' : ''}'
                              : (user.institution.isNotEmpty ? user.institution : 'VStay Portal'),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white70 : Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),

                // Action Buttons
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (onChangePhoto != null) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.camera_alt_outlined, size: 16),
                            label: Text(hasPic ? 'Change Photo' : 'Upload Photo'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                              side: BorderSide(
                                color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              onChangePhoto();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                            foregroundColor: isDark ? const Color(0xFF1B2B48) : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
