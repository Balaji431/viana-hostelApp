import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../theme/face_attendance_theme.dart';
import 'attendance_action_button.dart';

/// Full-screen success receipt view replacing the camera frame when attendance is marked or face is registered
class AttendanceSuccessView extends StatelessWidget {
  final AttendanceRecordResult record;
  final VoidCallback onDone;
  final VoidCallback? onProceedToCheckIn;

  const AttendanceSuccessView({
    super.key,
    required this.record,
    required this.onDone,
    this.onProceedToCheckIn,
  });

  @override
  Widget build(BuildContext context) {
    final isRegistration = record.punchType == 'REG';
    final isCheckIn = record.isCheckIn;

    String titleText = 'Attendance Marked Successfully';
    String subtitleText = 'Your attendance for ${record.sessionName} has been recorded.';

    if (isRegistration) {
      titleText = 'Face Biometric Registered! 🎉';
      subtitleText = 'Your face has been registered successfully. You can now check in anytime.';
    } else if (isCheckIn) {
      titleText = 'Check-In Confirmed! 🟢';
      subtitleText = 'Your morning/first check-in punch has been marked.';
    } else {
      titleText = 'Check-Out Confirmed! 🔵';
      subtitleText = 'Your check-out punch has been recorded as today\'s latest checkout time.';
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusCard),
        gradient: FaceAttendanceTheme.cardGradient,
        border: Border.all(color: Colors.black.withValues(alpha: 0.15), width: 1.0),
        boxShadow: FaceAttendanceTheme.cardShadow,
      ),
      child: Stack(
        children: [
          // Inner top highlight
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
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. 64px Medallion: 3px gold ring around icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: FaceAttendanceTheme.goldBezel,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3.0),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isRegistration
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFD4AF37), Color(0xFF996515)],
                            )
                          : FaceAttendanceTheme.glossyGreenGradient,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isRegistration ? Icons.face_retouching_natural : Icons.check_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Title & Subtitle
                Text(
                  titleText,
                  textAlign: TextAlign.center,
                  style: FaceAttendanceTheme.successTitle,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  textAlign: TextAlign.center,
                  style: FaceAttendanceTheme.bodyText.copyWith(
                    color: FaceAttendanceTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // 3. Receipt Details Tile
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusTile),
                    gradient: FaceAttendanceTheme.tileGradient,
                    border: Border.all(color: FaceAttendanceTheme.borderLight, width: 1.0),
                  ),
                  child: Column(
                    children: [
                      _buildReceiptRow('Student', record.studentName),
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildReceiptRow('Register Number', record.registerNumber),
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildReceiptRow('Date', record.dateFormatted),
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildReceiptRow('Punch Time', record.timeFormatted),
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildReceiptRow(
                        'Punch Type',
                        isRegistration
                            ? 'Face Registration'
                            : (isCheckIn ? 'Check-In (Punch IN)' : 'Check-Out (Punch OUT)'),
                      ),
                      if (record.firstCheckInTime != null && !isRegistration) ...[
                        const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                        _buildReceiptRow('First Check-In Today', record.firstCheckInTime!),
                      ],
                      if (record.lastCheckOutTime != null && !isRegistration && !isCheckIn) ...[
                        const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                        _buildReceiptRow('Last Check-Out Today', record.lastCheckOutTime!),
                      ],
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildStatusReceiptRow('Status', record.statusText),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 4. Reference ID (if provided by server)
                if (record.referenceId != null && record.referenceId!.isNotEmpty) ...[
                  Text(
                    'Reference ID ${record.referenceId}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: FaceAttendanceTheme.textMuted,
                      fontFamily: 'Lato',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Biometric attendance recorded with high-accuracy GNSS & PAD evidence.',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: FaceAttendanceTheme.textMuted.withValues(alpha: 0.8),
                      fontFamily: 'Lato',
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // 5. Action Buttons
                if (isRegistration && onProceedToCheckIn != null) ...[
                  AttendanceActionButton(
                    mode: ActionButtonMode.enabled,
                    label: 'PROCEED TO CHECK-IN',
                    hint: 'Your face is enrolled. Tap to perform your check-in.',
                    onPressed: onProceedToCheckIn,
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onDone,
                    child: const Text('Back to Home Dashboard', style: TextStyle(color: Color(0xFF1A2744), fontWeight: FontWeight.bold)),
                  ),
                ] else ...[
                  AttendanceActionButton(
                    mode: ActionButtonMode.enabled,
                    label: 'DONE',
                    hint: 'Return to dashboard.',
                    onPressed: onDone,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: FaceAttendanceTheme.supportingText.copyWith(
              fontSize: 13,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: FaceAttendanceTheme.rowValue,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusReceiptRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: FaceAttendanceTheme.supportingText.copyWith(
              fontSize: 13,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF81C784), width: 1),
            ),
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
                fontFamily: 'Lato',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
