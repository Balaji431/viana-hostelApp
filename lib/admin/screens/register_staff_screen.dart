import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/category_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class RegisterStaffScreen extends StatefulWidget {
  const RegisterStaffScreen({super.key});

  @override
  State<RegisterStaffScreen> createState() => _RegisterStaffScreenState();
}

class _RegisterStaffScreenState extends State<RegisterStaffScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  
  String? _selectedRole;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final catProvider = context.watch<CategoryProvider>();
    final roles = catProvider.categories
        .where((c) => (c['is_staff_role'] ?? 1) == 1)
        .map((c) => c['name'] as String)
        .toList();
    if (roles.isEmpty) roles.addAll(['Warden', 'Security', 'Maintenance']);
    
    _selectedRole ??= roles.first;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SkeuomorphicNavBar(
        title: 'New Staff',
        onBack: null,
      ),
      body: LinenGridBackground(
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Register New Staff Member',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                    fontFamily: 'Lato',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create credentials for new wardens, security guards, or maintenance staff.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey.shade600,
                    fontFamily: 'Lato',
                  ),
                ),
                const SizedBox(height: 24),
                
                // Form Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE2DACC),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Role Selector
                      Text(
                        'Select Role',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? const Color(0xFFD4AF37) : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: roles.map((role) {
                          final isSelected = _selectedRole == role;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedRole = role),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) 
                                    : (isDark ? const Color(0xFF1E293B) : Colors.grey.shade100),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected 
                                      ? (isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744)) 
                                      : (isDark ? Colors.white24 : Colors.grey.shade300),
                                ),
                              ),
                              child: Text(
                                role,
                                style: TextStyle(
                                  color: isSelected 
                                      ? (isDark ? const Color(0xFF1A2744) : Colors.white) 
                                      : (isDark ? Colors.white70 : Colors.black87),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      
                      _buildStyledField(
                        label: 'Full Name',
                        controller: _nameController,
                        icon: Icons.badge_outlined,
                        hint: 'e.g., Rajesh Kumar',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                      
                      _buildStyledField(
                        label: 'Username / Reg No',
                        controller: _usernameController,
                        icon: Icons.alternate_email_rounded,
                        hint: 'e.g., warden_rajesh',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                      
                      _buildStyledField(
                        label: 'Login Password',
                        controller: _passwordController,
                        icon: Icons.lock_outline_rounded,
                        hint: 'Set a secure password',
                        isPassword: true,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                      
                      _buildStyledField(
                        label: 'Phone Number',
                        controller: _phoneController,
                        icon: Icons.phone_android_rounded,
                        hint: 'Primary contact number',
                        keyboardType: TextInputType.phone,
                        isDark: isDark,
                      ),
                      const SizedBox(height: 32),
                      
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                            foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 2,
                          ),
                          child: _isSaving
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: isDark ? const Color(0xFF1A2744) : Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Register Staff',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    fontFamily: 'Lato',
                                  ),
                                ),
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
    );
  }

  Widget _buildStyledField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    bool isDark = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isDark ? const Color(0xFFD4AF37) : Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 13),
            prefixIcon: Icon(icon, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744), size: 20),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F1520) : Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final res = await ApiService.registerStaff(
        fullName: name,
        username: username,
        password: password,
        role: _selectedRole,
        phone: phone,
      );

      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Staff member registered successfully')),
          );
          _nameController.clear();
          _usernameController.clear();
          _passwordController.clear();
          _phoneController.clear();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Registration failed')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
