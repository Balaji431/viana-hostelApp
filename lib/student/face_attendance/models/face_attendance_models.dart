import 'package:flutter/material.dart';

/// All face attendance states (positioning + liveness + registration)
enum FaceAttendanceStatus {
  // ── Camera / Positioning ──────────────────────────────────────────────────
  initializing,
  cameraReady,
  noFace,
  faceDetected,
  positioned,
  multipleFaces,
  tooFar,
  tooClose,
  outOfFrame,
  poorLighting,
  // ── Liveness Challenges ───────────────────────────────────────────────────
  livenessChallenge,   // one challenge is active (turn/blink)
  livenessComplete,    // all 3 challenges passed — ready to register or verify
  // ── Registration (first-time) ─────────────────────────────────────────────
  registering,         // capturing + uploading face for registration
  faceRegistered,      // face registration successful
  // ── Attendance Verification (returning) ───────────────────────────────────
  readyToVerify,
  verifying,
  verified,
  verificationFailed,
  attendanceMarked,
  unauthorized,        // face doesn't match registered profile
  // ── Error / Terminal ──────────────────────────────────────────────────────
  permissionDenied,
  permissionPermanentlyDenied,
  networkError,
  duplicate,
}

/// The server-driven liveness challenge steps
enum LivenessChallenge {
  lookStraight,
  blinkEyes,
  turnRight,
  turnLeft,
  openMouth,
  colorFlash,
}

extension LivenessChallengeX on LivenessChallenge {
  static LivenessChallenge fromServerString(String str) {
    final s = str.toLowerCase().trim();
    if (s.contains('straight')) return LivenessChallenge.lookStraight;
    if (s.contains('blink')) return LivenessChallenge.blinkEyes;
    if (s.contains('right')) return LivenessChallenge.turnRight;
    if (s.contains('left')) return LivenessChallenge.turnLeft;
    if (s.contains('mouth')) return LivenessChallenge.openMouth;
    if (s.contains('flash') || s.contains('color')) return LivenessChallenge.colorFlash;
    return LivenessChallenge.lookStraight;
  }

  String get serverKey {
    switch (this) {
      case LivenessChallenge.lookStraight: return 'look_straight';
      case LivenessChallenge.blinkEyes:    return 'blink';
      case LivenessChallenge.turnRight:    return 'turn_right';
      case LivenessChallenge.turnLeft:     return 'turn_left';
      case LivenessChallenge.openMouth:    return 'open_mouth';
      case LivenessChallenge.colorFlash:   return 'color_flash';
    }
  }

  String get instruction {
    switch (this) {
      case LivenessChallenge.lookStraight: return 'Look straight at the camera';
      case LivenessChallenge.blinkEyes:    return 'Blink your eyes';
      case LivenessChallenge.turnRight:    return 'Turn your head right';
      case LivenessChallenge.turnLeft:     return 'Turn your head left';
      case LivenessChallenge.openMouth:    return 'Open your mouth slightly';
      case LivenessChallenge.colorFlash:   return 'Hold still for screen flash check';
    }
  }

  String get hint {
    switch (this) {
      case LivenessChallenge.lookStraight: return 'Align face in the center of the ring.';
      case LivenessChallenge.blinkEyes:    return 'Close both eyes briefly and open.';
      case LivenessChallenge.turnRight:    return 'Slowly rotate your head to the right.';
      case LivenessChallenge.turnLeft:     return 'Slowly rotate your head to the left.';
      case LivenessChallenge.openMouth:    return 'Open mouth briefly to verify liveness.';
      case LivenessChallenge.colorFlash:   return 'Keep face steady while screen flashes.';
    }
  }

  String get iconEmoji {
    switch (this) {
      case LivenessChallenge.lookStraight: return '🎯';
      case LivenessChallenge.blinkEyes:    return '👁';
      case LivenessChallenge.turnRight:    return '→';
      case LivenessChallenge.turnLeft:     return '←';
      case LivenessChallenge.openMouth:    return '😮';
      case LivenessChallenge.colorFlash:   return '⚡';
    }
  }
}

