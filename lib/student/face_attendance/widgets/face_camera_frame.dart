import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../models/face_attendance_state_config.dart';
import '../theme/face_attendance_theme.dart';

/// Hero component: Camera frame with luxury navy frame, gold bezel,
/// CustomPainter face guide oval, corner brackets, laser scan line, and status pills.
class FaceCameraFrame extends StatefulWidget {
  final CameraController? cameraController;
  final bool isSimulated;
  final FaceAttendanceStatus status;
  final FaceAttendanceStateConfig config;
  final LivenessChallenge? currentChallenge;
  final int challengeIndex;
  final List<bool> challengesDone;
  final List<LivenessChallenge> challenges;

  const FaceCameraFrame({
    super.key,
    required this.cameraController,
    required this.isSimulated,
    required this.status,
    required this.config,
    this.currentChallenge,
    this.challengeIndex = 0,
    this.challengesDone = const [],
    this.challenges = const [],
  });

  @override
  State<FaceCameraFrame> createState() => _FaceCameraFrameState();
}

class _FaceCameraFrameState extends State<FaceCameraFrame>
    with TickerProviderStateMixin {
  late AnimationController _scanController;
  late AnimationController _breatheController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // 1. Laser scanning line controller (2.4s top-to-bottom loop)
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // 2. Oval breathe controller (1.8s loop: 1.0 -> 0.55 -> 1.0)
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 3. Verified green pulse controller (400ms one-shot)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimationStates();
  }

  @override
  void didUpdateWidget(FaceCameraFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimationStates();
    }
  }

  void _updateAnimationStates() {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _scanController.stop();
      _breatheController.stop();
      _pulseController.stop();
      return;
    }

    // Scan line
    if (widget.status == FaceAttendanceStatus.verifying ||
        widget.status == FaceAttendanceStatus.registering) {
      if (!_scanController.isAnimating) {
        _scanController.repeat(reverse: true);
      }
    } else {
      _scanController.stop();
      _scanController.reset();
    }

    // Breathe
    if (widget.status == FaceAttendanceStatus.positioned ||
        widget.status == FaceAttendanceStatus.readyToVerify ||
        widget.status == FaceAttendanceStatus.livenessChallenge) {
      if (!_breatheController.isAnimating) {
        _breatheController.repeat(reverse: true);
      }
    } else {
      _breatheController.stop();
      _breatheController.value = 0.0;
    }

    // Verified single pulse
    if (widget.status == FaceAttendanceStatus.verified ||
        widget.status == FaceAttendanceStatus.faceRegistered) {
      _pulseController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _breatheController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;

    return Semantics(
      label: 'Face camera verification view. ${config.guideText}. ${config.guideHint}',
      liveRegion: true,
      child: Container(
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
          padding: const EdgeInsets.all(3.0), // 3px gold bezel
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusInnerPreview),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Camera Feed / Initializing Fallback
                  _buildCameraPreview(),

                  // 2. Custom Painter Overlay (Vignette, Oval, Corner Brackets, Laser Scan)
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _scanController,
                      _breatheController,
                      _pulseController,
                    ]),
                    builder: (context, child) {
                      final breatheOpacity = (widget.status == FaceAttendanceStatus.positioned ||
                              widget.status == FaceAttendanceStatus.readyToVerify ||
                              widget.status == FaceAttendanceStatus.livenessChallenge)
                          ? (1.0 - (_breatheController.value * 0.45)) // 1.0 -> 0.55
                          : 1.0;

                      return CustomPaint(
                        painter: _FaceGuidePainter(
                          tone: config.tone,
                          scanProgress: _scanController.value,
                          isScanning: widget.status == FaceAttendanceStatus.verifying ||
                              widget.status == FaceAttendanceStatus.registering,
                          breatheOpacity: breatheOpacity,
                          pulseValue: _pulseController.value,
                          isVerified: widget.status == FaceAttendanceStatus.verified ||
                              widget.status == FaceAttendanceStatus.faceRegistered,
                        ),
                      );
                    },
                  ),

                  // 3. Inner Highlight Bevel Overlay (White 18% border)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(FaceAttendanceTheme.radiusInnerPreview),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 4. Top-Left Status Pill
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _buildStatusPill(config),
                  ),

                  // 5. Top-Right "FRONT" Camera Pill
                  Positioned(
                    top: 14,
                    right: 14,
                    child: _buildCameraTypePill(),
                  ),

                  // 6. Liveness Challenge Indicator Badge
                  if (widget.status == FaceAttendanceStatus.livenessChallenge &&
                      widget.currentChallenge != null)
                    Positioned(
                      top: 54,
                      left: 16,
                      right: 16,
                      child: _buildLivenessBanner(),
                    ),

                  // 7. Bottom Dark Scrim with Guide Text + Lato Hint
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomGuide(config),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLivenessBanner() {
    final challenge = widget.currentChallenge!;
    final stepNum = (widget.challengeIndex + 1).clamp(1, 3);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: FaceAttendanceTheme.navyDark.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FaceAttendanceTheme.goldPrimary,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'ACTION $stepNum OF 3',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: FaceAttendanceTheme.goldLight,
                  fontFamily: 'Playfair',
                ),
              ),
              const SizedBox(width: 8),
              // 3 Mini step dots
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final isDone = i < widget.challengeIndex;
                  final isCurrent = i == widget.challengeIndex;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone
                          ? FaceAttendanceTheme.successGreenLight
                          : (isCurrent
                              ? FaceAttendanceTheme.goldPrimary
                              : Colors.white.withValues(alpha: 0.3)),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                challenge.iconEmoji,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 6),
              Text(
                challenge.instruction,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: 'Lato',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = widget.cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              FaceAttendanceTheme.navySurface,
              FaceAttendanceTheme.navyBlack,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(4),
                child: const CircularProgressIndicator(
                  strokeWidth: 3.0,
                  valueColor: AlwaysStoppedAnimation<Color>(FaceAttendanceTheme.goldPrimary),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Starting front camera…',
                style: FaceAttendanceTheme.supportingText.copyWith(
                  color: FaceAttendanceTheme.textOnNavyMedium,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final size = controller.value.previewSize;
    final double previewW = size != null ? size.height : 300;
    final double previewH = size != null ? size.width : 400;

    final previewWidget = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: previewW,
        height: previewH,
        child: CameraPreview(controller),
      ),
    );

    return ClipRect(
      child: previewWidget,
    );
  }

  Widget _buildStatusPill(FaceAttendanceStateConfig config) {
    Color borderColor;
    Color textColor = config.statusPillTextColor;

    switch (config.tone) {
      case FaceGuidanceTone.neutral:
        borderColor = FaceAttendanceTheme.goldLight.withValues(alpha: 0.75);
        break;
      case FaceGuidanceTone.active:
        borderColor = FaceAttendanceTheme.goldPrimary;
        break;
      case FaceGuidanceTone.success:
        borderColor = FaceAttendanceTheme.successGreenLight;
        break;
      case FaceGuidanceTone.warning:
        borderColor = FaceAttendanceTheme.warningAmberLight;
        break;
      case FaceGuidanceTone.danger:
        borderColor = FaceAttendanceTheme.dangerRedLight;
        break;
      case FaceGuidanceTone.scanning:
        borderColor = FaceAttendanceTheme.goldLight;
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Container(
        key: ValueKey('${config.status}_${config.statusPillText}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: FaceAttendanceTheme.navyBlack.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (config.buttonMode == ActionButtonMode.verifying)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(FaceAttendanceTheme.goldLight),
                ),
              )
            else
              Icon(config.statusPillIcon, color: textColor, size: 14),
            const SizedBox(width: 6),
            Text(
              config.statusPillText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textColor,
                fontFamily: 'Lato',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraTypePill() {
    final isBack = widget.cameraController?.description.lensDirection == CameraLensDirection.back;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: FaceAttendanceTheme.navyBlack.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isBack ? Icons.camera_rear : Icons.camera_front,
            color: isBack ? FaceAttendanceTheme.goldLight : FaceAttendanceTheme.textOnNavyMedium,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            isBack ? 'REAR' : 'FRONT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: isBack ? FaceAttendanceTheme.goldLight : FaceAttendanceTheme.textOnNavyMedium,
              fontFamily: 'Lato',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomGuide(FaceAttendanceStateConfig config) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            FaceAttendanceTheme.navyBlack.withValues(alpha: 0.92),
            FaceAttendanceTheme.navyBlack.withValues(alpha: 0.65),
            Colors.transparent,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Text(
              config.guideText,
              key: ValueKey(config.guideText),
              textAlign: TextAlign.center,
              style: FaceAttendanceTheme.cameraGuideText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            config.guideHint,
            key: ValueKey(config.guideHint),
            textAlign: TextAlign.center,
            style: FaceAttendanceTheme.guideHintText,
          ),
        ],
      ),
    );
  }
}

