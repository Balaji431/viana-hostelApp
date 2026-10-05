import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vianasoft_stay/core/api_service.dart';
import 'package:vianasoft_stay/shared/user_provider.dart';
import 'package:vianasoft_stay/shared/wallpaper_provider.dart';
import 'package:vianasoft_stay/warden/screens/warden_face_enrollment_screen.dart';
import 'package:vianasoft_stay/student/face_attendance/controllers/face_attendance_controller.dart';
import 'package:vianasoft_stay/student/face_attendance/models/face_attendance_models.dart';

class MockWardenUserProvider extends ChangeNotifier implements UserProvider {
  @override
  String get userName => 'Mr. K. Venkatesh';
  @override
  String get username => 'warden_floor3';
  @override
  UserRole get role => UserRole.warden;
  @override
  String get roleName => 'Floor Warden';
  @override
  int? get dbId => 42;
  @override
  String get registerNo => '';
  @override
  String get studentId => '';
  @override
  String get institution => 'SIMATS';
  @override
  bool get hasMultipleRoles => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Warden Face Enrollment Allocation Verification Logic', () {
    test('Unallocated student returns NOT_ALLOCATED error', () async {
      final res = await ApiService.verifyStudentForFaceEnrollment(
        regNo: 'UNALLOCATED_999',
        wardenUsername: 'warden_floor3',
      );

      expect(res['success'], isFalse);
      expect(res['error_code'], equals('NOT_ALLOCATED'));
      expect(res['message'], contains('has not been allocated to any room'));
    });

    test('Student allocated to another warden returns ALLOCATED_TO_OTHER_WARDEN error', () async {
      final res = await ApiService.verifyStudentForFaceEnrollment(
        regNo: '112201999',
        wardenUsername: 'warden_floor3',
      );

      expect(res['success'], isFalse);
      expect(res['error_code'], equals('ALLOCATED_TO_OTHER_WARDEN'));
      expect(res['message'], contains('Unauthorized Floor'));
      expect(res['message'], contains('Only their assigned floor warden can enroll their face'));
    });

    test('Student allocated to current warden floor returns success', () async {
      final res = await ApiService.verifyStudentForFaceEnrollment(
        regNo: '192524999',
        wardenUsername: 'warden_floor3',
      );

      expect(res['success'], isTrue);
      expect(res['status'], equals('success'));
      expect(res['student'], isNotNull);
      expect(res['student']['is_allocated'], isTrue);
      expect(res['student']['is_assigned_to_you'], isTrue);
    });

