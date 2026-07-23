import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../../core/styles.dart';
import '../widgets/warden_widgets.dart';
import '../../shared/widgets/calendar_modal.dart';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';
import '../../core/api_service.dart';
import '../../shared/category_provider.dart';
import '../../shared/chat/request_details_screen.dart';
import '../../core/models/request_model.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class WardenReportsTab extends StatefulWidget {
  final String? initialCategory;
  const WardenReportsTab({super.key, this.initialCategory});

  @override
  State<WardenReportsTab> createState() => _WardenReportsTabState();
}

class _WardenReportsTabState extends State<WardenReportsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? _selectedCategory;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  Timer? _refreshTimer;
  final LayerLink _categoryLayerLink = LayerLink();
  OverlayEntry? _categoryOverlayEntry;
  double _categoryDropdownWidth = 140.0;

  @override
  void initState() {
    super.initState();
    final user = context.read<UserProvider>();
    final roleStr = user.role.toString().split('.').last.toLowerCase();
    String defaultCategory = 'Warden';
    if (roleStr == 'security') {
      defaultCategory = 'Security';
    } else if (roleStr == 'maintenance' || roleStr == 'staff') {
      defaultCategory = 'Maintenance';
    }
    _selectedCategory = widget.initialCategory ?? (user.username == 'warden1' ? null : defaultCategory);
    _fetchReports();
  }

  @override
  void didUpdateWidget(WardenReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCategory != oldWidget.initialCategory) {
      setState(() {
        _selectedCategory = widget.initialCategory;
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _closeCategoryDropdown();
    super.dispose();
  }

  String _normalizeDepartment(String dept) {
    final raw = dept.trim().toLowerCase();
    if (raw == 'parent_warden') return 'Parent_Warden';
    if (raw.contains('security')) return 'Security';
    if (raw.contains('maintenance') ||
        raw.contains('plumber') ||
        raw.contains('electric') ||
        raw.contains('staff')) {
      return 'Maintenance';
    }
    if (raw.contains('warden')) return 'Warden';
    return 'Warden';
  }

  Future<void> _fetchReports({bool isBackground = false}) async {
    if (!isBackground && mounted) setState(() => _isLoading = true);
    
    final user = context.read<UserProvider>();
    
    final results = await Future.wait([
      ApiService.getAllReports(wardenUsername: user.username),
      ApiService.getPendingRenewals(wardenUsername: user.username),
    ]);
    
    final response = results[0];
    final renewalsResponse = results[1];
    
    List<Map<String, dynamic>> mappedReports = [];
    List<Map<String, dynamic>> mappedRenewals = [];
    
    if (response['success'] == true) {
      final List rawData = response['data'] ?? [];
      mappedReports = rawData.map((r) {
        String dept = r['department'] ?? 'warden';
        String displayDept = _normalizeDepartment(dept);
        String typeMatch = displayDept.toLowerCase();

        return {
          'type': displayDept,
          'typeMatch': typeMatch,
          'sub': r['request_type'] ?? 'Request',
          'student': r['student_name'] ?? 'Unknown',
          'room': r['room_number'] ?? 'N/A',
          'status': (r['status'] ?? 'pending').toString().toUpperCase(),
          'date': r['created_at'] ?? DateTime.now().toString(),
          'id': (r['request_id'] ?? r['id'] ?? 'N/A').toString(),
          'desc': r['purpose'] ?? '',
          'raw': r,
        };
      }).where((r) {
        final staffRole = user.role.toString().split('.').last.toLowerCase();
        final reqDept = r['typeMatch'].toString().toLowerCase();
        
        if (user.username == 'warden1') {
          return reqDept == 'warden' || reqDept == 'security' || reqDept == 'maintenance' || reqDept == 'parent_warden';
        }

        // Admin sees everything
        if (staffRole == 'admin') return true;

        // Specific Role matching
        if (staffRole == reqDept) return true;

        // Group matching
        if (staffRole == 'warden' && (reqDept == 'warden' || reqDept == 'parent_warden')) return false;
        if (staffRole == 'maintenance' && (reqDept == 'maintenance' || reqDept == 'plumber' || reqDept == 'electricity')) return true;
        
        return false;
      }).toList();
    }

    if (renewalsResponse['success'] == true || renewalsResponse['status'] == 'success') {
      final List rawRenewals = renewalsResponse['data'] ?? [];
      mappedRenewals = rawRenewals.map<Map<String, dynamic>>((r) {
        return {
          'type': 'Renewals',
          'typeMatch': 'renewals',
          'sub': 'Renewal Request',
          'student': r['student_name'] ?? 'Unknown',
          'room': r['room_number'] ?? 'N/A',
          'status': (r['status'] ?? 'pending').toString().toUpperCase(),
          'date': r['requested_at'] ?? DateTime.now().toString(),
          'id': 'REN-${r['id']}',
          'desc': r['reason'] ?? 'Renewal request',
          'raw': r,
        };
      }).toList();
    }

    if (mounted) {
      setState(() {
        _reports = [...mappedReports, ...mappedRenewals];
        _isLoading = false;
      });
    }
  }

  void _openRequestDetails(Map<String, dynamic> report) {
    final user = context.read<UserProvider>();
    final isWarden1 = user.username == 'warden1';

    if (report['typeMatch'] == 'renewals') {
      _showRenewalActionDialog(report);
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      useRootNavigator: false,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.85,
        child: RequestDetailsScreen(
          request: RequestModel.fromJson(report['raw']),
          canAction: !isWarden1,
        ),
      ),
    ).then((_) => _fetchReports());
  }

  void _showRenewalActionDialog(Map<String, dynamic> report) {
    final renewalId = int.tryParse(report['raw']['id']?.toString() ?? '');
    if (renewalId == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Renewal Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student: ${report['student']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Room: ${report['room']}'),
            const SizedBox(height: 8),
            Text('Reason: ${report['desc']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.rejectRenewal(renewalId);
              if (res['success'] == true || res['status'] == 'success') {
                _fetchReports();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final res = await ApiService.approveRenewal(renewalId);
              if (res['success'] == true || res['status'] == 'success') {
                _fetchReports();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    List<Map<String, dynamic>> filteredReports = _reports.where((r) {
      final categoryMatch = _selectedCategory == null || 
          r['type'] == _selectedCategory ||
          (_selectedCategory == 'Warden' && r['type'] == 'Parent_Warden');
      DateTime reportDate;
      try {
        reportDate = DateTime.parse(r['date']);
      } catch (_) {
        reportDate = DateTime.now();
      }
      
      bool dateMatch = true;
      if (_startDate != null && reportDate.isBefore(_startDate!)) dateMatch = false;
      if (_endDate != null && reportDate.isAfter(_endDate!.add(const Duration(days: 1)))) dateMatch = false;
      
      return categoryMatch && dateMatch;
    }).toList();

    final user = context.watch<UserProvider>();
    final showInternalAppBar = true;

    if (_isLoading) {
      return const LinenBackground(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: showInternalAppBar 
          ? const SkeuomorphicNavBar(
              title: 'Reports',
              rightAction: ProfileButton(),
            )
          : null,
      body: LinenBackground(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _buildDashboardSummary(),
                  const SizedBox(height: 20),
                  _buildFiltersSection(user, filteredReports.length),
                  _buildResultsList(filteredReports),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardSummary() {
    final user = context.watch<UserProvider>();
    final isWarden1 = user.username == 'warden1';

    if (isWarden1) {
      // 2x2 Grid of Dashboard Cards
      final wardenReports = _reports.where((r) => r['typeMatch'] == 'warden' || r['typeMatch'] == 'parent_warden').toList();
      final wardenTotal = wardenReports.length;
      final wardenPending = wardenReports.where((r) => r['status'] == 'PENDING').length;

      final securityReports = _reports.where((r) => r['typeMatch'] == 'security').toList();
      final securityTotal = securityReports.length;
      final securityPending = securityReports.where((r) => r['status'] == 'PENDING').length;

      final renewalsReports = _reports.where((r) => r['typeMatch'] == 'renewals').toList();
      final renewalsPending = renewalsReports.where((r) => r['status'] == 'PENDING').length;
      final renewalsTotal = renewalsReports.length;

      final maintenanceReports = _reports.where((r) => r['typeMatch'] == 'maintenance').toList();
      final maintenanceTotal = maintenanceReports.length;
      final maintenancePending = maintenanceReports.where((r) => r['status'] == 'PENDING').length;



      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A2744), Color(0xFF2A3A5C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildDashboardCard(
                    title: 'MAINTENANCE',
                    total: maintenanceTotal,
                    pending: maintenancePending,
                    gradientColors: [const Color(0xFFFFD54F), const Color(0xFFFFA000)],
                    isSelected: _selectedCategory == 'Maintenance',
                    onTap: () => setState(() => _selectedCategory = 'Maintenance'),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildDashboardCard(
                    title: 'SECURITY',
                    total: securityTotal,
                    pending: securityPending,
                    gradientColors: [const Color(0xFFEF9A9A), const Color(0xFFE53935)],
                    isSelected: _selectedCategory == 'Security',
                    onTap: () => setState(() => _selectedCategory = 'Security'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child: _buildDashboardCard(
                    title: 'WARDEN REQUESTS',
                    total: wardenTotal,
                    pending: wardenPending,
                    gradientColors: [const Color(0xFFA5D6A7), const Color(0xFF66BB6A)],
                    isSelected: _selectedCategory == 'Warden',
                    onTap: () => setState(() => _selectedCategory = 'Warden'),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: _buildDashboardCard(
                    title: 'RENEWALS',
                    total: renewalsTotal,
                    pending: renewalsPending,
                    gradientColors: [const Color(0xFFE8D48A), const Color(0xFFD4AF37)],
                    isSelected: _selectedCategory == 'Renewals',
                    onTap: () => setState(() => _selectedCategory = 'Renewals'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      // Floor-wise warden/staff: single card matching their role category
      final roleStr = user.role.toString().split('.').last.toLowerCase();
      String categoryKey = 'warden';
      String cardTitle = 'WARDEN';
      Color cardColor = const Color(0xFF00AFA3);

      if (roleStr == 'security') {
        categoryKey = 'security';
        cardTitle = 'SECURITY';
        cardColor = const Color(0xFFE53935);
      } else if (roleStr == 'maintenance' || roleStr == 'staff') {
        categoryKey = 'maintenance';
        cardTitle = 'MAINTENANCE';
        cardColor = const Color(0xFFFFA000);
      }
      
      // Filter reports by date for the summary boxes
      List<Map<String, dynamic>> dateFilteredReports = _reports.where((r) {
        DateTime reportDate;
        try {
          reportDate = DateTime.parse(r['date']);
        } catch (_) {
          reportDate = DateTime.now();
        }
        
        bool dateMatch = true;
        if (_startDate != null && reportDate.isBefore(_startDate!)) dateMatch = false;
        if (_endDate != null && reportDate.isAfter(_endDate!.add(const Duration(days: 1)))) dateMatch = false;
        
        return dateMatch;
      }).toList();
      
      int count = dateFilteredReports.where((r) => 
        r['typeMatch'] == categoryKey || 
        (categoryKey == 'warden' && r['typeMatch'] == 'parent_warden')
      ).length;
      
      int pending = dateFilteredReports.where((r) => 
        (r['typeMatch'] == categoryKey || (categoryKey == 'warden' && r['typeMatch'] == 'parent_warden')) && 
        r['status'] == 'PENDING'
      ).length;

      return Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1A2744), Color(0xFF2A3A5C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Row(
          children: [
            Expanded(
              child: _buildModernSummaryCard(
                cardTitle, 
                count.toString(), 
                pending.toString(), 
                cardColor, 
                () => setState(() => _selectedCategory = cardTitle[0].toUpperCase() + cardTitle.substring(1).toLowerCase())
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDashboardCard({
    required String title,
    required int total,
    required int pending,
    required List<Color> gradientColors,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final int completionPercent = total > 0 ? ((pending / total) * 100).round() : 0;
    final double progress = total > 0 ? pending / total : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2B48),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? gradientColors[1] : Colors.white12,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$completionPercent%',
                  style: TextStyle(
                    color: gradientColors[0],
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    color: Colors.white10,
                  ),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 500),
                    alignment: Alignment.centerLeft,
                    widthFactor: progress.clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$pending',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Pending',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernSummaryCard(String label, String active, String updated, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2B48),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label, 
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    active, 
                    style: SkeuomorphicStyles.playfairHeader.copyWith(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 5),
                  child: Text('Total', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 8),
            Row(
              children: [
                Flexible(
                  child: Text(
                    updated, 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 5),
                const Text('Pending', style: TextStyle(color: Colors.white54, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersSection(UserProvider user, int filteredCount) {
    final isWarden1 = user.username == 'warden1';

    String getCategoryDisplay(String? category) {
      if (category == 'Warden') return 'Warden';
      return category ?? 'All';
    }

    bool hasActiveFilter;
    if (isWarden1) {
      hasActiveFilter = _selectedCategory != null || _startDate != null || _endDate != null;
    } else {
      hasActiveFilter = _startDate != null || _endDate != null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "FILTERS" Row
          Row(
            children: const [
              Icon(Icons.filter_alt_outlined, size: 14, color: Color(0xFF8A7A6A)),
              SizedBox(width: 6),
              Text(
                'FILTERS',
                style: TextStyle(
                  color: Color(0xFF8A7A6A),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Horizontal Filter Inputs (Single Row)
          LayoutBuilder(
            builder: (context, constraints) {
              _categoryDropdownWidth = (constraints.maxWidth - 16) / 3;
              return Row(
                children: [
                  // Category Dropdown
                  Expanded(
                    child: CompositedTransformTarget(
                      link: _categoryLayerLink,
                      child: GestureDetector(
                        onTap: isWarden1 ? _toggleCategoryDropdown : null,
                        child: Container(
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF7F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFD0C8BC), width: 1.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 3,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  getCategoryDisplay(_selectedCategory),
                                  style: TextStyle(
                                    fontFamily: 'Lato',
                                    fontSize: 12,
                                    fontWeight: _selectedCategory != null ? FontWeight.bold : FontWeight.normal,
                                    color: const Color(0xFF1B2B48),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isWarden1)
                              const Icon(
                                Icons.keyboard_arrow_down,
                                size: 16,
                                color: Color(0xFF7A6F62),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Start Date field
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showUniversalCalendar(context, isStart: true),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF7F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _startDate != null ? const Color(0xFFD4AF37) : const Color(0xFFD0C8BC),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 3,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                _startDate != null 
                                    ? DateFormat('dd-MM-yyyy').format(_startDate!) 
                                    : 'dd-mm-yyyy',
                                style: TextStyle(
                                  fontFamily: 'Lato',
                                  fontSize: 12,
                                  fontWeight: _startDate != null ? FontWeight.bold : FontWeight.normal,
                                  color: _startDate != null ? const Color(0xFF1B2B48) : const Color(0xFFA09080),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // End Date field
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showUniversalCalendar(context, isStart: false),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF7F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _endDate != null ? const Color(0xFFD4AF37) : const Color(0xFFD0C8BC),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 3,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                _endDate != null 
                                    ? DateFormat('dd-MM-yyyy').format(_endDate!) 
                                    : 'dd-mm-yyyy',
                                style: TextStyle(
                                  fontFamily: 'Lato',
                                  fontSize: 12,
                                  fontWeight: _endDate != null ? FontWeight.bold : FontWeight.normal,
                                  color: _endDate != null ? const Color(0xFF1B2B48) : const Color(0xFFA09080),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.black87,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // Conditional "Clear All Filters" text button
          if (hasActiveFilter) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedCategory = isWarden1 ? null : 'Warden';
                  _startDate = null;
                  _endDate = null;
                });
                _closeCategoryDropdown();
              },
              child: const Text(
                'Clear All Filters',
                style: TextStyle(
                  fontFamily: 'Lato',
                  color: Color(0xFFD4AF37),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleCategoryDropdown() {
    if (_categoryOverlayEntry != null) {
      _closeCategoryDropdown();
      return;
    }

    _categoryOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: _closeCategoryDropdown,
            behavior: HitTestBehavior.translucent,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.transparent,
            ),
          ),
          CompositedTransformFollower(
            link: _categoryLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 44),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: _categoryDropdownWidth,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF7F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFD0C8BC), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDropdownItem(null, 'All'),
                    _buildDropdownItem('Maintenance', 'Maintenance'),
                    _buildDropdownItem('Security', 'Security'),
                    _buildDropdownItem('Warden', 'Warden'),
                    _buildDropdownItem('Renewals', 'Renewals'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_categoryOverlayEntry!);
    setState(() {});
  }

  void _closeCategoryDropdown() {
    _categoryOverlayEntry?.remove();
    _categoryOverlayEntry = null;
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildDropdownItem(String? value, String label) {
    final isSelected = (_selectedCategory == value) || (_selectedCategory == null && value == null);

    return InkWell(
      onTap: () {
        setState(() {
          _selectedCategory = value;
        });
        _closeCategoryDropdown();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? const Color(0xFFE2DDD5) : Colors.transparent,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lato',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: const Color(0xFF1B2B48),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(List<Map<String, dynamic>> reports) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reports.isEmpty)
             const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.bar_chart, size: 48, color: Colors.grey), SizedBox(height: 10), Text('No items match your filters', style: TextStyle(color: Colors.grey))]))),
          ...reports.map((r) => GestureDetector(
            onTap: () => _openRequestDetails(r),
            child: _buildReportCard(r)
          )),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(_getReportIcon(report['type']), size: 16, color: _getReportColor(report['type'])),
                    const SizedBox(width: 8),
                    Expanded(child: Text(report['sub'], style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildStatusBadge(report['status']),
            ],
          ),
          const SizedBox(height: 10),
          Text(report['id'], style: const TextStyle(fontFamily: 'Lato', fontSize: 10, color: Colors.blueGrey)),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(width: 32, height: 32, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient), child: Center(child: Text(report['student'][0], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${report['student']} (${report['room']})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text(DateFormat('dd MMM yyyy').format(DateTime.parse(report['date'])), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getReportIcon(String type) {
    final catProvider = context.read<CategoryProvider>();
    String name = type == 'Warden Requests' ? 'Warden' : type;
    return catProvider.getIconData(name);
  }

  Color _getReportColor(String type) {
    final catProvider = context.read<CategoryProvider>();
    String name = type == 'Warden Requests' ? 'Warden' : type;
    final cat = catProvider.getCategoryByName(name);
    if (cat != null) return catProvider.getColor(cat['color']);
    return const Color(0xFFD4AF37);
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String displayStatus = status.toUpperCase();
    
    if (displayStatus == 'RESOLVED' || displayStatus == 'APPROVED' || displayStatus == 'COMPLETED') {
      color = Colors.green;
    } else if (displayStatus == 'REJECTED') {
      color = Colors.red;
    } else if (displayStatus == 'FIXED') {
      color = Colors.blue;
    } else if (displayStatus == 'REOPENED') {
      color = Colors.orange;
    } else {
      color = Colors.amber;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), 
        borderRadius: BorderRadius.circular(12), 
        border: Border.all(color: color.withOpacity(0.2))
      ),
      child: Text(displayStatus, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }



  void _showUniversalCalendar(BuildContext context, {required bool isStart}) async {
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => const UniversalCalendarModal(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) _endDate = null;
        } else {
          _endDate = picked;
          if (_startDate != null && _startDate!.isAfter(_endDate!)) _startDate = null;
        }
      });
    }
  }
}
