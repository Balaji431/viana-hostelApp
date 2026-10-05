import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_service.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/user_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart' show LinenBackground;

class SuperAdminDashboardScreen extends StatefulWidget {
  final String title;
  final bool showBackButton;

  const SuperAdminDashboardScreen({
    super.key,
    this.title = 'Developer Dashboard',
    this.showBackButton = false,
  });

  @override
  State<SuperAdminDashboardScreen> createState() => _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _issues = [];
  Map<String, int> _counts = {
    'total': 0,
    'student': 0,
    'warden': 0,
    'it': 0,
    'security': 0,
    'admin': 0,
    'maintenance': 0,
    'pending': 0,
    'in_progress': 0,
    'resolved': 0,
  };

  final String _selectedRoleFilter = 'all'; // Default to all now that role tabs are removed
  String _selectedStatusFilter = 'all'; // all, Pending, In Progress, Resolved, Closed
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchIssues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchIssues() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getIssues(
        role: _selectedRoleFilter,
        status: _selectedStatusFilter,
        search: _searchController.text.trim(),
      );

      if (res['success'] == true && mounted) {
        final data = res['data'];
        final List<dynamic> issueList = data['issues'] ?? [];
        final Map<String, dynamic> countMap = Map<String, dynamic>.from(data['counts'] ?? {});

        setState(() {
          _issues = issueList.map((e) => Map<String, dynamic>.from(e)).toList();
          _counts = countMap.map((k, v) => MapEntry(k, int.tryParse(v.toString()) ?? 0));
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  void _onStatusSelected(String status) {
    setState(() {
      _selectedStatusFilter = status;
    });
    _fetchIssues();
  }

  Future<void> _updateStatusDialog(Map<String, dynamic> issue) async {
    final user = Provider.of<UserProvider>(context, listen: false);
    final isDeveloper = user.role == UserRole.developer ||
        user.roleName.toLowerCase() == 'developer' ||
        user.username == '192211929';
    if (!isDeveloper) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only developers can update issue status.')),
      );
      return;
    }

    String currentStatus = issue['status'] ?? 'Pending';
    final notesController = TextEditingController(text: issue['admin_notes'] ?? '');
    String selectedStatus = currentStatus;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'Update Issue Status',
              style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 17),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Issue ID: #${issue['id']} • ${issue['username']}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Status:',
                  style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['Pending', 'In Progress', 'Resolved', 'Closed'].map((st) {
                    final isSel = selectedStatus.toLowerCase() == st.toLowerCase();
                    final stColor = _getStatusColor(st);
                    return ChoiceChip(
                      label: Text(st),
                      selected: isSel,
                      selectedColor: stColor.withOpacity(0.18),
                      backgroundColor: const Color(0xFFF8FAFC),
                      side: BorderSide(color: isSel ? stColor : const Color(0xFFE2E8F0)),
                      labelStyle: TextStyle(
                        color: isSel ? stColor : const Color(0xFF475569),
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (val) {
                        if (val) setModalState(() => selectedStatus = st);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin Notes / Resolution Remarks:',
                  style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesController,
                  maxLines: 3,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Add remarks on how this issue was handled...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: () async {
                  final res = await ApiService.updateIssueStatus(
                    issueId: int.parse(issue['id'].toString()),
                    status: selectedStatus,
                    adminNotes: notesController.text.trim(),
                    role: 'developer',
                  );
                  if (res['success'] == true && ctx.mounted) {
                    Navigator.pop(ctx, true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD4AF37),
                  foregroundColor: const Color(0xFF1B2B48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (updated == true) {
      _fetchIssues();
    }
  }

  void _showImagePreview(String imageUrl) {
    final fullUrl = imageUrl.startsWith('http') ? imageUrl : '${ApiService.baseUrl}$imageUrl';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.network(
                  fullUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(24),
                    color: Colors.white,
                    child: const Text('Could not load image', style: TextStyle(color: Color(0xFF0F172A))),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(String url) async {
    final fullUrl = url.startsWith('http') ? url : '${ApiService.baseUrl}$url';
    final uri = Uri.tryParse(fullUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFEF4444); // Red
      case 'in progress':
        return const Color(0xFFF59E0B); // Amber
      case 'resolved':
        return const Color(0xFF10B981); // Emerald Green
      case 'closed':
        return const Color(0xFF64748B); // Slate Gray
      default:
        return const Color(0xFF3B82F6);
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'student':
        return const Color(0xFF3B82F6); // Blue
      case 'warden':
        return const Color(0xFFD4AF37); // Gold
      case 'it':
      case 'it_department':
        return const Color(0xFF8B5CF6); // Purple
      case 'security':
        return const Color(0xFF10B981); // Green
      case 'admin':
        return const Color(0xFFEC4899); // Pink / Magenta
      case 'maintenance':
        return const Color(0xFF06B6D4); // Cyan
      default:
        return const Color(0xFF64748B);
    }
  }

  String _formatRoleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'student':
        return 'Student';
      case 'warden':
        return 'Warden';
      case 'it':
      case 'it_department':
        return 'IT';
      case 'security':
        return 'Security';
      case 'admin':
        return 'Admin';
      case 'maintenance':
        return 'Maintenance';
      default:
        return role.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final user = context.watch<UserProvider>();
    final isDark = wallpaper.isDarkTheme;
    final isDeveloper = user.role == UserRole.developer ||
        user.roleName.toLowerCase() == 'developer' ||
        user.username == '192211929';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: widget.title,
        onBack: widget.showBackButton ? () => Navigator.of(context).pop() : null,
        onHomeTap: () => _fetchIssues(),
      ),
      body: LinenBackground(
        child: RefreshIndicator(
          onRefresh: _fetchIssues,
          color: const Color(0xFFD4AF37),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top KPI Summary Cards
                _buildKpiMetrics(),
                const SizedBox(height: 18),

                // Search and Status Filters
                _buildSearchAndFilterBar(),
                const SizedBox(height: 18),

                // Issue List Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'All Reported Issues (${_issues.length})',
                      style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Lato',
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18, color: Color(0xFF64748B)),
                      tooltip: 'Refresh',
                      onPressed: _fetchIssues,
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Issues List
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
                      ),
                    ),
                  )
                else if (_issues.isEmpty)
                  _buildEmptyState()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _issues.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) => _buildIssueCard(_issues[index], isDeveloper: isDeveloper),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiMetrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 550;
        final cardWidth = isWide ? (constraints.maxWidth - 24) / 3 : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStatCard(
              title: 'Total Issues',
              value: '${_counts['total'] ?? 0}',
              icon: Icons.assignment_rounded,
              color: const Color(0xFF3B82F6),
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Pending Action',
              value: '${_counts['pending'] ?? 0}',
              icon: Icons.pending_actions_rounded,
              color: const Color(0xFFEF4444),
              width: cardWidth,
            ),
            _buildStatCard(
              title: 'Resolved',
              value: '${_counts['resolved'] ?? 0}',
              icon: Icons.check_circle_rounded,
              color: const Color(0xFF10B981),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Lato',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Lato',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _fetchIssues(),
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search by ID, name, or description...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Color(0xFF64748B), size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _fetchIssues();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _fetchIssues,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1B2B48),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Search', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['all', 'Pending', 'In Progress', 'Resolved', 'Closed'].map((st) {
              final isSel = _selectedStatusFilter.toLowerCase() == st.toLowerCase();
              final stColor = _getStatusColor(st);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(st == 'all' ? 'All Status' : st),
                  selected: isSel,
                  selectedColor: stColor.withOpacity(0.14),
                  backgroundColor: Colors.white,
                  checkmarkColor: stColor,
                  labelStyle: TextStyle(
                    color: isSel ? stColor : const Color(0xFF475569),
                    fontSize: 11.5,
                    fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: isSel ? stColor : const Color(0xFFE2E8F0),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onSelected: (_) => _onStatusSelected(st),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildIssueCard(Map<String, dynamic> issue, {bool isDeveloper = false}) {
    final role = (issue['user_role'] ?? 'student').toString().toLowerCase();
    final roleColor = _getRoleColor(role);
    final status = issue['status'] ?? 'Pending';
    final statusColor = _getStatusColor(status);
    final attachmentUrl = issue['attachment_url'];
    final attachmentType = issue['attachment_type'] ?? '';
    final isPdf = attachmentType == 'pdf' || (attachmentUrl != null && attachmentUrl.toString().toLowerCase().endsWith('.pdf'));

    String timeStr = '';
    if (issue['created_at'] != null) {
      try {
        final dt = DateTime.parse(issue['created_at'].toString());
        timeStr = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
      } catch (_) {
        timeStr = issue['created_at'].toString();
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Bar: Role Banner + Status Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.08),
                border: Border(bottom: BorderSide(color: roleColor.withOpacity(0.18))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: roleColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _formatRoleLabel(role).toUpperCase(),
                      style: TextStyle(
                        color: roleColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 0.8,
                        fontFamily: 'Lato',
                      ),
                    ),
                  ),
                  if (isDeveloper)
                    InkWell(
                      onTap: () => _updateStatusDialog(issue),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withOpacity(0.5), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_drop_down, color: statusColor, size: 14),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor.withOpacity(0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Main Body: User Identity & Details
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User Details Grid
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: roleColor.withOpacity(0.15),
                        child: Text(
                          (issue['user_name'] != null && issue['user_name'].toString().isNotEmpty)
                              ? issue['user_name'].toString()[0].toUpperCase()
                              : 'U',
                          style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              issue['user_name'] != null && issue['user_name'].toString().isNotEmpty
                                  ? issue['user_name'].toString()
                                  : issue['username'].toString(),
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: ${issue['username']} • ${_formatRoleLabel(issue['user_role'] ?? 'user')}',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                            ),
                            if (issue['email'] != null && issue['email'].toString().isNotEmpty)
                              Text(
                                issue['email'].toString(),
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                    ],
                  ),

                  if ((issue['hostel_name'] != null && issue['hostel_name'].toString().isNotEmpty) ||
                      (issue['room_no'] != null && issue['room_no'].toString().isNotEmpty)) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.apartment_rounded, color: Color(0xFFD4AF37), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            '${issue['hostel_name'] ?? ''} ${issue['room_no'] != null ? '• Room: ${issue['room_no']}' : ''}',
                            style: const TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Issue Description Content
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Issue Description:',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          issue['issue_description'] ?? 'No description provided.',
                          style: const TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Attachment Section if available
                  if (attachmentUrl != null && attachmentUrl.toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (!isPdf) ...[
                          // Image preview
                          InkWell(
                            onTap: () => _showImagePreview(attachmentUrl.toString()),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.image_outlined, color: Color(0xFF2563EB), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'View Screenshot Image',
                                    style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          // PDF Document preview / download
                          InkWell(
                            onTap: () => _openAttachment(attachmentUrl.toString()),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Open / Download PDF',
                                    style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Admin Notes if updated
                  if (issue['admin_notes'] != null && issue['admin_notes'].toString().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.note_alt_outlined, color: Color(0xFF059669), size: 15),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Resolution Note: ${issue['admin_notes']}',
                              style: const TextStyle(color: Color(0xFF065F46), fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: const [
          Icon(Icons.inbox_rounded, color: Color(0xFF94A3B8), size: 48),
          SizedBox(height: 12),
          Text(
            'No issues reported matching criteria',
            style: TextStyle(color: Color(0xFF1E293B), fontSize: 15, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            'Any submitted reports from students or staff will appear here.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
