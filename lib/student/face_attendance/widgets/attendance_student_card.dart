import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/user_provider.dart';
import '../models/face_attendance_models.dart';
import '../theme/face_attendance_theme.dart';

/// Student Information Card displaying authenticated user details
class AttendanceStudentCard extends StatelessWidget {
  final AttendanceSessionInfo sessionInfo;

  const AttendanceStudentCard({
    super.key,
    required this.sessionInfo,
  });

  String _getInitials(String name) {
    if (name.isEmpty) return 'VS';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, mathMin(2, name.length)).toUpperCase();
  }

  int mathMin(int a, int b) => a < b ? a : b;

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context, listen: false);
    final studentName = user.userName.isNotEmpty
        ? user.userName
        : 'Resident Student';
    final registerNumber = user.registerNo.isNotEmpty
        ? user.registerNo
        : (user.studentId.isNotEmpty ? user.studentId : (user.username.isNotEmpty ? user.username : 'STU-2026-001'));
    final initials = _getInitials(studentName);

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
                        'Student Information',
                        style: FaceAttendanceTheme.sectionTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.lock_outline, size: 12, color: FaceAttendanceTheme.textMuted),
                        SizedBox(width: 4),
                        Text(
                          'Signed in',
                          style: TextStyle(
                            fontSize: 10,
                            color: FaceAttendanceTheme.textMuted,
                            fontFamily: 'Lato',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Avatar + Name Header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: FaceAttendanceTheme.glossyGoldButton,
                        border: Border.all(color: FaceAttendanceTheme.goldBorder, width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.20),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: FaceAttendanceTheme.textOnGold,
                          fontFamily: 'Playfair Display',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studentName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: FaceAttendanceTheme.navyDark,
                              fontFamily: 'Lato',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Resident student',
                            style: FaceAttendanceTheme.supportingText.copyWith(
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Details Tile
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusTile),
                    gradient: FaceAttendanceTheme.tileGradient,
                    border: Border.all(color: FaceAttendanceTheme.borderLight, width: 1.0),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow('Name', studentName),
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildInfoRow('Register Number', registerNumber),
                      const Divider(height: 1, color: FaceAttendanceTheme.borderLight),
                      _buildInfoRow(
                        'Attendance Session',
                        '${sessionInfo.sessionName} · ${sessionInfo.timeRange}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
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
          const SizedBox(width: 12),
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
}
