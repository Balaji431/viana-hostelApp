import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';
import 'app_logger.dart';
import 'notification_service.dart';

/// Singleton WebSocket service managing real-time chat connection lifecycle.
///
/// Features:
/// - Auto-connect on login with user identity.
/// - Dynamic WebSocket URL resolution (production wss://, local ws://).
/// - Exponential backoff auto-reconnect (1s, 2s, 4s, up to 10s).
/// - 25s ping/pong heartbeat to detect dead TCP connections.
/// - In-memory active room tracker with automatic re-subscription upon reconnection.
/// - Reactive stream dispatcher for instant UI message ingestion.
/// - Thread-safe and resilient against network fluctuations.
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  static WebSocketService get instance => _instance;
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  /// Master feature flag for WebSockets
  static const bool enableWebSockets = true;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSubscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  String? _username;
  String? _token;

  final Set<String> _activeRooms = <String>{};

  int _reconnectAttempts = 0;
  bool _isConnecting = false;
  bool _isExplicitlyDisconnected = false;

  /// Connection state notifier for reactive UI binding
  final ValueNotifier<bool> isConnectedNotifier = ValueNotifier<bool>(false);
  bool get isConnected => isConnectedNotifier.value;

  /// Broadcast stream controller for all incoming WebSocket events
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of all incoming WebSocket events
  Stream<Map<String, dynamic>> get onEvent => _eventController.stream;

  /// Stream filtered for 'new_message' chat events
  Stream<Map<String, dynamic>> get onNewMessage =>
      _eventController.stream.where((event) => event['event'] == 'new_message');

  /// Stream for messages in a specific request/room
  Stream<Map<String, dynamic>> onRoomMessage(String requestId) {
    final cleanId = requestId.trim();
    return onNewMessage.where((event) {
      final reqId = (event['request_id'] ?? event['data']?['request_id'])?.toString();
      return reqId == cleanId;
    });
  }

  /// Resolve WebSocket URL based on current environment and ApiService.baseUrl
  String resolveWebSocketUrl() {
    // 1. Production domain check (production host Nginx reverse proxies /ws/ to internal 3001)
    final isProductionHost = (kIsWeb && Uri.base.host.toLowerCase() == 'vstay.saveetha.com') ||
        ApiService.baseUrl.toLowerCase().contains('vstay.saveetha.com');

    if (isProductionHost) {
      return 'wss://vstay.saveetha.com/ws/';
    }

    // 2. Web browser in local development or staging
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
      return 'ws://$host:3001';
    }

    // 3. Mobile / Desktop platforms (Android, iOS, Windows, macOS, Linux)
    final apiUri = Uri.tryParse(ApiService.baseUrl);
    final host = apiUri?.host ?? 'localhost';

    if (defaultTargetPlatform == TargetPlatform.android && (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2')) {
      // Android emulator needs 10.0.2.2 to reach host machine port 3001
      return 'ws://10.0.2.2:3001';
    }

    if (host == 'localhost' || host == '127.0.0.1') {
      return 'ws://localhost:3001';
    }

    return 'ws://$host:3001';
  }

  /// Connect to the WebSocket server using the provided username and optional token
  Future<void> connect({String? username, String? token}) async {
    if (!enableWebSockets) return;

    if (username != null && username.isNotEmpty) {
      _username = username;
    }
    if (token != null && token.isNotEmpty) {
      _token = token;
    }

    _isExplicitlyDisconnected = false;

    if (_isConnecting || (isConnected && _channel != null)) {
      return;
    }

    _isConnecting = true;
    final wsUrl = resolveWebSocketUrl();
    AppLogger.info("[WebSocket] Connecting to $wsUrl for user: $_username");

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection to be ready / listen
      await _channel?.ready;

      _channelSubscription = _channel?.stream.listen(
        _onMessageReceived,
        onDone: _onConnectionClosed,
        onError: _onConnectionError,
        cancelOnError: true,
      );

      _isConnecting = false;
      isConnectedNotifier.value = true;
      _reconnectAttempts = 0;
      AppLogger.info("[WebSocket] Connected successfully to $wsUrl");

      // Send authentication handshake
      if (_username != null && _username!.isNotEmpty) {
        send({
          'action': 'auth',
          'username': _username,
          'token': _token ?? '',
        });
      }

      // Re-join any previously active rooms
      for (final room in _activeRooms) {
        send({
          'action': 'join_room',
          'room': room,
        });
      }

      // Start ping/pong heartbeat
      _startHeartbeat();
    } catch (e) {
      _isConnecting = false;
      isConnectedNotifier.value = false;
      AppLogger.warning("[WebSocket] Connection failed: $e");
      _scheduleReconnect();
    }
  }

  /// Disconnect explicitly (e.g. on logout)
  void disconnect() {
    _isExplicitlyDisconnected = true;
    _stopHeartbeat();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;

    _channelSubscription?.cancel();
    _channelSubscription = null;

    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _activeRooms.clear();
    isConnectedNotifier.value = false;
    _isConnecting = false;
    AppLogger.info("[WebSocket] Disconnected explicitly.");
  }

  /// Join a chat room by request ID (e.g. 'chat_WRD-1234').
  /// Idempotent — if the client is already subscribed to this room, the
  /// join_room action is silently skipped to prevent duplicate delivery.
  void joinRoom(String requestId) {
    if (requestId.isEmpty) return;
    final roomName = requestId.startsWith('chat_') ? requestId : 'chat_$requestId';

    // De-duplication: only send join_room to the server on first subscribe.
    final alreadyJoined = _activeRooms.contains(roomName);
    _activeRooms.add(roomName);

    if (alreadyJoined) {
      AppLogger.info("[WebSocket] Already in room $roomName — skipping duplicate join.");
      return;
    }

    if (isConnected) {
      send({
        'action': 'join_room',
        'room': roomName,
      });
      AppLogger.info("[WebSocket] Joined room: $roomName");
    }
  }

  /// Leave a chat room by request ID
  void leaveRoom(String requestId) {
    if (requestId.isEmpty) return;
    final roomName = requestId.startsWith('chat_') ? requestId : 'chat_$requestId';
    _activeRooms.remove(roomName);

    if (isConnected) {
      send({
        'action': 'leave_room',
        'room': roomName,
      });
      AppLogger.info("[WebSocket] Left room: $roomName");
    }
  }

  /// Send a JSON map over the WebSocket connection
  bool send(Map<String, dynamic> data) {
    if (_channel == null || !isConnected) {
      return false;
    }
    try {
      _channel!.sink.add(jsonEncode(data));
      return true;
    } catch (e) {
      AppLogger.warning("[WebSocket] Failed to send payload: $e");
      return false;
    }
  }

  void _onMessageReceived(dynamic rawData) {
    try {
      final String text = rawData is String ? rawData : utf8.decode(rawData as List<int>);
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        _eventController.add(decoded);

        final event = decoded['event'];
        if (event == 'pong') {
          // Heartbeat acknowledged
          return;
        }

        if (event == 'new_message') {
          final int t5ClientReceived = DateTime.now().millisecondsSinceEpoch;
          final dynamic rawTimings = decoded['timings'];
          final Map<String, dynamic> timings =
              rawTimings is Map ? Map<String, dynamic>.from(rawTimings) : {};

          final int? t0 = timings['t0_http_received_ms'] is num
              ? (timings['t0_http_received_ms'] as num).toInt()
              : null;
          final int? t1 = timings['t1_db_inserted_ms'] is num
              ? (timings['t1_db_inserted_ms'] as num).toInt()
              : null;
          final int? t2 = timings['t2_redis_published_ms'] is num
              ? (timings['t2_redis_published_ms'] as num).toInt()
              : null;
          final int? t3 = timings['t3_ws_redis_received_ms'] is num
              ? (timings['t3_ws_redis_received_ms'] as num).toInt()
              : null;
          final int? t4 = timings['t4_ws_socket_dispatched_ms'] is num
              ? (timings['t4_ws_socket_dispatched_ms'] as num).toInt()
              : null;

          final msgId = decoded['message_id'] ?? decoded['id'] ?? 'unknown';
          final reqId = decoded['request_id'] ?? 'unknown';

          if (t0 != null && t1 != null && t2 != null && t3 != null && t4 != null) {
            final dbMs = t1 - t0;
            final redisPubMs = t2 - t1;
            final redisTransitMs = t3 - t2;
            final wsDispatchMs = t4 - t3;
            final networkTransitMs = t5ClientReceived - t4;
            final totalE2eMs = t5ClientReceived - t0;

            AppLogger.info('''
================================================================================
⚡ [LATENCY BREAKDOWN] Message E2E Delivery Profiler (Req: $reqId, Msg: $msgId)
--------------------------------------------------------------------------------
1. HTTP Request Received (send_message.php) : $t0 ms
2. MySQL Insert Finished                    : $t1 ms  (+${dbMs}ms)
3. Redis Published (send_message.php)       : $t2 ms  (+${redisPubMs}ms)
4. Redis Event Received (daemon)           : $t3 ms  (+${redisTransitMs}ms)
5. WebSocket Frame Dispatched (daemon)     : $t4 ms  (+${wsDispatchMs}ms)
6. Flutter Client Frame Ingestion          : $t5ClientReceived ms  (+${networkTransitMs}ms)
--------------------------------------------------------------------------------
🔥 TOTAL END-TO-END LATENCY: ${totalE2eMs}ms
================================================================================''');
          } else {
            AppLogger.info("[WebSocket] New message received: req=$reqId msg=$msgId at $t5ClientReceived ms");
          }

          // Trigger global notifier so all open chat screens and badges instantly refresh
          NotificationService.fcmRefreshNotifier.value++;
        }

        AppLogger.info("[WebSocket] Received event: $event");
      }
    } catch (e) {
      AppLogger.warning("[WebSocket] Error parsing incoming message: $e");
    }
  }

  void _onConnectionClosed() {
    AppLogger.warning("[WebSocket] Connection closed.");
    _handleDisconnection();
  }

  void _onConnectionError(dynamic error) {
    AppLogger.warning("[WebSocket] Socket error: $error");
    _handleDisconnection();
  }

  void _handleDisconnection() {
    _stopHeartbeat();
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel = null;
    isConnectedNotifier.value = false;
    _isConnecting = false;

    if (!_isExplicitlyDisconnected) {
      _scheduleReconnect();
    }
  }

  /// Schedule reconnection with exponential backoff: 1s, 2s, 4s, up to 10s
  void _scheduleReconnect() {
    if (_isExplicitlyDisconnected || _isConnecting) return;

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    final backoffSeconds = (_reconnectAttempts <= 1)
        ? 1
        : (_reconnectAttempts == 2)
            ? 2
            : (_reconnectAttempts == 3)
                ? 4
                : 10;

    AppLogger.info("[WebSocket] Scheduling reconnect in ${backoffSeconds}s (attempt #$_reconnectAttempts)...");
    _reconnectTimer = Timer(Duration(seconds: backoffSeconds), () {
      if (!_isExplicitlyDisconnected && !isConnected) {
        connect(username: _username, token: _token);
      }
    });
  }

  /// Start 25s ping/pong heartbeat
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (isConnected) {
        final sent = send({
          'action': 'ping',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        if (!sent) {
          _handleDisconnection();
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}
