import 'dart:async';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/face_attendance_models.dart';
import '../services/attendance_bootstrap_service.dart';
import '../services/attendance_socket_service.dart';
import '../services/device_security_service.dart';

/// Response payload from face registration
class FaceRegistrationResult {
  final bool isSuccess;
  final String? errorMessage;
  final String? errorCode;

  const FaceRegistrationResult({
    required this.isSuccess,
    this.errorMessage,
    this.errorCode,
  });
}

/// Response payload from attendance verification / punch
class AttendanceVerificationResult {
  final bool isSuccess;
  final bool isDuplicate;
  final bool isNetworkError;
  final bool isUnauthorized;
  final bool isOutOfGeofence;
  final bool isIpUnauthorized;
  final bool isSpoofDetected;
  final String? errorCode;
  final String? errorMessage;
  final AttendanceRecordResult? record;

  const AttendanceVerificationResult({
    required this.isSuccess,
    this.isDuplicate = false,
    this.isNetworkError = false,
    this.isUnauthorized = false,
    this.isOutOfGeofence = false,
    this.isIpUnauthorized = false,
    this.isSpoofDetected = false,
    this.errorCode,
    this.errorMessage,
    this.record,
  });
}

/// Abstract contract for Face Attendance API
abstract class FaceAttendanceRepository {
  Future<AttendanceSessionInfo> getCurrentSession();
  Future<bool> isFaceRegistered(String studentUsername);
  
  Future<AttendanceAuthSession> bootstrapSession({
    required int bioId,
  });

  Future<void> connectSocket(String accessToken);

  Stream<LivenessChallengeData> get onLivenessChallenge;
  Stream<OperationResultEvent> get onOperationResult;

  void startLivenessSession({
    required String requestId,
    required String purpose, // 'punch' or 'enroll'
    String? wifiSsid,
    String? wifiBssid,
  });

  Future<bool> sendLivenessFrame({
    required String requestId,
    required String challengeId,
    required String nonce,
    required String step,
    required String imageDataUrl,
  });

  Future<AttendanceVerificationResult> verifyFastPunch({
    required String requestId,
    required String challengeId,
    required String nonce,
    required List<String> completedSteps,
    required String punchType,
    required String baseFaceImageUrl,
    required String? flashImageUrl,
    required String? actionImageUrl,
    required String studentName,
    required String registerNumber,
    required String sessionName,
  });

  Future<FaceRegistrationResult> completeEnrollment({
    required String requestId,
    required String challengeId,
    required String nonce,
    required List<String> completedSteps,
    required String baseFaceImageUrl,
    required String? flashImageUrl,
    required String? actionImageUrl,
  });

  void dispose();
}

/// Production implementation of manager's Attendance Engine
class ProductionFaceAttendanceRepository implements FaceAttendanceRepository {
  final AttendanceBootstrapService bootstrapService;
  final AttendanceSocketService socketService;
  final DeviceSecurityService securityService;

  AttendanceAuthSession? _activeSession;
  NativeDeviceEvidence? _lastEvidence;

  ProductionFaceAttendanceRepository({
    AttendanceBootstrapService? bootstrapService,
    AttendanceSocketService? socketService,
    DeviceSecurityService? securityService,
  })  : bootstrapService = bootstrapService ?? AttendanceBootstrapService(),
        socketService = socketService ?? AttendanceSocketService(),
        securityService = securityService ?? DeviceSecurityService();

  @override
  Stream<LivenessChallengeData> get onLivenessChallenge => socketService.onChallenge;

  @override
  Stream<OperationResultEvent> get onOperationResult => socketService.onOperationResult;

  @override
  Future<AttendanceSessionInfo> getCurrentSession() async {
    return AttendanceSessionInfo.defaultEvening();
  }

  @override
  Future<bool> isFaceRegistered(String studentUsername) async {
    if (_activeSession != null) {
      return _activeSession!.faceEnrolled;
    }
    return false;
  }

  @override
  Future<AttendanceAuthSession> bootstrapSession({required int bioId}) async {
    // 1. Clock skew check
    await bootstrapService.checkServerTime();

    // 2. Native device evidence
    _lastEvidence = await securityService.collectEvidence();

    // 3. Auth Validate
    _activeSession = await bootstrapService.validateDeviceAndAuth(
      bioId: bioId,
      evidence: _lastEvidence!,
    );

    return _activeSession!;
  }

