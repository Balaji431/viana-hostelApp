import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../theme/face_attendance_theme.dart';

/// Alert message banner displaying warning, danger, or info state with animations
class AttendanceAlertBanner extends StatelessWidget {
  final String title;
  final String message;
  final AlertBannerType type;

  const AttendanceAlertBanner({
    super.key,
    required this.title,
    required this.message,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    Gradient gradient;
    Border border;
    IconData icon;
    Color iconColor;
    Color titleColor;
    Color messageColor;

    switch (type) {
      case AlertBannerType.warning:
        gradient = FaceAttendanceTheme.warningAlertGradient;
        border = Border.all(color: FaceAttendanceTheme.warningAmberLight, width: 1.0);
        icon = Icons.warning_amber_rounded;
        iconColor = FaceAttendanceTheme.warningAmber;
        titleColor = FaceAttendanceTheme.warningDarkText;
        messageColor = FaceAttendanceTheme.warningDarkText;
        break;
      case AlertBannerType.danger:
        gradient = FaceAttendanceTheme.dangerAlertGradient;
        border = Border.all(color: FaceAttendanceTheme.dangerRedMuted, width: 1.0);
        icon = Icons.cancel_outlined;
        iconColor = FaceAttendanceTheme.dangerRed;
        titleColor = FaceAttendanceTheme.dangerDarkText;
        messageColor = FaceAttendanceTheme.dangerDarkText;
        break;
      case AlertBannerType.info:
        gradient = FaceAttendanceTheme.infoAlertGradient;
        border = Border.all(color: FaceAttendanceTheme.goldPrimary, width: 1.0);
        icon = Icons.check_circle_outline;
        iconColor = FaceAttendanceTheme.goldDarker;
        titleColor = FaceAttendanceTheme.navyDark;
        messageColor = FaceAttendanceTheme.textSecondary;
        break;
    }

    return Semantics(
      label: '$title: $message',
      liveRegion: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusCard),
          gradient: gradient,
          border: border,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                      fontFamily: 'Lato',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                      color: messageColor,
                      fontFamily: 'Lato',
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
