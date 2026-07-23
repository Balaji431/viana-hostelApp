import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/design_system.dart' as ds;
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';
import '../../core/royal_theme.dart';

class WardenAllocationScreen extends StatefulWidget {
  const WardenAllocationScreen({super.key});

  @override
  State<WardenAllocationScreen> createState() => _WardenAllocationScreenState();
}

class _WardenAllocationScreenState extends State<WardenAllocationScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = false;
  String _filterStatus = 'under_review';
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  
  // Batch processing state
  final Set<int> _selectedRequestIds = {};
  
  // Right panel state
  Map<String, dynamic>? _selectedRequest;

  final Map<int, Map<String, dynamic>> _selectedAllocations = {};

  String _roleScope = 'floor_warden';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final user = context.read<UserProvider>();
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/allocation/warden_requests.php?status=$_filterStatus'),
        headers: {
          'X-User-Id': user.dbId.toString(),
          'X-User-Role': user.role.name,
          'X-User-Username': user.username,
        },
      );
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _requests = List<Map<String, dynamic>>.from(data['requests']);
          _roleScope = data['role_scope'] ?? 'floor_warden';
          // Clear selections if they no longer exist in the new data
          _selectedRequestIds.retainWhere((id) => _requests.any((req) => req['id'] == id));
          if (_selectedRequest != null) {
            final idx = _requests.indexWhere((req) => req['id'] == _selectedRequest!['id']);
            if (idx == -1) {
              _selectedRequest = null;
            } else {
              _selectedRequest = _requests[idx];
            }
          }
        });
      } else {
        setState(() {
          _requests = [];
          _errorMessage = data['message'] ?? 'Failed to load requests';
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() {
        _requests = [];
        _errorMessage = 'An error occurred: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      key: _scaffoldKey,

      body: ds.LinenBackground(
        child: Column(
          children: [
            const ds.SkeuomorphicNavBar(title: 'Room Allocation'),
            
            // Filters
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Room Requests', 'under_review'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Approved', 'approved'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Rejected', 'rejected'),
                  ],
                ),
              ),
            ),

            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  Widget queueList = _buildQueueList();
                  if (constraints.maxWidth >= 800) {
                    queueList = Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: 800,
                        child: queueList,
                      ),
                    );
                  }
                  return queueList;
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
              : _buildExpandedStudentDetails(_selectedRequest!, setState),
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
          Expanded(child: _buildExpandedStudentDetails(_selectedRequest!, setState)),
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
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_requests.isEmpty) return const Center(child: Text('No requests found in this queue.'));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final req = _requests[index];
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
              onTap: () {
                setState(() => _selectedRequest = req);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StatefulBuilder(
                      builder: (context, setModalState) {
                        return Scaffold(
                          body: SafeArea(
                            child: _buildExpandedStudentDetails(req, setModalState),
                          ),
                        );
                      }
                    ),
                  ),
                );
              },
              child: Row(
                children: [
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
                          style: GoogleFonts.lato(fontSize: 16, fontWeight: FontWeight.bold),
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
                      child: Text('REQUESTED', style: TextStyle(color: ds.RoyalTheme.primaryGoldEnd, fontSize: 10, fontWeight: FontWeight.bold)),
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

  Widget _buildExpandedStudentDetails(Map<String, dynamic> request, StateSetter setModalState) {
    final recommendedRoomId = request['recommended_room']?['room_id'];
    final bool hasSelected = _selectedAllocations.containsKey(request['id']);
    
    // Extract details
    final String studentName = request['student_name'] ?? 'Unknown';
    final String studentId = request['student_reg_no'] ?? 'N/A';
    final String allocationStatus = request['allocation_status'] ?? 'submitted';
    final bool isPaid = allocationStatus == 'approved';
    final String paidStatus = isPaid ? 'Paid' : (allocationStatus == 'payment_pending' ? 'Pending Payment' : 'Requested');
    
    final String hostelName = request['director_paid_data']?['hostel_name'] ?? 'Ponni Hostel';
    final String hostelPreference = request['director_paid_data']?['room_type'] ?? '4 IN 1 Non AC';
    final String institution = request['director_paid_data']?['institution'] ?? 'Poonamallee Campus';
    final String gender = request['director_paid_data']?['hostel_type'] ?? 'Male';
    final String academicYear = request['academic_year'] ?? '1st Year';
    final double feeAmount = double.tryParse(request['director_paid_data']?['paid_amount']?.toString() ?? '86000') ?? 86000.00;
    final String feePaid = '₹${feeAmount.toStringAsFixed(2)}';

    return Container(
      color: const Color(0xFFFDFBF7), // Warm premium background
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Blue Header Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              gradient: ds.RoyalTheme.navyGradient,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Room Allocation Requests',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
          
          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Main Card Container (Matches First Image)
                  Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    )
                  ],
                  border: Border.all(color: ds.RoyalTheme.primaryGoldStart, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Student Profile Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                studentName,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1B2B48),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'ID: $studentId',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Paid Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPaid ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            paidStatus,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.black12, height: 1),
                    const SizedBox(height: 20),

                    if (request['allocated_room_code'] != null || request['allocated_room_no'] != null) ...[
                      Text(
                        'SUGGESTED AUTO-ALLOCATED ROOM & BED',
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildSuggestedAllocationCard(request),
                    ] else ...[
                      // Detail Rows (Matches Second Image)
                      _buildAllocationDetailRow('Paid Status', paidStatus),
                      const SizedBox(height: 12),
                      _buildAllocationDetailRow('Hostel Name', hostelName),
                      const SizedBox(height: 12),
                      _buildAllocationDetailRow('Hostel Preference', hostelPreference),
                      const SizedBox(height: 12),
                      _buildAllocationDetailRow('Institution', institution),
                      const SizedBox(height: 12),
                      _buildAllocationDetailRow('Gender', gender),
                      const SizedBox(height: 12),
                      _buildAllocationDetailRow('Academic Year', academicYear),
                      const SizedBox(height: 12),
                      _buildAllocationDetailRow('Fee Paid', feePaid),
                    ],
                    
                    const SizedBox(height: 24),
                    
                    // Show selected room details if selected
                    if (_selectedAllocations.containsKey(request['id'])) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      Text('SELECTED ROOM & BED', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      _buildSelectedAllocationCard(_selectedAllocations[request['id']]!),
                    ],
                    
                    const SizedBox(height: 32),

                    // Action Buttons depending on allocationStatus
                    if (allocationStatus == 'approved') ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _processSingleAction(request['id'], 'deallocate', null);
                          },
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Deallocate Room'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ds.RoyalTheme.dangerMid,
                            side: const BorderSide(color: ds.RoyalTheme.dangerMid),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ] else if (allocationStatus == 'payment_pending') ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _processSingleAction(request['id'], 'release_room', null);
                              },
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
                                    'HOLD PENDING',
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
                    ] else if (allocationStatus == 'payment_expired') ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                              'HOLD EXPIRED',
                              style: TextStyle(
                                color: ds.RoyalTheme.dangerMid,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _processSingleAction(request['id'], 'reject', null);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: ds.RoyalTheme.dangerMid,
                                side: BorderSide(color: ds.RoyalTheme.dangerMid),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text(
                                'Reject',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _showRoomSelectionDialog(request, setModalState);
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber.shade700,
                                side: BorderSide(color: Colors.amber.shade400),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text(
                                'Availability',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: (hasSelected || request['allocated_room_code'] != null || request['recommended_room'] != null)
                                  ? () {
                                      Navigator.pop(context);
                                      if (hasSelected) {
                                        final selection = _selectedAllocations[request['id']];
                                        if (selection != null) {
                                          final int? roomId = int.tryParse(selection['room']['id'].toString());
                                          final String bedNo = selection['bed'].toString();
                                          _processSingleAction(request['id'], 'approve', roomId, bedNo: bedNo);
                                        }
                                      } else {
                                        final recommendedRoomId = request['recommended_room']?['room_id'] ?? request['allocated_room_id'];
                                        final String? bedNo = request['allocated_bed_no']?.toString();
                                        if (recommendedRoomId != null) {
                                          _processSingleAction(
                                            request['id'],
                                            'approve',
                                            int.parse(recommendedRoomId.toString()),
                                            bedNo: bedNo,
                                          );
                                        }
                                      }
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ds.RoyalTheme.primaryGoldStart,
                                foregroundColor: ds.RoyalTheme.navyDarker,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text(
                                'Approve Match',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF1B2B48),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
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
                          style: GoogleFonts.lato(
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

  Future<void> _processSingleAction(dynamic allocationId, String action, int? roomId, {String? bedNo}) async {
    final user = context.read<UserProvider>();
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/allocation/warden_requests.php'),
        headers: {
          'X-User-Id': user.dbId.toString(),
          'X-User-Role': user.role.name,
          'X-User-Username': user.username,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'action': action,
          'allocation_id': allocationId,
          'room_id': roomId,
          'bed_no': bedNo,
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
    final roomCode = request['allocated_room_code'] ?? request['allocated_room_no'] ?? 'N/A';
    final block = request['allocated_block'] ?? 'N/A';
    final bed = request['allocated_bed_no'] ?? 'B1';
    final hostel = request['allocated_hostel_name'] ?? 'N/A';
    final roomType = request['allocated_room_type'] ?? 'N/A';
    final int capacity = int.tryParse(request['allocated_room_capacity']?.toString() ?? '') ?? 4;
    final int occupied = int.tryParse(request['allocated_room_occupied']?.toString() ?? '') ?? 0;
    // allocated_room_available comes directly from hostel_rooms.available_rooms — ground truth
    final int available = int.tryParse(request['allocated_room_available']?.toString() ?? '') ?? (capacity - occupied);
    final int displayNumerator = occupied + 1;
    final floor = request['allocated_floor'] ?? 'N/A';
    final wing = request['allocated_wing'] ?? 'N/A';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ds.RoyalTheme.successMid.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.RoyalTheme.successMid, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ds.RoyalTheme.successMid,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bed, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested Room',
                      style: GoogleFonts.lato(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    Text(
                      roomCode,
                      style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 16, color: ds.RoyalTheme.navyDarker),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: Colors.black12),
          const SizedBox(height: 12),
          _buildSuggestedDetailRow('Bed', bed),
          _buildSuggestedDetailRow('Hostel', hostel),
          _buildSuggestedDetailRow('Room Type', roomType),
          _buildSuggestedDetailRow('Vacant Beds', '$displayNumerator / $capacity'),
          _buildSuggestedDetailRow('Building', block),
          _buildSuggestedDetailRow('Floor', floor),
          _buildSuggestedDetailRow('Wing', wing),
        ],
      ),
    );
  }

  Widget _buildSuggestedDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: ds.RoyalTheme.navyDarker, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedAllocationCard(Map<String, dynamic> selection) {
    final room = selection['room'];
    final bed = selection['bed'];
    final roomCode = room['room_code'] ?? room['number'] ?? 'N/A';
    final block = room['block'] ?? 'N/A';
    final hostel = room['hostel_name'] ?? 'N/A';
    final roomType = room['room_type'] ?? 'N/A';
    final int capacity = room['capacity'] ?? 4;
    final int available = room['available'] ?? 0;
    final floor = room['floor'] ?? 'N/A';
    final wing = room['wing_code'] ?? 'N/A';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ds.RoyalTheme.successMid.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.RoyalTheme.successMid, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ds.RoyalTheme.successMid,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bed, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Room',
                      style: GoogleFonts.lato(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    Text(
                      roomCode,
                      style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 16, color: ds.RoyalTheme.navyDarker),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, thickness: 1, color: Colors.black12),
          const SizedBox(height: 12),
          _buildSuggestedDetailRow('Bed', bed),
          _buildSuggestedDetailRow('Hostel', hostel),
          _buildSuggestedDetailRow('Room Type', roomType),
          _buildSuggestedDetailRow('Vacant Beds Ratio', '$available / $capacity'),
          _buildSuggestedDetailRow('Building', block),
          _buildSuggestedDetailRow('Floor', floor),
          _buildSuggestedDetailRow('Wing', wing),
        ],
      ),
    );
  }

  Future<void> _showRoomSelectionDialog(Map<String, dynamic> request, StateSetter setModalState) async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> allRooms = [];
    try {
      final response = await http.get(Uri.parse('${ApiService.baseUrl}/allocation/get_rooms.php?student_id=${request['student_id']}'));
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
    final String targetHostelName = request['director_paid_data']?['hostel_name'] ?? '';

    final filteredRooms = allRooms.where((r) {
      final String hType = r['hostel_type'] ?? 'Girls';
      final String facility = r['facility'] ?? 'AC';
      final String hName = r['hostel_name'] ?? '';
      final int available = r['available'] ?? 0;
      
      final String normTargetHostel = targetHostelName.replaceAll(' Hostel', '').trim().toLowerCase();
      final String normRoomHostel = hName.replaceAll(' Hostel', '').trim().toLowerCase();
      final bool matchesHostel = normRoomHostel.startsWith(normTargetHostel) || normTargetHostel.startsWith(normRoomHostel) || normRoomHostel.contains(normTargetHostel);

      return matchesHostel &&
             hType.toLowerCase() == targetHostelType.toLowerCase() &&
             facility.toLowerCase() == targetFacility.toLowerCase() &&
             available > 0;
    }).toList();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.RoyalTheme.linenStart,
        title: Text(
          'Check Availability',
          style: GoogleFonts.lato(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 400,
          height: 450,
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
                          final int available = r['available'] ?? 0;
                          final int capacity = r['capacity'] ?? 0;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text('Room ${r['number']} (${r['block']})'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${r['hostel_name']} • ${r['room_type']}'),
                                  Text('Room Code: ${r['room_code'] ?? 'N/A'}'),
                                  Text('$available / $capacity beds available', style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward, color: Color(0xFFC5A358)),
                              onTap: () {
                                _showBedSelectionDialog(ctx, request, r, setModalState);
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

  void _showBedSelectionDialog(BuildContext parentCtx, Map<String, dynamic> request, Map<String, dynamic> room, StateSetter setModalState) {
    final int capacity = room['capacity'] ?? 4;
    final List<dynamic> occupiedBeds = room['occupied_beds'] ?? [];
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ds.RoyalTheme.linenStart,
        title: Text(
          'Select Bed - Room ${room['room_code'] ?? room['number']}',
          style: GoogleFonts.lato(fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Capacity: $capacity Beds', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.2,
                ),
                itemCount: capacity,
                itemBuilder: (context, idx) {
                  final int b = idx + 1;
                  final String bedLabel = 'B$b';
                  final bool isOccupied = occupiedBeds.contains(bedLabel);
                  
                  return InkWell(
                    onTap: isOccupied ? null : () {
                      setState(() {
                        _selectedAllocations[request['id']] = {
                          'room': room,
                          'bed': bedLabel,
                        };
                      });
                      setModalState(() {});
                      Navigator.pop(ctx);
                      Navigator.pop(parentCtx);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isOccupied ? Colors.grey.shade300 : Colors.white,
                        border: Border.all(
                          color: isOccupied ? Colors.grey : ds.RoyalTheme.primaryGoldEnd,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isOccupied ? Icons.person : Icons.bed_outlined,
                            color: isOccupied ? Colors.grey.shade600 : ds.RoyalTheme.navyDarker,
                            size: 20,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bedLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: isOccupied ? Colors.grey.shade600 : ds.RoyalTheme.navyDarker,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

enum ApprovalActionColor { reject, availability, approve }

class IOS6ApprovalActions extends StatelessWidget {
  final VoidCallback? onReject;
  final VoidCallback? onCheckAvailability;
  final VoidCallback? onApprove;
  final bool approveEnabled;

  const IOS6ApprovalActions({
    super.key,
    this.onReject,
    this.onCheckAvailability,
    this.onApprove,
    this.approveEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 450;
        final double fontSize = isNarrow ? 10.0 : 13.0;
        final double spacing = isNarrow ? 6.0 : 10.0;

        final buttons = [
          Expanded(
            flex: 1,
            child: IOS6ActionButton(
              label: 'Reject',
              type: ApprovalActionColor.reject,
              icon: Icons.close_rounded,
              onPressed: onReject,
              fontSize: fontSize,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            flex: 1,
            child: IOS6ActionButton(
              label: 'Availability',
              type: ApprovalActionColor.availability,
              icon: Icons.calendar_month_outlined,
              onPressed: onCheckAvailability,
              fontSize: fontSize,
            ),
          ),
          SizedBox(width: spacing),
          Expanded(
            flex: 1,
            child: IOS6ActionButton(
              label: 'Approve Match',
              type: ApprovalActionColor.approve,
              icon: Icons.check_rounded,
              onPressed: approveEnabled ? onApprove : null,
              fontSize: fontSize,
            ),
          ),
        ];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: buttons,
        );
      },
    );
  }
}

class IOS6ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final ApprovalActionColor type;
  final VoidCallback? onPressed;
  final double fontSize;

  const IOS6ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.type,
    this.onPressed,
    this.fontSize = 13.0,
  });

  @override
  State<IOS6ActionButton> createState() => _IOS6ActionButtonState();
}

class _IOS6ActionButtonState extends State<IOS6ActionButton> {
  bool _isPressed = false;

  List<Color> get _gradientColors {
    switch (widget.type) {
      case ApprovalActionColor.reject:
        return const [
          Color(0xFFFF6A5F),
          Color(0xFFF0483C),
          Color(0xFFD62B1F),
          Color(0xFFC11F14),
        ];

      case ApprovalActionColor.availability:
        return const [
          Color(0xFFFFCF4D),
          Color(0xFFF7A713),
          Color(0xFFEF9406),
          Color(0xFFE07D00),
        ];

      case ApprovalActionColor.approve:
        return const [
          Color(0xFF5FD06F),
          Color(0xFF2FB14A),
          Color(0xFF26A041),
          Color(0xFF1C8A36),
        ];
    }
  }

  Color get _borderColor {
    switch (widget.type) {
      case ApprovalActionColor.reject:
        return const Color(0xFF9C1409);
      case ApprovalActionColor.availability:
        return const Color(0xFFB56B00);
      case ApprovalActionColor.approve:
        return const Color(0xFF147029);
    }
  }

  Color get _bottomShadowColor {
    switch (widget.type) {
      case ApprovalActionColor.reject:
        return const Color(0xFF8F120A);
      case ApprovalActionColor.availability:
        return const Color(0xFFA86200);
      case ApprovalActionColor.approve:
        return const Color(0xFF126325);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.onPressed == null;
    final isSmallIcon = widget.fontSize < 12;

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 80),
      child: GestureDetector(
        onTapDown: isDisabled
            ? null
            : (_) {
                setState(() => _isPressed = true);
              },
        onTapUp: isDisabled
            ? null
            : (_) {
                setState(() => _isPressed = false);
                widget.onPressed?.call();
              },
        onTapCancel: () {
          setState(() => _isPressed = false);
        },
        child: Opacity(
          opacity: isDisabled ? 0.42 : 1,
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.50, 0.51, 1.0],
                colors: _gradientColors,
              ),
              border: Border.all(
                color: _borderColor,
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _bottomShadowColor,
                  offset: const Offset(0, 2),
                  blurRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.22),
                  offset: const Offset(0, 6),
                  blurRadius: 14,
                ),
              ],
            ),
            child: Stack(
              children: [
                // iOS 6 glossy top highlight
                Positioned(
                  top: 1,
                  left: 1,
                  right: 1,
                  height: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(17),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withOpacity(0.52),
                          Colors.white.withOpacity(0.10),
                        ],
                      ),
                    ),
                  ),
                ),

                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _GlossyIconChip(
                          icon: widget.icon,
                          isSmall: isSmallIcon,
                        ),
                        SizedBox(width: isSmallIcon ? 6 : 10),
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: widget.fontSize,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              shadows: const [
                                Shadow(
                                  color: Color.fromRGBO(0, 0, 0, 0.35),
                                  offset: Offset(0, -1),
                                  blurRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlossyIconChip extends StatelessWidget {
  final IconData icon;
  final bool isSmall;

  const _GlossyIconChip({
    required this.icon,
    this.isSmall = false,
  });

  @override
  Widget build(BuildContext context) {
    final double size = isSmall ? 22 : 31;
    final double iconSize = isSmall ? 14 : 20;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.60),
        ),
        gradient: RadialGradient(
          center: const Alignment(0, -0.45),
          colors: [
            Colors.white.withOpacity(0.42),
            Colors.white.withOpacity(0.10),
            Colors.black.withOpacity(0.14),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: iconSize,
        shadows: const [
          Shadow(
            color: Color.fromRGBO(0, 0, 0, 0.40),
            offset: Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
    );
  }
}
