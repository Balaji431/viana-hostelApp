import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/design_system.dart' as ds;
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';

class WardenAllocationScreen extends StatefulWidget {
  const WardenAllocationScreen({super.key});

  @override
  State<WardenAllocationScreen> createState() => _WardenAllocationScreenState();
}

class _WardenAllocationScreenState extends State<WardenAllocationScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = false;
  String _filterStatus = 'under_review';
  
  // Batch processing state
  Set<int> _selectedRequestIds = {};
  
  // Right panel state
  Map<String, dynamic>? _selectedRequest;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/allocation/warden_requests.php?status=$_filterStatus'));
      final data = json.decode(response.body);
      if (data['success']) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(data['requests']);
          // Clear selections if they no longer exist in the new data
          _selectedRequestIds.retainWhere((id) => _requests.any((req) => req['id'] == id));
          if (_selectedRequest != null && !_requests.any((req) => req['id'] == _selectedRequest!['id'])) {
            _selectedRequest = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _toggleSelectAll() {
    setState(() {
      final matchedRequests = _requests.where((r) => r['first_priority_held'] != true && r['recommended_room'] != null).toList();
      
      bool allMatchedSelected = matchedRequests.isNotEmpty && matchedRequests.every((r) => _selectedRequestIds.contains(r['id']));
      
      if (allMatchedSelected) {
        for (var r in matchedRequests) {
          _selectedRequestIds.remove(r['id']);
        }
      } else {
        for (var r in matchedRequests) {
          _selectedRequestIds.add(r['id'] as int);
        }
      }
    });
  }

  Future<void> _runAutoAllocation() async {
    final user = context.read<UserProvider>();
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/auto_allocate.php'),
        body: json.encode({
          'action': 'preview',
          'request_ids': _selectedRequestIds.toList(),
          'warden_id': user.dbId
        }),
      );
      final data = json.decode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        _showAutoAllocationPreview(data['preview'] ?? [], data['summary'] ?? {});
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Failed to generate preview')));
      }
    } catch (e) {
      debugPrint("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server Error')));
    }
  }
  
  void _showAutoAllocationPreview(List<dynamic> previewList, Map<String, dynamic> summary) {
     showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: ds.RoyalTheme.linenStart,
        title: Text('Allocation Preview', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('Matched: ${summary['matched']}', style: TextStyle(color: ds.RoyalTheme.successMid, fontWeight: FontWeight.bold)),
                  Text('Rejected: ${summary['rejected']}', style: TextStyle(color: ds.RoyalTheme.dangerMid, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: previewList.length,
                  itemBuilder: (ctx, i) {
                    final item = previewList[i];
                    final isMatched = item['status'] == 'matched';
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isMatched ? Icons.check_circle : Icons.warning_amber_rounded,
                        color: isMatched ? ds.RoyalTheme.successMid : ds.RoyalTheme.warningMid,
                      ),
                      title: Text(item['student_name'] ?? ''),
                      subtitle: Text(item['room_display'] ?? ''),
                      trailing: isMatched ? Text('P${item['priority_matched']}', style: const TextStyle(fontWeight: FontWeight.bold)) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ds.RoyalTheme.navyStart, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _confirmAutoAllocation();
            },
            child: const Text('Confirm Allocations'),
          ),
        ],
      )
    );
  }

  Future<void> _confirmAutoAllocation() async {
    setState(() => _isLoading = true);
    final user = context.read<UserProvider>();
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/auto_allocate.php'),
        body: json.encode({
          'action': 'confirm',
          'request_ids': _selectedRequestIds.toList(),
          'warden_id': user.dbId
        }),
      );
      final data = json.decode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        _selectedRequestIds.clear();
        _selectedRequest = null;
        _fetchRequests();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Allocations confirmed!'), backgroundColor: ds.RoyalTheme.successMid));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Failed to confirm')));
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ds.LinenBackground(
        child: Column(
          children: [
            const ds.SkeuomorphicNavBar(title: 'Smart Allocation System'),
            
            // Filters
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('New Student Queue', 'under_review'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Approved', 'approved'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Rejected', 'rejected'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Expired', 'payment_expired'),
                  ],
                ),
              ),
            ),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isDesktop = constraints.maxWidth >= 600;
                  return isDesktop 
                      ? _buildSplitLayout() 
                      : _buildMobileLayout();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT SIDE - QUEUE
        Expanded(
          flex: 4,
          child: Column(
            children: [
              _buildBatchActionsBar(),
              Expanded(child: _buildQueueList()),
            ],
          ),
        ),
        
        // Vertical Divider
        Container(width: 1, color: Colors.grey.withOpacity(0.3)),
        
        // RIGHT SIDE - DETAILS
        Expanded(
          flex: 6,
          child: _selectedRequest == null 
              ? _buildEmptyState()
              : _buildExpandedStudentDetails(_selectedRequest!),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    // For mobile, we might just show the list, and pushing details on tap. 
    // To stick to the "expandable panel" concept, we'll keep it simple for now.
    if (_selectedRequest != null) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _selectedRequest = null),
            ),
          ),
          Expanded(child: _buildExpandedStudentDetails(_selectedRequest!)),
        ],
      );
    }
    
    return Column(
      children: [
        _buildBatchActionsBar(),
        Expanded(child: _buildQueueList()),
      ],
    );
  }

  Widget _buildBatchActionsBar() {
    final bool allSelected = _requests.isNotEmpty && _selectedRequestIds.length == _requests.length;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.15))),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: _requests.isEmpty ? null : (val) => _toggleSelectAll(),
            activeColor: ds.RoyalTheme.primaryGoldEnd,
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Text(
              'Select All (${_selectedRequestIds.length})', 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_filterStatus == 'submitted')
            ElevatedButton.icon(
              onPressed: _selectedRequestIds.isEmpty ? null : _runAutoAllocation,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('Auto Match', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: ds.RoyalTheme.navyStart,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                elevation: 0,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: ds.RoyalTheme.primaryGoldEnd));
    if (_requests.isEmpty) return const Center(child: Text('No requests found in this queue.'));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final req = _requests[index];
        final bool isSelected = _selectedRequestIds.contains(req['id']);
        final bool isViewing = _selectedRequest?['id'] == req['id'];
        
        // auto-match status
        final bool hasMatch = req['recommended_room'] != null;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              border: isViewing ? Border.all(color: ds.RoyalTheme.primaryGoldEnd, width: 2) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ds.SkeuomorphicCard(
              onTap: () => setState(() => _selectedRequest = req),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) _selectedRequestIds.add(req['id']);
                        else _selectedRequestIds.remove(req['id']);
                      });
                    },
                    activeColor: ds.RoyalTheme.primaryGoldEnd,
                  ),
                  CircleAvatar(
                    backgroundColor: ds.RoyalTheme.navyStart,
                    child: Text(req['student_name']?[0] ?? 'S', style: const TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          req['student_name'] ?? 'Unknown',
                          style: GoogleFonts.playfairDisplay(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'ID: ${req['student_reg_no']}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  // Auto-Match / Approval Status Badge
                  if (req['allocation_status'] == 'payment_expired')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.dangerMid.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('EXPIRED', style: TextStyle(color: ds.RoyalTheme.dangerMid, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else if (req['allocation_status'] == 'approved')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.successMid.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('PAID', style: TextStyle(color: ds.RoyalTheme.successMid, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else if (req['allocation_status'] == 'under_review')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.primaryGoldEnd.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('SUGGESTED', style: TextStyle(color: ds.RoyalTheme.primaryGoldEnd, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else if (req['allocation_status'] == 'payment_pending')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.primaryGoldEnd.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('PENDING PAYMENT', style: TextStyle(color: ds.RoyalTheme.primaryGoldEnd, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else if (req['allocation_status'] == 'rejected')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.dangerMid.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('REJECTED', style: TextStyle(color: ds.RoyalTheme.dangerMid, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else if (hasMatch)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.successMid.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text('MATCHED', style: TextStyle(color: ds.RoyalTheme.successMid, fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: ds.RoyalTheme.warningMid.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Text('CONFLICT', style: TextStyle(color: ds.RoyalTheme.warningMid, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: isViewing ? ds.RoyalTheme.primaryGoldEnd : Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rule_folder_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Select a student to view allocation details',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedStudentDetails(Map<String, dynamic> request) {
    final recommendedRoomId = request['recommended_room']?['room_id'];
    
    return Container(
      color: Colors.white.withOpacity(0.5),
      child: Column(
        children: [
          // Student Info Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: ds.RoyalTheme.navyGradient,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                CircleAvatar(radius: 30, backgroundColor: ds.RoyalTheme.primaryGoldEnd, child: Text(request['student_name']?[0] ?? 'S', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(request['student_name'], style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('Reg No: ${request['student_reg_no']} • Submitted: ${_formatSubmissionTime(request['submitted_at'])}', style: const TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Priorities List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (request['allocation_status'] == 'under_review') ...[
                  Text('PAID HOSTEL SPECIFICATIONS', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  _buildDirectorPaidSpecsCard(request['director_paid_data']),
                  const SizedBox(height: 24),
                  Text('SUGGESTED AUTO-ALLOCATED ROOM & BED', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  _buildSuggestedAllocationCard(request),
                ] else ...[
                  Text('PRIORITY QUEUE', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 16),
                  
                  if (request['priorities'] != null)
                    ...(request['priorities'] as List).asMap().entries.map((entry) {
                      final int idx = entry.key;
                      final p = entry.value;
                      final int capacity = int.tryParse(p['capacity'].toString()) ?? 0;
                      final int occupied = int.tryParse(p['occupied'].toString()) ?? 0;
                      final int available = capacity - occupied;
                      final bool isFull = available <= 0;
                      
                      final String status = request['allocation_status'] ?? 'submitted';
                      final String? allocatedId = request['allocated_room_id']?.toString();
                      final String? roomId = p['room_id']?.toString();
                      
                      final bool isAllocated = status == 'approved' && allocatedId == roomId;
                      final bool isReserved = status == 'payment_pending' && allocatedId == roomId;
                      final bool isExpiredRoom = status == 'payment_expired' && allocatedId == roomId;
                      
                      return _buildPriorityCard(idx + 1, p, isFull, available, isAllocated, isReserved, isExpiredRoom: isExpiredRoom);
                    }).toList(),
                ]
              ],
            ),
          ),
          
          // Smart Action Buttons / Statuses
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            ),
            child: request['allocation_status'] == 'payment_expired'
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: ds.RoyalTheme.dangerMid.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ds.RoyalTheme.dangerMid),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.timer_off_outlined, color: ds.RoyalTheme.dangerMid),
                            const SizedBox(width: 8),
                            Text(
                              'RESERVATION EXPIRED',
                              style: TextStyle(
                                color: ds.RoyalTheme.dangerMid,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: null,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.grey.shade400,
                                side: BorderSide(color: Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Approve Match'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey.shade200,
                                foregroundColor: Colors.grey.shade400,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : request['allocation_status'] == 'approved'
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: ds.RoyalTheme.successMid.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ds.RoyalTheme.successMid),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, color: ds.RoyalTheme.successMid),
                        const SizedBox(width: 8),
                        Text(
                          'ALLOCATED & PAID',
                          style: TextStyle(
                            color: ds.RoyalTheme.successMid,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  )
                : request['allocation_status'] == 'payment_pending'
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _processSingleAction(request['id'], 'release_room', null),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ds.RoyalTheme.warningMid,
                                side: BorderSide(color: ds.RoyalTheme.warningMid),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Release Hold'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: ds.RoyalTheme.primaryGoldStart.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: ds.RoyalTheme.primaryGoldEnd),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.hourglass_empty, color: ds.RoyalTheme.primaryGoldEnd, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'PENDING PAYMENT',
                                    style: TextStyle(
                                      color: ds.RoyalTheme.navyDarker,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : request['allocation_status'] == 'under_review'
                        ? Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _processSingleAction(request['id'], 'reject', null),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: ds.RoyalTheme.dangerMid,
                                    side: const BorderSide(color: ds.RoyalTheme.dangerMid),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _showModifyRoomDialog(request),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: ds.RoyalTheme.warningMid,
                                    side: BorderSide(color: ds.RoyalTheme.warningMid),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('Modify'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  onPressed: () => _processSingleAction(request['id'], 'approve', (request['allocated_room_id'] != null) ? int.parse(request['allocated_room_id'].toString()) : null),
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: const Text('Approve Match', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ds.RoyalTheme.primaryGoldStart,
                                    foregroundColor: ds.RoyalTheme.navyDarker,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (request['first_priority_held'] == true) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Waiting: 1st Priority Room is locked under active payment holds. Auto-bypass disabled.',
                                          style: GoogleFonts.lato(
                                            fontSize: 12, 
                                            color: Colors.amber.shade900, 
                                            fontWeight: FontWeight.bold
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _processSingleAction(request['id'], 'reject', null),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: ds.RoyalTheme.dangerMid,
                                        side: const BorderSide(color: ds.RoyalTheme.dangerMid),
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (request['first_priority_held'] == true) ...[
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: (request['notified_of_conflict'] == 1 || request['notified_of_conflict'] == '1')
                                                  ? null 
                                                  : () => _processSingleAction(request['id'], 'notify_conflict', null),
                                              icon: const Icon(Icons.notifications_active_outlined, size: 16),
                                              label: Text((request['notified_of_conflict'] == 1 || request['notified_of_conflict'] == '1') ? 'Updated' : 'Update'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: ds.RoyalTheme.primaryGoldStart,
                                                foregroundColor: ds.RoyalTheme.navyDarker,
                                                padding: const EdgeInsets.symmetric(vertical: 16),
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: null,
                                              icon: const Icon(Icons.hourglass_bottom, size: 16),
                                              label: const Text('Wait to Approve', style: TextStyle(fontSize: 11)),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.grey.shade200,
                                                foregroundColor: Colors.grey.shade500,
                                                padding: const EdgeInsets.symmetric(vertical: 16),
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    Expanded(
                                      flex: 2,
                                      child: ElevatedButton.icon(
                                        onPressed: recommendedRoomId == null ? null : () => _processSingleAction(request['id'], 'approve', int.parse(recommendedRoomId.toString())),
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text('Approve Match'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: ds.RoyalTheme.primaryGoldStart,
                                          foregroundColor: ds.RoyalTheme.navyDarker,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
          )
        ],
      ),
    );
  }

  Widget _buildPriorityCard(int priorityNum, Map<String, dynamic> room, bool isFull, int available, bool isAllocated, bool isReserved, {bool isExpiredRoom = false}) {
    final bool hasHighlight = isAllocated || isReserved || isExpiredRoom;
    final Color highlightColor = isExpiredRoom ? ds.RoyalTheme.dangerMid : (isAllocated ? ds.RoyalTheme.successMid : ds.RoyalTheme.primaryGoldEnd);
    final Color highlightBg = isExpiredRoom ? ds.RoyalTheme.dangerMid.withOpacity(0.08) : (isAllocated ? ds.RoyalTheme.successMid.withOpacity(0.08) : ds.RoyalTheme.primaryGoldStart.withOpacity(0.08));
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: hasHighlight ? highlightBg : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasHighlight ? highlightColor : Colors.grey.withOpacity(0.2),
          width: hasHighlight ? 2 : 1,
        ),
        boxShadow: [
          if (hasHighlight) BoxShadow(color: highlightColor.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))
        ]
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Priority Number Bubble
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: hasHighlight ? highlightColor : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('$priorityNum', style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: hasHighlight ? Colors.white : Colors.grey.shade600
                )),
              ),
            ),
            const SizedBox(width: 16),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${room['room_type']}', 
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: ds.RoyalTheme.navyDarker,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.meeting_room_outlined, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text('Room ${room['room_no']} (${room['building_code']})', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bed_outlined, size: 14, color: isFull ? ds.RoyalTheme.dangerMid : Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text('$available beds available', style: TextStyle(fontSize: 12, color: isFull ? ds.RoyalTheme.dangerMid : Colors.grey.shade600, fontWeight: isFull ? FontWeight.bold : FontWeight.normal)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            
            // Status Badges
            if (isAllocated)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: ds.RoyalTheme.successMid, borderRadius: BorderRadius.circular(20)),
                child: const Text('ALLOCATED & PAID', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              )
            else if (isReserved)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: ds.RoyalTheme.primaryGoldEnd, borderRadius: BorderRadius.circular(20)),
                child: const Text('RESERVED HOLD', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              )
            else if (isExpiredRoom)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: ds.RoyalTheme.dangerMid, borderRadius: BorderRadius.circular(20)),
                child: const Text('HOLD EXPIRED', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              )
            else if (isFull)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: ds.RoyalTheme.dangerMid, borderRadius: BorderRadius.circular(20)),
                child: const Text('CONFLICT: FULL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _processSingleAction(dynamic allocationId, String action, int? roomId) async {
    final user = context.read<UserProvider>();
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/warden_requests.php'),
        body: json.encode({
          'action': action,
          'allocation_id': allocationId,
          'room_id': roomId,
          'warden_id': user.dbId
        }),
      );
      final data = json.decode(response.body);
      if (data['success'] == true) {
        if (!mounted) return;
        if (action == 'notify_conflict') {
          setState(() {
            if (_selectedRequest != null) {
              _selectedRequest!['notified_of_conflict'] = 1;
            }
          });
          _fetchRequests();
        } else {
          setState(() => _selectedRequest = null);
          _fetchRequests();
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Action completed successfully'), backgroundColor: ds.RoyalTheme.successMid));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Failed to process request')));
      }
    } catch (e) {
      debugPrint("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server Error')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildFilterChip(String label, String status) {
    final isSelected = _filterStatus == status;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _filterStatus = status;
            _selectedRequest = null;
            _selectedRequestIds.clear();
          });
          _fetchRequests();
        }
      },
      selectedColor: ds.RoyalTheme.primaryGoldStart,
      labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.grey, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  String _formatSubmissionTime(dynamic timestamp) {
    if (timestamp == null || timestamp.toString().isEmpty) {
      return 'Just now';
    }
    try {
      String ts = timestamp.toString();
      if (!ts.contains('T') && ts.contains(' ')) {
        ts = ts.replaceFirst(' ', 'T');
      }
      final date = DateTime.parse(ts).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final submittedDay = DateTime(date.year, date.month, date.day);
      final difference = today.difference(submittedDay).inDays;
      
      final timeStr = DateFormat('hh:mm a').format(date);
      if (difference == 0) {
        return 'Today at $timeStr';
      } else if (difference == 1) {
        return 'Yesterday at $timeStr';
      } else {
        return '${DateFormat('dd MMM yyyy').format(date)} at $timeStr';
      }
    } catch (e) {
      return timestamp.toString();
    }
  }

  Widget _buildDirectorPaidSpecsCard(Map<String, dynamic>? data) {
    if (data == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No Director application paid specifications found.'),
        ),
      );
    }
    final hType = data['hostel_type'] ?? 'Girls';
    final rType = data['room_type'] ?? 'AC - B ATTACHED (6 IN 1)';
    final facility = data['facility'] ?? 'AC';
    final amount = data['paid_amount'] ?? 68000.00;
    final inst = data['institution'] ?? 'Saveetha School of Engineering';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          _buildWardenDetailRow('Institution', inst),
          const SizedBox(height: 8),
          _buildWardenDetailRow('Hostel Category', '$hType Hostel'),
          const SizedBox(height: 8),
          _buildWardenDetailRow('Room Specification', rType),
          const SizedBox(height: 8),
          _buildWardenDetailRow('Facility Option', facility),
          const SizedBox(height: 8),
          _buildWardenDetailRow('Amount Paid', '₹${amount.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildWardenDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1A2744)),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestedAllocationCard(Map<String, dynamic> request) {
    final roomNo = request['allocated_room_no'] ?? 'N/A';
    final block = request['allocated_block'] ?? 'N/A';
    final bed = request['allocated_bed_no'] ?? 'B1';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ds.RoyalTheme.successMid.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.RoyalTheme.successMid, width: 2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ds.RoyalTheme.successMid,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bed, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested Room $roomNo',
                  style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, fontSize: 16, color: ds.RoyalTheme.navyDarker),
                ),
                Text(
                  'Block: $block • Bed: $bed',
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showModifyRoomDialog(Map<String, dynamic> request) async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> allRooms = [];
    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/allocation/get_rooms.php'));
      final data = json.decode(response.body);
      if (data['success'] == true) {
        allRooms = List<Map<String, dynamic>>.from(data['rooms']);
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }

    if (allRooms.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No rooms available')));
      }
      return;
    }

    final String targetHostelType = request['director_paid_data']?['hostel_type'] ?? 'Girls';
    final String targetFacility = request['director_paid_data']?['facility'] ?? 'AC';
    final String targetRoomType = request['director_paid_data']?['room_type'] ?? '';

    final filteredRooms = allRooms.where((r) {
      final String hType = r['hostel_type'] ?? 'Girls';
      final String facility = r['facility'] ?? 'AC';
      final String rType = r['room_type'] ?? '';
      final int available = r['available'] ?? 0;
      
      bool matchesRoomType = true;
      if (targetRoomType.isNotEmpty) {
        matchesRoomType = rType.toLowerCase() == targetRoomType.toLowerCase();
      }

      return hType.toLowerCase() == targetHostelType.toLowerCase() &&
             facility.toLowerCase() == targetFacility.toLowerCase() &&
             matchesRoomType &&
             available > 0;
    }).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.RoyalTheme.linenStart,
        title: Text(
          'Modify Room Allocation',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Student: ${request['student_name']}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                'Paid Target: $targetHostelType ($targetFacility)',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: filteredRooms.isEmpty
                    ? const Center(child: Text('No other matching vacant rooms found'))
                    : ListView.builder(
                        itemCount: filteredRooms.length,
                        itemBuilder: (context, index) {
                          final r = filteredRooms[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text('Room ${r['number']} (${r['block']})'),
                              subtitle: Text('${r['room_type']} • ${r['available']} beds vacant'),
                              trailing: const Icon(Icons.arrow_forward, color: Color(0xFFC5A358)),
                              onTap: () {
                                Navigator.pop(ctx);
                                _processSingleAction(request['id'], 'approve', int.parse(r['id'].toString()));
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
