import 'package:flutter/material.dart';
import '../models/face_attendance_models.dart';
import '../theme/face_attendance_theme.dart';

/// 3-step progress tracker: "Position" -> "Verify" -> "Result"
class AttendanceProgressSteps extends StatelessWidget {
  final int currentStep; // 0, 1, 2
  final StepIndicatorState stepState;

  const AttendanceProgressSteps({
    super.key,
    required this.currentStep,
    required this.stepState,
  });

  static const List<String> _stepLabels = [
    'Position',
    'Verify',
    'Result',
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${currentStep + 1} of 3: ${_stepLabels[currentStep]} (${_getAccessibilityStatus(currentStep)})',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isVeryNarrow = constraints.maxWidth < 340;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < 3; i++) ...[
                _buildStepItem(i, isVeryNarrow),
                if (i < 2) _buildConnector(i, isVeryNarrow),
              ],
            ],
          );
        },
      ),
    );
  }

  String _getAccessibilityStatus(int index) {
    if (index < currentStep) return 'complete';
    if (index == currentStep) {
      if (stepState == StepIndicatorState.error) return 'needs attention';
      if (stepState == StepIndicatorState.done) return 'complete';
      return 'current';
    }
    return 'upcoming';
  }

  Widget _buildStepItem(int index, bool isNarrow) {
    final bool isPast = index < currentStep || (index == currentStep && stepState == StepIndicatorState.done);
    final bool isCurrent = index == currentStep && stepState != StepIndicatorState.done;
    final bool isError = index == currentStep && stepState == StepIndicatorState.error;

    Decoration circleDecoration;
    Widget circleChild;

    if (isPast) {
      circleDecoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: FaceAttendanceTheme.glossyGreenGradient,
        border: Border.all(color: FaceAttendanceTheme.successGreen, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      );
      circleChild = const Icon(Icons.check, color: Colors.white, size: 13);
    } else if (isError) {
      circleDecoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            FaceAttendanceTheme.dangerRedLight,
            FaceAttendanceTheme.dangerRed,
          ],
        ),
        border: Border.all(color: FaceAttendanceTheme.dangerRed, width: 1.0),
      );
      circleChild = const Icon(Icons.close, color: Colors.white, size: 13);
    } else if (isCurrent) {
      circleDecoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: FaceAttendanceTheme.glossyGoldButton,
        border: Border.all(color: FaceAttendanceTheme.goldBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      );
      circleChild = Text(
        '${index + 1}',
        style: const TextStyle(
          color: FaceAttendanceTheme.textOnGold,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lato',
        ),
      );
    } else {
      circleDecoration = BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1.0),
      );
      circleChild = Text(
        '${index + 1}',
        style: const TextStyle(
          color: FaceAttendanceTheme.textOnNavyDim,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lato',
        ),
      );
    }

    Color labelColor;
    if (isPast) {
      labelColor = FaceAttendanceTheme.successGreenMuted;
    } else if (isCurrent) {
      labelColor = Colors.white;
    } else if (isError) {
      labelColor = FaceAttendanceTheme.dangerRedMuted;
    } else {
      labelColor = FaceAttendanceTheme.textOnNavyDim;
    }

    final bool showLabel = !isNarrow || isCurrent;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: circleDecoration,
          alignment: Alignment.center,
          child: circleChild,
        ),
        if (showLabel) ...[
          const SizedBox(width: 5),
          Text(
            _stepLabels[index],
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
              color: labelColor,
              fontFamily: 'Lato',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConnector(int stepIndex, bool isNarrow) {
    final bool isCompleted = stepIndex < currentStep;

    return Container(
      width: isNarrow ? 12 : 18,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isCompleted
          ? FaceAttendanceTheme.successGreenLight
          : Colors.white.withValues(alpha: 0.20),
    );
  }
}
