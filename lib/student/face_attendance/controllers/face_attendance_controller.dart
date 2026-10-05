import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/face_attendance_models.dart';
import '../models/face_attendance_state_config.dart';
import '../repositories/face_attendance_repository.dart';
import '../services/attendance_punch_service.dart';
import '../services/attendance_socket_service.dart';
import '../services/face_detection_service.dart';

enum _Phase { positioning, liveness, capturing, done }

class FaceAttendanceController extends ChangeNotifier {
  final FaceAttendanceRepository repository;
  final FaceDetectionService detectionService;

  FaceScanMode _mode = FaceScanMode.punch;
  CameraLensDirection _preferredLens = CameraLensDirection.front;
  FaceAttendanceStatus _status = FaceAttendanceStatus.initializing;
  FaceDetectionMetrics _metrics = FaceDetectionMetrics.initial;
  AttendanceSessionInfo _sessionInfo = AttendanceSessionInfo.defaultEvening();
  AttendanceRecordResult? _recordResult;
  TodayPunchSummary? _todayPunchSummary;

  bool _isCapturing = false;
  bool _isSessionCompleted = false;
  bool _disposed = false;

  _Phase _phase = _Phase.positioning;
  List<LivenessChallenge> _challenges = [
    LivenessChallenge.turnLeft,
    LivenessChallenge.turnRight,
    LivenessChallenge.blinkEyes,
  ];
  int _challengeIndex = 0;
  List<bool> _challengesDone = [false, false, false];
  bool _isRegistered = false;
  int _gestureFrameCount = 0;
  static const int _gestureFramesRequired = 2;

  // Server Challenge tracking
  String _currentChallengeId = '';
  String _currentNonce = '';
  String _currentRequestId = '';
  List<List<int>> _flashColors = [[10, 220, 255], [255, 10, 10]];
  Color? _activeFlashColor;

  // Frame evidence
  String? _baseFaceImageUrl;
  String? _flashImageUrl;
  String? _actionImageUrl;

  String _pendingStudentUsername = '';
  String _pendingStudentName = '';
  String _pendingRegisterNumber = '';
  String? _customErrorMessage;
  String? _customSuccessMessage;

  FaceScanMode get mode => _mode;
  CameraLensDirection get preferredLens => _preferredLens;
  FaceAttendanceStatus get status => _status;
  FaceDetectionMetrics get metrics => _metrics;
  AttendanceSessionInfo get sessionInfo => _sessionInfo;
  AttendanceRecordResult? get recordResult => _recordResult;
  TodayPunchSummary? get todayPunchSummary => _todayPunchSummary;
  bool get isCapturing => _isCapturing;
  bool get isVerifying => _status == FaceAttendanceStatus.verifying || _status == FaceAttendanceStatus.registering;
  bool get isSessionCompleted => _isSessionCompleted;
  bool get isRegistered => _isRegistered;
  Color? get activeFlashColor => _activeFlashColor;
  String? get customErrorMessage => _customErrorMessage;
  String? get customSuccessMessage => _customSuccessMessage;

  LivenessChallenge? get currentChallenge =>
      _phase == _Phase.liveness && _challengeIndex < _challenges.length
          ? _challenges[_challengeIndex]
          : null;

  int get currentChallengeIndex => _challengeIndex;
  List<bool> get challengesDone => List.unmodifiable(_challengesDone);
  List<LivenessChallenge> get challenges => List.unmodifiable(_challenges);

  FaceAttendanceStateConfig get currentConfig =>
      FaceAttendanceStateMap.getConfig(_status);

  FaceAttendanceController({
    FaceAttendanceRepository? repository,
    FaceDetectionService? detectionService,
    FaceScanMode initialMode = FaceScanMode.punch,
    CameraLensDirection? preferredLens,
  })  : repository = repository ?? ProductionFaceAttendanceRepository(),
        detectionService = detectionService ?? FaceDetectionService(),
        _mode = initialMode,
        _preferredLens = preferredLens ??
            (initialMode == FaceScanMode.registration
                ? CameraLensDirection.back
                : CameraLensDirection.front);

  void setScanMode(FaceScanMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    if (newMode == FaceScanMode.registration) {
      _preferredLens = CameraLensDirection.back;
    }
    retry();
  }

