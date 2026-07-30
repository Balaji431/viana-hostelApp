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
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userProvider = context.read<UserProvider>();
      // If already logged in from synchronous prefs restore — ready immediately
      if (userProvider.isLoggedIn) {
        setState(() => _isReady = true);
        unawaited(userProvider.checkPersistence());
      } else {
        // Need async check for edge cases (first launch, expired session etc.)
        unawaited(userProvider.checkPersistence().then((_) {
          if (mounted) setState(() => _isReady = true);
        }));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userUpdate, _) {
        // Show dark splash until persistence check completes
        if (!_isReady) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F1520),
            body: SizedBox.expand(),
          );
        }
        if (!userUpdate.isLoggedIn) {
          return const LoginScreen();
        }
        return const MainResponsiveLayout();
      },
    );
  }
}
