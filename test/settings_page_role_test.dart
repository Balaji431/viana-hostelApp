import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vianasoft_stay/shared/user_provider.dart';
import 'package:vianasoft_stay/shared/wallpaper_provider.dart';
import 'package:vianasoft_stay/student/screens/settings_page.dart';
import 'package:vianasoft_stay/shared/widgets/user_avatar_header.dart';

class MockTestUserProvider extends ChangeNotifier implements UserProvider {
  final UserRole _role;
  final String _userName;
  final String _username;
  final String _roleName;
  String _profilePic;

  MockTestUserProvider({
    required UserRole role,
    required String userName,
    required String username,
    required String roleName,
    String profilePic = '',
  })  : _role = role,
        _userName = userName,
        _username = username,
        _roleName = roleName,
        _profilePic = profilePic;

  @override
  UserRole get role => _role;

  @override
  String get userName => _userName;

  @override
  String get username => _username;

  @override
  String get roleName => _roleName;

  @override
  int get dashboardRefreshTick => 0;

  @override
  int? get dbId => 1;

  @override
  String get registerNo => _role == UserRole.student ? _username : '';

  @override
  String get studentId => '';

  @override
  String get institution => 'Hostel Admin';

  @override
  bool get hasMultipleRoles => false;

  @override
  List<UserRole> get availableRoles => [_role];

  @override
  String get email => 'test@hostel.com';

  @override
  String get phone => '9876543210';

  @override
  String get campus => 'Main Campus';

  @override
  String get hostelName => 'Main Hostel';

  @override
  String get roomNumber => '';

  @override
  DateTime? get checkInDate => null;

  @override
  DateTime? get renewalDate => null;

  @override
  Future<void> refreshUserData() async {}

  @override
  String get profilePic => _profilePic;

  @override
  Future<void> updateProfilePic(String newPic) async {
    _profilePic = newPic;
    notifyListeners();
  }

  @override
  String get roomAllocation => '101';

  @override
  String get roomTypeDisplay => 'Standard Room';

  @override
  String get conduct => 'Good';

  @override
  String get conductRemarks => '';

  @override
  String get warden => '';

  @override
  String get fullRoomDetails => '101';

  @override
  bool get isGuest => false;

  @override
  Map<String, dynamic>? get temporaryStayRequest => null;

  @override
  int get remainingDays => 30;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SettingsPage does NOT display Room and management section for Admin', (tester) async {
    final adminUser = MockTestUserProvider(
      role: UserRole.admin,
      userName: 'Administrator',
      username: 'admin',
      roleName: 'System Admin',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: adminUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 'Room and management' header is NOT present
    expect(find.text('Room and management'), findsNothing);
    // Verify actions inside that section are NOT present
    expect(find.text('Room search'), findsNothing);
    expect(find.text('Room change'), findsNothing);
  });

  testWidgets('SettingsPage does NOT display Room and management section for SuperAdmin', (tester) async {
    final superAdminUser = MockTestUserProvider(
      role: UserRole.superAdmin,
      userName: 'Super Admin',
      username: 'superadmin',
      roleName: 'Super Admin',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: superAdminUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Room and management'), findsNothing);
    expect(find.text('Room search'), findsNothing);
    expect(find.text('Room change'), findsNothing);
  });

  testWidgets('SettingsPage DOES display Room and management section for Warden', (tester) async {
    final wardenUser = MockTestUserProvider(
      role: UserRole.warden,
      userName: 'Kanita K',
      username: '29617',
      roleName: 'Hostel Warden',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: wardenUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // In warden portal / login, Room and management MUST be visible
    expect(find.text('Room and management'), findsOneWidget);
    expect(find.text('Room search'), findsOneWidget);
    expect(find.text('Room change'), findsOneWidget);
  });

  testWidgets('Student avatar displays SA initials, camera badge, and opens photo picker modal on tap', (tester) async {
    final studentUser = MockTestUserProvider(
      role: UserRole.student,
      userName: 'Shaik Ashraf',
      username: '192211929',
      roleName: 'Student',
      profilePic: '',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: studentUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Initial "SA" should be visible in avatar
    expect(find.text('SA'), findsOneWidget);

    // 2. Camera icon badge should be visible on avatar
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);

    // 3. Tap on the avatar
    await tester.tap(find.byTooltip('Tap to change profile photo'));
    await tester.pumpAndSettle();

    // 4. Modal options should appear
    expect(find.text('Profile Photo'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    // Since student has no custom pic yet, Remove option is not shown
    expect(find.text('Remove Current Photo'), findsNothing);
  });

  testWidgets('Student avatar with custom photo shows Remove Current Photo option in modal', (tester) async {
    final studentUser = MockTestUserProvider(
      role: UserRole.student,
      userName: 'Shaik Ashraf',
      username: '192211929',
      roleName: 'Student',
      profilePic: 'uploads/profiles/profile_192211929_test.jpg',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: studentUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap on the avatar
    await tester.tap(find.byTooltip('Tap to change profile photo'));
    await tester.pumpAndSettle();

    // All options including Remove Photo and View Full Photo should be visible
    expect(find.text('View Full Photo'), findsOneWidget);
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.text('Remove Current Photo'), findsOneWidget);
  });

  testWidgets('Image 2 UI is removed from Settings and View Full Photo is accessed via top avatar', (tester) async {
    final studentUser = MockTestUserProvider(
      role: UserRole.student,
      userName: 'Gurikani Amrutha',
      username: '192511250',
      roleName: 'Student',
      profilePic: 'uploads/profiles/profile_192511250_1790685280_937.jpeg',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: studentUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify Image 2 UI ("Profile Photo & ID") is completely removed from SettingsPage
    expect(find.text('Profile Photo & ID'), findsNothing);

    // 2. Tap on the top avatar to open options
    await tester.tap(find.byTooltip('Tap to change profile photo'));
    await tester.pumpAndSettle();

    expect(find.text('View Full Photo'), findsOneWidget);

    // 3. Tap "View Full Photo"
    await tester.tap(find.text('View Full Photo'));
    await tester.pumpAndSettle();

    // 4. Full photo dialog should display student name and ID
    expect(find.text('Gurikani Amrutha'), findsWidgets);
    expect(find.text('Reg No: 192511250'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    // 5. Tap Close
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('UserHeaderAvatar renders round photo on home screen / dashboard and taps to view full photo', (tester) async {
    final wardenUser = MockTestUserProvider(
      role: UserRole.warden,
      userName: 'KANITA K',
      username: '29617',
      roleName: 'Warden',
      profilePic: 'uploads/profiles/profile_warden_29617.jpeg',
    );
    final wallpaper = WallpaperProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>.value(value: wardenUser),
          ChangeNotifierProvider<WallpaperProvider>.value(value: wallpaper),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: UserHeaderAvatar(user: wardenUser, size: 44),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Should render UserHeaderAvatar
    expect(find.byType(UserHeaderAvatar), findsOneWidget);

    // Tap on avatar to view full photo
    await tester.tap(find.byType(UserHeaderAvatar));
    await tester.pumpAndSettle();

    // Full photo modal should open with warden details
    expect(find.text('KANITA K'), findsOneWidget);
    expect(find.text('User ID: 29617'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);
  });
}

