import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../theme/face_attendance_theme.dart';

/// Primary action button for face verification workflow
class AttendanceActionButton extends StatefulWidget {
  final ActionButtonMode mode;
  final String label;
  final String hint;
  final IconData? icon;
  final VoidCallback? onPressed;

  const AttendanceActionButton({
    super.key,
    required this.mode,
    required this.label,
    required this.hint,
    this.icon,
    this.onPressed,
  });

  @override
  State<AttendanceActionButton> createState() => _AttendanceActionButtonState();
}

class _AttendanceActionButtonState extends State<AttendanceActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.mode == ActionButtonMode.enabled ||
        widget.mode == ActionButtonMode.retry;
    final bool isVerifying = widget.mode == ActionButtonMode.verifying;
    final bool isCompleted = widget.mode == ActionButtonMode.completed;

    // Gradient & Styling selection
    Gradient buttonGradient;
    Color borderColor;
    Color textColor;
    List<BoxShadow> shadows;

    if (isCompleted) {
      buttonGradient = FaceAttendanceTheme.glossyGreenGradient;
      borderColor = FaceAttendanceTheme.successGreen;
      textColor = Colors.white;
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          offset: const Offset(0, 2),
          blurRadius: 6,
        ),
      ];
    } else if (isEnabled) {
      buttonGradient = _isPressed
          ? FaceAttendanceTheme.glossyGoldButtonPressed
          : FaceAttendanceTheme.glossyGoldButton;
      borderColor = FaceAttendanceTheme.goldBorder;
      textColor = FaceAttendanceTheme.textOnGold;
      shadows = _isPressed
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                offset: const Offset(0, 1),
                blurRadius: 2,
              ),
            ]
          : FaceAttendanceTheme.goldButtonShadow;
    } else {
      // Disabled / Verifying
      buttonGradient = FaceAttendanceTheme.glossyGoldButton;
      borderColor = FaceAttendanceTheme.goldBorder.withValues(alpha: 0.6);
      textColor = FaceAttendanceTheme.textOnGold.withValues(alpha: isVerifying ? 1.0 : 0.6);
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ];
    }

    final double buttonOpacity = (widget.mode == ActionButtonMode.disabled) ? 0.55 : 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: isEnabled,
          label: '${widget.label}. ${widget.hint}',
          child: Opacity(
            opacity: buttonOpacity,
            child: GestureDetector(
              onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
              onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
              onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
              onTap: isEnabled ? widget.onPressed : null,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusButton),
                  gradient: buttonGradient,
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: shadows,
                ),
                child: Stack(
                  children: [
                    // Inner top highlight line (50% white)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 1.2,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(FaceAttendanceTheme.radiusButton),
                            topRight: Radius.circular(FaceAttendanceTheme.radiusButton),
                          ),
                          color: Colors.white.withValues(alpha: 0.50),
                        ),
                      ),
                    ),

                    // Inner bottom shadow (20% black)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 1.2,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(FaceAttendanceTheme.radiusButton),
                            bottomRight: Radius.circular(FaceAttendanceTheme.radiusButton),
                          ),
                          color: Colors.black.withValues(alpha: 0.20),
                        ),
                      ),
                    ),

                    // Centered Content (Icon + Label or Spinner)
                    Center(
                      child: isVerifying
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      FaceAttendanceTheme.textOnGold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'VERIFYING…',
                                  style: FaceAttendanceTheme.buttonText.copyWith(
                                    color: textColor,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (widget.icon != null) ...[
                                  Icon(widget.icon, color: textColor, size: 20),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  widget.label.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    color: textColor,
                                    fontFamily: 'Lato',
                                    shadows: [
                                      if (!isCompleted)
                                        Shadow(
                                          color: Colors.white.withValues(alpha: 0.30),
                                          offset: const Offset(0, 1),
                                          blurRadius: 0,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Hint Line under Button
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.mode == ActionButtonMode.disabled)
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.lock_outline, size: 13, color: FaceAttendanceTheme.textSecondary),
              )
            else if (widget.mode == ActionButtonMode.verifying)
              const Padding(
                padding: EdgeInsets.only(right: 5),
                child: Icon(Icons.security, size: 13, color: FaceAttendanceTheme.goldDarker),
              ),
            Flexible(
              child: Text(
                widget.hint,
                textAlign: TextAlign.center,
                style: FaceAttendanceTheme.supportingText.copyWith(
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
