import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import '../warden/screens/warden_reports_tab.dart';
import 'screens/security_home_tab.dart';

class SecurityTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const SecurityTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<SecurityTabItem> getSecurityTabs(UserProvider user, {String? reportsCategoryFilter}) {
  return [
    const SecurityTabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      page: SecurityHomeTab(),
    ),
    SecurityTabItem(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      page: WardenReportsTab(initialCategory: reportsCategoryFilter),
    ),
    const SecurityTabItem(
      label: 'Settings',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      page: SettingsPage(),
    ),
  ];
}
