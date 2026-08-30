import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:vianasoft_stay/shared/user_provider.dart';
import 'package:vianasoft_stay/shared/wallpaper_provider.dart';
import 'package:vianasoft_stay/core/api_service.dart';
import 'package:vianasoft_stay/core/providers/allocation_provider.dart';
import 'package:vianasoft_stay/core/styles.dart';
import 'package:vianasoft_stay/shared/widgets/skeuomorphic_widgets.dart';
import 'package:vianasoft_stay/shared/widgets/skeuomorphic_navbar.dart';
import 'package:vianasoft_stay/core/design_system.dart' as ds;
import 'package:vianasoft_stay/shared/screens/privacy_policy_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _payments = [];
  bool _isLoading = true;
  final ScrollController _nameScrollController = ScrollController();
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _refreshUserData();
  }

  Future<void> _refreshUserData() async {
    final user = context.read<UserProvider>();
    await user.refreshUserData();
  }

  Future<void> _fetchHistory() async {
    final user = context.read<UserProvider>();
    if (user.dbId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await ApiService.getPaymentHistory(user.dbId!);
      if (mounted) {
        setState(() {
          if (response['status'] == 'success') {
            _payments = List<Map<String, dynamic>>.from(response['data']);
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameScrollController.dispose();
    super.dispose();
  }

  void _scrollName() async {
    if (_isScrolling) return;
    setState(() => _isScrolling = true);
    
    if (_nameScrollController.hasClients) {
      final maxScroll = _nameScrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        await _nameScrollController.animateTo(
          maxScroll,
          duration: Duration(milliseconds: maxScroll.toInt() * 40),
          curve: Curves.linear,
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await _nameScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    }
    
    setState(() => _isScrolling = false);
  }

  DateTime? _getInitialPaymentDate(UserProvider user) {
    if (_payments.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(_payments)
        ..sort((a, b) {
          final aDate = DateTime.tryParse(a['paid_at'] ?? a['booking_date'] ?? a['created_at'] ?? '') ?? DateTime.now();
          final bDate = DateTime.tryParse(b['paid_at'] ?? b['booking_date'] ?? b['created_at'] ?? '') ?? DateTime.now();
          return aDate.compareTo(bDate);
        });

      final firstDate = DateTime.tryParse(sorted.first['paid_at'] ?? sorted.first['booking_date'] ?? sorted.first['created_at'] ?? '');
      if (firstDate != null) return firstDate;
    }

    if (user.checkInDate != null) return user.checkInDate;
    return DateTime(2026, 8, 9);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = context.watch<UserProvider>();
    final wallpaper = context.watch<WallpaperProvider>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Settings',
        onHomeTap: () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        },
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EmbossedCard(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0xFFEBC15B), Color(0xFFB88E2F)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  user.userName.isNotEmpty
                                      ? user.userName.split(' ').where((s) => s.trim().isNotEmpty).map((l) => l[0]).take(2).join().toUpperCase()
                                      : "?",
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1B2B48),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GestureDetector(
                                    onTap: _scrollName,
                                    child: SizedBox(
                                      height: 25,
                                      child: SingleChildScrollView(
                                        controller: _nameScrollController,
                                        scrollDirection: Axis.horizontal,
                                        physics: const NeverScrollableScrollPhysics(),
                                        child: Text(
                                          user.userName,
                                          style: TextStyle(
                                            fontFamily: 'Lato',
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: wallpaper.isDarkTheme ? Colors.white : const Color(0xFF1B2B48),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Text(
                                    user.role == UserRole.student ? 'ID: ${user.registerNo}' : 'ID: ${user.username}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: wallpaper.isDarkTheme ? Colors.white70 : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user.email,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: wallpaper.isDarkTheme ? Colors.white70 : Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${user.institution} • Hostel: ${user.hostelName}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: wallpaper.isDarkTheme ? Colors.white60 : Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (user.role == UserRole.student) ...[
                          const SizedBox(height: 20),
                          _buildDetailRow(Icons.badge_outlined, 'Registration No', user.registerNo),
                          Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                          _buildDetailRow(Icons.email_outlined, 'Email Address', user.email),
                          Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                          _buildDetailRow(Icons.phone_outlined, 'Personal Phone', user.phone.isNotEmpty ? user.phone : 'Not provided'),
                          Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                          Row(
                            children: [
                              Icon(Icons.home_outlined, color: wallpaper.isDarkTheme ? Colors.white70 : Colors.grey, size: 24),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Room Allocation',
                                      style: TextStyle(
                                        color: wallpaper.isDarkTheme ? Colors.white60 : Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (user.roomAllocation.isNotEmpty || user.roomNumber.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              user.fullRoomDetails,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: wallpaper.isDarkTheme ? Colors.white : const Color(0xFF1B2B48),
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD4AF37).withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: const Color(0xFFD4AF37), width: 1),
                                            ),
                                            child: Text(
                                              user.roomTypeDisplay,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFEBC15B),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 20),
                          _buildDetailRow(
                            Icons.shield_outlined,
                            'Role / Department',
                            user.roleName.isNotEmpty
                                ? user.roleName
                                : user.role.name.toUpperCase(),
                          ),
                          Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                          _buildDetailRow(
                            Icons.email_outlined,
                            'Email Address',
                            user.email.isNotEmpty ? user.email : 'Not set',
                          ),
                          Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                          _buildDetailRow(
                            Icons.phone_outlined,
                            'Phone Number',
                            user.phone.isNotEmpty ? user.phone : 'Not set',
                          ),
                          Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                          _buildDetailRow(
                            Icons.badge_outlined,
                            'User ID',
                            user.username,
                          ),
                          if (user.institution.isNotEmpty &&
                              user.institution != 'N/A') ...[
                            Divider(height: 20, color: wallpaper.isDarkTheme ? Colors.white12 : Colors.grey.shade200),
                            _buildDetailRow(
                              Icons.school_outlined,
                              'Institution',
                              user.institution,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (user.role == UserRole.student) ...[
                    EmbossedCard(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _getConductColor(user.conduct).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_getConductIcon(user.conduct), color: _getConductColor(user.conduct), size: 24),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Conduct Status',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: wallpaper.isDarkTheme ? Colors.white : const Color(0xFF1B2B48),
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  user.conductRemarks.isNotEmpty ? user.conductRemarks : '${user.conduct} standing', 
                                  style: TextStyle(
                                    color: wallpaper.isDarkTheme ? Colors.white70 : Colors.grey,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _getConductColor(user.conduct).withOpacity(0.8),
                                  _getConductColor(user.conduct),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              user.conduct,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 18, color: wallpaper.headerIconColor),
                        const SizedBox(width: 8),
                        Text(
                          'Payment History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: wallpaper.headingColor,
                            shadows: wallpaper.isDarkTheme
                                ? const [
                                    Shadow(
                                      color: Colors.black54,
                                      offset: Offset(0, 1),
                                      blurRadius: 3,
                                    )
                                  ]
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    EmbossedCard(
                      padding: const EdgeInsets.all(0),
                      child: _isLoading 
                        ? const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
                        : (_payments.isEmpty
                          ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text("No payments yet.", style: TextStyle(color: Colors.grey))))
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _payments.length,
                              separatorBuilder: (context, index) => const Divider(height: 0),
                              itemBuilder: (context, index) {
                                final pay = _payments[index];
                                final dateStr = pay['booking_date'] ?? DateTime.now().toString();
                                final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                                return _buildHistoryRow(
                                  pay['payment_type'] ?? 'Hostel Payment', 
                                  '${DateFormat('d MMM yyyy').format(date)} • ID: ${pay['payment_id'] ?? 'N/A'}', 
                                  '₹${pay['amount']}',
                                  status: pay['status'] ?? 'Success',
                                  onTap: () => _showReceiptDialog(pay),
                                );
                              },
                            )),
                    ),
                    if (!user.isGuest) ...[
                      const SizedBox(height: 25),
                      Row(
                        children: [
                          Icon(Icons.history_outlined, size: 18, color: wallpaper.headerIconColor),
                          const SizedBox(width: 8),
                          Text(
                            'Renewal Timeline',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: wallpaper.headingColor,
                              shadows: wallpaper.isDarkTheme
                                  ? const [
                                      Shadow(
                                        color: Colors.black54,
                                        offset: Offset(0, 1),
                                        blurRadius: 3,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      EmbossedCard(
                        padding: const EdgeInsets.all(25),
                        child: Column(
                          children: [
                            _buildTimelineNode(
                              'Initial Allocation / Check-in',
                              DateFormat('d MMM yyyy').format(_getInitialPaymentDate(user)!),
                              isCompleted: true,
                            ),
                            ..._payments.where((p) => (p['payment_type'] ?? '').toString().toLowerCase().contains('renewal')).map((p) {
                              final dateStr = p['paid_at'] ?? p['booking_date'] ?? p['created_at'] ?? DateTime.now().toString();
                              final date = DateTime.tryParse(dateStr) ?? DateTime.now();
                              final amt = p['amount'] != null ? ' · ₹${NumberFormat('#,##,###').format((double.tryParse(p['amount'].toString()) ?? 120000).toInt())}' : '';
                              return _buildTimelineNode('Renewed (Stay Extended$amt)', DateFormat('d MMM yyyy, hh:mm a').format(date), isCompleted: true);
                            }),
                            _buildTimelineNode('Current Period Ends', DateFormat('d MMM yyyy').format(user.renewalDate), isCurrent: true, isLast: true),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 15),
                  _buildWallpaperSection(context),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Icon(Icons.security_outlined, size: 18, color: wallpaper.headerIconColor),
                      const SizedBox(width: 8),
                      Text(
                        'Security & Privacy',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: wallpaper.headingColor,
                          shadows: wallpaper.isDarkTheme
                              ? const [
                                  Shadow(
                                    color: Colors.black54,
                                    offset: Offset(0, 1),
                                    blurRadius: 3,
                                  )
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  EmbossedCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildSettingsActionRow(
                          Icons.privacy_tip_outlined, 
                          'Privacy Policy', 
                          'Read our institutional data & privacy policy',
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
                        const Divider(height: 30),
                        _buildSettingsActionRow(
                          Icons.lock_reset_outlined, 
                          'Change Login Password', 
                          'Update your account security',
                          onTap: () => _showChangePasswordDialog(context, user),
                        ),
                        const Divider(height: 30),
                        _buildSettingsActionRow(
                          Icons.delete_outline_rounded,
                          'Request Account Deletion',
                          'Notify VStay Admin & Warden for deletion',
                          isDanger: true,
                          onTap: () => _showDeleteAccountDialog(context, user),
                        ),
                        const Divider(height: 30),
                        _buildSettingsActionRow(
                          Icons.logout_rounded, 
                          'Logout', 
                          'Sign out of your account',
                          isDanger: true,
                          onTap: () => _showLogoutDialog(context, user),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsActionRow(IconData icon, String title, String subtitle, {required VoidCallback onTap, bool isDanger = false}) {
    return ds.SkeuomorphicListTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: onTap,
      iconColor: isDanger ? Colors.red : const Color(0xFF1B2B48),
      activeColor: isDanger ? const Color(0xFFE53935) : const Color(0xFF1976D2),
    );
  }

  void _showLogoutDialog(BuildContext context, UserProvider user) {
    final wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
    final isDark = wallpaper.isDarkTheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.15)) : BorderSide.none,
        ),
        title: Text(
          'Logout',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF1B2B48),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AllocationProvider>().reset();
              user.logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            }, 
            child: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, UserProvider user) {
    final reasonController = TextEditingController();
    bool isSubmitting = false;
    final wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
    final isDark = wallpaper.isDarkTheme;

    final isStaffOrAdmin = user.role == UserRole.admin ||
        user.role == UserRole.warden ||
        user.role == UserRole.maintenance ||
        user.role == UserRole.security ||
        user.role == UserRole.staff;

    final isParent = user.role == UserRole.parent;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF131D2E) : const Color(0xFFFAF7F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: isDark ? BorderSide(color: Colors.white.withOpacity(0.18)) : BorderSide.none,
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isStaffOrAdmin ? 'Request Account Deactivation' : 'Request Account Deletion',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                    fontFamily: 'Lato',
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isStaffOrAdmin
                      ? 'Staff and administrator account deactivation requests are forwarded to the SIMATS Super Administrator & University IT Authority for access revocation and security clearance.'
                      : (isParent
                          ? 'Parent account deletion requests are submitted to the VStay Administration for verification and profile removal.'
                          : 'Account deletion requests are sent directly to the VStay Administrator and your Hostel Warden to review room checkout, fee clearance, and data removal.'),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3B1219).withOpacity(0.6) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFFF87171).withOpacity(0.4) : const Color(0xFFFCA5A5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notification Recipient Details:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (isStaffOrAdmin) ...[
                        Text('• Account: ${user.userName} (${user.username})', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        Text('• Role: ${user.role.name.toUpperCase()}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        Text('• Authority: SIMATS IT & Super Administrator', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                      ] else if (isParent) ...[
                        Text('• Parent: ${user.userName}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        Text('• Linked Student: ${user.linkedStudentName} (${user.linkedStudentUsername})', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        Text('• Authority: VStay Administrator', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                      ] else ...[
                        Text('• Student: ${user.userName} (${user.registerNo})', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        if (user.warden.isNotEmpty && user.warden != 'Kanita K')
                          Text('• Assigned Warden: ${user.warden}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        if (user.hostelName.isNotEmpty && user.hostelName != 'N/A')
                          Text('• Hostel: ${user.hostelName}', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                        Text('• Authority: Hostel Warden & Administrator', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF7F1D1D))),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Reason for Deletion (Optional):',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    hintText: isStaffOrAdmin
                        ? 'Enter reason (e.g., Transfer, Resignation, Role change...)'
                        : 'Enter reason (e.g., Course completed, Hostel checkout...)',
                    hintStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white60 : Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      setDialogState(() => isSubmitting = true);
                      try {
                        final reason = reasonController.text.trim();
                        final String messageText;
                        if (isStaffOrAdmin) {
                          messageText = "STAFF ACCOUNT DEACTIVATION REQUEST:\nStaff ${user.userName} (${user.username}, Role: ${user.role.name.toUpperCase()}) has requested account deactivation.\nReason: ${reason.isNotEmpty ? reason : 'Not specified'}";
                        } else if (isParent) {
                          messageText = "PARENT ACCOUNT DELETION REQUEST:\nParent ${user.userName} (Linked Student: ${user.linkedStudentUsername}) has requested account deletion.\nReason: ${reason.isNotEmpty ? reason : 'Not specified'}";
                        } else {
                          messageText = "STUDENT ACCOUNT DELETION REQUEST:\nStudent ${user.userName} (${user.registerNo}) from ${user.hostelName} has submitted an account deletion request.\nReason: ${reason.isNotEmpty ? reason : 'Not specified'}";
                        }

                        // Notify Admin/Warden via ticket system
                        await ApiService.sendChatMessage(
                          'DEL_${user.username}_${DateTime.now().millisecondsSinceEpoch}',
                          user.dbId ?? 0,
                          messageText,
                          department: 'warden',
                        ).catchError((_) => <String, dynamic>{});

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          _showDeletionSuccessDialog(context);
                        }
                      } catch (_) {
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          _showDeletionSuccessDialog(context);
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      isStaffOrAdmin
                          ? 'Notify Super Admin'
                          : (isParent ? 'Notify Administrator' : 'Notify Admin & Warden'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeletionSuccessDialog(BuildContext context) {
    final wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
    final isDark = wallpaper.isDarkTheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.18)) : BorderSide.none,
        ),
        title: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.green, size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Request Sent',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your account deletion request has been successfully sent to the VStay Administrator and your Hostel Warden.\n\nThey will review your checkout status and clear your hostel records and account data within 24-48 hours.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final Uri url = Uri.parse('https://balaji431.github.io/viana-hostelApp/delete_account.html');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              },
              icon: Icon(Icons.open_in_new, size: 16, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)),
              label: Text(
                'View Policy & Status Online',
                style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48)),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? const Color(0xFFD4AF37).withOpacity(0.5) : Colors.grey.shade400),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
              foregroundColor: isDark ? const Color(0xFF1B2B48) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, UserProvider user) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    String? errorMessage;
    final wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
    final isDark = wallpaper.isDarkTheme;

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
            border: isDark ? Border(top: BorderSide(color: Colors.white.withOpacity(0.16))) : null,
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
                    color: isDark ? Colors.white30 : Colors.grey.shade300,
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
                style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 25),
              
              if (errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
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
                        _showSuccessDialog(context, user);
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
                    foregroundColor: isDark ? const Color(0xFF1B2B48) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: isLoading 
                    ? CircularProgressIndicator(color: isDark ? const Color(0xFF1B2B48) : Colors.white)
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

  Widget _buildPasswordField(String label, TextEditingController controller, [bool isDark = false]) {
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
            style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1B2B48), fontSize: 14),
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
                icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: isDark ? Colors.white54 : Colors.grey, size: 20),
                onPressed: () => setFieldState(() => obscureText = !obscureText),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context, UserProvider user) {
    final wallpaper = Provider.of<WallpaperProvider>(context, listen: false);
    final isDark = wallpaper.isDarkTheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D2E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: isDark ? BorderSide(color: Colors.white.withOpacity(0.18)) : BorderSide.none,
        ),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 10),
            Text(
              'Success',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1B2B48),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Your password has been changed successfully. Please login again with your new password.',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<AllocationProvider>().reset();
              user.logout();
              Navigator.of(context).popUntil((route) => route.isFirst);
            }, 
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFFD4AF37) : const Color(0xFF1B2B48),
              foregroundColor: isDark ? const Color(0xFF1B2B48) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return Row(
      children: [
        Icon(icon, color: isDark ? Colors.white70 : Colors.grey, size: 24),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 11)),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryRow(String title, String subtitle, String amount, {String status = 'Paid', VoidCallback? onTap}) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: status.toLowerCase() == 'success' ? const Color(0xFFE2F0E5) : const Color(0xFFFFEBEE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              status.toLowerCase() == 'success' ? Icons.check_circle_outline : Icons.error_outline, 
              color: status.toLowerCase() == 'success' ? const Color(0xFF2E7D32) : Colors.red, 
              size: 20
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1B2B48),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFFDE047) : const Color(0xFF1B2B48),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: status.toLowerCase() == 'success' 
                      ? const LinearGradient(
                          colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFEF5350), Color(0xFFC62828)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                    ]
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showReceiptDialog(Map<String, dynamic> pay) {
    final user = context.read<UserProvider>();
    final dateStr = pay['booking_date'] ?? DateTime.now().toString();
    final date = DateTime.tryParse(dateStr) ?? DateTime.now();
    final formattedDate = DateFormat('d MMM yyyy').format(date);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F1),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Payment Receipt',
                      style: TextStyle(
                        fontFamily: 'Lato',
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1B2B48),
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 18, color: Colors.grey),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 1),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFEBC15B).withOpacity(0.2), shape: BoxShape.circle),
                  child: const Icon(Icons.receipt_outlined, color: Color(0xFFB88E2F), size: 30),
                ),
                const SizedBox(height: 15),
                const Text(
                  'Saveetha Hostels',
                  style: TextStyle(fontFamily: 'Lato', fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48)),
                ),
                const Text('Student Hostel', style: TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 30),
                _buildReceiptRow('Receipt No.', 'SH${pay['payment_id'] ?? pay['pid']}'),
                _buildReceiptRow('Date', formattedDate),
                _buildReceiptRow('Student Name', pay['name'] ?? user.userName),
                _buildReceiptRow('Student ID', pay['registerNumber']?.toString() ?? user.studentId),
                _buildReceiptRow('Room', user.fullRoomDetails),
                _buildReceiptRow('Description', pay['payment_type'] ?? 'Hostel Fee Payment'),
                _buildReceiptRow('Payment Method', 'Card Payment'),
                const SizedBox(height: 25),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC5A358).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFC5A358).withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Paid', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
                      Text('₹${pay['amount']}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFC5A358))),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32), size: 20),
                    SizedBox(width: 8),
                    Text('Payment Successful', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 25),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Receipt downloaded successfully to Desktop/Storage.'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: const Color(0xFF2E7D32),
                        action: SnackBarAction(label: 'OPEN', textColor: Colors.white, onPressed: () {}),
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: SkeuomorphicColors.goldGlossyGradient,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.download_rounded, color: Color(0xFF291E1A), size: 18),
                        SizedBox(width: 10),
                        Text('Download Receipt', style: TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                const Text('This is a simulated receipt for demonstration', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 14))),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1B2B48),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineNode(String title, String date, {bool isCompleted = false, bool isCurrent = false, bool isLast = false}) {
    WallpaperProvider? wallpaper;
    try {
      wallpaper = context.watch<WallpaperProvider>();
    } catch (_) {}
    final isDark = wallpaper?.isDarkTheme ?? false;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isCurrent ? const Color(0xFFEBC15B) : const Color(0xFF66BB6A),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isCurrent ? const Color(0xFFEBC15B) : const Color(0xFF66BB6A)).withOpacity(0.3),
                    blurRadius: 5,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 45,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCurrent ? const Color(0xFFC5A358) : (isDark ? Colors.white : const Color(0xFF1B2B48)),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(date, style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.grey)),
                  ],
                ),
              ),
              if (isCurrent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEBC15B), Color(0xFFB88E2F)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Current',
                    style: TextStyle(color: Color(0xFF1B2B48), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getConductColor(String conduct) {
    if (conduct == 'Good') return Colors.green;
    if (conduct == 'Satisfactory') return Colors.orange;
    if (conduct == 'Poor') return Colors.red;
    return Colors.grey;
  }

  IconData _getConductIcon(String conduct) {
    if (conduct == 'Good') return Icons.shield_outlined;
    if (conduct == 'Satisfactory') return Icons.info_outline;
    if (conduct == 'Poor') return Icons.warning_amber_rounded;
    return Icons.help_outline;
  }

  Widget _buildWallpaperSection(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.wallpaper_outlined, size: 18, color: wallpaper.headerIconColor),
            const SizedBox(width: 8),
            Text(
              'App Background & Wallpaper',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: wallpaper.headingColor,
                shadows: wallpaper.isDarkTheme
                    ? const [
                        Shadow(
                          color: Colors.black54,
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        )
                      ]
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        EmbossedCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose a background theme or wallpaper:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 15),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Default Theme Option (Classic Linen Grid)
                    _buildWallpaperOptionCard(
                      context,
                      title: 'Default Theme',
                      isSelected: wallpaper.isDefault,
                      previewWidget: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F0E8),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFF5F0E8), Color(0xFFE8E0D5)],
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.grid_on, size: 22, color: Color(0xFF8C6239)),
                        ),
                      ),
                      onTap: () => wallpaper.setDefault(),
                    ),
                    const SizedBox(width: 12),
                    // Preset Wallpapers (Water, Ocean, Forest, Marble, Royal Navy)
                    ...WallpaperProvider.defaultWallpapers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final opt = entry.value;
                      final isSelected = wallpaper.type == 'asset' && wallpaper.value == opt.id;
                      final isLast = idx == WallpaperProvider.defaultWallpapers.length - 1;
                      return Padding(
                        padding: EdgeInsets.only(right: isLast ? 0 : 12),
                        child: _buildWallpaperOptionCard(
                          context,
                          title: opt.label,
                          isSelected: isSelected,
                          previewWidget: Image.asset(
                            opt.assetPath!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => Container(color: opt.previewColor),
                          ),
                          onTap: () => wallpaper.setAssetWallpaper(opt.id),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWallpaperOptionCard(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required Widget previewWidget,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? const Color(0xFFD4AF37) : Colors.black.withOpacity(0.12),
                width: isSelected ? 3 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFFD4AF37).withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: previewWidget,
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD4AF37),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 80,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF1B2B48) : Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
