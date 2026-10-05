import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import 'screens/home_screen.dart';
import 'screens/attendance_page.dart' show AttendancePage, BiometricHistoryPage;

import 'screens/student_vacate_status_screen.dart';
import 'screens/student_wallet_screen.dart';
import 'screens/settings_page.dart';
import 'screens/warden_chat_screen.dart';
import 'screens/security_chat_screen.dart';
import 'screens/maintenance_chat_screen.dart';
import 'screens/parent_warden_chat_screen.dart';

class StudentTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const StudentTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<StudentTabItem> getStudentTabs(UserProvider user) {
  return const [
    StudentTabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      page: StudentHomeScreen(),
    ),
    StudentTabItem(
      label: 'Attendance',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month,
      page: AttendancePage(),
    ),

    StudentTabItem(
      label: 'Vacate',
      icon: Icons.exit_to_app_outlined,
      activeIcon: Icons.exit_to_app_rounded,
      page: StudentVacateStatusScreen(),
    ),
    StudentTabItem(
      label: 'Wallet',
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      page: StudentWalletScreen(),
    ),
    StudentTabItem(
      label: 'Bio History',
      icon: Icons.fingerprint,
      activeIcon: Icons.fingerprint,
      page: BiometricHistoryPage(),
    ),
    StudentTabItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      page: SettingsPage(),
    ),
  ];
}

List<StudentTabItem> getGuestTabs(UserProvider user) {
  return const [
    StudentTabItem(
      label: 'Home',
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      page: StudentHomeScreen(),
    ),
    StudentTabItem(
      label: 'Wallet',
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      page: StudentWalletScreen(),
    ),
    StudentTabItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      page: SettingsPage(),
    ),
  ];
}

List<StudentTabItem> getParentTabs(UserProvider user) {
  return const [
    StudentTabItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      page: StudentHomeScreen(),
    ),
    StudentTabItem(
      label: 'Attendance',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month,
      page: AttendancePage(),
    ),
    StudentTabItem(
      label: 'Bio History',
      icon: Icons.fingerprint,
      activeIcon: Icons.fingerprint,
      page: BiometricHistoryPage(),
    ),
    StudentTabItem(
      label: 'Settings',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      page: SettingsPage(),
    ),
  ];
}

Widget getStudentChatWidget(String channel, bool isParent, String? requestId) {
  switch (channel.toLowerCase()) {
    case 'warden':
      return isParent
          ? ParentWardenChatScreen(requestId: requestId)
          : WardenChatScreen(requestId: requestId);
    case 'security':
      return SecurityChatScreen(requestId: requestId);
    default:
      return MaintenanceChatScreen(requestId: requestId, department: channel);
  }
}