    test('searchFloorStudentsForEnrollment returns matching students on floor for 19 and 192211', () async {
      final res19 = await ApiService.searchFloorStudentsForEnrollment(
        query: '19',
        wardenUsername: 'warden_floor3',
      );

      expect(res19['success'], isTrue);
      final List<dynamic> students19 = res19['students'];
      expect(students19.length, greaterThanOrEqualTo(4));
      expect(students19.any((s) => s['reg_no'].toString().startsWith('192211')), isTrue);
      expect(students19.any((s) => s['reg_no'].toString() == '192524999'), isTrue);

      final res192211 = await ApiService.searchFloorStudentsForEnrollment(
        query: '192211',
        wardenUsername: 'warden_floor3',
      );

      expect(res192211['success'], isTrue);
      final List<dynamic> students192211 = res192211['students'];
      expect(students192211.length, greaterThanOrEqualTo(3));
      for (final s in students192211) {
        expect(s['reg_no'].toString().startsWith('192211'), isTrue);
      }
    });
  });

  group('WardenFaceEnrollmentScreen UI Tests', () {
    testWidgets('Renders Lookup View with Register Number input and verify button', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => MockWardenUserProvider()),
            ChangeNotifierProvider<WallpaperProvider>(create: (_) => WallpaperProvider()),
          ],
          child: const MaterialApp(
            home: WardenFaceEnrollmentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('STUDENT REGISTER NUMBER'), findsOneWidget);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Entering invalid / unallocated student shows error warning card', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => MockWardenUserProvider()),
            ChangeNotifierProvider<WallpaperProvider>(create: (_) => WallpaperProvider()),
          ],
          child: const MaterialApp(
            home: WardenFaceEnrollmentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'UNALLOCATED_123');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('ROOM ALLOCATION REQUIRED'), findsOneWidget);
      expect(find.textContaining('has not been allocated to any room'), findsOneWidget);
    });

    testWidgets('Entering other warden student shows unauthorized floor error card', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => MockWardenUserProvider()),
            ChangeNotifierProvider<WallpaperProvider>(create: (_) => WallpaperProvider()),
          ],
          child: const MaterialApp(
            home: WardenFaceEnrollmentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '112201999');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('UNAUTHORIZED FLOOR ALLOCATION'), findsOneWidget);
      expect(find.textContaining('Unauthorized Floor'), findsOneWidget);
    });

    testWidgets('Entering valid student shows verified student card with Proceed button', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => MockWardenUserProvider()),
            ChangeNotifierProvider<WallpaperProvider>(create: (_) => WallpaperProvider()),
          ],
          child: const MaterialApp(
            home: WardenFaceEnrollmentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '192524999');
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();

      expect(find.text('ALLOCATION VERIFIED'), findsOneWidget);
      expect(find.text('Proceed to Face Biometric Capture'), findsOneWidget);
      expect(find.text('Alex Rivera'), findsOneWidget);
    });

    testWidgets('Searching 19 displays dropdown with related students on that floor', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => MockWardenUserProvider()),
            ChangeNotifierProvider<WallpaperProvider>(create: (_) => WallpaperProvider()),
          ],
          child: const MaterialApp(
            home: WardenFaceEnrollmentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter '19' into the register number search box
      await tester.enterText(find.byType(TextField), '19');
      // Pump debounce time
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Dropdown header must be visible
      expect(find.text('STUDENTS ON YOUR FLOOR'), findsOneWidget);
      expect(find.textContaining('MATCH'), findsOneWidget);

      // Matching students on this floor must appear in the dropdown
      expect(find.text('192211001'), findsOneWidget);
      expect(find.text('Aravind Kumar'), findsOneWidget);
      expect(find.text('192211045'), findsOneWidget);
      expect(find.text('Balaji S'), findsOneWidget);
    });

    testWidgets('Searching 192211 and tapping student selects regNo and verifies them', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => MockWardenUserProvider()),
            ChangeNotifierProvider<WallpaperProvider>(create: (_) => WallpaperProvider()),
          ],
          child: const MaterialApp(
            home: WardenFaceEnrollmentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter '192211'
      await tester.enterText(find.byType(TextField), '192211');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('STUDENTS ON YOUR FLOOR'), findsOneWidget);
      expect(find.text('192211045'), findsOneWidget);
      expect(find.text('Balaji S'), findsOneWidget);

      // Tap on Balaji S from the dropdown
      await tester.tap(find.text('Balaji S'));
      await tester.pumpAndSettle();

      // Dropdown should close
      expect(find.text('STUDENTS ON YOUR FLOOR'), findsNothing);

      // Text field should be populated with '192211045'
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, equals('192211045'));

      // Student is selected and verified
      expect(find.text('ALLOCATION VERIFIED'), findsOneWidget);
      expect(find.text('Proceed to Face Biometric Capture'), findsOneWidget);
    });

    test('Registration mode defaults to Back Camera and 3 compulsory liveness steps', () async {
      final controller = FaceAttendanceController(initialMode: FaceScanMode.registration);
      expect(controller.preferredLens, equals(CameraLensDirection.back));
      await controller.initialize();
      expect(controller.challenges, equals([
        LivenessChallenge.turnLeft,
        LivenessChallenge.turnRight,
        LivenessChallenge.blinkEyes,
      ]));
    });
  });
}
