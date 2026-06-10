import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/api_service.dart';
import 'core/app_logger.dart';
import 'core/notification_service.dart';
import 'core/providers/allocation_provider.dart';
import 'core/providers/hierarchical_hostel_provider.dart';
import 'core/providers/mapping_provider.dart';
import 'core/royal_theme.dart';
import 'firebase_options.dart';
import 'shared/auth_wrapper.dart';
import 'shared/category_provider.dart';
import 'shared/main_layout.dart';
import 'shared/request_provider.dart';
import 'shared/ui_provider.dart';
import 'shared/user_provider.dart';
import 'student/screens/warden_chat_screen.dart';
import 'student/screens/security_chat_screen.dart';
import 'student/screens/maintenance_chat_screen.dart';
import 'student/screens/parent_warden_chat_screen.dart';
import 'warden/screens/warden_chat_interface.dart';
import 'admin/screens/category_manager_screen.dart';
import 'admin/screens/admin_hostel_manager_screen.dart';
import 'admin/staff_mapping_manager_screen.dart';
import 'admin/screens/room_master_screen.dart';
import 'admin/screens/hostel_detail_screen.dart';
import 'core/models/hierarchical_hostel_model.dart';
import 'core/styles.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.info("Background message: ${message.messageId}");

  final String? title = message.data['title'];
  final String? body = message.data['body'];

  if (title != null && body != null) {
    await NotificationService.init();
    NotificationService.showNotificationSimple(title, body);
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => RequestProvider()),
        ChangeNotifierProvider(create: (_) => UIProvider()),
        ChangeNotifierProvider(create: (_) => CategoryProvider()),
        ChangeNotifierProvider(create: (_) => HierarchicalHostelProvider()),
        ChangeNotifierProvider(create: (_) => MappingProvider()),
        ChangeNotifierProvider(create: (_) => AllocationProvider()),
      ],
      child: const MyApp(),
    ),
  );

  unawaited(_initializeAppServices());
}

Future<void> _initializeAppServices() async {
  final futures = [
    ApiService.init(),
    _initializeFirebaseMessaging(),
  ];
  if (!kIsWeb) {
    futures.insert(0, _initializeHive());
  }
  await Future.wait(futures);
}

Future<void> _initializeHive() async {
  try {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox('chat_warden'),
      Hive.openBox('chat_security'),
      Hive.openBox('chat_maintenance'),
    ]);
  } catch (e) {
    AppLogger.error("Hive init failed: $e");
  }
}

Future<void> _initializeFirebaseMessaging() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.init();

    // Token generation can be slow, especially on web, so it must not block UI.
    final String? token = await NotificationService.getToken();
    AppLogger.info("FCM Token: $token");

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (e) {
    AppLogger.error("Firebase init failed: $e");
    AppLogger.warning(
      "Firebase Messaging might not work on Web without proper configuration",
    );
  }

  if (Firebase.apps.isNotEmpty) {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.info("Foreground message: ${message.data}");

      final currentContext = navigatorKey.currentContext;
      if (currentContext != null) {
        final userProvider =
            Provider.of<UserProvider>(currentContext, listen: false);
        final String? senderId = message.data['sender_id']?.toString();

        if (senderId != null &&
            (senderId == userProvider.username ||
                senderId == userProvider.dbId?.toString())) {
          AppLogger.info("Suppressing self-notification: $senderId");
          return;
        }
      }

      final String? dataTitle = message.data['title'];
      final String? dataBody = message.data['body'];
      final String title =
          dataTitle ?? message.notification?.title ?? 'Notification';
      final String body = dataBody ?? message.notification?.body ?? 'New Message';

      NotificationService.showNotificationSimple(title, body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      AppLogger.info("Notification clicked: ${message.data}");
      _handleNotificationNavigation(message);
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        AppLogger.info("App launched from notification: ${message.data}");
        _handleNotificationNavigation(message);
      }
    });
  } else {
    AppLogger.warning("Skipping Firebase Messaging setup");
  }
}

