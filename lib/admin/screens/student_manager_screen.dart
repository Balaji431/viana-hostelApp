import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
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

  Future<void> _submitForm() async {
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text('Registration Success'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Student has been registered successfully.'),
                  const SizedBox(height: 20),
                  const Text('Login Credentials:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _buildCredentialRow('Register No:', _registerNoController.text),
                  _buildCredentialRow('Password:', _passwordController.text),
                  const SizedBox(height: 15),
                  const Text(
                    'Note: The student can change their password after logging in from the Settings page.',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
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
                  child: const Text('Great!', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Register Number is required';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    isPassword: true,
                    hintText: 'Min 6 chars, 1 Capital, 1 Special, 1 Num',
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'Minimum 6 characters required';
                      if (!RegExp(r'^(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#\$&*~]).*$').hasMatch(v)) {
                        return 'Must have 1 Capital, 1 Number, 1 Special char';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _emailController,
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!v.endsWith('@gmail.com')) return 'Only @gmail.com addresses allowed';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _phoneController,
                    label: 'Phone Number',
                    icon: Icons.phone_android_outlined,
                    keyboardType: TextInputType.phone,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Phone number is required';
                      if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) return 'Enter exactly 10 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildGenderDropdown(),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _contactNumberController,
                    label: 'Contact Number (Parent/Guardian)',
                    icon: Icons.contact_phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _addressController,
                    label: 'Address',
                    icon: Icons.home_outlined,
                    keyboardType: TextInputType.multiline,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A2744),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        elevation: 5,
                      ),
                      child: _isSubmitting
                          ? const CircularProgressIndicator(color: Colors.white)
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
          ],
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
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          obscureText: isPassword,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: Colors.grey, size: 20),
            hintText: hintText ?? 'Enter $label',
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1A2744), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Gender',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A2744),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedGender,
              isExpanded: true,
              items: ['Male', 'Female', 'Other'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
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

  Widget _buildCredentialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A2744))),
        ],
      ),
    );
  }
}
