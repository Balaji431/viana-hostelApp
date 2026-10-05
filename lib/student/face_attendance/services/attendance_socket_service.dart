import 'dart:async';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../core/api_service.dart';

class LivenessChallengeData {
  final String challengeId;
  final String nonce;
  final List<String> steps;
  final List<List<int>> flashColors;
  final int expiresIn;

  const LivenessChallengeData({
    required this.challengeId,
    required this.nonce,
    required this.steps,
    required this.flashColors,
    required this.expiresIn,
  });

  factory LivenessChallengeData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final rawSteps = data['steps'] as List? ?? ['look_straight', 'blink', 'color_flash'];
    final rawColors = data['flash_colors'] as List? ?? [[10, 220, 255], [255, 10, 10]];

    return LivenessChallengeData(
      challengeId: data['challenge_id'] ?? '',
      nonce: data['nonce'] ?? '',
      steps: rawSteps.map((e) => e.toString()).toList(),
      flashColors: rawColors.map((c) => (c as List).map((v) => (v as num).toInt()).toList()).toList(),
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 120,
    );
  }
}

class OperationResultEvent {
  final bool isSuccess;
  final String? requestId;
  final String? message;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? data;

  const OperationResultEvent({
    required this.isSuccess,
    this.requestId,
    this.message,
    this.errorCode,
    this.errorMessage,
    this.data,
  });

  factory OperationResultEvent.fromJson(Map<String, dynamic> json) {
    final isOk = json['status'] == 'ok' || json['success'] == true;
    final err = json['error'] as Map<String, dynamic>?;

    return OperationResultEvent(
      isSuccess: isOk,
      requestId: json['request_id'],
      message: json['message'],
      errorCode: err?['code'] ?? json['code'],
      errorMessage: err?['message'] ?? json['message'] ?? (isOk ? null : 'Operation failed'),
      data: json['data'] as Map<String, dynamic>?,
    );
  }
}

class AttendanceSocketService {
  final String socketUrl;
  IO.Socket? _socket;

  final _challengeController = StreamController<LivenessChallengeData>.broadcast();
  final _operationResultController = StreamController<OperationResultEvent>.broadcast();
  final _punchBroadcastController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<LivenessChallengeData> get onChallenge => _challengeController.stream;
  Stream<OperationResultEvent> get onOperationResult => _operationResultController.stream;
  Stream<Map<String, dynamic>> get onAttendancePunch => _punchBroadcastController.stream;

  bool get isConnected => _socket?.connected ?? false;

  AttendanceSocketService({String? socketUrl})
      : socketUrl = (socketUrl ?? ApiService.attendanceServerUrl).replaceAll(RegExp(r'/api/?$'), '');

  Future<void> connect({required String accessToken}) async {
    disconnect();

    final completer = Completer<void>();

    _socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .setAuth({'token': accessToken})
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .build(),
    );

    _socket!.onConnect((_) {
      if (!completer.isCompleted) completer.complete();
    });

    _socket!.onConnectError((err) {
      if (!completer.isCompleted) completer.completeError(Exception('Socket connect error: $err'));
    });

    _socket!.on('connected', (data) {});

    _socket!.on('liveness_challenge', (data) {
      if (data is Map<String, dynamic>) {
        _challengeController.add(LivenessChallengeData.fromJson(data));
      }
    });

    _socket!.on('operation_result', (data) {
      if (data is Map<String, dynamic>) {
        _operationResultController.add(OperationResultEvent.fromJson(data));
      }
    });

    _socket!.on('attendance_punch', (data) {
      if (data is Map<String, dynamic>) {
        _punchBroadcastController.add(data);
      }
    });

    _socket!.connect();

    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
      if (!completer.isCompleted) completer.complete();
    });
  }

  void startLivenessSession({
    required String requestId,
    required String purpose, // 'punch' or 'enroll'
    String? wifiSsid,
    String? wifiBssid,
  }) {
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('start_liveness_session', {
      'request_id': requestId,
      'purpose': purpose,
      'wifi_ssid': wifiSsid ?? 'SIMATS',
      'wifi_bssid': wifiBssid ?? '00:11:22:33:44:55',
    });
  }

  Future<bool> sendLivenessFrame({
    required String requestId,
    required String challengeId,
    required String nonce,
    required String step,
    required String imageDataUrl,
  }) async {
    if (_socket == null || !_socket!.connected) return false;

    final completer = Completer<bool>();

    // Listen for one-time frame ack
    void onAck(dynamic data) {
      _socket!.off('liveness_frame_ack');
      if (!completer.isCompleted) completer.complete(true);
    }

    _socket!.once('liveness_frame_ack', onAck);

    _socket!.emit('liveness_frame', {
      'request_id': requestId,
      'challenge_id': challengeId,
      'nonce': nonce,
      'step': step,
      'image_data_url': imageDataUrl,
    });

    return completer.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _socket?.off('liveness_frame_ack');
      return true; // proceed if network delay
    });
  }

  void verifyFastPunch(Map<String, dynamic> punchPayload) {
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('verify_fast_punch', punchPayload);
  }

  void completeEnrollment(Map<String, dynamic> enrollPayload) {
    if (_socket == null || !_socket!.connected) return;
    _socket!.emit('complete_enrollment', enrollPayload);
  }

  void disconnect() {
    try {
      _socket?.disconnect();
      _socket?.dispose();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    disconnect();
    _challengeController.close();
    _operationResultController.close();
    _punchBroadcastController.close();
  }
}
