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

class _WardenReportsTabState extends State<WardenReportsTab> {
  String? _selectedCategory;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;
  List<Map<String, dynamic>> _reports = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'Warden';
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
    super.dispose();
  }

  Future<void> _fetchReports({bool isBackground = false}) async {
    if (!isBackground && mounted) setState(() => _isLoading = true);
    
    final response = await ApiService.getAllReports();
    
    if (response['success'] == true) {
      final List rawData = response['data'] ?? [];
      final List<Map<String, dynamic>> mapped = rawData.map((r) {
        String dept = r['department'] ?? 'warden';
        String displayDept = dept[0].toUpperCase() + dept.substring(1);
        // Standardize to just "Warden"
        if (displayDept.toLowerCase().contains('warden')) displayDept = 'Warden';

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
        final user = context.read<UserProvider>();
        final staffRole = user.role.toString().split('.').last.toLowerCase();
        final reqDept = r['typeMatch'].toString().toLowerCase();
        
        // Admin sees everything
        if (staffRole == 'admin') return true;

        // Specific Role matching
        if (staffRole == reqDept) return true;

        // Group matching
        if (staffRole == 'warden' && (reqDept == 'warden' || reqDept == 'parent_warden')) return false;
        if (staffRole == 'maintenance' && (reqDept == 'maintenance' || reqDept == 'plumber' || reqDept == 'electricity')) return true;
        
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _reports = mapped;
          _isLoading = false;
        });
      }
    } else {
      if (mounted && !isBackground) setState(() => _isLoading = false);
    }
  }

  void _openRequestDetails(Map<String, dynamic> report) {
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
          canAction: true,
        ),
      ),
    ).then((_) => _fetchReports());
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> filteredReports = _reports.where((r) {
      final categoryMatch = _selectedCategory == null || r['type'] == _selectedCategory;
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
    final showInternalAppBar = (user.role == UserRole.warden || user.role == UserRole.admin);

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
                  _buildFiltersSection(),
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
    final catProvider = context.watch<CategoryProvider>();
    final categories = catProvider.categories;
    List<Widget> summaryCards = [];
    
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
    
    for (var cat in categories) {
      String name = cat['name'] ?? '';
      String categoryKey = name.toLowerCase();
      
      // ONLY show Warden card in the dashboard summary as requested
      if (categoryKey != 'warden') continue;
      
      int count = dateFilteredReports.where((r) => r['typeMatch'] == 'warden').length;
      int pending = dateFilteredReports.where((r) => r['typeMatch'] == 'warden' && r['status'] == 'PENDING').length;
      Color color = catProvider.getColor(cat['color'] ?? '#D4AF37');
      
      summaryCards.add(_buildModernSummaryCard(
        'WARDEN', 
        count.toString(), 
        pending.toString(), 
        color, 
        () => setState(() => _selectedCategory = 'Warden')
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 15,
        crossAxisSpacing: 15,
        childAspectRatio: 1.0,
        children: summaryCards,
      ),
    );
  }

  Widget _buildModernSummaryCard(String label, String active, String updated, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2B48),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
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

  Widget _buildFiltersSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _showCategoryPicker(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F6F1),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.black12),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.category_outlined, size: 20, color: Colors.grey),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            _selectedCategory ?? 'Warden',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1B2B48)),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          if ((_selectedCategory != null && _selectedCategory != 'Warden') || _startDate != null || _endDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ActionChip(
                avatar: const Icon(Icons.close, size: 14),
                label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  _selectedCategory = 'Warden';
                  _startDate = null;
                  _endDate = null;
                }),
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showUniversalCalendar(context, isStart: true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _startDate != null ? const Color(0xFFD4AF37) : Colors.black12, width: _startDate != null ? 1.5 : 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _startDate != null ? DateFormat('dd-MM-yyyy').format(_startDate!) : 'Start Date', 
                            style: TextStyle(color: _startDate != null ? const Color(0xFF1B2B48) : Colors.grey, fontSize: 13, fontWeight: _startDate != null ? FontWeight.bold : FontWeight.normal),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.calendar_today, size: 16, color: _startDate != null ? const Color(0xFFD4AF37) : Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showUniversalCalendar(context, isStart: false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: _endDate != null ? const Color(0xFFD4AF37) : Colors.black12, width: _endDate != null ? 1.5 : 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            _endDate != null ? DateFormat('dd-MM-yyyy').format(_endDate!) : 'End Date', 
                            style: TextStyle(color: _endDate != null ? const Color(0xFF1B2B48) : Colors.grey, fontSize: 13, fontWeight: _endDate != null ? FontWeight.bold : FontWeight.normal),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.calendar_today, size: 16, color: _endDate != null ? const Color(0xFFD4AF37) : Colors.grey.shade400),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(List<Map<String, dynamic>> reports) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${reports.length} items found', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
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

  void _showCategoryPicker(BuildContext context) {
    final categoriesList = ['Warden'];
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 250,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F1),
            borderRadius: BorderRadius.circular(15),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
          ),
          child: ListView(
            shrinkWrap: true,
            children: categoriesList.map((c) => ListTile(
              title: Text(
                c, 
                style: TextStyle(
                  color: const Color(0xFF1B2B48), 
                  fontWeight: _selectedCategory == c ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14
                )
              ),
              onTap: () {
                setState(() => _selectedCategory = c);
                Navigator.pop(context);
              },
            )).toList(),
          ),
        ),
      ),
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
