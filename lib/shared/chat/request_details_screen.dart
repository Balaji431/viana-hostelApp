import 'package:flutter/material.dart';
import '../../core/models/request_model.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../user_provider.dart';

class RequestDetailsScreen extends StatefulWidget {
  final RequestModel request;
  final bool canAction;

  const RequestDetailsScreen({
    super.key,
    required this.request,
    this.canAction = false,
  });

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  late String _status;
  bool _isLoading = false;
  String? _acknowledgingAction;

  @override
  void initState() {
    super.initState();
    _status = widget.request.status;
  }

  Future<void> _updateStatus(String newStatus, {String? reason}) async {
    setState(() => _isLoading = true);
    final userProvider = context.read<UserProvider>();
    final wardenId = userProvider.dbId ?? 0;
    
    final response = await ApiService.updateServiceRequestStatus(
      widget.request.customId, 
      newStatus,
      wardenId,
      reason: reason,
    );
    setState(() => _isLoading = false);

    if (response['success'] == true) {
      if (!mounted) return;
      setState(() => _status = newStatus);
      
      String displayMsg = newStatus == 'fixed' ? 'Marked as fixed' : 'Request $newStatus successfully';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayMsg), backgroundColor: Colors.green),
      );
      
      // Delay pop to let user see success
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: ${response['message']}')),
      );
    }
  }

  void _showRejectionDialog() {
    final TextEditingController reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reason for Rejection', style: TextStyle(fontFamily: 'Lato', fontWeight: FontWeight.bold)),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: 'Enter reason here...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason')),
                );
                return;
              }
              Navigator.pop(context);
              _updateStatus('rejected', reason: reason);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _acknowledgeRequest(bool isWorking) async {
    setState(() => _acknowledgingAction = isWorking ? 'yes' : 'no');
    final userProvider = context.read<UserProvider>();
    final studentId = userProvider.dbId ?? 0;
    
    final response = await ApiService.acknowledgeServiceRequest(
      widget.request.customId,
      studentId,
      isWorking,
    );
    setState(() => _acknowledgingAction = null);

    if (response['success'] == true) {
      if (!mounted) return;
      setState(() => _status = response['status'] ?? (isWorking ? 'completed' : 'reopened'));
      
      String displayMsg = isWorking ? 'Thank you! Issue marked as resolved.' : 'Issue reported as not working. Request reopened.';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(displayMsg), backgroundColor: isWorking ? Colors.green : const Color(0xFF1E88E5)),
      );
      
      if (Navigator.canPop(context)) {
        Navigator.pop(context, true);
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${response['message']}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if we are in a modal or a full screen
    final isModal = ModalRoute.of(context)?.isCurrent == false || Navigator.canPop(context);

    Widget content = Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6F1), // Cream background from image
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle for modal feel
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Block
          _buildHeader(),
          
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(25, 10, 25, 30),
              child: Column(
                children: [
                  // Submitted Date Section
                  _buildSectionBox(
                    label: 'Submitted',
                    value: '${DateFormat('d MMMM yyyy').format(widget.request.createdAt)} at ${DateFormat('hh:mm a').format(widget.request.createdAt)}',
                  ),
                  const SizedBox(height: 20),
                  
                  // Request Details Section
                  _buildRequestDetailsSection(),
                  const SizedBox(height: 20),
                  
                  // Location Section
                  _buildSectionBox(
                    label: 'Location',
                    value: widget.request.roomNumber,
                  ),
                  const SizedBox(height: 20),
                  
                  // Status Timeline Section
                  _buildStatusTimeline(),
                  const SizedBox(height: 30),
                  
                  // Action Buttons for Staff or Student
                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (isModal) {
      return Material(
        color: Colors.transparent,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          child: content,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(25, 30, 25, 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.request.requestType,
                  style: const TextStyle(
                    fontFamily: 'Lato',
                    fontSize: 24, // Reduced from 32
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B2B48),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.request.customId,
                  style: const TextStyle(
                    color: Color(0xFF8E99A5),
                    fontSize: 13, // Reduced from 15
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusBadge(_status),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color startColor;
    Color endColor;
    final s = status.toLowerCase();
    final dept = widget.request.department.toLowerCase();

    if (s == 'completed' || (s == 'approved' && dept != 'maintenance')) {
      startColor = const Color(0xFF2E7D32);
      endColor = const Color(0xFF1B5E20);
    } else if (s == 'rejected') {
      startColor = const Color(0xFFEF5350);
      endColor = const Color(0xFFD32F2F);
    } else if (s == 'fixed' || s == 'verification' || s == 'resolved') {
      // Blue for Verification / Marked Fixed by maintenance
      startColor = const Color(0xFF1E88E5);
      endColor = const Color(0xFF1565C0);
    } else if (s == 'reopened') {
      // Deep Blue for Reopened / Not Fixed
      startColor = const Color(0xFF0288D1);
      endColor = const Color(0xFF01579B);
    } else {
      // Orange for Pending / In Progress
      startColor = const Color(0xFFFF9800);
      endColor = const Color(0xFFFF8000);
    }

    String displayText;
    if (s == 'fixed' || s == 'verification' || s == 'resolved') {
      displayText = 'VERIFICATION';
    } else if (s == 'reopened') {
      displayText = 'NOT FIXED';
    } else if (s == 'completed') {
      displayText = 'COMPLETED';
    } else if (s == 'approved' && dept == 'maintenance') {
      displayText = 'PENDING';
    } else {
      displayText = s.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [startColor, endColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: startColor.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        displayText,
        style: const TextStyle(
          color: Colors.white, 
          fontSize: 12, // Reduced from 14
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSectionBox({required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE6DD).withOpacity(0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDED9CD), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label, 
            style: const TextStyle(
              fontSize: 11, // Reduced from 12
              color: Color(0xFF8E99A5), 
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )
          ),
          const SizedBox(height: 8),
          Text(
            value, 
            style: const TextStyle(
              fontSize: 17, // Reduced from 20
              fontWeight: FontWeight.bold, 
              color: Color(0xFF1B2B48),
              height: 1.2,
            )
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getDisplayConfig() {
    String type = widget.request.requestType.toLowerCase();
    String dept = widget.request.department.toLowerCase();

    if (type.contains('permission')) {
      return {
        'depLabel': 'Request Date',
        'purposeLabel': 'Respected Purpose',
        'showDep': true,
        'showRet': false,
        'showDest': false,
      };
    } else if (type.contains('complaint')) {
      return {
        'purposeLabel': 'Nature of Complaint',
        'showDep': false,
        'showRet': false,
        'showDest': false,
      };
    } else if (type.contains('home') || type.contains('hostel leave')) {
      return {
        'depLabel': 'Departure Date',
        'retLabel': 'Return Date',
        'destLabel': 'Destination',
        'purposeLabel': 'Purpose of Leave',
        'showDep': true,
        'showRet': true,
        'showDest': true,
      };
    } else if (type.contains('late entry')) {
      return {
        'depLabel': 'Date of Late Entry',
        'destLabel': 'Expected Return Time',
        'purposeLabel': 'Reason for Late Entry',
        'showDep': true,
        'showRet': false,
        'showDest': true,
      };
    } else if (type.contains('guest')) {
      return {
        'depLabel': 'Arrival Date',
        'retLabel': 'Departure Date',
        'destLabel': 'Guest Name',
        'purposeLabel': 'Relationship',
        'showDep': true,
        'showRet': true,
        'showDest': true,
      };
    } else if (dept == 'maintenance' || type.contains('plumbing') || type.contains('electrical') || type.contains('internet') || type.contains('repair')) {
      return {
        'purposeLabel': 'Problem Description',
        'showDep': false,
        'showRet': false,
        'showDest': false,
      };
    } else if (type.contains('room')) {
      return {
        'destLabel': 'Preferred Room/Type',
        'purposeLabel': 'Reason for Change',
        'showDep': false,
        'showRet': false,
        'showDest': true,
      };
    } else if (type.contains('lost') || type.contains('theft')) {
      return {
        'depLabel': 'Date of Incident',
        'destLabel': 'Last Seen/Location',
        'purposeLabel': 'Item Description',
        'showDep': true,
        'showRet': false,
        'showDest': true,
      };
    } else if (dept == 'security') {
       return {
        'destLabel': 'Location',
        'purposeLabel': 'Incident Report',
        'showDep': false,
        'showRet': false,
        'showDest': true,
      };
    }

    // Default Fallback
    return {
      'depLabel': 'Departure',
      'retLabel': 'Return',
      'destLabel': 'Destination',
      'purposeLabel': 'Purpose',
      'showDep': widget.request.fromDate != null,
      'showRet': widget.request.toDate != null,
      'showDest': widget.request.destination != null,
    };
  }

  Widget _buildRequestDetailsSection() {
    final config = _getDisplayConfig();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE6DD).withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDED9CD), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Request Details', 
            style: TextStyle(
              fontSize: 11, // Reduced from 12
              color: Color(0xFF8E99A5), 
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )
          ),
          const SizedBox(height: 15),
          
          if (config['showDep'] == true) ...[
            _buildDetailRow(config['depLabel'], widget.request.fromDate != null ? DateFormat('d MMM yyyy').format(widget.request.fromDate!) : 'N/A'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFDED9CD)),
            ),
          ],

          if (config['showRet'] == true) ...[
            _buildDetailRow(config['retLabel'], widget.request.toDate != null ? DateFormat('d MMM yyyy').format(widget.request.toDate!) : 'N/A'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFDED9CD)),
            ),
          ],

          if (config['showDest'] == true) ...[
            _buildDetailRow(config['destLabel'], widget.request.destination ?? 'N/A'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFDED9CD)),
            ),
          ],
          
          _buildDetailRow(config['purposeLabel'], widget.request.message),

          if (widget.request.attachment != null && widget.request.attachment!.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: Color(0xFFDED9CD)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Attachment',
                  style: TextStyle(
                    color: Color(0xFF8E99A5),
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAttachmentDialog,
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 16, color: Colors.white),
                  label: const Text('View Document', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B2B48),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showAttachmentDialog() {
    if (widget.request.attachment == null || widget.request.attachment!.isEmpty) return;
    
    String fullUrl = widget.request.attachment!;
    if (!fullUrl.startsWith('http')) {
      fullUrl = ApiService.baseUrl + (fullUrl.startsWith('/') ? fullUrl.substring(1) : fullUrl);
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Appliance / Issue Photo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1B2B48)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    fullUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Unable to load photo attachment', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label, 
            style: const TextStyle(
              color: Color(0xFF8E99A5), 
              fontWeight: FontWeight.w500,
              fontSize: 14, // Reduced from 15
            )
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: Text(
            value, 
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.bold, 
              color: Color(0xFF1B2B48),
              fontSize: 14, // Reduced from 16
            )
          ),
        ),
      ],
    );
  }

  Widget _buildStatusTimeline() {
    if (widget.request.department.toLowerCase() != 'maintenance') {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFEBE6DD).withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDED9CD), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status Timeline', 
            style: TextStyle(
              fontSize: 12, 
              color: Color(0xFF8E99A5), 
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )
          ),
          const SizedBox(height: 20),
          _timelineItem('Submitted', DateFormat('M/d/yyyy').format(widget.request.createdAt), true, isLast: false),
          _timelineItem('In Progress', (_status == 'pending') ? 'Waiting for staff' : 'Staff is working', _status != 'pending', isLast: false),
          _timelineItem(
            'Verification', 
            (_status == 'fixed' || _status == 'verification')
                ? 'Staff marked as fixed'
                : (_status == 'reopened' ? 'Reopened (Student reported not fixed)' : (_status == 'completed' ? 'Verified & resolved' : 'Waiting for resolution')), 
            _status == 'fixed' || _status == 'verification' || _status == 'reopened' || _status == 'completed', 
            isLast: false,
            isBlue: _status == 'fixed' || _status == 'verification' || _status == 'reopened',
          ),
          _timelineItem('Completed', _status == 'completed' ? 'Request finalized' : 'Waiting for student confirmation', _status == 'completed', isLast: true),
        ],
      ),
    );
  }

  Widget _timelineItem(String title, String sub, bool isDone, {required bool isLast, bool isBlue = false}) {
    final Color activeColor = isBlue ? const Color(0xFF1E88E5) : const Color(0xFF4CAF50);
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isDone ? activeColor : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDone ? activeColor : const Color(0xFFDED9CD),
                    width: 2,
                  ),
                  boxShadow: isDone ? [BoxShadow(color: activeColor.withOpacity(0.25), blurRadius: 4, spreadRadius: 1)] : null,
                ),
                child: isDone ? const Icon(Icons.check, color: Colors.white, size: 12) : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isDone ? activeColor.withOpacity(0.3) : const Color(0xFFDED9CD),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 15),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title, 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: isDone ? const Color(0xFF1B2B48) : const Color(0xFF8E99A5),
                    fontSize: 14, // Reduced from 16
                  )
                ),
                const SizedBox(height: 4),
                Text(
                  sub, 
                  style: const TextStyle(
                    fontSize: 12, // Reduced from 13
                    color: Color(0xFF8E99A5),
                    fontWeight: FontWeight.w500,
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final userProvider = context.read<UserProvider>();
    final reqDept = widget.request.department.toLowerCase();
    
    // Authorization Check for Staff
    bool isAuthorizedStaff = false;
    final staffRole = userProvider.role.toString().split('.').last.toLowerCase();
    
    if (userProvider.role != UserRole.student) {
      if (staffRole == 'admin') {
        isAuthorizedStaff = true;
      } else if (staffRole == reqDept || (staffRole == 'maintenance' && reqDept == 'maintenannce')) {
        isAuthorizedStaff = true;
      } else if (staffRole == 'warden' && (reqDept == 'warden' || reqDept == 'parent_warden')) {
        isAuthorizedStaff = true;
      } else if (staffRole == 'maintenance' && (reqDept == 'maintenance' || reqDept == 'plumber' || reqDept == 'electricity')) {
        isAuthorizedStaff = true;
      } else if (widget.request.requestType.toLowerCase().contains('room') && staffRole == 'warden') {
        isAuthorizedStaff = true;
      }
    }

    bool isStudent = userProvider.role == UserRole.student || !isAuthorizedStaff;

    // 1. Staff Actions
    if (widget.canAction && isAuthorizedStaff) {
      if (reqDept == 'maintenance' || reqDept == 'maintenannce') {
        if (_status == 'pending' || _status == 'approved' || _status == 'reopened' || _status == 'in_progress') {
          return Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isLoading ? null : () => _updateStatus('fixed'),
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: SkeuomorphicColors.goldGlossyGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Center(
                      child: _isLoading ? const CircularProgressIndicator() : const Text('MARK AS FIXED', style: TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      } else {
        // Other departments: Approve/Reject
        if (_status == 'pending') {
          return Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _isLoading ? null : _showRejectionDialog,
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Center(
                      child: _isLoading ? const CircularProgressIndicator() : const Text('Reject', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: GestureDetector(
                  onTap: _isLoading ? null : () => _updateStatus('approved'),
                  child: Container(
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: SkeuomorphicColors.goldGlossyGradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: const Text('Approve', style: TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      }
    }

    // 2. Student Actions / Student View Verification Buttons
    if (isStudent) {
      final cleanStatus = _status.toLowerCase();
      if (cleanStatus == 'fixed' || cleanStatus == 'verification' || cleanStatus == 'resolved') {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2D6BE)),
          ),
          child: Column(
            children: [
              const Text(
                'PLEASE VERIFY & ACKNOWLEDGE RESOLUTION',
                style: TextStyle(color: Color(0xFF1B2B48), fontWeight: FontWeight.bold, letterSpacing: 1.0, fontSize: 11),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Left Button: No, it's not working (Yellow/Amber Card)
                  Expanded(
                    child: GestureDetector(
                      onTap: (_isLoading || _acknowledgingAction != null) ? null : () => _acknowledgeRequest(false),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFC107), // Amber/Yellow Card
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                          ],
                        ),
                        child: Center(
                          child: _acknowledgingAction == 'no'
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Text(
                                  "No, it's not working",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right Button: Yes, it was fixed (Green Card)
                  Expanded(
                    child: GestureDetector(
                      onTap: (_isLoading || _acknowledgingAction != null) ? null : () => _acknowledgeRequest(true),
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50), // Green Card
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                          ],
                        ),
                        child: Center(
                          child: _acknowledgingAction == 'yes'
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text(
                                  "Yes, it was fixed",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      } else if (cleanStatus == 'completed') {
        return Container(
          width: double.infinity,
          height: 55,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(colors: [Color(0xFF66BB6A), Color(0xFF43A047)]),
          ),
          child: const Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text('COMPLETED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        );
      } else if (cleanStatus == 'approved' && (reqDept == 'warden' || reqDept == 'parent_warden' || reqDept == 'security')) {
        return _buildCloseButton();
      } else if (cleanStatus == 'pending' || cleanStatus == 'approved' || cleanStatus == 'reopened' || cleanStatus == 'in_progress') {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time, color: Colors.orange, size: 20),
              SizedBox(width: 10),
              Text('REQUEST PENDING...', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      }
    }

    // Default Close Button
    return _buildCloseButton();
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: SkeuomorphicColors.goldGlossyGradient,
        ),
        child: const Center(
          child: Text('Close', style: TextStyle(color: Color(0xFF291E1A), fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
