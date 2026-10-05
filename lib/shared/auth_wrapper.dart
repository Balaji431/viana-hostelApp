import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'user_provider.dart';
import '../student/screens/login_screen.dart';
import 'main_layout.dart' deferred as main_layout;
import 'category_provider.dart';
import 'request_provider.dart';
import '../core/providers/hierarchical_hostel_provider.dart';
import '../core/providers/mapping_provider.dart';
import '../core/providers/allocation_provider.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  Future<void>? _layoutLoader;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    if (!user.isLoggedIn) {
      return const LoginScreen();
    }

    _layoutLoader ??= main_layout.loadLibrary();
    return FutureBuilder<void>(
      future: _layoutLoader,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          if (snapshot.hasError) {
            return Scaffold(
              backgroundColor: const Color(0xFF0F1520),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, color: Colors.amber, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load dashboard resources.\nPlease check your internet connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        setState(() {
                          _layoutLoader = main_layout.loadLibrary();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          // ─── DASHBOARD-ONLY PROVIDERS ─────────────────────────────────────
          // Scoped here so they are NEVER instantiated during the login screen.
          // They are created exactly once when a logged-in user's dashboard
          // loads, then disposed automatically when the user logs out.
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => RequestProvider()),
              ChangeNotifierProvider(create: (_) => CategoryProvider()),
              ChangeNotifierProvider(create: (_) => HierarchicalHostelProvider()),
              ChangeNotifierProvider(create: (_) => MappingProvider()),
              ChangeNotifierProvider(create: (_) => AllocationProvider()),
            ],
            child: main_layout.MainResponsiveLayout(),
          );
        }
        return const Scaffold(
          backgroundColor: Color(0xFF0F1520),
          body: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        );
      },
    );
  }
}
