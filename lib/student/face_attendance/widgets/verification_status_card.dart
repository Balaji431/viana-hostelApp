import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../theme/face_attendance_theme.dart';

/// Verification Status Card with 2x2 metric tiles
class VerificationStatusCard extends StatelessWidget {
  final int stepIndex; // 0: Detection, 1: Verification, 2: Attendance
  final FaceDetectionMetrics metrics;

  const VerificationStatusCard({
    super.key,
    required this.stepIndex,
    required this.metrics,
  });

  String _getStageChipText() {
    switch (stepIndex) {
      case 0:
        return 'Detection';
      case 1:
        return 'Verification';
      case 2:
      default:
        return 'Attendance';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusCard),
        gradient: FaceAttendanceTheme.cardGradient,
        border: Border.all(color: Colors.black.withValues(alpha: 0.15), width: 1.0),
        boxShadow: FaceAttendanceTheme.cardShadow,
      ),
      child: Stack(
        children: [
          // Inner top white highlight
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1.2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(FaceAttendanceTheme.radiusCard),
                  topRight: Radius.circular(FaceAttendanceTheme.radiusCard),
                ),
                color: Colors.white.withValues(alpha: 0.70),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Verification Status',
                        style: FaceAttendanceTheme.sectionTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FaceAttendanceTheme.creamLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: FaceAttendanceTheme.borderLight, width: 1.0),
                      ),
                      child: Text(
                        _getStageChipText().toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: FaceAttendanceTheme.goldBorder,
                          letterSpacing: 0.8,
                          fontFamily: 'Lato',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 2x2 Grid of Metric Tiles
                Row(
                  children: [
                    Expanded(
                      child: _buildTile(
                        label: 'Face Status',
                        icon: Icons.face_retouching_natural,
                        value: metrics.faceStatusText,
                        level: metrics.faceStatusLevel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTile(
                        label: 'Position',
                        icon: Icons.filter_center_focus,
                        value: metrics.positionText,
                        level: metrics.positionLevel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildTile(
                        label: 'Lighting',
                        icon: Icons.wb_sunny_outlined,
                        value: metrics.lightingText,
                        level: metrics.lightingLevel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTile(
                        label: 'Distance',
                        icon: Icons.straighten_outlined,
                        value: metrics.distanceText,
                        level: metrics.distanceLevel,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Footnote
                Text(
                  'Values appear only when reported by the detection layer.',
                  style: FaceAttendanceTheme.supportingText.copyWith(
                    fontSize: 11,
                    color: FaceAttendanceTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required String label,
    required IconData icon,
    required String value,
    required MetricLevel level,
  }) {
    IconData levelIcon;
    Color levelColor;

    switch (level) {
      case MetricLevel.good:
        levelIcon = Icons.check_circle;
        levelColor = FaceAttendanceTheme.successGreen;
        break;
      case MetricLevel.warn:
        levelIcon = Icons.warning_amber_rounded;
        levelColor = FaceAttendanceTheme.warningAmber;
        break;
      case MetricLevel.bad:
        levelIcon = Icons.cancel;
        levelColor = FaceAttendanceTheme.dangerRed;
        break;
      case MetricLevel.pending:
        levelIcon = Icons.remove;
        levelColor = FaceAttendanceTheme.textMuted;
        break;
    }

    final bool isPending = level == MetricLevel.pending;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusTile),
        gradient: FaceAttendanceTheme.tileGradient,
        border: Border.all(color: FaceAttendanceTheme.borderLight, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: FaceAttendanceTheme.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: FaceAttendanceTheme.tileLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(levelIcon, size: 15, color: levelColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isPending ? FaceAttendanceTheme.textMuted : FaceAttendanceTheme.navyDark,
                    fontFamily: 'Lato',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
