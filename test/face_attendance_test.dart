import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vianasoft_stay/shared/user_provider.dart';
import 'package:vianasoft_stay/shared/wallpaper_provider.dart';
import 'package:vianasoft_stay/student/face_attendance/controllers/face_attendance_controller.dart';
import 'package:vianasoft_stay/student/face_attendance/models/face_attendance_models.dart';
import 'package:vianasoft_stay/student/face_attendance/models/face_attendance_state_config.dart';
import 'package:vianasoft_stay/student/face_attendance/repositories/face_attendance_repository.dart';
import 'package:vianasoft_stay/student/face_attendance/screens/face_attendance_screen.dart';
import 'package:vianasoft_stay/student/face_attendance/services/attendance_bootstrap_service.dart';
import 'package:vianasoft_stay/student/face_attendance/services/attendance_socket_service.dart';
import 'package:vianasoft_stay/student/face_attendance/widgets/attendance_action_button.dart';
import 'package:vianasoft_stay/student/face_attendance/widgets/attendance_alert_banner.dart';
import 'package:vianasoft_stay/student/face_attendance/widgets/attendance_progress_steps.dart';
import 'package:vianasoft_stay/student/face_attendance/widgets/attendance_student_card.dart';
import 'package:vianasoft_stay/student/face_attendance/widgets/attendance_success_view.dart';
import 'package:vianasoft_stay/student/face_attendance/widgets/verification_status_card.dart';

