import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_service.dart';
import '../../core/styles.dart';
import '../../main.dart';
import '../../shared/wallpaper_provider.dart';
import '../../shared/ui_provider.dart';
import '../../shared/widgets/skeuomorphic_navbar.dart';
import '../../warden/widgets/warden_widgets.dart';

class TemporaryStayAdminScreen extends StatefulWidget {
  final bool showBackButton;
  const TemporaryStayAdminScreen({super.key, this.showBackButton = false});

  @override
  State<TemporaryStayAdminScreen> createState() => _TemporaryStayAdminScreenState();
}

class _TemporaryStayAdminScreenState extends State<TemporaryStayAdminScreen>
    with SingleTickerProviderStateMixin {
  String _selectedStatus = 'pending';
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Theme colors matching Royal app palette (same as Activity Logs)
  static const Color _navy = Color(0xFF1B2B48);
  static const Color _gold = Color(0xFFD4AF37);

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
    try {
      final res = await ApiService.fetchAdminTemporaryStayRequests(status: _selectedStatus);
      if (!mounted) return;
      if (res['success'] == true) {
        final List<dynamic> list = res['requests'] ?? [];
        setState(() {
          _requests = list.map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Failed to load requests';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading requests: $e';
        _isLoading = false;
      });
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
              status == 'approved' ? Icons.check_circle : Icons.cancel,
              color: status == 'approved' ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${status == 'approved' ? 'Approve' : 'Reject'} Request',
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
                'Set request $requestId to ${status.toUpperCase()}?',
                style: GoogleFonts.inter(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: notesController,
                maxLines: 2,
                style: GoogleFonts.inter(fontSize: 13),
                decoration: InputDecoration(
                  labelText: status == 'rejected'
                      ? 'Rejection Reason (Required)'
                      : 'Admin Notes (Optional)',
                  labelStyle: GoogleFonts.inter(fontSize: 12),
                  hintText: status == 'rejected'
                      ? 'e.g. Invalid document'
                      : 'Optional notes',
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: status == 'approved' ? Colors.green.shade700 : Colors.red.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (status == 'rejected') {
                if (!formKey.currentState!.validate()) return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: Text(
              status == 'approved' ? 'Approve' : 'Reject',
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
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
      if (!mounted) return;
      if (res['success'] == true) {
        final rootContext = navigatorKey.currentContext;
        if (rootContext != null && rootContext.mounted) {
          try {
            ScaffoldMessenger.of(rootContext).showSnackBar(
              SnackBar(
                content: Text(
                  status == 'rejected'
                      ? 'Request $requestId rejected.'
                      : 'Request $requestId approved!',
                  style: GoogleFonts.inter(),
                ),
              ),
            );
          } catch (_) {}
        }
        _fetchRequests();
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Action failed';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  // ── Bottom sheet with full details ──────────────────────────────────────────
  void _showDetailSheet(Map<String, dynamic> req) {
    final status = req['status'] ?? 'pending';
    Color statusColor = const Color(0xFFF59E0B);
    if (status == 'approved') statusColor = Colors.green.shade700;
    if (status == 'rejected') statusColor = Colors.red.shade700;

    final docType = req['doc_type'] ?? 'ID';
    final docNum = req['doc_number'] ?? 'N/A';
    final roomCodeDisplay = (req['room_code'] != null &&
            req['room_code'].toString().isNotEmpty)
        ? req['room_code']
        : (req['room_no'] ?? 'N/A');
    final durationStr =
        '${req['duration_value'] ?? 1} ${req['duration_type'] ?? 'days'} '
        '(${req['from_date']} to ${req['to_date']})';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Sheet header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          req['request_id'] ?? 'TEMP-REQ',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: _navy,
                            letterSpacing: 0.3,
                          ),
                        ),
                        Text(
                          req['full_name'] ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _statusBadge(status, statusColor),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 20, color: _navy),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Scrollable details
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _sectionLabel('APPLICANT INFO'),
                    const SizedBox(height: 8),
                    _detailBox([
                      _detailRow('Name', req['full_name'] ?? 'N/A', Icons.person),
                      _detailRow('Email', req['email'] ?? 'N/A', Icons.email),
                      _detailRow('Phone', req['phone'] ?? 'N/A', Icons.phone),
                      _detailRow('Gender', req['gender'] ?? 'N/A', Icons.wc),
                    ]),
                    const SizedBox(height: 16),
                    _sectionLabel('STAY DETAILS'),
                    const SizedBox(height: 8),
                    _detailBox([
                      _detailRow('Hostel & Room', '${req['hostel_name']} - $roomCodeDisplay', Icons.hotel),
                      _detailRow('Room Type', req['room_type'] ?? 'N/A', Icons.meeting_room),
                      _detailRow('Duration', durationStr, Icons.calendar_month),
                      _detailRow('Purpose', req['institution_purpose'] ?? 'N/A', Icons.description),
                    ]),
                    const SizedBox(height: 16),
                    _sectionLabel('VERIFICATION & FEE'),
                    const SizedBox(height: 8),
                    _detailBox([
                      _detailRow('ID Type', '$docType: $docNum', Icons.badge),
                      _detailRow(
                        'Fee',
                        (req['amount'] != null &&
                                (double.tryParse(req['amount'].toString()) ?? 0) > 0)
                            ? '₹${(((double.tryParse(req['amount'].toString()) ?? 0) / 50.0).round() * 50)} (Annual/365 × days)'
                            : 'Calculated upon approval',
                        Icons.payments,
                      ),
                    ]),

                    // Document
                    if (req['doc_file_path'] != null &&
                        req['doc_file_path'].toString().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _sectionLabel('DOCUMENT'),
                      const SizedBox(height: 8),
                      _docViewerTile(req),
                    ],

                    // Admin notes
                    if (req['admin_notes'] != null &&
                        req['admin_notes'].toString().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: status == 'rejected'
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: status == 'rejected'
                                ? const Color(0xFFEF9A9A)
                                : const Color(0xFFADCCF7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              status == 'rejected'
                                  ? Icons.cancel_outlined
                                  : Icons.note,
                              color: status == 'rejected'
                                  ? Colors.red
                                  : Colors.blue,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${status == 'rejected' ? 'Rejection Reason' : 'Admin Notes'}: ${req['admin_notes']}',
                                style: GoogleFonts.inter(
                                  color: status == 'rejected'
                                      ? Colors.red.shade900
                                      : Colors.blue.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Approve / Reject buttons for pending
                    if (status == 'pending') ...[
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade700),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.cancel, size: 18),
                              label: Text('Reject',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _updateStatus(req['request_id'], 'rejected');
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade700,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.check_circle, size: 18),
                              label: Text('Approve',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14)),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _updateStatus(req['request_id'], 'approved');
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Compact list card ────────────────────────────────────────────────────────
  Widget _buildRequestCard(Map<String, dynamic> req, [bool isDark = false]) {
    final status = req['status'] ?? 'pending';
    Color statusColor = const Color(0xFFF59E0B);
    if (status == 'approved') statusColor = Colors.green.shade700;
    if (status == 'rejected') statusColor = Colors.red.shade700;

    final hasDoc = req['doc_file_path'] != null &&
        req['doc_file_path'].toString().isNotEmpty;

    return GestureDetector(
      onTap: () => _showDetailSheet(req),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.35 : 0.07),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.14) : const Color(0xFFE8EDF3),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Left accent line
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 14),
              // ID + name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req['request_id'] ?? 'TEMP-REQ',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        color: isDark ? const Color(0xFFD4AF37) : _navy,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      req['full_name'] ?? 'Unknown Applicant',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 11, color: isDark ? Colors.white54 : Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '${req['from_date'] ?? ''} → ${req['to_date'] ?? ''}',
                          style: GoogleFonts.inter(
                              fontSize: 10.5, color: isDark ? Colors.white60 : Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Right side: status + doc button
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _statusBadge(status, statusColor),
                  if (hasDoc) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final String fullUrl =
                            '${ApiService.baseUrl}${req['doc_file_path']}';
                        final Uri uri = Uri.parse(fullUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        } else {
                          await launchUrl(uri);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: _navy.withOpacity(0.2),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.open_in_new,
                                color: Colors.white, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              'View Doc',
                              style: GoogleFonts.outfit(
                                  fontSize: 10.5,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade400, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared helpers ───────────────────────────────────────────────────────────
  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.outfit(
            color: color, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 0.5),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
          color: _navy.withOpacity(0.65),
          letterSpacing: 0.9,
        ),
      );

  Widget _detailBox(List<Widget> rows) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: rows
              .expand((w) => [
                    w,
                    if (w != rows.last)
                      const Divider(height: 10, thickness: 0.5),
                  ])
              .toList(),
        ),
      );

  Widget _detailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: _gold),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label,
                style: GoogleFonts.inter(
                    color: const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          Text(' : ',
              style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12)),
          Expanded(
            child: Text(value,
                style: GoogleFonts.inter(
                    color: const Color(0xFF1E293B),
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _docViewerTile(Map<String, dynamic> req) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F4F8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC4D3E0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.picture_as_pdf, color: _navy, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Uploaded ID Verification File',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                          color: _navy)),
                  Text('File: ${req['doc_file_path']}',
                      style: GoogleFonts.inter(color: Colors.grey.shade600, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: Text('View Document',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final String fullUrl =
                    '${ApiService.baseUrl}${req['doc_file_path']}';
                final Uri uri = Uri.parse(fullUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  await launchUrl(uri);
                }
              },
            ),
          ],
        ),
      );

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperProvider>();
    final isDark = wallpaper.isDarkTheme;
    final canPop = Navigator.of(context).canPop();
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: SkeuomorphicNavBar(
        title: 'Temporary Stay Requests',
        onBack: widget.showBackButton
            ? () {
                final ui = Provider.of<UIProvider>(context, listen: false);
                if (isDesktop && ui.activeChatChannel != null) {
                  ui.setActiveChatChannel(null);
                } else if (canPop) {
                  Navigator.of(context).pop();
                }
              }
            : null,
        rightAction: IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
          onPressed: _fetchRequests,
          constraints: const BoxConstraints(),
          padding: EdgeInsets.zero,
        ),
      ),
      body: LinenGridBackground(
        child: Column(
          children: [
            // Status filter tabs — gold glossy active pill (Activity Logs style)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A).withOpacity(0.85) : Colors.white,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.14) : Colors.black12,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(child: _buildStatusTab('pending', 'Pending', Icons.hourglass_empty_outlined, isDark)),
                  Expanded(child: _buildStatusTab('approved', 'Approved', Icons.check_circle_outline, isDark)),
                  Expanded(child: _buildStatusTab('rejected', 'Rejected', Icons.cancel_outlined, isDark)),
                ],
              ),
            ),
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_errorMessage!,
                            style: GoogleFonts.inter(color: Colors.red.shade800, fontSize: 13))),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF1B2B48)))
                  : _requests.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 56, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                'No $_selectedStatus requests',
                                style: GoogleFonts.outfit(
                                    color: Colors.grey.shade500, fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            14,
                            8,
                            14,
                            MediaQuery.of(context).padding.bottom + 110,
                          ),
                          itemCount: _requests.length,
                          itemBuilder: (ctx, i) =>
                              _buildRequestCard(_requests[i], isDark),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // Activity-Logs-style gold glossy tab (matches the app's skeuomorphic design system)
  Widget _buildStatusTab(String status, String label, IconData icon, [bool isDark = false]) {
    final bool isSelected = _selectedStatus == status;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() => _selectedStatus = status);
          _fetchRequests();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? SkeuomorphicColors.goldGlossyGradient : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFB8962E).withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF3D2E0A) : (isDark ? Colors.white60 : Colors.grey),
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF3D2E0A) : (isDark ? Colors.white70 : Colors.grey),
                fontWeight: FontWeight.bold,
                fontSize: 13,
                fontFamily: 'Lato',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
