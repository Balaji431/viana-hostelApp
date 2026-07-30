import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../shared/user_provider.dart';
import '../../shared/main_layout.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../widgets/temporary_stay_dialog.dart';

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
  final _userController = TextEditingController();
  final _passController = TextEditingController();

  String? _usernameError;
  String? _passwordError;
  String? _errorMessage;

  bool _isLoading = false;
  bool _isObscured = true;
  bool _showCredentials = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? '907286443175-1uqe7brjctqhvoprujjv1ilf85ahongj.apps.googleusercontent.com' : null,
    scopes: ['email', 'profile'],
  );

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final username = _userController.text.trim();
    final password = _passController.text.trim();

    setState(() {
      _usernameError = null;
      _passwordError = null;
      _errorMessage = null;
    });

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        if (username.isEmpty) _usernameError = 'Required';
        if (password.isEmpty) _passwordError = 'Required';
        _errorMessage = 'Please enter both username and password.';
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      AuthService.login(username, password);

      final response = await ApiService.login(username, password);

      if (response['success'] == true) {
        final userData = response['data'];
        if (mounted) {
          Provider.of<UserProvider>(context, listen: false).login(userData);
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = response['message'] ?? 'Login failed';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Connection error: $e';
        });
      }
    }
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool isPassword = false,
    bool isObscured = true,
    required String? errorText,
    VoidCallback? onToggleObscure,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4E3E),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: isPassword && isObscured,
          onSubmitted: (_) => _handleLogin(),
          style: const TextStyle(fontSize: 14, color: Color(0xFF1B2B48)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withOpacity(0.95),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC4B8A6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFDCD2C3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
            ),
            suffixIcon: isPassword 
                ? IconButton(
                    icon: Icon(
                      isObscured ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: const TextStyle(color: Color(0xFFC62828), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorBanner() {
    if (_errorMessage == null) return const SizedBox.shrink();
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
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
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
    );
  }

  Widget _buildSignInButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _isLoading ? null : _handleLogin,
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFBEAA6), Color(0xFFD4AF37), Color(0xFFB8962E)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF8B7025), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.4),
                blurRadius: 1,
                offset: const Offset(0, -1.5),
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Color(0xFF3D2E0A),
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Login',
                    style: TextStyle(
                      color: Color(0xFF3D2E0A),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      shadows: [
                        Shadow(
                          color: Colors.white70,
                          offset: Offset(0, 1),
                          blurRadius: 1,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }



  Widget _buildAdminStaffLoginButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showCredentials = true;
            _errorMessage = null;
          });
        },
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF0F1520),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'Login with Bio ID',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackToGoogleButton() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _showCredentials = false;
            _errorMessage = null;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.arrow_back,
                color: Color(0xFF2D3748),
                size: 18,
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Back to sign in',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF2D3748),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Lato',
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
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

      // Check if email already registered in system database
      Map<String, dynamic> checkRes = {};
      try {
        checkRes = await ApiService.checkTemporaryStayEmail(googleEmail);
      } catch (_) {}

      // Case 1: Already has active temporary stay request
      if (checkRes['has_request'] == true && checkRes['request_details'] != null) {
        final req = Map<String, dynamic>.from(checkRes['request_details']);
        final userData = {
          'id': req['id'] ?? 0,
          'username': req['email'] ?? googleEmail,
          'full_name': req['full_name'] ?? googleName,
          'email': googleEmail,
          'role': 'guest',
          'hostel_name': req['hostel_name'] ?? '',
          'room_no': req['room_no'] ?? '',
          'room_code': req['room_code'] ?? req['room_no'] ?? '',
          'temporary_stay_request': req,
        };

        if (mounted) {
          final userProvider = Provider.of<UserProvider>(context, listen: false);
          await userProvider.login(userData);
          setState(() => _isLoading = false);
        }
        return;
      }

      // Case 2: Registered user (student, admin, staff) in DB but no active temporary stay request
      if (checkRes['registered'] == true) {
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
              _errorMessage = response['message'] ?? 'Verification failed';
            });
          }
        }
        return;
      }

      // Case 3: New email (free for temporary stay booking)
      setState(() => _isLoading = false);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => TemporaryStayDialog(
            googleEmail: googleEmail,
            googleName: googleName,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Google Authentication failed: $e';
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
                                  horizontal: isMobile ? 16 : 28,
                                  vertical: isMobile ? 28 : 40,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                // Logo Section
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFE8D48A), Color(0xFFD4AF37), Color(0xFFB8962E)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF8B7025), width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(40),
                                    child: Image.asset(
                                      'assets/images/favicon.png',
                                      width: 80,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => const Center(
                                        child: Icon(
                                          Icons.apartment,
                                          color: Color(0xFF3D2E0A),
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                 const SizedBox(height: 15),
                                 const SizedBox(height: 15),
                                 const Text(
                                  'SIMATS VSTAY',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Helvetica',
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 30),
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
                                        padding: const EdgeInsets.all(24),
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
                                            if (_showCredentials)
                                              const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    'Admin / Staff Login Only',
                                                    style: TextStyle(
                                                      color: Colors.black,
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.bold,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            else
                                              const Center(
                                                child: Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                                  child: Text(
                                                    'Authenticate using your registered Google account to securely access the hostel portal.',
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
                                            if (_showCredentials) ...[
                                              _buildInputField(
                                                label: 'Bio ID',
                                                controller: _userController,
                                                hint: 'Enter Bio ID',
                                                errorText: _usernameError,
                                              ),
                                              const SizedBox(height: 20),
                                              _buildInputField(
                                                label: 'Password',
                                                controller: _passController,
                                                hint: 'Enter password',
                                                isPassword: true,
                                                isObscured: _isObscured,
                                                onToggleObscure: () => setState(() => _isObscured = !_isObscured),
                                                errorText: _passwordError,
                                              ),
                                              const SizedBox(height: 30),
                                              _buildSignInButton(),
                                              const SizedBox(height: 25),
                                            ] else ...[
                                              _buildGoogleSignInButton(),
                                              const SizedBox(height: 25),
                                            ],
                                            // Secure Authentication divider
                                            Row(
                                              children: [
                                                Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
                                                const Padding(
                                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                                  child: Text(
                                                    'SECURE AUTHENTICATION',
                                                    style: TextStyle(
                                                      color: Color(0xFF888888),
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      letterSpacing: 1.0,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(child: Divider(color: Colors.grey.shade300, thickness: 1)),
                                              ],
                                            ),
                                            const SizedBox(height: 20),
                                            if (_showCredentials) ...[
                                              _buildBackToGoogleButton(),
                                            ] else ...[
                                              _buildAdminStaffLoginButton(),
                                            ],
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
                                     final Uri url = Uri.parse('https://balaji431.github.io/viana-hostelApp/privacy_policy.html');
                                     if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                                       debugPrint('Could not launch $url');
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
