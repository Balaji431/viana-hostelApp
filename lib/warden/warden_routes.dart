import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import 'screens/warden_home_tab.dart';
import 'screens/warden_attendance_tab.dart';
import 'screens/warden_biometric_screen.dart';
import 'screens/warden_reports_tab.dart';
import 'screens/warden_management_tab.dart';
import 'screens/warden_room_change_requests_screen.dart';
import 'screens/warden_room_search_screen.dart';
import 'screens/warden_chat_interface.dart';
import '../admin/screens/temporary_stay_admin_screen.dart';

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
    const WardenTabItem(
      label: 'Temp Stay',
      icon: Icons.hotel_outlined,
      activeIcon: Icons.hotel,
      page: TemporaryStayAdminScreen(),
    ),
    const WardenTabItem(
      label: 'Biometric',
      icon: Icons.fingerprint_rounded,
      activeIcon: Icons.fingerprint,
      page: WardenBiometricScreen(),
    ),
    WardenTabItem(
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      activeIcon: Icons.bar_chart,
      page: WardenReportsTab(initialCategory: reportsCategoryFilter),
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
  if (channel.toLowerCase() == 'temporary_stay' || channel.toLowerCase() == 'temp_stay') {
    return const TemporaryStayAdminScreen();
  }
  return WardenChatInterface(channel: channel);
}
