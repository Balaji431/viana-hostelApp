import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/api_service.dart';
import '../../shared/user_provider.dart';

class WardenTemporaryStayDialog extends StatefulWidget {
  final String? wardenId;
  final String? wardenName;

  const WardenTemporaryStayDialog({
    super.key,
    this.wardenId,
    this.wardenName,
  });

  @override
  State<WardenTemporaryStayDialog> createState() => _WardenTemporaryStayDialogState();
}

class _WardenTemporaryStayDialogState extends State<WardenTemporaryStayDialog> {
  String _selectedStatus = 'pending';
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic> _counts = {};
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _timer;

  static const Color _navy = Color(0xFF1B2B48);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _fetchRequests();
    // Auto-refresh timer every 10 seconds
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _fetchRequests(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRequests({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = Provider.of<UserProvider>(context, listen: false);
      final wId = widget.wardenId ?? user.dbId?.toString() ?? user.username;
      final wName = widget.wardenName ?? user.userName;

      final res = await ApiService.fetchAdminTemporaryStayRequests(
        status: _selectedStatus,
        wardenId: wId,
        wardenName: wName,
      );

      if (mounted) {
        if (res['success'] == true) {
          final List<dynamic> list = res['requests'] ?? [];
          setState(() {
            _requests = list.map((e) => Map<String, dynamic>.from(e)).toList();
            _counts = Map<String, dynamic>.from(res['counts'] ?? {});
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = res['message'] ?? 'Failed to load requests';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading requests: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateStatus(String requestId, String status) async {
    final notesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              status == 'approved' ? Icons.check_circle_outline : Icons.cancel_outlined,
              color: status == 'approved' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status == 'approved' ? 'Approve & Hold Room (24h)' : 'Reject Application',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16, color: _navy),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status == 'approved'
                    ? 'Approve request $requestId? The room will be held for 24 hours allowing the student to pay via their wallet.'
                    : 'Reject request $requestId? Please specify the reason below.',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: notesController,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 13),
                decoration: InputDecoration(
                  labelText: status == 'rejected' ? 'Rejection Reason (Required)' : 'Warden Notes (Optional)',
                  labelStyle: GoogleFonts.inter(fontSize: 12),
                  hintText: status == 'rejected' ? 'e.g. Ineligible / Invalid ID' : 'Optional notes',
                  hintStyle: GoogleFonts.inter(fontSize: 12),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (status == 'rejected' && (v == null || v.trim().isEmpty)) {
                    return 'Please enter a rejection reason';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'approved' ? Colors.green.shade700 : Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: Text(status == 'approved' ? 'Confirm Approval' : 'Confirm Rejection'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final res = await ApiService.updateTemporaryStayStatus(
        requestId: requestId,
        status: status,
        adminNotes: notesController.text.trim(),
      );

      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                status == 'approved'
                    ? 'Request approved! Room held for 24 hours for student payment.'
                    : 'Request rejected.',
              ),
              backgroundColor: status == 'approved' ? Colors.green.shade800 : Colors.red.shade800,
            ),
          );
          _fetchRequests();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Failed to update request'), backgroundColor: Colors.red),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatHoldCountdown(int remainingSeconds) {
    if (remainingSeconds <= 0) return 'Expired';
    final hours = remainingSeconds ~/ 3600;
    final minutes = (remainingSeconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m left to pay';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 36,
        vertical: isMobile ? 16 : 28,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: isMobile ? double.infinity : 760,
        height: 650,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            _buildHeader(context),
            // Status Tabs Bar
            _buildStatusTabs(),
            // Requests Content List
            Expanded(
              child: _isLoading && _requests.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: _navy))
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _requests.isEmpty
                          ? _buildEmptyView()
                          : _buildRequestsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _gold.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.hotel_rounded, color: _gold, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Temporary Stay Requests',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  'Manage short-term bookings under your floors/hostel',
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70, size: 20),
            onPressed: () => _fetchRequests(),
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTabs() {
    final pendingCount = _counts['pending_count'] ?? 0;
    final approvedCount = _counts['approved_count'] ?? 0;
    final allocatedCount = _counts['allocated_count'] ?? 0;
    final rejectedCount = _counts['rejected_count'] ?? 0;

    final tabs = [
      {'status': 'pending', 'label': 'Pending', 'count': pendingCount, 'color': const Color(0xFFE65100)},
      {'status': 'approved', 'label': 'Approved (Hold 24h)', 'count': approvedCount, 'color': const Color(0xFF0288D1)},
      {'status': 'allocated', 'label': 'Allocated (Paid)', 'count': allocatedCount, 'color': const Color(0xFF2E7D32)},
      {'status': 'rejected', 'label': 'Rejected / Timed Out', 'count': rejectedCount, 'color': const Color(0xFFC62828)},
    ];

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((t) {
            final isSelected = _selectedStatus == t['status'];
            final color = t['color'] as Color;
            final count = t['count'] as int;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  setState(() => _selectedStatus = t['status'] as String);
                  _fetchRequests();
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? _navy : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? _navy : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        t['label'] as String,
                        style: GoogleFonts.outfit(
                          color: isSelected ? Colors.white : Colors.grey.shade800,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isSelected ? _gold : color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: GoogleFonts.outfit(
                              color: isSelected ? _navy : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRequestsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final req = _requests[index];
        return _buildRequestCard(req);
      },
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    final status = (req['status'] ?? 'pending').toString().toLowerCase();
    final paymentStatus = (req['payment_status'] ?? 'unpaid').toString().toLowerCase();
    final amount = double.tryParse(req['amount']?.toString() ?? '0') ?? 0.0;
    final holdSeconds = int.tryParse(req['hold_remaining_seconds']?.toString() ?? '0') ?? 0;

    Color statusColor;
    String statusLabel;
    if (status == 'allocated' || paymentStatus == 'paid') {
      statusColor = const Color(0xFF2E7D32);
      statusLabel = 'Allocated (Paid)';
    } else if (status == 'approved') {
      statusColor = const Color(0xFF0288D1);
      statusLabel = 'Approved (Hold 24h)';
    } else if (status == 'timed_out') {
      statusColor = const Color(0xFFC62828);
      statusLabel = 'Hold Expired';
    } else if (status == 'rejected') {
      statusColor = const Color(0xFFC62828);
      statusLabel = 'Rejected';
    } else {
      statusColor = const Color(0xFFE65100);
      statusLabel = 'Pending Review';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Name, Status Badge, Amount
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _navy.withOpacity(0.08),
                  child: Text(
                    (req['full_name'] ?? 'G')[0].toUpperCase(),
                    style: GoogleFonts.outfit(color: _navy, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req['full_name'] ?? 'Guest Applicant',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15, color: _navy),
                      ),
                      Text(
                        '${req['gender'] ?? 'Gender'} • ${req['institution_purpose'] ?? 'Short Stay'}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        statusLabel,
                        style: GoogleFonts.outfit(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${amount.toStringAsFixed(2)}',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),

            // Room & Dates Info
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.apartment,
                    title: 'Hostel & Room',
                    value: '${req['hostel_name'] ?? ''} • ${req['room_no'] ?? req['room_code'] ?? ''}',
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.date_range,
                    title: 'Duration',
                    value: '${req['from_date'] ?? ''} to ${req['to_date'] ?? ''} (${req['duration_value'] ?? 1} ${req['duration_type'] ?? 'days'})',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Contact Info & Hold Timer
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    icon: Icons.email_outlined,
                    title: 'Contact',
                    value: '${req['email'] ?? ''} | ${req['phone'] ?? ''}',
                  ),
                ),
                if (status == 'approved' && holdSeconds > 0)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFFB74D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 14, color: Color(0xFFE65100)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formatHoldCountdown(holdSeconds),
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFE65100),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            if (req['admin_notes'] != null && req['admin_notes'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Notes: ${req['admin_notes']}',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade700),
                ),
              ),
            ],

            // Action Buttons for Pending Requests
            if (status == 'pending') ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject'),
                    onPressed: () => _updateStatus(req['request_id'], 'rejected'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Accept & Hold (24h)'),
                    onPressed: () => _updateStatus(req['request_id'], 'approved'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem({required IconData icon, required String title, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 10, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
              ),
              Text(
                value,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No $_selectedStatus requests found',
            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            'New applications under your rooms will appear here.',
            style: GoogleFonts.inter(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 44, color: Colors.red),
          const SizedBox(height: 10),
          Text(_errorMessage!, style: GoogleFonts.inter(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: () => _fetchRequests(),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }
}
