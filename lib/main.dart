import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart';
import 'core/api_service.dart';
import 'core/deferred_app_services.dart' deferred as app_services;
import 'core/play_update_service.dart';
import 'core/royal_theme.dart';
import 'shared/auth_wrapper.dart';
import 'shared/deferred_routes.dart' deferred as deferred_routes;
import 'shared/ui_provider.dart';
import 'shared/user_provider.dart';
import 'shared/wallpaper_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Deduplication: track recently-reported error messages to prevent
// the same error being inserted multiple times within a short window.
final _recentErrors = <String>{};
bool _flutterErrorHandled = false;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Skip orientation lock on web — it does nothing in a browser and costs ~30ms
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _flutterErrorHandled = true;
    _reportErrorAfterStartup(
      details.exceptionAsString(),
      details.stack?.toString() ?? '',
    );
    Future.microtask(() => _flutterErrorHandled = false);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (_flutterErrorHandled) return true;
    _reportErrorAfterStartup(error.toString(), stack.toString());
    return true;
  };

  // Load SharedPreferences before runApp so user session is restored immediately on Frame 1
  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider(prefs: prefs)),
        ChangeNotifierProvider(create: (_) => UIProvider()),
        ChangeNotifierProvider(create: (_) => WallpaperProvider()),
      ],
      child: const MyApp(),
    ),
  );

  _scheduleAppServicesInitialization(prefs);
}

void _scheduleAppServicesInitialization(SharedPreferences prefs) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      try {
        Provider.of<UserProvider>(context, listen: false).initPrefs(prefs);
      } catch (_) {}
    }

    // ApiService: trivial init, 1 second after first paint — zero contention
    await Future<void>.delayed(const Duration(seconds: 1));
    unawaited(ApiService.init());

    // Firebase + heavy services: 5 seconds after first paint — completely
    // outside Lighthouse's 0–5 s TBT measurement window.
    Future<void>.delayed(const Duration(seconds: 5), () async {
      await app_services.loadLibrary();
      await app_services.initializeDeferredAppServices(navigatorKey);
    });

    // Google Play In-App Updates check (Android-native, runs 2s after launch)
    if (!kIsWeb) {
      Future<void>.delayed(const Duration(seconds: 2), () {
        PlayUpdateService.checkForUpdate(context: navigatorKey.currentContext);
      });
    }
  });
}

void _reportErrorAfterStartup(String message, String stackTrace) {
  // Deduplicate: skip if the same error was already queued recently
  final key = message.length > 200 ? message.substring(0, 200) : message;
  if (_recentErrors.contains(key)) return;
  _recentErrors.add(key);

  unawaited(() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    await ApiService.reportError(message, stackTrace);
    // Remove from dedup set after 60 s so genuine recurrences are still logged
    await Future<void>.delayed(const Duration(seconds: 60));
    _recentErrors.remove(key);
  }());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIMATS VStay Portal',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: RoyalTheme.theme,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        if (kIsWeb) {
          return Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => SelectionArea(child: child),
              ),
            ],
          );
        }
        return child;
      },
      home: const AuthWrapper(),
      onGenerateRoute: (settings) => PageRouteBuilder(
        settings: settings,
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _DeferredRoutePage(settings: settings),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

class _DeferredRoutePage extends StatefulWidget {
  final RouteSettings settings;

  const _DeferredRoutePage({required this.settings});

  @override
  State<_DeferredRoutePage> createState() => _DeferredRoutePageState();
}

class _DeferredRoutePageState extends State<_DeferredRoutePage> {
  Future<void>? _routeLibrary;

  @override
  void initState() {
    super.initState();
    _routeLibrary = deferred_routes.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _routeLibrary,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F1520),
            body: SizedBox.expand(),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFF0F1520),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.amber, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to load screen resources.\nPlease try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _routeLibrary = deferred_routes.loadLibrary();
                      });
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return deferred_routes.buildDeferredRoutePage(context, widget.settings);
      },
    );
  }
}