  Future<void> initialize() async {
    _phase = _Phase.positioning;
    _status = FaceAttendanceStatus.initializing;
    _metrics = FaceDetectionMetrics.initial;
    _isCapturing = false;
    _isSessionCompleted = false;
    _challengeIndex = 0;
    _gestureFrameCount = 0;
    _customErrorMessage = null;
    _customSuccessMessage = null;

    if (_mode == FaceScanMode.registration) {
      _challenges = [
        LivenessChallenge.turnLeft,
        LivenessChallenge.turnRight,
        LivenessChallenge.blinkEyes,
      ];
      _challengesDone = [false, false, false];
    } else {
      _challenges = [
        LivenessChallenge.lookStraight,
        LivenessChallenge.blinkEyes,
        LivenessChallenge.colorFlash,
      ];
      _challengesDone = [false, false, false];
    }
    _notifySafely();

    try {
      _sessionInfo = await repository.getCurrentSession();
    } catch (_) {}

    // Check local registration status
    if (_pendingStudentUsername.isNotEmpty) {
      final localEnrolled = await AttendancePunchService.isFaceEnrolled(_pendingStudentUsername);
      if (localEnrolled) _isRegistered = true;
      _todayPunchSummary = await AttendancePunchService.getTodayPunchSummary(_pendingStudentUsername);
    }

    // Bootstrap manager session
    try {
      final bioId = int.tryParse(_pendingStudentUsername) ?? (int.tryParse(_pendingRegisterNumber) ?? 1001);
      final session = await repository.bootstrapSession(bioId: bioId);
      if (session.faceEnrolled) {
        _isRegistered = true;
        if (_pendingStudentUsername.isNotEmpty) {
          await AttendancePunchService.setFaceEnrolled(_pendingStudentUsername);
        }
      }
      
      // Connect to Socket.IO
      await repository.connectSocket(session.accessToken);
      
      // Listen for incoming server liveness challenge
      repository.onLivenessChallenge.listen(_handleServerChallenge);
    } catch (e) {
      debugPrint('Bootstrap / Socket.IO error: $e');
      _customErrorMessage = e.toString().replaceFirst('Exception: ', '');
      _status = FaceAttendanceStatus.networkError;
      _notifySafely();
      return;
    }

    await detectionService.initialize(
      onStatusChanged: onDetectionUpdate,
      preferredLens: _preferredLens,
    );
    _notifySafely();
  }

  void _handleServerChallenge(LivenessChallengeData data) {
    if (_disposed) return;
    _currentChallengeId = data.challengeId;
    _currentNonce = data.nonce;
    _flashColors = data.flashColors;

    if (_mode == FaceScanMode.registration) {
      // Compulsory 3 steps for registration: Turn Left -> Turn Right -> Blink Eyes
      _challenges = [
        LivenessChallenge.turnLeft,
        LivenessChallenge.turnRight,
        LivenessChallenge.blinkEyes,
      ];
      _challengesDone = [false, false, false];
      _challengeIndex = 0;
      _notifySafely();
    } else {
      final parsedSteps = data.steps.map((s) => LivenessChallengeX.fromServerString(s)).toList();
      if (parsedSteps.isNotEmpty) {
        _challenges = parsedSteps;
        _challengesDone = List.filled(parsedSteps.length, false);
        _challengeIndex = 0;
        _notifySafely();
      }
    }
  }

  void onDetectionUpdate(FaceAttendanceStatus newStatus, FaceDetectionMetrics newMetrics) {
    if (_isCapturing || _isSessionCompleted || _disposed) return;
    _metrics = newMetrics;
    switch (_phase) {
      case _Phase.positioning:
        _handlePositioning(newStatus);
        break;
      case _Phase.liveness:
        _handleLiveness(newStatus, newMetrics);
        break;
      case _Phase.capturing:
      case _Phase.done:
        break;
    }
  }

  void _handlePositioning(FaceAttendanceStatus s) {
    _status = s;
    _notifySafely();
    if (s == FaceAttendanceStatus.positioned) {
      // If student is trying to punch/check-in without registration, halt and inform
      if (_mode == FaceScanMode.punch && !_isRegistered) {
        _phase = _Phase.done;
        _status = FaceAttendanceStatus.verificationFailed;
        _customErrorMessage = "Face Not Enrolled: Please visit your assigned Floor Warden in person with your Register Number to register your face biometric.";
        _notifySafely();
        return;
      }

      _phase = _Phase.liveness;
      _challengeIndex = 0;
      _gestureFrameCount = 0;
      _status = FaceAttendanceStatus.livenessChallenge;
      _currentRequestId = const Uuid().v4();
      
      // Request server liveness session with exact purpose
      repository.startLivenessSession(
        requestId: _currentRequestId,
        purpose: _mode == FaceScanMode.registration ? 'enroll' : 'punch',
      );
      
      _notifySafely();
    }
  }

