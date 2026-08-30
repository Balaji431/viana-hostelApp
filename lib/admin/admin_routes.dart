import 'package:flutter/material.dart';
import '../shared/user_provider.dart';
import '../student/screens/settings_page.dart';
import '../warden/screens/warden_management_tab.dart';
import 'admin_screen.dart';
import 'screens/admin_activity_logs_screen.dart';
import 'screens/temporary_stay_admin_screen.dart';
import 'screens/category_manager_screen.dart';
import 'screens/admin_hostel_manager_screen.dart';
import 'staff_mapping_manager_screen.dart';
import 'screens/hostel_detail_screen.dart';
import 'screens/room_master_screen.dart';
import '../core/models/hierarchical_hostel_model.dart';
import '../shared/role_guard.dart';

class AdminTabItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;

  const AdminTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
}

List<AdminTabItem> getAdminTabs(UserProvider user) {
  return const [
    AdminTabItem(
      label: 'Admin',
      icon: Icons.admin_panel_settings_outlined,
      activeIcon: Icons.admin_panel_settings,
      page: AdminScreen(),
    ),
    AdminTabItem(
      label: 'Activity Logs',
      icon: Icons.assignment_outlined,
      activeIcon: Icons.assignment,
      page: AdminActivityLogsScreen(),
    ),
    AdminTabItem(
      label: 'Temp Stay',
      icon: Icons.hotel_outlined,
      activeIcon: Icons.hotel,
      page: TemporaryStayAdminScreen(),
    ),
    AdminTabItem(
      label: 'Management',
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      page: WardenManagementTab(),
    ),
    AdminTabItem(
      label: 'Settings',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      page: SettingsPage(),
    ),
  ];
}

Widget? buildAdminSubRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/category_manager':
      return const RoleGuard(
        allowedRoles: [UserRole.admin],
        child: CategoryManagerScreen(showAppBar: true),
      );
    case '/hostel_manager':
      return const RoleGuard(
        allowedRoles: [UserRole.admin],
        child: AdminHostelManagerScreen(showAppBar: true),
      );
    case '/mapping_manager':
      return const RoleGuard(
        allowedRoles: [UserRole.admin],
        child: StaffMappingManagerScreen(showAppBar: true),
      );
    case '/room_master':
      return RoleGuard(
        allowedRoles: const [UserRole.admin],
        child: RoomMasterScreen(),
      );
    case '/hostel_detail':
      final args = settings.arguments as HierarchicalHostel;
      return RoleGuard(
        allowedRoles: const [UserRole.admin],
        child: HostelDetailScreen(hostel: args, showAppBar: true),
      );
    default:
      return null;
  }
}