/// Visual tone for overlay, stroke, and pill
enum FaceGuidanceTone {
  neutral,
  active,
  success,
  warning,
  danger,
  scanning,
}

/// Level indicator for 2x2 metric tiles
enum MetricLevel {
  good,
  warn,
  bad,
  pending,
}

/// Mode of the primary action button
enum ActionButtonMode {
  enabled,
  disabled,
  verifying,
  completed,
  retry,
}

/// Alert message type
enum AlertBannerType {
  warning,
  danger,
  info,
}

/// Progress step state
enum StepIndicatorState {
  upcoming,
  current,
  done,
  error,
}

/// Face detection metrics reported from the detection / frame analysis layer
class FaceDetectionMetrics {
  final MetricLevel faceStatusLevel;
  final String faceStatusText;
  final MetricLevel positionLevel;
  final String positionText;
  final MetricLevel lightingLevel;
  final String lightingText;
  final MetricLevel distanceLevel;
  final String distanceText;
  final int faceCount;
  final Rect? faceRect;
  final double? brightness;

  /// Raw face geometry from ML Kit — used for liveness challenge detection
  final double? headEulerY;               // yaw: positive = turn right, negative = turn left
  final double? leftEyeOpenProbability;   // 0.0 = closed, 1.0 = open
  final double? rightEyeOpenProbability;  // 0.0 = closed, 1.0 = open

  const FaceDetectionMetrics({
    this.faceStatusLevel = MetricLevel.pending,
    this.faceStatusText = 'Waiting',
    this.positionLevel = MetricLevel.pending,
    this.positionText = 'Waiting',
    this.lightingLevel = MetricLevel.pending,
    this.lightingText = 'Waiting',
    this.distanceLevel = MetricLevel.pending,
    this.distanceText = 'Waiting',
    this.faceCount = 0,
    this.faceRect,
    this.brightness,
    this.headEulerY,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
  });

  static const FaceDetectionMetrics initial = FaceDetectionMetrics(
    faceStatusLevel: MetricLevel.pending,
    faceStatusText: 'Waiting',
    positionLevel: MetricLevel.pending,
    positionText: 'Waiting',
    lightingLevel: MetricLevel.pending,
    lightingText: 'Waiting',
    distanceLevel: MetricLevel.pending,
    distanceText: 'Waiting',
    faceCount: 0,
  );

  static const FaceDetectionMetrics searching = FaceDetectionMetrics(
    faceStatusLevel: MetricLevel.pending,
    faceStatusText: 'Searching',
    positionLevel: MetricLevel.pending,
    positionText: 'Not available',
    lightingLevel: MetricLevel.pending,
    lightingText: 'Not available',
    distanceLevel: MetricLevel.pending,
    distanceText: 'Not available',
    faceCount: 0,
  );

  static const FaceDetectionMetrics noFace = FaceDetectionMetrics(
    faceStatusLevel: MetricLevel.bad,
    faceStatusText: 'No face',
    positionLevel: MetricLevel.pending,
    positionText: 'N/A',
    lightingLevel: MetricLevel.pending,
    lightingText: 'N/A',
    distanceLevel: MetricLevel.pending,
    distanceText: 'N/A',
    faceCount: 0,
  );

  static const FaceDetectionMetrics multiple = FaceDetectionMetrics(
    faceStatusLevel: MetricLevel.bad,
    faceStatusText: '2 faces',
    positionLevel: MetricLevel.pending,
    positionText: 'N/A',
    lightingLevel: MetricLevel.good,
    lightingText: 'Good',
    distanceLevel: MetricLevel.pending,
    distanceText: 'N/A',
    faceCount: 2,
  );