  void _handleLiveness(FaceAttendanceStatus s, FaceDetectionMetrics m) {
    if (s == FaceAttendanceStatus.noFace ||
        s == FaceAttendanceStatus.multipleFaces ||
        s == FaceAttendanceStatus.outOfFrame) {
      _phase = _Phase.positioning;
      _gestureFrameCount = 0;
      _status = s;
      _notifySafely();
      return;
    }

    if (_challengeIndex >= _challenges.length) return;

    final currentStep = _challenges[_challengeIndex];

    if (_checkGesture(currentStep, m)) {
      _gestureFrameCount++;
      if (_gestureFrameCount >= _gestureFramesRequired) {
        _gestureFrameCount = 0;
        _advanceStep(currentStep);
      } else {
        _notifySafely();
      }
    } else {
      if (_gestureFrameCount > 0) {
        _gestureFrameCount = 0;
        _notifySafely();
      }
    }
  }

  Future<void> _advanceStep(LivenessChallenge step) async {
    if (_disposed) return;

    // Capture frame for step
    final frameBase64 = await detectionService.captureFrameBase64();

    if (step == LivenessChallenge.lookStraight) {
      _baseFaceImageUrl = frameBase64;
    } else if (step == LivenessChallenge.colorFlash) {
      // Execute color flash effect
      if (_flashColors.isNotEmpty) {
        final c = _flashColors.first;
        _activeFlashColor = Color.fromARGB(255, c[0], c.length > 1 ? c[1] : 0, c.length > 2 ? c[2] : 0);
        _notifySafely();
        await Future.delayed(const Duration(milliseconds: 250));
        _flashImageUrl = await detectionService.captureFrameBase64();
        _activeFlashColor = null;
        _notifySafely();
      }
    } else {
      _actionImageUrl = frameBase64;
    }

    // Stream frame to server
    if (frameBase64 != null) {
      repository.sendLivenessFrame(
        requestId: _currentRequestId,
        challengeId: _currentChallengeId,
        nonce: _currentNonce,
        step: step.serverKey,
        imageDataUrl: frameBase64,
      );
    }

    _challengesDone[_challengeIndex] = true;
    _challengeIndex++;
    _notifySafely();

    if (_challengeIndex >= _challenges.length) {
      _phase = _Phase.capturing;
      _status = FaceAttendanceStatus.livenessComplete;
      _notifySafely();
      Future.delayed(const Duration(milliseconds: 400), _executeSubmission);
    } else {
      _status = FaceAttendanceStatus.livenessChallenge;
      _notifySafely();
    }
  }

  bool _checkGesture(LivenessChallenge challenge, FaceDetectionMetrics m) {
    switch (challenge) {
      case LivenessChallenge.lookStraight:
        return (m.headEulerY ?? 0).abs() < 8.0 &&
            (m.leftEyeOpenProbability ?? 1.0) > 0.6 &&
            (m.rightEyeOpenProbability ?? 1.0) > 0.6;
      case LivenessChallenge.turnRight:
        // Turn right: negative EulerY on front camera, positive on rear camera (or > 8.0 / < -8.0)
        return (m.headEulerY ?? 0) < -8.0 || (detectionService.isBackCamera && (m.headEulerY ?? 0) > 8.0);
      case LivenessChallenge.turnLeft:
        // Turn left: positive EulerY on front camera, negative on rear camera (or > 8.0 / < -8.0)
        return (m.headEulerY ?? 0) > 8.0 || (detectionService.isBackCamera && (m.headEulerY ?? 0) < -8.0);
      case LivenessChallenge.blinkEyes:
        return (m.leftEyeOpenProbability ?? 1.0) < 0.40 &&
            (m.rightEyeOpenProbability ?? 1.0) < 0.40;
      case LivenessChallenge.openMouth:
        return true; // Frame streamed and validated on server
      case LivenessChallenge.colorFlash:
        return true;
    }
  }

  Future<void> _executeSubmission() async {
    if (_isCapturing || _isSessionCompleted || _disposed) return;

    if (_mode == FaceScanMode.registration) {
      await registerFace();
    } else {
      await verifyAttendance();
    }
  }

  void setStudentInfo({
    required String username,
    required String name,
    required String registerNumber,
  }) async {
    _pendingStudentUsername = username;
    _pendingStudentName = name;
    _pendingRegisterNumber = registerNumber;

    final localEnrolled = await AttendancePunchService.isFaceEnrolled(username);
    if (localEnrolled && !_disposed) {
      _isRegistered = true;
      _notifySafely();
    }

    _todayPunchSummary = await AttendancePunchService.getTodayPunchSummary(username);
    if (!_disposed) _notifySafely();

    repository.isFaceRegistered(username).then((registered) {
      if (!_disposed) {
        _isRegistered = registered || localEnrolled;
        _notifySafely();
      }
    }).catchError((_) {});
  }