class FakeUserProvider extends ChangeNotifier implements UserProvider {
  @override
  String get userName => 'Balaji';
  @override
  String get username => 'STU-1001';
  @override
  String get registerNo => 'STU-1001';
  @override
  String get studentId => 'STU-1001';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFaceAttendanceRepository implements FaceAttendanceRepository {
  final Duration latency;
  final bool shouldFail;
  final bool isUnauthorized;
  final bool isNetworkError;
  final Set<String> _registeredUsers = {};

  MockFaceAttendanceRepository({
    this.latency = Duration.zero,
    this.shouldFail = false,
    bool isUnauthorized = false,
    bool isNetworkError = false,
    bool? forceUnauthorized,
    bool? forceNetworkError,
  }) : isUnauthorized = forceUnauthorized ?? isUnauthorized,
       isNetworkError = forceNetworkError ?? isNetworkError;

  @override
  Stream<LivenessChallengeData> get onLivenessChallenge => const Stream.empty();

  @override
  Stream<OperationResultEvent> get onOperationResult => const Stream.empty();

  @override
  Future<AttendanceSessionInfo> getCurrentSession() async {
    await Future.delayed(latency);
    return AttendanceSessionInfo.defaultEvening();
  }

  @override
  Future<bool> isFaceRegistered(String studentUsername) async {
    await Future.delayed(latency);
    return _registeredUsers.contains(studentUsername);
  }

  Future<void> registerFace({
    required String studentUsername,
    required String studentName,
    required String registerNumber,
  }) async {
    _registeredUsers.add(studentUsername);
  }

  @override
  Future<AttendanceAuthSession> bootstrapSession({required int bioId}) async {
    await Future.delayed(latency);
    return AttendanceAuthSession(
      accessToken: 'MOCK_TOKEN',
      expiresIn: 3600,
      tokenType: 'Bearer',
      faceEnrolled: _registeredUsers.contains(bioId.toString()),
      bioId: bioId,
      policy: const AttendancePolicy(),
    );
  }

  @override
  Future<void> connectSocket(String accessToken) async {}

  @override
  void startLivenessSession({
    required String requestId,
    required String purpose,
    String? wifiSsid,
    String? wifiBssid,
  }) {}

  @override
  Future<bool> sendLivenessFrame({
    required String requestId,
    required String challengeId,
    required String nonce,
    required String step,
    required String imageDataUrl,
  }) async => true;

  @override
  Future<AttendanceVerificationResult> verifyFastPunch({
    required String requestId,
    required String challengeId,
    required String nonce,
    required List<String> completedSteps,
    required String punchType,
    required String baseFaceImageUrl,
    required String? flashImageUrl,
    required String? actionImageUrl,
    required String studentName,
    required String registerNumber,
    required String sessionName,
  }) async {
    await Future.delayed(latency);
    if (isUnauthorized) {
      return const AttendanceVerificationResult(
        isSuccess: false,
        isUnauthorized: true,
        errorMessage: 'Face mismatch. Please register your face first.',
      );
    }
    if (isNetworkError) {
      return const AttendanceVerificationResult(
        isSuccess: false,
        isNetworkError: true,
        errorMessage: 'Network error occurred. Please retry.',
      );
    }
    if (shouldFail) {
      return const AttendanceVerificationResult(
        isSuccess: false,
        errorMessage: 'Verification failed.',
      );
    }

    return AttendanceVerificationResult(
      isSuccess: true,
      record: AttendanceRecordResult(
        studentName: studentName.isNotEmpty ? studentName : 'Resident Student',
        registerNumber: registerNumber.isNotEmpty ? registerNumber : 'SIMATS',
        dateFormatted: 'Today',
        timeFormatted: '8:00 PM',
        sessionName: sessionName,
        statusText: '✓ Present',
        referenceId: 'MOCK-REF-12345',
      ),
    );
  }

  @override
  Future<FaceRegistrationResult> completeEnrollment({
    required String requestId,
    required String challengeId,
    required String nonce,
    required List<String> completedSteps,
    required String baseFaceImageUrl,
    required String? flashImageUrl,
    required String? actionImageUrl,
  }) async {
    await Future.delayed(latency);
    return const FaceRegistrationResult(isSuccess: true);
  }

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Face Attendance State & Copy Configurations', () {
    test('Every FaceAttendanceStatus has a valid configuration mapping', () {
      for (final status in FaceAttendanceStatus.values) {
        final config = FaceAttendanceStateMap.getConfig(status);
        expect(config.status, equals(status));
        expect(config.statusPillText, isNotEmpty);
        expect(config.guideText, isNotEmpty);
        expect(config.guideHint, isNotEmpty);
        expect(config.stepIndex, inInclusiveRange(0, 2));
        expect(config.buttonLabel, isNotEmpty);
        expect(config.buttonHint, isNotEmpty);
      }
    });

    test('Permission states show VianaStay in instructions', () {
      final config = FaceAttendanceStateMap.getConfig(
        FaceAttendanceStatus.permissionPermanentlyDenied,
      );
      expect(config.guideText, equals('Camera Access Disabled'));
      expect(config.buttonLabel, equals('Open Settings'));
    });

    test('Duplicate state has correct copy and completed mode', () {
      final config = FaceAttendanceStateMap.getConfig(FaceAttendanceStatus.duplicate);
      expect(config.statusPillText, equals('Already recorded'));
      expect(config.buttonMode, equals(ActionButtonMode.completed));
      expect(config.buttonLabel, equals('Already Recorded'));
      expect(config.alertTitle, equals('Attendance already recorded'));
    });

    test('Unauthorized state has correct copy and danger banner', () {
      final config = FaceAttendanceStateMap.getConfig(FaceAttendanceStatus.unauthorized);
      expect(config.statusPillText, equals('Unauthorized'));
      expect(config.buttonMode, equals(ActionButtonMode.retry));
      expect(config.alertTitle, equals('Unauthorized Face Detected'));
      expect(config.alertType, equals(AlertBannerType.danger));
    });
  });

  group('FaceAttendanceController Logic & Liveness', () {
    late FaceAttendanceController controller;
    late MockFaceAttendanceRepository mockRepo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRepo = MockFaceAttendanceRepository(
        latency: const Duration(milliseconds: 50),
      );
      controller = FaceAttendanceController(repository: mockRepo);
    });

    tearDown(() {
      controller.dispose();
    });

    test('Initializes with default session and generates 3 liveness challenges', () async {
      await controller.initialize();
      expect(controller.sessionInfo.sessionName, equals('Evening Roll Call'));
      expect(controller.challenges.length, equals(3));
      expect(
        controller.status,
        isIn([
          FaceAttendanceStatus.initializing,
          FaceAttendanceStatus.cameraReady,
          FaceAttendanceStatus.noFace,
          FaceAttendanceStatus.positioned,
        ]),
      );
    });

    test('First-time student face registration flow', () async {
      controller.setStudentInfo(
        username: 'STU_NEW_01',
        name: 'New Student',
        registerNumber: 'REG-999',
      );
      await controller.initialize();
      expect(controller.isRegistered, isFalse);

      await controller.registerFace();
      expect(controller.isRegistered, isTrue);
      expect(controller.status, equals(FaceAttendanceStatus.faceRegistered));
      expect(controller.isSessionCompleted, isTrue);
    });

    test('Returning registered student verification succeeds', () async {
      controller.setStudentInfo(
        username: 'STU_RETURNING_01',
        name: 'Aravind Kumar',
        registerNumber: 'REG-9876',
      );
      await mockRepo.registerFace(
        studentUsername: 'STU_RETURNING_01',
        studentName: 'Aravind Kumar',
        registerNumber: 'REG-9876',
      );

      await controller.initialize();
      controller.setDebugState(FaceAttendanceStatus.positioned);
      expect(controller.status, equals(FaceAttendanceStatus.positioned));

      await controller.verifyAttendance(
        studentUsername: 'STU_RETURNING_01',
        studentName: 'Aravind Kumar',
        registerNumber: 'REG-9876',
      );

      expect(controller.isSessionCompleted, isTrue);
      expect(controller.status, equals(FaceAttendanceStatus.attendanceMarked));
      expect(controller.recordResult, isNotNull);
      expect(controller.recordResult!.studentName, equals('Aravind Kumar'));
      expect(controller.recordResult!.statusText, contains('Recorded'));
    });

    test('Unauthorized access triggers unauthorized status and error alert', () async {
      final unauthRepo = MockFaceAttendanceRepository(
        forceUnauthorized: true,
        latency: const Duration(milliseconds: 20),
      );
      final unauthController = FaceAttendanceController(repository: unauthRepo);
      unauthController.setStudentInfo(
        username: 'STU_WRONG_01',
        name: 'Unregistered Student',
        registerNumber: 'REG-000',
      );

      unauthController.setDebugState(FaceAttendanceStatus.positioned);
      await unauthController.verifyAttendance();

      expect(unauthController.status, equals(FaceAttendanceStatus.unauthorized));
      expect(unauthController.currentConfig.alertTitle, equals('Unauthorized Face Detected'));
      expect(unauthController.currentConfig.buttonMode, equals(ActionButtonMode.retry));
      unauthController.dispose();
    });

    test('Network error transitions to networkError status and allows retry', () async {
      final errorRepo = MockFaceAttendanceRepository(
        forceNetworkError: true,
        latency: const Duration(milliseconds: 20),
      );
      final errorController = FaceAttendanceController(repository: errorRepo);

      errorController.setDebugState(FaceAttendanceStatus.positioned);
      await errorController.verifyAttendance(
        studentUsername: 'STU12345',
        studentName: 'Test Student',
        registerNumber: 'REG-001',
      );

      expect(errorController.status, equals(FaceAttendanceStatus.networkError));
      expect(errorController.currentConfig.buttonMode, equals(ActionButtonMode.retry));

      errorController.retry();
      expect(
        errorController.status,
        isIn([
          FaceAttendanceStatus.cameraReady,
          FaceAttendanceStatus.initializing,
          FaceAttendanceStatus.noFace,
        ]),
      );
      errorController.dispose();
    });
  });

  group('Widget Tests for Face Attendance Components', () {
    Widget createTestApp(Widget child, {FaceAttendanceController? controller}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => FakeUserProvider()),
          ChangeNotifierProvider(create: (_) => WallpaperProvider()),
          if (controller != null)
            ChangeNotifierProvider<FaceAttendanceController>.value(
              value: controller,
            ),
        ],
        child: MaterialApp(
          home: child,
        ),
      );
    }

    testWidgets('AttendanceActionButton renders states and handles tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        createTestApp(
          Scaffold(
            body: AttendanceActionButton(
              mode: ActionButtonMode.enabled,
              label: 'Verify Attendance',
              hint: 'Position face in frame',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('VERIFY ATTENDANCE'), findsOneWidget);
      expect(find.text('Position face in frame'), findsOneWidget);

      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isTrue);
    });

    testWidgets('AttendanceProgressSteps displays 3 steps with correct active step', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const Scaffold(
            body: AttendanceProgressSteps(
              currentStep: 1,
              stepState: StepIndicatorState.current,
            ),
          ),
        ),
      );

      expect(find.text('Position'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.text('Result'), findsOneWidget);
    });

    testWidgets('VerificationStatusCard displays 4 metric tiles', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const Scaffold(
            body: VerificationStatusCard(
              stepIndex: 0,
              metrics: FaceDetectionMetrics.allGood,
            ),
          ),
        ),
      );

      expect(find.text('Verification Status'), findsOneWidget);
      expect(find.text('FACE STATUS'), findsOneWidget);
      expect(find.text('POSITION'), findsOneWidget);
      expect(find.text('LIGHTING'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('Centered'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
    });

    testWidgets('AttendanceStudentCard renders student info and session', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          Scaffold(
            body: AttendanceStudentCard(
              sessionInfo: AttendanceSessionInfo.defaultEvening(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Student Information'), findsOneWidget);
      expect(find.text('Balaji'), findsWidgets);
      expect(find.text('STU-1001'), findsWidgets);
      expect(find.text('Evening Roll Call · 7:00 – 9:00 PM'), findsOneWidget);
    });

    testWidgets('AttendanceAlertBanner renders title and message with correct color', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const Scaffold(
            body: AttendanceAlertBanner(
              title: 'Low Lighting',
              message: 'Face a light source to improve detection.',
              type: AlertBannerType.warning,
            ),
          ),
        ),
      );

      expect(find.text('Low Lighting'), findsOneWidget);
      expect(find.text('Face a light source to improve detection.'), findsOneWidget);
    });

    testWidgets('AttendanceSuccessView renders receipt with medallion and Done button', (tester) async {
      bool doneTapped = false;
      const record = AttendanceRecordResult(
        studentName: 'Balaji S',
        registerNumber: 'STU-1001',
        dateFormatted: 'Wed, 23 Sep 2026',
        timeFormatted: '7:45 PM',
        sessionName: 'Evening Roll Call',
        statusText: '✓ Present',
        referenceId: 'REF-998811',
      );

      await tester.pumpWidget(
        createTestApp(
          Scaffold(
            body: SingleChildScrollView(
              child: AttendanceSuccessView(
                record: record,
                onDone: () => doneTapped = true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Check-In Confirmed! 🟢'), findsOneWidget);
      expect(find.text('Balaji S'), findsOneWidget);
      expect(find.text('STU-1001'), findsOneWidget);
      expect(find.text('✓ Present'), findsOneWidget);
      expect(find.text('Reference ID REF-998811'), findsOneWidget);

      await tester.tap(find.text('DONE'));
      expect(doneTapped, isTrue);
    });

    testWidgets('FaceAttendanceScreen renders responsive layout on mobile', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = FaceAttendanceController(
        repository: MockFaceAttendanceRepository(),
      );

      await tester.pumpWidget(
        createTestApp(
          FaceAttendanceScreen(controller: controller),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('TODAY · EVENING ROLL CALL'), findsOneWidget);
      expect(find.text('Verification Status'), findsOneWidget);
      expect(find.text('Student Information'), findsOneWidget);

      controller.dispose();
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
