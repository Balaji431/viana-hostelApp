import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';
import 'auth_wrapper.dart';
import 'widgets/access_denied_screen.dart';

class RoleGuard extends StatelessWidget {
  final Widget child;
  final List<UserRole> allowedRoles;

  const RoleGuard({
    super.key,
    required this.child,
    required this.allowedRoles,
  });

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context);

    if (!user.isLoggedIn) {
      return const AuthWrapper();
    }

    if (!allowedRoles.contains(user.role)) {
      return const AccessDeniedScreen();
    }

    return child;
  }
}
