import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../admin/screens/admin_hostel_manager_screen.dart';
import '../admin/screens/category_manager_screen.dart';
import '../admin/screens/hostel_detail_screen.dart';
import '../admin/screens/room_master_screen.dart';
import '../admin/screens/temporary_stay_admin_screen.dart';
import '../admin/staff_mapping_manager_screen.dart';
import '../core/models/hierarchical_hostel_model.dart';
import '../core/styles.dart';
import '../student/screens/maintenance_chat_screen.dart';
import '../student/screens/parent_warden_chat_screen.dart';
import '../student/screens/security_chat_screen.dart';
import '../student/screens/warden_chat_screen.dart';
import '../warden/screens/warden_chat_interface.dart';
import 'auth_wrapper.dart';
import 'main_layout.dart';
import 'role_guard.dart';
import 'user_provider.dart';

Widget buildDeferredRoutePage(BuildContext context, RouteSettings settings) {
  switch (settings.name) {
    case '/chat':
      return _buildChatRoute(context, settings.arguments);
    case '/security_chat':
      return _buildSecurityChatRoute(settings.arguments);
    case '/announcements':
      return const MainResponsiveLayout(showAnnouncements: true);
    case '/temporary_stay_admin':
      return const RoleGuard(
        allowedRoles: [UserRole.admin, UserRole.warden, UserRole.staff],
        child: TemporaryStayAdminScreen(),
      );
    case '/category_manager':
      return _buildAdminAdaptiveRoute(
        context,
        desktopRoute: '/category_manager',
        mobile: const CategoryManagerScreen(showAppBar: true),
      );
    case '/hostel_manager':
      return _buildAdminAdaptiveRoute(
        context,
        desktopRoute: '/hostel_manager',
        mobile: const AdminHostelManagerScreen(showAppBar: true),
      );
    case '/mapping_manager':
      return _buildAdminAdaptiveRoute(
        context,
        desktopRoute: '/mapping_manager',
        mobile: const StaffMappingManagerScreen(showAppBar: true),
      );
    case '/room_master':
      return const RoleGuard(
        allowedRoles: [UserRole.admin],
        child: RoomMasterScreen(),
      );
    case '/hostel_detail':
      return _buildHostelDetailRoute(context, settings.arguments);
    default:
      return const AuthWrapper();
  }
}

Widget _buildChatRoute(BuildContext context, Object? args) {
  Map<String, dynamic>? mapArgs;
  if (args is Map) {
    mapArgs = Map<String, dynamic>.from(args);
  }

  final requestId = args is String ? args : mapArgs?['request_id']?.toString();

  String department = mapArgs?['department']?.toString().toLowerCase() ?? '';

  if (department.isEmpty && requestId != null && requestId.isNotEmpty) {
    final cleanId = requestId.trim().toUpperCase();
    if (cleanId.startsWith('WAR-')) {
      department = 'warden';
    } else if (cleanId.startsWith('PAR-')) {
      department = 'parent_warden';
    } else if (cleanId.startsWith('SEC-')) {
      department = 'security';
    } else {
      department = 'maintenance';
    }
  }

  final user = Provider.of<UserProvider>(context, listen: false);

  if (!user.isLoggedIn) {
    return const AuthWrapper();
  }

  if (user.role == UserRole.warden ||
      user.role == UserRole.security ||
      user.role == UserRole.maintenance ||
      user.role == UserRole.staff ||
      user.role == UserRole.admin) {
    String channel = department;
    if (channel == 'parent_warden') {
      channel = 'parent_warden';
    } else if (user.role == UserRole.security) {
      channel = 'security';
    } else if (user.role == UserRole.maintenance ||
        user.role == UserRole.staff) {
      channel = user.roleName.isNotEmpty ? user.roleName : 'maintenance';
    } else if (user.role == UserRole.warden) {
      if (requestId != null &&
          (requestId.toUpperCase().startsWith('PAR-') ||
              department == 'parent_warden')) {
        channel = 'parent_warden';
      } else {
        channel = 'warden';
      }
    } else {
      channel = 'warden';
    }

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: WardenChatInterface(
          channel: channel,
          initialRequestId: requestId,
        ),
      ),
    );
  }

  Widget targetScreen;
  if (department == 'warden' || department == 'parent_warden') {
    targetScreen = user.isParent
        ? ParentWardenChatScreen(requestId: requestId, department: 'Warden')
        : WardenChatScreen(requestId: requestId, department: 'Warden');
  } else if (department == 'security') {
    targetScreen = SecurityChatScreen(requestId: requestId);
  } else {
    final capitalizedDept = department.isNotEmpty
        ? department[0].toUpperCase() + department.substring(1)
        : 'Maintenance';
    targetScreen = MaintenanceChatScreen(
      requestId: requestId,
      department: capitalizedDept,
    );
  }

  return LinenGridBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      body: targetScreen,
    ),
  );
}

Widget _buildSecurityChatRoute(Object? args) {
  Map<String, dynamic>? mapArgs;
  if (args is Map) {
    mapArgs = Map<String, dynamic>.from(args);
  }
  final requestId = args is String ? args : mapArgs?['request_id']?.toString();
  final senderId = mapArgs?['sender_id']?.toString() ?? '';
  return RoleGuard(
    allowedRoles: const [
      UserRole.security,
      UserRole.warden,
      UserRole.admin,
    ],
    child: MainResponsiveLayout(
      initialRequestId: requestId,
      senderId: senderId,
      isSecurity: true,
    ),
  );
}

Widget _buildAdminAdaptiveRoute(
  BuildContext context, {
  required String desktopRoute,
  required Widget mobile,
}) {
  final isDesktop = MediaQuery.of(context).size.width >= 768;
  return RoleGuard(
    allowedRoles: const [UserRole.admin],
    child:
        isDesktop ? MainResponsiveLayout(initialRoute: desktopRoute) : mobile,
  );
}

Widget _buildHostelDetailRoute(BuildContext context, Object? args) {
  final isDesktop = MediaQuery.of(context).size.width >= 768;
  return RoleGuard(
    allowedRoles: const [UserRole.admin],
    child: isDesktop
        ? MainResponsiveLayout(
            initialRoute: '/hostel_detail',
            initialRouteArgs: args,
          )
        : HostelDetailScreen(
            hostel: args as HierarchicalHostel,
            showAppBar: true,
          ),
  );
}