  static const FaceDetectionMetrics allGood = FaceDetectionMetrics(
    faceStatusLevel: MetricLevel.good,
    faceStatusText: '1 face',
    positionLevel: MetricLevel.good,
    positionText: 'Centered',
    lightingLevel: MetricLevel.good,
    lightingText: 'Good',
    distanceLevel: MetricLevel.good,
    distanceText: 'Optimal',
    faceCount: 1,
  );

  static const FaceDetectionMetrics notRequired = FaceDetectionMetrics(
    faceStatusLevel: MetricLevel.pending,
    faceStatusText: 'Not required',
    positionLevel: MetricLevel.pending,
    positionText: 'Not required',
    lightingLevel: MetricLevel.pending,
    lightingText: 'Not required',
    distanceLevel: MetricLevel.pending,
    distanceText: 'Not required',
    faceCount: 0,
  );

  FaceDetectionMetrics copyWith({
    MetricLevel? faceStatusLevel,
    String? faceStatusText,
    MetricLevel? positionLevel,
    String? positionText,
    MetricLevel? lightingLevel,
    String? lightingText,
    MetricLevel? distanceLevel,
    String? distanceText,
    int? faceCount,
    Rect? faceRect,
    double? brightness,
    double? headEulerY,
    double? leftEyeOpenProbability,
    double? rightEyeOpenProbability,
  }) {
    return FaceDetectionMetrics(
      faceStatusLevel: faceStatusLevel ?? this.faceStatusLevel,
      faceStatusText: faceStatusText ?? this.faceStatusText,
      positionLevel: positionLevel ?? this.positionLevel,
      positionText: positionText ?? this.positionText,
      lightingLevel: lightingLevel ?? this.lightingLevel,
      lightingText: lightingText ?? this.lightingText,
      distanceLevel: distanceLevel ?? this.distanceLevel,
      distanceText: distanceText ?? this.distanceText,
      faceCount: faceCount ?? this.faceCount,
      faceRect: faceRect ?? this.faceRect,
      brightness: brightness ?? this.brightness,
      headEulerY: headEulerY ?? this.headEulerY,
      leftEyeOpenProbability: leftEyeOpenProbability ?? this.leftEyeOpenProbability,
      rightEyeOpenProbability: rightEyeOpenProbability ?? this.rightEyeOpenProbability,
    );
  }
}

/// Active Roll Call / Attendance Session info
class AttendanceSessionInfo {
  final String sessionName;
  final String timeRange;
  final DateTime startTime;
  final DateTime endTime;
  final bool isWindowOpen;

  const AttendanceSessionInfo({
    required this.sessionName,
    required this.timeRange,
    required this.startTime,
    required this.endTime,
    this.isWindowOpen = true,
  });

  static AttendanceSessionInfo defaultEvening() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 19, 0);
    final end = DateTime(now.year, now.month, now.day, 21, 0);
    return AttendanceSessionInfo(
      sessionName: 'Evening Roll Call',
      timeRange: '7:00 – 9:00 PM',
      startTime: start,
      endTime: end,
      isWindowOpen: true,
    );
  }
}

/// Mode of the Face Biometric scanner
enum FaceScanMode {
  punch,        // Check-In / Check-Out
  registration, // Register Face Biometrics
}

/// Result record returned on successful attendance submission
class AttendanceRecordResult {
  final String studentName;
  final String registerNumber;
  final String dateFormatted;
  final String timeFormatted;
  final String sessionName;
  final String statusText;
  final String? referenceId;
  final String punchType; // 'IN' or 'OUT'
  final bool isCheckIn;
  final String? firstCheckInTime;
  final String? lastCheckOutTime;
  final int totalPunchesToday;

  const AttendanceRecordResult({
    required this.studentName,
    required this.registerNumber,
    required this.dateFormatted,
    required this.timeFormatted,
    required this.sessionName,
    this.statusText = '✓ Present',
    this.referenceId,
    this.punchType = 'IN',
    this.isCheckIn = true,
    this.firstCheckInTime,
    this.lastCheckOutTime,
    this.totalPunchesToday = 1,
  });
}