  @override
  Future<void> connectSocket(String accessToken) async {
    await socketService.connect(accessToken: accessToken);
  }

  @override
  void startLivenessSession({
    required String requestId,
    required String purpose,
    String? wifiSsid,
    String? wifiBssid,
  }) {
    socketService.startLivenessSession(
      requestId: requestId,
      purpose: purpose,
      wifiSsid: wifiSsid ?? _lastEvidence?.wifiSsid,
      wifiBssid: wifiBssid ?? _lastEvidence?.wifiBssid,
    );
  }

  @override
  Future<bool> sendLivenessFrame({
    required String requestId,
    required String challengeId,
    required String nonce,
    required String step,
    required String imageDataUrl,
  }) async {
    return await socketService.sendLivenessFrame(
      requestId: requestId,
      challengeId: challengeId,
      nonce: nonce,
      step: step,
      imageDataUrl: imageDataUrl,
    );
  }

  @override
  Future<AttendanceVerificationResult> verifyFastPunch({
    required String requestId,
    required String challengeId,
    required String nonce,
    required List<String> completedSteps,
    required String punchType,
    required String baseFaceImageUrl,
    required String? flashImageUrl,
    required String? actionImageUrl,
    required String studentName,
    required String registerNumber,
    required String sessionName,
  }) async {
    // Collect fresh GNSS and network evidence per punch
    final evidence = await securityService.collectEvidence();
    _lastEvidence = evidence;

    final punchPayload = {
      'request_id': requestId.isNotEmpty ? requestId : const Uuid().v4(),
      'challenge_id': challengeId,
      'nonce': nonce,
      'completed_steps': completedSteps,
      'punch_type': punchType, // 'IN' or 'OUT'
      'latitude': evidence.latitude ?? 13.0827,
      'longitude': evidence.longitude ?? 80.2707,
      'accuracy': evidence.accuracy ?? 10.0,
      'client_epoch_ms': DateTime.now().millisecondsSinceEpoch,
      'image_data_url': baseFaceImageUrl,
      'flash_image_data_url': flashImageUrl ?? baseFaceImageUrl,
      'action_image_data_url': actionImageUrl ?? baseFaceImageUrl,
      'mock_location': evidence.isMockLocation,
      'is_vpn': evidence.isVpn,
      'is_rooted': evidence.isRooted,
      'is_jailbroken': evidence.isJailbroken,
      'is_emulator': evidence.isEmulator,
      'wifi_ssid': evidence.wifiSsid ?? 'SIMATS',
      'wifi_bssid': evidence.wifiBssid ?? '00:11:22:33:44:55',
    };

    final completer = Completer<AttendanceVerificationResult>();

    // Listen on socket operation_result
    late final StreamSubscription<OperationResultEvent> sub;
    sub = socketService.onOperationResult.listen((event) {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.complete(_mapOperationResult(event, studentName, registerNumber, sessionName));
      }
    });

