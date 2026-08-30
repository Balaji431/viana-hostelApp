import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/screens/privacy_policy_screen.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../core/api_service.dart';

class MaintenanceSettingsTab extends StatefulWidget {
  const MaintenanceSettingsTab({super.key});

  @override
  State<MaintenanceSettingsTab> createState() => _MaintenanceSettingsTabState();
}

class _MaintenanceSettingsTabState extends State<MaintenanceSettingsTab> {

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const SkeuomorphicNavBar(
        title: 'Settings',
        rightAction: ProfileButton(),
      ),
      body: LinenBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileHeader(user, isDark),
                  const SizedBox(height: 25),
                  _buildUserDetailsSection(user, isDark),
                  const SizedBox(height: 25),
                  _buildSecuritySection(context, user, isDark),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(UserProvider user, bool isDark) {
    String displayName = user.userName.isEmpty ? '${user.role.name[0].toUpperCase()}${user.role.name.substring(1)} Staff' : user.userName;
    String email = user.email.isEmpty ? 'Not set' : user.email;

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: SkeuomorphicColors.goldGlossyGradient,
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5)),
              ],
            ),
            child: Center(
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : 'M',
                style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF1a2744)),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 22, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.white : const Color(0xFF1A2744),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${user.role.name[0].toUpperCase()}${user.role.name.substring(1)} Staff',
            style: TextStyle(fontSize: 14, color: isDark ? Colors.white70 : Colors.grey[600]),
          ),
          const SizedBox(height: 5),
          Text(
            email,
            style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildUserDetailsSection(UserProvider user, bool isDark) {
    final userDetails = [
      {'label': 'Username', 'value': user.username.isEmpty ? 'N/A' : user.username, 'icon': Icons.person},
      {'label': 'Full Name', 'value': user.userName.isEmpty ? 'N/A' : user.userName, 'icon': Icons.badge},
      {'label': 'Email', 'value': user.email.isEmpty ? 'Not set' : user.email, 'icon': Icons.email},
      {'label': 'Phone', 'value': user.phone.isEmpty ? 'Not set' : user.phone, 'icon': Icons.phone},
      {'label': 'Department', 'value': user.role.name[0].toUpperCase() + user.role.name.substring(1), 'icon': Icons.build},
      {'label': 'Institution', 'value': user.institution.isEmpty ? 'Not set' : user.institution, 'icon': Icons.school},
      {'label': 'Address', 'value': user.address.isEmpty ? 'Not set' : user.address, 'icon': Icons.location_on},
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5, bottom: 15),
            child: Text(
              'USER DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFD4AF37) : Colors.grey[600],
                letterSpacing: 1.2,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: userDetails.asMap().entries.map((entry) {
                final detail = entry.value;
                final isLast = entry.key == userDetails.length - 1;
                
                return Column(
                  children: [
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFF1A2744).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          detail['icon'] as IconData, 
                          color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744), 
                          size: 20,
                        ),
                      ),
                      title: Text(
                        detail['label'] as String,
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey[600]),
                      ),
                      subtitle: Text(
                        detail['value'] as String,
                        style: TextStyle(
                          fontSize: 14, 
                          fontWeight: FontWeight.w600, 
                          color: isDark ? Colors.white : const Color(0xFF1A2744),
                        ),
                      ),
                    ),
                    if (!isLast)
                      Divider(height: 1, indent: 70, endIndent: 20, color: isDark ? Colors.white12 : Colors.grey[300]),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecuritySection(BuildContext context, UserProvider user, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 5, bottom: 15),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: isDark ? const Color(0xFFD4AF37) : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Security & Privacy',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF5D5D5D),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D2E).withOpacity(0.72) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.35 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFF1A2744).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.privacy_tip_outlined, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744), size: 20),
                  ),
                  title: Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A2744))),
                  subtitle: Text('View institutional privacy policy', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 14, color: isDark ? Colors.white60 : Colors.grey),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        settings: const RouteSettings(name: '/privacy-policy'),
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                ),
                Divider(height: 1, indent: 60, color: isDark ? Colors.white12 : Colors.grey.shade300),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFF1A2744).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.settings_backup_restore, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1A2744), size: 20),
                  ),
                  title: Text('Change Login Password', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A2744))),
                  subtitle: Text('Update your account security', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white60 : Colors.grey),
                  onTap: () => _showChangePasswordDialog(context, user, isDark),
                ),
                Divider(height: 1, indent: 70, color: isDark ? Colors.white12 : Colors.grey[300]),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.exit_to_app, color: Colors.red, size: 20),
                  ),
                  title: const Text('Logout', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                  subtitle: Text('Sign out of your account', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: isDark ? Colors.white60 : Colors.grey),
                  onTap: () => _showLogoutDialog(context, user, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, UserProvider user, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isDark ? Colors.white.withOpacity(0.14) : Colors.transparent),
        ),
        title: Text('Logout', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text('Are you sure you want to logout?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              user.logout();
            }, 
            child: const Text('Logout', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, UserProvider user, bool isDark) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 20,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131D2E) : const Color(0xFFF9F6F0),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(30),
              topRight: Radius.circular(30),
            ),
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.transparent),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 25),
              Text(
                'Change Password',
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1B2B48),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Enter your current password and a new one to update.',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 25),
              
              if (errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ),
                    ],
                  ),
                ),

              _buildPasswordField('Current Password', oldPasswordController, isDark),
              const SizedBox(height: 15),
              _buildPasswordField('New Password', newPasswordController, isDark),
              const SizedBox(height: 15),
              _buildPasswordField('Confirm New Password', confirmPasswordController, isDark),
              const SizedBox(height: 30),
              
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    if (newPasswordController.text != confirmPasswordController.text) {
                      setModalState(() => errorMessage = "Passwords do not match");
                      return;
                    }
                    if (newPasswordController.text.length < 6) {
                      setModalState(() => errorMessage = "Password must be at least 6 characters");
                      return;
                    }

                    setModalState(() {
                      isLoading = true;
                      errorMessage = null;
                    });

                    try {
                      final result = await ApiService.changePassword(
                        user.dbId!,
                        oldPasswordController.text,
                        newPasswordController.text,
                        role: user.role.name,
                      );

                      if (result['success']) {
                        Navigator.pop(ctx);
                        _showSuccessDialog(context, user, isDark);
                      } else {
                        setModalState(() {
                          isLoading = false;
                          errorMessage = result['message'] ?? 'Failed to change password';
                        });
                      }
                    } catch (e) {
                      setModalState(() {
                        isLoading = false;
                        errorMessage = 'Server error. Please try again.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        'Update Password', 
                        style: TextStyle(
                          color: isDark ? const Color(0xFF1B2B48) : Colors.white, 
                          fontWeight: FontWeight.bold, 
                          fontSize: 16,
                        ),
                      ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller, bool isDark) {
    bool obscureText = true;
    return StatefulBuilder(
      builder: (context, setFieldState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label, 
            style: TextStyle(
              fontSize: 13, 
              fontWeight: FontWeight.bold, 
              color: isDark ? Colors.white : const Color(0xFF1B2B48),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: obscureText,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              hintText: 'Enter $label',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400, fontSize: 14),
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
                borderSide: BorderSide(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48), width: 1.5),
              ),
              suffixIcon: IconButton(
                icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: isDark ? Colors.white60 : Colors.grey, size: 20),
                onPressed: () => setFieldState(() => obscureText = !obscureText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, UserProvider user, bool isDark) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
            Text('Success', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
        content: Text(
          'Your password has been changed successfully. Please login again with your new password.',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              user.logout();
            }, 
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD4AF37))),
          ),
        ],
      ),
    );
  }
}