/// Custom painter rendering the face guide oval, 52% dark vignette,
/// corner brackets, and scanning laser line in a 300x400 normalized space.
class _FaceGuidePainter extends CustomPainter {
  final FaceGuidanceTone tone;
  final double scanProgress;
  final bool isScanning;
  final double breatheOpacity;
  final double pulseValue;
  final bool isVerified;

  _FaceGuidePainter({
    required this.tone,
    required this.scanProgress,
    required this.isScanning,
    required this.breatheOpacity,
    required this.pulseValue,
    required this.isVerified,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / 300.0;
    final double scaleY = size.height / 400.0;

    // Oval parameters in 300x400 space
    final Offset ovalCenter = Offset(150.0 * scaleX, 180.0 * scaleY);
    final double rx = 96.0 * scaleX;
    final double ry = 126.0 * scaleY;
    final Rect ovalRect = Rect.fromCenter(center: ovalCenter, width: rx * 2, height: ry * 2);

    // 1. Dark Vignette Cutout (52% opacity #0F1520)
    final Path backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path ovalPath = Path()..addOval(ovalRect);
    final Path vignettePath = Path.combine(PathOperation.difference, backgroundPath, ovalPath);

    final Paint vignettePaint = Paint()
      ..color = const Color(0xFF0F1520).withValues(alpha: 0.52)
      ..style = PaintingStyle.fill;
    canvas.drawPath(vignettePath, vignettePaint);

    // 2. Corner Brackets (28px arms, 2.5 stroke, gold #E8D48A @ 70%, inset 18px)
    final double inset = 18.0 * scaleX;
    final double arm = 28.0 * scaleX;
    final Paint bracketPaint = Paint()
      ..color = const Color(0xFFE8D48A).withValues(alpha: 0.70)
      ..strokeWidth = 2.5 * scaleX
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Top-Left
    canvas.drawLine(Offset(inset, inset + arm), Offset(inset, inset), bracketPaint);
    canvas.drawLine(Offset(inset, inset), Offset(inset + arm, inset), bracketPaint);

    // Top-Right
    canvas.drawLine(Offset(size.width - inset - arm, inset), Offset(size.width - inset, inset), bracketPaint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + arm), bracketPaint);

    // Bottom-Left
    canvas.drawLine(Offset(inset, size.height - inset - arm), Offset(inset, size.height - inset), bracketPaint);
    canvas.drawLine(Offset(inset, size.height - inset), Offset(inset + arm, size.height - inset), bracketPaint);

    // Bottom-Right
    canvas.drawLine(Offset(size.width - inset - arm, size.height - inset), Offset(size.width - inset, size.height - inset), bracketPaint);
    canvas.drawLine(Offset(size.width - inset, size.height - inset), Offset(size.width - inset, size.height - inset - arm), bracketPaint);

    // 3. Oval Stroke by Tone
    Color strokeColor;
    double strokeWidth = 3.0 * scaleX;
    bool isDashed = false;

    switch (tone) {
      case FaceGuidanceTone.neutral:
        strokeColor = const Color(0xFFE8D48A).withValues(alpha: 0.75 * breatheOpacity);
        strokeWidth = 2.0 * scaleX;
        isDashed = true;
        break;
      case FaceGuidanceTone.active:
        strokeColor = FaceAttendanceTheme.goldPrimary.withValues(alpha: breatheOpacity);
        strokeWidth = 3.0 * scaleX;
        break;
      case FaceGuidanceTone.success:
        strokeColor = FaceAttendanceTheme.successGreenLight.withValues(alpha: breatheOpacity);
        strokeWidth = 3.0 * scaleX;
        break;
      case FaceGuidanceTone.warning:
        strokeColor = FaceAttendanceTheme.warningAmberLight;
        strokeWidth = 3.0 * scaleX;
        break;
      case FaceGuidanceTone.danger:
        strokeColor = FaceAttendanceTheme.dangerRedLight;
        strokeWidth = 3.0 * scaleX;
        break;
      case FaceGuidanceTone.scanning:
        strokeColor = FaceAttendanceTheme.goldLight;
        strokeWidth = 3.0 * scaleX;
        break;
    }

    final Paint ovalPaint = Paint()
      ..color = strokeColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    if (isDashed) {
      _drawDashedOval(canvas, ovalRect, ovalPaint, 7.0 * scaleX, 7.0 * scaleX);
    } else {
      canvas.drawOval(ovalRect, ovalPaint);
    }

    // 4. Verified Pulse Ring (Scale 1.0 -> 1.12, fade out)
    if (isVerified && pulseValue > 0.0) {
      final double pulseScale = 1.0 + (pulseValue * 0.12);
      final double pulseOpacity = (1.0 - pulseValue).clamp(0.0, 1.0);
      final Rect pulseRect = Rect.fromCenter(
        center: ovalCenter,
        width: rx * 2 * pulseScale,
        height: ry * 2 * pulseScale,
      );
      final Paint pulsePaint = Paint()
        ..color = FaceAttendanceTheme.successGreenLight.withValues(alpha: pulseOpacity * 0.8)
        ..strokeWidth = 3.5 * scaleX
        ..style = PaintingStyle.stroke;
      canvas.drawOval(pulseRect, pulsePaint);
    }

    // 5. Laser Scanning Line (Clipped to Oval)
    if (isScanning) {
      canvas.save();
      canvas.clipPath(ovalPath);

      final double scanY = ovalRect.top + (ovalRect.height * scanProgress);

      // Gold Glow Band above scan line
      final Rect glowRect = Rect.fromLTWH(
        ovalRect.left,
        scanY - (36.0 * scaleY),
        ovalRect.width,
        36.0 * scaleY,
      );
      final Paint glowPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FaceAttendanceTheme.goldLight.withValues(alpha: 0.0),
            FaceAttendanceTheme.goldLight.withValues(alpha: 0.35),
          ],
        ).createShader(glowRect);
      canvas.drawRect(glowRect, glowPaint);

      // 2.5px Gold Laser Line
      final Paint laserPaint = Paint()
        ..color = FaceAttendanceTheme.goldLight
        ..strokeWidth = 2.5 * scaleX
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(ovalRect.left, scanY), Offset(ovalRect.right, scanY), laserPaint);

      canvas.restore();
    }
  }

  void _drawDashedOval(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double dashLength,
    double spaceLength,
  ) {
    final Path path = Path()..addOval(rect);
    final Path dashedPath = Path();
    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double nextDistance = math.min(distance + dashLength, metric.length);
        dashedPath.addPath(
          metric.extractPath(distance, nextDistance),
          Offset.zero,
        );
        distance += dashLength + spaceLength;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) {
    return oldDelegate.tone != tone ||
        oldDelegate.scanProgress != scanProgress ||
        oldDelegate.isScanning != isScanning ||
        oldDelegate.breatheOpacity != breatheOpacity ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.isVerified != isVerified;
  }
}
