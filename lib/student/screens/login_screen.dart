import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../shared/user_provider.dart';
import '../../shared/screens/privacy_policy_screen.dart' deferred as privacy_screen;
import '../../core/api_service.dart';
import '../../core/app_update_service.dart';
import '../widgets/temporary_stay_dialog.dart' deferred as temp_dialog;

class LeatherFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final RRect rrect = RRect.fromRectAndRadius(rect, const Radius.circular(28));

    // 1. Radial leather background gradient
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.6),
        radius: 1.3,
        colors: [
          const Color(0xFF5D4037), // Lighter warm brown highlight
          const Color(0xFF3E2723), // Deep chocolate brown
          const Color(0xFF1B0E0A), // Near black brown at edges
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);

    // 2. Leather pores texture
    final noisePaint = Paint()..color = Colors.black.withValues(alpha: 0.06);
    final random = Random(42);
    for (int i = 0; i < 200; i++) {
      double x = random.nextDouble() * size.width;
      double y = random.nextDouble() * size.height;
      double radius = 0.6 + random.nextDouble() * 0.8;
      canvas.drawCircle(Offset(x, y), radius, noisePaint);
    }

    // 3. Inner inset shadows
    final insetPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withOpacity(0.4),
          Colors.black.withOpacity(0.7),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, insetPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LinenCardPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    // 1. Warm linen base color
    final paint = Paint()..color = const Color(0xFFFAF7F2);
    canvas.drawRRect(rrect, paint);

    // 2. Linen criss-cross texture pattern
    final linePaint = Paint()
      ..color = const Color(0xFFDCD6CD).withOpacity(0.24)
      ..strokeWidth = 0.5;

    // Horizontal lines
    for (double y = 0; y < size.height; y += 8) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
    // Vertical lines
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double r = min(w, h) / 2;
    final Offset center = Offset(w / 2, h / 2);

    final double strokeWidth = r * 0.45;
    final double radius = r - strokeWidth / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Red sector (Top): starts at -2.4 rad (-137 deg), sweep 1.6 rad (91 deg)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -2.4, 1.6, false, paint);

    // Yellow sector (Left): starts at -3.8 rad (-217 deg), sweep 1.45 rad (83 deg)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, -3.8, 1.45, false, paint);

    // Green sector (Bottom): starts at 0.5 rad (28 deg), sweep 2.1 rad (120 deg)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.5, 2.1, false, paint);

    // Blue sector (Right): starts at -0.8 rad (-45 deg), sweep 1.4 rad (80 deg)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.8, 1.4, false, paint);

    // Blue horizontal bar
    final Paint barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final double barWidth = r;
    final double barHeight = strokeWidth;
    final Rect barRect = Rect.fromLTWH(
      center.dx,
      center.dy - barHeight / 2,
      barWidth,
      barHeight,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String? _errorMessage;
  String? _lastGoogleEmail;
  String? _lastGoogleName;
  bool _isLoading = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '907286443175-1uqe7brjctqhvoprujjv1ilf85ahongj.apps.googleusercontent.com' : null,
    serverClientId: '907286443175-1uqe7brjctqhvoprujjv1ilf85ahongj.apps.googleusercontent.com',
    scopes: ['email', 'profile'],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        AppUpdateService.checkUpdateAndPrompt(context);
      }
    });
  }

  Future<void> _openTemporaryStayDialog([String? email, String? name]) async {
    final targetEmail = (email != null && email.isNotEmpty) ? email : (_lastGoogleEmail ?? '');
    final targetName = (name != null && name.isNotEmpty) ? name : (_lastGoogleName ?? '');

    Map<String, dynamic>? existingRequest;
    if (targetEmail.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        final res = await ApiService.checkTemporaryStayEmail(targetEmail);
        if (res['success'] == true && res['has_request'] == true) {
          existingRequest = res['request_details'] != null
              ? Map<String, dynamic>.from(res['request_details'])
              : null;
        }
      } catch (e) {
        debugPrint('Error checking temporary stay email: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }

    await temp_dialog.loadLibrary();
    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => temp_dialog.TemporaryStayDialog(
        googleEmail: targetEmail,
        googleName: targetName,
        existingRequest: existingRequest,
      ),
    );

    if (result != null && result['auto_login_user'] != null && mounted) {
      final userData = Map<String, dynamic>.from(result['auto_login_user']);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      userProvider.login(userData);
    }
  }

  Widget _buildErrorBanner() {
    if (_errorMessage == null) return const SizedBox.shrink();
    final bool isAccountNotFound = _errorMessage!.toLowerCase().contains('no vstay account') ||
        _errorMessage!.toLowerCase().contains('not found') ||
        _errorMessage!.toLowerCase().contains('hostel fee');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEBEE), Color(0xFFFFCDD2)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF9A9A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Color(0xFFC62828),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (isAccountNotFound) ...[
            const SizedBox(height: 10),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _openTemporaryStayDialog(_lastGoogleEmail, _lastGoogleName),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE57373)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.hotel_rounded, size: 15, color: Color(0xFFC62828)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Looking for Short Stay? Apply Here ➔',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFFC62828),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }





  void _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the login dialog
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      final String? accessToken = googleAuth.accessToken;

      if (idToken == null && accessToken == null) {
        throw Exception("Failed to retrieve Google credentials (ID and Access Token are both null).");
      }

      final String googleEmail = googleUser.email;
      final String googleName = googleUser.displayName ?? 'Applicant';
      _lastGoogleEmail = googleEmail;
      _lastGoogleName = googleName;

      // Direct Google Login for registered VStay users
      final response = await ApiService.googleLogin(
        googleEmail,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response['success'] == true) {
        final userData = response['data'];
        if (mounted) {
          final provider = Provider.of<UserProvider>(context, listen: false);
          provider.login(userData);
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = response['message'] ?? 'No VStay account was found for this email. Use email which u have used to pay the hostel fee.';
          });
        }
      }
      return;
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.contains('SocketException') || msg.contains('Connection refused') || msg.contains('ClientException')) {
          msg = 'Unable to connect to server. Please check your connection or verify backend server is running.';
        } else {
          msg = 'Google Authentication failed: $e';
        }
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
      }
    }
  }


  Widget _buildGoogleSignInButton() {
    return MouseRegion(
      cursor: _isLoading ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isLoading ? null : _handleGoogleSignIn,
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFDADCE0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFF4285F4),
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/google_logo.png',
                        width: 20,
                        height: 20,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.account_circle, size: 20, color: Color(0xFF4285F4)),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Continue with Google',
                        style: TextStyle(
                          color: Color(0xFF1F1F1F),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 500;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1520),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            // Background Gradient Overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 250,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.0),
                      Colors.black.withOpacity(0.35),
                    ],
                  ),
                ),
              ),
            ),
            // Centered Frame Container
            Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 10 : 24,
                    vertical: isMobile ? 20 : 40,
                  ),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 250),
                    tween: Tween(begin: 0.9, end: 1.0),
                    curve: Curves.easeOut,
                    builder: (context, scale, child) {
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: Container(
                      width: isMobile ? screenWidth * 0.94 : 440,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(36),
                        // Layered outer metallic border
                        border: Border.all(
                          color: Colors.black,
                          width: 4.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.6),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.black,
                            width: 4,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: LeatherFramePainter(),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isMobile ? 12 : 28,
                                  vertical: isMobile ? 20 : 36,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  // Logo Section - Clean Round Emblem
                                  Container(
                                    width: isMobile ? 88 : 96,
                                    height: isMobile ? 88 : 96,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.35),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Image.asset(
                                          'assets/images/favicon.png',
                                          fit: BoxFit.contain,
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Icon(
                                              Icons.apartment,
                                              color: Color(0xFF1B2B48),
                                              size: 40,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isMobile ? 12 : 18),
                                 Text(
                                  'SIMATS VSTAY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isMobile ? 22 : 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Helvetica',
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                SizedBox(height: isMobile ? 18 : 28),
                                // Linen Card
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFD0C8BC), width: 1.2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: RepaintBoundary(
                                      child: CustomPaint(
                                        painter: LinenCardPainter(),
                                        child: Padding(
                                        padding: EdgeInsets.all(isMobile ? 18 : 24),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Center(
                                              child: Text(
                                                'Welcome Back',
                                                style: TextStyle(
                                                  color: Color(0xFF1A2744),
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            const Center(
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 8),
                                                child: Text(
                                                  'Sign in with your registered Google account to securely access the SIMATS VStay portal.',
                                                  style: TextStyle(
                                                    color: Color(0xFF5F6368),
                                                    fontSize: 13,
                                                    height: 1.4,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 25),
                                            _buildErrorBanner(),
                                            _buildGoogleSignInButton(),
                                            const SizedBox(height: 10),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                               ),
                               const SizedBox(height: 16),
                               MouseRegion(
                                 cursor: SystemMouseCursors.click,
                                 child: GestureDetector(
                                   onTap: () async {
                                     await privacy_screen.loadLibrary();
                                     if (context.mounted) {
                                       Navigator.push(
                                         context,
                                         MaterialPageRoute(
                                           settings: const RouteSettings(name: '/privacy-policy'),
                                           builder: (_) => privacy_screen.PrivacyPolicyScreen(),
                                         ),
                                       );
                                     }
                                   },
                                   child: const Padding(
                                     padding: EdgeInsets.symmetric(vertical: 4),
                                     child: Text(
                                       'Privacy Policy',
                                       style: TextStyle(
                                         color: Colors.white,
                                         fontSize: 13,
                                         fontWeight: FontWeight.w600,
                                         decoration: TextDecoration.underline,
                                         decorationColor: Colors.white,
                                         letterSpacing: 0.5,
                                       ),
                                     ),
                                   ),
                                 ),
                               ),
                               const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    ),
  );
}
}
