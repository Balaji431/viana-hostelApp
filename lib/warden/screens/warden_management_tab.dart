import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import 'package:provider/provider.dart';
import '../../shared/user_provider.dart';
import '../widgets/warden_widgets.dart';
import '../widgets/warden_modals.dart';
import '../../admin/hostel_fee_selector_screen.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';

class WardenManagementTab extends StatefulWidget {
  const WardenManagementTab({super.key});

  @override
  State<WardenManagementTab> createState() => _WardenManagementTabState();
}

class _WardenManagementTabState extends State<WardenManagementTab> {
  int _activeSubTab = 0; // 0: Conduct, 1: Payments, 2: Renewals

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserProvider>();
    final showInternalAppBar = (user.role == UserRole.warden || user.role == UserRole.admin);

    return Scaffold(
      appBar: showInternalAppBar 
          ? const SkeuomorphicNavBar(
              title: 'Management',
              rightAction: ProfileButton(),
            )
          : null,
      body: LinenBackground(
        child: CustomScrollView(
          slivers: [
            if (user.role != UserRole.admin) SliverToBoxAdapter(child: _buildProfileHeader()),
            if (user.role == UserRole.warden) SliverToBoxAdapter(child: _buildSubTabSelector()),
            if (user.role == UserRole.admin) const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverPersistentHeader(
              pinned: true,
              delegate: _ManagementHeaderDelegate(
                child: Container(
                  color: const Color(0xFFF9F6F1),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    user.role == UserRole.admin 
                        ? 'Fee Management' 
                        : (_activeSubTab == 0 ? 'Conduct Records' : (_activeSubTab == 1 ? 'Payment History' : 'Renewal Logs')),
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
              ),
            ),
            _buildActiveSubTabSliver(),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSubTabSliver() {
    final user = context.read<UserProvider>();
    if (user.role == UserRole.admin) {
      return const SliverToBoxAdapter(
        child: HostelFeeSelectorScreen(isEmbedded: true),
      );
    }

    switch (_activeSubTab) {
      case 0: return const _ConductSubSliver();
      case 1: return const _PaymentsSubSliver();
      case 2: return const _RenewalsSubSliver();
      default: return const SliverToBoxAdapter(child: SizedBox());
    }
  }

  Widget _buildProfileHeader() {
    final user = context.watch<UserProvider>();
    String name = user.userName;
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 25),
      decoration: const BoxDecoration(
        gradient: SkeuomorphicColors.royalContentGradient,
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: SkeuomorphicStyles.playfairHeader.copyWith(fontSize: 18, color: Colors.white)),
              Text(
                (user.institution.isNotEmpty && user.institution != 'N/A' ? user.institution : "ID: ${user.username}"), 
                style: SkeuomorphicStyles.latoBody.copyWith(fontSize: 13, color: Colors.white70)
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildSubTabItem('Conduct', 0),
            const SizedBox(width: 10),
            _buildSubTabItem('Payments', 1),
            const SizedBox(width: 10),
            _buildSubTabItem('Renewals', 2),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTabItem(String label, int index) {
    bool active = _activeSubTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeSubTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: active 
          ? BoxDecoration(gradient: SkeuomorphicColors.goldGlossyGradient, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))])
          : BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.black12)),
        child: Text(label, style: TextStyle(color: active ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _ManagementHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  _ManagementHeaderDelegate({required this.child});
  @override double get minExtent => 45;
  @override double get maxExtent => 45;
  @override Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);
  @override bool shouldRebuild(_ManagementHeaderDelegate oldDelegate) => false;
}

class _ConductSubSliver extends StatefulWidget {
  const _ConductSubSliver();
  @override State<_ConductSubSliver> createState() => _ConductSubSliverState();
}

class _ConductSubSliverState extends State<_ConductSubSliver> {
  List<Map<String, dynamic>> _students = [];
  bool _isLoading = true;
  String _selectedFilter = 'All';

  @override 
  void initState() { 
    super.initState(); 
    _fetchStudents(); 
  }

  Future<void> _fetchStudents() async {
    final user = context.read<UserProvider>();
    final response = await ApiService.getStudents(wardenUsername: user.username);
    if (response['status'] == 'success') {
      if (mounted) {
        setState(() { 
          _students = List<Map<String, dynamic>>.from(response['data']); 
          _isLoading = false; 
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _students.where((s) {
      if (_selectedFilter == 'All') return true;
      return (s['conduct'] ?? 'Good').toString().toLowerCase() == _selectedFilter.toLowerCase();
    }).toList();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: _buildFilterPills(),
          ),
        ),
        if (_isLoading)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (filtered.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: Text("No students found"))))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildStudentCard(filtered[index]),
              childCount: filtered.length,
            ),
          ),
      ],
    );
  }

  Widget _buildFilterPills() {
    final filters = ['All', 'Good', 'Satisfactory', 'Poor'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          bool active = _selectedFilter == f;
          return GestureDetector(
            onTap: () => setState(() { _selectedFilter = f; }),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: active ? _getColor(f) : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: active ? Colors.transparent : Colors.black12)),
              child: Text(f, style: TextStyle(color: active ? Colors.white : _getColor(f), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getColor(String f) {
    final val = f.trim().toLowerCase();
    if (val == 'good') return Colors.green;
    if (val == 'satisfactory') return Colors.orange;
    if (val == 'poor') return Colors.red;
    return const Color(0xFF1B2B48);
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    String name = student['full_name'] ?? student['name'] ?? 'Unknown';
    String room = student['room_no'] ?? 'N/A';
    String conduct = student['conduct'] ?? 'Good';
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      child: ListTile(
        onTap: () async {
          final result = await showDialog(
            context: context,
            builder: (context) => EditConductModal(student: student),
          );
          if (result == true) _fetchStudents();
        },
        leading: Container(
          width: 40, height: 40,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
          child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
        subtitle: Text('Room $room'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _getColor(conduct).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(
            conduct[0].toUpperCase() + conduct.substring(1).toLowerCase(), 
            style: TextStyle(color: _getColor(conduct), fontSize: 10, fontWeight: FontWeight.bold)
          ),
        ),
      ),
    );
  }
}

class _PaymentsSubSliver extends StatefulWidget {
  const _PaymentsSubSliver();
  @override
  State<_PaymentsSubSliver> createState() => _PaymentsSubSliverState();
}

class _PaymentsSubSliverState extends State<_PaymentsSubSliver> {
  List<Map<String, dynamic>> _students = [];
  Map<String, List<Map<String, dynamic>>> _studentPayments = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'All';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (mounted) setState(() => _isLoading = true);
    final user = context.read<UserProvider>();
    
    // Fetch both students and payments
    final studentsRes = await ApiService.getStudents(wardenUsername: user.username);
    final paymentsRes = await ApiService.getAllPayments(wardenUsername: user.username);
    
    if (mounted) {
      setState(() {
        if (studentsRes['status'] == 'success') {
          _students = List<Map<String, dynamic>>.from(studentsRes['data']);
        }
        
        if (paymentsRes['success'] == true || paymentsRes['status'] == 'success') {
          final allPayments = List<Map<String, dynamic>>.from(paymentsRes['data']);
          _studentPayments = {};
          for (var p in allPayments) {
            String reg = (p['registerNumber'] ?? '').toString().trim();
            String name = (p['name'] ?? '').toString().trim().toUpperCase();
            
            if (reg.isNotEmpty) {
              if (!_studentPayments.containsKey(reg)) _studentPayments[reg] = [];
              _studentPayments[reg]!.add(p);
            }
            
            if (name.isNotEmpty) {
              if (!_studentPayments.containsKey(name)) _studentPayments[name] = [];
              // Check if already added by reg to avoid duplicates if they match, 
              // but adding to both is safer for different lookup keys
              if (!_studentPayments[name]!.contains(p)) {
                _studentPayments[name]!.add(p);
              }
            }
          }
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));

    final filteredStudents = _students.where((s) {
      final name = (s['full_name'] ?? s['name'] ?? '').toString().toLowerCase();
      final room = (s['room_no'] ?? '').toString().toLowerCase();
      final matchesSearch = name.contains(_searchQuery.toLowerCase()) || room.contains(_searchQuery.toLowerCase());
      
      if (!matchesSearch) return false;
      
      if (_filterStatus == 'All') return true;
      final reg = (s['register_number'] ?? s['student_id'] ?? s['id'] ?? '').toString();
      bool hasPayments = _studentPayments.containsKey(reg) && _studentPayments[reg]!.isNotEmpty;
      if (_filterStatus == 'Paid') return hasPayments;
      if (_filterStatus == 'Pending') return !hasPayments;
      return true;
    }).toList();

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Text('Student Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSearchBar(),
                const SizedBox(height: 12),
                _buildFilterPills(),
                const SizedBox(height: 8),
                Text('${filteredStudents.length} students', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildStudentPaymentCard(filteredStudents[index]),
            childCount: filteredStudents.length,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.black12)),
      child: TextField(
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: const InputDecoration(hintText: 'Search name or room...', prefixIcon: Icon(Icons.search, size: 20), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)),
      ),
    );
  }

  Widget _buildFilterPills() {
    return Row(
      children: [
        _filterPill('All'),
        const SizedBox(width: 10),
        _filterPill('Paid'),
        const SizedBox(width: 10),
        _filterPill('Pending'),
      ],
    );
  }

  Widget _filterPill(String label) {
    bool active = _filterStatus == label;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? SkeuomorphicColors.royalContentGradient : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: active ? Colors.transparent : (label == 'Paid' ? Colors.green.withOpacity(0.3) : (label == 'Pending' ? Colors.orange.withOpacity(0.3) : Colors.black12))),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : (label == 'Paid' ? Colors.green : (label == 'Pending' ? Colors.orange : Colors.grey)),
            fontSize: 12,
            fontWeight: FontWeight.bold
          ),
        ),
      ),
    );
  }

  Widget _buildStudentPaymentCard(Map<String, dynamic> student) {
    String reg = (student['register_number'] ?? student['student_id'] ?? student['id'] ?? '').toString().trim();
    String fullName = (student['full_name'] ?? student['name'] ?? '').toString().trim().toUpperCase();
    String room = student['room_no'] ?? 'N/A';
    List<Map<String, dynamic>> payments = _studentPayments[reg] ?? _studentPayments[fullName] ?? [];
    String initials = fullName.isNotEmpty ? fullName.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: SkeuomorphicStyles.skeuomorphicCard,
        child: ExpansionTile(
          leading: Container(
            width: 42, height: 42,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
            child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
          ),
          title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text('Room $room • ${payments.length} payment${payments.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          children: [
            if (payments.isEmpty)
              const Padding(padding: EdgeInsets.all(20), child: Text("No payment history recorded", style: TextStyle(color: Colors.grey, fontSize: 12)))
            else
              Column(
                children: payments.map((p) => _buildPaymentDetailItem(p)).toList(),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentDetailItem(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('₹${p['amount']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              Text(p['booking_date']?.toString().split(' ')[0] ?? 'N/A', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: (p['status']?.toString().toLowerCase() == 'success' ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(p['status'] ?? 'Success', style: TextStyle(color: p['status']?.toString().toLowerCase() == 'success' ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _RenewalsSubSliver extends StatefulWidget {
  const _RenewalsSubSliver();
  @override
  State<_RenewalsSubSliver> createState() => _RenewalsSubSliverState();
}

class _RenewalsSubSliverState extends State<_RenewalsSubSliver> {
  List<Map<String, dynamic>> _renewals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRenewals();
  }

  Future<void> _fetchRenewals() async {
    if (mounted) setState(() => _isLoading = true);
    final user = context.read<UserProvider>();
    final response = await ApiService.getPendingRenewals(wardenUsername: user.username);
    
    if (mounted) {
      setState(() {
        if (response['success'] == true || response['status'] == 'success') {
          _renewals = List<Map<String, dynamic>>.from(response['data'] ?? []);
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SliverToBoxAdapter(child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())));

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.history_edu, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Text('Pending Renewals', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                const Spacer(),
                Text('${_renewals.length} pending', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ),
        if (_renewals.isEmpty)
          const SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text("No pending renewal requests found", style: TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildRenewalCard(_renewals[index]),
              childCount: _renewals.length,
            ),
          ),
      ],
    );
  }

  Widget _buildRenewalCard(Map<String, dynamic> renewal) {
    String name = renewal['student_name'] ?? 'Unknown';
    String reg = (renewal['student_reg_no'] ?? 'N/A').toString();
    String room = renewal['room_number'] ?? 'N/A';
    String date = renewal['requested_at']?.toString().split(' ')[0] ?? 'N/A';
    String initials = name.isNotEmpty ? name.split(' ').where((s)=>s.isNotEmpty).map((l)=>l[0]).take(2).join().toUpperCase() : "?";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: SkeuomorphicStyles.skeuomorphicCard,
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: SkeuomorphicColors.goldGlossyGradient),
                child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Reg No: $reg • Room $room', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Text(date, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  'Reject', 
                  Colors.red, 
                  () => _handleAction(renewal, 'reject')
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  'Approve', 
                  Colors.green, 
                  () => _handleAction(renewal, 'approve')
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.1),
        foregroundColor: color,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Future<void> _handleAction(Map<String, dynamic> renewal, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${action[0].toUpperCase()}${action.substring(1)} Request?'),
        content: Text('Are you sure you want to $action this renewal request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action, style: TextStyle(color: action == 'approve' ? Colors.green : Colors.red))),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      bool success = false;
      final id = renewal['id'];
      if (action == 'approve') {
        final res = await ApiService.approveRenewal(int.parse(id.toString()));
        success = res['success'] == true;
      } else {
        final res = await ApiService.rejectRenewal(int.parse(id.toString()));
        success = res['success'] == true;
      }
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Renewal $action successful')));
        _fetchRenewals();
      }
    }
  }
}
