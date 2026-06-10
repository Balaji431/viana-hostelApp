import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/styles.dart';
import '../shared/widgets/skeuo_button.dart';
import 'simple_admin_screen.dart';

class AdminPortalLauncher extends StatelessWidget {
  const AdminPortalLauncher({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HierarchicalHostelProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.navyDark, AppColors.navy],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings, color: AppColors.gold, size: 32),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Admin Portal',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hierarchical Management System',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
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
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
