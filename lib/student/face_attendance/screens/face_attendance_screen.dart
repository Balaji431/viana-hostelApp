import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/styles.dart';
import '../../../shared/user_provider.dart';
import '../../../shared/widgets/skeuomorphic_navbar.dart';
import '../controllers/face_attendance_controller.dart';
import '../models/face_attendance_models.dart';
import '../models/face_attendance_state_config.dart';
import '../theme/face_attendance_theme.dart';
import '../widgets/attendance_action_button.dart';
import '../widgets/attendance_alert_banner.dart';
import '../widgets/attendance_progress_steps.dart';
import '../widgets/attendance_student_card.dart';
import '../widgets/attendance_success_view.dart';
import '../widgets/camera_permission_view.dart';
import '../widgets/face_camera_frame.dart';
import '../widgets/verification_status_card.dart';

/// Full Face Attendance Screen conforming pixel-faithfully to the VianaStay design language
class FaceAttendanceScreen extends StatefulWidget {
  final FaceAttendanceController? controller;
  final FaceScanMode initialMode;

  const FaceAttendanceScreen({
    super.key,
    this.controller,
    this.initialMode = FaceScanMode.punch,
  });

  @override
  State<FaceAttendanceScreen> createState() => _FaceAttendanceScreenState();
}

class _FaceAttendanceScreenState extends State<FaceAttendanceScreen>
    with WidgetsBindingObserver {
  late FaceAttendanceController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = FaceAttendanceController(initialMode: widget.initialMode);
      _ownsController = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Provider.of<UserProvider>(context, listen: false);
      _controller.setStudentInfo(
        username: user.username,
        name: user.userName,
        registerNumber: user.registerNo.isNotEmpty
            ? user.registerNo
            : (user.studentId.isNotEmpty ? user.studentId : user.username),
      );
    });

    _controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controller.detectionService.pause();
    } else if (state == AppLifecycleState.resumed) {
      _controller.detectionService.resume(
        onStatusChanged: _controller.onDetectionUpdate,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleBackNavigation(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<FaceAttendanceController>.value(
      value: _controller,
      child: Consumer<FaceAttendanceController>(
        builder: (context, controller, child) {
          final config = controller.currentConfig;
          final status = controller.status;
          final isSuccess = (status == FaceAttendanceStatus.attendanceMarked ||
                  status == FaceAttendanceStatus.faceRegistered) &&
              controller.recordResult != null;
          final isPermissionState =
              status == FaceAttendanceStatus.permissionDenied ||
                  status == FaceAttendanceStatus.permissionPermanentlyDenied;

          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: SkeuomorphicNavBar(
              title: controller.mode == FaceScanMode.registration
                  ? 'Face Registration'
                  : 'Face Biometric',
              gradient: FaceAttendanceTheme.glossyNavBar,
              onBack: () => _handleBackNavigation(context),
            ),
            body: LinenGridBackground(
              child: SafeArea(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        // B) Navy Header Band with Mode Switcher
                        _buildNavyHeaderBand(controller, config),

                        // C) Body Content (Responsive Layout)
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16.0),
                            physics: const BouncingScrollPhysics(),
                            child: Center(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final double width = constraints.maxWidth;

                                  if (isSuccess) {
                                    return ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 440),
                                      child: Column(
                                        children: [
                                          AttendanceSuccessView(
                                            record: controller.recordResult!,
                                            onDone: () => _handleBackNavigation(context),
                                            onProceedToCheckIn: () {
                                              controller.setScanMode(FaceScanMode.punch);
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          _buildPrivacyNote(),
                                          const SizedBox(height: 24),
                                        ],
                                      ),
                                    );
                                  }

                                  if (isPermissionState) {
                                    return ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 420),
                                      child: Column(
                                        children: [
                                          CameraPermissionView(
                                            status: status,
                                            config: config,
                                            onRequestPermission: () =>
                                                controller.requestCameraPermission(),
                                            onBackToHome: () =>
                                                _handleBackNavigation(context),
                                          ),
                                          const SizedBox(height: 16),
                                          _buildPrivacyNote(),
                                          const SizedBox(height: 24),
                                        ],
                                      ),
                                    );
                                  }

                                  // Standard Interactive Attendance Flow
                                  if (width >= 900) {
                                    return _buildDesktopLayout(context, controller, config);
                                  } else if (width >= 600) {
                                    return _buildTabletLayout(context, controller, config);
                                  } else {
                                    return _buildMobileLayout(context, controller, config);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Color Flash Overlay (Server-triggered liveness check)
                    if (controller.activeFlashColor != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            color: controller.activeFlashColor!.withValues(alpha: 0.92),
                          ),
                        ),
                      ),

                    // Developer State Switcher (Dev Mode Only)
                    if (kDebugMode)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: _buildDebugStateButton(context, controller),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Navy Header Band with Mode Switch Segment, Session Eyebrow, Title, and 3-step progress tracker
  Widget _buildNavyHeaderBand(
    FaceAttendanceController controller,
    FaceAttendanceStateConfig config,
  ) {
    final session = controller.sessionInfo;
    final isRegMode = controller.mode == FaceScanMode.registration;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: FaceAttendanceTheme.navyHeaderBand,
        border: Border(
          bottom: BorderSide(
            color: FaceAttendanceTheme.navyDeep,
            width: 1.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Registration status banner for students who are not yet enrolled
          if (!controller.isRegistered)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Face Not Enrolled: Please visit your Floor Warden to complete biometric registration.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFDE68A),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Eyebrow
          Text(
            'TODAY · ${session.sessionName.toUpperCase()}',
            style: FaceAttendanceTheme.eyebrowLabel,
          ),
          const SizedBox(height: 4),

          // Title
          Text(
            isRegMode ? 'Face Biometric Registration' : 'Mark Biometric Attendance',
            style: FaceAttendanceTheme.pageTitle,
          ),
          const SizedBox(height: 2),

          // Subtitle
          Text(
            isRegMode
                ? 'Align your face and follow the liveness checks to register your face.'
                : (controller.todayPunchSummary?.hasCheckIn == true
                    ? 'Check-In recorded at ${controller.todayPunchSummary?.checkInTime ?? ""}. Next scan will record Check-Out.'
                    : 'First scan of today records your Check-In time.'),
            style: FaceAttendanceTheme.bodyText.copyWith(
              color: FaceAttendanceTheme.textOnNavyLight,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 14),

          // 3-Step Progress Tracker
          AttendanceProgressSteps(
            currentStep: config.stepIndex,
            stepState: config.stepState,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraFrameWidget(
    FaceAttendanceController controller,
    FaceAttendanceStateConfig config,
  ) {
    return FaceCameraFrame(
      cameraController: controller.detectionService.controller,
      isSimulated: controller.detectionService.isSimulated,
      status: controller.status,
      config: config,
      currentChallenge: controller.currentChallenge,
      challengeIndex: controller.currentChallengeIndex,
      challengesDone: controller.challengesDone,
      challenges: controller.challenges,
    );
  }

  Widget _buildErrorBannerWithActions(
    BuildContext context,
    FaceAttendanceController controller,
  ) {
    final errMsg = controller.customErrorMessage ?? '';
    final isNotRegistered = errMsg.toLowerCase().contains('register') || errMsg.toLowerCase().contains('not found');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF87171), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Check-In Notice',
                  style: TextStyle(
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            errMsg,
            style: const TextStyle(
              color: Color(0xFF7F1D1D),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (isNotRegistered) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2F5E).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.how_to_reg_rounded, size: 16, color: Color(0xFFD4AF37)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please meet your assigned floor warden to enroll your face.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A2744),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Mobile Layout (<600px): Single Column Stack (max width 400)
  Widget _buildMobileLayout(
    BuildContext context,
    FaceAttendanceController controller,
    FaceAttendanceStateConfig config,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Camera Frame Hero
          _buildCameraFrameWidget(controller, config),
          const SizedBox(height: 14),

          // 2. Alert Banner (if state has one or server error)
          if (controller.customErrorMessage != null) ...[
            _buildErrorBannerWithActions(context, controller),
            const SizedBox(height: 14),
          ] else if (config.alertTitle != null && config.alertMessage != null) ...[
            AttendanceAlertBanner(
              title: config.alertTitle!,
              message: config.alertMessage!,
              type: config.alertType ?? AlertBannerType.warning,
            ),
            const SizedBox(height: 14),
          ],

          // 3. Primary Action Button + Hint
          _buildActionButton(context, controller, config),
          const SizedBox(height: 16),

          // 4. Verification Status Card
          VerificationStatusCard(
            stepIndex: config.stepIndex,
            metrics: controller.metrics,
          ),
          const SizedBox(height: 14),

          // 5. Student Information Card
          AttendanceStudentCard(
            sessionInfo: controller.sessionInfo,
          ),
          const SizedBox(height: 16),

          // 6. Privacy Note
          _buildPrivacyNote(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Tablet Layout (600 - 900px): Centered Camera (max 420), side-by-side cards (max 540)
  Widget _buildTabletLayout(
    BuildContext context,
    FaceAttendanceController controller,
    FaceAttendanceStateConfig config,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _buildCameraFrameWidget(controller, config),
          ),
          const SizedBox(height: 14),

          if (controller.customErrorMessage != null) ...[
            _buildErrorBannerWithActions(context, controller),
            const SizedBox(height: 14),
          ] else if (config.alertTitle != null && config.alertMessage != null) ...[
            AttendanceAlertBanner(
              title: config.alertTitle!,
              message: config.alertMessage!,
              type: config.alertType ?? AlertBannerType.warning,
            ),
            const SizedBox(height: 14),
          ],

          _buildActionButton(context, controller, config),
          const SizedBox(height: 18),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: VerificationStatusCard(
                  stepIndex: config.stepIndex,
                  metrics: controller.metrics,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: AttendanceStudentCard(
                  sessionInfo: controller.sessionInfo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          _buildPrivacyNote(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// Desktop / Web Layout (>=900px): 2 Columns
  Widget _buildDesktopLayout(
    BuildContext context,
    FaceAttendanceController controller,
    FaceAttendanceStateConfig config,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _buildCameraFrameWidget(controller, config),
                const SizedBox(height: 16),
                _buildPrivacyNote(),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.customErrorMessage != null) ...[
                  _buildErrorBannerWithActions(context, controller),
                  const SizedBox(height: 14),
                ] else if (config.alertTitle != null && config.alertMessage != null) ...[
                  AttendanceAlertBanner(
                    title: config.alertTitle!,
                    message: config.alertMessage!,
                    type: config.alertType ?? AlertBannerType.warning,
                  ),
                  const SizedBox(height: 14),
                ],

                _buildActionButton(context, controller, config),
                const SizedBox(height: 16),

                VerificationStatusCard(
                  stepIndex: config.stepIndex,
                  metrics: controller.metrics,
                ),
                const SizedBox(height: 14),

                AttendanceStudentCard(
                  sessionInfo: controller.sessionInfo,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    FaceAttendanceController controller,
    FaceAttendanceStateConfig config,
  ) {
    final user = Provider.of<UserProvider>(context, listen: false);
    final studentName = user.userName.isNotEmpty
        ? user.userName
        : 'Resident Student';
    final registerNumber = user.registerNo.isNotEmpty
        ? user.registerNo
        : (user.studentId.isNotEmpty ? user.studentId : (user.username.isNotEmpty ? user.username : 'STU-2026-001'));

    return AttendanceActionButton(
      mode: config.buttonMode,
      label: controller.mode == FaceScanMode.registration && config.buttonMode == ActionButtonMode.enabled
          ? 'REGISTER FACE'
          : config.buttonLabel,
      hint: config.buttonHint,
      icon: config.buttonIcon,
      onPressed: () {
        if (config.buttonMode == ActionButtonMode.retry) {
          controller.retry();
        } else if (controller.mode == FaceScanMode.registration ||
            (controller.status == FaceAttendanceStatus.livenessComplete && !controller.isRegistered)) {
          controller.registerFace(
            studentUsername: user.username,
            studentName: studentName,
            registerNumber: registerNumber,
          );
        } else if (config.buttonMode == ActionButtonMode.enabled) {
          controller.verifyAttendance(
            studentUsername: user.username,
            studentName: studentName,
            registerNumber: registerNumber,
          );
        }
      },
    );
  }

  Widget _buildPrivacyNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.shield_outlined, size: 14, color: FaceAttendanceTheme.goldDarker),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Face verification is encrypted and used solely for attendance authentication.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: FaceAttendanceTheme.textMuted,
              fontFamily: 'Lato',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebugStateButton(
    BuildContext context,
    FaceAttendanceController controller,
  ) {
    return PopupMenuButton<FaceAttendanceStatus>(
      tooltip: 'Preview Face Attendance States (Dev Mode)',
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: FaceAttendanceTheme.navyDark.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          border: Border.all(color: FaceAttendanceTheme.goldPrimary, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.tune_rounded, color: FaceAttendanceTheme.goldPrimary, size: 20),
      ),
      onSelected: (selectedStatus) {
        controller.setDebugState(selectedStatus);
      },
      itemBuilder: (context) {
        return FaceAttendanceStatus.values.map((status) {
          return PopupMenuItem<FaceAttendanceStatus>(
            value: status,
            child: Row(
              children: [
                Icon(
                  controller.status == status ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 14,
                  color: controller.status == status ? FaceAttendanceTheme.goldPrimary : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  status.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: controller.status == status ? FontWeight.bold : FontWeight.normal,
                    color: controller.status == status ? FaceAttendanceTheme.goldPrimary : const Color(0xFF1A2744),
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}
