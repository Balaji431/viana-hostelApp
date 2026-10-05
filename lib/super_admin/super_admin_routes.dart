import 'package:flutter/material.dart';
import '../admin/admin_screen.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import 'screens/super_admin_dashboard_screen.dart';

class SuperAdminTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const SuperAdminTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<SuperAdminTabItem> getSuperAdminTabs(UserProvider user) {
  return const [
    SuperAdminTabItem(
      label: 'Super Admin',
      icon: Icons.admin_panel_settings_outlined,
      activeIcon: Icons.admin_panel_settings_rounded,
      page: AdminScreen(title: 'Super Admin'),
    ),
    SuperAdminTabItem(
      label: 'Issues Reports',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment_rounded,
      page: SuperAdminDashboardScreen(title: 'Issues Reports'),
    ),
    SuperAdminTabItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      page: SettingsPage(),
    ),
  ];
}
