import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../firebase_options.dart';
import '../shared/ui_provider.dart';
import '../shared/user_provider.dart';
import 'app_logger.dart';
import 'notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.info("Background message: ${message.messageId}");

  final String? title = message.data['title'];
  final String? body = message.data['body'];

  if (title != null && body != null) {
    await NotificationService.init();
    NotificationService.showNotificationSimple(title, body);
  }
}

Future<void> initializeDeferredAppServices(
  GlobalKey<NavigatorState> navigatorKey,
) async {
  final futures = [
    _initializeFirebaseMessaging(navigatorKey),
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

Future<void> _initializeFirebaseMessaging(
  GlobalKey<NavigatorState> navigatorKey,
) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (!kIsWeb) {
      await NotificationService.init();
      unawaited(NotificationService.getToken().then((String? token) {
        AppLogger.info("FCM Token: $token");
      }));
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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
      if (currentContext != null && currentContext.mounted) {
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
      final String body =
          dataBody ?? message.notification?.body ?? 'New Message';

      NotificationService.showNotificationSimple(title, body);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      AppLogger.info("Notification clicked: ${message.data}");
      _handleNotificationNavigation(navigatorKey, message);
    });

    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        AppLogger.info("App launched from notification: ${message.data}");
        _handleNotificationNavigation(navigatorKey, message);
      }
    });
  } else {
    AppLogger.warning("Skipping Firebase Messaging setup");
  }
}

void _handleNotificationNavigation(
  GlobalKey<NavigatorState> navigatorKey,
  RemoteMessage message,
) {
  final type = message.data['type']?.toString();
  if ((type == 'chat' || type == 'attendance_alert') &&
      message.data['request_id'] != null) {
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
