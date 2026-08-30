import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../wallpaper_provider.dart';
import '../../core/styles.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  final bool showAppBar;

  const PrivacyPolicyScreen({super.key, this.showAppBar = true});

  @override
  Widget build(BuildContext context) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: showAppBar
            ? AppBar(
                backgroundColor: isDark ? const Color(0xFF131D2E).withOpacity(0.85) : const Color(0xFF1A2744),
                foregroundColor: Colors.white,
                elevation: 0,
                centerTitle: true,
                title: const Text(
                  'Privacy Policy',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                children: [
                  // Header card
                  _buildHeaderCard(isDark),
                  const SizedBox(height: 16),

                  // Apple Review & No Tracking Guarantee Badge
                  _buildTrackingNoticeCard(isDark),
                  const SizedBox(height: 16),

                  // Sections
                  _buildSection(
                    icon: Icons.info_outline_rounded,
                    title: '1. Overview & Scope',
                    content:
                        'This Privacy Policy applies to the VStay mobile application and web portal ("App"), operated for student hostel administration, room allocation, maintenance management, and campus security by SIMATS (Saveetha Institute of Medical and Technical Sciences).\n\n'
                        'By using VStay, you acknowledge and agree to the collection, processing, and storage of information described in this Policy.',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildSection(
                    icon: Icons.person_search_outlined,
                    title: '2. Information We Collect',
                    content:
                        'We collect only information necessary for institutional hostel management and student accommodation:\n\n'
                        '• Student & User Profile: Full Name, University Registration Number, College Email Address, Phone Number, Assigned Hostel, Building, Floor, and Room Number.\n'
                        '• Account & Auth Data: Google Sign-In authentication identifiers (strictly restricted to registered institutional or authorized guest accounts).\n'
                        '• Temporary Stay Data: Guest names, dates of stay, proof documents, and emergency contact details for short-term visitors.\n'
                        '• Support & Maintenance Tickets: Maintenance issues, student complaints, request logs, and chat messages with wardens and security officers.\n'
                        '• Push Notification Token: Firebase Cloud Messaging (FCM) device tokens used solely for critical hostel alerts and status updates.',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildSection(
                    icon: Icons.verified_user_outlined,
                    title: '3. Apple Guideline 5.1.2 & Zero Tracking Guarantee',
                    content:
                        '• NO Third-Party Advertising: VStay contains zero advertisements.\n'
                        '• NO Cross-App Tracking: We do not track your activity across other apps or websites.\n'
                        '• NO Data Broker Sharing: We never sell, monetize, rent, or trade your personal data with third-party data brokers.\n'
                        '• NO IDFA / Ad Identifier Collection: We do not access the Apple Advertising Identifier (IDFA).',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildSection(
                    icon: Icons.settings_suggest_outlined,
                    title: '4. How We Use Your Information',
                    content:
                        'Your data is used strictly for legitimate educational and residential administrative operations:\n\n'
                        '1. Authenticating your identity and granting access to hostel services.\n'
                        '2. Managing room allocations, room changes, and vacation requests.\n'
                        '3. Routing maintenance issues directly to hostel staff and wardens.\n'
                        '4. Sending instant push notifications for safety announcements, approval statuses, and curfew alerts.\n'
                        '5. Enforcing campus security and authorized gate entry.',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildSection(
                    icon: Icons.lock_outline_rounded,
                    title: '5. Data Security & Storage',
                    content:
                        'All communications with VStay backend servers use Transport Layer Security (TLS/HTTPS) with 256-bit encryption. Database access is strictly role-restricted with token-based authorization. Only authorized wardens, security staff, and administrators can access resident information corresponding to their assigned duties.',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildSection(
                    icon: Icons.delete_forever_outlined,
                    title: '6. Account & Data Deletion (Apple Guideline 5.1.1)',
                    content:
                        'In full compliance with Apple App Store Review Guideline 5.1.1(v), users have the right to request the deletion or deactivation of their account and associated personal data:\n\n'
                        '• In-App Deletion Request: You can initiate an account deletion request directly from Settings > Request Account Deletion.\n'
                        '• Email Deletion Request: You may submit a written data deletion request to itsupport@saveetha.com.\n'
                        '• Processing: Requests are processed by SIMATS IT within 30 days after verifying hostel clearance and settling any outstanding dues.',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 14),

                  _buildSection(
                    icon: Icons.contact_support_outlined,
                    title: '7. Contact Us',
                    content:
                        'If you have questions, feedback, or privacy concerns regarding this policy, please reach out to:\n\n'
                        'SIMATS Hostel Administration & IT Department\n'
                        'Saveetha Institute of Medical and Technical Sciences (SIMATS)\n'
                        'Saveetha Nagar, Thandalam, Chennai - 602 105, Tamil Nadu, India\n'
                        'Email: itsupport@saveetha.com | hostel@saveetha.com\n'
                        'Website: https://vstudy.saveetha.com',
                    isDark: isDark,
                  ),
                  const SizedBox(height: 24),

                  // Footer
                  Center(
                    child: Text(
                      '© ${DateTime.now().year} VStay — SIMATS Hostel Portal. All Rights Reserved.',
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D2E) : null,
        gradient: isDark
            ? null
            : const LinearGradient(
                colors: [Color(0xFF1A2744), Color(0xFF2C3E6B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(16),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.14)) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VStay Privacy Policy',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'SIMATS Institutional Hostel Application',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          const Text(
            'Last Updated: August 2026 | Effective Date: August 2026',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingNoticeCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF064E3B).withOpacity(0.4) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF059669).withOpacity(0.6) : const Color(0xFFA5D6A7),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            color: isDark ? const Color(0xFF34D399) : const Color(0xFF2E7D32),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zero Tracking & Data Privacy Commitment',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'VStay is strictly an institutional accommodation portal. We do not track users across third-party websites or apps, do not display advertisements, and do not share personal information with commercial data brokers.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white.withOpacity(0.85) : const Color(0xFF2E7D32),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String content,
    bool isDark = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.14) : Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1A2744)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1A2744),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: isDark ? Colors.white.withOpacity(0.1) : null),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white70 : const Color(0xFF424242),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