void _handleNotificationNavigation(RemoteMessage message) {
  final type = message.data['type']?.toString();
  if ((type == 'chat' || type == 'attendance_alert') && message.data['request_id'] != null) {
    final currentContext = navigatorKey.currentContext;
    if (currentContext == null) return;

    final ui = currentContext.read<UIProvider>();

    String? currentRouteName;
    navigatorKey.currentState?.popUntil((route) {
      currentRouteName = route.settings.name;
      return true;
    });

    AppLogger.info("Current route: $currentRouteName");

    final bool isAlreadyInChat =
        (currentRouteName?.toLowerCase().contains('chat') ?? false) ||
            ui.activeChatChannel != null;

    if (isAlreadyInChat) {
      AppLogger.info("Already in chat, skipping navigation");
      return;
    }

    AppLogger.info("Navigating to chat: ${message.data['request_id']}");

    navigatorKey.currentState?.pushNamed(
      '/chat',
      arguments: {
        'request_id': message.data['request_id'],
        'sender_id': message.data['sender_id'] ?? '',
        'sender_name': message.data['title'] ?? 'Chat',
        'department': message.data['department'] ?? '',
      },
    );
  }
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
      routes: {
        '/chat': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;

          Map<String, dynamic>? mapArgs;
          if (args is Map) {
            mapArgs = Map<String, dynamic>.from(args);
          }

          final requestId =
              args is String ? args : mapArgs?['request_id']?.toString();
          
          String department = mapArgs?['department']?.toString().toLowerCase() ?? '';
          
          // DEDUCE DEPARTMENT FROM REQUEST_ID PREFIX IF EMPTY
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

          // STAFF LOGINS (Warden, Security, Maintenance, Staff, Admin)
          if (user.role == UserRole.warden || 
              user.role == UserRole.security || 
              user.role == UserRole.maintenance || 
              user.role == UserRole.staff || 
              user.role == UserRole.admin) {
            
            // Resolve the department/channel name to pass
            String channel = department;
            if (channel == 'parent_warden') {
              channel = 'parent_warden';
            } else if (user.role == UserRole.security) {
              channel = 'security';
            } else if (user.role == UserRole.maintenance || user.role == UserRole.staff) {
              channel = user.roleName.isNotEmpty ? user.roleName : 'maintenance';
            } else if (user.role == UserRole.warden) {
              if (requestId != null && (requestId.toUpperCase().startsWith('PAR-') || department == 'parent_warden')) {
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

          // STUDENT & PARENT LOGINS
          Widget targetScreen;
          if (department == 'warden' || department == 'parent_warden') {
            targetScreen = user.isParent
                ? ParentWardenChatScreen(requestId: requestId, department: 'Warden')
                : WardenChatScreen(requestId: requestId, department: 'Warden');
          } else if (department == 'security') {
            targetScreen = SecurityChatScreen(requestId: requestId);
          } else {
            // Capitalize first letter of department for maintenance
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
        },
        '/security_chat': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          Map<String, dynamic>? mapArgs;
          if (args is Map) {
            mapArgs = Map<String, dynamic>.from(args);
          }
          final requestId =
              args is String ? args : mapArgs?['request_id']?.toString();
          final senderId = mapArgs?['sender_id']?.toString() ?? '';
          return MainResponsiveLayout(
            initialRequestId: requestId,
            senderId: senderId,
            isSecurity: true,
          );
        },
        '/announcements': (context) =>
            const MainResponsiveLayout(showAnnouncements: true),
        '/category_manager': (context) => const MainResponsiveLayout(initialRoute: '/category_manager'),
        '/hostel_manager': (context) => const MainResponsiveLayout(initialRoute: '/hostel_manager'),
        '/mapping_manager': (context) => const MainResponsiveLayout(initialRoute: '/mapping_manager'),
        '/room_master': (context) => const RoomMasterScreen(),
        '/hostel_detail': (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          return MainResponsiveLayout(initialRoute: '/hostel_detail', initialRouteArgs: args);
        },
      },
    );
  }
}
