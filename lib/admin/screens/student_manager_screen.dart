import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class StudentManagerScreen extends StatefulWidget {
  const StudentManagerScreen({super.key});

  @override
  State<StudentManagerScreen> createState() => _StudentManagerScreenState();
}

class _StudentManagerScreenState extends State<StudentManagerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _registerNoController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedGender = 'Male';
  bool _isSubmitting = false;

  Future<void> _submitForm(bool isDark) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiService.registerStudent(
        fullName: _fullNameController.text,
        registerNo: _registerNoController.text,
        password: _passwordController.text,
        email: _emailController.text,
        phone: _phoneController.text,
      );

      if (mounted) {
        if (response['success']) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isDark ? Colors.white.withOpacity(0.14) : Colors.transparent),
              ),
              title: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(width: 10),
                  Text('Registration Success', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Student has been registered successfully.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Login Credentials:', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFD4AF37) : Colors.black87),
                  ),
                  const SizedBox(height: 10),
                  _buildCredentialRow('Register No:', _registerNoController.text, isDark),
                  _buildCredentialRow('Password:', _passwordController.text, isDark),
                  const SizedBox(height: 15),
                  Text(
                    'Note: The student can change their password after logging in from the Settings page.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _fullNameController.clear();
                    _registerNoController.clear();
                    _emailController.clear();
                    _phoneController.clear();
                    _contactNumberController.clear();
                    _addressController.clear();
                    _passwordController.clear();
                  },
                  child: const Text('Great!', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response['message'] ?? 'Registration failed')),
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Register New Student',
        onBack: () => Navigator.of(context).pop(),
      ),
      body: LinenGridBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Form(
                key: _formKey,
                child: Column(
                  children: [
                  _buildTextField(
                    controller: _fullNameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                    isDark: isDark,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Full Name is required';
                      if (v.length < 3) return 'Name too short';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _registerNoController,
                    label: 'Register Number',
                    icon: Icons.badge_outlined,
                    isDark: isDark,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Register Number is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    isDark: isDark,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Invalid email format';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                    isDark: isDark,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Phone number is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _contactNumberController,
                    label: 'Parent / Guardian Phone Number',
                    icon: Icons.contact_phone_outlined,
                    keyboardType: TextInputType.phone,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _buildGenderDropdown(isDark),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _addressController,
                    label: 'Permanent Address',
                    icon: Icons.home_outlined,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Initial Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    isDark: isDark,
                    hintText: 'Minimum 6 characters',
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : () => _submitForm(isDark),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
                        foregroundColor: isDark ? const Color(0xFF1A2744) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 5,
                      ),
                      child: _isSubmitting
                          ? CircularProgressIndicator(color: isDark ? const Color(0xFF1A2744) : Colors.white)
                          : const Text(
                              'Register Student',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    bool isPassword = false,
    String? hintText,
    bool isDark = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          obscureText: isPassword,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: isDark ? const Color(0xFFD4AF37) : Colors.grey, size: 20),
            hintText: hintText ?? 'Enter $label',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
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

  Widget _buildGenderDropdown(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedGender,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              isExpanded: true,
              items: ['Male', 'Female', 'Other'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                );
              }).toList(),
              onChanged: (v) {
                setState(() => _selectedGender = v!);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.grey)),
          const SizedBox(width: 8),
          Text(
            value, 
            style: TextStyle(
              fontSize: 14, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.white : const Color(0xFF1A2744),
            ),
          ),
        ],
      ),
    );
  }
}