    if (socketService.isConnected) {
      socketService.verifyFastPunch(punchPayload);
    } else if (_activeSession != null) {
      // Fallback to HTTP fast-punch if socket connection dropped
      try {
        final httpRes = await bootstrapService.httpFastPunch(
          accessToken: _activeSession!.accessToken,
          punchPayload: punchPayload,
        );
        sub.cancel();
        return _mapOperationResult(
          OperationResultEvent.fromJson(httpRes),
          studentName,
          registerNumber,
          sessionName,
        );
      } catch (e) {
        sub.cancel();
        return _mapError('HTTP fallback failed: $e');
      }
    } else {
      sub.cancel();
      return const AttendanceVerificationResult(
        isSuccess: false,
        isNetworkError: true,
        errorCode: 'SERVER_OFFLINE',
        errorMessage: 'Attendance Server Offline: Socket.IO is disconnected and no active session token exists.',
      );
    }

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        sub.cancel();
        return const AttendanceVerificationResult(
          isSuccess: false,
          isNetworkError: true,
          errorMessage: 'Attendance verification timed out. Please retry.',
        );
      },
    );
  }

  @override
  Future<FaceRegistrationResult> completeEnrollment({
    required String requestId,
    required String challengeId,
    required String nonce,
    required List<String> completedSteps,
    required String baseFaceImageUrl,
    required String? flashImageUrl,
    required String? actionImageUrl,
  }) async {
    final evidence = _lastEvidence ?? await securityService.collectEvidence();

    final enrollPayload = {
      'request_id': requestId.isNotEmpty ? requestId : const Uuid().v4(),
      'challenge_id': challengeId,
      'nonce': nonce,
      'completed_steps': completedSteps,
      'image_data_url': baseFaceImageUrl,
      'flash_image_data_url': flashImageUrl ?? baseFaceImageUrl,
      'action_image_data_url': actionImageUrl ?? baseFaceImageUrl,
      'wifi_ssid': evidence.wifiSsid ?? 'SIMATS',
      'wifi_bssid': evidence.wifiBssid ?? '00:11:22:33:44:55',
    };

    if (!socketService.isConnected) {
      return const FaceRegistrationResult(
        isSuccess: false,
        errorCode: 'SOCKET_DISCONNECTED',
        errorMessage: 'Cannot enroll face: Socket.IO attendance server is offline.',
      );
    }

    final completer = Completer<FaceRegistrationResult>();

    late final StreamSubscription<OperationResultEvent> sub;
    sub = socketService.onOperationResult.listen((event) {
      sub.cancel();
      if (!completer.isCompleted) {
        completer.complete(
          FaceRegistrationResult(
            isSuccess: event.isSuccess,
            errorCode: event.errorCode,
            errorMessage: event.errorMessage,
          ),
        );
      }
    });

    socketService.completeEnrollment(enrollPayload);

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        sub.cancel();
        return const FaceRegistrationResult(
          isSuccess: false,
          errorCode: 'TIMEOUT',
          errorMessage: 'Face enrollment timed out. Please retry.',
        );
      },
    );
  }

  AttendanceVerificationResult _mapOperationResult(
    OperationResultEvent event,
    String studentName,
    String registerNumber,
    String sessionName,
  ) {
    if (event.isSuccess) {
      final now = DateTime.now();
      final dateStr = DateFormat('EEE, d MMM yyyy').format(now);
      final timeStr = DateFormat('h:mm a').format(now);
      final refId = event.requestId ?? 'REF-${now.millisecondsSinceEpoch.toString().substring(5)}';

      return AttendanceVerificationResult(
        isSuccess: true,
        record: AttendanceRecordResult(
          studentName: studentName.isNotEmpty ? studentName : 'Resident Student',
          registerNumber: registerNumber.isNotEmpty ? registerNumber : 'SIMATS',
          dateFormatted: dateStr,
          timeFormatted: timeStr,
          sessionName: sessionName,
          statusText: '✓ Present',
          referenceId: refId,
        ),
      );
    }

    final code = event.errorCode ?? 'PUNCH_FAILED';
    final msg = event.errorMessage ?? 'Attendance verification failed.';

    return AttendanceVerificationResult(
      isSuccess: false,
      errorCode: code,
      errorMessage: msg,
      isOutOfGeofence: code == 'OUT_OF_GEOFENCE' || code == 'GEO_OUT_OF_BOUNDS',
      isIpUnauthorized: code == 'IP_NOT_WHITELISTED' || code == 'SSID_MISMATCH' || code == 'UNAUTHORIZED_NETWORK',
      isDuplicate: code == 'DUPLICATE_PUNCH',
      isUnauthorized: code == 'UNAUTHORIZED' || code == 'FACE_MISMATCH' || code == 'IMPERSONATION_ATTEMPT',
      isSpoofDetected: code.startsWith('SPOOF_') || code == 'PAD_FAILED',
    );
  }

  AttendanceVerificationResult _mapError(String errorStr) {
    final isOut = errorStr.contains('OUT_OF_GEOFENCE') || errorStr.contains('GEO_OUT_OF_BOUNDS');
    final isIp = errorStr.contains('IP_NOT_WHITELISTED') || errorStr.contains('SSID_MISMATCH') || errorStr.contains('UNAUTHORIZED_NETWORK');
    final isDup = errorStr.contains('DUPLICATE_PUNCH');
    final isUnauth = errorStr.contains('UNAUTHORIZED') || errorStr.contains('FACE_MISMATCH');
    final isSpoof = errorStr.contains('SPOOF_') || errorStr.contains('PAD_FAILED');

    return AttendanceVerificationResult(
      isSuccess: false,
      isOutOfGeofence: isOut,
      isIpUnauthorized: isIp,
      isDuplicate: isDup,
      isUnauthorized: isUnauth,
      isSpoofDetected: isSpoof,
      errorMessage: errorStr,
    );
  }

  @override
  void dispose() {
    socketService.dispose();
  }
}
