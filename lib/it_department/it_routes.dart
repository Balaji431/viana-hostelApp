import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import 'screens/it_audit_history_screen.dart';
import 'screens/it_dashboard_screen.dart';
import 'screens/it_universal_search_screen.dart';

class ItTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const ItTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<ItTabItem> getItTabs(UserProvider user, {String? reportsCategoryFilter}) {
  return [
    const ItTabItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      page: ItDashboardScreen(),
    ),
    const ItTabItem(
      label: 'Audit Search',
      icon: Icons.fingerprint_rounded,
      activeIcon: Icons.fingerprint_rounded,
      page: ItUniversalSearchScreen(),
    ),
    const ItTabItem(
      label: 'Audit History',
      icon: Icons.history_rounded,
      activeIcon: Icons.history_toggle_off_rounded,
      page: ItAuditHistoryScreen(),
    ),
    const ItTabItem(
      label: 'Settings',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      page: SettingsPage(),
    ),
  ];
}
