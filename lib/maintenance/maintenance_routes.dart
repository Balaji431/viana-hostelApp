import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import '../warden/screens/warden_reports_tab.dart';
import 'screens/maintenance_home_tab.dart';

class MaintenanceTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const MaintenanceTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<MaintenanceTabItem> getMaintenanceTabs(UserProvider user, {String? reportsCategoryFilter}) {
  return [
    const MaintenanceTabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      page: MaintenanceHomeTab(),
    ),
    MaintenanceTabItem(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      page: WardenReportsTab(initialCategory: reportsCategoryFilter),
    ),
    const MaintenanceTabItem(
      label: 'Settings',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      page: SettingsPage(),
    ),
  ];
}
