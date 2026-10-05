import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/styles.dart';
import '../shared/user_provider.dart';
import '../shared/wallpaper_provider.dart';
import '../shared/widgets/skeuo_button.dart';
import '../shared/widgets/user_avatar_header.dart';
import 'simple_admin_screen.dart';

class AdminPortalLauncher extends StatelessWidget {
  const AdminPortalLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;
    UserProvider? user;
    try {
      user = context.watch<UserProvider>();
    } catch (_) {}

    final String displayName = user?.userName.isNotEmpty == true ? user!.userName : 'Admin';
    final String displayId = user?.username.isNotEmpty == true ? "ID: ${user!.username}" : 'ID: Admin';

    String initials = 'AD';
    final parts = displayName.trim().split(RegExp(r'\s+'));
    if (parts.isNotEmpty) {
      if (parts.length > 1 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else if (parts[0].isNotEmpty) {
        initials = parts[0].length >= 2 ? parts[0].substring(0, 2).toUpperCase() : parts[0][0].toUpperCase();
      }
    }

    return Consumer<HierarchicalHostelProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header Badge matching Image 5
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : null,
                  gradient: isDark ? null : SkeuomorphicColors.royalContentGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.12)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (user != null)
                      UserHeaderAvatar(user: user, size: 44)
                    else
                      Container(
                        width: 44,
                        height: 44,
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
                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1B2B48),
                              fontFamily: 'Lato',
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName.toUpperCase(),
                            style: const TextStyle(
                              fontFamily: 'Lato',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            displayId,
                            style: TextStyle(
                              fontFamily: 'Lato',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : SkeuomorphicColors.residenceMutedText,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Statistics Cards
              Row(
                children: [
                  Expanded(
                    child: _buildFeatureCard(
                      context,
                      icon: Icons.hotel,
                      title: '${provider.hostels.length}',
                      subtitle: 'Hostels',
                      color: AppColors.gold,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeatureCard(
                      context,
                      icon: Icons.layers,
                      title: '${provider.hostels.fold<int>(0, (sum, h) => sum + ((h as dynamic).totalZones ?? 0) as int)}',
                      subtitle: 'Zones',
                      color: Colors.blue,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeatureCard(
                      context,
                      icon: Icons.meeting_room,
                      title: '${provider.hostels.fold<int>(0, (sum, h) => sum + ((h as dynamic).totalSubZones ?? 0) as int)}',
                      subtitle: 'Wings',
                      color: Colors.green,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildFeatureCard(
                      context,
                      icon: Icons.door_sliding,
                      title: '${provider.hostels.fold<int>(0, (sum, h) => sum + ((h as dynamic).totalRooms ?? 0) as int)}',
                      subtitle: 'Rooms',
                      color: Colors.orange,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // Launch Button
              SkeuoButton(
                text: 'Launch Admin Portal',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SimpleAdminScreen(),
                    ),
                  );
                },
                icon: Icons.launch,
                width: double.infinity,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : color.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
