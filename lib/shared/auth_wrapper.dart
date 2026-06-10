import 'dart:async';

import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'user_provider.dart';
import '../student/screens/login_screen.dart';
import 'main_layout.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    unawaited(context.read<UserProvider>().checkPersistence());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userUpdate, _) {
        if (!userUpdate.isLoggedIn) {
          return const LoginScreen();
        }
        return const MainResponsiveLayout();
      },
    );
  }
}
