import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../firebase_options.dart';
import 'app_logger.dart';
import 'notification_service.dart';

Future<void> initializeDeferredAppServices(
  GlobalKey<NavigatorState> navigatorKey,
) async {
  final futures = <Future<void>>[
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
  } catch (e) {
    AppLogger.error("Firebase init failed: $e");
    AppLogger.warning(
      "Firebase Messaging might not work on Web without proper configuration",
    );
  }
}