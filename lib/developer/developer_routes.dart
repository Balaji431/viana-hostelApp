import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import '../super_admin/screens/super_admin_dashboard_screen.dart';

class DeveloperTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const DeveloperTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<DeveloperTabItem> getDeveloperTabs(UserProvider user) {
  return const [
    DeveloperTabItem(
      label: 'Developer Dashboard',
      icon: Icons.developer_mode_outlined,
      activeIcon: Icons.developer_mode_rounded,
      page: SuperAdminDashboardScreen(),
    ),
    DeveloperTabItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      page: SettingsPage(),
    ),
  ];
}
