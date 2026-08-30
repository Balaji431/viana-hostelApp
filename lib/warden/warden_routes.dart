import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import 'screens/warden_home_tab.dart';
import 'screens/warden_attendance_tab.dart';
import 'screens/warden_reports_tab.dart';
import 'screens/warden_management_tab.dart';
import 'screens/warden_room_change_requests_screen.dart';
import 'screens/warden_room_search_screen.dart';
import 'screens/warden_chat_interface.dart';

class WardenTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const WardenTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<WardenTabItem> getWardenTabs(UserProvider user, {String? reportsCategoryFilter}) {
  return [
    const WardenTabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      page: WardenHomeTab(),
    ),
    const WardenTabItem(
      label: 'Attendance',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month,
      page: WardenAttendanceTab(),
    ),
    WardenTabItem(
      label: 'Room Change',
      icon: Icons.sync_outlined,
      activeIcon: Icons.sync,
      page: WardenRoomChangeRequestsScreen(wardenId: user.dbId ?? 1),
    ),
    WardenTabItem(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      page: WardenReportsTab(initialCategory: reportsCategoryFilter),
    ),
    const WardenTabItem(
      label: 'Management',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      page: WardenManagementTab(),
    ),
    const WardenTabItem(
      label: 'Room Search',
      icon: Icons.search_outlined,
      activeIcon: Icons.search,
      page: WardenRoomSearchScreen(),
    ),
    const WardenTabItem(
      label: 'Settings',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      page: SettingsPage(),
    ),
  ];
}

Widget getWardenReportsPage(String? filter) {
  return WardenReportsTab(initialCategory: filter);
}

Widget getWardenChatWidget(String channel) {
  return WardenChatInterface(channel: channel);
}
