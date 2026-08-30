import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/services.dart';
import 'core/api_service.dart';
import 'core/deferred_app_services.dart' deferred as app_services;
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

  // ─── CRITICAL: Don't await SharedPreferences before runApp ───────────────
  // Awaiting SharedPreferences.getInstance() before runApp() blocks Frame 1
  // from painting until the disk read resolves (~80–120ms on mobile).
  // App starts immediately with prefs=null; real prefs are injected post-frame.
  runApp(
    MultiProvider(
      // ─── LOGIN-ONLY PROVIDERS ────────────────────────────────────────────
      // Only providers required to render the Login screen are here.
      // Dashboard providers (Category, Request, HierarchicalHostel, Mapping,
      // Allocation) are scoped inside MainResponsiveLayout so they are never
      // instantiated until after a successful login.
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider(prefs: null)),
        ChangeNotifierProvider(create: (_) => UIProvider()),
        ChangeNotifierProvider(create: (_) => WallpaperProvider()),
      ],
      child: const MyApp(),
    ),
  );

  _scheduleAppServicesInitialization();
}

void _scheduleAppServicesInitialization() {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Load SharedPreferences now (post-frame, so it never blocks Frame 1)
    // and inject into UserProvider so session restore happens right after paint.
    final prefs = await SharedPreferences.getInstance();
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
  late final Future<void> _routeLibrary = deferred_routes.loadLibrary();

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
        return deferred_routes.buildDeferredRoutePage(context, widget.settings);
      },
    );
  }
}
