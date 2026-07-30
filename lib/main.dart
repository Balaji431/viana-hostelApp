import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_service.dart';
import 'core/deferred_app_services.dart' deferred as app_services;
import 'core/providers/allocation_provider.dart';
import 'core/providers/hierarchical_hostel_provider.dart';
import 'core/providers/mapping_provider.dart';
import 'core/royal_theme.dart';
import 'shared/auth_wrapper.dart';
import 'shared/category_provider.dart';
import 'shared/deferred_routes.dart' deferred as deferred_routes;
import 'shared/request_provider.dart';
import 'shared/ui_provider.dart';
import 'shared/user_provider.dart';
import 'shared/wallpaper_provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _reportErrorAfterStartup(
      details.exceptionAsString(),
      details.stack?.toString() ?? '',
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _reportErrorAfterStartup(error.toString(), stack.toString());
    return true;
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider(prefs: prefs)),
        ChangeNotifierProvider(create: (_) => RequestProvider()),
        ChangeNotifierProvider(create: (_) => UIProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => HierarchicalHostelProvider()),
        ChangeNotifierProvider(create: (_) => MappingProvider()),
        ChangeNotifierProvider(create: (_) => AllocationProvider()),
        ChangeNotifierProvider(create: (_) => WallpaperProvider()),
      ],
      child: const MyApp(),
    ),
  );

  _scheduleAppServicesInitialization();
}

void _scheduleAppServicesInitialization() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      // Web loads faster; mobile needs slightly more time for the framework to settle
      await Future<void>.delayed(kIsWeb
          ? const Duration(milliseconds: 500)
          : const Duration(milliseconds: 800));
      await ApiService.init();
      await app_services.loadLibrary();
      await app_services.initializeDeferredAppServices(navigatorKey);
    }());
  });
}

void _reportErrorAfterStartup(String message, String stackTrace) {
  unawaited(() async {
    await Future<void>.delayed(const Duration(seconds: 5));
    await ApiService.reportError(message, stackTrace);
  }());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Saveetha Hostels',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: RoyalTheme.theme,
      home: const AuthWrapper(),
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: settings,
        builder: (_) => _DeferredRoutePage(settings: settings),
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
            backgroundColor: Color(0xFFF5F0E8),
            body: SizedBox.expand(),
          );
        }
        return deferred_routes.buildDeferredRoutePage(context, widget.settings);
      },
    );
  }
}
