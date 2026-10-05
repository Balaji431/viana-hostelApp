import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/warden_widgets.dart' show LinenBackground;
import 'warden_face_enrollment_screen.dart';

class WardenBiometricScreen extends StatefulWidget {
  final bool showBackButton;
  const WardenBiometricScreen({super.key, this.showBackButton = false});

  @override
  State<WardenBiometricScreen> createState() => _WardenBiometricScreenState();
}

class _WardenBiometricScreenState extends State<WardenBiometricScreen> {
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String _filter = 'all'; // all, punched, missing, parent_msg
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  int _totalStudents = 0;
  int _punchedCount = 0;
  int _missingCount = 0;
  int _parentMsgReachedCount = 0;
  bool _isTriggeringAlerts = false;

  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _fetchBiometricSummary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchBiometricSummary({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final user = context.read<UserProvider>();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final res = await ApiService.getBiometricWardenSummary(
        date: dateStr,
        wardenUsername: user.username,
      );

      if (mounted) {
        if (res['status'] == 'success') {
          final summary = res['summary'] ?? {};
          final rawData = List<Map<String, dynamic>>.from(res['data'] ?? []);

          setState(() {
            _totalStudents = summary['total_students'] ?? rawData.length;
            _punchedCount = summary['fingerprint_punched'] ?? 0;
            _missingCount = summary['fingerprint_missing'] ?? 0;
            _parentMsgReachedCount = summary['parent_msg_reached'] ?? 0;
            _students = rawData;
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final isDark = context.read<WallpaperProvider>().isDarkTheme;

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'SELECT ATTENDANCE DATE',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Color(0xFFD4AF37),
                    onPrimary: Colors.black,
                    surface: Color(0xFF1E293B),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Color(0xFFD4AF37),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Color(0xFF1B2B48),
                  ),
            dialogTheme: DialogThemeData(
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchBiometricSummary();
    }
  }

  void _stepDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _fetchBiometricSummary();
  }

  Future<void> _triggerCutoffAlerts() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final user = context.read<UserProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.notification_important_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text('Send 6:00 PM Alerts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'This will check all students against the 6:00 PM biometric cutoff for $dateStr.\n\nAny student who did not place their fingerprint punch before 6:00 PM will be marked Absent, and a push notification with a chat alert will be sent directly to their parents.\n\nProceed to send alerts?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send Alerts'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isTriggeringAlerts = true);
    try {
      final res = await ApiService.triggerBiometricCutoffAlerts(
        date: dateStr,
        cutoffTime: '18:00:00',
        wardenUsername: user.username,
        force: true,
      );

      if (!mounted) return;

      if (res['status'] == 'success') {
        final sent = res['alerts_sent_now'] ?? 0;
        final already = res['already_alerted'] ?? 0;
        final missing = res['absent_missing'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Sent $sent parent push notifications ($already already alerted today) out of $missing absent students.'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchBiometricSummary(showLoading: false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ${res['message'] ?? 'Could not trigger alerts'}'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error triggering alerts: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTriggeringAlerts = false);
    }
  }

  List<Map<String, dynamic>> get _filteredStudents {
    return _students.where((s) {
      // 1. Status Filter
      if (_filter == 'punched' && s['is_punched'] != true) return false;
      if (_filter == 'missing' && s['is_punched'] == true) return false;
      if (_filter == 'parent_msg' && s['parent_msg_reached'] != true) return false;

      // 2. Search Query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = (s['name'] ?? '').toString().toLowerCase();
        final regNo = (s['register_number'] ?? '').toString().toLowerCase();
        final roomNo = (s['room_no'] ?? '').toString().toLowerCase();
        final hostel = (s['hostel_name'] ?? '').toString().toLowerCase();
        return name.contains(query) || regNo.contains(query) || roomNo.contains(query) || hostel.contains(query);
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1522) : const Color(0xFFF4F6F9),
      appBar: SkeuomorphicNavBar(
        title: 'Biometric Attendance',
        onBack: widget.showBackButton ? () => Navigator.of(context).pop() : null,
      ),
      body: LinenBackground(
        child: RefreshIndicator(
          onRefresh: () => _fetchBiometricSummary(showLoading: false),
          color: const Color(0xFFD4AF37),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              // 1. Top Date Picker Header
              SliverToBoxAdapter(
                child: _buildDateSelectorSection(isDark),
              ),

              // 2. Face Enrollment / Registration Action Banner
              SliverToBoxAdapter(
                child: _buildFaceEnrollmentActionBanner(isDark),
              ),

              // 3. 6:00 PM Cutoff Rule & Parent Push Alert Trigger Banner
              SliverToBoxAdapter(
                child: _buildCutoffRuleAndTriggerBanner(isDark),
              ),

              // 3. The 3 Primary Count Cards for that Selected Day
              SliverToBoxAdapter(
                child: _buildPrimaryCountCards(isDark),
              ),

              // 3. Search & Filter Bar
              SliverToBoxAdapter(
                child: _buildSearchAndFilterSection(isDark),
              ),

              // 4. Student Records List
              _isLoading
                  ? const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                        ),
                      ),
                    )
                  : _filteredStudents.isEmpty
                      ? SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(isDark),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                return _buildStudentRecordCard(_filteredStudents[index], isDark);
                              },
                              childCount: _filteredStudents.length,
                            ),
                          ),
                        ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== DATE SELECTOR ====================

  Widget _buildDateSelectorSection(bool isDark) {
    final isToday = DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Previous Day Button
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: const Color(0xFFD4AF37),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Previous Day',
            onPressed: () => _stepDate(-1),
          ),
          const SizedBox(width: 8),

          // Date Display & Picker Tap
          Expanded(
            child: InkWell(
              onTap: () => _pickDate(context),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: Color(0xFFD4AF37), size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        DateFormat('EEEE, dd MMM yyyy').format(_selectedDate),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                        ),
                        child: const Text(
                          'TODAY',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Next Day Button
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: const Color(0xFFD4AF37),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Next Day',
            onPressed: () => _stepDate(1),
          ),
        ],
      ),
    );
  }

  // ==================== FACE BIOMETRIC ENROLLMENT BANNER ====================

  Widget _buildFaceEnrollmentActionBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
              )
            : const LinearGradient(
                colors: [Color(0xFF1E2F5E), Color(0xFF152244)],
              ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.6),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
            ),
            child: const Icon(
              Icons.face_retouching_natural_rounded,
              color: Color(0xFFD4AF37),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STUDENT FACE REGISTRATION',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Enroll Student Biometric Face',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Verify student room allocation and complete in-person biometric registration.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (ApiService.enableFaceBiometric) ...[
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1B2B48),
                elevation: 2,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WardenFaceEnrollmentScreen(),
                  ),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.how_to_reg_rounded, size: 16),
                  SizedBox(width: 5),
                  Text(
                    'Enroll Face',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 6:00 PM CUTOFF RULE & ALERT TRIGGER BANNER ====================

  Widget _buildCutoffRuleAndTriggerBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.4 : 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.alarm_rounded, size: 14, color: Color(0xFFF59E0B)),
                    SizedBox(width: 5),
                    Text(
                      'CUTOFF: 6:00 PM',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _isTriggeringAlerts
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)),
                    )
                  : InkWell(
                      onTap: _triggerCutoffAlerts,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notification_important_rounded, size: 14, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'Alert Parents (Absent)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Students who do not place their fingerprint punch before 6:00 PM are marked Absent and parent push notifications are sent.',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? Colors.white70 : const Color(0xFF92400E),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3 PRIMARY COUNT CARDS ====================

  Widget _buildPrimaryCountCards(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          // Total Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.group_rounded, size: 16, color: Color(0xFFD4AF37)),
                    const SizedBox(width: 6),
                    Text(
                      'Total Assigned Students:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                Text(
                  '$_totalStudents',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD4AF37),
                  ),
                ),
              ],
            ),
          ),

          // The 3 Key Count Cards Grid
          Row(
            children: [
              // Card 1: Put Fingerprint (Punched)
              Expanded(
                child: _buildMetricCard(
                  title: 'Fingerprint\nPunched',
                  count: _punchedCount,
                  subtitle: 'Punched',
                  icon: Icons.fingerprint_rounded,
                  color: const Color(0xFF10B981),
                  isSelected: _filter == 'punched',
                  onTap: () => setState(() => _filter = _filter == 'punched' ? 'all' : 'punched'),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),

              // Card 2: Did NOT Put Fingerprint (Missing)
              Expanded(
                child: _buildMetricCard(
                  title: 'Fingerprint\nMissing',
                  count: _missingCount,
                  subtitle: 'Missing',
                  icon: Icons.fingerprint_outlined,
                  color: const Color(0xFFEF4444),
                  isSelected: _filter == 'missing',
                  onTap: () => setState(() => _filter = _filter == 'missing' ? 'all' : 'missing'),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),

              // Card 3: Messages Reached to Parents
              Expanded(
                child: _buildMetricCard(
                  title: 'Parent Alerts\nDelivered',
                  count: _parentMsgReachedCount,
                  subtitle: 'Delivered',
                  icon: Icons.mark_chat_read_rounded,
                  color: const Color(0xFF3B82F6),
                  isSelected: _filter == 'parent_msg',
                  onTap: () => setState(() => _filter = _filter == 'parent_msg' ? 'all' : 'parent_msg'),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required int count,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: isDark ? 0.25 : 0.12)
              : (isDark ? const Color(0xFF162032) : Colors.white),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : Colors.grey.shade200),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Icon Pill
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),

            // Bold Count
            Text(
              '$count',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF1B2B48),
              ),
            ),
            const SizedBox(height: 4),

            // Title
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.grey.shade700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.25 : 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== SEARCH & FILTER SECTION ====================

  Widget _buildSearchAndFilterSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Column(
        children: [
          // Search Input
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF162032) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1B2B48),
                fontSize: 13.5,
              ),
              decoration: InputDecoration(
                hintText: 'Search by student name, reg no, or room...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                  fontSize: 12.5,
                ),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFD4AF37), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _buildFilterChip('All (${_students.length})', 'all', const Color(0xFFD4AF37), isDark),
                const SizedBox(width: 6),
                _buildFilterChip('Punched ($_punchedCount)', 'punched', const Color(0xFF10B981), isDark),
                const SizedBox(width: 6),
                _buildFilterChip('Missing ($_missingCount)', 'missing', const Color(0xFFEF4444), isDark),
                const SizedBox(width: 6),
                _buildFilterChip('Parent Notified ($_parentMsgReachedCount)', 'parent_msg', const Color(0xFF3B82F6), isDark),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Results counter text
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Showing ${_filteredStudents.length} of ${_students.length} students',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, Color color, bool isDark) {
    final isSelected = (_filter == value);
    return InkWell(
      onTap: () => setState(() => _filter = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : (isDark ? const Color(0xFF162032) : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }

  // ==================== STUDENT RECORD CARD ====================

  Widget _buildStudentRecordCard(Map<String, dynamic> student, bool isDark) {
    final isPunched = student['is_punched'] == true;
    final parentMsgReached = student['parent_msg_reached'] == true;
    final name = student['name'] ?? 'Unknown';
    final regNo = student['register_number'] ?? 'N/A';
    final roomNo = student['room_no'] ?? 'N/A';
    final hostel = student['hostel_name'] ?? 'Hostel';
    final punchTime = student['punch_time'] ?? '';
    final parentPhone = student['parent_phone'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF162032) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPunched
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : const Color(0xFFEF4444).withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Status Indicator Avatar
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPunched
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFFEF4444).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isPunched ? Icons.fingerprint_rounded : Icons.fingerprint_outlined,
              color: isPunched ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),

          // Details Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name & Punch Badge Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF1B2B48),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPunched
                            ? const Color(0xFF10B981).withValues(alpha: 0.18)
                            : const Color(0xFFEF4444).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isPunched ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPunched ? Icons.check_circle_rounded : Icons.cancel_rounded,
                            size: 11,
                            color: isPunched ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPunched ? (punchTime.isNotEmpty ? punchTime : 'Punched') : 'Missing',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isPunched ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // Reg No & Room Info
                Row(
                  children: [
                    Text(
                      regNo,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD4AF37),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.grey.shade400),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$hostel • $roomNo',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Parent Notification Status Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: parentMsgReached
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                        : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        parentMsgReached ? Icons.mark_chat_read_rounded : Icons.mail_outline_rounded,
                        size: 13,
                        color: parentMsgReached
                            ? const Color(0xFF3B82F6)
                            : (isDark ? Colors.white38 : Colors.grey),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        parentMsgReached
                            ? 'Msg Reached Parent (Delivered)'
                            : (isPunched ? 'Parent Alert: Not Needed (Present)' : 'Parent Alert: Pending / Not Sent'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: parentMsgReached ? FontWeight.bold : FontWeight.w500,
                          color: parentMsgReached
                              ? const Color(0xFF3B82F6)
                              : (isDark ? Colors.white54 : Colors.grey.shade600),
                        ),
                      ),
                      if (parentPhone.isNotEmpty && parentMsgReached) ...[
                        const SizedBox(width: 6),
                        Text(
                          '($parentPhone)',
                          style: TextStyle(
                            fontSize: 9.5,
                            color: isDark ? Colors.white38 : Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fingerprint_rounded,
            size: 56,
            color: isDark ? Colors.white24 : Colors.grey.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'No student biometric records found',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try selecting another date or clearing your search filters',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
