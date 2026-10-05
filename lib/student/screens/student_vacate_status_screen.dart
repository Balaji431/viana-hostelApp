import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../shared/user_provider.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../widgets/student_vacate_modal.dart';

class StudentVacateStatusScreen extends StatefulWidget {
  const StudentVacateStatusScreen({super.key});

  @override
  State<StudentVacateStatusScreen> createState() => _StudentVacateStatusScreenState();
}

class _StudentVacateStatusScreenState extends State<StudentVacateStatusScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isLoading = true;
  bool _isCancelling = false;
  Map<String, dynamic>? _vacateRequest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVacateStatus());
  }

  Future<void> _loadVacateStatus() async {
    setState(() => _isLoading = true);
    final user = Provider.of<UserProvider>(context, listen: false);

    try {
      final res = await ApiService.getStudentVacateStatus(
        studentId: user.dbId,
        regNo: user.username,
      );

      if (mounted) {
        if (res['success'] == true && res['has_request'] == true) {
          setState(() {
            _vacateRequest = res['data'] != null ? Map<String, dynamic>.from(res['data']) : null;
            _isLoading = false;
          });
        } else {
          setState(() {
            _vacateRequest = null;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cancelRequest() async {
    if (_vacateRequest == null) return;
    final reqId = _vacateRequest!['request_id']?.toString() ?? '';
    final user = Provider.of<UserProvider>(context, listen: false);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('Cancel Vacate Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Are you sure you want to withdraw your room vacate request? Your room allocation will remain active.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Request'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isCancelling = true);

    try {
      final res = await ApiService.cancelVacateRequest(
        requestId: reqId,
        regNo: user.username,
      );

      if (mounted) {
        setState(() => _isCancelling = false);
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Vacate request cancelled.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _loadVacateStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Failed to cancel request.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openVacateModal(UserProvider user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StudentVacateModal(
        user: user,
        onSubmitted: () => _loadVacateStatus(),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'cancelled':
        return Colors.grey;
      case 'pending':
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return 'N/A';
    try {
      final dt = DateTime.parse(raw);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = Provider.of<UserProvider>(context);
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;

    final String roomName = user.roomAllocation.isNotEmpty && user.roomAllocation != 'unallocated'
        ? user.roomAllocation
        : 'Unallocated';
    final String hostelName = user.hostelName.isNotEmpty ? user.hostelName : 'Hostel N/A';
    final DateTime? renewalDate = user.renewalDate;
    final int daysRemaining = renewalDate != null ? renewalDate.difference(DateTime.now()).inDays : 0;

    final req = _vacateRequest;
    final status = (req?['status'] ?? '').toString().toLowerCase();

    return LinenGridBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: SkeuomorphicNavBar(
          title: 'Vacate',
          rightAction: IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Status',
            onPressed: _loadVacateStatus,
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            child: RefreshIndicator(
              onRefresh: _loadVacateStatus,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                      ),
                    )
                  : SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Current Allocation Summary Card
                          _buildAllocationCard(
                            roomName: roomName,
                            hostelName: hostelName,
                            renewalDate: renewalDate,
                            daysRemaining: daysRemaining,
                            isDark: isDark,
                          ),

                          const SizedBox(height: 18),

                          // 2. Main Body: Active Request Card OR Vacate Policy / Apply Card
                          if (req != null && status != 'cancelled') ...[
                            _buildRequestStatusCard(req, isDark, user),
                          ] else ...[
                            _buildNewRequestPromoCard(user, isDark, roomName),
                          ],

                          const SizedBox(height: 30),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Allocation Card ---
  Widget _buildAllocationCard({
    required String roomName,
    required String hostelName,
    required DateTime? renewalDate,
    required int daysRemaining,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.home_outlined, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room Allocation',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      '$roomName • $hostelName',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Active',
                  style: TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniInfo('Paid Tenure Ends', renewalDate != null ? DateFormat('dd MMM yyyy').format(renewalDate) : 'N/A', isDark),
              _buildMiniInfo(
                'Tenure Countdown',
                renewalDate != null
                    ? (daysRemaining > 0 ? '$daysRemaining days left' : 'Due for renewal')
                    : 'N/A',
                isDark,
                valueColor: daysRemaining > 0 ? const Color(0xFF2563EB) : const Color(0xFFEF4444),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String label, String value, bool isDark, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }

  // --- Request Status Card ---
  Widget _buildRequestStatusCard(Map<String, dynamic> req, bool isDark, UserProvider user) {
    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final statusColor = _getStatusColor(status);
    final reqId = req['request_id'] ?? '';
    final vacateDate = _formatDate(req['expected_vacate_date']);
    final renewalDate = _formatDate(req['renewal_date']);
    final wardenName = req['assigned_warden_name'] ?? 'Hostel Warden';
    final reason = req['reason'] ?? '';
    final isPending = status == 'pending';
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vacate Clearance Status',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Request ID: $reqId',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isApproved ? Icons.check_circle_rounded : (isRejected ? Icons.cancel_rounded : Icons.pending_rounded),
                      size: 13,
                      color: statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Details List
          _buildDetailTile(
            icon: Icons.calendar_today_rounded,
            iconColor: const Color(0xFFDC2626),
            title: 'Expected Vacate Date',
            value: vacateDate,
            isDark: isDark,
            isHighlight: true,
          ),
          const SizedBox(height: 10),
          _buildDetailTile(
            icon: Icons.event_repeat_rounded,
            iconColor: const Color(0xFF2563EB),
            title: 'Paid Tenure Expiry',
            value: renewalDate,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildDetailTile(
            icon: Icons.shield_outlined,
            iconColor: const Color(0xFF8B5CF6),
            title: 'Assigned Warden',
            value: wardenName,
            subtitle: isPending ? 'Conducting room physical clearance' : null,
            isDark: isDark,
          ),

          if (reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildDetailTile(
              icon: Icons.notes_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: 'Reason for Vacating',
              value: reason,
              isDark: isDark,
            ),
          ],

          if (isRejected && (req['rejection_reason'] != null && req['rejection_reason'].toString().isNotEmpty)) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFEF4444), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Warden Rejection Feedback',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    req['rejection_reason'],
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : const Color(0xFF7F1D1D),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Clearance Progress Timeline
          _buildClearanceTimeline(status, isDark),

          const SizedBox(height: 20),

          // Actions
          if (isPending) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isCancelling ? null : _cancelRequest,
                icon: _isCancelling
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.close, size: 16),
                label: Text(_isCancelling ? 'Cancelling...' : 'Cancel Vacate Request'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ] else if (isRejected) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openVacateModal(user),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Submit New Vacate Request'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
    required bool isDark,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                  color: isHighlight
                      ? const Color(0xFFDC2626)
                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --- Timeline ---
  Widget _buildClearanceTimeline(String status, bool isDark) {
    final isApproved = status == 'approved';
    final isRejected = status == 'rejected';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clearance Workflow',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 10),
          _buildTimelineStep(
            '1. Request Submitted',
            'Registered with assigned warden',
            true,
            isDark,
          ),
          _buildTimelineStep(
            '2. Room Inspection & Handover',
            'Return keys and inspect furniture',
            isApproved,
            isDark,
            isCurrent: !isApproved && !isRejected,
          ),
          _buildTimelineStep(
            '3. Warden Approval & Bed Release',
            isApproved ? 'Approved & bed immediately freed' : 'Room freed for next student',
            isApproved,
            isDark,
            isLast: true,
            isFailed: isRejected,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep(
    String title,
    String subtitle,
    bool isCompleted,
    bool isDark, {
    bool isCurrent = false,
    bool isLast = false,
    bool isFailed = false,
  }) {
    Color iconColor;
    IconData icon;
    if (isCompleted) {
      iconColor = const Color(0xFF10B981);
      icon = Icons.check_circle_rounded;
    } else if (isFailed) {
      iconColor = const Color(0xFFEF4444);
      icon = Icons.cancel_rounded;
    } else if (isCurrent) {
      iconColor = const Color(0xFFF59E0B);
      icon = Icons.radio_button_checked_rounded;
    } else {
      iconColor = Colors.grey.shade400;
      icon = Icons.radio_button_unchecked_rounded;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icon, size: 16, color: iconColor),
            if (!isLast)
              Container(
                width: 1.5,
                height: 24,
                color: isCompleted ? const Color(0xFF10B981) : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isCurrent || isCompleted ? FontWeight.bold : FontWeight.normal,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white54 : const Color(0xFF64748B),
                ),
              ),
              if (!isLast) const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  // --- Promo / Informational Card (When No Request Active) ---
  Widget _buildNewRequestPromoCard(UserProvider user, bool isDark, String roomName) {
    final bool canVacate = roomName != 'Unallocated';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
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
                  color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.exit_to_app_rounded, color: Color(0xFFDC2626), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hostel Room Clearance',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Early Room Vacate & Handover',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Text(
            'If you have completed your academic term, internship, or project early, you can submit an official room vacate request up to 1 day before your renewal expiry date.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Important Clearance Guidelines:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                _buildGuidelineItem('Return room keys and access cards to warden.', isDark),
                _buildGuidelineItem('Clear personal belongings & ensure zero furniture damage.', isDark),
                _buildGuidelineItem('Once approved, room is immediately freed for new students.', isDark),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: canVacate ? () => _openVacateModal(user) : null,
              icon: const Icon(Icons.exit_to_app_rounded, size: 18),
              label: Text(canVacate ? 'Request to Vacate Room' : 'No Active Room to Vacate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidelineItem(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF10B981)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
