import 'package:flutter/material.dart';
import '../theme/face_attendance_theme.dart';
import 'face_attendance_models.dart';

/// Single configuration record for a UI state
class FaceAttendanceStateConfig {
  final FaceAttendanceStatus status;
  final FaceGuidanceTone tone;
  final String statusPillText;
  final IconData statusPillIcon;
  final Color statusPillTextColor;
  final String guideText;
  final String guideHint;
  final int stepIndex; // 0, 1, 2
  final StepIndicatorState stepState;
  final String? alertTitle;
  final String? alertMessage;
  final AlertBannerType? alertType;
  final FaceDetectionMetrics defaultMetrics;
  final ActionButtonMode buttonMode;
  final String buttonLabel;
  final String buttonHint;
  final IconData? buttonIcon;

  const FaceAttendanceStateConfig({
    required this.status,
    required this.tone,
    required this.statusPillText,
    required this.statusPillIcon,
    required this.statusPillTextColor,
    required this.guideText,
    required this.guideHint,
    required this.stepIndex,
    required this.stepState,
    this.alertTitle,
    this.alertMessage,
    this.alertType,
    required this.defaultMetrics,
    required this.buttonMode,
    required this.buttonLabel,
    required this.buttonHint,
    this.buttonIcon,
  });
}

/// Central state configuration repository mapping all states exactly to the spec
class FaceAttendanceStateMap {
  static final Map<FaceAttendanceStatus, FaceAttendanceStateConfig> configs = {
    // 1. Initializing
    FaceAttendanceStatus.initializing: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.initializing,
      tone: FaceGuidanceTone.neutral,
      statusPillText: 'Starting camera',
      statusPillIcon: Icons.camera_front_outlined,
      statusPillTextColor: FaceAttendanceTheme.creamLight,
      guideText: 'Starting camera…',
      guideHint: 'Preparing the front camera.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.initial,
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Available once the camera is ready.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 2. Camera Ready
    FaceAttendanceStatus.cameraReady: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.cameraReady,
      tone: FaceGuidanceTone.neutral,
      statusPillText: 'Camera ready',
      statusPillIcon: Icons.camera_front_outlined,
      statusPillTextColor: FaceAttendanceTheme.creamLight,
      guideText: 'Position your face inside the frame',
      guideHint: 'Look straight at the camera.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.searching,
      buttonMode: ActionButtonMode.enabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Position your face inside the guide to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 3. No Face
    FaceAttendanceStatus.noFace: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.noFace,
      tone: FaceGuidanceTone.neutral,
      statusPillText: 'No face detected',
      statusPillIcon: Icons.face_retouching_natural,
      statusPillTextColor: FaceAttendanceTheme.creamLight,
      guideText: 'Position your face inside the frame',
      guideHint: 'Make sure your whole face is visible.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      alertTitle: 'No face detected',
      alertMessage: 'No face detected. Position your face inside the guide.',
      alertType: AlertBannerType.warning,
      defaultMetrics: FaceDetectionMetrics.noFace,
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Position your face inside the guide to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 4. Face Detected
    FaceAttendanceStatus.faceDetected: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.faceDetected,
      tone: FaceGuidanceTone.active,
      statusPillText: 'Face detected',
      statusPillIcon: Icons.face_retouching_natural,
      statusPillTextColor: FaceAttendanceTheme.goldLight,
      guideText: 'Face detected',
      guideHint: 'Align your face with the guide.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.good,
        faceStatusText: '1 face',
        positionLevel: MetricLevel.warn,
        positionText: 'Adjusting',
        lightingLevel: MetricLevel.good,
        lightingText: 'Good',
        distanceLevel: MetricLevel.good,
        distanceText: 'Optimal',
        faceCount: 1,
      ),
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Center your face in the guide to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 5. Positioned
    FaceAttendanceStatus.positioned: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.positioned,
      tone: FaceGuidanceTone.success,
      statusPillText: 'Position correct',
      statusPillIcon: Icons.check_circle_outline,
      statusPillTextColor: FaceAttendanceTheme.successGreenMuted,
      guideText: 'Perfect. Hold still.',
      guideHint: 'Keep your face inside the guide.',
      stepIndex: 0,
      stepState: StepIndicatorState.done,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.enabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Your face is positioned correctly.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 6. Multiple Faces
    FaceAttendanceStatus.multipleFaces: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.multipleFaces,
      tone: FaceGuidanceTone.danger,
      statusPillText: '2 faces detected',
      statusPillIcon: Icons.people_outline,
      statusPillTextColor: FaceAttendanceTheme.dangerRedMuted,
      guideText: 'Multiple faces detected',
      guideHint: 'Only one person should be visible.',
      stepIndex: 0,
      stepState: StepIndicatorState.error,
      alertTitle: 'Multiple faces detected',
      alertMessage: 'Multiple faces detected. Only one person should be visible.',
      alertType: AlertBannerType.danger,
      defaultMetrics: FaceDetectionMetrics.multiple,
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Only one face can be verified at a time.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 7. Too Far
    FaceAttendanceStatus.tooFar: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.tooFar,
      tone: FaceGuidanceTone.warning,
      statusPillText: 'Too far',
      statusPillIcon: Icons.warning_amber_rounded,
      statusPillTextColor: FaceAttendanceTheme.warningAmberLight,
      guideText: 'Move closer',
      guideHint: 'Your face should fill the guide.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      alertTitle: 'Too far from the camera',
      alertMessage: 'Move closer to the camera.',
      alertType: AlertBannerType.warning,
      defaultMetrics: FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.good,
        faceStatusText: '1 face',
        positionLevel: MetricLevel.good,
        positionText: 'Centered',
        lightingLevel: MetricLevel.good,
        lightingText: 'Good',
        distanceLevel: MetricLevel.warn,
        distanceText: 'Too far',
        faceCount: 1,
      ),
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Move closer to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 8. Too Close
    FaceAttendanceStatus.tooClose: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.tooClose,
      tone: FaceGuidanceTone.warning,
      statusPillText: 'Too close',
      statusPillIcon: Icons.warning_amber_rounded,
      statusPillTextColor: FaceAttendanceTheme.warningAmberLight,
      guideText: 'Move back slightly',
      guideHint: 'Keep your whole face inside the guide.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      alertTitle: 'Too close to the camera',
      alertMessage: 'Move slightly away from the camera.',
      alertType: AlertBannerType.warning,
      defaultMetrics: FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.good,
        faceStatusText: '1 face',
        positionLevel: MetricLevel.good,
        positionText: 'Centered',
        lightingLevel: MetricLevel.good,
        lightingText: 'Good',
        distanceLevel: MetricLevel.warn,
        distanceText: 'Too close',
        faceCount: 1,
      ),
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Move back slightly to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 9. Out of Frame
    FaceAttendanceStatus.outOfFrame: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.outOfFrame,
      tone: FaceGuidanceTone.warning,
      statusPillText: 'Off-center',
      statusPillIcon: Icons.warning_amber_rounded,
      statusPillTextColor: FaceAttendanceTheme.warningAmberLight,
      guideText: 'Move to the center',
      guideHint: 'Align your face with the guide.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      alertTitle: 'Face out of frame',
      alertMessage: 'Move your face slightly to the center.',
      alertType: AlertBannerType.warning,
      defaultMetrics: FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.good,
        faceStatusText: '1 face',
        positionLevel: MetricLevel.warn,
        positionText: 'Off-center',
        lightingLevel: MetricLevel.good,
        lightingText: 'Good',
        distanceLevel: MetricLevel.good,
        distanceText: 'Optimal',
        faceCount: 1,
      ),
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Center your face in the guide to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 10. Poor Lighting
    FaceAttendanceStatus.poorLighting: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.poorLighting,
      tone: FaceGuidanceTone.warning,
      statusPillText: 'Low light',
      statusPillIcon: Icons.warning_amber_rounded,
      statusPillTextColor: FaceAttendanceTheme.warningAmberLight,
      guideText: 'Too dark',
      guideHint: 'Face a light source if possible.',
      stepIndex: 0,
      stepState: StepIndicatorState.current,
      alertTitle: 'Poor lighting',
      alertMessage: 'Move to a better-lit area.',
      alertType: AlertBannerType.warning,
      defaultMetrics: FaceDetectionMetrics(
        faceStatusLevel: MetricLevel.good,
        faceStatusText: '1 face',
        positionLevel: MetricLevel.good,
        positionText: 'Centered',
        lightingLevel: MetricLevel.bad,
        lightingText: 'Too dark',
        distanceLevel: MetricLevel.good,
        distanceText: 'Optimal',
        faceCount: 1,
      ),
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Improve lighting to continue.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // ── Liveness Challenge Active ─────────────────────────────────────────────
    FaceAttendanceStatus.livenessChallenge: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.livenessChallenge,
      tone: FaceGuidanceTone.active,
      statusPillText: 'Liveness Check',
      statusPillIcon: Icons.motion_photos_on_outlined,
      statusPillTextColor: FaceAttendanceTheme.goldLight,
      guideText: 'Follow on-screen action',
      guideHint: 'Perform the action shown above.',
      stepIndex: 1,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.disabled,
      buttonLabel: 'Verifying Liveness…',
      buttonHint: 'Complete the 3 verification gestures.',
      buttonIcon: Icons.motion_photos_on,
    ),

    // ── Liveness Complete (Ready to Register or Auto-verify) ───────────────────
    FaceAttendanceStatus.livenessComplete: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.livenessComplete,
      tone: FaceGuidanceTone.success,
      statusPillText: 'Liveness confirmed',
      statusPillIcon: Icons.verified_user_outlined,
      statusPillTextColor: FaceAttendanceTheme.successGreenMuted,
      guideText: 'Liveness Confirmed!',
      guideHint: 'Tap Register Face Profile to complete setup.',
      stepIndex: 1,
      stepState: StepIndicatorState.done,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.enabled,
      buttonLabel: 'Register Face Profile',
      buttonHint: 'Tap to register your face securely.',
      buttonIcon: Icons.how_to_reg,
    ),

    // ── Registering Face Profile ──────────────────────────────────────────────
    FaceAttendanceStatus.registering: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.registering,
      tone: FaceGuidanceTone.scanning,
      statusPillText: 'Registering face',
      statusPillIcon: Icons.hourglass_empty_rounded,
      statusPillTextColor: FaceAttendanceTheme.goldLight,
      guideText: 'Saving face profile…',
      guideHint: 'Storing encrypted biometric template.',
      stepIndex: 1,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.verifying,
      buttonLabel: 'REGISTERING…',
      buttonHint: 'Registration in progress.',
      buttonIcon: Icons.how_to_reg,
    ),

    // ── Face Registered Success ───────────────────────────────────────────────
    FaceAttendanceStatus.faceRegistered: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.faceRegistered,
      tone: FaceGuidanceTone.success,
      statusPillText: 'Face Registered',
      statusPillIcon: Icons.check_circle_outline,
      statusPillTextColor: FaceAttendanceTheme.successGreenMuted,
      guideText: 'Registration Complete!',
      guideHint: 'Your face is now registered for future attendance.',
      stepIndex: 2,
      stepState: StepIndicatorState.done,
      alertTitle: 'Face Registered Successfully',
      alertMessage: 'Your face profile is saved. You can now use Face Attendance anytime.',
      alertType: AlertBannerType.info,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.completed,
      buttonLabel: 'Face Registered ✓',
      buttonHint: 'Registration successfully linked to your student ID.',
      buttonIcon: Icons.check_circle,
    ),

    // 11. Ready To Verify
    FaceAttendanceStatus.readyToVerify: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.readyToVerify,
      tone: FaceGuidanceTone.success,
      statusPillText: 'Ready to verify',
      statusPillIcon: Icons.check_circle_outline,
      statusPillTextColor: FaceAttendanceTheme.successGreenMuted,
      guideText: 'Perfect. Hold still.',
      guideHint: 'Tap Verify Attendance when ready.',
      stepIndex: 1,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.enabled,
      buttonLabel: 'Verify Attendance',
      buttonHint: 'Your face is positioned correctly.',
      buttonIcon: Icons.face_retouching_natural,
    ),

    // 12. Verifying
    FaceAttendanceStatus.verifying: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.verifying,
      tone: FaceGuidanceTone.scanning,
      statusPillText: 'Verifying',
      statusPillIcon: Icons.hourglass_empty_rounded,
      statusPillTextColor: FaceAttendanceTheme.goldLight,
      guideText: 'Verifying your identity…',
      guideHint: 'Keep still until verification completes.',
      stepIndex: 1,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.verifying,
      buttonLabel: 'VERIFYING…',
      buttonHint: 'Request in progress — additional taps are ignored.',
    ),

    // 13. Verified
    FaceAttendanceStatus.verified: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.verified,
      tone: FaceGuidanceTone.success,
      statusPillText: 'Identity verified',
      statusPillIcon: Icons.check_circle_outline,
      statusPillTextColor: FaceAttendanceTheme.successGreenMuted,
      guideText: 'Identity verified',
      guideHint: 'Recording your attendance…',
      stepIndex: 2,
      stepState: StepIndicatorState.current,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.completed,
      buttonLabel: 'Identity Verified',
      buttonHint: 'Recording attendance for this session.',
      buttonIcon: Icons.check,
    ),

    // 14. Verification Failed
    FaceAttendanceStatus.verificationFailed: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.verificationFailed,
      tone: FaceGuidanceTone.danger,
      statusPillText: 'Not verified',
      statusPillIcon: Icons.highlight_off,
      statusPillTextColor: FaceAttendanceTheme.dangerRedMuted,
      guideText: 'Verification failed',
      guideHint: 'Your face was detected but could not be matched.',
      stepIndex: 1,
      stepState: StepIndicatorState.error,
      alertTitle: 'Verification failed',
      alertMessage: 'Your identity could not be verified. Please try again.',
      alertType: AlertBannerType.danger,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.retry,
      buttonLabel: 'Try Again',
      buttonHint: 'Reposition your face, then verify again.',
      buttonIcon: Icons.refresh,
    ),

    // ── Unauthorized / Face Mismatch Error ────────────────────────────────────
    FaceAttendanceStatus.unauthorized: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.unauthorized,
      tone: FaceGuidanceTone.danger,
      statusPillText: 'Unauthorized',
      statusPillIcon: Icons.gpp_bad_outlined,
      statusPillTextColor: FaceAttendanceTheme.dangerRedMuted,
      guideText: 'Unauthorized Access',
      guideHint: 'Detected face does not match the registered student.',
      stepIndex: 1,
      stepState: StepIndicatorState.error,
      alertTitle: 'Unauthorized Face Detected',
      alertMessage: 'The detected face does not match the registered profile for this student account. Please use your own account or contact the warden.',
      alertType: AlertBannerType.danger,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.retry,
      buttonLabel: 'Try Again',
      buttonHint: 'Only the registered student can mark attendance.',
      buttonIcon: Icons.refresh,
    ),

    // 15. Attendance Marked (Success View is displayed)
    FaceAttendanceStatus.attendanceMarked: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.attendanceMarked,
      tone: FaceGuidanceTone.success,
      statusPillText: 'Attendance Marked',
      statusPillIcon: Icons.check_circle,
      statusPillTextColor: FaceAttendanceTheme.successGreenMuted,
      guideText: 'Attendance Recorded',
      guideHint: 'Your attendance has been confirmed.',
      stepIndex: 2,
      stepState: StepIndicatorState.done,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.completed,
      buttonLabel: 'Done',
      buttonHint: 'Return to dashboard.',
      buttonIcon: Icons.check,
    ),

    // 16. Permission Denied
    FaceAttendanceStatus.permissionDenied: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.permissionDenied,
      tone: FaceGuidanceTone.neutral,
      statusPillText: 'Permission needed',
      statusPillIcon: Icons.camera_alt_outlined,
      statusPillTextColor: FaceAttendanceTheme.creamLight,
      guideText: 'Camera Permission Denied',
      guideHint: 'Camera permission is required for face verification.',
      stepIndex: 0,
      stepState: StepIndicatorState.error,
      defaultMetrics: FaceDetectionMetrics.initial,
      buttonMode: ActionButtonMode.enabled,
      buttonLabel: 'Allow Camera Access',
      buttonHint: 'Tap to request camera access.',
      buttonIcon: Icons.camera_alt,
    ),

    // 17. Permission Permanently Denied
    FaceAttendanceStatus.permissionPermanentlyDenied: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.permissionPermanentlyDenied,
      tone: FaceGuidanceTone.neutral,
      statusPillText: 'Access disabled',
      statusPillIcon: Icons.no_photography_outlined,
      statusPillTextColor: FaceAttendanceTheme.creamLight,
      guideText: 'Camera Access Disabled',
      guideHint: 'Camera access is disabled. Open device settings to enable camera permission.',
      stepIndex: 0,
      stepState: StepIndicatorState.error,
      defaultMetrics: FaceDetectionMetrics.initial,
      buttonMode: ActionButtonMode.enabled,
      buttonLabel: 'Open Settings',
      buttonHint: 'Open system settings to allow camera access.',
      buttonIcon: Icons.settings,
    ),

    // 18. Network Error
    FaceAttendanceStatus.networkError: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.networkError,
      tone: FaceGuidanceTone.neutral,
      statusPillText: 'Connection problem',
      statusPillIcon: Icons.wifi_off_rounded,
      statusPillTextColor: FaceAttendanceTheme.creamLight,
      guideText: 'Connection problem',
      guideHint: 'Your face was captured, but the server could not be reached.',
      stepIndex: 1,
      stepState: StepIndicatorState.error,
      alertTitle: 'Unable to connect',
      alertMessage: 'Unable to connect to the attendance server. Check your internet connection and try again.',
      alertType: AlertBannerType.danger,
      defaultMetrics: FaceDetectionMetrics.allGood,
      buttonMode: ActionButtonMode.retry,
      buttonLabel: 'Retry',
      buttonHint: 'Check your connection before retrying.',
      buttonIcon: Icons.refresh,
    ),

    // 19. Duplicate Attendance
    FaceAttendanceStatus.duplicate: const FaceAttendanceStateConfig(
      status: FaceAttendanceStatus.duplicate,
      tone: FaceGuidanceTone.active,
      statusPillText: 'Already recorded',
      statusPillIcon: Icons.check_circle_outline,
      statusPillTextColor: FaceAttendanceTheme.goldLight,
      guideText: 'Already recorded',
      guideHint: 'No further action is needed for this session.',
      stepIndex: 2,
      stepState: StepIndicatorState.done,
      alertTitle: 'Attendance already recorded',
      alertMessage: 'Attendance has already been recorded for this session.',
      alertType: AlertBannerType.info,
      defaultMetrics: FaceDetectionMetrics.notRequired,
      buttonMode: ActionButtonMode.completed,
      buttonLabel: 'Already Recorded',
      buttonHint: 'You can mark attendance again in the next session.',
      buttonIcon: Icons.verified_outlined,
    ),
  };

  static FaceAttendanceStateConfig getConfig(FaceAttendanceStatus status) {
    return configs[status] ?? configs[FaceAttendanceStatus.cameraReady]!;
  }
}
