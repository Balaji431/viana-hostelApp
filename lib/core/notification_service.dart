import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../shared/user_provider.dart';
import '../shared/category_provider.dart';
import 'api_service.dart';
import 'app_logger.dart';

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Initialize local notifications in background isolate so we can show
  // notifications with action buttons (Reply / Mark as Read / Mute).
  // This is required because background isolates don't share state with the main isolate.
  final FlutterLocalNotificationsPlugin localPlugin = FlutterLocalNotificationsPlugin();

  const androidChannel = AndroidNotificationChannel(
    'chat_channel',
    'Chat Notifications',
    description: 'Notifications for new chat messages',
    importance: Importance.max,
    playSound: true,
  );
  const mutedChannel = AndroidNotificationChannel(
    'muted_chat_channel',
    'Muted Chat Notifications',
    description: 'Silent notifications for muted chats',
    importance: Importance.low,
    playSound: false,
  );

  await localPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);
  await localPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(mutedChannel);

  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: android);
  await localPlugin.initialize(
    initSettings,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );

  // Show local notification with action buttons (works for both
  // data-only messages and messages with notification payload)
  await NotificationService._showNotificationWithPlugin(localPlugin, message);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  NotificationService.handleNotificationAction(notificationResponse);
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  static final ValueNotifier<int> fcmRefreshNotifier = ValueNotifier<int>(0);

  // Notification IDs by requestId hash for targeted cancellation
  static int _notifIdForRequest(String requestId) {
    return requestId.hashCode.abs() % 100000;
  }

  static Future<void> init() async {
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true, provisional: false,
    );

    AppLogger.info("Notification Permission: ${settings.authorizationStatus}");

    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    const androidChannel = AndroidNotificationChannel(
      'chat_channel',
      'Chat Notifications',
      description: 'Notifications for new messages',
      importance: Importance.max,
      playSound: true,
    );

    const mutedChannel = AndroidNotificationChannel(
      'muted_chat_channel',
      'Muted Chat Notifications',
      description: 'Silent notifications for muted chats',
      importance: Importance.low,
      playSound: false,
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
    await androidPlugin?.createNotificationChannel(mutedChannel);

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS: Non-const construction is required for DarwinNotificationAction.text
    final chatCategory = DarwinNotificationCategory(
      'chat_category',
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.text(
          'reply_action',
          'Reply',
          buttonTitle: 'Send',
          placeholder: 'Type your message...',
        ),
        DarwinNotificationAction.plain(
          'mark_read_action',
          'Mark as Read',
        ),
        DarwinNotificationAction.plain(
          'mute_action',
          'Mute',
          options: <DarwinNotificationActionOption>{
            DarwinNotificationActionOption.destructive,
          },
        ),
      ],
    );

    final initializationSettingsDarwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [chatCategory],
    );

    final initSettings = InitializationSettings(
      android: android,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.actionId != null && response.actionId != 'dismiss_action') {
          NotificationService.handleNotificationAction(response);
        } else if (response.payload != null) {
          _handlePayload(response.payload!);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNavigation);
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    // Handle notification tap when app was terminated
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        AppLogger.info("App opened from terminated state via push notification: ${message.data}");
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNavigation(message);
        });
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      AppLogger.info("Foreground message received: ${message.data}");
      
      fcmRefreshNotifier.value++;
      
      final context = navigatorKey.currentContext;
      if (context != null) {
        try {
          final user = Provider.of<UserProvider>(context, listen: false);
          if (user.role == UserRole.student) {
            Provider.of<CategoryProvider>(context, listen: false).fetchCounts(studentUsername: user.username);
          } else if (user.isParent) {
            Provider.of<CategoryProvider>(context, listen: false).fetchCounts(studentUsername: user.username);
          } else if (user.role == UserRole.warden || user.role == UserRole.security || user.role == UserRole.maintenance || user.role == UserRole.staff) {
            Provider.of<CategoryProvider>(context, listen: false).fetchCounts(wardenUsername: user.username);
          }
        } catch (e) {
          AppLogger.error("Error refreshing counts in foreground push: $e");
        }
      }
      
      // Show local notification (works for both data-only and notification-block FCM)
      _showNotification(message);

    });

    String? token = await getToken();
    if (token != null) {
      final context = navigatorKey.currentContext; 
      if (context != null) {
        final user = Provider.of<UserProvider>(context, listen: false);
        if (user.isLoggedIn) {
          saveTokenToBackend(user.username, token);
        }
      }
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
       final context = navigatorKey.currentContext;
       if (context != null) {
         final user = Provider.of<UserProvider>(context, listen: false);
         if (user.isLoggedIn) saveTokenToBackend(user.username, newToken);
       }
    });
  }

  static Future<String?> getToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        int attempts = 0;
        while (apnsToken == null && attempts < 6) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          attempts++;
        }
        AppLogger.info("APNs Token: $apnsToken");
      }
      String? token = await FirebaseMessaging.instance.getToken();
      AppLogger.info("FCM Token: $token");
      return token;
    } catch (e) {
      AppLogger.error("FCM Token Error: $e");
      return null;
    }
  }

  static Future<void> saveTokenToBackend(String username, String token) async {
    try {
      if (username.isEmpty || username == 'null') return;
      // Use ApiService.buildUri so the correct URL is used in both local & production
      final url = ApiService.buildUri('auth/save_token.php');
      
      AppLogger.info("Saving token for $username to $url");
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'fcm_token': token}),
      ).timeout(const Duration(seconds: 2)); // 2 s max — prevents blocking logout/startup
      
      AppLogger.info("Token Save Response: ${response.statusCode} - ${response.body}");
    } catch (e) {
      AppLogger.error("Token Save Failed: $e");
    }
  }

  /// Show a notification with the 3 WhatsApp-style action buttons.
  /// [requestId] is required for action buttons to work (stored as payload).
  /// [notifId] controls which slot to use — deterministic per requestId keeps cancel working.
  static Future<void> showChatNotification(
    String title,
    String body, {
    required String requestId,
    bool isMuted = false,
  }) async {
    final int notifId = _notifIdForRequest(requestId);
    final bool currentlyMuted = isMuted;
    final String muteLabel = currentlyMuted ? 'Unmute 🔔' : 'Mute 🔕';

    final androidDetails = AndroidNotificationDetails(
      currentlyMuted ? 'muted_chat_channel' : 'chat_channel',
      currentlyMuted ? 'Muted Chat Notifications' : 'Chat Notifications',
      channelDescription: currentlyMuted
          ? 'Silent notifications for muted chats'
          : 'Notifications for new chat messages',
      importance: currentlyMuted ? Importance.low : Importance.max,
      priority: currentlyMuted ? Priority.low : Priority.high,
      playSound: !currentlyMuted,
      enableVibration: !currentlyMuted,
      icon: '@mipmap/ic_launcher',
      // ──────────────────────────────────────────────────────
      // All 3 buttons always present so they remain actionable
      // ──────────────────────────────────────────────────────
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'reply_action',
          'Reply',
          allowGeneratedReplies: true,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(
              label: 'Type your message...',
            ),
          ],
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          'mark_read_action',
          'Mark as Read',
          showsUserInterface: false,
        ),
        AndroidNotificationAction(
          'mute_action',
          muteLabel,
          showsUserInterface: false,
        ),
      ],
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: !currentlyMuted,
      categoryIdentifier: 'chat_category',
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _local.show(
      notifId,
      title,
      body,
      details,
      payload: requestId,
    );
  }

  /// Cancel (dismiss) the notification for a specific request.
  static Future<void> cancelNotificationForRequest(String requestId) async {
    if (requestId.isEmpty) return;
    final int notifId = _notifIdForRequest(requestId);
    await _local.cancel(notifId);
    AppLogger.info("Cancelled notification for request: $requestId (id=$notifId)");
  }

  /// Show a simple system notification (no action buttons).
  static Future<void> showNotificationSimple(
    String title,
    String body, {
    String? payload,
    bool showActions = false,
    bool isMuted = false,
  }) async {
    if (showActions && payload != null && payload.isNotEmpty) {
      // Delegate to the full chat notification
      await showChatNotification(title, body, requestId: payload, isMuted: isMuted);
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'chat_channel',
      'Chat Notifications',
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      icon: '@mipmap/ic_launcher',
    );

    final iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _local.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }


  /// Called from foreground FCM listener (app is open)
  static Future<void> _showNotification(RemoteMessage message) async {
    await _showNotificationWithPlugin(_local, message);
  }

  /// Core notification display — accepts any plugin instance so it works
  /// in both the main isolate and the background isolate.
  static Future<void> _showNotificationWithPlugin(
    FlutterLocalNotificationsPlugin plugin,
    RemoteMessage message,
  ) async {
    final String? requestId = message.data['request_id']?.toString();
    final prefs = await SharedPreferences.getInstance();
    final List<String> mutedList = prefs.getStringList('muted_requests') ?? [];
    final bool isMuted = requestId != null && mutedList.contains(requestId);

    // Title/body come from data payload (data-only FCM) OR notification block
    final String title = (message.data['title']?.toString().isNotEmpty == true)
        ? message.data['title']!
        : (message.notification?.title ?? message.data['sender_name'] ?? 'New Message');

    final String body = (message.data['body']?.toString().isNotEmpty == true)
        ? message.data['body']!
        : (message.notification?.body ?? message.data['message'] ?? 'You have a new message');

    final String payloadJson = jsonEncode({
      'request_id': requestId ?? message.data['request_id'] ?? '',
      'type': message.data['type'] ?? '',
      'department': message.data['department'] ?? '',
    });

    if (requestId != null && requestId.isNotEmpty) {
      // Show with 3 action buttons using deterministic notification ID
      final int notifId = requestId.hashCode.abs() % 100000;
      final String muteLabel = isMuted ? 'Unmute 🔔' : 'Mute 🔕';

      final androidDetails = AndroidNotificationDetails(
        isMuted ? 'muted_chat_channel' : 'chat_channel',
        isMuted ? 'Muted Chat Notifications' : 'Chat Notifications',
        channelDescription: isMuted
            ? 'Silent notifications for muted chats'
            : 'Notifications for new chat messages',
        importance: isMuted ? Importance.low : Importance.max,
        priority: isMuted ? Priority.low : Priority.high,
        playSound: !isMuted,
        enableVibration: !isMuted,
        icon: '@mipmap/ic_launcher',
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'reply_action',
            'Reply',
            allowGeneratedReplies: true,
            inputs: <AndroidNotificationActionInput>[
              AndroidNotificationActionInput(label: 'Type your message...'),
            ],
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'mark_read_action',
            'Mark as Read',
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'mute_action',
            muteLabel,
            showsUserInterface: false,
          ),
        ],
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: !isMuted,
        categoryIdentifier: 'chat_category',
      );

      final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      await plugin.show(notifId, title, body, details, payload: payloadJson);
    } else {
      // No requestId — show simple notification without action buttons
      const androidDetails = AndroidNotificationDetails(
        'chat_channel',
        'Chat Notifications',
        channelDescription: 'Notifications for new chat messages',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
      await plugin.show(message.hashCode.abs() % 100000, title, body, details, payload: payloadJson);
    }
  }



  static Future<void> handleNotificationAction(NotificationResponse response) async {
    String? requestId = response.payload;
    if (requestId != null && requestId.startsWith('{')) {
      try {
        final data = jsonDecode(requestId);
        requestId = data['request_id']?.toString();
      } catch (_) {}
    }
    final String? actionId = response.actionId;
    
    AppLogger.info("Notification action clicked: $actionId, payload: $requestId");
    
    if (actionId == null || requestId == null || requestId.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    final String? userDataStr = prefs.getString('user_data');
    if (userDataStr == null) {
      AppLogger.warning("No user session found for notification action");
      return;
    }
    
    final Map<String, dynamic> userData = jsonDecode(userDataStr);
    
    // ─────────────────────────────────────────────────────────────────────
    // Resolve sender ID: prefer 'username' (works for both students/staff)
    // Students:  register_no == username (e.g. "192524101")
    // Staff:     username == "warden1", register_no == ""
    // ─────────────────────────────────────────────────────────────────────
    String senderId = '';
    if (userData['username'] != null && userData['username'].toString().isNotEmpty) {
      senderId = userData['username'].toString();
    } else if (userData['register_no'] != null && userData['register_no'].toString().isNotEmpty) {
      senderId = userData['register_no'].toString();
    } else if (userData['parent_id'] != null && userData['parent_id'].toString().isNotEmpty) {
      senderId = userData['parent_id'].toString();
    } else if (userData['email'] != null && userData['email'].toString().isNotEmpty) {
      senderId = userData['email'].toString();
    }
    
    if (senderId.isEmpty) {
      AppLogger.warning("Could not resolve sender ID for notification action");
      return;
    }
    
    await ApiService.init();
    
    // Check current mute status
    final List<String> mutedList = prefs.getStringList('muted_requests') ?? [];
    final bool isCurrentlyMuted = mutedList.contains(requestId);
    
    if (actionId == 'reply_action') {
      final String? replyText = response.input;
      if (replyText != null && replyText.trim().isNotEmpty) {
        AppLogger.info("Sending inline reply: '${replyText.trim()}' for request: $requestId from sender: $senderId");
        
        try {
          final result = await ApiService.sendChatMessage(
            requestId,
            senderId,
            replyText.trim(),
          );
          AppLogger.info("Inline reply response: $result");
          
          if (result['success'] == true) {
            // 1. Dismiss the original notification
            await cancelNotificationForRequest(requestId);
            
            // 2. Show updated notification with "Reply sent" body and all 3 buttons still active
            await showChatNotification(
              'Reply Sent ✓',
              replyText.trim(),
              requestId: requestId,
              isMuted: isCurrentlyMuted,
            );
            
            // 3. Signal the app to refresh if it's in foreground
            try { fcmRefreshNotifier.value++; } catch (_) {}
          } else {
            AppLogger.error("Reply failed: ${result['message']}");
            // Show error notification
            await showNotificationSimple(
              'Reply Failed',
              'Could not send reply. Please open the app to try again.',
            );
          }
        } catch (e) {
          AppLogger.error("Reply exception: $e");
          await showNotificationSimple(
            'Reply Failed',
            'Network error. Please open the app to try again.',
          );
        }
      }
    } else if (actionId == 'mark_read_action') {
      AppLogger.info("Marking request as read: $requestId by $senderId");
      
      try {
        final result = await ApiService.markRead(requestId, senderId);
        AppLogger.info("Mark read response: $result");
        
        // Dismiss the notification — no need for a confirmation alert
        await cancelNotificationForRequest(requestId);
        
        // Signal app refresh
        try { fcmRefreshNotifier.value++; } catch (_) {}
      } catch (e) {
        AppLogger.error("Mark read exception: $e");
      }
    } else if (actionId == 'mute_action') {
      AppLogger.info("Toggling mute for request: $requestId (currently muted: $isCurrentlyMuted)");
      
      List<String> updatedMutedList = List<String>.from(mutedList);
      
      if (isCurrentlyMuted) {
        // UNMUTE
        updatedMutedList.remove(requestId);
        await prefs.setStringList('muted_requests', updatedMutedList);
        
        // Show updated notification with sound + "Mute" button (now unmuted)
        await showChatNotification(
          'Notifications Unmuted 🔔',
          'You will now receive sound notifications for this chat.',
          requestId: requestId,
          isMuted: false,
        );
      } else {
        // MUTE
        updatedMutedList.add(requestId);
        await prefs.setStringList('muted_requests', updatedMutedList);
        
        // Show updated notification silently + "Unmute" button
        await showChatNotification(
          'Notifications Muted 🔕',
          'This chat will be delivered silently. Tap to unmute.',
          requestId: requestId,
          isMuted: true,
        );
      }
    }
  }

  static Future<void> unmuteRequest(String requestId) async {
    if (requestId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    List<String> mutedList = prefs.getStringList('muted_requests') ?? [];
    if (mutedList.contains(requestId)) {
      mutedList.remove(requestId);
      await prefs.setStringList('muted_requests', mutedList);
      AppLogger.info("Unmuted notifications for request: $requestId");
    }
  }

  static void _navigateFromData(Map<String, dynamic> data) {
    final String? requestId = data['request_id']?.toString();
    final String type = data['type']?.toString().toLowerCase() ?? '';
    final String department = data['department']?.toString().toLowerCase() ?? '';

    AppLogger.info("Navigating from notification payload: type=$type, request_id=$requestId, dept=$department");

    if (type == 'announcement' || requestId == 'announcement') {
      navigatorKey.currentState?.pushNamed('/announcements');
      return;
    }

    if (requestId != null && requestId.isNotEmpty && requestId != 'conduct_update') {
      unmuteRequest(requestId);
      navigatorKey.currentState?.pushNamed('/chat', arguments: {
        'request_id': requestId,
        'department': department,
      });
      return;
    }

    if (type.contains('chat') || type.contains('request') || type.contains('allocation')) {
      if (requestId != null && requestId.isNotEmpty) {
        navigatorKey.currentState?.pushNamed('/chat', arguments: {
          'request_id': requestId,
          'department': department,
        });
      }
    }
  }

  static void _handlePayload(String payload) {
    if (payload.isEmpty) return;
    try {
      if (payload.startsWith('{')) {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        _navigateFromData(data);
      } else {
        unmuteRequest(payload);
        navigatorKey.currentState?.pushNamed('/chat', arguments: {'request_id': payload});
      }
    } catch (_) {
      unmuteRequest(payload);
      navigatorKey.currentState?.pushNamed('/chat', arguments: {'request_id': payload});
    }
  }

  static void _handleNavigation(RemoteMessage message) {
    _navigateFromData(message.data);
  }
}