  /// Register student face (Server Enrollment)
  Future<void> registerFace({
    String? studentUsername,
    String? studentName,
    String? registerNumber,
  }) async {
    if (_disposed || _isSessionCompleted) return;

    _status = FaceAttendanceStatus.registering;
    _isCapturing = true;
    _notifySafely();

    final baseImg = _baseFaceImageUrl ?? await detectionService.captureFrameBase64() ?? '';

    try {
      final result = await repository.completeEnrollment(
        requestId: _currentRequestId,
        challengeId: _currentChallengeId,
        nonce: _currentNonce,
        completedSteps: _challenges.map((c) => c.serverKey).toList(),
        baseFaceImageUrl: baseImg,
        flashImageUrl: _flashImageUrl,
        actionImageUrl: _actionImageUrl,
      );

      if (_disposed) return;

      if (result.isSuccess) {
        _isRegistered = true;
        _isSessionCompleted = true;
        _status = FaceAttendanceStatus.faceRegistered;
        _customSuccessMessage = "Your Face Biometric has been registered successfully! 🎉 You can now check in.";

        // Save local enrollment flag
        if (_pendingStudentUsername.isNotEmpty) {
          await AttendancePunchService.setFaceEnrolled(_pendingStudentUsername);
        }

        final now = DateTime.now();
        _recordResult = AttendanceRecordResult(
          studentName: _pendingStudentName.isNotEmpty ? _pendingStudentName : 'Student',
          registerNumber: _pendingRegisterNumber.isNotEmpty ? _pendingRegisterNumber : _pendingStudentUsername,
          dateFormatted: DateFormat('EEE, d MMM yyyy').format(now),
          timeFormatted: DateFormat('h:mm a').format(now),
          sessionName: 'Face Registration',
          statusText: '✓ Registered Successfully',
          punchType: 'REG',
          isCheckIn: true,
        );
      } else {
        _customErrorMessage = result.errorMessage ?? 'Registration failed. Please try again.';
        _status = FaceAttendanceStatus.networkError;
      }
    } catch (e) {
      if (!_disposed) {
        _customErrorMessage = e.toString();
        _status = FaceAttendanceStatus.networkError;
      }
    }
    _isCapturing = false;
    _notifySafely();
  }

