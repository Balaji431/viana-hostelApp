import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../models/face_attendance_state_config.dart';
import '../theme/face_attendance_theme.dart';
import 'attendance_action_button.dart';

/// Permission view replacing the camera frame when camera access is denied or disabled
class CameraPermissionView extends StatelessWidget {
  final FaceAttendanceStatus status;
  final FaceAttendanceStateConfig config;
  final VoidCallback onRequestPermission;
  final VoidCallback onBackToHome;

  const CameraPermissionView({
    super.key,
    required this.status,
    required this.config,
    required this.onRequestPermission,
    required this.onBackToHome,
  });

  @override
  Widget build(BuildContext context) {
    final bool isPermanentlyDenied =
        status == FaceAttendanceStatus.permissionPermanentlyDenied;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Navy/Gold Frame Shell with 3:4 Aspect Ratio
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusOuterCamera),
              gradient: FaceAttendanceTheme.outerCameraFrame,
              border: Border.all(
                color: FaceAttendanceTheme.navyDeep,
                width: 1.5,
              ),
              boxShadow: FaceAttendanceTheme.cameraOuterShadow,
            ),
            padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusGoldBezel),
              gradient: FaceAttendanceTheme.goldBezel,
            ),
            padding: const EdgeInsets.all(3.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusInnerPreview),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        FaceAttendanceTheme.navyDark,
                        FaceAttendanceTheme.navyBlack,
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 64px Cream Circle with Camera-Off Icon
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                FaceAttendanceTheme.creamLight,
                                FaceAttendanceTheme.creamDark,
                              ],
                            ),
                            border: Border.all(color: const Color(0xFFB0A090), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.no_photography_outlined,
                            color: FaceAttendanceTheme.navyDark,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Title
                        Text(
                          config.guideText,
                          textAlign: TextAlign.center,
                          style: FaceAttendanceTheme.permissionTitle,
                        ),
                        const SizedBox(height: 8),

                        // Message (constrained to max width ~260)
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            config.guideHint,
                            textAlign: TextAlign.center,
                            style: FaceAttendanceTheme.bodyText.copyWith(
                              color: FaceAttendanceTheme.textOnNavyLight,
                              fontSize: 13.5,
                            ),
                          ),
                        ),

                        // Numbered Steps (Permanently Denied only)
                        if (isPermanentlyDenied) ...[
                          const SizedBox(height: 18),
                          _buildNumberedStep('1', 'Open device Settings'),
                          const SizedBox(height: 8),
                          _buildNumberedStep('2', 'Find VianaStay'),
                          const SizedBox(height: 8),
                          _buildNumberedStep('3', 'Allow Camera'),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Action Gold Button
        AttendanceActionButton(
          mode: ActionButtonMode.enabled,
          label: config.buttonLabel,
          hint: config.buttonHint,
          icon: config.buttonIcon,
          onPressed: onRequestPermission,
        ),
        const SizedBox(height: 10),

        // 3. Grey Glossy "Back to Home" Button
        _buildGreyBackButton(onBackToHome),
      ],
    ),
  );
  }

  Widget _buildNumberedStep(String number, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: FaceAttendanceTheme.glossyGoldButton,
            border: Border.all(color: FaceAttendanceTheme.goldBorder, width: 1.0),
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: FaceAttendanceTheme.textOnGold,
              fontFamily: 'Lato',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FaceAttendanceTheme.textOnNavyLight,
              fontFamily: 'Lato',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGreyBackButton(VoidCallback onTap) {
    return Semantics(
      button: true,
      label: 'Back to Home',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusButton),
            gradient: FaceAttendanceTheme.glossyGreyButton,
            border: Border.all(color: const Color(0xFF999999), width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                offset: const Offset(0, 1),
                blurRadius: 3,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Text(
            'BACK TO HOME',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Color(0xFF333333),
              fontFamily: 'Lato',
            ),
          ),
        ),
      ),
    );
  }
}
