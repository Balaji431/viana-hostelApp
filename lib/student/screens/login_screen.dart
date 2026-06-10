import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/user_provider.dart';
import '../../core/api_service.dart';
import '../../core/auth_service.dart';
import '../../core/royal_theme.dart';
import '../../core/styles.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  
  // Registration Controllers
  final _regNameController = TextEditingController();
  final _regNoController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPhoneController = TextEditingController();
  final _regPassController = TextEditingController();
  final _regConfirmPassController = TextEditingController();
  
  bool _isLoading = false;
  bool _isRegistering = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F1520), // Deep dark navy matching desktop theme
              Color(0xFF1A2235),
              Color(0xFF0F1520),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Container(
              width: 400,
              margin: const EdgeInsets.symmetric(horizontal: 24),
              child: SkeuomorphicCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Section (Leather Header)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        gradient: RoyalTheme.leatherGradient,
                      ),
                      child: Column(
                        children: [
                          // Logo Circle
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              gradient: RoyalTheme.glossyGoldGradient,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black.withOpacity(0.3), width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.apartment,
                              color: Color(0xFF1A0F0A),
                              size: 35,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Royal Residences',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: RoyalTheme.goldTop,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'STUDENT HOSTEL MANAGEMENT',
                            style: GoogleFonts.lato(
                              fontSize: 8,
                              letterSpacing: 2.0,
                              fontWeight: FontWeight.w700,
                              color: RoyalTheme.goldMid.withOpacity(0.85),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Section (Linen Content)
                    LinenGridBackground(
                      isWhite: true,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(30, 30, 30, 35),
                        child: _isRegistering ? _buildRegistrationForm() : _buildLoginForm(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return Column(
      children: [
        Text(
          'Welcome Back',
          style: GoogleFonts.playfairDisplay(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: RoyalTheme.navyDark,
          ),
        ),
        const SizedBox(height: 30),
        
        // Username Field
        _buildLabel('Username / Reg No'),
        InsetInputField(
          controller: _userController,
          hint: 'Enter your registration number',
        ),
        const SizedBox(height: 20),
        
        // Password Field
        _buildLabel('Password'),
        InsetInputField(
          controller: _passController,
          hint: 'Enter your password',
          isPassword: true,
        ),
        const SizedBox(height: 35),

        // Glossy 3D Button
        GlossyButton(
          text: 'Sign In',
          isLoading: _isLoading,
          onPressed: _handleLogin,
        ),
        
        const SizedBox(height: 25),
        
        // Privacy Policy Button
        TextButton(
          onPressed: _launchPrivacyPolicy,
          child: Text(
            'Privacy Policy',
            style: GoogleFonts.lato(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFC5A358),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_person_outlined, size: 14, color: RoyalTheme.navyDark.withOpacity(0.5)),
            const SizedBox(width: 8),
            Text(
              'Secure Login',
              style: GoogleFonts.lato(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: RoyalTheme.navyDark.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegistrationForm() {
    return Column(
      children: [
        Text(
          'New Applicant Registration',
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: RoyalTheme.navyDark,
          ),
        ),
        const SizedBox(height: 25),
        
        _buildLabel('Full Name'),
        InsetInputField(
          controller: _regNameController,
          hint: 'Enter your full name',
        ),
        const SizedBox(height: 15),
        
        _buildLabel('Registration Number'),
        InsetInputField(
          controller: _regNoController,
          hint: 'Enter registration number',
        ),
        const SizedBox(height: 15),
        
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Email'),
                  InsetInputField(
                    controller: _regEmailController,
                    hint: 'student@email.com',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Phone'),
                  InsetInputField(
                    controller: _regPhoneController,
                    hint: '9876543210',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        
        _buildLabel('Create Password'),
        InsetInputField(
          controller: _regPassController,
          hint: 'Min. 6 characters',
          isPassword: true,
        ),
        const SizedBox(height: 15),
        
        _buildLabel('Confirm Password'),
        InsetInputField(
          controller: _regConfirmPassController,
          hint: 'Re-enter password',
          isPassword: true,
        ),
        const SizedBox(height: 30),

        GlossyButton(
          text: 'Register Now',
          isLoading: _isLoading,
          onPressed: _handleRegistration,
        ),
        
        const SizedBox(height: 20),
        
        TextButton(
          onPressed: () => setState(() => _isRegistering = false),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Already have an account?',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  color: RoyalTheme.navyDark.withOpacity(0.7),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Sign In',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFC5A358),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        text,
        style: GoogleFonts.lato(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: RoyalTheme.navyDark,
        ),
      ),
    );
  }

  void _handleRegistration() async {
    if (_regNameController.text.isEmpty || 
        _regNoController.text.isEmpty || 
        _regPassController.text.isEmpty) {
      _showError('Full name, Reg No, and Password are required');
      return;
    }

    if (_regPassController.text != _regConfirmPassController.text) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.registerStudent(
        fullName: _regNameController.text.trim(),
        registerNo: _regNoController.text.trim(),
        password: _regPassController.text.trim(),
        email: _regEmailController.text.trim(),
        phone: _regPhoneController.text.trim(),
      );

      if (response['success'] == true) {
        _showSuccess('Registration successful! Please login.');
        setState(() {
          _isRegistering = false;
          _isLoading = false;
          _userController.text = _regNoController.text;
        });
      } else {
        _showError(response['message'] ?? 'Registration failed');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      _showError('Server error: $e');
      setState(() => _isLoading = false);
    }
  }

  void _handleLogin() async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      _showError('Please enter both username and password');
      return;
    }

    setState(() => _isLoading = true);

    final username = _userController.text.trim();
    final password = _passController.text.trim();
    
    // Check master auth first (for demo/admin purposes)
    AuthService.login(username, password);

    final response = await ApiService.login(username, password);

    if (response['success'] == true) {
      final userData = response['data'];
      if (mounted) {
        Provider.of<UserProvider>(context, listen: false).login(userData);
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError(response['message'] ?? 'Login failed');
      }
    }
  }

  Future<void> _launchPrivacyPolicy() async {
    final Uri url = Uri.parse('https://www.termsfeed.com/live/e1b2a8d4-0e7b-4675-b983-328ecb79f09d');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        _showError('Could not launch Privacy Policy link');
      }
    } catch (e) {
      _showError('Error opening link: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }
}