  /// Verify face and mark Check-In or Check-Out punch
  Future<void> verifyAttendance({
    String? studentUsername,
    String? studentName,
    String? registerNumber,
  }) async {
    if (_isCapturing && _status == FaceAttendanceStatus.verifying) return;
    if (_isSessionCompleted || _disposed) return;

    final n = studentName ?? _pendingStudentName;
    final r = registerNumber ?? _pendingRegisterNumber;
    final u = studentUsername ?? _pendingStudentUsername;

    _isCapturing = true;
    _status = FaceAttendanceStatus.verifying;
    _customErrorMessage = null;
    _notifySafely();

    final baseImg = _baseFaceImageUrl ?? await detectionService.captureFrameBase64() ?? '';

    // Calculate punch type based on today's punches
    final todaySummary = await AttendancePunchService.getTodayPunchSummary(u);
    final isFirstPunchToday = !todaySummary.hasCheckIn;
    final punchType = isFirstPunchToday ? 'IN' : 'OUT';

    try {
      final result = await repository.verifyFastPunch(
        requestId: _currentRequestId,
        challengeId: _currentChallengeId,
        nonce: _currentNonce,
        completedSteps: _challenges.map((c) => c.serverKey).toList(),
        punchType: punchType,
        baseFaceImageUrl: baseImg,
        flashImageUrl: _flashImageUrl,
        actionImageUrl: _actionImageUrl,
        studentName: n,
        registerNumber: r,
        sessionName: _sessionInfo.sessionName,
      );

      if (_disposed) return;

      if (result.isSuccess) {
        // Record punch in local storage
        final punchRecord = await AttendancePunchService.recordPunch(
          username: u,
          studentName: n,
          registerNumber: r,
          sessionName: _sessionInfo.sessionName,
        );

        final now = DateTime.now();
        _recordResult = AttendanceRecordResult(
          studentName: n.isNotEmpty ? n : 'Resident Student',
          registerNumber: r.isNotEmpty ? r : 'SIMATS',
          dateFormatted: punchRecord['dateFormatted'] ?? DateFormat('EEE, d MMM yyyy').format(now),
          timeFormatted: punchRecord['timeFormatted'] ?? DateFormat('h:mm a').format(now),
          sessionName: _sessionInfo.sessionName,
          statusText: punchRecord['isCheckIn'] == true ? '✓ Check-In Recorded' : '✓ Check-Out Recorded',
          referenceId: result.record?.referenceId ?? 'PUNCH-${now.millisecondsSinceEpoch.toString().substring(6)}',
          punchType: punchRecord['punchType'] ?? punchType,
          isCheckIn: punchRecord['isCheckIn'] ?? isFirstPunchToday,
          firstCheckInTime: punchRecord['firstCheckIn'],
          lastCheckOutTime: punchRecord['lastCheckOut'],
          totalPunchesToday: punchRecord['totalPunchesToday'] ?? 1,
        );

        _status = FaceAttendanceStatus.verified;
        _notifySafely();

        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (_disposed) return;

        _status = FaceAttendanceStatus.attendanceMarked;
        _isSessionCompleted = true;
      } else if (result.isNetworkError) {
        _customErrorMessage = result.errorMessage ?? 'Network error occurred. Please check connection.';
        _status = FaceAttendanceStatus.networkError;
      } else if (result.isOutOfGeofence) {
        _customErrorMessage = result.errorMessage ?? 'Out of Geofence: You are outside the authorized hostel geofence boundaries.';
        _status = FaceAttendanceStatus.outOfFrame;
      } else if (result.isIpUnauthorized) {
        _customErrorMessage = result.errorMessage ?? 'Unauthorized Network: Campus Wi-Fi / whitelisted IP is required for biometric attendance.';
        _status = FaceAttendanceStatus.networkError;
      } else if (result.isSpoofDetected) {
        _customErrorMessage = result.errorMessage ?? 'Anti-Spoofing Detection Failed: Live human reflection verification failed.';
        _status = FaceAttendanceStatus.verificationFailed;
      } else if (result.isUnauthorized) {
        _customErrorMessage = result.errorMessage ?? 'Face mismatch with registered student identity.';
        _status = FaceAttendanceStatus.unauthorized;
      } else if (result.isDuplicate) {
        _customErrorMessage = result.errorMessage ?? 'Attendance already recorded for today.';
        _status = FaceAttendanceStatus.duplicate;
        _isSessionCompleted = true;
      } else {
        _customErrorMessage = result.errorMessage ?? 'Verification failed by attendance server. Please retry.';
        _status = FaceAttendanceStatus.verificationFailed;
      }
    } catch (e) {
      if (!_disposed) {
        _customErrorMessage = e.toString();
        _status = FaceAttendanceStatus.networkError;
      }
    }
    _isCapturing = false;
    _notifySafely();
  }

  void setDebugState(FaceAttendanceStatus debugStatus) {
    if (kDebugMode) {
      _status = debugStatus;
      _metrics = FaceAttendanceStateMap.getConfig(debugStatus).defaultMetrics;
      if (debugStatus == FaceAttendanceStatus.attendanceMarked) {
        _recordResult = AttendanceRecordResult(
          studentName: _pendingStudentName.isNotEmpty ? _pendingStudentName : 'Resident Student',
          registerNumber: _pendingRegisterNumber.isNotEmpty ? _pendingRegisterNumber : 'SIMATS-001',
          dateFormatted: 'Today',
          timeFormatted: '7:42 PM',
          sessionName: _sessionInfo.sessionName,
          statusText: '✓ Check-In Recorded',
          referenceId: 'REF-789234',
          punchType: 'IN',
          isCheckIn: true,
        );
      }
      _notifySafely();
    }
  }

  void retry() {
    _phase = _Phase.positioning;
    _challengeIndex = 0;
    _gestureFrameCount = 0;
    _challengesDone = List.filled(_challenges.length, false);
    _isCapturing = false;
    _isSessionCompleted = false;
    _customErrorMessage = null;
    _customSuccessMessage = null;
    _baseFaceImageUrl = null;
    _flashImageUrl = null;
    _actionImageUrl = null;
    _status = FaceAttendanceStatus.cameraReady;
    _metrics = FaceDetectionMetrics.searching;
    _notifySafely();
    detectionService.resume(onStatusChanged: onDetectionUpdate);
  }

  Future<void> requestCameraPermission() async => initialize();

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    repository.dispose();
    detectionService.dispose();
    super.dispose();
  }
}
